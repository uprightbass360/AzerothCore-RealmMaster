# AzerothCore Automated Deployment System

## 🚀 Overview

This deployment system provides automated installation, monitoring, and management of AzerothCore World of Warcraft server on Debian systems with Docker. It features layered service deployment, comprehensive monitoring, and system service integration.

## 📋 Features

- **Layered Deployment**: Database → Services → Optional → Tools
- **Real-time Monitoring**: Health checks, alerts, and web dashboard
- **System Service**: Automatic startup on boot with systemd
- **Resource Management**: CPU, memory, and disk monitoring
- **Backup System**: Automated database backups with retention
- **Security**: User isolation, firewall rules, and secure defaults
- **Web Interface**: Real-time status at http://localhost:8080

## 🛠️ Prerequisites

### System Requirements
- **OS**: Debian 10+ (Ubuntu 18.04+ compatible)
- **RAM**: 4GB minimum, 8GB recommended
- **Disk**: 20GB free space minimum
- **Network**: Internet access for image downloads

### Software Requirements
```bash
# Install Docker
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER

# Install Docker Compose
sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
sudo chmod +x /usr/local/bin/docker-compose

# Reboot to apply group changes
sudo reboot
```

## 🚀 Quick Start

### 1. Test Installation
```bash
# Clone or download the AzerothCore deployment files
cd /path/to/azerothcore-compose2

# Run comprehensive tests
./test-deployment.sh all

# Expected output: "All tests passed! 🎉"
```

### 2. Manual Deployment (Development)
```bash
# Start the stack manually
./azerothcore-deploy.sh start

# Monitor status
./azerothcore-deploy.sh status

# View logs
./azerothcore-deploy.sh logs ac-worldserver

# Stop the stack
./azerothcore-deploy.sh stop
```

### 3. System Service Installation (Production)
```bash
# Install as system service
sudo ./install-system-service.sh install

# Start services
sudo systemctl start azerothcore

# Check status
sudo systemctl status azerothcore

# Enable auto-start on boot (already enabled by installer)
sudo systemctl enable azerothcore
```

## 📊 Monitoring & Management

### Web Dashboard
- **URL**: http://localhost:8080
- **Features**: Real-time service status, resource usage, recent alerts
- **Auto-refresh**: Updates every 30 seconds

### Command Line Monitoring
```bash
# Real-time monitoring
./azerothcore-monitor.sh monitor

# Generate status page
./azerothcore-monitor.sh status

# View alerts
./azerothcore-monitor.sh alerts

# View metrics
./azerothcore-monitor.sh metrics
```

### System Service Management
```bash
# Start services
sudo systemctl start azerothcore

# Stop services
sudo systemctl stop azerothcore

# Restart services
sudo systemctl restart azerothcore

# Check status
sudo systemctl status azerothcore

# View logs
sudo journalctl -u azerothcore -f

# Check monitoring service
sudo systemctl status azerothcore-monitor

# Check web service
sudo systemctl status azerothcore-web
```

## 🔧 Configuration

### Environment Files
- `.env-database-local`: Local development settings
- `.env-production`: Production optimized settings (auto-created during system install)

### Key Configuration Options
```bash
# Database settings
MYSQL_ROOT_PASSWORD=azerothcore123
DB_WAIT_RETRIES=60
DB_WAIT_SLEEP=10

# Performance settings
MYSQL_MAX_CONNECTIONS=200
MYSQL_INNODB_BUFFER_POOL_SIZE=512M
PLAYERBOT_MAX_BOTS=20

# Storage paths
STORAGE_PATH=./local-data  # or /opt/azerothcore/data for system install
```

## 🗂️ Directory Structure

```
azerothcore-compose2/
├── azerothcore-deploy.sh           # Main deployment script
├── azerothcore-monitor.sh          # Monitoring script
├── install-system-service.sh       # System service installer
├── test-deployment.sh              # Test suite
├── docker-compose-*.yml            # Service layer definitions
├── .env-*                          # Environment configurations
├── deployment-logs/                # Deployment logs
├── monitoring-logs/                # Monitoring logs
├── monitoring-web/                 # Web dashboard files
├── local-data/                     # Application data
├── backups/                        # Database backups
└── backup-scripts/                 # Backup scripts
```

## 🚀 Deployment Layers

### 1. Database Layer
- **Services**: MySQL, DB Init, DB Import, Backup, Persistence
- **Purpose**: Core database infrastructure
- **Startup Time**: 2-5 minutes

### 2. Services Layer
- **Services**: Auth Server, World Server, Client Data
- **Purpose**: Core game servers
- **Startup Time**: 5-15 minutes (includes 15GB client data download)

### 3. Optional Layer
- **Services**: Eluna, Modules, Playerbots
- **Purpose**: Enhanced features and scripting
- **Startup Time**: 1-2 minutes

