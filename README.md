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

# 4. Create the network (ensure docker is running)
docker network create local-ai-network

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
docker compose restart n8n

# Update images
docker compose --profile all pull
docker compose --profile all up -d
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