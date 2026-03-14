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
openclaw cron list --json 2>/dev/null | jq -c '.[]' | awk '{print "    " $0 ","}' | sed '$ s/,$//' >> "$STATE_FILE" || echo "" >> "$STATE_FILE"
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
if [[ -d "$HOME/repos/llm-observability/podcasts" ]]; then
    for script in "$HOME/repos/llm-observability/podcasts"/*.txt; do
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

# Check for orphaned workspace files (scripts not in repos or symlinks)
ORPHANED_COUNT=0
for file in "$HOME/.openclaw/workspace"/*.{sh,py}; do
    if [[ -f "$file" ]] && [[ ! -L "$file" ]]; then
        # It's a real file, not a symlink - check if it's tracked in a repo
        BASENAME=$(basename "$file")
        # Skip known temp/generated files
        if [[ "$BASENAME" != "venv" ]] && [[ "$BASENAME" != "__pycache__" ]]; then
            ORPHANED_COUNT=$((ORPHANED_COUNT + 1))
        fi
    fi
done
if [[ $ORPHANED_COUNT -gt 0 ]]; then
    echo "    {\"severity\": \"low\", \"type\": \"orphaned_files\", \"message\": \"$ORPHANED_COUNT workspace scripts not tracked in repos (may need migration to workspace-tools)\"}," >> "$HEALTH_FILE"
fi

sed -i '' '$ s/,$//' "$HEALTH_FILE" 2>/dev/null || true
echo "  ]" >> "$HEALTH_FILE"
echo "}" >> "$HEALTH_FILE"

echo "Daily scan complete: $STATE_FILE, $HEALTH_FILE"
