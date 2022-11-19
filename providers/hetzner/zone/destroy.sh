#!/usr/bin/env bash

local zonefile; zonefile=$(provider-dns-zonefile)
local zone; zone=$(jq -rc ".zone.id" "$zonefile")

# Delete dns zone for the project
curl -X "DELETE" "https://dns.hetzner.com/api/v1/zones/$zone" \
-s \
-H "Auth-API-Token: $dns_token" > dns-del.log

if [[ $(cat "dns-del.log") == '{"error":{}}' ]]; then
echo-success "DNS zone for your project was deleted"
else
echo-error "Check your hezner dns console, automatic zone deletion might of failed."
fi

rm -f dns-del.log "$zonefile"