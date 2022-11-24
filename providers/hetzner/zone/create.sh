#!/usr/bin/env bash

carburator fn echo info "Invoking Hetzner's DNS API provisioner..."

resource="zone"
output="$PROVISIONER_PROVIDER_PATH/${DOMAIN_FQDN}_${resource}.json"
existing_zones="$PROVISIONER_PROVIDER_PATH/${DOMAIN_PROVIDER_NAME}_zones.json"


###
# Get API token from secrets or bail early.
#
token=$(carburator get secret "$DOMAIN_PROVIDER_SECRET_0" --user root); exitcode=$?

if [[ -z $token || $exitcode -gt 0 ]]; then
	carburator fn echo error \
		"Could not load Hetzner DNS API token from secret. Unable to proceed"
	exit 120
fi

create_zone() {
    curl -X "POST" "https://dns.hetzner.com/api/v1/zones" \
        -s \
        -H 'Content-Type: application/json' \
        -H "Auth-API-Token: $1" \
        -d $'{"name": "'"$2"'","ttl": 86400}' > "$3"

    # Assuming create failed as we don't have a zone.
	if [[ $(jq -rc ".zone | length" "$output") -eq 0 ]]; then
		rm -f "$3"; exit 110
	fi
}

destroy_zone() {
    curl -X "DELETE" "https://dns.hetzner.com/api/v1/zones/$1" \
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

verify_zone() {
    local id;

    id=$(curl "https://dns.hetzner.com/api/v1/zones/$1" \
        -s \
        -H "Auth-API-Token: $token" \
        -H 'Content-Type: application/json; charset=utf-8' | jq -rc ".zone.id")

    if [[ $id != "$1" ]]; then return 1; fi
}

###
# Only thing between the api calls and complete fuckup is you.
# Make sure to check existence of the output file, verify that the zone in
# it exists and if so, never ever, never never destroy the zone.
#
# If output file is missing or does not contain zone ID we can only assume
# this is new project or we have failure of previous intent on our hands.
#
if [[ -e $output ]]; then
    zone_id=$(jq -rc ".zone.id")

    # Same zone ID on localhost and remote -- nothing to do.
    if [[ $zone_id != null ]]; then
        verify_zone "$zone_id" && exit
    fi
fi

carburator fn echo attention \
    "DNS zone file for $DOMAIN_FQDN not found, searching existing zones..."

# Output file doesn't exist or zone verify failed.
find_zones "$token" "$DOMAIN_FQDN" "$existing_zones"

# No exitsting zones matching our fully qualified domain name (FQDN)
if [[ $(jq -rc '.zones | length' "$existing_zones") -eq 0 ]]; then
    rm -f "$existing_zones"
    create_zone "$token" "$DOMAIN_FQDN" "$output" && exit
fi

# Only one zone matches
if [[ $(jq -rc '.zones | length' "$existing_zones") -eq 1 ]]; then
    carburator fn echo warn \
        "Duplicate DNS zone for $DOMAIN_FQDN found from Hetzner DNS."

    carburator prompt yes-no \
        "Should we destroy existing zone and create a new one, or use the found zone?" \
        --yes-val "Destroy old zone and create new one" \
        --no-val "Keep the found zone with it's records"; exitcode=$?

    if [[ $exitcode -eq 0 ]]; then
        destroy_zone "$token"
        create_zone "$token" "$DOMAIN_FQDN" "$output"
        rm -f "$existing_zones"
        exit
    else
        get_zone "$token" "$(jq -rc '.zones[0].id' "$existing_zones")" "$output"
        rm -f "$existing_zones"
        exit
    fi
fi

# Still here, more than one (1) matching zones, how is that even possible, I don't
# know, but it seems to have happened.
carburator fn echo error \
    "Multiple DNS zones match to $DOMAIN_FQDN, Unable to proceed with zone \
registration. Use your human touch with existing DNS zones before trying again."

exit 120
