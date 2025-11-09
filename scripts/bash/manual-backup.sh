#!/bin/bash
# Trigger an on-demand database backup via the ac-backup container.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"

usage(){
  cat <<'USAGE'
Usage: ./scripts/bash/manual-backup.sh [options]

Options:
  --label NAME        Prefix for the backup directory (default: manual)
  --container NAME    Override backup container name (default: CONTAINER_BACKUP from .env)
  -h, --help          Show this help and exit
USAGE
}

read_env(){
  local key="$1" default="$2" value=""
  if [[ -f "$ENV_FILE" ]]; then
    value="$(grep -E "^${key}=" "$ENV_FILE" | tail -n1 | cut -d'=' -f2- | tr -d $'\r')"
  fi
  [[ -n "$value" ]] || value="$default"
  echo "$value"
}

LABEL="manual"
CONTAINER_BACKUP="$(read_env CONTAINER_BACKUP "ac-backup")"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --label) LABEL="$2"; shift 2;;
    --container) CONTAINER_BACKUP="$2"; shift 2;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage; exit 1;;
  esac
done

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER_BACKUP"; then
  echo "❌ Backup container '$CONTAINER_BACKUP' is not running. Start it with 'docker compose up -d ac-backup'." >&2
  exit 1
fi

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
TARGET_DIR="/backups/${LABEL}_${TIMESTAMP}"

# shellcheck disable=SC2016
docker exec -i \
  -e LABEL="$LABEL" \
  -e TIMESTAMP="$TIMESTAMP" \
  -e TARGET_DIR="$TARGET_DIR" \
  "$CONTAINER_BACKUP" bash <<'SCRIPT'
set -euo pipefail
LABEL="${LABEL}"
TIMESTAMP="${TIMESTAMP}"
TARGET_DIR="${TARGET_DIR}"

mkdir -p "${TARGET_DIR}"
export MYSQL_PWD="${MYSQL_PASSWORD}"

dbs=("${DB_AUTH_NAME}" "${DB_WORLD_NAME}" "${DB_CHARACTERS_NAME}")
if mysql -h"${MYSQL_HOST}" -P"${MYSQL_PORT}" -u"${MYSQL_USER}" -e "USE ${DB_PLAYERBOTS_NAME:-acore_playerbots};" >/dev/null 2>&1; then
  dbs+=("${DB_PLAYERBOTS_NAME:-acore_playerbots}")
fi

for db in "${dbs[@]}"; do
  echo "[manual] Backing up ${db} -> ${TARGET_DIR}/${db}.sql.gz"
  mysqldump -h"${MYSQL_HOST}" -P"${MYSQL_PORT}" -u"${MYSQL_USER}" \
    --single-transaction --routines --triggers --events \
    --hex-blob --quick --lock-tables=false --add-drop-database \
    --databases "${db}" | gzip -c > "${TARGET_DIR}/${db}.sql.gz"
  echo "[manual] ✅ ${db}"
done

size="$(du -sh "${TARGET_DIR}" | cut -f1)"
cat > "${TARGET_DIR}/manifest.json" <<EOF
{
  "timestamp": "${TIMESTAMP}",
  "label": "${LABEL}",
  "databases": [$(printf '"%s",' "${dbs[@]}" | sed 's/,$//')],
  "backup_size": "${size}",
  "mode": "manual"
}
EOF

chown -R ${CONTAINER_USER:-1000:1000} "${TARGET_DIR}" 2>/dev/null || true
chmod -R 750 "${TARGET_DIR}" 2>/dev/null || true
echo "[manual] Backup complete: ${TARGET_DIR} (size ${size})"
SCRIPT
