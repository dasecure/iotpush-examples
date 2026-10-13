#!/usr/bin/env bash
# Moving a script from Pushover to iotPush: change the URL and the two credentials.
#
# iotPush accepts the Pushover message format at /api/1/messages.json:
#   token = your iotPush topic API key
#   user  = your iotPush topic name
#   message, and optionally title, url, priority (-2..2)
#
# This works for your own scripts and libraries where you can set the URL.
# Apps with built-in Pushover support usually hard-code api.pushover.net,
# so they cannot simply be pointed here.
#
# Usage:
#   IOTPUSH_TOPIC=my-topic IOTPUSH_TOPIC_KEY=... ./migrate.sh "Disk almost full"
set -euo pipefail

BASE="${IOTPUSH_BASE:-https://www.iotpush.com}"
MESSAGE="${1:-Hello from a former Pushover script}"

# BEFORE (Pushover):
#   curl -s https://api.pushover.net/1/messages.json \
#     --data-urlencode "token=$PUSHOVER_APP_TOKEN" \
#     --data-urlencode "user=$PUSHOVER_USER_KEY" \
#     --data-urlencode "message=$MESSAGE"

# AFTER (iotPush):
curl -sS --fail-with-body "$BASE/api/1/messages.json" \
  --data-urlencode "token=${IOTPUSH_TOPIC_KEY:?set IOTPUSH_TOPIC_KEY (topic API key)}" \
  --data-urlencode "user=${IOTPUSH_TOPIC:?set IOTPUSH_TOPIC (topic name)}" \
  --data-urlencode "message=$MESSAGE" \
  --data-urlencode "title=Server" \
  --data-urlencode "priority=1" \
  --data-urlencode "url=https://www.iotpush.com/docs"
echo
