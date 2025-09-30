# Scripts Directory

This directory contains deployment and validation scripts for the AzerothCore Docker deployment.

## Contents

- **`deploy-and-check.sh`** - Automated deployment and comprehensive health check script
- **`cleanup.sh`** - Resource cleanup script with multiple cleanup levels
- **`DEPLOYMENT.md`** - Complete documentation for the deployment script
- **`CLEANUP.md`** - Complete documentation for the cleanup script

## Quick Usage

### Run Health Check on Current Deployment
```bash
cd scripts
./deploy-and-check.sh --skip-deploy
```

### Full Deployment with Health Checks
```bash
cd scripts
./deploy-and-check.sh
```

### Quick Health Check (Basic Tests Only)
```bash
cd scripts
./deploy-and-check.sh --skip-deploy --quick-check
```

### Cleanup Resources
```bash
cd scripts

# Stop containers only (safe)
./cleanup.sh --soft

# Remove containers + networks (preserves data)
./cleanup.sh --hard

# Complete removal (DESTROYS ALL DATA)
./cleanup.sh --nuclear

# Dry run to see what would happen
./cleanup.sh --hard --dry-run
```

## Features

✅ **Container Health Validation**: Checks all 8 core containers
✅ **Port Connectivity Tests**: Validates all external ports
✅ **Web Service Verification**: HTTP response and content validation
✅ **Database Validation**: Schema and realm configuration checks
✅ **Automated Deployment**: Three-layer deployment (database → services → tools)
✅ **Comprehensive Reporting**: Color-coded status with detailed results

## Variable Names Verified

The scripts validate the updated variable names:
- `MYSQL_EXTERNAL_PORT` (was `DOCKER_DB_EXTERNAL_PORT`)
- `AUTH_EXTERNAL_PORT` (was `DOCKER_AUTH_EXTERNAL_PORT`)
- `WORLD_EXTERNAL_PORT` (was `DOCKER_WORLD_EXTERNAL_PORT`)
- `SOAP_EXTERNAL_PORT` (was `DOCKER_SOAP_EXTERNAL_PORT`)
- `MYSQL_ROOT_PASSWORD` (was `DOCKER_DB_ROOT_PASSWORD`)

For complete documentation, see `DEPLOYMENT.md`.