#!/usr/bin/env bash
# Send a push to an iotPush topic with curl.
#
# Usage:
#   IOTPUSH_TOPIC=my-topic IOTPUSH_TOPIC_KEY=... ./send.sh "Backup finished" [-t title] [-p priority] [-c click_url]
#
# Env:
#   IOTPUSH_TOPIC      topic name (required)
#   IOTPUSH_TOPIC_KEY  the topic's API key (required for private topics, omit for public ones)
#   IOTPUSH_BASE       override the base URL (default https://www.iotpush.com)
#
# This uses the plain-text body plus header shortcuts (Title, Priority, Click).
# Header values must be ASCII; for non-ASCII titles send a JSON body instead
# (see ../python/send.py or ../node/send.mjs).
set -euo pipefail

BASE="${IOTPUSH_BASE:-https://www.iotpush.com}"
TOPIC="${IOTPUSH_TOPIC:?set IOTPUSH_TOPIC}"

MESSAGE="${1:?usage: send.sh \"message\" [-t title] [-p low|normal|high|urgent] [-c click_url]}"
shift
TITLE="" PRIORITY="" CLICK=""
while getopts "t:p:c:" opt; do
  case "$opt" in
    t) TITLE="$OPTARG" ;;
    p) PRIORITY="$OPTARG" ;;
    c) CLICK="$OPTARG" ;;
    *) exit 64 ;;
  esac
done

args=(-sS --fail-with-body -X POST "$BASE/api/push/$TOPIC"
      -H "Content-Type: text/plain; charset=utf-8" --data-binary "$MESSAGE")
[ -n "${IOTPUSH_TOPIC_KEY:-}" ] && args+=(-H "Authorization: Bearer $IOTPUSH_TOPIC_KEY")
[ -n "$TITLE" ]    && args+=(-H "Title: $TITLE")
[ -n "$PRIORITY" ] && args+=(-H "Priority: $PRIORITY")
[ -n "$CLICK" ]    && args+=(-H "Click: $CLICK")

# Prints the JSON response, which includes a receipt_id.
# On the Free plan, going over the monthly push limit returns HTTP 429.
curl "${args[@]}"
echo
