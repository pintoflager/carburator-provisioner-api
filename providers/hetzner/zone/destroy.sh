#!/usr/bin/env bash

resource="zone"
output="$PROVISIONER_PROVIDER_PATH/${DOMAIN_FQDN}_${resource}.json"
existing_zones="$PROVISIONER_PROVIDER_PATH/${DOMAIN_PROVIDER_NAME}_zones.json"
id=$(carburator get json zones.0.id string --path "$existing_zones") || exit 120


###
# Get API token from secrets or bail early.
#
token=$(carburator get secret "$DOMAIN_PROVIDER_SECRET_0" --user root); exitcode=$?

if [[ -z $token || $exitcode -gt 0 ]]; then
	carburator print terminal error \
		"Could not load Hetzner DNS API token from secret. Unable to proceed"
	exit 120
fi

# TODO: should extract http response code and != 200, failed.
destroy_zone() {
    curl -X "DELETE" "https://dns.hetzner.com/api/v1/zones/$2" \
        -s \
        -H "Auth-API-Token: $1" &> /dev/null
}


# Delete dns zone for the project
destroy_zone "$token" "$id"

rm -f "$output"