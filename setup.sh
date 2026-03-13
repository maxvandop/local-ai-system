#!/bin/bash
# =============================================================================
# Baxter v2 — Setup Script
# Run once after cloning the repo, safe to re-run at any time.
# =============================================================================

set -e

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║          Baxter v2 — Setup               ║"
echo "╚══════════════════════════════════════════╝"
echo ""

# ─── 1. Directory structure ──────────────────────────────────────────────────

echo "📁 Creating directory structure..."
mkdir -p n8n/demo-data/credentials
mkdir -p n8n/demo-data/workflows
mkdir -p postgres_init
mkdir -p postgres_storage
mkdir -p shared
mkdir -p whisper
mkdir -p qwen-tts
echo "✓ Directories ready"

# ─── 2. Database init script ─────────────────────────────────────────────────
# baxter_init.sql is the single source of truth for all Baxter tables.
# Postgres automatically runs every *.sql file in /docker-entrypoint-initdb.d/
# on first container boot. For existing installs, step 6 applies it manually.

echo ""
echo "📝 Copying database init script..."
if [ -f "baxter_init.sql" ]; then
    cp baxter_init.sql postgres_init/baxter_init.sql
    echo "✓ baxter_init.sql copied to postgres_init/"
else
    echo "⚠️  baxter_init.sql not found in the repo root."
    echo "   Make sure it is committed alongside setup.sh and re-run."
    exit 1
fi

# ─── 3. Whisper service files ────────────────────────────────────────────────

echo ""
echo "📝 Setting up Whisper service..."
if [ ! -f whisper/api_server.py ]; then
    echo "  Downloading api_server.py..."
    curl -sSL https://raw.githubusercontent.com/maxvandop/local-whisper/main/api_server.py \
        -o whisper/api_server.py
fi
if [ ! -f whisper/Dockerfile ]; then
    echo "  Downloading Dockerfile..."
    curl -sSL https://raw.githubusercontent.com/maxvandop/local-whisper/main/dockerfile \
        -o whisper/Dockerfile
fi
if [ ! -f whisper/.gitignore ]; then
    echo "  Downloading .gitignore..."
    curl -sSL https://raw.githubusercontent.com/maxvandop/local-whisper/main/.gitignore \
        -o whisper/.gitignore
fi
echo "✓ Whisper service ready"

# ─── 4. Environment file ─────────────────────────────────────────────────────

echo ""
if [ ! -f .env ]; then
    echo "📝 Generating .env file..."

    N8N_ENCRYPTION_KEY=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    N8N_JWT_SECRET=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    POSTGRES_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)

    cat > .env << EOF
# ── PostgreSQL ────────────────────────────────────────────
POSTGRES_USER=n8n
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=n8n

# ── n8n ──────────────────────────────────────────────────
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
N8N_USER_MANAGEMENT_JWT_SECRET=${N8N_JWT_SECRET}
WEBHOOK_URL=http://localhost:5678/

# ── Ollama ────────────────────────────────────────────────
OLLAMA_HOST=ollama:11434

# ── ComfyUI (GPU image generation, optional) ─────────────
USER_ID=1000
GROUP_ID=1000
EOF

    echo "✓ .env created with generated keys"
    echo "⚠️  IMPORTANT: Back up your .env — these keys cannot be regenerated."

else
    echo "🔍 .env exists — checking for missing variables..."

    MISSING_VARS=()
    grep -q "^POSTGRES_USER="                   .env || MISSING_VARS+=("POSTGRES_USER=n8n")
    grep -q "^POSTGRES_PASSWORD="               .env || MISSING_VARS+=("POSTGRES_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)")
    grep -q "^POSTGRES_DB="                     .env || MISSING_VARS+=("POSTGRES_DB=n8n")
    grep -q "^N8N_ENCRYPTION_KEY="              .env || MISSING_VARS+=("N8N_ENCRYPTION_KEY=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)")
    grep -q "^N8N_USER_MANAGEMENT_JWT_SECRET="  .env || MISSING_VARS+=("N8N_USER_MANAGEMENT_JWT_SECRET=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)")
    grep -q "^WEBHOOK_URL="                     .env || MISSING_VARS+=("WEBHOOK_URL=http://localhost:5678/")
    grep -q "^OLLAMA_HOST="                     .env || MISSING_VARS+=("OLLAMA_HOST=ollama:11434")
    grep -q "^USER_ID="                         .env || MISSING_VARS+=("USER_ID=1000")
    grep -q "^GROUP_ID="                        .env || MISSING_VARS+=("GROUP_ID=1000")

    if [ ${#MISSING_VARS[@]} -gt 0 ]; then
        echo "  Adding missing variables:"
        for var in "${MISSING_VARS[@]}"; do
            echo "    + $var"
            echo "$var" >> .env
        done
        echo "✓ .env updated"
    else
        echo "✓ All required variables present"
    fi
fi

# ─── 5. Docker network ───────────────────────────────────────────────────────

echo ""
echo "🔧 Checking Docker network..."
if docker network inspect local-bridge >/dev/null 2>&1; then
    echo "✓ Network 'local-bridge' already exists"
else
    docker network create local-bridge
    echo "✓ Network 'local-bridge' created"
fi

# ─── 6. Apply database schema ────────────────────────────────────────────────
# If Postgres is already running (re-run scenario), apply baxter_init.sql now.
# On a fresh install this is a no-op — Postgres hasn't started yet and the
# file in postgres_init/ will be picked up automatically on first boot.

echo ""
echo "🗄️  Applying database schema..."

source .env

if docker ps --format '{{.Names}}' | grep -q "^postgres$"; then
    echo "  Postgres container is running — applying schema now..."
    docker exec -i postgres psql -U "${POSTGRES_USER}" -d "${POSTGRES_DB}" \
        < postgres_init/baxter_init.sql \
        && echo "✓ Schema applied successfully" \
        || echo "⚠️  Schema apply failed — check the output above for errors"
else
    echo "  Postgres not running yet — schema will be applied automatically on first boot"
    echo "  To apply manually later:"
    echo "    docker exec -i postgres psql -U \$POSTGRES_USER -d \$POSTGRES_DB < postgres_init/baxter_init.sql"
fi

# ─── Done ────────────────────────────────────────────────────────────────────

echo ""
echo "╔══════════════════════════════════════════╗"
echo "║           Setup complete  ✅             ║"
echo "╚══════════════════════════════════════════╝"
echo ""
echo "Next steps:"
echo ""
echo "  1. Start services:"
echo "       GPU:  docker compose --profile gpu-nvidia up -d"
echo "       CPU:  docker compose --profile cpu up -d"
echo ""
echo "  2. Import workflows into n8n:"
echo "       http://localhost:5678"
echo ""
echo "  3. Add credentials in n8n:"
echo "       - Telegram API"
echo "       - Google Calendar OAuth2"
echo "       - Ollama  (http://ollama:11434)"
echo "       - Qdrant  (http://qdrant:6333)"
echo ""
echo "  4. (Optional) Seed your profile to skip onboarding:"
echo "       Uncomment the INSERT block in postgres_init/baxter_init.sql"
echo "       then re-run:  bash setup.sh"
echo ""
echo "Services:"
echo "  n8n        →  http://localhost:5678"
echo "  Postgres   →  localhost:5432"
echo "  Qdrant     →  http://localhost:6333"
echo "  Ollama     →  http://localhost:11434"
echo "  Whisper    →  http://localhost:5001"
echo "  Qwen TTS   →  http://localhost:8881"
echo "  ComfyUI    →  http://localhost:8188"
echo ""