### 4. Tools Layer
- **Services**: PHPMyAdmin, Keira3, Grafana, InfluxDB
- **Purpose**: Management and monitoring interfaces
- **Startup Time**: 2-3 minutes

## 🔍 Troubleshooting

### Common Issues

#### Services Not Starting
```bash
# Check Docker daemon
sudo systemctl status docker

# Check logs
./azerothcore-deploy.sh logs [service-name]

# Check resource usage
docker stats

# Restart specific layer
docker-compose -f docker-compose-azerothcore-database.yml restart
```

#### Database Connection Issues
```bash
# Test database connectivity
docker exec ac-mysql mysql -uroot -pazerothcore123 -e "SELECT 1;"

# Check database logs
docker logs ac-mysql

# Verify network
docker network ls | grep azerothcore
```

#### Web Dashboard Not Accessible
```bash
# Check web service
sudo systemctl status azerothcore-web

# Check port availability
sudo netstat -tlnp | grep 8080

# Restart web service
sudo systemctl restart azerothcore-web
```

#### High Resource Usage
```bash
# Check container stats
docker stats

# Reduce playerbot count
# Edit .env: PLAYERBOT_MAX_BOTS=5

# Reduce MySQL buffer size
# Edit .env: MYSQL_INNODB_BUFFER_POOL_SIZE=256M
```

### Log Locations

#### Manual Deployment
- **Deployment Logs**: `./deployment-logs/`
- **Monitoring Logs**: `./monitoring-logs/`
- **Container Logs**: `docker logs [container-name]`

#### System Service
- **System Logs**: `sudo journalctl -u azerothcore`
- **Application Logs**: `/opt/azerothcore/deployment-logs/`
- **Monitoring Logs**: `/opt/azerothcore/monitoring-logs/`

## 🔐 Security Considerations

### Default Security Features
- Dedicated service user (`azerothcore`)
- Firewall rules for game ports only
- Database access restricted to localhost
- Non-root container execution where possible
- Secure systemd service configuration

### Additional Security Recommendations
```bash
# Configure UFW firewall
sudo ufw enable
sudo ufw default deny incoming
sudo ufw allow ssh

# Update system regularly
sudo apt update && sudo apt upgrade

# Monitor logs for suspicious activity
sudo journalctl -u azerothcore | grep -i error

# Change default passwords
# Edit .env: MYSQL_ROOT_PASSWORD=your-secure-password
```

## 🔄 Backup & Recovery

### Automated Backups
- **Schedule**: Daily at 3:00 AM (configurable)
- **Location**: `./backups/` or `/opt/azerothcore/backups/`
- **Retention**: 7 days (configurable)
- **Format**: SQL dumps with timestamp

### Manual Backup
```bash
# Create immediate backup
docker exec ac-mysql mysqldump -uroot -pazerothcore123 --all-databases > backup-$(date +%Y%m%d).sql

# Backup with backup script
./backup-scripts/backup.sh
```

### Recovery
```bash
# Stop services
./azerothcore-deploy.sh stop

# Restore from backup
docker run --rm -v $(pwd)/backups:/backups -v azerothcore_mysql_data:/var/lib/mysql mysql:8.0 \
  sh -c "mysql -uroot -pazerothcore123 < /backups/your-backup.sql"

# Restart services
./azerothcore-deploy.sh start
```

## 🗑️ Uninstallation

### Manual Deployment
```bash
# Stop and remove containers
./azerothcore-deploy.sh stop
docker system prune -a --volumes

# Remove data (optional)
rm -rf local-data backups deployment-logs monitoring-logs
```

### System Service
```bash
# Run uninstaller
sudo /opt/azerothcore/uninstall.sh

# Follow prompts to remove data directories
```

## 📞 Support

### Documentation
- [AzerothCore Wiki](https://www.azerothcore.org/wiki/)
- [Docker Documentation](https://docs.docker.com/)
- [Docker Compose Reference](https://docs.docker.com/compose/)

### Getting Help
1. Check logs for error messages
2. Run diagnostic tests: `./test-deployment.sh all`
3. Search [AzerothCore Discord](https://discord.gg/azerothcore)
4. Review [GitHub Issues](https://github.com/azerothcore/azerothcore-wotlk/issues)

### Performance Tuning
- Adjust `PLAYERBOT_MAX_BOTS` based on server capacity
- Tune MySQL settings for your hardware
- Monitor resource usage and scale accordingly
- Consider SSD storage for better I/O performance

---

## 🎉 Enjoy Your AzerothCore Server!

Your World of Warcraft server is now ready to accept connections:

- **Auth Server**: `localhost:3784`
- **World Server**: `localhost:8215`
- **Web Dashboard**: `http://localhost:8080`
- **Database**: `localhost:64306` (internal use)

Happy gaming! 🏰⚔️🛡️