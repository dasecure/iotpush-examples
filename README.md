# iotPush examples

Copy-paste examples for [iotPush](https://www.iotpush.com), a DaSecure Solutions LLC
product. iotPush sends a message to a **topic** with one HTTP request and delivers it
to the topic's subscribers through the iotPush app (iOS/Android), email or webhook.
It can also ask you a question on your phone and hand the answer back to the script,
CI job or AI agent that is waiting for it.

## 60-second quick start

Create a topic at [iotpush.com](https://www.iotpush.com), then:

```bash
curl https://www.iotpush.com/api/push/YOUR_TOPIC \
  -H "Authorization: Bearer YOUR_TOPIC_KEY" \
  -H "Content-Type: text/plain" \
  --data-binary "Backup finished"
```

The plain-text body is the message. Public topics need no `Authorization` header.
The response JSON includes a `receipt_id`.

## Examples

| Path | What it shows |
| --- | --- |
| [`curl/send.sh`](curl/send.sh) | Send a push with curl, using the `Title` / `Priority` / `Click` header shortcuts |
| [`curl/ask-and-wait.sh`](curl/ask-and-wait.sh) | Ask Approve/Reject and block; exits 0 only on approve (curl + jq) |
| [`python/send.py`](python/send.py) | Send a JSON push, standard library only (Python 3.9+) |
| [`python/ask_and_wait.py`](python/ask_and_wait.py) | Ask and wait, standard library only |
| [`node/send.mjs`](node/send.mjs) | Send a JSON push with built-in `fetch`, no dependencies (Node 18.3+) |
| [`node/ask-and-wait.mjs`](node/ask-and-wait.mjs) | Ask and wait with built-in `fetch` |
| [`esp32/`](esp32/) | ESP32 sketch: push when a GPIO goes HIGH, TLS verified with `setCACert` |
| [`raspberry-pi/`](raspberry-pi/) | CPU temperature alert with cooldown, plus a systemd timer |
| [`github-actions/notify-on-failure.yml`](github-actions/notify-on-failure.yml) | Push when a CI job fails, with a link to the run |
| [`home-assistant/configuration.yaml`](home-assistant/configuration.yaml) | `rest_command` plus an example automation |
| [`pushover/migrate.sh`](pushover/migrate.sh) | Move a Pushover script to iotPush's Pushover-format endpoint |
| [`mcp/`](mcp/) | Connect AI agents (Claude Code, Cursor, others) to the iotPush MCP server |

Every script reads its settings from environment variables. None contains a real key.

| Variable | Used by |
| --- | --- |
| `IOTPUSH_TOPIC` | topic name |
| `IOTPUSH_TOPIC_KEY` | the topic's API key, for sending to private topics |
| `IOTPUSH_API_KEY` | an **account** API key (`iop_live_...`) for ask-and-wait |
| `IOTPUSH_BASE` | base URL override, default `https://www.iotpush.com` (the tests point it at a local mock) |

## The API in brief

**Send:** `POST https://www.iotpush.com/api/push/{topic}`

- Plain-text body, or `Content-Type: application/json` with `message`, `title`,
  `priority` (`low` | `normal` | `high` | `urgent`), `tags` (`"a,b"` or an array),
  `click_url`, `idempotency_key`.
- Header shortcuts for plain-text sends: `Title`, `Priority`, `Tags`, `Click`.
  Header values must be ASCII, so put non-ASCII titles in a JSON body.
- Private topics: `Authorization: Bearer <topic API key>`.

**Ask and wait:** needs an account API key (`iop_live_...`) with the scopes
`questions:ask` and `questions:read`, created at
[Dashboard → Settings → API keys](https://www.iotpush.com/dashboard/settings).
A per-topic key will not work.

1. `POST /api/v1/questions` with `question`, and optionally `title`, `kind`, `topic`,
   `timeout_s` (10–86400, default 300) and `idempotency_key`. Returns `question_id`.
2. `GET /api/v1/questions/{question_id}/wait?timeout=30` (up to 55 s). Repeat while
   `status` is `pending`.
3. `POST /api/v1/questions/{question_id}/cancel` withdraws it.

`kind` is `confirm` (Approve/Reject, the default; `answer.action_id` is `approve` or
`reject`), `select` (send `choices`: 2–4 `{"id", "label"}` objects; `answer.action_id`
is the chosen id) or `input` (free text in `answer.text`).

### Ask and wait: no answer means no

A question ends as `answered`, `expired` or `cancelled`. **Only an explicit approval
means go ahead.** An expired or cancelled question means nobody decided, so treat it
as "do not proceed", never as approval. Every ask-and-wait example here exits 0 only
on approve.

## Free plan limits

1 topic, 100 pushes a month and 20 approvals a month, no card required. Over the push
limit, sends return HTTP 429; over the approval limit, asks return HTTP 402. See
[pricing](https://www.iotpush.com/pricing) for the Solo and Team plans.

## More

- Docs: https://www.iotpush.com/docs
- MCP server for AI agents: https://www.iotpush.com/docs/mcp
- Apple Shortcuts gallery: https://www.iotpush.com/shortcuts
- Android (HTTP Shortcuts, Tasker, NFC): https://www.iotpush.com/android
- Integrations: https://www.iotpush.com/integrations
- n8n: the community node [`n8n-nodes-iotpush`](https://www.npmjs.com/package/n8n-nodes-iotpush)
  adds an iotPush node and an iotPush Trigger node (self-hosted n8n: Settings → Community Nodes).
- Pricing: https://www.iotpush.com/pricing

## Tests

`tests/run.sh` runs every curl, Python and Node example against a local mock of the
API (`tests/mock_server.py`) and checks paths, methods, headers, JSON fields and exit
codes. It never contacts iotpush.com. Requires bash, curl, jq, python3 and node.

```bash
bash tests/run.sh
```

## License

MIT. Copyright (c) 2026 DaSecure Solutions LLC. See [LICENSE](LICENSE).
