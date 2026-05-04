# Baxter — Feature Roadmap

Ordered roughly by dependency and value. Items marked 🔍 need further scoping before implementation.

---

## 1. Async Task System — Improvements

**Current state:**
- `agent_tasks` table exists with a well-designed schema: `parent_task_id`, `previous_task_id`, `next_task_id`, `depends_on` (JSONB array of UUIDs), `subtasks` (JSONB array), `requires_approval`, `prompts` (JSONB: user/core/context)
- `5-JobRunner.json` polls for `status = 'pending' AND type = 'task'` every cycle, calls `_BaxterCore` sub-workflow, writes result back
- `CreateTask` tool is functional — the agent calls it to queue background tasks. The INSERT uses `COALESCE`/`NULLIF` fallbacks on all `$fromAI()` fields so partial tool calls (where the LLM omits args) still produce valid rows. `prompts.user` is populated with the actual user message from SetVars.
- **Gap 1:** JobRunner only picks up `type = 'task'` — orchestrator tasks (`type = 'orchestrator'`) that need to plan and spawn subtasks have no runner
- **Gap 2:** `depends_on` is stored but never checked — tasks start regardless of whether their dependencies completed
- **Gap 3:** `prompts.context` is passed through as-is with no enrichment — the agent has no awareness of sibling tasks, parent goal, or what already ran
- **Gap 4:** No retry or iterative loop mechanism — if a task fails or returns a low-quality result it just ends

**Planned improvements:**

### 1a. Orchestrator task runner
Add a second branch in JobRunner (or a separate `5b-OrchestratorRunner.json`) that picks up `type = 'orchestrator'` tasks. The orchestrator agent's job is:
1. Receive the high-level goal from `prompts.user`
2. Plan 2–5 subtasks with clear scope, write them to `agent_tasks` with `parent_task_id` set and `depends_on` chained correctly
3. Mark itself `completed` once all subtasks are queued

### 1b. Dependency-aware scheduling
Before starting a task, JobRunner should check: all UUIDs in `depends_on` have `status = 'completed'`. If not, skip and try next pending task. Simple SQL addition.

### 1c. Richer context injection
When building the task prompt, inject:
- Parent task name and goal (from `parent_task_id` lookup)
- Completed sibling results (SELECT result FROM agent_tasks WHERE parent_task_id = X AND status = 'completed')
- This prevents each subtask running blind and allows downstream tasks to build on upstream output

### 1d. Iterative / self-correcting tasks
For research tasks: after the agent produces a result, a lightweight "judge" step checks quality. If the result contains phrases like "I could not find", "no results", or is under a word threshold → requeue with an enriched prompt that includes what was tried. Cap retries at 3 with a `retry_count` column.

Alternatively, within a single task: the agent calls a web search tool, evaluates the results, and decides whether to search again with a different query before concluding. This requires the agent to have an explicit "am I done?" decision step — achievable with a simple prompt instruction and a structured output check.

**Key guardrail:** Always set a hard cap on iterations (max 3). Include in every task prompt: "If after 3 attempts you cannot find a satisfactory answer, return what you have and explain why." Never let the agent silently loop.

---

## 2. Vault Write — ✅ Done

`WriteVaultNote` toolCode node writes to `Atlas/Baxter/` only. See README for implementation details.

---

## 3. Baxter as Claude Code Manager

**Concept:** Baxter creates an `agent_task` with `agent = 'claude-code'`, which JobRunner picks up and instead of running the LLM agent, it shells out to Claude Code CLI with the task instructions as the prompt.

**Implementation path:**
1. Add a new branch in JobRunner: if `agent = 'claude-code'`, run a Code node that executes `claude --print "<instructions>"` via `execSync` (note: this runs in the n8n container, not the toolCode sandbox — `child_process` IS available in regular Code nodes)
2. Claude Code needs to be installed in the n8n container — requires a custom Dockerfile extending `n8nio/n8n:latest`
3. The working directory / repo to operate on needs to be mounted into n8n as a volume
4. Output (stdout) is written back to `agent_tasks.result` and reported to Telegram

**Considerations:**
- Claude Code CLI requires an Anthropic API key — add `ANTHROPIC_API_KEY` to `.env`
- Security: Claude Code can execute arbitrary commands. Scope the mounted volume carefully (read-write only for specific repos, not the whole filesystem)
- Cost: Claude Code uses Anthropic API credits, unlike the local LLM. Gate it behind `requires_approval = true` for expensive operations

---

## 4. Better Web Search — ✅ Done

**Implemented:** SearXNG (self-hosted) + Jina AI Reader, both wired into Research Agent.

