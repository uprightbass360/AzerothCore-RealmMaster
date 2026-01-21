#!/bin/bash
# Restore one or more ACore databases from a backup directory.
set -euo pipefail

INVOCATION_DIR="$PWD"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

source "$SCRIPT_DIR/lib/common.sh"

SUPPORTED_DBS=(auth characters world)
declare -A SUPPORTED_SET=()
for db in "${SUPPORTED_DBS[@]}"; do
  SUPPORTED_SET["$db"]=1
done

declare -A DB_NAMES=([auth]="" [characters]="" [world]="")
declare -a INCLUDE_DBS=()
declare -a SKIP_DBS=()
declare -a ACTIVE_DBS=()

MYSQL_PW=""
BACKUP_DIR=""
BACKUP_PROVIDED=false
EXPLICIT_SELECTION=false

usage(){
  cat <<'EOF'
Usage: ./backup-import.sh [options]

Restores selected ACore databases from a backup directory.

Options:
  -b, --backup-dir DIR      Backup directory (required)
  -p, --password PASS       MySQL root password
      --auth-db NAME        Auth database schema name
      --characters-db NAME  Characters database schema name
      --world-db NAME       World database schema name
      --db LIST             Comma-separated list of databases to import
      --skip LIST           Comma-separated list of databases to skip
      --all                 Import all supported databases
  -h, --help                Show this help and exit

Supported database identifiers: auth, characters, world.
By default the script restores auth and characters databases.

Examples:
  # Restore from specific backup directory
  ./backup-import.sh --backup-dir /path/to/backup --password azerothcore123 --auth-db acore_auth --characters-db acore_characters

  # Restore all databases
  ./backup-import.sh --backup-dir ./storage/backups/ExportBackup_20241029_120000 --password azerothcore123 --all --auth-db acore_auth --characters-db acore_characters --world-db acore_world

  # Restore only world database
  ./backup-import.sh --backup-dir ./backups/daily/latest --password azerothcore123 --db world --world-db acore_world
EOF
}

normalize_token(){
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]'
}

add_unique(){
  local -n arr="$1"
  local value="$2"
  for existing in "${arr[@]:-}"; do
    [[ "$existing" == "$value" ]] && return
  done
  arr+=("$value")
}

parse_db_list(){
  local -n target="$1"
  local value="$2"
  IFS=',' read -ra parts <<<"$value"
  for part in "${parts[@]}"; do
    local token
    token="$(normalize_token "$part")"
    [[ -z "$token" ]] && continue
    if [[ -z "${SUPPORTED_SET[$token]:-}" ]]; then
      fatal "Unknown database identifier: $token (supported: ${SUPPORTED_DBS[*]})"
    fi
    add_unique target "$token"
  done
}

remove_from_list(){
  local -n arr="$1"
  local value="$2"
  local -a filtered=()
  for item in "${arr[@]}"; do
    [[ "$item" == "$value" ]] || filtered+=("$item")
  done
  arr=("${filtered[@]}")
}

resolve_relative(){
  local base="$1" path="$2"
  if command -v python3 >/dev/null 2>&1; then
    python3 - "$base" "$path" <<'PY'
import os, sys
base, path = sys.argv[1:3]
if not path:
    print(os.path.abspath(base))
elif os.path.isabs(path):
    print(os.path.normpath(path))
else:
    print(os.path.normpath(os.path.join(base, path)))
PY
  else
    fatal "python3 is required but was not found on PATH"
  fi
}

load_manifest(){
  local path="$1"
  [[ -f "$path" ]] || return 0
  if ! command -v python3 >/dev/null 2>&1; then
    fatal "python3 is required to read $path"
  fi
  while IFS='=' read -r key value; do
    [[ -n "$key" && -n "$value" ]] || continue
    local token
    token="$(normalize_token "$key")"
    [[ -n "${SUPPORTED_SET[$token]:-}" ]] || continue
    if [[ -z "${DB_NAMES[$token]}" ]]; then
      DB_NAMES[$token]="$value"
    fi
  done < <(python3 - "$path" <<'PY'
import json, sys

SUPPORTED = {
    "auth": {"keys": {"auth"}, "schemas": {"acore_auth"}},
    "characters": {"keys": {"characters", "chars", "char"}, "schemas": {"acore_characters"}},
    "world": {"keys": {"world"}, "schemas": {"acore_world"}},
}

def map_entry(key, value, result):
    if key and key in SUPPORTED:
        result[key] = value
        return
    value_lower = value.lower()
    for ident, meta in SUPPORTED.items():
        if value_lower in meta["schemas"]:
            result.setdefault(ident, value)
            return
    if key:
        for ident, meta in SUPPORTED.items():
            if key in meta["keys"]:
                result.setdefault(ident, value)
                return

def main():
    path = sys.argv[1]
    with open(path, "r", encoding="utf-8") as fh:
        data = json.load(fh)
    result = {}
    databases = data.get("databases")
    if isinstance(databases, dict):
        for key, value in databases.items():
            map_entry(key.lower(), str(value), result)
    elif isinstance(databases, list):
        for value in databases:
            map_entry("", str(value), result)
    for key, value in result.items():
        print(f"{key}={value}")

if __name__ == "__main__":
    main()
PY
)
}

