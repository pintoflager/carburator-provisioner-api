#!/usr/bin/env bash

resource="zone"
output="$PROVISIONER_PROVIDER_PATH/${DOMAIN_FQDN}_${resource}.json"

###
# Get API token from secrets or bail early.
#
token=$(carburator get secret "$PROVIDER_SECRET_0" --user root); exitcode=$?

if [[ -z $token || $exitcode -gt 0 ]]; then
	carburator fn echo error \
		"Could not load Hetzner DNS API token from secret. Unable to proceed"
	exit 120
fi

provisioner_call() {
    curl -X "POST" "https://dns.hetzner.com/api/v1/zones" \
        -s \
        -H 'Content-Type: application/json' \
        -H "Auth-API-Token: $1" \
        -d $'{"name": "'"$2"'","ttl": 86400}' > "$1"

    # Assuming create failed as output doesn't have zone object.
	if [[ ! -s "$1" ]]; then
		rm -f "$1"; exit 110
	fi
}

# Analyze output json to determine if zone was registered OK.
if provisioner_call "$token" "$DOMAIN_FQDN" "$output"; then
	# If we have zone but not the id we might have a duplicate zone.
    zone_id=$(jq -rc ".zone.id" "$output")

	if [[ -z $zone_id  ]]; then
        carburator fn echo warn \
            "DNS zone id came back empty, try searching for a duplicate.."

        extzone_id=$(curl "https://dns.hetzner.com/api/v1/zones?name=$DOMAIN_FQDN" \
            -s \
            -H "Auth-API-Token: $token" | \
            jq -rc '.zones[].id')

        # Existing DNS zone was found from hetzner, delete it and try again.                                                                                                                
        if [[ -n $extzone_id ]]; then
            carburator fn echo success \
                "Duplicate DNS zone found, deleting it and trying again..."

            curl -X "DELETE" "https://dns.hetzner.com/api/v1/zones/$extzone_id" \
                -s \
                -H "Auth-API-Token: $token" &> /dev/null
            
            # Try again
            if ! provisioner_call "$token" "$DOMAIN_FQDN" "$output"; then
                exit 120
            fi
        else
            carburator fn echo error \
                "We had problems with creating new DNS zone with API. Debug."
            exit 120
        fi
    fi
fi
