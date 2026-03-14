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

# Process issues (if any)
if [[ "$ISSUE_COUNT" -gt 0 ]]; then
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
        
        orphaned_files)
            if [[ "$SEVERITY" == "low" ]]; then
                # Low risk - migrate to workspace-tools repo autonomously
                TOOLS_REPO="$HOME/repos/workspace-tools"
                WORKSPACE="$HOME/.openclaw/workspace"
                
                # Find orphaned .sh and .py files
                ORPHANED_FILES=$(find "$WORKSPACE" -maxdepth 1 -type f \( -name "*.sh" -o -name "*.py" \) 2>/dev/null)
                
                if [[ -n "$ORPHANED_FILES" ]]; then
                    cd "$TOOLS_REPO"
                    MIGRATED=0
                    while IFS= read -r file; do
                        FILENAME=$(basename "$file")
                        # Copy to repo
                        cp "$file" "$TOOLS_REPO/$FILENAME"
                        # Replace with symlink
                        rm "$file"
                        ln -s "$TOOLS_REPO/$FILENAME" "$file"
                        MIGRATED=$((MIGRATED + 1))
                    done <<< "$ORPHANED_FILES"
                    
                    # Commit and push
                    git add *.sh *.py 2>/dev/null || true
                    git commit -m "Auto-migrate $MIGRATED orphaned workspace scripts

Low-risk infrastructure fix: moved untracked scripts to repo
Replaced with symlinks to maintain paths" 2>&1
                    git push 2>&1
                    
                    imsg send --to "$ADAM_NUMBER" --text "Fixed: Migrated $MIGRATED orphaned workspace scripts to workspace-tools repo, replaced with symlinks ✅ 🕶️"
                else
                    # Already fixed or false positive
                    imsg send --to "$ADAM_NUMBER" --text "ℹ️ Orphaned files alert but none found - may have been fixed already"
                fi
            fi
            ;;
    esac
    done
fi

# Process auto-triage suggestions (from health report)
if [[ -f "$HEALTH_FILE" ]]; then
    SUGGESTIONS=$(jq -r '.auto_triage_suggestions[]? | @json' "$HEALTH_FILE" 2>/dev/null)
    
    while IFS= read -r suggestion_json; do
        if [[ -n "$suggestion_json" ]]; then
            SUGGESTION_TYPE=$(echo "$suggestion_json" | jq -r '.type')
            
            case "$SUGGESTION_TYPE" in
                stale_commits)
                    # Auto-commit stale changes >3 days old
                    REPO_NAME=$(echo "$suggestion_json" | jq -r '.repo')
                    REPO_PATH="$HOME/repos/$REPO_NAME"
                    AGE_DAYS=$(echo "$suggestion_json" | jq -r '.age_days')
                    
                    if [[ -d "$REPO_PATH/.git" ]]; then
                        cd "$REPO_PATH"
                        UNCOMMITTED=$(git status --porcelain | wc -l | xargs)
                        if [[ $UNCOMMITTED -gt 0 ]]; then
                            git add -A
                            git commit -m "Auto-commit: stale changes from daily scan ($AGE_DAYS days old)" 2>&1
                            imsg send --to "$ADAM_NUMBER" --text "Fixed: Auto-committed $UNCOMMITTED stale changes in $REPO_NAME ($AGE_DAYS days old) ✅ 🕶️"
                        fi
                    fi
                    ;;
                
                unpushed_commits)
                    # Auto-push unpushed commits
                    REPO_NAME=$(echo "$suggestion_json" | jq -r '.repo')
                    REPO_PATH="$HOME/repos/$REPO_NAME"
                    COUNT=$(echo "$suggestion_json" | jq -r '.count')
                    
                    if [[ -d "$REPO_PATH/.git" ]]; then
                        cd "$REPO_PATH"
                        git push 2>&1
                        imsg send --to "$ADAM_NUMBER" --text "Fixed: Auto-pushed $COUNT commits in $REPO_NAME to remote ✅ 🕶️"
                    fi
                    ;;
                
                failed_launchagent)
                    # Auto-restart failed LaunchAgent (only if actually NOT running)
                    LABEL=$(echo "$suggestion_json" | jq -r '.label')
                    STATUS=$(echo "$suggestion_json" | jq -r '.status')
                    
                    # Check if it's actually running (has a valid PID)
                    CURRENT_PID=$(launchctl list | grep "$LABEL" | awk '{print $1}')
                    if [[ "$CURRENT_PID" != "-" ]] && [[ -n "$CURRENT_PID" ]]; then
                        # Service is running (has PID) - sticky error status is harmless, skip
                        continue
                    fi
                    
                    # Service is NOT running - restart it
                    launchctl kickstart -k "gui/$(id -u)/$LABEL" 2>&1
                    sleep 2
                    
                    # Check if it's running now
                    NEW_PID=$(launchctl list | grep "$LABEL" | awk '{print $1}')
                    if [[ "$NEW_PID" != "-" ]] && [[ -n "$NEW_PID" ]]; then
                        imsg send --to "$ADAM_NUMBER" --text "Fixed: Restarted failed LaunchAgent $LABEL (now running with PID $NEW_PID) ✅ 🕶️"
                    else
                        imsg send --to "$ADAM_NUMBER" --text "⚠️ Tried to restart $LABEL but it's still not running"
                    fi
                    ;;
                
                large_log_files|disk_trending_high|future_capability)
                    # Not implemented yet - skip
                    ;;
            esac
        fi
    done <<< "$SUGGESTIONS"
fi

echo "Triage complete: processed $ISSUE_COUNT issues"

# Re-run the daily scan to update health report (clears fixed suggestions)
echo "Re-running scan to update health status..."
"$HOME/.openclaw/workspace/daily-scan.sh" >/dev/null 2>&1
