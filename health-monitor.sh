#!/bin/bash
# Lightweight health monitor - runs every 2 hours
# Checks for failed services and openclaw cron jobs
# Alerts via iMessage for failures

set -euo pipefail

OBS_DIR="$HOME/repos/llm-observability"
HEALTH_CHECK_FILE="$OBS_DIR/health-check-$(date +%Y%m%d-%H%M).json"
ADAM_NUMBER=$(python3 -c "import json; print(json.load(open('$HOME/.openclaw/secrets.json'))['operator_phone'])")

echo "{"  > "$HEALTH_CHECK_FILE"
echo "  \"timestamp\": \"$(date -u +"%Y-%m-%dT%H:%M:%SZ")\"," >> "$HEALTH_CHECK_FILE"
echo "  \"alerts\": [" >> "$HEALTH_CHECK_FILE"

ALERT_COUNT=0

# Check for failed openclaw cron jobs
FAILED_CRONS=$(openclaw cron list --json 2>/dev/null | jq -c '.jobs[] | select(.state.lastRunStatus == "error") | {id, name, error: .state.lastError, consecutive: .state.consecutiveErrors}' 2>/dev/null)

if [[ -n "$FAILED_CRONS" ]]; then
    while IFS= read -r failed_job; do
        JOB_NAME=$(echo "$failed_job" | jq -r '.name')
        CONSECUTIVE=$(echo "$failed_job" | jq -r '.consecutive')
        ERROR_MSG=$(echo "$failed_job" | jq -r '.error' | head -c 150)
        
        # Alert on first failure or every 3rd consecutive failure
        if [[ $CONSECUTIVE -eq 1 ]] || [[ $(($CONSECUTIVE % 3)) -eq 0 ]]; then
            SEVERITY="⚠️"
            [[ $CONSECUTIVE -gt 3 ]] && SEVERITY="🚨"
            
            imsg send --to "$ADAM_NUMBER" --text "$SEVERITY Cron job '$JOB_NAME' failed ($CONSECUTIVE consecutive)
Error: $ERROR_MSG"
            
            echo "    {\"type\": \"openclaw_cron\", \"job\": \"$JOB_NAME\", \"consecutive\": $CONSECUTIVE, \"alerted\": true}," >> "$HEALTH_CHECK_FILE"
            ALERT_COUNT=$((ALERT_COUNT + 1))
        fi
    done <<< "$FAILED_CRONS"
fi

# Check for crashed LaunchAgents (status != 0)
CRASHED_AGENTS=$(launchctl list | grep -iE '(openclaw|clawd|imessage-|paper)' | awk '$2 != "0" && $2 != "-" {print $3 ":" $2}')

if [[ -n "$CRASHED_AGENTS" ]]; then
    while IFS=':' read -r label status; do
        imsg send --to "$ADAM_NUMBER" --text "🚨 LaunchAgent crashed: $label (status $status)"
        echo "    {\"type\": \"launchagent\", \"label\": \"$label\", \"status\": \"$status\", \"alerted\": true}," >> "$HEALTH_CHECK_FILE"
        ALERT_COUNT=$((ALERT_COUNT + 1))
    done <<< "$CRASHED_AGENTS"
fi

# Remove trailing comma if alerts exist
if [[ $ALERT_COUNT -gt 0 ]]; then
    sed -i '' '$ s/,$//' "$HEALTH_CHECK_FILE" 2>/dev/null || true
fi

echo "  ]," >> "$HEALTH_CHECK_FILE"
echo "  \"alert_count\": $ALERT_COUNT" >> "$HEALTH_CHECK_FILE"
echo "}" >> "$HEALTH_CHECK_FILE"

# Cleanup old health-check files (keep last 48 hours = 24 runs)
find "$OBS_DIR" -name "health-check-*.json" -mtime +2d -delete 2>/dev/null || true

exit 0
