# AzerothCore Deployment Guide

## 🚀 Quick Deployment Options

### **Option 1: Fast Deployment (Use Cached Images)**
Set this in `.env-core` for fastest deployment:
```bash
IMAGE_PULL_POLICY=if_not_present
SKIP_CLIENT_DATA_IF_EXISTS=true
ENABLE_PARALLEL_STARTUP=true
```

### **Option 2: Always Fresh Images**
For production deployments with latest images:
```bash
IMAGE_PULL_POLICY=always
SKIP_CLIENT_DATA_IF_EXISTS=false
ENABLE_PARALLEL_STARTUP=true
```

### **Option 3: Offline Deployment**
If images are already present locally:
```bash
IMAGE_PULL_POLICY=never
SKIP_CLIENT_DATA_IF_EXISTS=true
ENABLE_PARALLEL_STARTUP=true
```

## 📊 Image Pull Policy Options

| Policy | Speed | Reliability | Use Case |
|--------|-------|-------------|----------|
| `if_not_present` | ⚡ Fast | ✅ Good | **Recommended** - Best balance |
| `always` | 🐌 Slow | ✅ Best | Production with latest images |
| `never` | ⚡ Fastest | ⚠️ Risk | Offline or cached deployments |

## 🛠️ Pre-deployment Steps (Optional)

To avoid Portainer timeouts, pre-pull images manually:

```bash
# Core AzerothCore images (large downloads)
docker pull acore/ac-wotlk-db-import:14.0.0-dev
docker pull acore/ac-wotlk-authserver:14.0.0-dev
docker pull acore/ac-wotlk-worldserver:14.0.0-dev
docker pull acore/eluna-ts:master

# Base images (usually cached)
docker pull mysql:8.0
docker pull alpine:latest
docker pull alpine/git:latest
```

## 🏗️ Staged Deployment Strategy

If experiencing timeouts, deploy in stages:

### **Stage 1: Database Layer**
Deploy only MySQL and database initialization:
```yaml
services:
  ac-mysql-init: ...
  ac-mysql: ...
  ac-db-init: ...
  ac-db-import: ...
```

### **Stage 2: Core Services**
Add authentication and world servers:
```yaml
services:
  ac-authserver: ...
  ac-client-data: ...
  ac-worldserver: ...
```

### **Stage 3: Optional Services**
Add monitoring and modules:
```yaml
services:
  ac-eluna: ...
  ac-modules: ...
  ac-backup: ...
```

## 🎯 Troubleshooting Deployment Issues

### **504 Gateway Timeout in Portainer**
- **Cause**: Large image downloads or client data download (15GB)
- **Solutions**:
  1. Set `IMAGE_PULL_POLICY=if_not_present`
  2. Pre-pull images manually
  3. Use staged deployment
  4. Increase Portainer timeout settings

### **Container "Already Exists" Errors**
- **Cause**: Previous deployment attempts left containers
- **Solution**: Remove old containers first:
```bash
docker container prune -f
docker volume prune -f
```

### **Client Data Download Timeout**
- **Cause**: 15GB download takes time
- **Solutions**:
  1. Set `SKIP_CLIENT_DATA_IF_EXISTS=true`
  2. Pre-download data manually
  3. Use faster internet connection

## 📋 Environment Variables for Speed Optimization

```bash
# Image handling
IMAGE_PULL_POLICY=if_not_present

# Deployment optimization
SKIP_CLIENT_DATA_IF_EXISTS=true
ENABLE_PARALLEL_STARTUP=true

# Reduce health check intervals for faster startup
MYSQL_HEALTHCHECK_INTERVAL=5s
MYSQL_HEALTHCHECK_TIMEOUT=3s
AUTH_HEALTHCHECK_INTERVAL=10s
WORLD_HEALTHCHECK_INTERVAL=15s
```

## 🚨 Production vs Development Settings

### **Development (Fast Deployment)**
```bash
IMAGE_PULL_POLICY=if_not_present
SKIP_CLIENT_DATA_IF_EXISTS=true
MYSQL_HEALTHCHECK_INTERVAL=5s
```

### **Production (Reliable Deployment)**
```bash
IMAGE_PULL_POLICY=always
SKIP_CLIENT_DATA_IF_EXISTS=false
MYSQL_HEALTHCHECK_INTERVAL=15s
```

## 📊 Expected Deployment Times

| Configuration | First Deploy | Subsequent Deploys |
|---------------|--------------|-------------------|
| Fast (cached) | 5-10 minutes | 2-3 minutes |
| Standard | 15-20 minutes | 5-8 minutes |
| Always pull | 20-30 minutes | 15-20 minutes |

*Times vary based on internet speed and server performance*