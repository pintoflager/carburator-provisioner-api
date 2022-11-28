#!/usr/bin/env bash

carburator print terminal info "Invoking Hetzner's DNS API provisioner..."

resource="zone"
output="$PROVISIONER_PROVIDER_PATH/${DOMAIN_FQDN}_${resource}.json"
existing_zones="$PROVISIONER_PROVIDER_PATH/${DOMAIN_PROVIDER_NAME}_zones.json"


###
# Get API token from secrets or bail early.
#
token=$(carburator get secret "$DOMAIN_PROVIDER_SECRET_0" --user root); exitcode=$?

if [[ -z $token || $exitcode -gt 0 ]]; then
	carburator print terminal error \
		"Could not load Hetzner DNS API token from secret. Unable to proceed"
	exit 120
fi

create_zone() {
    curl -X "POST" "https://dns.hetzner.com/api/v1/zones" \
        -s \
        -H 'Content-Type: application/json' \
        -H "Auth-API-Token: $1" \
        -d $'{"name": "'"$2"'","ttl": 86400}' > "$3"

    # Assuming create failed as we cant load a zone id.
	if ! carburator has json zone.id --path "$3"; then
        carburator print terminal error "Create zone '$2' failed."
		rm -f "$3"; return 1
	fi
}

destroy_zone() {
    curl -X "DELETE" "https://dns.hetzner.com/api/v1/zones/$2" \
        -s \
        -H "Auth-API-Token: $1" &> /dev/null
}

find_zones() {
    curl "https://dns.hetzner.com/api/v1/zones?name=$2" \
        -s \
        -H "Auth-API-Token: $1" > "$3"
}

get_zone() {
    curl "https://dns.hetzner.com/api/v1/zones/$2" \
        -s \
        -H "Auth-API-Token: $1" \
        -H 'Content-Type: application/json; charset=utf-8' > "$3"
}

###
# Only thing between the api call and a complete disaster is you.
# Make sure to check existence of the output file, verify that the zone in
# it exists and if so, never ever, never never destroy the zone.
#
# If output file is missing or does not contain zone ID we can only assume
# this is new project or we have failure of previous intent on our hands.
#
if [[ -e $output ]]; then
    zone_id=$(carburator get json zone.id string --path "$output")

    # Same zone ID on localhost and remote -- nothing to do.
    if [[ -n $zone_id ]] && get_zone "$token" "$zone_id" "$output"; then
        verify_id=$(carburator get json zone.id string --path "$output")

        # Zone ID's before and after query match.
        if [[ $zone_id == "$verify_id" ]]; then exit; fi
    fi
fi

carburator print terminal attention \
    "DNS zone file for $DOMAIN_FQDN not found, searching existing zones..."

# Output file doesn't exist or zone verify failed.
find_zones "$token" "$DOMAIN_FQDN" "$existing_zones"

# No exitsting zones matching our fully qualified domain name (FQDN)
zones=$(carburator get json zones array --path "$existing_zones") || exit 120

if [[ -z $zones || $(wc -l <<< "$zones") -eq 0 ]]; then
    rm -f "$existing_zones"
    
    if create_zone "$token" "$DOMAIN_FQDN" "$output"; then
        carburator print terminal success \
            "Hetzner DNS zone for $DOMAIN_FQDN created."
        exit
    else
        exit 110
    fi
fi

# Only one zone matches
if [[ $(wc -l <<< "$zones") -eq 1 ]]; then
    carburator print terminal warn \
        "Duplicate DNS zone for $DOMAIN_FQDN found from Hetzner DNS."

    carburator prompt yes-no \
        "Should we destroy existing zone and create a new one, or use the found zone?" \
        --yes-val "Destroy old zone and create new one" \
        --no-val "Keep the found zone with it's records"; exitcode=$?

    id=$(carburator get json zones.0.id string --path "$existing_zones") || exit 120

    if [[ $exitcode -eq 0 ]]; then
        destroy_zone "$token" "$id"
        if create_zone "$token" "$DOMAIN_FQDN" "$output"; then
            rm -f "$existing_zones"
            carburator print terminal success \
                "Hetzner DNS zone for $DOMAIN_FQDN created."
            exit
        else
            exit 110
        fi
    else
        get_zone "$token" "$id" "$output"
        rm -f "$existing_zones"
        exit
    fi
fi

# Still here, more than one (1) matching zones, how is that even possible, I don't
# know, but it seems to have happened.
carburator print terminal error \
    "Multiple DNS zones match to $DOMAIN_FQDN, Unable to proceed with zone \
registration. Use your human touch with existing DNS zones before trying again."

exit 120
