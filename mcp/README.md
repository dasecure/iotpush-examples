# iotPush MCP server (for AI agents)

Let an AI agent notify you on your phone, or ask you a question and wait for your answer.

- **Endpoint:** `https://mcp.iotpush.com/mcp` (Streamable HTTP)
- **Auth:** `Authorization: Bearer iop_live_...` (an account API key from
  https://www.iotpush.com/dashboard/settings -> API keys), or MCP OAuth in clients that
  support it: a browser page opens where you paste your API key once.
- **Docs:** https://www.iotpush.com/docs/mcp

## Configure your client

**Claude Code**

```bash
claude mcp add --transport http iotpush https://mcp.iotpush.com/mcp --header "Authorization: Bearer iop_live_..."
```

**Cursor** (`~/.cursor/mcp.json`) or any client with remote HTTP support

```json
{
  "mcpServers": {
    "iotpush": {
      "url": "https://mcp.iotpush.com/mcp",
      "headers": { "Authorization": "Bearer iop_live_..." }
    }
  }
}
```

**stdio-only clients** (bridged with [`mcp-remote`](https://www.npmjs.com/package/mcp-remote))

```json
{
  "mcpServers": {
    "iotpush": {
      "command": "npx",
      "args": ["-y", "mcp-remote", "https://mcp.iotpush.com/mcp", "--header", "Authorization:Bearer iop_live_..."]
    }
  }
}
```

## Tools

| Tool | What it does |
| --- | --- |
| `send_notification` | Send a push to one of your topics |
| `ask_user` | Ask you a question on your phone |
| `wait_for_answer` | Wait for the answer, up to 55 s per call; call it again in a loop while the question is pending |
| `cancel_question` | Withdraw a question |
| `list_topics` | List your topics |
| `send_pushover_notification` | Send using the Pushover message format |

## The rule: no answer means no

When an agent asks before doing something, it must only proceed on an explicit
approval. A question that **expired** or was **cancelled** means nobody made a
decision. Treat it as "do not proceed", never as approval.

A good instruction to give your agent:

> Before deleting data, deploying, or spending money, use iotPush `ask_user` and loop
> `wait_for_answer` until the status is no longer pending. Only continue if the answer
> is "approve". If it is rejected, expired or cancelled, stop and tell me.
