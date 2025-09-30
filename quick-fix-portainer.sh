#!/bin/bash
# Quick fixes for common Portainer timeout issues
# Run this script to apply optimizations for slower machines

echo "==============================================="
echo "AzerothCore Portainer Quick Fixes"
echo "==============================================="

# Create optimized .env for Portainer
create_portainer_env() {
    echo "📝 Creating Portainer-optimized .env file..."

    cat > .env.portainer << 'EOF'
# Portainer Optimized Configuration
DEPLOYMENT_MODE=portainer

# Reduce resource usage
PLAYERBOT_MAX_BOTS=10
MODULE_PLAYERBOTS=1
MODULE_AOE_LOOT=0
MODULE_LEARN_SPELLS=0
MODULE_FIREWORKS=0
MODULE_INDIVIDUAL_PROGRESSION=0

# Database optimizations for slower machines
DOCKER_DB_ROOT_PASSWORD=password

# Monitoring disabled for performance
INFLUXDB_INIT_MODE=disabled
GF_INSTALL_PLUGINS=""

# Backup disabled during initial setup
BACKUP_RETENTION_DAYS=3
BACKUP_CRON_SCHEDULE="0 4 * * 0"

# Network settings
NETWORK_NAME=azerothcore
NETWORK_SUBNET=172.20.0.0/16

# Storage paths
STORAGE_PATH_CONTAINERS=./volumes

# Port configurations
DOCKER_DB_EXTERNAL_PORT=64306
DOCKER_AUTH_EXTERNAL_PORT=3784
DOCKER_WORLD_EXTERNAL_PORT=8215
DOCKER_SOAP_EXTERNAL_PORT=7778
PMA_EXTERNAL_PORT=8081
KEIRA3_EXTERNAL_PORT=4201
INFLUXDB_EXTERNAL_PORT=8087
GF_EXTERNAL_PORT=3001
EOF

    echo "✅ Created .env.portainer with optimized settings"
}

# Create minimal docker-compose for phased deployment
create_minimal_compose() {
    echo "📝 Creating minimal docker-compose for phased deployment..."

    cat > docker-compose.minimal.yml << 'EOF'
# Minimal AzerothCore setup for slow machines - Phase 1: Core services only
services:
  ac-mysql:
    image: mysql:8.0
    container_name: ac-mysql
    environment:
      MYSQL_ROOT_PASSWORD: ${DOCKER_DB_ROOT_PASSWORD:-password}
      MYSQL_ROOT_HOST: '%'
    ports:
      - "64306:3306"
    volumes:
      - ./volumes/azerothcore/mysql:/var/lib/mysql
    command:
      - --default-authentication-plugin=mysql_native_password
      - --character-set-server=utf8mb4
      - --collation-server=utf8mb4_unicode_ci
      - --max_connections=200
      - --innodb-buffer-pool-size=128M
      - --innodb-log-file-size=32M
    restart: unless-stopped
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-uroot", "-p${DOCKER_DB_ROOT_PASSWORD:-password}"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
    networks:
      - azerothcore

  ac-db-init:
    image: mysql:8.0
    container_name: ac-db-init
    depends_on:
      ac-mysql:
        condition: service_healthy
    networks:
      - azerothcore
    environment:
      MYSQL_PWD: ${DOCKER_DB_ROOT_PASSWORD:-password}
    command:
      - sh
      - -c
      - |
        echo "Creating AzerothCore databases..."
        mysql -h ac-mysql -uroot -e "
        CREATE DATABASE IF NOT EXISTS acore_auth DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
        CREATE DATABASE IF NOT EXISTS acore_world DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
        CREATE DATABASE IF NOT EXISTS acore_characters DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
        SHOW DATABASES;
        " || true
        echo "Databases created!"
    restart: "no"

networks:
  azerothcore:
    driver: bridge
EOF

    echo "✅ Created docker-compose.minimal.yml for phase 1"
}

