#!/usr/bin/env bash
# Ask an Approve/Reject question on your phone and block until it is answered.
# Requires: curl and jq (https://jqlang.org/ — apt install jq / brew install jq).
#
# Usage:
#   IOTPUSH_API_KEY=iop_live_... ./ask-and-wait.sh "Deploy v2.4 to production?" [-t title] [-s timeout_seconds]
#   ./ask-and-wait.sh "Run the migration?" && ./migrate.sh
#
# Env:
#   IOTPUSH_API_KEY  ACCOUNT API key (iop_live_...) with scopes questions:ask + questions:read.
#                    Create it at https://www.iotpush.com/dashboard/settings -> API keys.
#                    A per-topic key will not work here.
#   IOTPUSH_TOPIC    optional topic name (optional if the account has one)
#   IOTPUSH_BASE     override the base URL (default https://www.iotpush.com)
#
# Exit codes:
#   0  approved          (the ONLY code that means "go ahead")
#   1  rejected
#   2  no decision: expired, cancelled or interrupted. No answer means NO.
#   3  error (HTTP error, e.g. 402 when the Free plan's approvals are used up)
set -uo pipefail

command -v jq >/dev/null || { echo "jq is required" >&2; exit 3; }

BASE="${IOTPUSH_BASE:-https://www.iotpush.com}"
KEY="${IOTPUSH_API_KEY:?set IOTPUSH_API_KEY (account key, iop_live_...)}"
QUESTION="${1:?usage: ask-and-wait.sh \"question\" [-t title] [-s timeout_seconds]}"
shift
TITLE="" TIMEOUT_S=300
while getopts "t:s:" opt; do
  case "$opt" in
    t) TITLE="$OPTARG" ;;
    s) TIMEOUT_S="$OPTARG" ;;
    *) exit 3 ;;
  esac
done

api() { # api METHOD PATH [JSON_BODY]
  local extra=()
  [ $# -ge 3 ] && extra=(-H "Content-Type: application/json" --data-binary "$3")
  curl -sS --fail-with-body --max-time 70 -X "$1" "$BASE$2" \
    -H "Authorization: Bearer $KEY" ${extra[@]+"${extra[@]}"}
}

body=$(jq -n --arg q "$QUESTION" --arg t "$TITLE" --arg topic "${IOTPUSH_TOPIC:-}" --argjson s "$TIMEOUT_S" \
  '{question: $q, kind: "confirm", timeout_s: $s}
   + (if $t != "" then {title: $t} else {} end)
   + (if $topic != "" then {topic: $topic} else {} end)')

if ! created=$(api POST /api/v1/questions "$body"); then
  echo "ask failed: $created" >&2
  exit 3
fi
qid=$(jq -r '.question_id' <<<"$created")
echo "asked $qid, waiting for an answer..." >&2

cancel() { api POST "/api/v1/questions/$qid/cancel" >/dev/null 2>&1 || true; }
trap 'cancel; echo "interrupted: no decision" >&2; exit 2' INT TERM

deadline=$(( $(date +%s) + TIMEOUT_S + 60 ))   # safety net; the server expires the question first
while :; do
  if ! q=$(api GET "/api/v1/questions/$qid/wait?timeout=30"); then
    echo "wait failed: $q" >&2
    exit 3
  fi
  status=$(jq -r '.status' <<<"$q")
  [ "$status" != "pending" ] && break
  if [ "$(date +%s)" -ge "$deadline" ]; then cancel; status="cancelled"; break; fi
done

action=$(jq -r '.answer.action_id // empty' <<<"$q")
if [ "$status" = "answered" ] && [ "$action" = "approve" ]; then
  echo "approved by $(jq -r '.answer.answered_by // "?"' <<<"$q")" >&2
  exit 0
elif [ "$status" = "answered" ]; then
  echo "rejected" >&2
  exit 1
else
  # expired / cancelled: nobody decided. Never treat this as approval.
  echo "no decision ($status): not proceeding" >&2
  exit 2
fi
