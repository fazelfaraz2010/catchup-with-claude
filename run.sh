#!/bin/bash
# run.sh — Main entry point: fetch data → generate newsletter with Claude
# Usage: ./run.sh [days_back]
# Example: ./run.sh 7

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DAYS_BACK="${1:-7}"

if [[ "$(uname)" == "Darwin" ]]; then
  SINCE=$(date -v-${DAYS_BACK}d +%Y-%m-%d)
else
  SINCE=$(date -d "$DAYS_BACK days ago" +%Y-%m-%d)
fi
UNTIL=$(date +%Y-%m-%d)
DATA_DIR="$SCRIPT_DIR/data/$UNTIL"
OUTPUT_DIR="$HOME/Desktop/Catchup with Claude"
mkdir -p "$OUTPUT_DIR"
OUTPUT_FILE="$OUTPUT_DIR/${UNTIL}.md"

echo "=========================================="
echo "  Anthropic Weekly Newsletter Generator"
echo "  Period: $SINCE to $UNTIL"
echo "=========================================="
echo ""

# Step 1: Fetch all tweets
echo "[1/3] Fetching tweets from all accounts..."
bash "$SCRIPT_DIR/fetch.sh" "$DAYS_BACK"
echo ""

# Step 2: Resolve links
echo "[2/4] Resolving links and fetching article titles..."
python3 "$SCRIPT_DIR/resolve-links.py" "$DATA_DIR"
echo ""

# Step 3: Compile all data into a single feed file
echo "[3/4] Compiling feed..."
FEED_FILE="$DATA_DIR/_feed.json"

python3 - "$DATA_DIR" "$FEED_FILE" << 'PYEOF'
import json, os, sys, glob

data_dir = sys.argv[1]
feed_file = sys.argv[2]

feed = []
for filepath in sorted(glob.glob(os.path.join(data_dir, "*.json"))):
    if os.path.basename(filepath).startswith("_"):
        continue
    with open(filepath) as f:
        account_data = json.load(f)
    feed.append(account_data)

with open(feed_file, "w") as f:
    json.dump(feed, f, indent=2, ensure_ascii=False)

# Stats
# Stats for twitter accounts
twitter_feeds = [a for a in feed if "handle" in a]
discord_feeds = [a for a in feed if "channel" in a]
total_threads = sum(len(a.get("threads", [])) for a in twitter_feeds)
total_standalone = sum(len(a.get("standalone", [])) for a in twitter_feeds)
total_retweets = sum(len(a.get("retweets", [])) for a in twitter_feeds)
total_discord_msgs = sum(len(a.get("messages", [])) for a in discord_feeds)
total_discord_tweets = sum(len(a.get("fetched_tweets", [])) for a in discord_feeds)
accounts_with_activity = sum(1 for a in twitter_feeds if a.get("threads") or a.get("standalone") or a.get("retweets"))

print(f"  {len(twitter_feeds)} Twitter accounts, {len(discord_feeds)} Discord channels")
print(f"  {accounts_with_activity} Twitter accounts had activity")
print(f"  {total_threads} threads, {total_standalone} standalone tweets, {total_retweets} retweets")
print(f"  {total_discord_msgs} Discord messages, {total_discord_tweets} tweets fetched from Discord links")
PYEOF

echo ""

# Step 4: Generate newsletter with Claude
echo "[4/4] Generating newsletter with Claude..."
echo ""

PROMPT_FILE="$SCRIPT_DIR/newsletter-prompt.md"
PROMPT=$(cat "$PROMPT_FILE")

# Build the Claude input
cat > "$DATA_DIR/_claude_input.md" << INPUTEOF
${PROMPT}

---

## Raw Data (${SINCE} to ${UNTIL})

The following is the raw tweet data from all tracked Anthropic accounts for this period.
Analyze this data and write the newsletter.

\`\`\`json
$(cat "$FEED_FILE")
\`\`\`
INPUTEOF

# Use Claude CLI to generate the newsletter
cat "$DATA_DIR/_claude_input.md" | claude --print > "$OUTPUT_FILE" 2>/dev/null

# Generate .docx
DOCX_FILE="$OUTPUT_DIR/catchup-with-claude-${UNTIL}.docx"
python3 "$SCRIPT_DIR/generate-docx.py" "$OUTPUT_FILE" "$DOCX_FILE"

# Email if --email flag passed
if [[ "${2:-}" == "--email" ]]; then
  echo "[5/5] Emailing newsletter..."
  python3 "$SCRIPT_DIR/send-email.py" "$DOCX_FILE" "$OUTPUT_FILE"
fi

echo ""
echo "=========================================="
echo "  Newsletter generated!"
echo "  Markdown: $OUTPUT_FILE"
echo "  Docx:     $DOCX_FILE"
echo "=========================================="