# Create data download script for separate execution
create_data_download_script() {
    echo "📝 Creating separate client data download script..."

    cat > download-client-data.sh << 'EOF'
#!/bin/bash
# Separate client data download - run this independently
echo "🚀 Starting client data download..."

# Create data directory
mkdir -p ./volumes/azerothcore/data

# Check if data already exists
if [ -d './volumes/azerothcore/data/maps' ] && [ -d './volumes/azerothcore/data/vmaps' ]; then
    echo '✅ Game data already exists, skipping download'
    exit 0
fi

echo '📥 Downloading client data (this may take 30+ minutes on slow connections)...'

# Download with progress and resume capability
wget -c -t 3 --progress=bar:force \
    -O ./volumes/azerothcore/data/data.zip \
    "https://github.com/wowgaming/client-data/releases/download/v16/data.zip"

if [ $? -eq 0 ]; then
    echo '📂 Extracting client data...'
    cd ./volumes/azerothcore/data
    unzip -q data.zip
    rm -f data.zip
    echo '✅ Client data download and extraction complete!'
else
    echo '❌ Download failed. You may need to:'
    echo '1. Run this script again (wget will resume)'
    echo '2. Download manually from a faster connection'
    echo '3. Copy data from another AzerothCore installation'
fi
EOF

    chmod +x download-client-data.sh
    echo "✅ Created download-client-data.sh script"
}

# Create deployment instructions
create_deployment_guide() {
    echo "📝 Creating deployment guide..."

    cat > PORTAINER-DEPLOYMENT.md << 'EOF'
# AzerothCore Portainer Deployment Guide

## For Slow Machines / High Latency Connections

### Phase 1: Pre-setup (Optional but Recommended)
1. Run diagnostics: `bash portainer-diagnostics.sh`
2. Pre-download client data: `bash download-client-data.sh`

### Phase 2: Minimal Core Services
1. Copy `.env.portainer` to `.env`
2. Deploy using `docker-compose.minimal.yml`:
   ```bash
   podman-compose -f docker-compose.minimal.yml up -d
   ```

### Phase 3: Add Database Import
Once Phase 2 is stable, add the db-import service to your stack.

### Phase 4: Add Application Services
Finally, add authserver and worldserver.

### Phase 5: Add Optional Services
Add monitoring, backup, and management tools last.

## Troubleshooting Tips

### 504 Gateway Timeouts
- These usually mean operations are taking too long, not failing
- Check logs: `podman-compose logs [service-name]`
- Monitor progress: `bash portainer-verify.sh`

### Memory Issues
- Reduce `PLAYERBOT_MAX_BOTS` to 5-10
- Disable monitoring services temporarily
- Deploy one service at a time

### Network Issues
- Pre-download client data on faster connection
- Use local file copies instead of downloads
- Check firewall/proxy settings

### Disk Space Issues
- Need minimum 20GB free space
- Monitor with `df -h`
- Clean up unused Podman images: `podman system prune`

## Service Dependencies
```
MySQL → DB Init → DB Import → Auth Server → World Server
                            ↓
                         Client Data (parallel)
```

Deploy in this order for best results.
EOF

    echo "✅ Created PORTAINER-DEPLOYMENT.md guide"
}

# Main execution
echo "🛠️  Applying Portainer optimizations..."

create_portainer_env
create_minimal_compose
create_data_download_script
create_deployment_guide

echo ""
echo "✅ Portainer optimization complete!"
echo ""
echo "📋 Next Steps:"
echo "1. Run: bash portainer-diagnostics.sh (to check your system)"
echo "2. Run: bash download-client-data.sh (to pre-download game data)"
echo "3. Copy .env.portainer to .env"
echo "4. Deploy with: podman-compose -f docker-compose.minimal.yml up -d"
echo "5. Monitor with: bash portainer-verify.sh"
echo ""
echo "📖 See PORTAINER-DEPLOYMENT.md for detailed instructions"