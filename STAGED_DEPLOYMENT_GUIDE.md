# AzerothCore Staged Deployment Guide

## 🚀 Three-Layer Deployment Strategy

The AzerothCore setup has been split into three logical layers for faster, more reliable deployments:

1. **Database Layer** - MySQL, database initialization, import, and backup
2. **Core Services Layer** - Authentication server, world server, and client data
3. **Optional Services Layer** - Modules and monitoring services

## 📋 Deployment Order

### **Stage 1: Database Layer** ⭐ **DEPLOY FIRST**
```bash
File: docker-compose-azerothcore-database.yml
Env:  .env-database
```

**Services:**
- `ac-mysql-init` - Fixes NFS permissions
- `ac-mysql` - MySQL database server
- `ac-db-init` - Creates AzerothCore databases
- `ac-db-import` - Imports database schema and data
- `ac-backup` - Automated database backups

**Expected Time:** 5-10 minutes

### **Stage 2: Core Services Layer** ⭐ **DEPLOY SECOND**
```bash
File: docker-compose-azerothcore-services.yml
Env:  .env-services
```

**Services:**
- `ac-client-data` - Downloads 15GB game data (cached after first run)
- `ac-authserver` - Authentication server
- `ac-worldserver` - Game world server with Playerbots

**Expected Time:** 15-20 minutes (first run), 3-5 minutes (subsequent)

### **Stage 3: Optional Services Layer** ⭐ **DEPLOY THIRD**
```bash
File: docker-compose-azerothcore-optional.yml
Env:  .env-optional
```

**Services:**
- `ac-eluna` - Lua scripting engine
- `ac-modules` - Module management and installation

**Expected Time:** 2-3 minutes

## 🛠️ Portainer Deployment Steps

### **Step 1: Deploy Database Layer**

1. **Create Stack in Portainer:**
   - Name: `azerothcore-database`
   - Repository: Select your repository
   - Compose file: `docker-compose-azerothcore-database.yml`
   - Environment file: `.env-database`

2. **Wait for Completion:**
   - Watch logs for "Database import complete!"
   - Verify MySQL health check is green
   - Should complete in 5-10 minutes

### **Step 2: Deploy Core Services Layer**

1. **Create Stack in Portainer:**
   - Name: `azerothcore-services`
   - Repository: Select your repository
   - Compose file: `docker-compose-azerothcore-services.yml`
   - Environment file: `.env-services`

2. **Wait for Completion:**
   - Watch for "Game data setup complete!"
   - Verify auth and world servers are healthy
   - First run: 15-20 minutes, subsequent: 3-5 minutes

### **Step 3: Deploy Optional Services Layer**

1. **Create Stack in Portainer:**
   - Name: `azerothcore-optional`
   - Repository: Select your repository
   - Compose file: `docker-compose-azerothcore-optional.yml`
   - Environment file: `.env-optional`

2. **Wait for Completion:**
   - Should complete quickly (2-3 minutes)

## ✅ Verification Steps

### **After Database Layer:**
```bash
# Check MySQL is running
docker exec ac-mysql mysql -u root -pazerothcore123 -e "SHOW DATABASES;"

# Expected output should include:
# - acore_auth
# - acore_world
# - acore_characters
```

### **After Core Services:**
```bash
# Check auth server
docker logs ac-authserver | tail -10

# Check world server
docker logs ac-worldserver | tail -10

# Look for "AzerothCore ready..." message
```

### **After Optional Services:**
```bash
# Check modules
docker exec ac-modules ls -la /modules

# Should show mod-playerbots directory
```

## 🔧 Configuration Notes

### **Cross-Layer Dependencies:**
- All layers share the same **network**: `azerothcore`
- All layers use the same **storage path**: `/nfs/containers/azerothcore`
- Services layer connects to database via **external_links**

### **Environment Variable Consistency:**
- Database credentials must match across all layers
- Container names must be consistent for external linking
- Network name must be identical

### **Image Pull Optimization:**
All layers use `IMAGE_PULL_POLICY=if_not_present` for fast deployment.

## 🚨 Troubleshooting

### **Database Layer Issues:**
- **MySQL won't start**: Check NFS permissions and storage path
- **Database import fails**: Check container logs for database connection errors
- **Backup fails**: Verify backup scripts directory exists

### **Core Services Issues:**
- **Auth server can't connect**: Verify database layer is healthy first
- **Client data download timeout**: Check internet connection, may take 30+ minutes
- **World server fails**: Ensure client data completed successfully

### **Optional Services Issues:**
- **Modules won't install**: Check git connectivity and storage permissions
- **Eluna won't start**: Verify world server is running first

## 🎯 Benefits of Staged Deployment

1. **Faster Individual Deployments** - Each layer deploys in 2-10 minutes vs 20-30 minutes
2. **Better Error Isolation** - Problems are contained to specific layers
3. **Selective Updates** - Update only the layer that changed
4. **Reduced Portainer Timeouts** - No more 504 Gateway Timeout errors
5. **Easier Debugging** - Clear separation of concerns

## 📊 Deployment Time Comparison

| Method | First Deploy | Update Deploy | Risk |
|--------|--------------|---------------|------|
| **Monolithic** | 20-30 min | 15-20 min | High timeout risk |
| **Staged** | 10-15 min total | 3-8 min per layer | Low timeout risk |

## 🔄 Update Strategy

To update a specific layer:
1. Stop only that layer's stack
2. Update the compose file or environment variables
3. Redeploy just that layer
4. Other layers continue running uninterrupted

This approach provides much better reliability and faster deployment times!