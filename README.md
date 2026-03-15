# Baxter v2

A self-hosted, fully local personal AI assistant running on n8n. Baxter lives in Telegram, understands text and voice, manages your tasks and calendar, remembers who you are, and gets smarter over time — all without sending your data to any external AI service.

---

## What Baxter can do

- **Converse** via text or voice message in Telegram
- **Remember** you — maintains a persistent profile (soul, user background, preferences, current focus) that shapes every response
- **Manage tasks, subtasks and projects** — create, update, complete and query via natural language
- **Set reminders** — fires Telegram alerts at the exact time you specify
- **Read and write Google Calendar** — check today's schedule, create events, update or delete them
- **Research** — web search via DuckDuckGo and Wikipedia lookups
- **Check weather** — real-time conditions for any location
- **Long-term memory** — conversation summaries are embedded and stored in Qdrant, retrieved semantically on every message
- **Daily briefing** — 8am Telegram message with weather, calendar events, upcoming tasks and reminders
- **Image generation** — optional ComfyUI integration

---

## Architecture

Baxter is built as a pipeline of n8n workflows, each with a single responsibility:

```
Telegram / Chat
      │
      ▼
a — Input               Auth check, message type routing, Whisper transcription
      │
      ▼
b — Divider             Classifies request (short_answer / long_answer / tool_use / job)
      │
      ▼
c — Orchestrator        Main agent — fetches user profile, builds system prompt,
      │                 runs tools (ProjectManager, CalendarManager, ResearchAgent,
      │                 LongTermMemory, ExecQuery, UpdateProfile)
      ▼
z — Communication       Routes response back as text or Qwen TTS voice audio
```

**Background workflows:**

| Workflow | Schedule | Purpose |
|----------|----------|---------|
| ReminderHeartbeat | Every minute | Checks `reminders` table, fires due alerts via Telegram |
| DailyBriefing | 08:00 daily | Sends weather + calendar + tasks + reminders summary |
| DailyHistorySummarizer | Hourly | Summarises new `message_history` rows and ingests into Qdrant |

---

## Infrastructure

| Service | Port | Description |
|---------|------|-------------|
| **n8n** | 5678 | Workflow automation — the brain |
| **Postgres** | 5432 | All structured data (messages, tasks, profile, reminders) |
| **Qdrant** | 6333 | Vector store for long-term semantic memory |
| **Ollama** | 11434 | Local LLM inference (qwen3.5:9b, llama3.2, nomic-embed-text) |
| **Whisper** | 5001 | Speech-to-text for voice messages |
| **Qwen TTS** | 8881 | Text-to-speech for voice responses |
| **ComfyUI** | 8188 | Image generation (optional, GPU only) |

---

## Quick Start

### Prerequisites

