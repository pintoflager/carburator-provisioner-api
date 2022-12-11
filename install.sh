#!/usr/bin/env bash

# Curl is required.
if ! carburator fn integration-installed curl; then
  carburator print terminal error "Missing required program curl. Please install it" \
    "before running this script." && exit 120
fi
