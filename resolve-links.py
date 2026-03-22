#!/usr/bin/env python3
"""Resolve t.co links in fetched tweet data and optionally fetch page titles."""

import json, sys, os, re, glob
import urllib.request
import ssl

data_dir = sys.argv[1]

# SSL context that doesn't verify (t.co redirects)
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

def resolve_tco(url, timeout=5):
    """Follow t.co redirect to get the real URL."""
    try:
        req = urllib.request.Request(url, method='HEAD', headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
            return resp.url
    except Exception:
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
                return resp.url
        except Exception:
            return url

def get_page_title(url, timeout=5):
    """Fetch the page title from a URL."""
    try:
        req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as resp:
            html = resp.read(8192).decode('utf-8', errors='ignore')
            match = re.search(r'<title[^>]*>(.*?)</title>', html, re.IGNORECASE | re.DOTALL)
            if match:
                title = match.group(1).strip()
                # Clean up common title suffixes
                for sep in [' | ', ' - ', ' — ', ' – ']:
                    if sep in title:
                        title = title.split(sep)[0].strip()
                return title
    except Exception:
        pass
    return None

total_resolved = 0
total_titles = 0

for filepath in sorted(glob.glob(os.path.join(data_dir, "*.json"))):
    basename = os.path.basename(filepath)
    if basename.startswith("_"):
        continue

    with open(filepath) as f:
        data = json.load(f)

    # Collect all tweets from threads, standalone, retweets, fetched_tweets
    all_tweets = []
    for thread in data.get("threads", []):
        all_tweets.extend(thread.get("tweets", []))
    all_tweets.extend(data.get("standalone", []))
    all_tweets.extend(data.get("retweets", []))
    all_tweets.extend(data.get("fetched_tweets", []))

    # Also handle discord messages
    for msg in data.get("messages", []):
        text = msg.get("Message", "")
        tco_links = re.findall(r'https://t\.co/\S+', text)
        for tco in tco_links:
            real_url = resolve_tco(tco)
            if real_url != tco:
                msg["Message"] = msg["Message"].replace(tco, real_url)
                total_resolved += 1

    for tweet in all_tweets:
        text = tweet.get("text", "")
        tco_links = re.findall(r'https://t\.co/\S+', text)
        if not tco_links:
            continue

        resolved_links = []
        for tco in tco_links:
            real_url = resolve_tco(tco)
            if real_url != tco:
                tweet["text"] = tweet["text"].replace(tco, real_url)
                total_resolved += 1

            # Get page title for non-image, non-tweet links
            if not any(x in real_url for x in ['pic.twitter', 'pbs.twimg', '/photo/', '/video/', 'x.com/i/status']):
                title = get_page_title(real_url)
                if title:
                    resolved_links.append({"url": real_url, "title": title})
                    total_titles += 1

        if resolved_links:
            tweet["resolved_links"] = resolved_links

    with open(filepath, "w") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)

print(f"  Resolved {total_resolved} links, fetched {total_titles} page titles")
