#!/usr/bin/env bash
# Generic Home Assistant service caller
# Usage: ha-call.sh <domain/service> <entity_id>
# Example: ha-call.sh light/toggle light.office

set -euo pipefail

HA_URL="https://ha.miker.be"
HA_TOKEN_FILE="$HOME/.config/home-assistant/token"

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <domain/service> <entity_id>" >&2
    exit 1
fi

SERVICE="$1"
ENTITY_ID="$2"

if [[ ! -f "$HA_TOKEN_FILE" ]]; then
    notify-send -u critical "Home Assistant" "Token file missing: $HA_TOKEN_FILE"
    exit 1
fi

HA_TOKEN=$(cat "$HA_TOKEN_FILE")

curl -s -X POST \
    -H "Authorization: Bearer $HA_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"entity_id\": \"$ENTITY_ID\"}" \
    "$HA_URL/api/services/$SERVICE" > /dev/null
