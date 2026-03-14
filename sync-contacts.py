#!/usr/bin/env python3
"""
Sync Apple Contacts to:
  - family-contacts.json  (identifier -> name map for attachment watcher)
  - ~/.openclaw/openclaw.json  (imessage allowFrom list)

Run this whenever contacts change, or on a schedule.
Skips the agent's own accounts.
"""

import json, re, subprocess, os, sys
from pathlib import Path

WORKSPACE = Path.home() / '.openclaw/workspace'
CONTACTS_FILE = WORKSPACE / 'family-contacts.json'
CONFIG_FILE = Path.home() / '.openclaw/openclaw.json'

SKIP_NAMES = {"Agent Clawd Smith"}
SKIP_EMAILS = {"agent.clawd.smith@icloud.com", "agent.clawd.smith@gmail.com"}

def get_contacts_from_applescript():
    script = '''
tell application "Contacts"
  set output to ""
  repeat with p in every person
    set pName to name of p
    set pPhones to phone of p
    set pEmails to email of p
    repeat with ph in pPhones
      set output to output & pName & "|phone|" & (value of ph) & "\n"
    end repeat
    repeat with em in pEmails
      set output to output & pName & "|email|" & (value of em) & "\n"
    end repeat
  end repeat
  return output
end tell
'''
    result = subprocess.run(['osascript', '-e', script], capture_output=True, text=True)
    return result.stdout.strip()

def normalize_phone(p):
    digits = re.sub(r'\D', '', p)
    if len(digits) == 10:
        digits = '1' + digits
    if len(digits) == 11 and digits.startswith('1'):
        return '+' + digits
    return None

def build_contacts(raw):
    contacts = {}
    for line in raw.strip().split('\n'):
        parts = line.split('|')
        if len(parts) != 3:
            continue
        name, kind, value = parts
        name = name.strip()
        value = value.strip()
        if name in SKIP_NAMES:
            continue
        if kind == 'phone':
            normalized = normalize_phone(value)
            if normalized:
                contacts[normalized] = name
        elif kind == 'email':
            email = value.lower()
            if email not in SKIP_EMAILS:
                contacts[email] = name
    return contacts

def update_openclaw_config(allow_from):
    with open(CONFIG_FILE) as f:
        config = json.load(f)
    config.setdefault('channels', {}).setdefault('imessage', {})
    config['channels']['imessage']['dmPolicy'] = 'allowlist'
    config['channels']['imessage']['allowFrom'] = sorted(allow_from)
    with open(CONFIG_FILE, 'w') as f:
        json.dump(config, f, indent=2)
    print(f"Updated openclaw.json allowFrom: {sorted(allow_from)}")

def main():
    print("Fetching contacts from Apple Contacts...")
    raw = get_contacts_from_applescript()
    if not raw:
        print("ERROR: No contacts returned from AppleScript", file=sys.stderr)
        sys.exit(1)

    contacts = build_contacts(raw)
    print(f"Found {len(contacts)} identifiers across {len(set(contacts.values()))} contacts")

    # Write family-contacts.json
    with open(CONTACTS_FILE, 'w') as f:
        json.dump(contacts, f, indent=2)
    print(f"Wrote {CONTACTS_FILE}")

    # Update openclaw.json
    update_openclaw_config(list(contacts.keys()))
    print("Done. Restart gateway for allowFrom changes to take effect.")
    print("  openclaw gateway restart")

if __name__ == '__main__':
    main()