- Docker + Docker Compose
- NVIDIA GPU recommended (CPU fallback available)
- A Telegram bot token ([create one via BotFather](https://t.me/botfather))
- A Google Cloud project with Calendar API enabled (for calendar features)

### 1. Clone and run setup

```bash
git clone <your-repo-url>
cd baxter

bash setup.sh
```

`setup.sh` will:
- Create the required directory structure
- Copy `baxter_init.sql` into `postgres_init/` for automatic DB setup on first boot
- Download Whisper service files
- Generate a `.env` file with random secure keys
- Create the `local-bridge` Docker network
- Apply the database schema if Postgres is already running

### 2. Start services

```bash
# With NVIDIA GPU (recommended)
docker compose --profile gpu-nvidia up -d

# CPU only
docker compose --profile cpu up -d

# Include ComfyUI (GPU required)
docker compose --profile gpu-nvidia --profile comfyui up -d
```

### 3. Pull Ollama models

```bash
docker exec ollama ollama pull qwen3.5:9b
docker exec ollama ollama pull llama3.2:3b
docker exec ollama ollama pull nomic-embed-text
```

### 4. Import workflows into n8n

Open `http://localhost:5678`, then import each workflow JSON in this order:

1. `a-Baxter-v2-Input.json`
2. `b-Baxter-v2-Divider.json`
3. `c-Baxter-v2-Orchestrator.json`
4. `z-Baxter-v2-Communication.json`
5. `ReminderHeartbeat.json`
6. `DailyBriefing.json`
7. `DailyHistorySummarizer.json`

### 5. Add credentials in n8n

Go to **Settings → Credentials** and create:

| Credential | Used by |
|-----------|---------|
| Telegram API | Input, Communication, ReminderHeartbeat, DailyBriefing |
| Postgres | All workflows |
| Ollama | Orchestrator, DailyHistorySummarizer |
| Qdrant API | Orchestrator, DailyHistorySummarizer |
| Google Calendar OAuth2 | Orchestrator (CalendarManager), DailyBriefing |

For Google Calendar OAuth2 — always set it up through your public domain (e.g. `https://yourdomain.com`), not `localhost`, to avoid OAuth callback errors.

### 6. Activate workflows

Activate in this order (background workers first):

1. ReminderHeartbeat
2. DailyHistorySummarizer
3. DailyBriefing
4. a-Baxter-v2-Input (activates the Telegram webhook)
5. b-Baxter-v2-Divider
6. c-Baxter-v2-Orchestrator
7. z-Baxter-v2-Communication

### 7. First message

Send any message to your Telegram bot. Baxter will walk through a short onboarding flow to set up its identity and learn about you. This only happens once — all answers are saved to the `user_profile` table and used in every subsequent conversation.

To skip onboarding and seed your profile manually, uncomment the `INSERT` block in `baxter_init.sql` and re-run `bash setup.sh`.

---

## Database

All tables are defined in `baxter_init.sql`. The file is idempotent — safe to run multiple times without affecting existing data.

| Table | Purpose |
|-------|---------|
| `n8n_chat_histories` | Short-term rolling memory (n8n Postgres memory node) |
| `message_history` | Structured log of every user↔Baxter exchange |
| `baxter_memory_tracker` | Tracks last message ID ingested into Qdrant |
| `user_profile` | Soul, personality, preferences, onboarding state |
| `projects` | Top-level project containers |
| `tasks` | Individual tasks, linked to projects |
| `subtasks` | Child items of tasks |
| `reminders` | Time-based Telegram alerts |

To apply the schema manually to an already-running Postgres:

```bash
docker exec -i postgres psql -U $POSTGRES_USER -d $POSTGRES_DB < postgres_init/baxter_init.sql
```

---

## Memory Architecture

Baxter has two memory layers:

**Short-term** — the last 2 conversation turns are kept in `n8n_chat_histories` via the n8n Postgres memory node, giving the agent immediate conversational context.

**Long-term** — `DailyHistorySummarizer` runs hourly, takes all new rows from `message_history` since the last run, summarises them with `llama3.2:3b`, embeds the summary with `nomic-embed-text`, and upserts it into the `baxter_memory` Qdrant collection. The `baxter_memory_tracker` table records how far ingestion has reached. On every conversation turn, the Orchestrator queries Qdrant semantically and injects relevant past context into the agent.

---

## Environment Variables

`setup.sh` generates these automatically. Edit `.env` to override:

```bash
# PostgreSQL
POSTGRES_USER=n8n
POSTGRES_PASSWORD=<generated>
POSTGRES_DB=n8n

# n8n
N8N_ENCRYPTION_KEY=<generated>
N8N_USER_MANAGEMENT_JWT_SECRET=<generated>
WEBHOOK_URL=https://yourdomain.com/

# Ollama
OLLAMA_HOST=ollama:11434

# ComfyUI (optional)
USER_ID=1000
GROUP_ID=1000
```

⚠️ Back up your `.env` — the `N8N_ENCRYPTION_KEY` encrypts all stored credentials. Losing it means losing access to all credentials stored in n8n.

---

## Directory Structure

```
baxter/
├── setup.sh                  # Run once after cloning
├── baxter_init.sql            # Single source of truth for all DB tables
├── docker-compose.yml
├── .env                       # Generated by setup.sh, never commit this
├── postgres_init/
│   └── baxter_init.sql        # Copied here by setup.sh for Docker auto-init
├── postgres_storage/          # Postgres data volume (runtime, git-ignored)
├── n8n/
│   └── demo-data/
│       ├── credentials/
│       └── workflows/
├── whisper/                   # Downloaded by setup.sh
│   └── Dockerfile
├── qwen-tts/
│   └── Dockerfile
├── shared/                    # File exchange between host and n8n
└── comfyui_storage/           # ComfyUI state (optional)
```

---

## Common Commands

```bash
# View running containers
docker compose ps

# Follow logs for a specific service
docker compose logs -f n8n
docker compose logs -f ollama

# Restart a service
docker compose restart n8n

# Update all images
docker compose --profile gpu-nvidia pull
docker compose --profile gpu-nvidia up -d

# Rebuild custom images (Whisper, Qwen TTS)
docker compose build --no-cache whisper qwen-tts
docker compose up -d whisper qwen-tts

# Ollama model management
docker exec ollama ollama list
docker exec ollama ollama pull <model-name>
docker exec -it ollama ollama run qwen3.5:9b

# Export all n8n workflows and credentials
docker exec n8n n8n export:workflow --all --output=/data/shared/
docker exec n8n n8n export:credentials --all --output=/data/shared/
```

---

## Monitoring

```bash
# Resource usage across all containers
docker stats

# Specific services
docker stats n8n ollama postgres

# Disk usage by Docker
docker system df
docker system df -v

# Check container health
docker inspect --format='{{.State.Health.Status}}' n8n
docker inspect --format='{{.State.Health.Status}}' postgres

# Follow logs with timestamps
docker compose logs -f --timestamps n8n
docker compose logs --tail=100 ollama

# Save logs to file
docker compose logs > baxter-logs-$(date +%Y%m%d).log
```

---

## Updating Services

All images use `:latest` — pull and restart to update:

```bash
# Update everything
docker compose --profile gpu-nvidia pull
docker compose --profile gpu-nvidia up -d

# Update a specific service
docker compose pull n8n
docker compose up -d n8n

# Rebuild custom images after Dockerfile changes (Whisper, Qwen TTS)
docker compose build --no-cache whisper qwen-tts
docker compose up -d whisper qwen-tts
```

---

## Maintenance

### Clean up unused resources

```bash
# Remove stopped containers
docker container prune

# Remove unused images
docker image prune

# Remove unused volumes ⚠️ check before running
docker volume prune

# Remove everything unused ⚠️ very destructive
docker system prune -a

# Dry run — see what would be removed
docker system prune --dry-run

# Clear build cache only
docker builder prune -af
```

### Reset a specific service

```bash
# Restart without losing data
docker compose restart n8n

# Full stop, remove, recreate
docker compose stop n8n
docker compose rm -f n8n
docker compose up -d n8n

# Reset with a completely fresh volume ⚠️ deletes all n8n data
docker compose stop n8n
docker volume rm n8n_storage
docker compose up -d n8n
```

---

## Volume Management

```bash
# List all project volumes
docker volume ls | grep -E "n8n|postgres|ollama|qdrant"

# Inspect a volume
docker volume inspect ollama_storage

# Check volume size
docker system df -v | grep ollama_storage

# Browse volume contents
docker run --rm -v ollama_storage:/data alpine ls -lah /data

# Copy a file into a volume
docker run --rm \
  -v ollama_storage:/data \
  -v $(pwd):/local \
  alpine cp /local/myfile.txt /data/

# Copy a file out of a volume
docker run --rm \
  -v ollama_storage:/data \
  -v $(pwd):/local \
  alpine cp /data/myfile.txt /local/
```

---

```bash
# Database
docker exec postgres pg_dump -U n8n n8n > backup_$(date +%Y%m%d).sql

# Restore database
cat backup_20250315.sql | docker exec -i postgres psql -U n8n -d n8n

# Qdrant vector store
docker run --rm \
  -v qdrant_storage:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/qdrant-$(date +%Y%m%d).tar.gz -C /data .

# All volumes + .env
mkdir -p ~/backups/baxter-$(date +%Y%m%d)
for volume in n8n_storage postgres_storage ollama_storage qdrant_storage; do
  docker run --rm \
    -v ${volume}:/data \
    -v ~/backups/baxter-$(date +%Y%m%d):/backup \
    alpine tar czf /backup/${volume}.tar.gz -C /data .
done
cp .env ~/backups/baxter-$(date +%Y%m%d)/env.backup
```

---

## Troubleshooting

**Telegram bot not responding**
Check that `a-Baxter-v2-Input` is active and the Telegram credential is valid:
```bash
docker compose logs -f n8n | grep -i telegram
```

**OAuth callback error ("Unauthorized") for Google Calendar**
Always complete the OAuth flow through your public domain, not `localhost`. The redirect URI registered in Google Cloud Console must exactly match `https://yourdomain.com/rest/oauth2-credential/callback`.

**Ollama model not found**
```bash
docker exec ollama ollama list
docker exec ollama ollama pull qwen3.5:9b
```

**Network not found**
```bash
docker network create local-bridge
```

**GPU not detected**
```bash
docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi
```
If that fails, install or reinstall the NVIDIA Container Toolkit:
```bash
# Ubuntu/Debian
distribution=$(. /etc/os-release; echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list \
  | sudo tee /etc/apt/sources.list.d/nvidia-docker.list

sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo systemctl restart docker
```

**Port already in use**
```bash
sudo lsof -i :5678   # or whichever port
```

**Re-apply database schema after an update**
```bash
bash setup.sh
# setup.sh detects a running Postgres container and applies the schema automatically
```

---

## Links

- [n8n Documentation](https://docs.n8n.io/)
- [Ollama](https://ollama.ai/)
- [Qdrant](https://qdrant.tech/)
- [ComfyUI](https://github.com/comfyanonymous/ComfyUI)
- [Whisper (local fork)](https://github.com/maxvandop/local-whisper)
