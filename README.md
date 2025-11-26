# Local AI System

A comprehensive Docker-based local AI infrastructure combining workflow automation, LLM inference, speech processing, and image generation capabilities.

## 🚀 Quick Start

```bash
# 1. Clone the repository
git clone <your-repo-url>
cd local-ai-system

# 2. Run the setup script
bash setup.sh

# 3. Configure your environment
cp .env.example .env
# Edit .env with your settings

# 4. Create the network
docker network create local-bridge

# 5. Start services (choose your profile)
docker compose --profile all up -d
docker compose --profile all-gpu up -d
```

## 📦 Services Included

| Service | Port | Profile | Description |
|---------|------|---------|-------------|
| **N8N** | 5678 | `n8n` | Workflow automation platform |
| **Postgres** | 5432 | `n8n` | Database for N8N |
| **Qdrant** | 6333 | `n8n` | Vector database |
| **Ollama** | 11434 | `ollama-cpu`/`ollama-gpu` | LLM inference engine |
| **Whisper** | 5001 | `whisper` | Speech-to-text |
| **ComfyUI** | 8188 | `comfyui` | Image generation UI |
| **Kitten TTS** | 8005 | `tts` | Text-to-speech |

## 🎯 Profile Usage

Start only the services you need using profiles:

```bash
# N8N workflow automation only
docker compose --profile n8n up -d

# N8N + Ollama (CPU)
docker compose --profile n8n --profile ollama-cpu up -d

# Everything with GPU support
docker compose --profile all-gpu up -d

# Everything (CPU where applicable)
docker compose --profile all up -d

# Specific combinations
docker compose --profile n8n --profile whisper --profile ollama-gpu up -d
```

### Available Profiles

- **`n8n`** - N8N, PostgreSQL, Qdrant
- **`ollama-cpu`** - Ollama with CPU support
- **`ollama-gpu`** - Ollama with NVIDIA GPU support
- **`whisper`** - Whisper speech-to-text
- **`comfyui`** - ComfyUI image generation (GPU)
- **`tts`** - Kitten TTS text-to-speech (GPU)
- **`all`** - All services (CPU fallbacks)
- **`all-gpu`** - All services with GPU support

## ⚙️ Configuration

### Environment Variables

Copy `.env.example` to `.env` and configure:

```bash
cp .env.example .env
```

**Required variables:**
- `POSTGRES_USER` - PostgreSQL username
- `POSTGRES_PASSWORD` - PostgreSQL password
- `POSTGRES_DB` - Database name
- `N8N_ENCRYPTION_KEY` - N8N encryption key (generate with `openssl rand -hex 32`)
- `N8N_USER_MANAGEMENT_JWT_SECRET` - JWT secret (generate with `openssl rand -hex 32`)

**ComfyUI paths:**
- `COMFYUI_MODELS_PATH` - Path to your ComfyUI models
- `COMFYUI_CUSTOM_NODES_PATH` - Path to your custom nodes

### Directory Structure

```
local-ai-system/
├── docker-compose.yml
├── .env
├── README.md
├── n8n/
│   └── demo-data/
│       ├── credentials/
│       └── workflows/
├── whisper/
│   └── Dockerfile
├── kitten-tts/
│   ├── Dockerfile
│   ├── config.yaml
│   ├── outputs/
│   └── logs/
├── comfyui/
└── shared/
```

## 🖥️ GPU Support

### NVIDIA GPU Requirements

1. **Install NVIDIA Container Toolkit:**
```bash
# Ubuntu/Debian
distribution=$(. /etc/os-release;echo $ID$VERSION_ID)
curl -s -L https://nvidia.github.io/nvidia-docker/gpgkey | sudo apt-key add -
curl -s -L https://nvidia.github.io/nvidia-docker/$distribution/nvidia-docker.list | sudo tee /etc/apt/sources.list.d/nvidia-docker.list

sudo apt-get update && sudo apt-get install -y nvidia-container-toolkit
sudo systemctl restart docker
```

2. **Use GPU profiles:**
```bash
docker compose --profile ollama-gpu --profile tts --profile comfyui up -d
```

### Fallback to CPU

If you don't have GPU support, use CPU profiles:
```bash
docker compose --profile ollama-cpu --profile n8n up -d
```

## 🔧 Common Commands

```bash
# View running services
docker compose ps

# View logs
docker compose logs -f [service-name]

# Stop all services
docker compose --profile all down

# Stop and remove volumes (⚠️ deletes data)
docker compose --profile all down -v

# Restart a specific service
docker compose restart n8n-local-ai

# Update images to latest versions
docker compose --profile all-gpu pull
docker compose --profile all-gpu up -d

# Update specific service
docker compose pull n8n
docker compose up -d n8n-local-ai
```

## 🔄 Updating Your Services

Since all images use `:latest` tags, you can easily update to the newest versions:

