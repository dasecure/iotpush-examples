#!/usr/bin/env node
// Ask an Approve/Reject question on your phone and block until it is answered.
// Node 18.3+ (built-in fetch, util.parseArgs), no dependencies.
//
// Usage:
//   IOTPUSH_API_KEY=iop_live_... node ask-and-wait.mjs "Deploy v2.4 to production?" [--title T] [--timeout 300]
//
// Env:
//   IOTPUSH_API_KEY  ACCOUNT API key (iop_live_...) with scopes questions:ask + questions:read,
//                    created at https://www.iotpush.com/dashboard/settings -> API keys.
//                    A per-topic key will not work here.
//   IOTPUSH_TOPIC    optional topic name (optional if the account has one)
//   IOTPUSH_BASE     override the base URL (default https://www.iotpush.com)
//
// Exit codes: 0 approved (the ONLY "go ahead"), 1 rejected,
//             2 no decision (expired / cancelled / interrupted), 3 error (e.g. HTTP 402 = approvals used up).
import { parseArgs } from "node:util";

const BASE = (process.env.IOTPUSH_BASE || "https://www.iotpush.com").replace(/\/+$/, "");
const KEY = process.env.IOTPUSH_API_KEY;

async function api(method, path, body) {
  const headers = { Authorization: `Bearer ${KEY}` };
  if (body !== undefined) headers["Content-Type"] = "application/json";
  const res = await fetch(BASE + path, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(70_000), // wait calls hold up to 55 s
  });
  const text = await res.text();
  if (!res.ok) throw new Error(`HTTP ${res.status} ${text}`);
  return JSON.parse(text);
}

const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    title: { type: "string", short: "t" },
    timeout: { type: "string", short: "s", default: "300" },
  },
});
if (!KEY || positionals.length !== 1) {
  console.error('usage: IOTPUSH_API_KEY=iop_live_... node ask-and-wait.mjs "question" [--title T] [--timeout 300]');
  process.exit(3);
}
const timeoutS = Number(values.timeout);

let q;
try {
  const created = await api("POST", "/api/v1/questions", {
    question: positionals[0],
    kind: "confirm",
    title: values.title,
    topic: process.env.IOTPUSH_TOPIC || undefined,
    timeout_s: timeoutS,
  });
  const qpath = `/api/v1/questions/${encodeURIComponent(created.question_id)}`;
  console.error(`asked ${created.question_id}, waiting for an answer...`);

  const cancel = () => api("POST", `${qpath}/cancel`).catch(() => {});
  process.on("SIGINT", async () => {
    await cancel();
    console.error("interrupted: no decision");
    process.exit(2);
  });

  const deadline = Date.now() + (timeoutS + 60) * 1000; // safety net; the server expires it first
  do {
    q = await api("GET", `${qpath}/wait?timeout=30`);
    if (q.status === "pending" && Date.now() > deadline) {
      await cancel();
      q = { status: "cancelled", answer: null };
    }
  } while (q.status === "pending");
} catch (err) {
  console.error("request failed:", err.message);
  process.exit(3);
}

if (q.status === "answered" && q.answer?.action_id === "approve") {
  console.error("approved by", q.answer.answered_by);
  process.exit(0);
} else if (q.status === "answered") {
  console.error("rejected");
  process.exit(1);
} else {
  // expired / cancelled: nobody decided. Never treat this as approval.
  console.error(`no decision (${q.status}): not proceeding`);
  process.exit(2);
}
