#!/bin/bash
# Daily system awareness scan - runs at 3 AM via cron
# Generates system-state.json, system-delta.json, health-report.json

set -euo pipefail

WORKSPACE="$HOME/.openclaw/workspace"
OBS_DIR="$HOME/repos/llm-observability"
STATE_FILE="$OBS_DIR/system-state.json"
PREV_STATE="$OBS_DIR/system-state-prev.json"
DELTA_FILE="$OBS_DIR/system-delta.json"
HEALTH_FILE="$OBS_DIR/health-report.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Move previous state
if [[ -f "$STATE_FILE" ]]; then
    mv "$STATE_FILE" "$PREV_STATE"
fi

# Initialize state
echo "{" > "$STATE_FILE"
echo "  \"timestamp\": \"$TIMESTAMP\"," >> "$STATE_FILE"

# 1. LaunchAgents
echo "  \"launch_agents\": [" >> "$STATE_FILE"
launchctl list | grep -iE '(openclaw|clawd|imessage-|paper)' | awk '{print "    {\"pid\": \"" $1 "\", \"status\": \"" $2 "\", \"label\": \"" $3 "\"},"}' | sed '$ s/,$//' >> "$STATE_FILE" || echo "" >> "$STATE_FILE"
echo "  ]," >> "$STATE_FILE"

# 2. Cron jobs
echo "  \"cron_jobs\": [" >> "$STATE_FILE"
crontab -l 2>/dev/null | grep -v '^#' | grep -v '^$' | awk '{print "    \"" $0 "\","}' | sed '$ s/,$//' >> "$STATE_FILE" || echo "" >> "$STATE_FILE"
echo "  ]," >> "$STATE_FILE"

# 3. OpenClaw managed crons (via openclaw cron list)
echo "  \"openclaw_crons\": [" >> "$STATE_FILE"
openclaw cron list --json 2>/dev/null | jq -c '.jobs[]' | awk '{print "    " $0 ","}' | sed '$ s/,$//' >> "$STATE_FILE" || echo "" >> "$STATE_FILE"
echo "  ]," >> "$STATE_FILE"

