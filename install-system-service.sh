#!/bin/bash
# ==============================================
# AzerothCore System Service Installer
# ==============================================
# Configures AzerothCore to start automatically on Debian systems

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
SERVICE_USER="${SERVICE_USER:-azerothcore}"
INSTALL_DIR="${INSTALL_DIR:-/opt/azerothcore}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    local level="$1"
    shift
    local message="$*"

    case "$level" in
        "INFO")  echo -e "${BLUE}[INFO]${NC} $message" ;;
        "WARN")  echo -e "${YELLOW}[WARN]${NC} $message" ;;
        "ERROR") echo -e "${RED}[ERROR]${NC} $message" ;;
        "SUCCESS") echo -e "${GREEN}[SUCCESS]${NC} $message" ;;
    esac
}

error_exit() {
    log "ERROR" "$1"
    exit 1
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        error_exit "This script must be run as root. Use: sudo $0"
    fi
}

# Check prerequisites
check_prerequisites() {
    log "INFO" "Checking prerequisites..."

    # Check if Docker is installed
    if ! command -v docker &> /dev/null; then
        error_exit "Docker is not installed. Please install Docker first."
    fi

    # Check if Docker Compose is installed
    if ! command -v docker-compose &> /dev/null; then
        error_exit "Docker Compose is not installed. Please install Docker Compose first."
    fi

    # Check if systemd is available
    if ! command -v systemctl &> /dev/null; then
        error_exit "systemd is not available on this system"
    fi

    log "SUCCESS" "Prerequisites check passed"
}

# Create service user
create_service_user() {
    log "INFO" "Creating service user: $SERVICE_USER"

    if id "$SERVICE_USER" &>/dev/null; then
        log "INFO" "User $SERVICE_USER already exists"
    else
        useradd --system --no-create-home --shell /bin/false --group docker "$SERVICE_USER"
        log "SUCCESS" "Created user: $SERVICE_USER"
    fi

    # Add user to docker group
    usermod -aG docker "$SERVICE_USER" || true
}

