#!/usr/bin/env python3
"""
Centralized Firecrawl credit tracker for all OpenClaw services.

Tracks month-to-date Firecrawl API usage across:
- Polymarket sentiment signal (paper trader)
- Daily podcast generation
- iMessage agent link enrichment
- Any other service using Firecrawl

Usage:
    from firecrawl_tracker import log_usage, get_monthly_usage
    
    # Log credits consumed
    log_usage(credits=2, service="sentiment", operation="news_search")
    
    # Get month-to-date stats
    stats = get_monthly_usage()
    print(f"Month total: {stats['total_credits']}/3000")

State file: ~/.openclaw/firecrawl-usage.json
Format:
{
  "month": "2026-03",
  "total_credits": 450,
  "by_service": {
    "sentiment": 320,
    "podcast": 100,
    "imessage": 30
  },
  "daily_log": [
    {"date": "2026-03-15", "credits": 80, "by_service": {...}}
  ]
}
"""
import json
import os
from datetime import datetime, timezone

STATE_PATH = os.path.expanduser("~/.openclaw/firecrawl-usage.json")
MONTHLY_CAP = 3000  # Hobby tier


def log_usage(credits, service="unknown", operation=""):
    """
    Log Firecrawl credit consumption.
    
    Args:
        credits: Number of credits consumed (typically 2 per /search call)
        service: Service name (sentiment, podcast, imessage, etc.)
        operation: Optional description (news_search, link_enrichment, etc.)
    """
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    current_month = datetime.now(timezone.utc).strftime("%Y-%m")
    
    # Load existing state
    if os.path.exists(STATE_PATH):
        with open(STATE_PATH) as f:
            state = json.load(f)
    else:
        state = {
            "month": current_month,
            "total_credits": 0,
            "by_service": {},
            "daily_log": []
        }
    
    # Reset if new month
    if state.get("month") != current_month:
        state = {
            "month": current_month,
            "total_credits": 0,
            "by_service": {},
            "daily_log": []
        }
    
    # Update totals
    state["total_credits"] += credits
    state["by_service"][service] = state["by_service"].get(service, 0) + credits
    
    # Update or create today's log entry
    daily_log = state.get("daily_log", [])
    today_entry = next((d for d in daily_log if d["date"] == today), None)
    
    if today_entry:
        today_entry["credits"] += credits
        today_entry["by_service"][service] = today_entry["by_service"].get(service, 0) + credits
    else:
        daily_log.append({
            "date": today,
            "credits": credits,
            "by_service": {service: credits}
        })
        state["daily_log"] = daily_log
    
    # Save
    os.makedirs(os.path.dirname(STATE_PATH), exist_ok=True)
    with open(STATE_PATH, "w") as f:
        json.dump(state, f, indent=2)


def get_monthly_usage():
    """
    Get month-to-date Firecrawl usage stats.
    
    Returns:
        dict with keys:
            month: "2026-03"
            total_credits: 450
            by_service: {sentiment: 320, podcast: 100, ...}
            daily_log: [...]
            remaining: 2550
            percent_used: 15
    """
    if not os.path.exists(STATE_PATH):
        return {
            "month": datetime.now(timezone.utc).strftime("%Y-%m"),
            "total_credits": 0,
            "by_service": {},
            "daily_log": [],
            "remaining": MONTHLY_CAP,
            "percent_used": 0
        }
    
    with open(STATE_PATH) as f:
        state = json.load(f)
    
    total = state.get("total_credits", 0)
    return {
        **state,
        "remaining": MONTHLY_CAP - total,
        "percent_used": round(total / MONTHLY_CAP * 100, 1)
    }


def get_today_usage():
    """
    Get today's Firecrawl credit usage.
    
    Returns:
        int: Credits used today
    """
    today = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    stats = get_monthly_usage()
    
    today_entry = next((d for d in stats["daily_log"] if d["date"] == today), None)
    return today_entry["credits"] if today_entry else 0


if __name__ == "__main__":
    import sys
    
    if len(sys.argv) > 1 and sys.argv[1] == "log":
        # Test logging
        if len(sys.argv) < 3:
            print("Usage: firecrawl-tracker.py log <credits> [service] [operation]")
            sys.exit(1)
        credits = int(sys.argv[2])
        service = sys.argv[3] if len(sys.argv) > 3 else "test"
        operation = sys.argv[4] if len(sys.argv) > 4 else ""
        log_usage(credits, service, operation)
        print(f"Logged {credits} credits for {service}")
    
    # Show current usage
    stats = get_monthly_usage()
    print(f"\nFirecrawl Usage for {stats['month']}:")
    print(f"  Total: {stats['total_credits']}/{MONTHLY_CAP} credits ({stats['percent_used']}%)")
    print(f"  Remaining: {stats['remaining']}")
    print(f"\n  By service:")
    for svc, count in sorted(stats["by_service"].items(), key=lambda x: x[1], reverse=True):
        pct = round(count / stats['total_credits'] * 100) if stats['total_credits'] > 0 else 0
        print(f"    {svc}: {count} credits ({pct}%)")
    
    if stats["daily_log"]:
        print(f"\n  Last 7 days:")
        for entry in stats["daily_log"][-7:]:
            print(f"    {entry['date']}: {entry['credits']} credits")
