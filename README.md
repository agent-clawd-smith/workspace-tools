# Workspace Tools

Infrastructure utilities and glue scripts for Agent Clawd Smith's workspace.

These are standalone scripts that live in `~/.openclaw/workspace/` and provide infrastructure services, automation, and integrations that don't fit into other repos.

## System Awareness

### `daily-scan.sh`
**Purpose:** Mechanical infrastructure scan (runs 3 AM daily via cron)

**What it captures:**
- LaunchAgents/LaunchDaemons status
- Cron jobs (system + OpenClaw managed)
- Git repo status (uncommitted/unpushed changes)
- Podcast outputs
- Paper trading health
- iMessage processor status
- Disk usage
- Installed skills

**Output:** `~/repos/llm-observability/system-state.json`, `system-delta.json`, `health-report.json`

**Cron:** `0 3 * * * ~/.openclaw/workspace/daily-scan.sh >> ~/.openclaw/workspace/daily-scan.log 2>&1`

### `auto-triage.sh`
**Purpose:** Auto-fix low-risk issues, alert on high-risk (runs 3:05 AM daily)

**What it does:**
- Reads `health-report.json` from daily scan
- Auto-fixes: stuck services, permission issues, disk cleanup
- Alerts via iMessage: service failures, security issues, unusual resource consumption

**Cron:** `5 3 * * * ~/.openclaw/workspace/auto-triage.sh >> ~/.openclaw/workspace/auto-triage.log 2>&1`

## iMessage Tools

### `send-later.sh`
**Purpose:** Schedule iMessage delivery with contact name resolution

**Usage:**
```bash
send-later.sh --to "Noah" --text "Message" --at "5:22PM"
send-later.sh --to "+1XXXXXXXXXX" --text "Message" --now
```

**Features:**
- Resolves contact names → phone numbers via `family-contacts.json`
- Schedules via macOS `at` command
- Validates job creation
- `--now` flag for immediate send with contact resolution

### `sync-contacts.py`
**Purpose:** Sync Apple Contacts → `family-contacts.json` + OpenClaw allowlist

**What it does:**
- Reads Apple Contacts database
- Exports family contacts to JSON
- Updates OpenClaw channel allowlists
- Ensures iMessage routing works with contact names

**LaunchAgent:** Runs on login + file system changes

## AgentShare Tools

### `agentshare-watch.sh`
**Purpose:** Watch `~/AgentShare/` for new files, notify agent

**LaunchAgent:** `com.agentclawd.agentshare-watch`

**What it does:**
- Monitors `~/AgentShare/<Person>/` directories
- Detects new files (images, documents, etc.)
- Notifies agent via OpenClaw
- Enables family members to share files with the agent

### `agentshare-read.sh`
**Purpose:** Helper script to read AgentShare files

## Firecrawl

### `firecrawl.sh`
**Purpose:** Firecrawl CLI wrapper with credential management

**Usage:**
```bash
firecrawl.sh scrape <url>
firecrawl.sh map <url>
```

**Features:**
- Loads API key from `~/.openclaw/secrets.json`
- Simplified interface for web scraping
- Used by podcast generation pipeline

## Other

### `email-check.py`
**Purpose:** Email polling script (himalaya integration)

### `alexa-trigger.sh`
**Purpose:** Alexa automation trigger (?)

### `moltbook_upvoter.py`
**Purpose:** Moltbook upvote automation

---

## Installation

These scripts are deployed to `~/.openclaw/workspace/` via symlink:

```bash
cd ~/.openclaw/workspace
ln -sf ~/repos/workspace-tools/daily-scan.sh daily-scan.sh
ln -sf ~/repos/workspace-tools/auto-triage.sh auto-triage.sh
# ... etc
```

## Observability

- Daily scan results appear in the **System** tab at http://localhost:8765
- Agent Operations table tracks scan execution costs
- Alerts delivered via iMessage to the operator (phone from `secrets.json`)
