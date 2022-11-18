#!/usr/bin/env bash

# Curl is required.
if ! carburator fn integration-installed curl; then
  carburator fn echo error "Missing required program curl. Please install it" \
    "before running this script." && exit 1
fi
