#!/usr/bin/env bash
# Runs every example against a local mock of the iotPush API (tests/mock_server.py).
# Nothing here talks to the real service. Requires: bash, curl, jq, python3, node.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TMP="$(mktemp -d)"
LOG="$TMP/requests.jsonl"
MOCK_PID=""
PASS=0
FAIL=0

cleanup() { [ -n "$MOCK_PID" ] && kill "$MOCK_PID" 2>/dev/null; rm -rf "$TMP"; }
trap cleanup EXIT

ok()   { PASS=$((PASS + 1)); echo "  ok    $1"; }
bad()  { FAIL=$((FAIL + 1)); echo "  FAIL  $1"; }
check() { local d="$1"; shift; if "$@" >"$TMP/out" 2>&1; then ok "$d"; else bad "$d"; sed 's/^/        /' "$TMP/out"; fi; }
# expect "description" 'jq expression over the array of recorded requests'
expect() { if jq -se "$2" "$LOG" >/dev/null 2>&1; then ok "$1"; else bad "$1"; jq -sc '.' "$LOG" | sed 's/^/        /'; fi; }
expect_exit() { # expect_exit "description" CODE command...
  local d="$1" want="$2"; shift 2
  "$@" >"$TMP/out" 2>&1; local got=$?
  if [ "$got" -eq "$want" ]; then ok "$d (exit $got)"; else bad "$d (want exit $want, got $got)"; sed 's/^/        /' "$TMP/out"; fi
}
reset_log() { : >"$LOG"; }

start_mock() { # start_mock MODE
  [ -n "$MOCK_PID" ] && kill "$MOCK_PID" 2>/dev/null && wait "$MOCK_PID" 2>/dev/null
  : >"$TMP/port"
  MOCK_MODE="$1" MOCK_LOG="$LOG" python3 tests/mock_server.py >"$TMP/port" &
  MOCK_PID=$!
  for _ in $(seq 50); do [ -s "$TMP/port" ] && break; sleep 0.1; done
  [ -s "$TMP/port" ] || { echo "mock server did not start"; exit 1; }
  export IOTPUSH_BASE="http://127.0.0.1:$(head -1 "$TMP/port")"
  reset_log
}

TOPIC_ENV=(IOTPUSH_TOPIC=t1 IOTPUSH_TOPIC_KEY=tk_123)
ACCOUNT_ENV=(IOTPUSH_API_KEY=iop_live_test IOTPUSH_TOPIC=t1)

