#!/bin/bash
# Wrapper entrypoint to adapt MySQL container UID/GID to match host user expectations.
set -euo pipefail

ORIGINAL_ENTRYPOINT="${MYSQL_ORIGINAL_ENTRYPOINT:-docker-entrypoint.sh}"
if ! command -v "$ORIGINAL_ENTRYPOINT" >/dev/null 2>&1; then
  # Fallback to common install path
  if [ -x /usr/local/bin/docker-entrypoint.sh ]; then
    ORIGINAL_ENTRYPOINT=/usr/local/bin/docker-entrypoint.sh
  fi
fi

TARGET_SPEC="${MYSQL_RUNTIME_USER:-${CONTAINER_USER:-}}"
target_group_name=""
if [ -n "${TARGET_SPEC:-}" ] && [ "${TARGET_SPEC}" != "0:0" ]; then
  if [[ "$TARGET_SPEC" != *:* ]]; then
    echo "mysql-entrypoint: Expected MYSQL_RUNTIME_USER/CONTAINER_USER in uid:gid form, got '${TARGET_SPEC}'" >&2
    exit 1
  fi

  IFS=':' read -r TARGET_UID TARGET_GID <<< "$TARGET_SPEC"

  if ! [[ "$TARGET_UID" =~ ^[0-9]+$ ]] || ! [[ "$TARGET_GID" =~ ^[0-9]+$ ]]; then
    echo "mysql-entrypoint: UID/GID must be numeric (received uid='${TARGET_UID}' gid='${TARGET_GID}')" >&2
    exit 1
  fi

  if ! id mysql >/dev/null 2>&1; then
    echo "mysql-entrypoint: mysql user not found in container" >&2
    exit 1
  fi

  current_uid="$(id -u mysql)"
  current_gid="$(id -g mysql)"

  # Adjust group if needed
  if [ "$current_gid" != "$TARGET_GID" ]; then
    if groupmod -g "$TARGET_GID" mysql 2>/dev/null; then
      target_group_name="mysql"
    else
      existing_group="$(getent group "$TARGET_GID" | cut -d: -f1 || true)"
      if [ -z "$existing_group" ]; then
        existing_group="mysql-host"
        if ! getent group "$existing_group" >/dev/null 2>&1; then
          groupadd -g "$TARGET_GID" "$existing_group"
        fi
      fi
      usermod -g "$existing_group" mysql
      target_group_name="$existing_group"
    fi
  else
    target_group_name="$(getent group mysql | cut -d: -f1)"
  fi

  if [ -z "$target_group_name" ]; then
    target_group_name="$(getent group "$TARGET_GID" | cut -d: -f1 || true)"
  fi

  # Adjust user UID if needed
  if [ "$current_uid" != "$TARGET_UID" ]; then
    if getent passwd "$TARGET_UID" >/dev/null 2>&1 && [ "$(getent passwd "$TARGET_UID" | cut -d: -f1)" != "mysql" ]; then
      echo "mysql-entrypoint: UID ${TARGET_UID} already in use by $(getent passwd "$TARGET_UID" | cut -d: -f1)." >&2
      echo "mysql-entrypoint: Please choose a different CONTAINER_USER or adjust the image." >&2
      exit 1
    fi
    usermod -u "$TARGET_UID" mysql
  fi

  # Ensure group lookup after potential changes
  target_group_name="$(getent group "$TARGET_GID" | cut -d: -f1 || echo "$target_group_name")"
else
  target_group_name="$(getent group mysql | cut -d: -f1 || echo mysql)"
fi

# Update ownership on relevant directories if they exist
for path in /var/lib/mysql-runtime /var/lib/mysql /var/lib/mysql-persistent /backups; do
  if [ -e "$path" ]; then
    chown -R mysql:"$target_group_name" "$path"
  fi
done

# Minimal fix: Restore data from persistent storage on startup and sync on shutdown only
RUNTIME_DIR="/var/lib/mysql-runtime"
PERSISTENT_DIR="/var/lib/mysql-persistent"

