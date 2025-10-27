#!/bin/bash
#
# Diagnostic script to identify why client-data extraction fails on Debian
# but works on Ubuntu
#

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info() { echo -e "${BLUE}[INFO]${NC} $*"; }
ok() { echo -e "${GREEN}[PASS]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; }

echo "========================================"
echo "  Client-Data Extraction Diagnostics"
echo "========================================"
echo ""

# Test 1: System Information
info "Test 1: System Information"
echo "  OS: $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
echo "  Kernel: $(uname -r)"
echo "  Host date: $(date)"
echo ""

# Test 2: Docker Version
info "Test 2: Docker Version"
docker version --format '{{.Server.Version}}' && ok "Docker installed" || fail "Docker not found"
echo "  Docker version: $(docker version --format '{{.Server.Version}}')"
echo ""

# Test 3: Docker Configuration
info "Test 3: Docker Configuration"
if [ -f /etc/docker/daemon.json ]; then
  ok "Found custom Docker config"
  echo "  Config:"
  cat /etc/docker/daemon.json | sed 's/^/    /'
else
  warn "No custom Docker config found (using defaults)"
fi
echo ""

# Test 4: Host DNS Configuration
info "Test 4: Host DNS Configuration"
echo "  Nameservers:"
cat /etc/resolv.conf | grep nameserver | sed 's/^/    /'
echo ""

# Test 5: Container DNS Resolution
info "Test 5: Container DNS Resolution"
echo "  Testing DNS inside Ubuntu 22.04 container..."
if docker run --rm ubuntu:22.04 sh -c "cat /etc/resolv.conf" >/dev/null 2>&1; then
  docker run --rm ubuntu:22.04 cat /etc/resolv.conf | sed 's/^/    /'
  ok "Container DNS configured"
else
  fail "Container DNS check failed"
fi
echo ""

# Test 6: Network Connectivity
info "Test 6: Network Connectivity to Ubuntu Repos"
echo "  Pinging archive.ubuntu.com..."
if docker run --rm ubuntu:22.04 sh -c "apt-get update -qq && apt-get install -y iputils-ping >/dev/null 2>&1 && ping -c 2 archive.ubuntu.com" >/dev/null 2>&1; then
  ok "Can reach archive.ubuntu.com"
else
  warn "Cannot reach archive.ubuntu.com (may be network/DNS issue)"
fi
echo ""

# Test 7: Container Date/Time
info "Test 7: Container Date/Time Sync"
HOST_DATE=$(date +%s)
CONTAINER_DATE=$(docker run --rm ubuntu:22.04 date +%s)
DATE_DIFF=$((HOST_DATE - CONTAINER_DATE))
if [ ${DATE_DIFF#-} -lt 10 ]; then
  ok "Container time synced (diff: ${DATE_DIFF}s)"
else
  warn "Container time out of sync (diff: ${DATE_DIFF}s)"
fi
echo "  Host: $(date)"
echo "  Container: $(docker run --rm ubuntu:22.04 date)"
echo ""

# Test 8: apt-get update (Default DNS)
info "Test 8: apt-get update with default DNS"
echo "  Running apt-get update inside container..."
if docker run --rm ubuntu:22.04 apt-get update >/dev/null 2>&1; then
  ok "apt-get update succeeded with default DNS"
else
  fail "apt-get update failed with default DNS"
  echo "  Error output:"
  docker run --rm ubuntu:22.04 apt-get update 2>&1 | grep -E "Err:|W:|E:" | head -5 | sed 's/^/    /'
fi
echo ""

# Test 9: apt-get update (Google DNS)
info "Test 9: apt-get update with Google DNS (8.8.8.8)"
echo "  Running apt-get update with --dns 8.8.8.8..."
if docker run --rm --dns 8.8.8.8 ubuntu:22.04 apt-get update >/dev/null 2>&1; then
  ok "apt-get update succeeded with Google DNS"
  echo "  ✓ FIX: Adding dns: [8.8.8.8, 8.8.4.4] to docker-compose.yml should work"
else
  fail "apt-get update failed even with Google DNS"
  echo "  Error output:"
  docker run --rm --dns 8.8.8.8 ubuntu:22.04 apt-get update 2>&1 | grep -E "Err:|W:|E:" | head -5 | sed 's/^/    /'
fi
echo ""

# Test 10: wget availability in base image
info "Test 10: Check if wget/curl exists in client-data image"
IMAGE="uprightbass360/azerothcore-wotlk-playerbots:client-data-Playerbot"
if docker image inspect "$IMAGE" >/dev/null 2>&1; then
  echo "  Checking for download tools in $IMAGE..."
  if docker run --rm "$IMAGE" sh -c "which wget" 2>/dev/null; then
    ok "wget found in base image"
  else
    warn "wget not found in base image"
  fi
  if docker run --rm "$IMAGE" sh -c "which curl" 2>/dev/null; then
    ok "curl found in base image"
  else
    warn "curl not found in base image"
  fi
  if docker run --rm "$IMAGE" sh -c "which aria2c" 2>/dev/null; then
    ok "aria2c found in base image"
  else
    warn "aria2c not found in base image"
  fi
else
  warn "Image $IMAGE not found locally"
fi
echo ""

# Test 11: GitHub connectivity
info "Test 11: GitHub Connectivity"
echo "  Testing connection to github.com..."
if docker run --rm alpine:latest sh -c "apk add --no-cache curl >/dev/null 2>&1 && curl -I https://github.com 2>&1" | grep -q "HTTP/"; then
  ok "Can reach github.com"
else
  fail "Cannot reach github.com"
fi
echo ""

# Test 12: Download test (small file)
info "Test 12: Download Test (small file from GitHub)"
echo "  Attempting to download a small file from GitHub releases..."
TEST_URL="https://github.com/wowgaming/client-data/releases/latest"
if docker run --rm alpine:latest sh -c "apk add --no-cache curl >/dev/null 2>&1 && curl -sL '$TEST_URL' >/dev/null" 2>&1; then
  ok "Successfully accessed GitHub releases"
else
  fail "Failed to access GitHub releases"
fi
echo ""

# Summary
echo "========================================"
echo "  Summary & Recommendations"
echo "========================================"
echo ""

# Provide recommendations based on test results
if docker run --rm --dns 8.8.8.8 ubuntu:22.04 apt-get update >/dev/null 2>&1; then
  echo "✓ RECOMMENDATION: Add Google DNS to docker-compose.yml"
  echo ""
  echo "Add this to the ac-client-data-playerbots service in docker-compose.yml:"
  echo ""
  echo "  ac-client-data-playerbots:"
  echo "    dns:"
  echo "      - 8.8.8.8"
  echo "      - 8.8.4.4"
  echo "    # ... rest of config"
  echo ""
elif ! docker run --rm ubuntu:22.04 apt-get update >/dev/null 2>&1; then
  echo "⚠ RECOMMENDATION: Use manual download method"
  echo ""
  echo "The apt-get update is failing even with Google DNS."
  echo "Use manual download:"
  echo ""
  echo "  cd /tmp"
  echo "  wget https://github.com/wowgaming/client-data/releases/download/v17/data.zip"
  echo "  docker volume create ac-client-data"
  echo "  docker run --rm -v ac-client-data:/data -v /tmp:/host alpine:latest \\"
  echo "    sh -c 'apk add --no-cache unzip && cd /data && unzip /host/data.zip'"
  echo ""
else
  ok "All tests passed - extraction should work"
fi

echo "========================================"
