# Unused Environment Variables Documentation

This document lists all environment variables that were removed from `.env-core` because they are not used by the current Docker Compose setup.

**Total removed**: 117 variables (72% of original configuration)

## 🗄️ Database Configuration (Not Used in Docker Compose)
```bash
AC_LOG_LEVEL_IMPORT=1
AC_LOG_LEVEL_AUTH=1
AC_LOG_LEVEL_WORLD=2
AC_UPDATES_ENABLE_DATABASES_IMPORT=7
AC_UPDATES_ENABLE_DATABASES_SERVERS=0
AC_UPDATES_AUTO_SETUP=1
AC_LOGGER_ROOT_CONFIG=1,Console
AC_LOGGER_SERVER_CONFIG=1,Console
AC_APPENDER_CONSOLE_CONFIG=1,2,0
AC_CLOSE_IDLE_CONNECTIONS=false
```

## 🌐 Network & Connection Settings (Not Used in Docker Compose)
```bash
EXTERNAL_IP=127.0.0.1
BIND_IP=0.0.0.0
SOAP_IP=0.0.0.0
RA_PORT=3443
AC_BIND_IP=0.0.0.0
AC_SOAP_PORT=7878
AC_PROCESS_PRIORITY=0
```

## 📁 Path Configuration (Not Used in Docker Compose)
```bash
AC_DATA_DIR=/azerothcore/data
AC_LOGS_DIR=/azerothcore/logs
AC_CONFIG_DIR=/azerothcore/env/dist/etc
AC_MODULES_DIR=/azerothcore/modules
AC_BIN_DIR=/azerothcore/env/dist/bin
HOST_DATA_PATH=./data
HOST_DB_PATH=/srv/azerothcore/database
HOST_LOGS_PATH=/srv/azerothcore/logs
HOST_CONFIG_PATH=/srv/azerothcore/config
```

## 💾 Volume Names (Not Used in Docker Compose)
```bash
VOLUME_DB_DATA=ac_mysql_data
VOLUME_WORLD_DATA=ac_data
VOLUME_CONFIG=ac_config
VOLUME_LOGS=ac_logs
VOLUME_BACKUP=ac_backup
```

## 📥 Client Data Settings (Not Used in Docker Compose)
```bash
CLIENT_DATA_REPO=wowgaming/client-data
CLIENT_DATA_FALLBACK_VERSION=v16
CLIENT_DATA_REQUIRED_DIRS=maps vmaps mmaps dbc
```

## 🎮 Game Server Configuration (Potentially Used by AzerothCore)
```bash
GAME_TYPE=0
REALM_ID=1
REALM_NAME=AzerothCore
REALM_ZONE=1
REALM_FLAGS=0
REALM_TIMEZONE=1
REALM_ALLOWED_SECURITY_LEVEL=0
REALM_POPULATION=0
REALM_GAMEBUILD=12340
```

## ⚡ Performance Settings (Not Used in Docker Compose)
```bash
PROCESS_PRIORITY=0
USE_PROCESSORS=0
COMPRESSION=1
MAX_CONNECTIONS=1000
MAX_PLAYERS=100
MAX_OVERSPEED_PINGS=2
INNODB_BUFFER_POOL_SIZE=256M
INNODB_LOG_FILE_SIZE=64M
SOCKET_TIMEOUT_TIME=900000
SESSION_ADD_DELAY=10000
GRID_CLEANUP_DELAY=300000
MAP_UPDATE_INTERVAL=100
```

## 🔄 Update Settings (Not Used in Docker Compose)
```bash
UPDATES_ENABLE_DATABASES=7
UPDATES_AUTO_SETUP=1
UPDATES_REDUNDANCY=2
UPDATES_ARCHIVED_REDUNDANCY=0
UPDATES_ALLOW_REHASH=1
UPDATES_CLEAN_DEAD_REF_MAX_COUNT=3
```

## 📝 Logging Configuration (Not Used in Docker Compose)
```bash
LOG_LEVEL=1
LOG_FILE=
LOG_TIMESTAMP=0
LOG_FILE_LEVEL=0
DB_ERROR_LOG_FILE=DBErrors.log
CHAR_LOG_FILE=
GM_LOG_FILE=
RA_LOG_FILE=
SQL_DRIVER_LOG_FILE=
SQL_DRIVER_QUERY_LOGGING=0
```

## 🔧 Feature Flags (Potentially Used by AzerothCore)
```bash
CONSOLE_ENABLE=1
SOAP_ENABLED=0
RA_ENABLE=0
RA_IP=127.0.0.1
RA_MIN_LEVEL=3
CLOSE_IDLE_CONNECTIONS=false
SKIP_BATTLEGROUND_RELOCATE_CHECK=0
```

## 💰 Backup Configuration (Not Used in Docker Compose)
```bash
BACKUP_FILE_PREFIX=acore_backup
```

## 🔒 Security Settings (Potentially Used by AzerothCore)
```bash
WRONG_PASS_MAX_COUNT=3
WRONG_PASS_BAN_TIME=600
WRONG_PASS_BAN_TYPE=0
BAN_EXPIRY_CHECK_INTERVAL=60
```

## 📈 Game Rates (Potentially Used by AzerothCore)
```bash
RATE_HEALTH=1
RATE_MANA=1
RATE_XP_KILL=1
RATE_XP_QUEST=1
RATE_XP_EXPLORE=1
RATE_DROP_MONEY=1
RATE_DROP_ITEMS=1
RATE_HONOR=1
RATE_REPUTATION=1
RATE_TALENT=1
```

## 👤 Character Settings (Potentially Used by AzerothCore)
```bash
CHARACTERS_PER_ACCOUNT=50
CHARACTERS_PER_REALM=10
HEROIC_CHARACTERS_PER_REALM=1
START_PLAYER_LEVEL=1
START_HEROIC_PLAYER_LEVEL=55
START_PLAYER_MONEY=0
START_HEROIC_PLAYER_MONEY=2000
MAX_PLAYER_LEVEL=80
MIN_DUAL_SPEC_LEVEL=40
```

## 🗺️ VMAP/MMAP Settings (Potentially Used by AzerothCore)
```bash
VMAP_ENABLE_LOS=1
VMAP_ENABLE_HEIGHT=1
VMAP_PET_LOS=1
VMAP_ENABLE_INDOOR_CHECK=1
MMAP_ENABLE_PATH_FINDING=0
```

## 🔌 Module Settings (Not Used in Docker Compose)
```bash
ELUNA_ENABLED=1
```

---

## Notes

**Categories marked "Potentially Used by AzerothCore"** may be used by the AzerothCore server configuration files (worldserver.conf, authserver.conf) even though they're not referenced in the Docker Compose file. These might be substituted into configuration files during container startup.

**Categories marked "Not Used in Docker Compose"** are definitely not used by the current Docker setup and can be safely removed.

If you need to restore any of these variables in the future, they can be found in this documentation file.

**Removal Date**: September 29, 2025
**Reason**: Environment cleanup - variables not referenced in docker-compose-azerothcore-core.yml