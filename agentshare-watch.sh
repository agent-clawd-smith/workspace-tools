#!/bin/zsh
# Watch AgentShare folder and log new files

AGENTSHARE="/Users/agentclawdsmith/Library/Mobile Documents/com~apple~CloudDocs/AgentShare"

echo "$(date): AgentShare watcher started" >> /tmp/agentshare-watch.log

/opt/homebrew/bin/fswatch -0 "$AGENTSHARE" | while IFS= read -r -d '' file; do
    if [[ -f "$file" ]]; then
        echo "$(date): NEW FILE: $file" >> /tmp/agentshare-watch.log
    fi
done
