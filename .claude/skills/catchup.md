---
name: catchup
description: Run the Catchup with Claude newsletter pipeline — fetches tweets from Anthropic accounts, reads Discord channels, resolves links, generates newsletter, and outputs a formatted .docx
user_invocable: true
---

# Catchup with Claude Newsletter

## Prerequisites Check
Before running, verify:
1. Chrome is open with the OpenCLI Browser Bridge extension active and logged into X/Twitter
2. Discord desktop app is running with CDP enabled (if not, launch it with: `/Applications/Discord.app/Contents/MacOS/Discord --remote-debugging-port=9333`)
3. OpenCLI is built at `~/opencli`

If any prerequisite is missing, tell the user what to open/launch and wait.

## Steps

1. `cd ~/Desktop/anthropic-weekly`
2. Run the full pipeline: `bash ./run.sh 7`
   - This fetches tweets from 13 Anthropic accounts on X (last 7 days)
   - Reads 3 Discord channels (announcements, events, updates)
   - Resolves t.co links and fetches article titles
   - Compiles all data into a feed
   - Generates the newsletter markdown using Claude
3. Generate the formatted Word doc: `python3 generate-docx.py output/$(date +%Y-%m-%d).md ~/Downloads/catchup-with-claude-$(date +%Y-%m-%d).docx`
4. Tell the user the .docx is in their Downloads folder and offer to open it

## Optional flags
- User can specify a different time range: `./run.sh 14` for last 14 days
- If the user wants to re-run just the generation (data already fetched): regenerate from the existing `data/` directory without re-fetching
