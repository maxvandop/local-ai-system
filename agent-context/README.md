# Agent Context — local-ai-system

This folder is the "memory" for AI coding agents working on this repo across sessions.
Read this before making any changes. Update it after significant work.

## What this repo is

Self-hosted personal AI assistant stack for **Max van Dop**, running on Docker Compose.
The assistant is called **Baxter**. It is accessible via **Telegram** (text + voice).

Pipeline: Telegram → `a-Baxter-v2-Input` → `c-Baxter-v2-Orchestrator-v8` → `z-Baxter-v2-Communication` → Telegram

---

## Stack overview

| Service | Image / Port | Purpose |
|---|---|---|
| **n8n** | `n8nio/n8n:latest` / `:5678` | Workflow engine, hosts Baxter |
| **postgres** | `pgvector/pgvector:pg16` / `:5432` | Persistent storage for all data |
| **qdrant** | `qdrant/qdrant` / `:6333` | Vector store (`baxter_memory` collection) |
| **ollama** | `ollama/ollama` / `:11434` | Local LLM host (`llama3.2`, `nomic-embed-text`, `gemma3`) |
| **llama.cpp** | custom / `:8082` | Main LLM inference, OpenAI-compatible API. Model: `google_gemma-4-E4B-it-Q8_0.gguf` |
| **whisper** | custom / — | Voice transcription |
| **comfyui** | custom / — | Image generation (profile: `comfyui` or `all-gpu`) |
| **qwen-tts** | custom / `:8005` | Text-to-speech |

All services run on `local-bridge` external Docker network.

---

## Key files

| File | What it does |
|---|---|
| `docker-compose.yml` | Defines all services. n8n mounts vault at `/data/vault:ro` |
| `.env` | All secrets and path variables. See section below |
| `setup.sh` | One-time setup: creates dirs, `.env` template, Docker network, applies DB schema |
| `n8n/workflows/c-Baxter-v2-Orchestrator-v8.json` | Main Baxter agent workflow |
| `n8n/workflows/a-Baxter-v2-Input.json` | Input handler (Telegram, voice) |
| `n8n/workflows/z-Baxter-v2-Communication.json` | Output/reply handler |
| `postgres_init/` | DB init SQL, runs on first postgres start |

---

## Required .env variables

```
POSTGRES_USER
POSTGRES_PASSWORD
POSTGRES_DB
N8N_ENCRYPTION_KEY
N8N_USER_MANAGEMENT_JWT_SECRET
WEBHOOK_URL
MODELS_PATH          # path to LLM model files on host, e.g. C:/Users/maxva/Models
VAULT_PATH           # path to Obsidian vault on host, e.g. C:/Users/maxva/Repositories/vault
COMFYUI_MODELS_PATH
COMFYUI_CUSTOM_NODES_PATH
```

---

## Obsidian vault integration

The vault (`VAULT_PATH`) is mounted into the n8n container at `/data/vault` (read-only).

Baxter has three vault-related nodes in the Orchestrator:

### 1. Vault Navigation (Code node — `n8n-nodes-base.code` typeVersion 2)
Runs at workflow start (not a tool). Reads `Maps/Navigation.md` via `fs.readFileSync`.
Output is `json.stdout`. Used by `BuildSystemPrompt` as `$('Vault Navigation').first().json.stdout`.

```js
const fs = require('fs');
const content = fs.readFileSync('/data/vault/Maps/Navigation.md', 'utf8');
return [{ json: { stdout: content } }];
```

### 2. ReadVaultNote (toolCode — `@n8n/n8n-nodes-langchain.toolCode`)
Agent calls this with a vault-relative path (e.g. `Atlas/Topics/AI.md`).
`query` = the path passed by the agent.

```js
const fs = require('fs');
const notePath = '/data/vault/' + query.trim();
try {
  return fs.readFileSync(notePath, 'utf8');
} catch(e) {
  return 'Error reading file: ' + e.message;
}
```

### 3. SearchVault (toolCode — `@n8n/n8n-nodes-langchain.toolCode`)
Agent calls this with a keyword. Recursively walks `/data/vault`, matches case-insensitively
against file content AND filename. Returns up to 20 vault-relative paths.
Uses pure `fs` — **do not use `child_process`/`execSync`**, it silently fails in the n8n sandbox.

