#!/bin/bash
# Export auth and character databases to ExportBackup_<timestamp>/
set -euo pipefail

usage(){
  cat <<EOF
Usage: ./backup-export.sh [output_dir] <mysql_password> <auth_db> <characters_db>

Creates a timestamped backup of the auth and character databases.

Arguments:
  [output_dir] Output directory (default: .)
  <mysql_password> MySQL root password (required)
  <auth_db> Auth database name (required)
  <characters_db> Characters database name (required)

Outputs:
  ExportBackup_YYYYMMDD_HHMMSS/
    acore_auth.sql.gz
    acore_characters.sql.gz
    manifest.json

Services stay online; backup uses mysqldump.
EOF
}

case "${1:-}" in
  -h|--help) usage; exit 0;;
esac

MYSQL_PW="$2"
DB_AUTH="$3"
DB_CHAR="$4"

# Check if required parameters are provided
if [[ -z "$MYSQL_PW" ]]; then
  echo "Error: MySQL password required as second argument." >&2
  exit 1
fi

if [[ -z "$DB_AUTH" ]]; then
  echo "Error: Auth database name required as third argument." >&2
  exit 1
fi

if [[ -z "$DB_CHAR" ]]; then
  echo "Error: Characters database name required as fourth argument." >&2
  exit 1
fi

DEST_PARENT="${1:-.}"
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
DEST_DIR="${DEST_PARENT%/}/ExportBackup_${TIMESTAMP}"
mkdir -p "$DEST_DIR"

dump_db(){
  local db="$1" outfile="$2"
  echo "Dumping $db -> $outfile"
  docker exec ac-mysql mysqldump -uroot -p"$MYSQL_PW" "$db" | gzip > "$outfile"
}

dump_db "$DB_AUTH" "$DEST_DIR/acore_auth.sql.gz"
dump_db "$DB_CHAR" "$DEST_DIR/acore_characters.sql.gz"

cat > "$DEST_DIR/manifest.json" <<JSON
{
  "generated_at": "$(date --iso-8601=seconds)",
  "databases": {
    "auth": "$DB_AUTH",
    "characters": "$DB_CHAR"
  }
}
JSON

echo "Backups saved under $DEST_DIR"