echo "== syntax"
for f in curl/*.sh pushover/*.sh tests/*.sh; do check "bash -n $f" bash -n "$f"; done
for f in python/*.py raspberry-pi/*.py tests/*.py; do
  check "py_compile $f" python3 -c 'import py_compile,sys; py_compile.compile(sys.argv[1], cfile=sys.argv[2], doraise=True)' "$f" "$TMP/x.pyc"
done
for f in node/*.mjs; do check "node --check $f" node --check "$f"; done
if python3 -c 'import yaml' 2>/dev/null; then
  yaml_ok() {
    python3 - "$1" <<'PY'
import sys, yaml
class L(yaml.SafeLoader): pass
L.add_constructor("!secret", lambda loader, node: "<secret>")
yaml.load(open(sys.argv[1]), Loader=L)
PY
  }
  for f in github-actions/*.yml home-assistant/*.yaml .github/workflows/*.yml; do check "yaml parses: $f" yaml_ok "$f"; done
else
  echo "  skip  YAML parse checks (PyYAML not installed)"
fi

echo "== send examples"
start_mock approve

expect_exit "curl/send.sh" 0 env "${TOPIC_ENV[@]}" curl/send.sh "hello" -t "Door" -p high -c "https://example.com/x"
grep -q r_test "$TMP/out" && ok "curl/send.sh prints receipt_id" || bad "curl/send.sh prints receipt_id"
expect "curl/send.sh: POST /api/push/t1, bearer topic key, text body, header shortcuts" \
  'length == 1 and (.[0] | .method == "POST" and .path == "/api/push/t1"
   and .headers.authorization == "Bearer tk_123" and .body == "hello"
   and .headers.title == "Door" and .headers.priority == "high" and .headers.click == "https://example.com/x")'

reset_log
expect_exit "curl/send.sh, public topic" 0 env -u IOTPUSH_TOPIC_KEY IOTPUSH_TOPIC=pub curl/send.sh "hi"
expect "curl/send.sh, public topic: no Authorization header" \
  'length == 1 and .[0].path == "/api/push/pub" and (.[0].headers | has("authorization") | not)'

for impl in "python3 python/send.py" "node node/send.mjs"; do
  reset_log
  # shellcheck disable=SC2086
  expect_exit "$impl" 0 env "${TOPIC_ENV[@]}" $impl "héllo" --title "Tür offen" --priority urgent --tags a,b --click "https://example.com/r"
  grep -q r_test "$TMP/out" && ok "$impl prints receipt_id" || bad "$impl prints receipt_id"
  expect "$impl: JSON body with message/title/priority/tags/click_url" \
    'length == 1 and (.[0] | .method == "POST" and .path == "/api/push/t1"
     and .headers.authorization == "Bearer tk_123" and (.headers["content-type"] | startswith("application/json"))
     and .json == {message: "héllo", title: "Tür offen", priority: "urgent", tags: "a,b", click_url: "https://example.com/r"})'
done

echo "== raspberry-pi/cpu_temp_alert.py"
reset_log
echo 85000 >"$TMP/temp"
PI_ENV=("${TOPIC_ENV[@]}" THERMAL_FILE="$TMP/temp" TEMP_THRESHOLD_C=80 STATE_FILE="$TMP/pi.last")
expect_exit "hot: alert" 0 env "${PI_ENV[@]}" python3 raspberry-pi/cpu_temp_alert.py
expect "hot: one high-priority push" \
  'length == 1 and .[0].path == "/api/push/t1" and .[0].json.priority == "high" and (.[0].json.message | test("85.0"))'
expect_exit "hot again: cooldown" 0 env "${PI_ENV[@]}" python3 raspberry-pi/cpu_temp_alert.py
expect "hot again: no second push during cooldown" 'length == 1'
reset_log; rm -f "$TMP/pi.last"; echo 45000 >"$TMP/temp"
expect_exit "cool: no alert" 0 env "${PI_ENV[@]}" python3 raspberry-pi/cpu_temp_alert.py
expect "cool: no push" 'length == 0'

echo "== pushover/migrate.sh"
reset_log
expect_exit "pushover/migrate.sh" 0 env "${TOPIC_ENV[@]}" pushover/migrate.sh "Disk almost full"
expect "pushover format: form POST to /api/1/messages.json with token=topic key, user=topic" \
  'length == 1 and (.[0] | .method == "POST" and .path == "/api/1/messages.json"
   and (.headers["content-type"] | startswith("application/x-www-form-urlencoded"))
   and ((.body | split("&") | map(split("=") | {(.[0]): .[1]}) | add) as $f
        | $f.token == "tk_123" and $f.user == "t1" and $f.message == "Disk+almost+full" and $f.priority == "1"))'

echo "== ask-and-wait examples"
ASKERS=("curl/ask-and-wait.sh" "python3 python/ask_and_wait.py" "node node/ask-and-wait.mjs")
for mode_exit in approve:0 reject:1 expired:2; do
  mode="${mode_exit%%:*}" want="${mode_exit##*:}"
  start_mock "$mode"
  for impl in "${ASKERS[@]}"; do
    reset_log
    # shellcheck disable=SC2086
    expect_exit "$impl [$mode]" "$want" env "${ACCOUNT_ENV[@]}" $impl "Deploy v2?" -t "Deploy"
    expect "$impl [$mode]: ask then wait until no longer pending" \
      'length == 3
       and (.[0] | .method == "POST" and .path == "/api/v1/questions"
            and .headers.authorization == "Bearer iop_live_test"
            and .json.question == "Deploy v2?" and .json.kind == "confirm" and .json.title == "Deploy"
            and .json.topic == "t1" and (.json.timeout_s >= 10 and .json.timeout_s <= 86400))
       and ([.[1:][] | .method == "GET" and .path == "/api/v1/questions/q_test/wait"
            and .headers.authorization == "Bearer iop_live_test"
            and ((.query.timeout | tonumber) <= 55)] | all)'
  done
done

start_mock approve
for impl in "${ASKERS[@]}"; do
  reset_log
  # shellcheck disable=SC2086
  env -u IOTPUSH_API_KEY $impl "Deploy?" >/dev/null 2>&1; rc=$?
  if [ "$rc" -ne 0 ] && [ ! -s "$LOG" ]; then ok "$impl without IOTPUSH_API_KEY refuses (exit $rc)"; else bad "$impl without IOTPUSH_API_KEY refuses (exit $rc)"; fi
done

echo "== esp32"
INO=esp32/iotpush_alert/iotpush_alert.ino
check "sketch verifies TLS with setCACert" grep -q 'client.setCACert(ISRG_ROOT_X1)' "$INO"
check "sketch never calls setInsecure()" bash -c "! sed 's://.*\$::' '$INO' | grep -q setInsecure"
if command -v openssl >/dev/null; then
  fp=$(sed -n '/BEGIN CERTIFICATE/,/END CERTIFICATE/p' "$INO" | openssl x509 -noout -fingerprint -sha256 | cut -d= -f2)
  [ "$fp" = "96:BC:EC:06:26:49:76:F3:74:60:77:9A:CF:28:C5:A7:CF:E8:A3:C0:AA:E1:1A:8F:FC:EE:05:C0:BD:DF:08:C6" ] \
    && ok "embedded certificate is ISRG Root X1 (SHA-256 fingerprint matches)" \
    || bad "embedded certificate fingerprint: $fp"
fi
if command -v arduino-cli >/dev/null; then
  check "arduino-cli compile (esp32:esp32:esp32)" arduino-cli compile --fqbn esp32:esp32:esp32 esp32/iotpush_alert
else
  echo "  skip  arduino-cli not installed; sketch not compiled"
fi

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
