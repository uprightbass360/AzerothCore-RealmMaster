#!/bin/bash
# Portainer Diagnostics Script for AzerothCore Docker Compose
# Run this on your slower Portainer machine to diagnose timeout issues

echo "==============================================="
echo "AzerothCore Portainer Diagnostics"
echo "==============================================="
echo "Date: $(date)"
echo "Machine: $(hostname)"
echo ""

# System Resources
echo "🖥️  SYSTEM RESOURCES"
echo "-------------------"
echo "CPU Cores: $(nproc)"
echo "Memory: $(free -h | grep '^Mem:' | awk '{print $2 " total, " $7 " available"}')"
echo "Disk Space: $(df -h / | tail -1 | awk '{print $4 " available on " $6}')"
echo "Load Average: $(uptime | awk -F'load average:' '{print $2}')"
echo ""

# Podman Status
echo "🐳 PODMAN STATUS"
echo "----------------"
podman --version
echo "Podman Service Status: $(systemctl is-active podman 2>/dev/null || echo 'Unknown')"
echo "Podman Memory Limit: $(podman system info 2>/dev/null | grep 'memTotal' || echo 'Unable to determine')"
echo ""

# Network Connectivity Tests
echo "🌐 NETWORK CONNECTIVITY"
echo "-----------------------"
echo "Testing GitHub connectivity (for client data download):"
curl -s -w "Response Time: %{time_total}s\n" -o /dev/null https://api.github.com/repos/wowgaming/client-data/releases/latest || echo "❌ GitHub API unreachable"

echo "Testing GitHub download speed (5MB test):"
timeout 30 wget -O /tmp/speed_test.zip https://github.com/wowgaming/client-data/releases/download/v16/data.zip --progress=dot 2>&1 | tail -5 || echo "❌ Download test failed"
rm -f /tmp/speed_test.zip

echo ""

# Check for existing volumes/data
echo "📁 EXISTING DATA CHECK"
echo "---------------------"
VOLUMES_PATH="${STORAGE_PATH_CONTAINERS:-./volumes}"
echo "Checking volumes path: $VOLUMES_PATH"

if [ -d "$VOLUMES_PATH/azerothcore/data" ]; then
    echo "✅ Data directory exists"
    if [ -d "$VOLUMES_PATH/azerothcore/data/maps" ] && [ -d "$VOLUMES_PATH/azerothcore/data/vmaps" ]; then
        echo "✅ Game data appears complete - client download should be skipped"
    else
        echo "⚠️  Game data incomplete - client download will be required"
    fi
else
    echo "❌ No existing data - full download required (~15GB)"
fi

if [ -d "$VOLUMES_PATH/azerothcore/mysql" ]; then
    echo "✅ MySQL data directory exists"
    if [ -f "$VOLUMES_PATH/azerothcore/mysql/acore_world/creature.ibd" ]; then
        echo "✅ Database appears populated - import should be skipped"
    else
        echo "⚠️  Database may need importing"
    fi
else
    echo "❌ No existing MySQL data - full import required"
fi

echo ""

# Podman Compose Services Status
echo "🔧 PODMAN COMPOSE STATUS"
echo "------------------------"
if [ -f "docker-compose.yml" ]; then
    echo "Docker Compose file found"
    podman-compose ps 2>/dev/null || echo "Podman Compose not running or not available"
else
    echo "❌ docker-compose.yml not found in current directory"
fi

echo ""

# Resource-intensive operation simulation
echo "⏱️  PERFORMANCE TESTS"
echo "--------------------"
echo "Testing disk I/O (1GB file):"
timeout 60 dd if=/dev/zero of=/tmp/test_io bs=1M count=1024 2>&1 | grep -E '(copied|MB/s)' || echo "❌ I/O test failed or too slow"
rm -f /tmp/test_io

echo "Testing compression/extraction speed:"
timeout 30 sh -c 'echo "test data" | gzip > /tmp/test.gz && gunzip /tmp/test.gz && echo "✅ Compression test OK"' || echo "❌ Compression test failed"
rm -f /tmp/test.gz /tmp/test

echo ""

# Memory pressure test
echo "🧠 MEMORY PRESSURE TEST"
echo "-----------------------"
echo "Available memory before test:"
free -h | grep '^Mem:'

echo "Testing memory allocation (512MB):"
timeout 10 sh -c 'python3 -c "import time; data = b\"x\" * (512 * 1024 * 1024); time.sleep(2); print(\"✅ Memory allocation test OK\")"' 2>/dev/null || echo "❌ Memory allocation test failed"

echo "Available memory after test:"
free -h | grep '^Mem:'

echo ""

# Container runtime test
echo "🏃 CONTAINER RUNTIME TEST"
echo "-------------------------"
echo "Testing basic container startup time:"
START_TIME=$(date +%s)
podman run --rm alpine:latest echo "Container startup test" 2>/dev/null || echo "❌ Container startup failed"
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
echo "Container startup took: ${DURATION}s"

if [ $DURATION -gt 10 ]; then
    echo "⚠️  Container startup is slow (>10s)"
else
    echo "✅ Container startup time is acceptable"
fi

echo ""

# Recommendations
echo "💡 RECOMMENDATIONS"
echo "------------------"

# Check if we have enough resources
AVAILABLE_GB=$(df / | tail -1 | awk '{print int($4/1024/1024)}')
MEMORY_GB=$(free -g | grep '^Mem:' | awk '{print $2}')

if [ $AVAILABLE_GB -lt 20 ]; then
    echo "⚠️  Low disk space ($AVAILABLE_GB GB available). Need at least 20GB for full setup."
fi

if [ $MEMORY_GB -lt 2 ]; then
    echo "⚠️  Low memory ($MEMORY_GB GB). Consider increasing to 4GB+ for better performance."
fi

echo ""
echo "🚀 SUGGESTED PORTAINER DEPLOYMENT STRATEGY:"
echo "1. Pre-download client data on faster machine and copy to Portainer server"
echo "2. Use 'DEPLOYMENT_MODE=portainer' environment variable for simplified setup"
echo "3. Increase Portainer deployment timeouts to 30+ minutes"
echo "4. Deploy services in phases rather than all at once"
echo ""
echo "Diagnostics complete. Save this output for troubleshooting."