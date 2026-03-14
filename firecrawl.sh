#!/bin/zsh
# Firecrawl search + scrape helper
# Usage:
#   firecrawl.sh search "your query" [limit]
#   firecrawl.sh scrape "https://example.com"

FIRECRAWL_API_KEY=$(python3 -c "import json; c=json.load(open('$HOME/.openclaw/secrets.json')); print(c['firecrawl']['apiKey'])")
BASE="https://api.firecrawl.dev/v1"

case "$1" in
  search)
    QUERY="$2"
    LIMIT="${3:-5}"
    # Use jq to safely construct JSON, preventing injection via user input
    JSON_BODY=$(jq -n --arg q "$QUERY" --argjson l "$LIMIT" '{query: $q, limit: $l}')
    curl -s -X POST "$BASE/search" \
      -H "Authorization: Bearer $FIRECRAWL_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$JSON_BODY"
    ;;
  scrape)
    URL="$2"
    # Use jq to safely construct JSON, preventing injection via user input
    JSON_BODY=$(jq -n --arg u "$URL" '{url: $u, formats: ["markdown"]}')
    curl -s -X POST "$BASE/scrape" \
      -H "Authorization: Bearer $FIRECRAWL_API_KEY" \
      -H "Content-Type: application/json" \
      -d "$JSON_BODY"
    ;;
  *)
    echo "Usage: $0 search <query> [limit]"
    echo "       $0 scrape <url>"
    ;;
esac
