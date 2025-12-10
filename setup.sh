#!/bin/bash

set -e

echo "📁 Creating directory structure..."
mkdir -p n8n/demo-data/credentials
mkdir -p n8n/demo-data/workflows
mkdir -p shared
mkdir -p whisper
mkdir -p kitten-tts/outputs
mkdir -p kitten-tts/logs
echo "✓ Directories created"

# Check if .env file exists
if [ ! -f .env ]; then
    echo "📝 Creating .env file..."
    
    # Generate random keys
    N8N_ENCRYPTION_KEY=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    N8N_JWT_SECRET=$(openssl rand -base64 32 | tr -d "=+/" | cut -c1-32)
    POSTGRES_PASSWORD=$(openssl rand -base64 16 | tr -d "=+/" | cut -c1-16)
    
    cat > .env << EOF
# PostgreSQL Configuration
POSTGRES_USER=n8n
POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
POSTGRES_DB=n8n

# n8n Configuration
N8N_ENCRYPTION_KEY=${N8N_ENCRYPTION_KEY}
N8N_USER_MANAGEMENT_JWT_SECRET=${N8N_JWT_SECRET}
WEBHOOK_URL=http://localhost:5678/

# Ollama Configuration
OLLAMA_HOST=ollama:11434

# ComfyUI Configuration
USER_ID=1000
GROUP_ID=1000

# Kitten TTS Configuration
PORT=8005
EOF
    
    echo "✓ .env file created with generated keys"
    echo "⚠️  IMPORTANT: Back up your .env file! The encryption keys cannot be regenerated."
else
    echo "✓ .env file already exists"
fi

# Check Docker network
echo "🔧 Checking Docker network..."
if docker network inspect local-bridge >/dev/null 2>&1; then
    echo "✓ Docker network 'local-bridge' already exists"
else
    echo "Creating Docker network 'local-bridge'..."
    docker network create local-bridge
    echo "✓ Docker network created"
fi

echo ""
echo "✅ Setup complete!"
echo ""
echo "To start the system:"
echo "  For GPU: docker-compose --profile all-gpu up -d"
echo "  For CPU: docker-compose --profile cpu up -d"
echo ""
echo "Services will be available at:"
echo "  - n8n: http://localhost:5678"
echo "  - Qdrant: http://localhost:6333"
echo "  - Ollama: http://localhost:11434"
echo "  - Whisper: http://localhost:5001"
echo "  - ComfyUI: http://localhost:8188"
echo "  - Kitten TTS: http://localhost:8005"