### Update Everything
```bash
# Pull latest images
docker compose --profile all-gpu pull

# Restart with new images
docker compose --profile all-gpu up -d
```

### Update Specific Services
```bash
# Update just N8N
docker compose pull n8n
docker compose up -d n8n-local-ai

# Update Ollama
docker compose pull ollama-gpu
docker compose up -d ollama-gpu

# Update ComfyUI
docker compose pull comfyui
docker compose up -d comfyui-local-ai
```

### Check for Updates
```bash
# See current image versions
docker images | grep -E "n8n|ollama|postgres|qdrant|comfyui"

# Compare with latest on Docker Hub
docker pull n8nio/n8n:latest
docker images n8nio/n8n
```

### Rebuild Custom Images
For services built from Dockerfiles (Whisper, Kitten TTS):
```bash
# Rebuild with latest dependencies
docker compose build --no-cache whisper-local-ai kitten-tts-local-ai

# Restart with new builds
docker compose up -d whisper-local-ai kitten-tts-local-ai
```

## 🤖 Working with Ollama Models

### Managing Models
```bash
# List installed models
docker exec ollama-gpu ollama list

# Pull a new model
docker exec ollama-gpu ollama pull mistral
docker exec ollama-gpu ollama pull codellama:13b

# Remove a model
docker exec ollama-gpu ollama rm llama3.2

# Run a model interactively
docker exec -it ollama-gpu ollama run llama3.2

# Show model information
docker exec ollama-gpu ollama show llama3.2
```

### Test Ollama API
```bash
# Simple completion
curl http://localhost:11434/api/generate -d '{
  "model": "llama3.2",
  "prompt": "Why is the sky blue?",
  "stream": false
}'

# Chat completion
curl http://localhost:11434/api/chat -d '{
  "model": "llama3.2",
  "messages": [
    {"role": "user", "content": "Hello!"}
  ]
}'
```

## 🗄️ Database Management

### PostgreSQL Backup & Restore
```bash
# Backup database
docker exec postgres-local-ai pg_dump -U n8n n8n > backup_$(date +%Y%m%d).sql

# Restore database
cat backup_20241126.sql | docker exec -i postgres-local-ai psql -U n8n -d n8n

# Access PostgreSQL shell
docker exec -it postgres-local-ai psql -U n8n -d n8n
```

### Qdrant Vector Database
```bash
# Access Qdrant web UI
# Open browser: http://localhost:6333/dashboard

# List collections via API
curl http://localhost:6333/collections

# Backup Qdrant data (via volume)
docker run --rm -v qdrant_storage:/data -v $(pwd):/backup \
  alpine tar czf /backup/qdrant-backup-$(date +%Y%m%d).tar.gz -C /data .
```

## 📊 Monitoring & Debugging

### Resource Usage
```bash
# Container resource stats
docker stats

# Specific service stats
docker stats n8n-local-ai ollama-gpu

# Disk usage by Docker
docker system df

# Detailed volume usage
docker system df -v
```

### Logs & Debugging
```bash
# Follow logs for all services
docker compose logs -f

# Logs for specific service with timestamps
docker compose logs -f --timestamps n8n-local-ai

# Last 100 lines
docker compose logs --tail=100 ollama-gpu

# Save logs to file
docker compose logs > system-logs-$(date +%Y%m%d).log

# Check service health
docker inspect --format='{{.State.Health.Status}}' n8n-local-ai
```

### Interactive Shell Access
```bash
# Access container shell
docker exec -it n8n-local-ai /bin/sh
docker exec -it postgres-local-ai /bin/bash
docker exec -it ollama-gpu /bin/bash

# Run commands directly
docker exec n8n-local-ai ls -la /home/node/.n8n
docker exec postgres-local-ai pg_isready -U n8n
```

## 🧹 Cleanup & Maintenance

### Clean Up Unused Resources
```bash
# Remove stopped containers
docker container prune

# Remove unused images
docker image prune

# Remove unused volumes (⚠️ careful!)
docker volume prune

# Remove everything unused (⚠️ very careful!)
docker system prune -a

# See what will be removed (dry run)
docker system prune --dry-run
```

### Reset Specific Service
```bash
# Stop, remove, and recreate service
docker compose stop n8n-local-ai
docker compose rm -f n8n-local-ai
docker compose up -d n8n-local-ai

# Reset with fresh volume
docker compose stop n8n-local-ai
docker volume rm n8n_storage
docker compose up -d n8n-local-ai
```

## 🔐 Security & Backups

### Backup Everything
```bash
# Create backup directory
mkdir -p ~/backups/local-ai-$(date +%Y%m%d)

# Backup all volumes
for volume in n8n_storage postgres_storage ollama_storage qdrant_storage hf_cache; do
  docker run --rm \
    -v ${volume}:/data \
    -v ~/backups/local-ai-$(date +%Y%m%d):/backup \
    alpine tar czf /backup/${volume}.tar.gz -C /data .
done

# Backup .env file
cp .env ~/backups/local-ai-$(date +%Y%m%d)/env.backup
```

