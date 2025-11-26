#!/bin/bash
set -e

BACKUP_DIR=~/n8n-backups/$(date +%Y%m%d_%H%M%S)
mkdir -p $BACKUP_DIR

echo "📦 Backing up N8N to $BACKUP_DIR"

# Export workflows
echo "📄 Exporting workflows..."
docker exec n8n-local-ai n8n export:workflow --all --output=/data/shared/backup-temp/workflows/
cp -r ./shared/backup-temp/workflows $BACKUP_DIR/

# Export credentials (encrypted)
echo "🔐 Exporting credentials..."
docker exec n8n-local-ai n8n export:credentials --all --output=/data/shared/backup-temp/credentials/
cp -r ./shared/backup-temp/credentials $BACKUP_DIR/

# Backup entire database (includes everything)
echo "🗄️ Backing up PostgreSQL database..."
docker exec postgres-local-ai pg_dump -U n8n n8n > $BACKUP_DIR/n8n-database.sql

# Copy .env encryption keys
echo "🔑 Backing up encryption keys..."
grep -E "N8N_ENCRYPTION_KEY|N8N_USER_MANAGEMENT_JWT_SECRET" .env > $BACKUP_DIR/encryption-keys.txt

# Clean up temp
rm -rf ./shared/backup-temp

echo "✅ Backup complete: $BACKUP_DIR"
echo "📊 Backup size: $(du -sh $BACKUP_DIR | cut -f1)"