```js
const fs = require('fs');
const path = require('path');
const keyword = query.trim().toLowerCase();
const vaultRoot = '/data/vault';
const matches = [];

function walk(dir) {
  let entries;
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch(e) { return; }
  for (const entry of entries) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full);
    } else if (entry.name.endsWith('.md')) {
      try {
        const text = fs.readFileSync(full, 'utf8');
        if (text.toLowerCase().includes(keyword) || entry.name.toLowerCase().includes(keyword)) {
          matches.push(full.replace(vaultRoot + '/', ''));
        }
      } catch(e) {}
    }
    if (matches.length >= 20) return;
  }
}

walk(vaultRoot);
return matches.length > 0 ? matches.join('\n') : 'No matching notes found.';
```

---

## n8n node type rules — CRITICAL

Only these node types can connect to an AI Agent via `ai_tool`:

- `@n8n/n8n-nodes-langchain.toolCode` — Custom Code Tool ✅
- `@n8n/n8n-nodes-langchain.toolWorkflow` — Call n8n Workflow Tool ✅
- `@n8n/n8n-nodes-langchain.agentTool` — Sub-agent ✅
- `n8n-nodes-base.postgresTool` — Postgres Tool ✅
- `n8n-nodes-base.httpRequestTool` — HTTP Request Tool ✅

**Do NOT invent tool variants of regular nodes. These do not exist:**
- `n8n-nodes-base.executeCommandTool` ❌
- `n8n-nodes-base.readWriteFileTool` ❌
- `n8n-nodes-base.codeTool` ❌

The `executeCommand` node (`n8n-nodes-base.executeCommand`) has been **removed from the n8n node picker** in recent versions. Use a Code node instead.

toolCode node parameters: `name`, `description`, `jsCode`. The agent input is available as `query`.
The `name` field is required — without it the agent can't call the tool.

---

## n8n sandbox limitations

Code nodes and toolCode nodes run in a sandboxed task runner.
- `require('fs')` ✅ works with `NODE_FUNCTION_ALLOW_BUILTIN=*` in docker-compose environment
- `require('path')` ✅ works
- `require('child_process')` / `execSync` ❌ silently fails — catch block fires, no error shown

`NODE_FUNCTION_ALLOW_BUILTIN=*` is already set in the `x-n8n` shared block in `docker-compose.yml`.

---

## Vault structure (brief)

Owner: **Max van Dop** — developer at Mendix/Siemens (Awards & APIs team)
Language: Dutch for personal/Atlas content, English for Efforts and technical notes

```
vault/
  Atlas/       # reference knowledge, topics
  Calendar/    # daily logs (YYYY-MM-DD.md)
  Efforts/     # active projects
  Maps/        # navigation/structural — start here
  Templates/
  _raw/        # unprocessed inbox
  _attachements/
```

Entry point for any agent: `Maps/Navigation.md`

---

## Workflow pipeline detail

Three workflows form the Baxter pipeline. They communicate via Postgres `message_history` and a shared input JSON format.

```
Telegram message
  → a-Baxter-v2-Input     (parses text/voice, writes to message_history, triggers Orchestrator)
  → c-Baxter-v2-Orchestrator-v8  (fetches profile, builds system prompt, runs Tools Agent)
  → z-Baxter-v2-Communication    (sends reply back to Telegram)
```

### Orchestrator internal flow

1. `SetVars` — extracts `ChannelID`, `MessageID`, `UserInput` from the trigger payload
2. `FetchUserProfile` — Postgres query on `user_profile` WHERE `channel_id`
3. `Vault Navigation` — Code node reads `/data/vault/Maps/Navigation.md` → `json.stdout`
4. `BuildSystemPrompt` — JS Code node that assembles the full system prompt from profile + vault navigation. Branches on `onboarding_step` (1–3 = onboarding, 0 = normal operation)
5. `Agent` — Tools Agent node with all tools attached via `ai_tool`
6. Post-agent: logs exchange to `message_history`, strips `RESPONSE:` prefix, forwards to Communication workflow

