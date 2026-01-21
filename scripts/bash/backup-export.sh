#!/bin/bash
# Export one or more ACore databases to ExportBackup_<timestamp>/
set -euo pipefail

INVOCATION_DIR="$PWD"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$SCRIPT_DIR"
source "$SCRIPT_DIR/lib/common.sh"

# Load environment defaults if present
if [ -f "$PROJECT_ROOT/.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$PROJECT_ROOT/.env"
  set +a
fi

SUPPORTED_DBS=(auth characters world)
declare -A SUPPORTED_SET=()
for db in "${SUPPORTED_DBS[@]}"; do
  SUPPORTED_SET["$db"]=1
done

declare -A DB_NAMES=([auth]="" [characters]="" [world]="")
declare -a INCLUDE_DBS=()
declare -a SKIP_DBS=()

MYSQL_PW="${MYSQL_ROOT_PASSWORD:-}"
DEST_PARENT=""
DEST_PROVIDED=false
EXPLICIT_SELECTION=false
MYSQL_CONTAINER="${CONTAINER_MYSQL:-ac-mysql}"
DEFAULT_BACKUP_DIR="${BACKUP_PATH:-${STORAGE_PATH:-./storage}/backups}"

usage(){
  cat <<'EOF'
Usage: ./backup-export.sh [options]

Creates a timestamped backup of one or more ACore databases.

Options:
  -o, --output DIR          Destination directory (default: BACKUP_PATH from .env, fallback: ./storage/backups)
  -p, --password PASS       MySQL root password
      --auth-db NAME        Auth database schema name
      --characters-db NAME  Characters database schema name
      --world-db NAME       World database schema name
      --db LIST             Comma-separated list of databases to export
      --skip LIST           Comma-separated list of databases to skip
  -h, --help                Show this help and exit

Supported database identifiers: auth, characters, world.
By default exports auth and characters if database names are provided.

Examples:
  # Export all databases to default location
  ./backup-export.sh --password azerothcore123 --auth-db acore_auth --characters-db acore_characters --world-db acore_world --all

  # Export specific databases to custom directory
  ./backup-export.sh --output /path/to/backups --password azerothcore123 --db auth,characters --auth-db acore_auth --characters-db acore_characters

  # Export only world database
  ./backup-export.sh --password azerothcore123 --db world --world-db acore_world
EOF
}

die(){ fatal "$1"; }

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
      die "Unknown database identifier: $token (supported: ${SUPPORTED_DBS[*]})"
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
    die "python3 is required but was not found on PATH"
  fi
}

json_string(){
  if ! command -v python3 >/dev/null 2>&1; then
    die "python3 is required but was not found on PATH"
  fi
  python3 - "$1" <<'PY'
import json, sys
print(json.dumps(sys.argv[1]))
PY
}

POSITIONAL=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)
      [[ $# -ge 2 ]] || die "--output requires a directory argument"
      DEST_PARENT="$2"
      DEST_PROVIDED=true
      shift 2
      ;;
    -p|--password)
      [[ $# -ge 2 ]] || die "--password requires a value"
      MYSQL_PW="$2"
      shift 2
      ;;
    --auth-db)
      [[ $# -ge 2 ]] || die "--auth-db requires a value"
      DB_NAMES[auth]="$2"
      shift 2
      ;;
    --characters-db)
      [[ $# -ge 2 ]] || die "--characters-db requires a value"
      DB_NAMES[characters]="$2"
      shift 2
      ;;
    --world-db)
      [[ $# -ge 2 ]] || die "--world-db requires a value"
      DB_NAMES[world]="$2"
      shift 2
      ;;
    --db|--only)
      [[ $# -ge 2 ]] || die "--db requires a value"
      EXPLICIT_SELECTION=true
      parse_db_list INCLUDE_DBS "$2"
      shift 2
      ;;
    --skip)
      [[ $# -ge 2 ]] || die "--skip requires a value"
      parse_db_list SKIP_DBS "$2"
      shift 2
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
      die "Unknown option: $1"
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done

if ((${#POSITIONAL[@]} > 0)); then
  die "Positional arguments are not supported. Use named options instead."
fi

declare -a ACTIVE_DBS=()
if $EXPLICIT_SELECTION; then
  ACTIVE_DBS=("${INCLUDE_DBS[@]}")
else
  for db in "${SUPPORTED_DBS[@]}"; do
    if [[ -n "${DB_NAMES[$db]}" ]]; then
      add_unique ACTIVE_DBS "$db"
    fi
  done
  if ((${#ACTIVE_DBS[@]} == 0)); then
    ACTIVE_DBS=(auth characters)
  fi
fi

for skip in "${SKIP_DBS[@]:-}"; do
  remove_from_list ACTIVE_DBS "$skip"
done

if ((${#ACTIVE_DBS[@]} == 0)); then
  die "No databases selected for export."
fi

[[ -n "$MYSQL_PW" ]] || die "MySQL password is required (use --password)."

for db in "${ACTIVE_DBS[@]}"; do
  case "$db" in
    auth|characters|world) ;;
    *) die "Unsupported database identifier requested: $db" ;;
  esac
  if [[ -z "${DB_NAMES[$db]}" ]]; then
    die "Missing schema name for '$db'. Provide --${db}-db."
  fi
done

if $DEST_PROVIDED; then
  DEST_PARENT="$(resolve_relative "$INVOCATION_DIR" "$DEST_PARENT")"
else
  DEFAULT_BACKUP_DIR="$(resolve_relative "$PROJECT_ROOT" "$DEFAULT_BACKUP_DIR")"
  DEST_PARENT="$DEFAULT_BACKUP_DIR"
  mkdir -p "$DEST_PARENT"
fi

TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
DEST_DIR="$(printf '%s/ExportBackup_%s' "$DEST_PARENT" "$TIMESTAMP")"
mkdir -p "$DEST_DIR"
generated_at="$(date --iso-8601=seconds)"

dump_db(){
  local schema="$1" outfile="$2"
  echo "Dumping ${schema} -> ${outfile}"
  docker exec "$MYSQL_CONTAINER" mysqldump -uroot -p"$MYSQL_PW" "$schema" | gzip > "$outfile"
}

for db in "${ACTIVE_DBS[@]}"; do
  outfile="$DEST_DIR/acore_${db}.sql.gz"
  dump_db "${DB_NAMES[$db]}" "$outfile"
done

first=1
{
  printf '{\n'
  printf '  "generated_at": %s,\n' "$(json_string "$generated_at")"
  printf '  "databases": {\n'
  for db in "${ACTIVE_DBS[@]}"; do
    key_json="$(json_string "$db")"
    value_json="$(json_string "${DB_NAMES[$db]}")"
    if (( first )); then
      first=0
    else
      printf ',\n'
    fi
    printf '    %s: %s' "$key_json" "$value_json"
  done
  printf '\n  }\n'
  printf '}\n'
} > "$DEST_DIR/manifest.json"

echo "Exported databases: ${ACTIVE_DBS[*]}"
echo "Backups saved under $DEST_DIR"