# 4. Git repos status
echo "  \"repos\": [" >> "$STATE_FILE"
for repo in "$HOME/repos"/*; do
    if [[ -d "$repo/.git" ]]; then
        cd "$repo"
        REPO_NAME=$(basename "$repo")
        BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
        UNCOMMITTED=$(git status --porcelain 2>/dev/null | wc -l | xargs)
        UNPUSHED=$(git log @{u}.. --oneline 2>/dev/null | wc -l | xargs || echo "0")
        LAST_COMMIT=$(git log -1 --format="%ci" 2>/dev/null || echo "unknown")
        echo "    {\"name\": \"$REPO_NAME\", \"branch\": \"$BRANCH\", \"uncommitted\": $UNCOMMITTED, \"unpushed\": $UNPUSHED, \"last_commit\": \"$LAST_COMMIT\"}," >> "$STATE_FILE"
    fi
done
sed -i '' '$ s/,$//' "$STATE_FILE" 2>/dev/null || true
echo "  ]," >> "$STATE_FILE"

# 5. Recent podcast outputs
echo "  \"podcasts\": [" >> "$STATE_FILE"
if [[ -d "$HOME/repos/podcast-generator/episodes" ]]; then
    for script in "$HOME/repos/podcast-generator/episodes"/*.txt; do
        if [[ -f "$script" ]]; then
            FILENAME=$(basename "$script")
            SIZE=$(wc -l < "$script" | xargs)
            MODIFIED=$(stat -f "%Sm" -t "%Y-%m-%dT%H:%M:%SZ" "$script")
            echo "    {\"file\": \"$FILENAME\", \"lines\": $SIZE, \"modified\": \"$MODIFIED\"}," >> "$STATE_FILE"
        fi
    done
    sed -i '' '$ s/,$//' "$STATE_FILE" 2>/dev/null || true
fi
echo "  ]," >> "$STATE_FILE"

# 6. Paper trading health
echo "  \"paper_trading\": {" >> "$STATE_FILE"
TRADING_DIR="$HOME/repos/polymarket-paper-trader"
if [[ -f "$TRADING_DIR/signal_weights.json" ]]; then
    WEIGHTS_MODIFIED=$(stat -f "%Sm" -t "%Y-%m-%dT%H:%M:%SZ" "$TRADING_DIR/signal_weights.json")
    echo "    \"signal_weights_modified\": \"$WEIGHTS_MODIFIED\"," >> "$STATE_FILE"
fi
if [[ -f "$HOME/repos/llm-observability/trading-summary.json" ]]; then
    SUMMARY_MODIFIED=$(stat -f "%Sm" -t "%Y-%m-%dT%H:%M:%SZ" "$HOME/repos/llm-observability/trading-summary.json")
    echo "    \"summary_modified\": \"$SUMMARY_MODIFIED\"," >> "$STATE_FILE"
fi
# Check for Kalshi integration files
if [[ -f "$TRADING_DIR/kalshi.py" ]] || [[ -f "$TRADING_DIR/modules/kalshi.py" ]]; then
    echo "    \"kalshi_integrated\": true," >> "$STATE_FILE"
else
    echo "    \"kalshi_integrated\": false," >> "$STATE_FILE"
fi
sed -i '' '$ s/,$//' "$STATE_FILE" 2>/dev/null || true
echo "  }," >> "$STATE_FILE"

# 7. iMessage processor health
echo "  \"imessage_processor\": {" >> "$STATE_FILE"
LOG_FILE="$HOME/.openclaw/workspace-imessage/imessage-processor.log"
if [[ -f "$LOG_FILE" ]]; then
    LAST_RUN=$(tail -n 1 "$LOG_FILE" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}' || echo "unknown")
    ERROR_COUNT=$(grep -c "ERROR" "$LOG_FILE" 2>/dev/null || echo "0")
    echo "    \"last_run\": \"$LAST_RUN\"," >> "$STATE_FILE"
    echo "    \"error_count_total\": $ERROR_COUNT" >> "$STATE_FILE"
else
    echo "    \"last_run\": \"unknown\"," >> "$STATE_FILE"
    echo "    \"error_count_total\": 0" >> "$STATE_FILE"
fi
echo "  }," >> "$STATE_FILE"

# 8. Disk space
echo "  \"disk\": {" >> "$STATE_FILE"
DISK_USAGE=$(df -h / | tail -n 1 | awk '{print $5}' | sed 's/%//')
echo "    \"root_used_percent\": $DISK_USAGE" >> "$STATE_FILE"
echo "  }," >> "$STATE_FILE"

# 9. Skills installed
echo "  \"skills\": [" >> "$STATE_FILE"
SKILLS_DIR="/opt/homebrew/lib/node_modules/openclaw/skills"
if [[ -d "$SKILLS_DIR" ]]; then
    for skill in "$SKILLS_DIR"/*; do
        if [[ -d "$skill" ]]; then
            SKILL_NAME=$(basename "$skill")
            echo "    \"$SKILL_NAME\"," >> "$STATE_FILE"
        fi
    done
    sed -i '' '$ s/,$//' "$STATE_FILE" 2>/dev/null || true
fi
echo "  ]" >> "$STATE_FILE"

echo "}" >> "$STATE_FILE"

# Generate delta if previous state exists
if [[ -f "$PREV_STATE" ]]; then
    echo "{" > "$DELTA_FILE"
    echo "  \"timestamp\": \"$TIMESTAMP\"," >> "$DELTA_FILE"
    echo "  \"changes\": []" >> "$DELTA_FILE"
    echo "}" >> "$DELTA_FILE"
    # TODO: Implement actual delta logic (compare repos, services, etc.)
fi

# Generate health report (check for failures)
echo "{" > "$HEALTH_FILE"
echo "  \"timestamp\": \"$TIMESTAMP\"," >> "$HEALTH_FILE"
echo "  \"issues\": [" >> "$HEALTH_FILE"

# Check for high disk usage
if [[ $DISK_USAGE -gt 85 ]]; then
    echo "    {\"severity\": \"high\", \"type\": \"disk\", \"message\": \"Disk usage at ${DISK_USAGE}%\"}," >> "$HEALTH_FILE"
fi

# Check if paper trading summary is stale (>2 hours old)
if [[ -f "$HOME/repos/llm-observability/trading-summary.json" ]]; then
    SUMMARY_AGE=$(( $(date +%s) - $(stat -f "%m" "$HOME/repos/llm-observability/trading-summary.json") ))
    if [[ $SUMMARY_AGE -gt 7200 ]]; then
        echo "    {\"severity\": \"medium\", \"type\": \"paper_trading\", \"message\": \"Trading summary is stale ($(($SUMMARY_AGE / 3600))h old)\"}," >> "$HEALTH_FILE"
    fi
fi

# Check if iMessage processor ran in last 30 minutes
if [[ -f "$LOG_FILE" ]]; then
    LOG_AGE=$(( $(date +%s) - $(stat -f "%m" "$LOG_FILE") ))
    if [[ $LOG_AGE -gt 1800 ]]; then
        echo "    {\"severity\": \"medium\", \"type\": \"imessage\", \"message\": \"iMessage processor log hasn't updated in $(($LOG_AGE / 60))m\"}," >> "$HEALTH_FILE"
    fi
fi

# Check for failed openclaw cron jobs
FAILED_CRONS=$(openclaw cron list --json 2>/dev/null | jq -c '.jobs[] | select(.state.lastRunStatus == "error") | {id, name, error: .state.lastError, consecutive: .state.consecutiveErrors}' 2>/dev/null)
if [[ -n "$FAILED_CRONS" ]]; then
    while IFS= read -r failed_job; do
        JOB_NAME=$(echo "$failed_job" | jq -r '.name')
        CONSECUTIVE=$(echo "$failed_job" | jq -r '.consecutive')
        ERROR_MSG=$(echo "$failed_job" | jq -r '.error' | head -c 100)
        SEVERITY="medium"
        [[ $CONSECUTIVE -gt 3 ]] && SEVERITY="high"
        echo "    {\"severity\": \"$SEVERITY\", \"type\": \"openclaw_cron\", \"job\": \"$JOB_NAME\", \"consecutive_errors\": $CONSECUTIVE, \"message\": \"$ERROR_MSG\"}," >> "$HEALTH_FILE"
    done <<< "$FAILED_CRONS"
fi

# Check for orphaned files across entire ~/.openclaw (scripts not in repos or symlinks)
ORPHANED_COUNT=0
ORPHANED_LIST=""
while IFS= read -r file; do
    if [[ -f "$file" ]] && [[ ! -L "$file" ]]; then
        # It's a real file, not a symlink
        RELPATH="${file#$HOME/.openclaw/}"
        ORPHANED_COUNT=$((ORPHANED_COUNT + 1))
        if [[ -z "$ORPHANED_LIST" ]]; then
            ORPHANED_LIST="$RELPATH"
        else
            ORPHANED_LIST="$ORPHANED_LIST, $RELPATH"
        fi
    fi
done < <(find "$HOME/.openclaw" -type f \( -name "*.sh" -o -name "*.py" \) ! -path "*/__pycache__/*" ! -path "*/.git/*" ! -path "*/node_modules/*" ! -path "*/venv/*" 2>/dev/null)

if [[ $ORPHANED_COUNT -gt 0 ]]; then
    echo "    {\"severity\": \"low\", \"type\": \"orphaned_files\", \"message\": \"$ORPHANED_COUNT scripts in ~/.openclaw not tracked in repos: $ORPHANED_LIST\"}," >> "$HEALTH_FILE"
fi

# Check for recurring jobs not reflected in Agent Operations table
AGENT_OPS_FILE="$OBS_DIR/agent-operations.json"
MISSING_JOBS=""
MISSING_COUNT=0

if [[ -f "$AGENT_OPS_FILE" ]]; then
    # Get all operation IDs from agent-operations.json
    KNOWN_OPS=$(jq -r '.agent_operations[].id' "$AGENT_OPS_FILE" 2>/dev/null || echo "")
    
    # Check system LaunchDaemons (not just user LaunchAgents)
    if [[ -d "/Library/LaunchDaemons" ]]; then
        for plist in /Library/LaunchDaemons/*.plist; do
            if [[ -f "$plist" ]]; then
                LABEL=$(defaults read "$plist" Label 2>/dev/null || basename "$plist" .plist)
                # Check if it's related to our operations (openclaw, clawd, agent)
                if echo "$LABEL" | grep -qiE "(openclaw|clawd|agent)"; then
                    OP_ID=$(echo "$LABEL" | tr '.' '-')
                    if ! echo "$KNOWN_OPS" | grep -q "$OP_ID"; then
                        MISSING_JOBS="$MISSING_JOBS LaunchDaemon:$LABEL,"
                        MISSING_COUNT=$((MISSING_COUNT + 1))
                    fi
                fi
            fi
        done
    fi
    
    # Check for 'at' scheduled jobs
    AT_JOBS=$(atq 2>/dev/null | wc -l | xargs)
    if [[ "$AT_JOBS" -gt 0 ]]; then
        # 'at' jobs are used by send-later.sh - check if we're tracking that
        if ! echo "$KNOWN_OPS" | grep -q "send-later"; then
            MISSING_JOBS="$MISSING_JOBS at-queue:${AT_JOBS}-jobs,"
            MISSING_COUNT=$((MISSING_COUNT + 1))
        fi
    fi
    
    # Check OpenClaw managed crons for recurring operations (exclude one-time reminders)
    OPENCLAW_CRON_FILE="$HOME/.openclaw/cron/jobs.json"
    if [[ -f "$OPENCLAW_CRON_FILE" ]]; then
        # Get cron jobs that are recurring (have "every" in schedule)
        RECURRING_CRONS=$(jq -r '.jobs[] | select(.schedule.kind == "every") | .name' "$OPENCLAW_CRON_FILE" 2>/dev/null || echo "")
        while IFS= read -r cron_name; do
            if [[ -n "$cron_name" ]]; then
                # Check if any part of the cron name appears in the operations table
                # e.g., "agent-inbox" should match "ai-openclaw-check-inbox"
                FOUND=false
                # Try direct match, lowercase match, and substring match
                if echo "$KNOWN_OPS" | grep -qiE "$cron_name"; then
                    FOUND=true
                else
                    # Try matching key words from the name
                    for word in $(echo "$cron_name" | tr '-' ' '); do
                        if [[ ${#word} -gt 3 ]] && echo "$KNOWN_OPS" | grep -qi "$word"; then
                            FOUND=true
                            break
                        fi
                    done
                fi
                
                if [[ "$FOUND" == "false" ]]; then
                    MISSING_JOBS="$MISSING_JOBS OpenClaw-cron:$cron_name,"
                    MISSING_COUNT=$((MISSING_COUNT + 1))
                fi
            fi
        done <<< "$RECURRING_CRONS"
    fi
    
    if [[ $MISSING_COUNT -gt 0 ]]; then
        MISSING_JOBS="${MISSING_JOBS%,}"  # Remove trailing comma
        echo "    {\"severity\": \"medium\", \"type\": \"untracked_jobs\", \"message\": \"$MISSING_COUNT recurring jobs not in Agent Operations table: $MISSING_JOBS\"}," >> "$HEALTH_FILE"
    fi
fi

sed -i '' '$ s/,$//' "$HEALTH_FILE" 2>/dev/null || true
echo "  ]," >> "$HEALTH_FILE"

# Suggest new auto-triage capabilities based on observed patterns
echo "  \"auto_triage_suggestions\": [" >> "$HEALTH_FILE"

# Check for repos with uncommitted changes >3 days old
for repo in "$HOME/repos"/*; do
    if [[ -d "$repo/.git" ]]; then
        cd "$repo"
        UNCOMMITTED=$(git status --porcelain 2>/dev/null | wc -l | xargs)
        if [[ $UNCOMMITTED -gt 0 ]]; then
            # Check if oldest uncommitted file is >3 days old
            OLDEST_MODIFIED=$(git status --porcelain | awk '{print $2}' | xargs stat -f "%m" 2>/dev/null | sort -n | head -1)
            if [[ -n "$OLDEST_MODIFIED" ]]; then
                AGE_DAYS=$(( ($(date +%s) - $OLDEST_MODIFIED) / 86400 ))
                if [[ $AGE_DAYS -gt 3 ]]; then
                    echo "    {\"type\": \"stale_commits\", \"repo\": \"$(basename $repo)\", \"age_days\": $AGE_DAYS, \"suggestion\": \"Auto-commit stale changes >3 days with message: 'Auto-commit: stale changes from daily scan'\"}," >> "$HEALTH_FILE"
                fi
            fi
        fi
        
        # Check for unpushed commits
        UNPUSHED=$(git log @{u}.. --oneline 2>/dev/null | wc -l | xargs || echo "0")
        if [[ $UNPUSHED -gt 0 ]]; then
            echo "    {\"type\": \"unpushed_commits\", \"repo\": \"$(basename $repo)\", \"count\": $UNPUSHED, \"suggestion\": \"Auto-push commits to remote (low risk if already committed)\"}," >> "$HEALTH_FILE"
        fi
    fi
done

# Check for large log files (>10MB)
for logfile in "$HOME/repos/llm-observability"/*.log "$HOME/.openclaw/workspace"/*.log; do
    if [[ -f "$logfile" ]]; then
        SIZE_MB=$(( $(stat -f "%z" "$logfile" 2>/dev/null || echo 0) / 1048576 ))
        if [[ $SIZE_MB -gt 10 ]]; then
            echo "    {\"type\": \"large_log_files\", \"file\": \"$(basename $logfile)\", \"size_mb\": $SIZE_MB, \"suggestion\": \"Auto-rotate/compress logs >10MB\"}," >> "$HEALTH_FILE"
        fi
    fi
done

# Check for disk usage trending (if >70%, suggest proactive cleanup)
if [[ $DISK_USAGE -gt 70 ]]; then
    echo "    {\"type\": \"disk_trending_high\", \"current_percent\": $DISK_USAGE, \"suggestion\": \"Auto-cleanup: old logs (>30 days), podcast archives (>60 days), temp files\"}," >> "$HEALTH_FILE"
fi

# Check for LaunchAgents that failed to load (status != 0, but only if not running)
launchctl list | grep -iE "(openclaw|clawd|agent)" | while read -r line; do
    PID=$(echo "$line" | awk '{print $1}')
    STATUS=$(echo "$line" | awk '{print $2}')
    LABEL=$(echo "$line" | awk '{print $3}')
    # Only flag if status is bad AND not running (PID is "-")
    if [[ "$STATUS" != "0" ]] && [[ "$STATUS" != "-" ]] && [[ "$PID" == "-" ]]; then
        echo "    {\"type\": \"failed_launchagent\", \"label\": \"$LABEL\", \"status\": $STATUS, \"suggestion\": \"Auto-restart failed LaunchAgent (low risk)\"}," >> "$HEALTH_FILE"
    fi
done

# Check for recurring cron job failures (exit code tracking would require log parsing - future enhancement)
# Placeholder for now
echo "    {\"type\": \"future_capability\", \"suggestion\": \"Track cron job exit codes → auto-restart failed jobs\"}," >> "$HEALTH_FILE"
echo "    {\"type\": \"future_capability\", \"suggestion\": \"Monitor service resource usage → auto-restart memory leaks\"}," >> "$HEALTH_FILE"
echo "    {\"type\": \"future_capability\", \"suggestion\": \"Detect config drift → auto-restore from known-good state\"}" >> "$HEALTH_FILE"

echo "  ]" >> "$HEALTH_FILE"
echo "}" >> "$HEALTH_FILE"

echo "Daily scan complete: $STATE_FILE, $HEALTH_FILE"
