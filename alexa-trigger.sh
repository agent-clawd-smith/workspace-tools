#!/bin/zsh
# Agent Smith Trigger Poller
# Watches the Hubitat virtual switch and responds when Alexa triggers it

TOKEN=$(python3 -c "import json; c=json.load(open('$HOME/.openclaw/secrets.json')); print(c['hubitat']['token'])")
DEVICE_ID="112"
API_BASE="http://10.0.0.53/apps/api/179"
STATE_FILE="/tmp/agent-smith-trigger-state"

# Initialize state file
if [ ! -f "$STATE_FILE" ]; then
    echo "off" > "$STATE_FILE"
fi

while true; do
    CURRENT=$(curl -s "$API_BASE/devices/$DEVICE_ID?access_token=$TOKEN" | python3 -c "import json,sys; d=json.load(sys.stdin); sw=[a for a in d['attributes'] if a['name']=='switch'][0]; print(sw['currentValue'])" 2>/dev/null)
    LAST=$(cat "$STATE_FILE")

    if [ "$CURRENT" = "on" ] && [ "$LAST" = "off" ]; then
        echo "$(date): Agent Smith Trigger fired!" >> /tmp/agent-smith-trigger.log

        # Flash office lights
        openhue set light 5235045d-2aa4-4250-a613-b5c50ce8c5a4 --color green &
        openhue set light 4fa76cb2-5ff0-47f9-9323-6d297683010c --color green &
        wait
        sleep 0.5
        openhue set light 5235045d-2aa4-4250-a613-b5c50ce8c5a4 --color deep_sky_blue --brightness 20 &
        openhue set light 4fa76cb2-5ff0-47f9-9323-6d297683010c --color deep_sky_blue --brightness 20 &
        wait

        # Reset the switch
        curl -s "$API_BASE/devices/$DEVICE_ID/off?access_token=$TOKEN" > /dev/null

        echo "on" > "$STATE_FILE"
    elif [ "$CURRENT" = "off" ]; then
        echo "off" > "$STATE_FILE"
    fi

    sleep 5
done
