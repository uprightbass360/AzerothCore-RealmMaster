#!/bin/bash
# Continuously ensure the MySQL runtime tmpfs contains the restored data.
# If the runtime tables are missing (for example after a host reboot),
# automatically rerun db-import-conditional to hydrate from backups.
set -euo pipefail

log(){ echo "🛡️ [db-guard] $*"; }
warn(){ echo "⚠️ [db-guard] $*" >&2; }
err(){ echo "❌ [db-guard] $*" >&2; }

MYSQL_HOST="${CONTAINER_MYSQL:-ac-mysql}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASS="${MYSQL_ROOT_PASSWORD:-root}"
IMPORT_SCRIPT="${DB_GUARD_IMPORT_SCRIPT:-/tmp/db-import-conditional.sh}"

RECHECK_SECONDS="${DB_GUARD_RECHECK_SECONDS:-120}"
RETRY_SECONDS="${DB_GUARD_RETRY_SECONDS:-10}"
WAIT_ATTEMPTS="${DB_GUARD_WAIT_ATTEMPTS:-60}"
VERIFY_INTERVAL="${DB_GUARD_VERIFY_INTERVAL_SECONDS:-0}"
VERIFY_FILE="${DB_GUARD_VERIFY_FILE:-/tmp/db-guard.last-verify}"
HEALTH_FILE="${DB_GUARD_HEALTH_FILE:-/tmp/db-guard.ready}"
STATUS_FILE="${DB_GUARD_STATUS_FILE:-/tmp/db-guard.status}"
ERROR_FILE="${DB_GUARD_ERROR_FILE:-/tmp/db-guard.error}"
MODULE_SQL_HOST_PATH="${MODULE_SQL_HOST_PATH:-/modules-sql}"

declare -a DB_SCHEMAS=()
for var in DB_AUTH_NAME DB_WORLD_NAME DB_CHARACTERS_NAME DB_PLAYERBOTS_NAME; do
  value="${!var:-}"
  if [ -n "$value" ]; then
    DB_SCHEMAS+=("$value")
  fi
done

if [ -n "${DB_GUARD_EXTRA_DATABASES:-}" ]; then
  IFS=',' read -ra extra <<< "${DB_GUARD_EXTRA_DATABASES}"
  for db in "${extra[@]}"; do
    if [ -n "${db// }" ]; then
      DB_SCHEMAS+=("${db// }")
    fi
  done
fi

if [ "${#DB_SCHEMAS[@]}" -eq 0 ]; then
  DB_SCHEMAS=(acore_auth acore_world acore_characters)
fi

SCHEMA_LIST_SQL="$(printf "'%s'," "${DB_SCHEMAS[@]}")"
SCHEMA_LIST_SQL="${SCHEMA_LIST_SQL%,}"

mark_ready(){
  mkdir -p "$(dirname "$HEALTH_FILE")" 2>/dev/null || true
  printf '%s\t%s\n' "$(date -Iseconds)" "$*" | tee "$STATUS_FILE" >/dev/null
  : > "$ERROR_FILE"
  printf '%s\n' "$*" > "$HEALTH_FILE"
}

mark_unhealthy(){
  printf '%s\t%s\n' "$(date -Iseconds)" "$*" | tee "$ERROR_FILE" >&2
  rm -f "$HEALTH_FILE" 2>/dev/null || true
}

wait_for_mysql(){
  local attempts="$WAIT_ATTEMPTS"
  while [ "$attempts" -gt 0 ]; do
    if MYSQL_PWD="$MYSQL_PASS" mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -e "SELECT 1" >/dev/null 2>&1; then
      return 0
    fi
    attempts=$((attempts - 1))
    sleep "$RETRY_SECONDS"
  done
  return 1
}

table_count(){
  local query="SELECT COUNT(*) FROM information_schema.tables WHERE table_schema IN (${SCHEMA_LIST_SQL});"
  MYSQL_PWD="$MYSQL_PASS" mysql -h "$MYSQL_HOST" -P "$MYSQL_PORT" -u "$MYSQL_USER" -N -B -e "$query"
}

rehydrate(){
  if [ ! -x "$IMPORT_SCRIPT" ]; then
    err "Import script not found at ${IMPORT_SCRIPT}"
    return 1
  fi
  "$IMPORT_SCRIPT"
}

ensure_dbimport_conf(){
  local conf="/azerothcore/env/dist/etc/dbimport.conf"
  local dist="${conf}.dist"
  if [ ! -f "$conf" ] && [ -f "$dist" ]; then
    cp "$dist" "$conf"
  fi
  mkdir -p /azerothcore/env/dist/temp
}

sync_host_stage_files(){
  local host_root="${MODULE_SQL_HOST_PATH}"
  [ -d "$host_root" ] || return 0
  for dir in db_world db_characters db_auth db_playerbots; do
    local src="$host_root/$dir"
    local dest="/azerothcore/data/sql/updates/$dir"
    mkdir -p "$dest"
    rm -f "$dest"/MODULE_*.sql >/dev/null 2>&1 || true
    if [ -d "$src" ]; then
      cp -a "$src"/MODULE_*.sql "$dest"/ >/dev/null 2>&1 || true
    fi
  done
}

dbimport_verify(){
  local bin_dir="/azerothcore/env/dist/bin"
  ensure_dbimport_conf
  sync_host_stage_files
  if [ ! -x "${bin_dir}/dbimport" ]; then
    warn "dbimport binary not found at ${bin_dir}/dbimport"
    return 1
  fi
  log "Running dbimport verification sweep..."
  if (cd "$bin_dir" && ./dbimport); then
    log "dbimport verification finished successfully"
    return 0
  fi
  warn "dbimport verification reported issues - review dbimport logs"
  return 1
}

maybe_run_verification(){
  if [ "${VERIFY_INTERVAL}" -lt 0 ]; then
    return 0
  fi
  local now last_run=0
  now="$(date +%s)"
  if [ -f "$VERIFY_FILE" ]; then
    last_run="$(cat "$VERIFY_FILE" 2>/dev/null || echo 0)"
    if [ "$VERIFY_INTERVAL" -eq 0 ]; then
      return 0
    fi
    if [ $((now - last_run)) -lt "${VERIFY_INTERVAL}" ]; then
      return 0
    fi
  fi
  if dbimport_verify; then
    echo "$now" > "$VERIFY_FILE"
  else
    warn "dbimport verification failed; will retry in ${VERIFY_INTERVAL}s"
  fi
}

log "Watching MySQL (${MYSQL_HOST}:${MYSQL_PORT}) for ${#DB_SCHEMAS[@]} schemas: ${DB_SCHEMAS[*]}"

while true; do
  if ! wait_for_mysql; then
    mark_unhealthy "MySQL is unreachable after ${WAIT_ATTEMPTS} attempts"
    sleep "$RETRY_SECONDS"
    continue
  fi

  count="$(table_count 2>/dev/null || echo "")"
  if [ -n "$count" ]; then
    if [ "$count" -gt 0 ] 2>/dev/null; then
      mark_ready "Detected ${count} tables across tracked schemas"
      maybe_run_verification
      sleep "$RECHECK_SECONDS"
      continue
    fi
  fi

  warn "No tables detected across ${DB_SCHEMAS[*]}; running rehydrate workflow..."
  if rehydrate; then
    log "Rehydrate complete - rechecking tables"
    sleep 5
    continue
  fi

  mark_unhealthy "Rehydrate workflow failed - retrying in ${RETRY_SECONDS}s"
  sleep "$RETRY_SECONDS"
done
