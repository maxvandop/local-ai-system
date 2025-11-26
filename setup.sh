#!/bin/bash

# Local AI System Setup Script
# This script creates the necessary directory structure for your local AI system

set -e

echo "🚀 Setting up Local AI System..."
echo ""

# Color codes for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Create directory structure
echo -e "${BLUE}📁 Creating directory structure...${NC}"
mkdir -p n8n/demo-data/credentials
mkdir -p n8n/demo-data/workflows
mkdir -p whisper
mkdir -p kitten-tts/outputs
mkdir -p kitten-tts/logs
mkdir -p comfyui
mkdir -p shared
echo -e "${GREEN}✓ Directories created${NC}"
echo ""

# Check if .env exists
if [ ! -f .env ]; then
    echo -e "${BLUE}📝 Creating .env file from template...${NC}"
    cp .env.example .env
    echo -e "${YELLOW}⚠️  Please edit .env file with your configuration${NC}"
    echo ""
else
    echo -e "${GREEN}✓ .env file already exists${NC}"
    echo ""
fi

# Check if Docker network exists
echo -e "${BLUE}🔌 Checking Docker network...${NC}"
if docker network inspect local-bridge >/dev/null 2>&1; then
    echo -e "${GREEN}✓ Network 'local-bridge' already exists${NC}"
else
    echo -e "${YELLOW}Creating Docker network 'local-bridge'...${NC}"
    docker network create local-bridge
    echo -e "${GREEN}✓ Network created${NC}"
fi
echo ""

# Generate encryption keys if .env is empty
echo -e "${BLUE}🔐 Checking encryption keys...${NC}"
if grep -q "your_encryption_key_here" .env 2>/dev/null; then
    echo -e "${YELLOW}Generating encryption keys...${NC}"
    
    # Generate keys (works on Linux/Mac/Git Bash)
    if command -v openssl &> /dev/null; then
        ENCRYPTION_KEY=$(openssl rand -hex 32)
        JWT_SECRET=$(openssl rand -hex 32)
        
        # Update .env file
        sed -i.bak "s/N8N_ENCRYPTION_KEY=.*/N8N_ENCRYPTION_KEY=$ENCRYPTION_KEY/" .env
        sed -i.bak "s/N8N_USER_MANAGEMENT_JWT_SECRET=.*/N8N_USER_MANAGEMENT_JWT_SECRET=$JWT_SECRET/" .env
        rm .env.bak
        
        echo -e "${GREEN}✓ Encryption keys generated${NC}"
    else
        echo -e "${YELLOW}⚠️  OpenSSL not found. Please manually generate keys in .env${NC}"
    fi
else
    echo -e "${GREEN}✓ Encryption keys already configured${NC}"
fi
echo ""

# Create placeholder Dockerfiles if they don't exist
echo -e "${BLUE}📄 Creating placeholder Dockerfiles...${NC}"

if [ ! -f whisper/Dockerfile ]; then
    cat > whisper/Dockerfile << 'EOFWHISPER'
FROM python:3.11-slim

WORKDIR /app

# Install whisper dependencies
RUN pip install --no-cache-dir openai-whisper flask

# Expose port
EXPOSE 5001

# Your whisper service code here
CMD ["python", "app.py"]
EOFWHISPER
    echo -e "${YELLOW}⚠️  Created whisper/Dockerfile - please add your Whisper implementation${NC}"
else
    echo -e "${GREEN}✓ whisper/Dockerfile exists${NC}"
fi

if [ ! -f kitten-tts/Dockerfile ]; then
    cat > kitten-tts/Dockerfile << 'EOFTTS'
FROM python:3.11-slim

WORKDIR /app

# Install TTS dependencies
RUN pip install --no-cache-dir TTS flask

# Expose port
EXPOSE 8005

# Your TTS service code here
CMD ["python", "app.py"]
EOFTTS
    echo -e "${YELLOW}⚠️  Created kitten-tts/Dockerfile - please add your TTS implementation${NC}"
else
    echo -e "${GREEN}✓ kitten-tts/Dockerfile exists${NC}"
fi

if [ ! -f kitten-tts/config.yaml ]; then
    cat > kitten-tts/config.yaml << 'EOFCONFIG'
# Kitten TTS Configuration
model: "tts_models/en/ljspeech/tacotron2-DDC"
vocoder: "vocoder_models/en/ljspeech/hifigan_v2"
EOFCONFIG
    echo -e "${GREEN}✓ Created kitten-tts/config.yaml${NC}"
fi

echo ""
echo -e "${GREEN}✅ Setup complete!${NC}"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Edit .env file with your configuration"
echo "   - Set COMFYUI paths"
echo "   - Review other settings"
echo ""
echo "2. Add your Whisper and Kitten TTS implementation files"
echo ""
echo "3. Start services with:"
echo "   ${YELLOW}docker compose --profile all up -d${NC}"
echo ""
echo "4. Access services at:"
echo "   - N8N: http://localhost:5678"
echo "   - ComfyUI: http://localhost:8188"
echo "   - Qdrant: http://localhost:6333"
echo "   - Whisper: http://localhost:5001"
echo "   - Kitten TTS: http://localhost:8005"
echo ""