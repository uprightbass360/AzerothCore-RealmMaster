#!/bin/bash
# AzerothCore RealmMaster - Install Docker NFS Dependencies Fix
# This script installs a systemd drop-in configuration to ensure Docker
# waits for NFS mounts before starting, preventing backup folder deletion issues

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
DROP_IN_SOURCE="$PROJECT_ROOT/config/systemd/docker.service.d/nfs-dependencies.conf"
DROP_IN_TARGET="/etc/systemd/system/docker.service.d/nfs-dependencies.conf"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}ℹ️  $*${NC}"; }
log_ok() { echo -e "${GREEN}✅ $*${NC}"; }
log_warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
log_err() { echo -e "${RED}❌ $*${NC}"; }

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  log_err "This script must be run as root (use sudo)"
  exit 1
fi

# Check if source file exists
if [ ! -f "$DROP_IN_SOURCE" ]; then
  log_err "Source configuration file not found: $DROP_IN_SOURCE"
  exit 1
fi

# Check if NFS mounts exist
log_info "Checking NFS mount configuration..."
if ! systemctl list-units --type=mount | grep -q "nfs-azerothcore.mount"; then
  log_warn "nfs-azerothcore.mount not found. This fix requires NFS mounts to be configured."
  log_warn "Continue anyway? (y/n)"
  read -r response
  if [[ ! "$response" =~ ^[Yy]$ ]]; then
    log_info "Installation cancelled."
    exit 0
  fi
fi

# Create drop-in directory
log_info "Creating systemd drop-in directory..."
mkdir -p "$(dirname "$DROP_IN_TARGET")"
log_ok "Drop-in directory ready: $(dirname "$DROP_IN_TARGET")"

# Install configuration file
log_info "Installing NFS dependencies configuration..."
cp "$DROP_IN_SOURCE" "$DROP_IN_TARGET"
chmod 644 "$DROP_IN_TARGET"
log_ok "Configuration installed: $DROP_IN_TARGET"

# Show what was installed
echo ""
log_info "Installed configuration:"
echo "---"
cat "$DROP_IN_TARGET"
echo "---"
echo ""

# Reload systemd
log_info "Reloading systemd daemon..."
systemctl daemon-reload
log_ok "Systemd daemon reloaded"

# Verify configuration
log_info "Verifying Docker service dependencies..."
echo ""
systemctl show -p After,Requires,Wants docker.service | grep -E '^(After|Requires|Wants)='
echo ""

# Check if Docker is running
if systemctl is-active --quiet docker.service; then
  log_warn "Docker is currently running"
  log_warn "The new configuration will take effect on next Docker restart or system reboot"
  echo ""
  log_info "To apply immediately, restart Docker (WARNING: will stop all containers):"
  echo "  sudo systemctl restart docker.service"
  echo ""
  log_info "Or reboot the system:"
  echo "  sudo reboot"
else
  log_ok "Docker is not running - configuration will apply on next start"
fi

echo ""
log_ok "Docker NFS dependencies fix installed successfully!"
log_info "Docker will now wait for NFS mounts before starting"
log_info "This prevents backup folders from being deleted during server restarts"
