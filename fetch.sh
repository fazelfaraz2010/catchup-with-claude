#!/bin/bash
# fetch.sh — Fetch tweets, threads, and retweets for all tracked accounts
# Usage: ./fetch.sh [days_back]
# Example: ./fetch.sh 7

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
OPENCLI_DIR="$HOME/opencli"
DAYS_BACK="${1:-7}"

# Calculate date range
if [[ "$(uname)" == "Darwin" ]]; then
  SINCE=$(date -v-${DAYS_BACK}d +%Y-%m-%d)
else
  SINCE=$(date -d "$DAYS_BACK days ago" +%Y-%m-%d)
fi
UNTIL=$(date +%Y-%m-%d)

echo "=== Anthropic Weekly Fetch ==="
echo "Period: $SINCE to $UNTIL"
echo ""

# Create data directory for this run
DATA_DIR="$SCRIPT_DIR/data/$UNTIL"
mkdir -p "$DATA_DIR"

# Read Twitter-only accounts (skip discord-sourced brand accounts)
ACCOUNTS=$(python3 -c "
import json
with open('$SCRIPT_DIR/accounts.json') as f:
    data = json.load(f)
for a in data['accounts']:
    if a.get('source', 'twitter') == 'twitter':
        print(a['handle'])
")

for HANDLE in $ACCOUNTS; do
  echo "--- Fetching @${HANDLE} ---"

  TMPFILE=$(mktemp)
  TMPFILE_RT=$(mktemp)

  # Fetch original tweets
  node "$OPENCLI_DIR/dist/main.js" twitter search "from:${HANDLE} since:${SINCE} until:${UNTIL}" \
    --limit 50 --format json 2>/dev/null > "$TMPFILE" || echo "[]" > "$TMPFILE"

  # Fetch including retweets
  node "$OPENCLI_DIR/dist/main.js" twitter search "from:${HANDLE} include:nativeretweets since:${SINCE} until:${UNTIL}" \
    --limit 50 --format json 2>/dev/null > "$TMPFILE_RT" || echo "[]" > "$TMPFILE_RT"

  # Process: detect threads, separate retweets, rank by engagement
  python3 - "$TMPFILE" "$TMPFILE_RT" "$HANDLE" "$OPENCLI_DIR" "$DATA_DIR" << 'PYEOF'
import json, subprocess, sys, os

tmpfile = sys.argv[1]
tmpfile_rt = sys.argv[2]
handle = sys.argv[3]
opencli_dir = sys.argv[4]
data_dir = sys.argv[5]
THRESHOLD = 10_000_000_000

try:
    with open(tmpfile) as f:
        tweets = json.load(f)
except:
    tweets = []

try:
    with open(tmpfile_rt) as f:
        rt_tweets = json.load(f)
except:
    rt_tweets = []

# Separate retweets
retweets = [t for t in rt_tweets if t.get("text", "").startswith("RT @")]

# Filter originals to this author only
tweets = [t for t in tweets if t.get("author", "").lower() == handle.lower()]

output = {"handle": handle, "threads": [], "standalone": [], "retweets": retweets}

if not tweets:
    print(f"  No original tweets from @{handle}")
    with open(os.path.join(data_dir, f"{handle}.json"), "w") as f:
        json.dump(output, f, indent=2, ensure_ascii=False)
    sys.exit(0)

tweets.sort(key=lambda x: int(x["id"]))

# Cluster by ID proximity to detect threads
clusters = []
standalone = []
current = [tweets[0]]

for i in range(1, len(tweets)):
    gap = int(tweets[i]["id"]) - int(tweets[i - 1]["id"])
    if gap < THRESHOLD:
        current.append(tweets[i])
    else:
        if len(current) > 1:
            clusters.append(current)
        else:
            standalone.append(current[0])
        current = [tweets[i]]

if len(current) > 1:
    clusters.append(current)
else:
    standalone.append(current[0])

# Reconstruct threads using twitter thread command
for cluster in clusters:
    reply_id = cluster[1]["id"]
    try:
        result = subprocess.run(
            ["node", os.path.join(opencli_dir, "dist/main.js"), "twitter", "thread", reply_id, "--format", "json"],
            capture_output=True, text=True, timeout=30, cwd=opencli_dir
        )
        if result.returncode == 0:
            thread_tweets = json.loads(result.stdout)
            thread_tweets = [t for t in thread_tweets if t.get("author", "").lower() == handle.lower()]
            thread_tweets.sort(key=lambda x: int(x["id"]))
            output["threads"].append({
                "tweet_count": len(thread_tweets),
                "url": thread_tweets[0].get("url", "") if thread_tweets else "",
                "tweets": thread_tweets
            })
        else:
            output["threads"].append({
                "tweet_count": len(cluster),
                "url": cluster[0].get("url", ""),
                "tweets": cluster,
                "note": "partial"
            })
    except Exception as e:
        output["threads"].append({
            "tweet_count": len(cluster),
            "url": cluster[0].get("url", ""),
            "tweets": cluster,
            "note": f"partial - {str(e)}"
        })

# Sort standalone by engagement
standalone.sort(key=lambda x: int(x.get("likes", 0)), reverse=True)
output["standalone"] = standalone

# Summary
thread_count = len(output["threads"])
standalone_count = len(output["standalone"])
rt_count = len(output["retweets"])
print(f"  @{handle}: {thread_count} threads, {standalone_count} standalone, {rt_count} retweets")

# Save
with open(os.path.join(data_dir, f"{handle}.json"), "w") as f:
    json.dump(output, f, indent=2, ensure_ascii=False)
PYEOF

  rm -f "$TMPFILE" "$TMPFILE_RT"
done

# Fetch Discord channels (for brand accounts: @AnthropicAI, @claudeai)
echo ""
bash "$SCRIPT_DIR/fetch-discord.sh" "$DATA_DIR" "$SINCE"

echo ""
echo "=== Fetch complete ==="
echo "Data saved to: $DATA_DIR"