- **SearXNG** (`searxng/searxng` container, port 8888/8080) — meta-search returning URLs + snippets as JSON. `SearXNG` HTTP Request Tool in `_BaxterCore` calls `http://searxng:8080/search?q={query}&format=json`. Config: `searxng/settings.yml` (JSON format enabled, rate limiter off).
- **JinaReader** — `JinaReader` HTTP Request Tool calls `https://r.jina.ai/{url}` to fetch full page content as clean markdown. No API key needed.

The Research Agent now has the full pipeline: DuckDuckGo/SearXNG for URL discovery → JinaReader for full content retrieval → Wikipedia for reference. DuckDuckGo kept alongside SearXNG for redundancy.

**Potential future upgrade:** Firecrawl (self-hosted) for JS-heavy sites that Jina struggles with.

---

## 5. Useful Community Nodes (langchain keyword search)

The npm registry blocked direct scraping, but based on known well-maintained packages:

| Package | What it adds | Fit for Baxter |
|---|---|---|
| `n8n-nodes-browserless` | Headless Chrome scraping | ✅ Good for reading paywalled pages or JS-heavy sites |
| `n8n-nodes-firecrawl` | Web scraping → clean markdown | ✅ Strong upgrade for ResearchAgent web reading |
| `n8n-nodes-mcp` | MCP client/server | ✅ Opens the entire MCP tool ecosystem (filesystem, GitHub, etc.) |
| `n8n-nodes-qdrant` (community) | Extended Qdrant ops | 🔍 Only if built-in Qdrant node becomes limiting |
| `n8n-nodes-replicate` | Image/audio/video generation via Replicate API | 🔍 Only if ComfyUI proves insufficient |

**Note:** n8n has `N8N_COMMUNITY_PACKAGES_ALLOW_TOOL_USAGE=true` already set, so community nodes can be used as AI tools directly.

---

## 6. Vision for Baxter

**How to give Baxter vision:**

### Option A — Swap main LLM to a multimodal model (recommended)
Replace `google_gemma-4-E4B-it-Q8_0.gguf` with a vision-capable GGUF model served by the same llama.cpp server. Good candidates:
- `llava-v1.6-mistral-7b.Q4_K_M.gguf` — lightweight, fast
- `Qwen2-VL-7B-Instruct-Q4_K_M.gguf` — better quality, still fits in 8GB
The llama.cpp server already has `--n-gpu-layers 99` and `--ctx-size 16384` — just swap the model and mount path.

Images would be sent via Telegram as photo messages. The Input workflow already receives Telegram updates — it would need to extract the `file_id`, download the photo via Telegram Bot API, convert to base64, and pass it to the LLM in the message content array (OpenAI vision format).

### Option B — Dedicated vision tool (parallel to main LLM)
Keep the main LLM as-is. Add an HTTP Request Tool that POSTs an image to a separate vision endpoint (e.g. a second llama.cpp instance running LLaVA, or Ollama with `llava` model). The main agent calls this tool when it receives an image.

**Option A is cleaner** — no extra container, no tool-calling overhead for vision. The cost is losing the current model for text-only tasks (though Qwen2-VL is competitive on text too).

---

## 7. Gaps vs a Cloud AI Assistant

Comparing Baxter to a well-configured ChatGPT/Claude setup:

| Gap | Severity | Bridgeable? |
|---|---|---|
| No persistent file/code context across sessions | High | ✅ Partly solved by vault notes + Qdrant. Full solution: Claude Code integration (item 3) |
| Web search quality | Medium | ✅ Item 4 above |
| No vision | Medium | ✅ Item 6 above |
| Single-LLM, no model routing | Medium | 🔍 Route simple tasks to a fast small model, complex to larger. Requires a classifier step |
| No real-time data (stocks, live sports, etc.) | Low | ✅ HTTP Request Tool to specific APIs |
| No voice output | Low | ✅ qwen-tts is already in the stack — wire it into the Communication workflow |
| Long-context degradation (16k ctx limit) | Medium | 🔍 Summarise older context before injecting. DailyHistorySummarizer already partially addresses this |
| No email/calendar write access | Low | ✅ Google Calendar write already works. Email send: add Gmail node |

**Highest-value gaps to bridge first:** web search quality (fast, free) → vision (one model swap) → Claude Code manager (unlocks autonomous coding tasks).

---

## 8. Daily Briefing Schedule Fix — ✅ Done

Added `GENERIC_TIMEZONE=Europe/Amsterdam` and `TZ=Europe/Amsterdam` to the `x-n8n` shared block in `docker-compose.yml`. All scheduled workflows now trigger at correct Amsterdam local time. Container clock shows `CEST` (UTC+2). Briefing is currently set to `triggerAtHour: 8` (08:00 Amsterdam time).