find_dump(){
  local db="$1"
  local hint="${DB_NAMES[$db]}"
  if ! command -v python3 >/dev/null 2>&1; then
    fatal "python3 is required to locate backup dumps"
  fi
  python3 - "$BACKUP_DIR" "$db" "$hint" <<'PY'
import glob, os, sys
backup_dir, db, hint = sys.argv[1:4]

# Search patterns for database dumps
patterns = [
    f"acore_{db}.sql.gz",
    f"acore_{db}.sql",
    f"{db}.sql.gz",
    f"{db}.sql",
]
if hint:
    patterns = [f"{hint}.sql.gz", f"{hint}.sql"] + patterns

# Search locations (in order of preference)
search_dirs = []

# Check for daily backups first (most recent)
daily_dir = os.path.join(backup_dir, "daily")
if os.path.isdir(daily_dir):
    daily_subdirs = [d for d in os.listdir(daily_dir) if os.path.isdir(os.path.join(daily_dir, d))]
    if daily_subdirs:
        latest_daily = max(daily_subdirs, key=lambda x: os.path.getmtime(os.path.join(daily_dir, x)))
        search_dirs.append(os.path.join(daily_dir, latest_daily))

# Check for hourly backups
hourly_dir = os.path.join(backup_dir, "hourly")
if os.path.isdir(hourly_dir):
    hourly_subdirs = [d for d in os.listdir(hourly_dir) if os.path.isdir(os.path.join(hourly_dir, d))]
    if hourly_subdirs:
        latest_hourly = max(hourly_subdirs, key=lambda x: os.path.getmtime(os.path.join(hourly_dir, x)))
        search_dirs.append(os.path.join(hourly_dir, latest_hourly))

# Check for timestamped backup directories
timestamped_dirs = []
try:
    for item in os.listdir(backup_dir):
        item_path = os.path.join(backup_dir, item)
        if os.path.isdir(item_path):
            # Match ExportBackup_YYYYMMDD_HHMMSS or just YYYYMMDD_HHMMSS
            if item.startswith("ExportBackup_") or (len(item) == 15 and item[8] == '_'):
                timestamped_dirs.append(item_path)
except OSError:
    pass

if timestamped_dirs:
    latest_timestamped = max(timestamped_dirs, key=os.path.getmtime)
    search_dirs.append(latest_timestamped)

# Add the main backup directory itself
search_dirs.append(backup_dir)

# Search for matching dumps
seen = {}
matches = []

for search_dir in search_dirs:
    for pattern in patterns:
        for path in glob.glob(os.path.join(search_dir, pattern)):
            if path not in seen and os.path.isfile(path):
                seen[path] = True
                matches.append(path)

if not matches:
    sys.exit(1)

# Return the most recent match
latest = max(matches, key=os.path.getmtime)
print(latest)
PY
}

guess_schema_from_dump(){
  local dump="$1"
  local base
  base="$(basename "$dump")"
  case "$base" in
    acore_auth.sql|acore_auth.sql.gz) echo "acore_auth" ;;
    acore_characters.sql|acore_characters.sql.gz) echo "acore_characters" ;;
    acore_world.sql|acore_world.sql.gz) echo "acore_world" ;;
    *)
      if [[ "$base" =~ ^([A-Za-z0-9_-]+)\.sql(\.gz)?$ ]]; then
        echo "${BASH_REMATCH[1]}"
      fi
      ;;
  esac
}

timestamp(){ date +%Y%m%d_%H%M%S; }

backup_db(){
  local schema="$1" label="$2"
  local out="manual-backups/${label}-pre-import-$(timestamp).sql"
  mkdir -p manual-backups
  log "Backing up current ${schema} to ${out}"
  docker exec ac-mysql mysqldump -uroot -p"$MYSQL_PW" "$schema" > "$out"
}

restore(){
  local schema="$1" dump="$2"
  log "Importing ${dump##*/} into ${schema}"
  case "$dump" in
    *.gz) gzip -dc "$dump" ;;
    *.sql) cat "$dump" ;;
    *) fatal "Unsupported dump format: $dump" ;;
  esac | docker exec -i ac-mysql mysql -uroot -p"$MYSQL_PW" "$schema"
}

db_selected(){
  local needle="$1"
  for item in "${ACTIVE_DBS[@]}"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

count_rows(){
  docker exec ac-mysql mysql -uroot -p"$MYSQL_PW" -N -B -e "$1"
}

case "${1:-}" in
  -h|--help) usage; exit 0;;
