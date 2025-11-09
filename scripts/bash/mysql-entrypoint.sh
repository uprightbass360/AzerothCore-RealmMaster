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
if [ -z "${TARGET_SPEC:-}" ] || [ "${TARGET_SPEC}" = "0:0" ]; then
  exec "$ORIGINAL_ENTRYPOINT" "$@"
fi

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
target_group_name=""
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

# Update ownership on relevant directories if they exist
for path in /var/lib/mysql-runtime /var/lib/mysql /var/lib/mysql-persistent /backups; do
  if [ -e "$path" ]; then
    chown -R mysql:"$target_group_name" "$path"
  fi
done

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

exec "$ORIGINAL_ENTRYPOINT" "$@"
