# AzerothCore Deployment & Health Check

This document describes how to use the automated deployment and health check script for the AzerothCore Docker stack.

## Quick Start

The script is located in the `scripts/` directory and should be run from there:

### Full Deployment and Health Check
```bash
cd scripts
./deploy-and-check.sh
```

### Health Check Only (Skip Deployment)
```bash
cd scripts
./deploy-and-check.sh --skip-deploy
```

### Quick Health Check (Basic Tests Only)
```bash
cd scripts
./deploy-and-check.sh --skip-deploy --quick-check
```

## Script Features

### Deployment
- **Layered Deployment**: Deploys database → services → tools layers in correct order
- **Dependency Waiting**: Waits for each layer to be ready before proceeding
- **Error Handling**: Stops on errors with clear error messages
- **Progress Monitoring**: Shows deployment progress and status

### Health Checks
- **Container Health**: Verifies all containers are running and healthy
- **Port Connectivity**: Tests all external ports are accessible
- **Web Service Verification**: Validates web interfaces are responding correctly
- **Database Validation**: Confirms database schemas and realm configuration
- **Comprehensive Reporting**: Color-coded status with detailed results

## Command Line Options

| Option | Description |
|--------|-------------|
| `--skip-deploy` | Skip the deployment phase, only run health checks |
| `--quick-check` | Run basic health checks only (faster, less comprehensive) |
| `--help` | Show usage information |

## What Gets Checked

### Container Health Status
- ✅ **ac-mysql**: Database server
- ✅ **ac-backup**: Automated backup service
- ✅ **ac-authserver**: Authentication server
- ✅ **ac-worldserver**: Game world server
- ✅ **ac-phpmyadmin**: Database management interface
- ✅ **ac-keira3**: Database editor

### Port Connectivity Tests
- **Database Layer**: MySQL (64306)
- **Services Layer**: Auth Server (3784), World Server (8215), SOAP API (7778)
- **Tools Layer**: PHPMyAdmin (8081), Keira3 (4201)

### Web Service Health Checks 
- **PHPMyAdmin**: HTTP response and content verification
- **Keira3**: Health endpoint and content verification

### Database Validation 
- **Schema Verification**: Confirms all required databases exist
- **Realm Configuration**: Validates realm setup

## Service URLs and Credentials

### Web Interfaces
- 🌐 **PHPMyAdmin**: http://localhost:8081
- 🛠️ **Keira3**: http://localhost:4201

### Game Connections
- 🎮 **Game Server**: localhost:8215
- 🔐 **Auth Server**: localhost:3784
- 🔧 **SOAP API**: localhost:7778
- 🗄️ **MySQL**: localhost:64306

### Default Credentials
- **MySQL**: root / azerothcore123

## Deployment Process

The script follows this deployment sequence:

### 1. Database Layer
- Deploys MySQL database server
- Waits for MySQL to be ready
- Runs database initialization
- Imports AzerothCore schemas
- Starts backup service

### 2. Services Layer
- Deploys authentication server
- Starts client data download/extraction (10-20 minutes)
- Deploys world server (waits for client data)
- Starts module management service

### 3. Tools Layer
- Deploys PHPMyAdmin database interface
- Deploys Keira3 database editor

## Troubleshooting

### Common Issues

**Port conflicts**: If ports are already in use, modify the environment files to use different external ports.

**Slow client data download**: The initial download is ~15GB and may take 10-30 minutes depending on connection speed.

**Container restart loops**: Check container logs with `docker logs <container-name>` for specific error messages.

### Manual Checks

```bash
# Check container status
docker ps | grep ac-

# Check specific container logs
docker logs ac-worldserver --tail 50

# Test port connectivity manually
nc -z localhost 8215

# Check container health
docker inspect ac-mysql --format='{{.State.Health.Status}}'
```

### Recovery Commands

```bash
# Restart specific layer
docker compose -f docker-compose-azerothcore-services.yml restart

# Reset specific service
docker compose -f docker-compose-azerothcore-services.yml stop ac-worldserver
docker compose -f docker-compose-azerothcore-services.yml up -d ac-worldserver

# Full reset (WARNING: destroys all data)
docker compose -f docker-compose-azerothcore-tools.yml down
docker compose -f docker-compose-azerothcore-services.yml down
docker compose -f docker-compose-azerothcore-database.yml down
docker volume prune -f
```

## Script Exit Codes

- **0**: All health checks passed successfully
- **1**: Health check failures detected or deployment errors

Use the exit code in CI/CD pipelines or automated deployment scripts to determine deployment success.