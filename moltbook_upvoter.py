#!/usr/bin/env python3
import json
import subprocess
import os
import re

def _load_moltbook_key():
    secrets_path = os.path.expanduser("~/.openclaw/secrets.json")
    with open(secrets_path) as f:
        secrets = json.load(f)
    key = secrets.get("moltbook", {}).get("apiKey")
    if not key:
        raise RuntimeError("Moltbook API key not found in ~/.openclaw/secrets.json under moltbook.apiKey")
    return key

KEY = _load_moltbook_key()
BASE = "https://www.moltbook.com/api/v1"

def run(cmd):
    """Run a command as a list (no shell). Safer than shell=True."""
    result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    return result.stdout.strip()

def _validate_post_id(post_id):
    """Validate post_id is alphanumeric to prevent injection."""
    s = str(post_id)
    if not re.match(r'^[a-zA-Z0-9_-]+$', s):
        raise ValueError(f"Invalid post_id: {s!r}")
    return s

def get_post_ids():
    raw = run(["curl", "-s", f"{BASE}/home", "-H", f"Authorization: Bearer {KEY}"])
    if not raw:
        return []
    try:
        data = json.loads(raw)
        return [p['post_id'] for p in data.get('posts_from_accounts_you_follow', {}).get('posts', [])]
    except (json.JSONDecodeError, KeyError):
        return []

def upvote_post(post_id):
    safe_id = _validate_post_id(post_id)
    run(["curl", "-s", "-X", "POST", f"{BASE}/posts/{safe_id}/upvote", "-H", f"Authorization: Bearer {KEY}"])
    print(f"Upvoted {safe_id}")

def main():
    post_ids = get_post_ids()
    if not post_ids:
        print("No new posts to upvote.")
        return

    for post_id in post_ids:
        upvote_post(post_id)

    # Update state file
    state = {"lastEmailCheck":1772638800,"lastPolymarketScan":1772638800,"lastMoltbookCheck":1772638800}
    with open("/Users/agentclawdsmith/.openclaw/workspace/memory/heartbeat-state.json", "w") as f:
        json.dump(state, f)
    print("State file updated.")

if __name__ == "__main__":
    main()