sync_datadir() {
  if [ ! -d "$RUNTIME_DIR" ]; then
    echo "⚠️  Runtime directory not found: $RUNTIME_DIR"
    return 1
  fi
  if [ ! -d "$PERSISTENT_DIR" ]; then
    echo "⚠️  Persistent directory not found: $PERSISTENT_DIR"
    return 1
  fi

  user_schema_count="$(find "$RUNTIME_DIR" -mindepth 1 -maxdepth 1 -type d \
    ! -name mysql \
    ! -name performance_schema \
    ! -name information_schema \
    ! -name sys \
    ! -name "#innodb_temp" \
    ! -name "#innodb_redo" 2>/dev/null | wc -l | tr -d ' ')"
  if [ "${user_schema_count:-0}" -eq 0 ]; then
    echo "⚠️  Runtime data appears empty (system schemas only); skipping sync"
    return 0
  fi

  echo "📦 Syncing MySQL data to persistent storage..."
  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete \
      --exclude='.restore-completed' \
      --exclude='.restore-failed' \
      --exclude='.import-completed' \
      --exclude='backup.sql' \
      "$RUNTIME_DIR"/ "$PERSISTENT_DIR"/
  else
    # Mirror the runtime state while preserving marker files.
    find "$PERSISTENT_DIR" -mindepth 1 -maxdepth 1 \
      ! -name ".restore-completed" \
      ! -name ".restore-failed" \
      ! -name ".import-completed" \
      ! -name "backup.sql" \
      -exec rm -rf {} + 2>/dev/null || true
    cp -a "$RUNTIME_DIR"/. "$PERSISTENT_DIR"/
  fi
  chown -R mysql:"$target_group_name" "$PERSISTENT_DIR"
  echo "✅ Sync completed"
}

handle_shutdown() {
  echo "🔻 Shutdown signal received"
  if command -v mysqladmin >/dev/null 2>&1; then
    if mysqladmin -h localhost -u root -p"${MYSQL_ROOT_PASSWORD:-}" shutdown 2>/dev/null; then
      echo "✅ MySQL shutdown complete"
      sync_datadir || true
    else
      echo "⚠️  mysqladmin shutdown failed; skipping sync to avoid corruption"
    fi
  else
    echo "⚠️  mysqladmin not found; skipping sync"
  fi

  if [ -n "${child_pid:-}" ] && kill -0 "$child_pid" 2>/dev/null; then
    wait "$child_pid" || true
  fi
  exit 0
}

# Simple startup restoration
if [ -d "$PERSISTENT_DIR" ]; then
  # Check for MySQL data files (exclude marker files starting with .)
  if find "$PERSISTENT_DIR" -maxdepth 1 -name "*" ! -name ".*" ! -path "$PERSISTENT_DIR" | grep -q .; then
    if [ -d "$RUNTIME_DIR" ] && [ -z "$(ls -A "$RUNTIME_DIR" 2>/dev/null)" ]; then
      echo "🔄 Restoring MySQL data from persistent storage..."
      cp -a "$PERSISTENT_DIR"/* "$RUNTIME_DIR/" 2>/dev/null || true
      chown -R mysql:"$target_group_name" "$RUNTIME_DIR"
      echo "✅ Data restored from persistent storage"
    fi
  fi
fi

# Simple approach: restore on startup only
# Data loss window exists but prevents complete loss on restart

trap handle_shutdown TERM INT

disable_binlog="${MYSQL_DISABLE_BINLOG:-}"
if [ "${disable_binlog}" = "1" ]; then
  add_skip_flag=1
  for arg in "$@"; do
    if [ "$arg" = "--skip-log-bin" ] || [[ "$arg" == --log-bin* ]]; then
      add_skip_flag=0
      break
    fi
  done
  if [ "$add_skip_flag" -eq 1 ]; then
    set -- "$@" --skip-log-bin
  fi
fi

"$ORIGINAL_ENTRYPOINT" "$@" &
child_pid=$!
wait "$child_pid"