# Install application
install_application() {
    log "INFO" "Installing AzerothCore to $INSTALL_DIR"

    # Create install directory
    mkdir -p "$INSTALL_DIR"

    # Copy application files
    cp -r "$SCRIPT_DIR"/* "$INSTALL_DIR/"

    # Set ownership
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"

    # Set permissions
    chmod +x "$INSTALL_DIR"/*.sh

    log "SUCCESS" "Application installed to $INSTALL_DIR"
}

# Create systemd service files
create_systemd_services() {
    log "INFO" "Creating systemd service files..."

    # Main AzerothCore service
    cat > /etc/systemd/system/azerothcore.service << EOF
[Unit]
Description=AzerothCore World of Warcraft Server
Documentation=https://www.azerothcore.org/
After=docker.service network.target
Requires=docker.service
StartLimitIntervalSec=0

[Service]
Type=forking
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
Environment=DEPLOY_MODE=system
Environment=MONITOR_MODE=single
ExecStartPre=/usr/bin/docker system prune -f --volumes
ExecStart=$INSTALL_DIR/azerothcore-deploy.sh start
ExecStop=$INSTALL_DIR/azerothcore-deploy.sh stop
ExecReload=/bin/kill -HUP \$MAINPID
PIDFile=/var/run/azerothcore-deploy.pid
Restart=always
RestartSec=30
TimeoutStartSec=1800
TimeoutStopSec=300
KillMode=mixed
KillSignal=SIGTERM

# Resource limits
LimitNOFILE=65536
LimitMEMLOCK=infinity

# Security settings
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$INSTALL_DIR /var/run /tmp
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF

    # AzerothCore monitoring service
    cat > /etc/systemd/system/azerothcore-monitor.service << EOF
[Unit]
Description=AzerothCore Monitoring Service
After=azerothcore.service
Requires=azerothcore.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR
Environment=MYSQL_ROOT_PASSWORD=azerothcore123
ExecStart=$INSTALL_DIR/azerothcore-monitor.sh monitor
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$INSTALL_DIR
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF

    # Web status service (simple HTTP server)
    cat > /etc/systemd/system/azerothcore-web.service << EOF
[Unit]
Description=AzerothCore Web Status Server
After=azerothcore-monitor.service
Requires=azerothcore-monitor.service

[Service]
Type=simple
User=$SERVICE_USER
Group=$SERVICE_USER
WorkingDirectory=$INSTALL_DIR/monitoring-web
ExecStart=/usr/bin/python3 -m http.server 8080
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

# Security settings
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
ReadWritePaths=$INSTALL_DIR/monitoring-web
PrivateTmp=yes

[Install]
WantedBy=multi-user.target
EOF

    log "SUCCESS" "Systemd service files created"
}

# Create startup configuration
create_startup_config() {
    log "INFO" "Creating startup configuration..."

    # Create environment file
    cat > "$INSTALL_DIR/.env-production" << EOF
# Production Environment Configuration
DEPLOYMENT_MODE=production
STORAGE_PATH=$INSTALL_DIR/data
HOST_BACKUP_PATH=$INSTALL_DIR/backups
HOST_BACKUP_SCRIPTS_PATH=$INSTALL_DIR/backup-scripts

# Database configuration
MYSQL_ROOT_PASSWORD=azerothcore123
DB_WAIT_RETRIES=60
DB_WAIT_SLEEP=10

# MySQL health check settings (for slower systems)
MYSQL_HEALTHCHECK_INTERVAL=20s
MYSQL_HEALTHCHECK_TIMEOUT=15s
MYSQL_HEALTHCHECK_RETRIES=25
MYSQL_HEALTHCHECK_START_PERIOD=120s

# Performance settings
MYSQL_MAX_CONNECTIONS=200
MYSQL_INNODB_BUFFER_POOL_SIZE=512M
MYSQL_INNODB_LOG_FILE_SIZE=128M

# Security settings
PLAYERBOT_MAX_BOTS=20
MODULE_PLAYERBOTS=1
EOF

    # Set default environment
    if [[ ! -f "$INSTALL_DIR/.env" ]]; then
        cp "$INSTALL_DIR/.env-production" "$INSTALL_DIR/.env"
    fi

    # Create data directories
    mkdir -p "$INSTALL_DIR/data/mysql-data"
    mkdir -p "$INSTALL_DIR/data/config"
    mkdir -p "$INSTALL_DIR/backups"
    mkdir -p "$INSTALL_DIR/monitoring-logs"
    mkdir -p "$INSTALL_DIR/deployment-logs"

    # Set ownership
    chown -R "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR"

    log "SUCCESS" "Startup configuration created"
}

# Configure logrotate
configure_logrotate() {
    log "INFO" "Configuring log rotation..."

    cat > /etc/logrotate.d/azerothcore << EOF
$INSTALL_DIR/deployment-logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    su $SERVICE_USER $SERVICE_USER
}

$INSTALL_DIR/monitoring-logs/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    su $SERVICE_USER $SERVICE_USER
}
EOF

    log "SUCCESS" "Log rotation configured"
}

# Configure firewall (if ufw is available)
configure_firewall() {
    if command -v ufw &> /dev/null; then
        log "INFO" "Configuring firewall rules..."

        # Game server ports
        ufw allow 3784/tcp comment "AzerothCore Auth Server"
        ufw allow 8215/tcp comment "AzerothCore World Server"
        ufw allow 7778/tcp comment "AzerothCore SOAP"

        # Database port (only from localhost)
        ufw allow from 127.0.0.1 to any port 64306 comment "AzerothCore MySQL"

        # Web status (optional, adjust as needed)
        ufw allow 8080/tcp comment "AzerothCore Web Status"

        log "SUCCESS" "Firewall rules configured"
    else
        log "WARN" "UFW not available, skipping firewall configuration"
    fi
}

# Enable and start services
enable_services() {
    log "INFO" "Enabling and starting services..."

    # Reload systemd
    systemctl daemon-reload

    # Enable services
    systemctl enable azerothcore.service
    systemctl enable azerothcore-monitor.service
    systemctl enable azerothcore-web.service

    log "SUCCESS" "Services enabled"
    log "INFO" "To start services: systemctl start azerothcore"
    log "INFO" "To check status: systemctl status azerothcore"
}

# Create uninstall script
create_uninstall_script() {
    cat > "$INSTALL_DIR/uninstall.sh" << 'EOF'
#!/bin/bash
# Uninstall AzerothCore system service

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root"
    exit 1
fi

echo "Stopping services..."
systemctl stop azerothcore-web azerothcore-monitor azerothcore 2>/dev/null || true

echo "Disabling services..."
systemctl disable azerothcore-web azerothcore-monitor azerothcore 2>/dev/null || true

echo "Removing service files..."
rm -f /etc/systemd/system/azerothcore*.service
rm -f /etc/logrotate.d/azerothcore

echo "Reloading systemd..."
systemctl daemon-reload

echo "Removing installation directory..."
read -p "Remove $INSTALL_DIR? [y/N] " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    rm -rf "$INSTALL_DIR"
    echo "Installation directory removed"
fi

echo "AzerothCore system service uninstalled"
EOF

    chmod +x "$INSTALL_DIR/uninstall.sh"
    chown "$SERVICE_USER:$SERVICE_USER" "$INSTALL_DIR/uninstall.sh"
}

# Display installation summary
show_summary() {
    log "SUCCESS" "AzerothCore system service installation completed!"
    echo
    echo "📋 Installation Summary:"
    echo "  • Install Directory: $INSTALL_DIR"
    echo "  • Service User: $SERVICE_USER"
    echo "  • Services: azerothcore, azerothcore-monitor, azerothcore-web"
    echo
    echo "🚀 Quick Start:"
    echo "  • Start services: systemctl start azerothcore"
    echo "  • Check status: systemctl status azerothcore"
    echo "  • View logs: journalctl -u azerothcore -f"
    echo "  • Web status: http://localhost:8080"
    echo
    echo "🔧 Management:"
    echo "  • Stop services: systemctl stop azerothcore"
    echo "  • Restart services: systemctl restart azerothcore"
    echo "  • Disable services: systemctl disable azerothcore"
    echo "  • Uninstall: $INSTALL_DIR/uninstall.sh"
    echo
    echo "📁 Important Paths:"
    echo "  • Configuration: $INSTALL_DIR/.env"
    echo "  • Data: $INSTALL_DIR/data/"
    echo "  • Backups: $INSTALL_DIR/backups/"
    echo "  • Logs: $INSTALL_DIR/deployment-logs/"
    echo "  • Monitoring: $INSTALL_DIR/monitoring-logs/"
    echo
}

# Main installation function
main_install() {
    log "INFO" "Starting AzerothCore system service installation..."

    check_root
    check_prerequisites
    create_service_user
    install_application
    create_systemd_services
    create_startup_config
    configure_logrotate
    configure_firewall
    enable_services
    create_uninstall_script
    show_summary
}

# Command handling
case "${1:-install}" in
    "install")
        main_install
        ;;
    "uninstall")
        if [[ -f "$INSTALL_DIR/uninstall.sh" ]]; then
            "$INSTALL_DIR/uninstall.sh"
        else
            error_exit "Uninstall script not found. Manual removal required."
        fi
        ;;
    *)
        echo "Usage: $0 [install|uninstall]"
        echo
        echo "Environment Variables:"
        echo "  SERVICE_USER=username    # Service user (default: azerothcore)"
        echo "  INSTALL_DIR=path         # Install directory (default: /opt/azerothcore)"
        echo
        echo "Examples:"
        echo "  sudo $0 install                    # Standard installation"
        echo "  sudo SERVICE_USER=wow $0 install   # Custom user"
        echo "  sudo $0 uninstall                  # Remove installation"
        exit 1
        ;;
esac