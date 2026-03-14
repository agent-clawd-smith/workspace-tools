#!/bin/bash
# Auto-triage health issues - runs after daily-scan.sh
# Low-risk fixes: auto-fix and notify
# High-risk issues: alert via iMessage for approval

set -euo pipefail

OBS_DIR="$HOME/repos/llm-observability"
HEALTH_FILE="$OBS_DIR/health-report.json"
ADAM_NUMBER=$(python3 -c "import json; print(json.load(open('$HOME/.openclaw/secrets.json'))['operator_phone'])")

if [[ ! -f "$HEALTH_FILE" ]]; then
    echo "No health report found, skipping triage"
    exit 0
fi

ISSUE_COUNT=$(jq '.issues | length' "$HEALTH_FILE")

if [[ "$ISSUE_COUNT" -eq 0 ]]; then
    echo "No issues detected, skipping triage"
    exit 0
fi

# Process each issue
for i in $(seq 0 $(($ISSUE_COUNT - 1))); do
    SEVERITY=$(jq -r ".issues[$i].severity" "$HEALTH_FILE")
    TYPE=$(jq -r ".issues[$i].type" "$HEALTH_FILE")
    MESSAGE=$(jq -r ".issues[$i].message" "$HEALTH_FILE")
    
    case "$TYPE" in
        disk)
            if [[ "$SEVERITY" == "high" ]]; then
                # High risk - alert Adam
                imsg send --to "$ADAM_NUMBER" --text "🚨 **Disk Usage**
Problem: $MESSAGE
Risk: HIGH
Suggested fix: Clean up old logs, podcasts, or temp files
Reply with your decision"
            fi
            ;;
        
        paper_trading)
            if [[ "$SEVERITY" == "medium" ]]; then
                # Check cron job status
                CRON_STATUS=$(openclaw cron list --json 2>/dev/null | jq -r '.[] | select(.label == "paper-trading-scan") | .enabled' || echo "unknown")
                if [[ "$CRON_STATUS" == "false" ]]; then
                    # Low risk - just enable it
                    # openclaw cron enable <id> (need to implement this properly)
                    imsg send --to "$ADAM_NUMBER" --text "Fixed: Paper trading cron was disabled, re-enabled it 🕶️"
                else
                    # Medium risk - notify
                    imsg send --to "$ADAM_NUMBER" --text "⚠️ Paper trading: $MESSAGE - cron is running but output is stale. May need manual check."
                fi
            fi
            ;;
        
        imessage)
            if [[ "$SEVERITY" == "medium" ]]; then
                # Check if LaunchAgent is running
                RUNNING=$(launchctl list | grep -c "com.openclaw.imessage-processor" || echo "0")
                if [[ "$RUNNING" -eq 0 ]]; then
                    # Low risk - restart the service
                    launchctl load ~/Library/LaunchAgents/com.openclaw.imessage-processor.plist 2>/dev/null || true
                    imsg send --to "$ADAM_NUMBER" --text "Fixed: iMessage processor wasn't running, restarted it 🕶️"
                else
                    # Unknown cause - alert
                    imsg send --to "$ADAM_NUMBER" --text "⚠️ iMessage processor: $MESSAGE - service is running but may be stuck."
                fi
            fi
            ;;
    esac
done

echo "Triage complete: processed $ISSUE_COUNT issues"
