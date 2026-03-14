#!/usr/bin/env bash
# send-later.sh — Schedule an iMessage for future delivery via `at`
# Wraps contact resolution (name → phone/email) + imsg send + at scheduling
#
# Usage:
#   send-later.sh --to "Noah" --text "Thank your dad!" --at "5:22PM"
#   send-later.sh --to "+17145043069" --text "Hey!" --at "10:00AM tomorrow"
#   send-later.sh --to "Noah" --text "Hi" --now   # send immediately (no scheduling)
#
# Contact lookup uses ~/.openclaw/workspace/family-contacts.json

set -euo pipefail

CONTACTS_FILE="$HOME/.openclaw/workspace/family-contacts.json"
IMSG="/opt/homebrew/bin/imsg"

# --- Parse args ---
TO=""
TEXT=""
AT_TIME=""
NOW=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --to)    TO="$2"; shift 2 ;;
    --text)  TEXT="$2"; shift 2 ;;
    --at)    AT_TIME="$2"; shift 2 ;;
    --now)   NOW=true; shift ;;
    *)       echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$TO" ]]; then
  echo "Error: --to is required" >&2
  exit 1
fi

if [[ -z "$TEXT" ]]; then
  echo "Error: --text is required" >&2
  exit 1
fi

if [[ "$NOW" == false && -z "$AT_TIME" ]]; then
  echo "Error: --at <time> or --now is required" >&2
  exit 1
fi

# --- Resolve contact name to phone number / email ---
resolve_contact() {
  local name="$1"

  # If it already looks like a phone number or email, use as-is
  if [[ "$name" == +* ]] || [[ "$name" == *@* ]]; then
    echo "$name"
    return 0
  fi

  if [[ ! -f "$CONTACTS_FILE" ]]; then
    echo "Error: contacts file not found at $CONTACTS_FILE" >&2
    return 1
  fi

  # Reverse lookup: find first phone number for this name (case-insensitive)
  local resolved
  resolved=$(python3 -c "
import json, sys
with open('$CONTACTS_FILE') as f:
    contacts = json.load(f)
name = '$name'.lower()
# Prefer phone numbers over emails
phones = [k for k, v in contacts.items() if v.lower().startswith(name.split()[0].lower()) and k.startswith('+')]
emails = [k for k, v in contacts.items() if v.lower().startswith(name.split()[0].lower()) and '@' in k]
if phones:
    print(phones[0])
elif emails:
    print(emails[0])
else:
    sys.exit(1)
" 2>/dev/null)

  if [[ $? -ne 0 ]] || [[ -z "$resolved" ]]; then
    echo "Error: could not resolve contact name '$name' — not found in $CONTACTS_FILE" >&2
    echo "Available contacts:" >&2
    python3 -c "
import json
with open('$CONTACTS_FILE') as f:
    contacts = json.load(f)
seen = set()
for addr, name in contacts.items():
    if name not in seen:
        seen.add(name)
        print(f'  {name}')
" >&2
    return 1
  fi

  echo "$resolved"
}

RESOLVED_TO=$(resolve_contact "$TO")
echo "Resolved recipient: $TO → $RESOLVED_TO"

# --- Send now or schedule ---
if [[ "$NOW" == true ]]; then
  echo "Sending immediately..."
  OUTPUT=$("$IMSG" send --to "$RESOLVED_TO" --text "$TEXT" 2>&1)
  EXIT_CODE=$?
  if [[ $EXIT_CODE -ne 0 ]]; then
    echo "FAILED (exit $EXIT_CODE): $OUTPUT" >&2
    exit 1
  fi
  echo "Sent successfully."
  echo "$OUTPUT"
else
  echo "Scheduling for: $AT_TIME"

  # Write a temporary script for `at` to execute (avoids all quoting issues)
  TMPSCRIPT=$(mktemp /tmp/send-later.XXXXXX.sh)
  cat > "$TMPSCRIPT" <<SEND_EOF
#!/usr/bin/env bash
"$IMSG" send --to "$RESOLVED_TO" --text "$TEXT"
rm -f "$TMPSCRIPT"
SEND_EOF
  chmod +x "$TMPSCRIPT"

  JOB_OUTPUT=$(echo "$TMPSCRIPT" | at "$AT_TIME" 2>&1)
  EXIT_CODE=$?

  if [[ $EXIT_CODE -ne 0 ]]; then
    rm -f "$TMPSCRIPT"
    echo "FAILED to schedule (exit $EXIT_CODE): $JOB_OUTPUT" >&2
    exit 1
  fi

  echo "Scheduled successfully."
  echo "$JOB_OUTPUT"

  # Verify the job is in the queue
  echo ""
  echo "Current at queue:"
  atq 2>&1 || true
fi
