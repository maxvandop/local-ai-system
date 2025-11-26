# Migration Guide: Transfer Local AI System to Another Machine

This guide walks you through copying your entire Local AI System (images + volumes) to another machine.

## 📋 Prerequisites

- Source machine: Fully built and running Local AI System
- Target machine: Docker and Docker Compose installed
- Transfer method: USB drive, network share, or cloud storage (you'll need ~20-30 GB)

---

## 🎯 Part 1: Export from Source Machine

### Step 1: Stop All Services

```bash
cd ~/Repositories/local-ai-system
docker compose --profile all-gpu down
```

### Step 2: Export Docker Images

Create a directory for exports:
```bash
mkdir -p ~/local-ai-export
cd ~/local-ai-export
```

Export all images:
```bash
# Export public images
docker save -o n8n-postgres-qdrant.tar \
  n8nio/n8n:latest \
  postgres:16-alpine \
  qdrant/qdrant

docker save -o ollama.tar \
  ollama/ollama:latest

docker save -o comfyui.tar \
  ghcr.io/lecode-official/comfyui-docker:latest

# Export custom-built images (these are the big ones you just built)
docker save -o whisper.tar \
  local-ai-system-whisper:latest

docker save -o kitten-tts.tar \
  local-ai-system-kitten-tts-server:latest
```

**Note:** If your custom image names are different, check with:
```bash
docker images | grep -E "whisper|kitten"
```

### Step 3: Export Docker Volumes

Export all persistent data:

```bash
# N8N workflows and data
docker run --rm \
  -v n8n_storage:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/n8n_storage.tar.gz -C /data .

# PostgreSQL database
docker run --rm \
  -v postgres_storage:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/postgres_storage.tar.gz -C /data .

# Ollama models (this will be large - 4+ GB)
docker run --rm \
  -v ollama_storage:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/ollama_storage.tar.gz -C /data .

# Qdrant vector database
docker run --rm \
  -v qdrant_storage:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/qdrant_storage.tar.gz -C /data .

# HuggingFace model cache (for TTS)
docker run --rm \
  -v hf_cache:/data \
  -v $(pwd):/backup \
  alpine tar czf /backup/hf_cache.tar.gz -C /data .
```

### Step 4: Verify Export Files

```bash
ls -lh ~/local-ai-export
```

You should see:
```
n8n-postgres-qdrant.tar    (~500 MB)
ollama.tar                 (~500 MB)
comfyui.tar                (~2 GB)
whisper.tar                (~2 GB)
kitten-tts.tar             (~2 GB)
n8n_storage.tar.gz         (~100 MB)
postgres_storage.tar.gz    (~50 MB)
ollama_storage.tar.gz      (~4+ GB - contains your models)
qdrant_storage.tar.gz      (~100 MB)
hf_cache.tar.gz            (~1-2 GB)
```

**Total size:** ~15-20 GB (depending on models)

### Step 5: Transfer Files

Copy the entire `~/local-ai-export` folder to your target machine using:
- USB drive
- Network share (`scp`, `rsync`)
- Cloud storage (Google Drive, Dropbox)

**Example using SCP:**
```bash
scp -r ~/local-ai-export user@target-machine:/home/user/
```

---

## 🎯 Part 2: Import on Target Machine

### Step 1: Prepare Target Machine

```bash
# Clone your GitHub repository
git clone https://github.com/YOUR_USERNAME/local-ai-system.git
cd local-ai-system

# Create Docker network
docker network create local-ai-network

# Copy .env file from source or create new one
cp .env.example .env
# Edit .env with your settings
```

### Step 2: Import Docker Images

Navigate to where you copied the export files:
```bash
cd ~/local-ai-export  # or wherever you copied them
```

Load all images:
```bash
# Load public images
docker load -i n8n-postgres-qdrant.tar
docker load -i ollama.tar
docker load -i comfyui.tar

# Load custom images
docker load -i whisper.tar
docker load -i kitten-tts.tar
```

Verify images loaded:
```bash
docker images
```

### Step 3: Create Empty Volumes

Create the volume structure (Docker will create them):
```bash
docker volume create n8n_storage
docker volume create postgres_storage
docker volume create ollama_storage
docker volume create qdrant_storage
docker volume create hf_cache
```

### Step 4: Import Volume Data

Restore all volumes:

```bash
# Restore N8N data
docker run --rm \
  -v n8n_storage:/data \
  -v $(pwd):/backup \
  alpine tar xzf /backup/n8n_storage.tar.gz -C /data

# Restore PostgreSQL database
docker run --rm \
  -v postgres_storage:/data \
  -v $(pwd):/backup \
  alpine tar xzf /backup/postgres_storage.tar.gz -C /data

# Restore Ollama models (this takes a while)
docker run --rm \
  -v ollama_storage:/data \
  -v $(pwd):/backup \
  alpine tar xzf /backup/ollama_storage.tar.gz -C /data

# Restore Qdrant database
docker run --rm \
  -v qdrant_storage:/data \
  -v $(pwd):/backup \
  alpine tar xzf /backup/qdrant_storage.tar.gz -C /data

# Restore HuggingFace cache
docker run --rm \
  -v hf_cache:/data \
  -v $(pwd):/backup \
  alpine tar xzf /backup/hf_cache.tar.gz -C /data
```

### Step 5: Start Services

```bash
cd ~/local-ai-system
docker compose --profile all-gpu up -d
```

### Step 6: Verify Everything Works

```bash
# Check all containers are running
docker compose ps

# Check logs
docker compose logs -f

# Access services
# N8N: http://localhost:5678
# ComfyUI: http://localhost:8188
# Ollama: http://localhost:11434
```

---

## 🤖 Automated Migration Scripts

### Export Script (Source Machine)

Create `export-all.sh`:
```bash
#!/bin/bash
set -e

EXPORT_DIR=~/local-ai-export
echo "📦 Exporting Local AI System to $EXPORT_DIR"

# Create export directory
mkdir -p $EXPORT_DIR
cd $EXPORT_DIR

# Stop services
echo "⏸️  Stopping services..."
cd ~/Repositories/local-ai-system
docker compose --profile all-gpu down

# Export images
echo "💾 Exporting Docker images..."
cd $EXPORT_DIR
docker save -o n8n-postgres-qdrant.tar n8nio/n8n:latest postgres:16-alpine qdrant/qdrant
docker save -o ollama.tar ollama/ollama:latest
docker save -o comfyui.tar ghcr.io/lecode-official/comfyui-docker:latest
docker save -o whisper.tar local-ai-system-whisper:latest
docker save -o kitten-tts.tar local-ai-system-kitten-tts-server:latest

# Export volumes
echo "💾 Exporting volumes..."
docker run --rm -v n8n_storage:/data -v $(pwd):/backup alpine tar czf /backup/n8n_storage.tar.gz -C /data .
docker run --rm -v postgres_storage:/data -v $(pwd):/backup alpine tar czf /backup/postgres_storage.tar.gz -C /data .
docker run --rm -v ollama_storage:/data -v $(pwd):/backup alpine tar czf /backup/ollama_storage.tar.gz -C /data .
docker run --rm -v qdrant_storage:/data -v $(pwd):/backup alpine tar czf /backup/qdrant_storage.tar.gz -C /data .
docker run --rm -v hf_cache:/data -v $(pwd):/backup alpine tar czf /backup/hf_cache.tar.gz -C /data .

echo "✅ Export complete!"
echo "📂 Files are in: $EXPORT_DIR"
echo "📊 Total size:"
du -sh $EXPORT_DIR
```

### Import Script (Target Machine)

Create `import-all.sh`:
```bash
#!/bin/bash
set -e

IMPORT_DIR=~/local-ai-export
echo "📥 Importing Local AI System from $IMPORT_DIR"

# Load images
echo "💾 Loading Docker images..."
cd $IMPORT_DIR
docker load -i n8n-postgres-qdrant.tar
docker load -i ollama.tar
docker load -i comfyui.tar
docker load -i whisper.tar
docker load -i kitten-tts.tar

# Create volumes
echo "📦 Creating volumes..."
docker volume create n8n_storage
docker volume create postgres_storage
docker volume create ollama_storage
docker volume create qdrant_storage
docker volume create hf_cache

# Restore volumes
echo "💾 Restoring volume data..."
docker run --rm -v n8n_storage:/data -v $(pwd):/backup alpine tar xzf /backup/n8n_storage.tar.gz -C /data
docker run --rm -v postgres_storage:/data -v $(pwd):/backup alpine tar xzf /backup/postgres_storage.tar.gz -C /data
docker run --rm -v ollama_storage:/data -v $(pwd):/backup alpine tar xzf /backup/ollama_storage.tar.gz -C /data
docker run --rm -v qdrant_storage:/data -v $(pwd):/backup alpine tar xzf /backup/qdrant_storage.tar.gz -C /data
docker run --rm -v hf_cache:/data -v $(pwd):/backup alpine tar xzf /backup/hf_cache.tar.gz -C /data

# Create network
echo "🔌 Creating Docker network..."
docker network create local-ai-network 2>/dev/null || echo "Network already exists"

echo "✅ Import complete!"
echo "🚀 Now run: cd ~/local-ai-system && docker compose --profile all-gpu up -d"
```

Make scripts executable:
```bash
chmod +x export-all.sh import-all.sh
```

---

## 📝 Tips & Notes

### Selective Export
If you only want specific services, export only those volumes:
```bash
# Only N8N and Ollama
docker run --rm -v n8n_storage:/data -v $(pwd):/backup alpine tar czf /backup/n8n_storage.tar.gz -C /data .
docker run --rm -v ollama_storage:/data -v $(pwd):/backup alpine tar czf /backup/ollama_storage.tar.gz -C /data .
```

### Compression
For better compression (slower but smaller):
```bash
# Use higher compression
docker run --rm -v ollama_storage:/data -v $(pwd):/backup alpine tar czf /backup/ollama_storage.tar.gz -C /data . --use-compress-program="gzip -9"
```

### Windows-Specific Notes
On Windows with Git Bash, use Windows paths:
```bash
EXPORT_DIR=/c/temp/local-ai-export
mkdir -p $EXPORT_DIR
```

### Verify Data Integrity
After import, verify volumes:
```bash
docker run --rm -v ollama_storage:/data alpine ls -lah /data
```

---

## 🆘 Troubleshooting

### "No such volume" error
Make sure volumes were created:
```bash
docker volume ls | grep -E "n8n|postgres|ollama|qdrant|hf_cache"
```

### Import fails with "not a tar archive"
File may be corrupted during transfer. Verify checksums:
```bash
# On source
md5sum ollama_storage.tar.gz > checksums.txt

# On target
md5sum -c checksums.txt
```

### Services won't start after import
Check logs:
```bash
docker compose logs postgres
docker compose logs n8n
```

### Out of space
Check available space before export:
```bash
df -h
```

---

## ✅ Verification Checklist

After migration, verify:
- [ ] All containers running: `docker compose ps`
- [ ] N8N accessible at http://localhost:5678
- [ ] N8N workflows intact
- [ ] Ollama models available: `docker exec ollama ollama list`
- [ ] ComfyUI accessible at http://localhost:8188
- [ ] Postgres data intact
- [ ] No error logs: `docker compose logs`

---

**Estimated Time:** 
- Export: 30-60 minutes (depending on data size)
- Transfer: Varies by method
- Import: 30-60 minutes

**Storage Required:** 
- 20-30 GB free space on both machines
- Transfer medium with 20+ GB capacity