esac

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -b|--backup-dir)
      [[ $# -ge 2 ]] || fatal "--backup-dir requires a directory argument"
      BACKUP_DIR="$2"
      BACKUP_PROVIDED=true
      shift 2
      ;;
    -p|--password)
      [[ $# -ge 2 ]] || fatal "--password requires a value"
      MYSQL_PW="$2"
      shift 2
      ;;
    --auth-db)
      [[ $# -ge 2 ]] || fatal "--auth-db requires a value"
      DB_NAMES[auth]="$2"
      shift 2
      ;;
    --characters-db)
      [[ $# -ge 2 ]] || fatal "--characters-db requires a value"
      DB_NAMES[characters]="$2"
      shift 2
      ;;
    --world-db)
      [[ $# -ge 2 ]] || fatal "--world-db requires a value"
      DB_NAMES[world]="$2"
      shift 2
      ;;
    --db|--only)
      [[ $# -ge 2 ]] || fatal "--db requires a value"
      EXPLICIT_SELECTION=true
      parse_db_list INCLUDE_DBS "$2"
      shift 2
      ;;
    --skip)
      [[ $# -ge 2 ]] || fatal "--skip requires a value"
      parse_db_list SKIP_DBS "$2"
      shift 2
      ;;
    --all)
      EXPLICIT_SELECTION=true
      for db in "${SUPPORTED_DBS[@]}"; do
        add_unique INCLUDE_DBS "$db"
      done
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      while [[ $# -gt 0 ]]; do
        POSITIONAL+=("$1")
        shift
      done
      break
      ;;
    -*)
      fatal "Unknown option: $1"
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

if ((${#POSITIONAL[@]} > 0)); then
  fatal "Positional arguments are not supported. Use named options instead."
fi

if $EXPLICIT_SELECTION; then
  ACTIVE_DBS=("${INCLUDE_DBS[@]}")
else
  ACTIVE_DBS=(auth characters)
fi

for skip in "${SKIP_DBS[@]:-}"; do
  remove_from_list ACTIVE_DBS "$skip"
done

if ((${#ACTIVE_DBS[@]} == 0)); then
  fatal "No databases selected for import."
fi

if $BACKUP_PROVIDED; then
  BACKUP_DIR="$(resolve_relative "$INVOCATION_DIR" "$BACKUP_DIR")"
else
  fatal "Backup directory is required. Use --backup-dir DIR to specify."
fi

[[ -d "$BACKUP_DIR" ]] || fatal "Backup directory not found: $BACKUP_DIR"
log "Using backup directory: $BACKUP_DIR"

MANIFEST_PATH="$BACKUP_DIR/manifest.json"
if [[ -f "$MANIFEST_PATH" ]]; then
  load_manifest "$MANIFEST_PATH"
fi

[[ -n "$MYSQL_PW" ]] || fatal "MySQL password is required (use --password)."

declare -A DUMP_PATHS=()
log "Databases selected: ${ACTIVE_DBS[*]}"
for db in "${ACTIVE_DBS[@]}"; do
  if ! dump_path="$(find_dump "$db")"; then
    fatal "No dump found for '$db' in $BACKUP_DIR (expected files like acore_${db}.sql or .sql.gz)."
  fi
  if [[ -z "${DB_NAMES[$db]}" ]]; then
    DB_NAMES[$db]="$(guess_schema_from_dump "$dump_path")"
  fi
  [[ -n "${DB_NAMES[$db]}" ]] || fatal "Missing schema name for '$db'. Provide --${db}-db, include it in manifest.json, or name the dump appropriately."
  DUMP_PATHS["$db"]="$dump_path"
  log "  $db -> ${DB_NAMES[$db]} (using ${dump_path##*/})"
done

log "Stopping world/auth services"
docker stop ac-worldserver ac-authserver >/dev/null || warn "Services already stopped"

for db in "${ACTIVE_DBS[@]}"; do
  backup_db "${DB_NAMES[$db]}" "$db"
  restore "${DB_NAMES[$db]}" "${DUMP_PATHS[$db]}"
done

log "Module SQL patches will be applied when services restart"

log "Restarting services to reinitialize GUID generators"
docker restart ac-authserver ac-worldserver >/dev/null

log "Waiting for services to fully initialize..."
sleep 10

for i in {1..30}; do
  if docker exec ac-worldserver pgrep worldserver >/dev/null 2>&1 && docker exec ac-authserver pgrep authserver >/dev/null 2>&1; then
    log "Services are running"
    break
  fi
  if [ $i -eq 30 ]; then
    warn "Services took longer than expected to start"
  fi
  sleep 2
done

if db_selected auth; then
  ACCOUNTS=$(count_rows "SELECT COUNT(*) FROM ${DB_NAMES[auth]}.account;")
  log "Accounts: $ACCOUNTS"
fi

if db_selected characters; then
  CHARS=$(count_rows "SELECT COUNT(*) FROM ${DB_NAMES[characters]}.characters;")
  log "Characters: $CHARS"
  if [ "$CHARS" -gt 0 ]; then
    MAX_GUID=$(count_rows "SELECT COALESCE(MAX(guid), 0) FROM ${DB_NAMES[characters]}.characters;")
    log "Highest character GUID: $MAX_GUID"
    log "Next new character will receive GUID: $((MAX_GUID + 1))"
  fi
fi

./status.sh --once || warn "status.sh reported issues; inspect manually."

log "Import completed for: ${ACTIVE_DBS[*]}"
