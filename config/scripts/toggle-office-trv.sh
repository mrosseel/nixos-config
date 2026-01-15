#!/usr/bin/env bash
# Toggle Office TRV and show notification with temperature

HA_URL="https://ha.miker.be"
HA_TOKEN_FILE="$HOME/.config/home-assistant/token"
ENTITY="climate.shellytrv_office"

if [[ ! -f "$HA_TOKEN_FILE" ]]; then
    notify-send -u critical "Office TRV" "Token file missing: $HA_TOKEN_FILE"
    exit 1
fi
HA_TOKEN=$(cat "$HA_TOKEN_FILE")

# Get current state
STATE_JSON=$(curl -s -H "Authorization: Bearer $HA_TOKEN" "$HA_URL/api/states/$ENTITY")
CURRENT_STATE=$(echo "$STATE_JSON" | jq -r '.state')
CURRENT_TEMP=$(echo "$STATE_JSON" | jq -r '.attributes.current_temperature')
TARGET_TEMP=$(echo "$STATE_JSON" | jq -r '.attributes.temperature')

# Toggle: if heat -> off, if off -> heat
if [ "$CURRENT_STATE" = "heat" ]; then
    NEW_MODE="off"
else
    NEW_MODE="heat"
fi

# Set new mode
curl -s -X POST \
    -H "Authorization: Bearer $HA_TOKEN" \
    -H "Content-Type: application/json" \
    -d "{\"entity_id\": \"$ENTITY\", \"hvac_mode\": \"$NEW_MODE\"}" \
    "$HA_URL/api/services/climate/set_hvac_mode" > /dev/null

# Show notification
notify-send -t 3000 "Office TRV" "Mode: $NEW_MODE\nCurrent: ${CURRENT_TEMP}°C\nTarget: ${TARGET_TEMP}°C"
