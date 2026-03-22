# Anthropic Weekly

Weekly newsletter generator that tracks Anthropic team members on X/Twitter, fetches their tweets/threads/retweets, and uses Claude to write a polished newsletter.

## Project Structure

- `accounts.json` — Tracked accounts (15 Anthropic people + official accounts)
- `fetch.sh` — Fetches tweets via opencli (requires Chrome extension running)
- `newsletter-prompt.md` — Newsletter writing prompt for Claude
- `run.sh` — Main script: fetch -> compile -> generate newsletter
- `output/` — Generated newsletters by date
- `data/` — Raw tweet data by date

## Prerequisites

- opencli installed and built at `~/opencli`
- opencli Browser Bridge Chrome extension loaded and connected
- Chrome open and logged into X/Twitter
- Claude CLI available (`claude` command)

## Usage

```bash
cd ~/Desktop/anthropic-weekly

# Generate this week's newsletter (last 7 days)
./run.sh

# Custom time range (last 14 days)
./run.sh 14

# Just fetch data without generating
./fetch.sh 7
```

## How Thread Detection Works

1. Search each account's tweets with date range via opencli
2. Sort tweets by ID and cluster ones posted in rapid succession (within ~10B ID range)
3. Clusters of 2+ tweets = self-reply thread
4. Reconstruct full thread via `opencli twitter thread` on the 2nd tweet
5. This catches tweets that search misses (search can skip ~40-50% of thread tweets)

## Adding/Removing Accounts

Edit `accounts.json`. Each account needs:
- `handle` — X/Twitter handle (no @)
- `name` — Display name
- `role` — Their role at Anthropic
- `tier` — Priority tier (1-6, lower = more important)

## Scheduling via Cowork

You can schedule this to run weekly via Claude Cowork:
"Every Sunday at 9am, run ./run.sh in ~/Desktop/anthropic-weekly and save the output"