### Input payload format (from `task-schema.json`)

The Orchestrator receives tasks as JSON strings on `$json.input`:

```json
{
  "id": null,
  "name": "Hello",
  "type": "orchestrator",
  "status": "pending",
  "agent": "baxter-orchestrator",
  "requiresApproval": false,
  "prompts": {
    "user": "the user message",
    "core": "core-prompt-v1",
    "context": ""
  },
  "metadata": {
    "inputType": "text",
    "telegram": { "channelId": 8497733638, "messageId": 1495 }
  }
}
```

`type` is `"orchestrator"` for live messages, `"task"` for async background jobs run via `5-JobRunner.json`.

---

## PostgreSQL schema

All tables live in the `n8n` database. Schema is in `postgres_init/baxter_init.sql` — safe to re-run.

| Table | Purpose |
|---|---|
| `n8n_chat_histories` | Short-term rolling memory, written by n8n Postgres Memory node. Keyed by `session_id` |
| `message_history` | Structured log of every user↔Baxter exchange. `channel_id`, `user_input`, `agent_response` |
| `baxter_memory_tracker` | Single-row bookmark: tracks last `message_history.id` ingested to Qdrant by `DailyHistorySummarizer` |
| `user_profile` | Soul, personality, preferences, current focus. PK is `channel_id`. `onboarding_step` 1–3 = setup, 0 = done |
| `projects` | Top-level project containers. `status`: `active` / `on_hold` / `completed` |
| `tasks` | Individual tasks, optionally linked to a project. `priority`: `low` / `medium` / `high` / `critical` |
| `subtasks` | Child items of tasks. Cascade-deleted when parent task is removed |
| `reminders` | Time-based alerts. Polled every minute by `2-ReminderHeartbeat`. `sent` boolean prevents duplicates |
| `news_sources` | RSS feed list. Add/disable in pgAdmin. `category`: `technology` / `local` / `world` |
| `news_items` | Fetched articles. Cleaned up after 30 days. `ingested_to_qdrant` tracks Qdrant embedding status |

Seeded news sources: Hacker News, MIT Tech Review, The Verge, NOS Nieuws, RTV Rijnmond, BBC World.

User `channel_id` is `8497733638` (Max's Telegram ID).

---

## Workflow auto-import mechanism

The `n8n-import` service in `docker-compose.yml` runs once on stack start and imports all JSON files from `./n8n/workflows/` into n8n automatically:

```
n8n import:workflow --separate --input=/workflows
```

To deploy a workflow change: edit the JSON file, then run:
```powershell
docker compose up -d --force-recreate n8n n8n-import
```

Workflow JSON files follow n8n's export format. Key top-level fields: `name`, `nodes`, `connections`, `settings`. Node IDs must be unique UUIDs. The `connections` object maps `"NodeName": { "connection_type": [[{ "node": "TargetName", "type": "connection_type", "index": 0 }]] }`.

---

## Scheduled workflows

| File | Schedule | Purpose |
|---|---|---|
| `1-DailyBriefing_v2.json` | Morning | Sends daily summary to Telegram |
| `2-ReminderHeartbeat.json` | Every minute | Checks `reminders` table, fires due alerts |
| `3-DailyHistorySummarizer-v2.json` | Daily | Summarises `message_history`, embeds to Qdrant `baxter_memory` |
| `4-MemoryConsolidator.json` | Weekly | Consolidates Qdrant memories |
| `5-JobRunner.json` | Polling | Runs async background tasks created by Baxter via `CreateTask` tool |
| `6-SketchRenderer.json` | On-demand | Renders Mermaid diagrams, sends as image to Telegram |
| `7-NewsDigest.json` | Periodic | Fetches RSS feeds, stores to `news_items` |

---

## Planned next steps

- [ ] **Qdrant vault indexer** — new n8n workflow to embed all `.md` files into a `vault_knowledge` Qdrant collection using `nomic-embed-text`. Would enable semantic search on top of the current keyword search.
- [ ] **Vault write tool** — allow Baxter to append to daily notes or create new notes (currently mount is read-only)
- [ ] **SearchVault performance** — current full-walk approach is fine for small vaults; for large vaults consider a pre-built index