### Security Hardening
```bash
# Generate strong encryption keys
openssl rand -hex 32

# Check exposed ports
docker compose ps --format "table {{.Service}}\t{{.Ports}}"

# Limit container resources
# Add to docker-compose.yml:
# deploy:
#   resources:
#     limits:
#       cpus: '2'
#       memory: 4G
```

## 🌐 Network & Connectivity

### Test Network Connectivity
```bash
# Test if services can reach each other
docker exec n8n-local-ai ping -c 3 postgres-local-ai
docker exec n8n-local-ai wget -O- http://ollama-gpu:11434

# Inspect network
docker network inspect local-ai-network

# See which containers are on the network
docker network inspect local-ai-network --format='{{range .Containers}}{{.Name}} {{end}}'
```

### Connect External Services
```bash
# Connect an external container to the network
docker network connect local-ai-network your-other-container

# Example: Connect a custom Python script container
docker run -d --name my-script \
  --network local-ai-network \
  python:3.11 python my_script.py
```

## 📈 Performance Optimization

### GPU Usage
```bash
# Monitor GPU usage (NVIDIA)
nvidia-smi

# Watch GPU usage in real-time
watch -n 1 nvidia-smi

# Check which containers are using GPU
docker ps --filter "label=com.nvidia.cuda.version"
```

### Optimize Docker
```bash
# Set Docker resource limits in Docker Desktop
# Settings → Resources → Advanced

# Clear build cache
docker builder prune -af

# Compact Docker disk image (Docker Desktop)
# Settings → Resources → Disk image location → Compact
```

## 🔗 Integration Examples

### Use N8N with Ollama
In N8N workflows, use Ollama HTTP Request node:
- URL: `http://ollama-gpu:11434/api/generate`
- Method: POST
- Body: `{"model": "llama3.2", "prompt": "{{$json.input}}"}`

### Use Whisper API
```bash
# Transcribe audio file
curl -X POST http://localhost:5001/transcribe \
  -F "audio=@recording.mp3" \
  -F "language=en"
```

### Use Kitten TTS API
```bash
# Generate speech
curl -X POST http://localhost:8005/generate \
  -H "Content-Type: application/json" \
  -d '{"text": "Hello world", "voice": "default"}'
```

## 💾 Volume Management

### Inspect Volumes
```bash
# List all volumes
docker volume ls | grep local-ai

# Inspect volume details
docker volume inspect ollama_storage

# Check volume size
docker system df -v | grep ollama_storage

# Browse volume contents
docker run --rm -v ollama_storage:/data alpine ls -lah /data
```

### Copy Files To/From Volumes
```bash
# Copy file into volume
docker run --rm -v ollama_storage:/data -v $(pwd):/local \
  alpine cp /local/myfile.txt /data/

# Copy file from volume
docker run --rm -v ollama_storage:/data -v $(pwd):/local \
  alpine cp /data/myfile.txt /local/
```

## 📝 Service-Specific Notes

### N8N
- Access at: http://localhost:5678
- Demo data automatically imported on first run
- Shared folder mounted at `/data/shared` for file exchange

### Ollama
- Pre-pulls: `llama3.2`, `nomic-embed-text`, `gemma3:latest`
- Add more models: `docker exec -it ollama ollama pull <model-name>`

### Whisper
- Requires Dockerfile in `./whisper/` directory
- Customize model size in Dockerfile

### ComfyUI
- Update paths in `.env` to point to your existing ComfyUI installation
- Models and custom nodes persist across restarts

### Kitten TTS
- Requires Dockerfile and config.yaml in `./kitten-tts/`
- HuggingFace models cached in named volume

## 🐛 Troubleshooting

### Port Already in Use
```bash
# Check what's using the port
sudo lsof -i :5678

# Change port in docker-compose.yml or stop conflicting service
```

### Network Not Found
```bash
# Create the external network
docker network create local-bridge
```

### GPU Not Detected
```bash
# Verify NVIDIA runtime
docker run --rm --gpus all nvidia/cuda:11.8.0-base-ubuntu22.04 nvidia-smi

# If that fails, check NVIDIA Container Toolkit installation
```

### Permission Issues (ComfyUI)
```bash
# Set correct USER_ID and GROUP_ID in .env
echo "USER_ID=$(id -u)" >> .env
echo "GROUP_ID=$(id -g)" >> .env
```

## 🤝 Contributing

Feel free to submit issues and enhancement requests!

## 📄 License

[Your License Here]

## 🔗 Links

- [N8N Documentation](https://docs.n8n.io/)
- [Ollama](https://ollama.ai/)
- [ComfyUI](https://github.com/comfyanonymous/ComfyUI)
- [Qdrant](https://qdrant.tech/)