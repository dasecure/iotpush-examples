#!/usr/bin/env node
// Send a push to an iotPush topic. Node 18.3+ (built-in fetch, util.parseArgs), no dependencies.
//
// Usage:
//   IOTPUSH_TOPIC=my-topic IOTPUSH_TOPIC_KEY=... node send.mjs "Backup finished" \
//     [--title T] [--priority low|normal|high|urgent] [--tags a,b] [--click URL]
//
// Env:
//   IOTPUSH_TOPIC      topic name (required)
//   IOTPUSH_TOPIC_KEY  the topic's API key (required for private topics, omit for public ones)
//   IOTPUSH_BASE       override the base URL (default https://www.iotpush.com)
import { parseArgs } from "node:util";

const BASE = (process.env.IOTPUSH_BASE || "https://www.iotpush.com").replace(/\/+$/, "");

async function send(topic, message, { title, priority, tags, click_url, key } = {}) {
  const headers = { "Content-Type": "application/json" };
  if (key) headers.Authorization = `Bearer ${key}`;
  const res = await fetch(`${BASE}/api/push/${encodeURIComponent(topic)}`, {
    method: "POST",
    headers,
    // JSON body: non-ASCII titles are fine here. undefined fields are dropped.
    body: JSON.stringify({ message, title, priority, tags, click_url }),
  });
  const text = await res.text();
  // 429 = over the Free plan's monthly push limit
  if (!res.ok) throw new Error(`push failed: HTTP ${res.status} ${text}`);
  return JSON.parse(text);
}

const { values, positionals } = parseArgs({
  allowPositionals: true,
  options: {
    title: { type: "string", short: "t" },
    priority: { type: "string", short: "p" },
    tags: { type: "string" },
    click: { type: "string", short: "c" },
  },
});

const topic = process.env.IOTPUSH_TOPIC;
if (!topic || positionals.length !== 1) {
  console.error('usage: IOTPUSH_TOPIC=... node send.mjs "message" [--title T] [--priority P] [--tags a,b] [--click URL]');
  process.exit(64);
}

try {
  const result = await send(topic, positionals[0], {
    title: values.title,
    priority: values.priority,
    tags: values.tags,
    click_url: values.click,
    key: process.env.IOTPUSH_TOPIC_KEY,
  });
  console.log("sent, receipt_id:", result.receipt_id);
} catch (err) {
  console.error(err.message);
  process.exit(1);
}
