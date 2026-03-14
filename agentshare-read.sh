#!/bin/zsh
# Download and copy all files from AgentShare to workspace for reading

AGENTSHARE="/Users/agentclawdsmith/Library/Mobile Documents/com~apple~CloudDocs/AgentShare"
DEST="/Users/agentclawdsmith/.openclaw/workspace/agentshare_inbox"

mkdir -p "$DEST"

cd "$AGENTSHARE"

for f in *; do
    [[ -f "$f" ]] || continue
    echo "Downloading: $f"
    /usr/bin/brctl download "$AGENTSHARE/$f" 2>/dev/null
done

sleep 5

for f in *; do
    [[ -f "$f" ]] || continue
    cp "$f" "$DEST/" 2>/dev/null && echo "Copied: $f" || echo "Failed: $f"
done

echo "Done."
