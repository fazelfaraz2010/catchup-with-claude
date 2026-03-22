#!/bin/bash
# fetch-discord.sh — Fetch Discord announcements, events, and updates
# Usage: ./fetch-discord.sh <data_dir> <since_date>
# Requires: Discord desktop app running with --remote-debugging-port=9232

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENCLI_DIR="$HOME/opencli"
DATA_DIR="${1:?Usage: ./fetch-discord.sh <data_dir> <since_date>}"
SINCE="${2:?Usage: ./fetch-discord.sh <data_dir> <since_date>}"

export OPENCLI_CDP_ENDPOINT="http://127.0.0.1:9333"
DISCORD_CDP_PORT=9333

echo "--- Fetching Discord channels ---"

# Check Discord is running with CDP
if ! curl -s http://127.0.0.1:${DISCORD_CDP_PORT}/json >/dev/null 2>&1; then
  echo "  Discord not running with CDP. Launching..."
  killall Discord 2>/dev/null || true
  sleep 2
  /Applications/Discord.app/Contents/MacOS/Discord --remote-debugging-port=${DISCORD_CDP_PORT} &disown 2>/dev/null
  sleep 10
fi

# Helper: navigate Discord to a channel via CDP
navigate_channel() {
  local SERVER_ID="$1"
  local CHANNEL_ID="$2"
  cd "$OPENCLI_DIR"
  node -e "
const http = require('http');
const WebSocket = require('ws');
http.get('http://127.0.0.1:${DISCORD_CDP_PORT}/json', (res) => {
  let data = '';
  res.on('data', chunk => data += chunk);
  res.on('end', () => {
    const targets = JSON.parse(data);
    const discord = targets.find(t => t.url && t.url.includes('discord.com'));
    if (!discord) { process.exit(1); }
    const ws = new WebSocket(discord.webSocketDebuggerUrl);
    ws.on('open', () => {
      ws.send(JSON.stringify({ id: 1, method: 'Runtime.evaluate', params: { expression: 'window.location.href = \"https://discord.com/channels/$SERVER_ID/$CHANNEL_ID\"' } }));
      setTimeout(() => { ws.close(); process.exit(0); }, 3000);
    });
    ws.on('error', () => process.exit(1));
  });
});
" 2>/dev/null
  cd "$SCRIPT_DIR"
}

# Read config
SERVER_ID=$(python3 -c "
import json
with open('$SCRIPT_DIR/accounts.json') as f:
    print(json.load(f)['discord']['server_id'])
")

CHANNELS=$(python3 -c "
import json
with open('$SCRIPT_DIR/accounts.json') as f:
    data = json.load(f)
for ch in data['discord']['channels']:
    print(ch['id'] + '|' + ch['name'])
")

for CHANNEL_INFO in $CHANNELS; do
  CHANNEL_ID=$(echo "$CHANNEL_INFO" | cut -d'|' -f1)
  CHANNEL_NAME=$(echo "$CHANNEL_INFO" | cut -d'|' -f2)

  echo "  Reading #${CHANNEL_NAME}..."

  # Navigate
  navigate_channel "$SERVER_ID" "$CHANNEL_ID"
  sleep 5

  # Read messages
  TMPFILE=$(mktemp)
  cd "$OPENCLI_DIR"
  node "$OPENCLI_DIR/dist/main.js" discord-app read --count 30 --format json > "$TMPFILE" 2>/dev/null || echo "[]" > "$TMPFILE"
  cd "$SCRIPT_DIR"

  # Process messages
  python3 - "$TMPFILE" "$DATA_DIR" "$CHANNEL_NAME" "$SINCE" "$OPENCLI_DIR" << 'PYEOF'
import json, sys, os, re, subprocess
from datetime import datetime

tmpfile = sys.argv[1]
data_dir = sys.argv[2]
channel_name = sys.argv[3]
since_str = sys.argv[4]
opencli_dir = sys.argv[5]

since_date = datetime.strptime(since_str, "%Y-%m-%d")

try:
    with open(tmpfile) as f:
        messages = json.load(f)
except:
    messages = []

# Deduplicate (Discord read returns doubles)
seen = set()
unique = []
for msg in messages:
    key = msg.get("Message", "")[:100] + msg.get("Time", "")
    if key not in seen:
        seen.add(key)
        unique.append(msg)

# Filter by date
filtered = []
for msg in unique:
    time_str = msg.get("Time", "")
    if not time_str:
        continue
    try:
        msg_date = datetime.fromisoformat(time_str.replace("Z", "+00:00"))
        if msg_date.replace(tzinfo=None) >= since_date:
            filtered.append(msg)
    except:
        continue

# For updates channel, extract tweet IDs and fetch full tweets
tweet_data = []
if channel_name == "updates":
    for msg in filtered:
        text = msg.get("Message", "")
        tweet_ids = re.findall(r'status/(\d+)', text)
        for tid in tweet_ids:
            try:
                # Unset CDP endpoint so twitter commands use browser bridge, not Discord
                env = os.environ.copy()
                env.pop("OPENCLI_CDP_ENDPOINT", None)
                result = subprocess.run(
                    ["node", os.path.join(opencli_dir, "dist/main.js"), "twitter", "thread", tid, "--format", "json"],
                    capture_output=True, text=True, timeout=60, cwd=opencli_dir, env=env
                )
                if result.returncode == 0:
                    tweets = json.loads(result.stdout)
                    for t in tweets:
                        if t.get("author", "").lower() in ["anthropicai", "claudeai"]:
                            tweet_data.append(t)
                else:
                    print(f"      tweet {tid}: failed - {result.stderr[:150]}")
            except Exception as e:
                print(f"      tweet {tid}: error - {e}")

output = {
    "channel": channel_name,
    "messages": filtered,
    "fetched_tweets": tweet_data
}

count = len(filtered)
tweet_count = len(tweet_data)
extra = f", {tweet_count} tweets fetched" if tweet_data else ""
print(f"    {count} messages in range{extra}")

with open(os.path.join(data_dir, f"discord_{channel_name}.json"), "w") as f:
    json.dump(output, f, indent=2, ensure_ascii=False)
PYEOF

  rm -f "$TMPFILE"
done

echo "  Discord fetch complete"
