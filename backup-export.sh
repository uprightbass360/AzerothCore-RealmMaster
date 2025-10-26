#!/bin/bash
# Export auth and character databases to ExportBackup_<timestamp>/
set -euo pipefail

MYSQL_PW="${MYSQL_ROOT_PASSWORD}"
DB_AUTH="${DB_AUTH_NAME}"
DB_CHAR="${DB_CHARACTERS_NAME}"

usage(){
  cat <<EOF
Usage: ./backup-export.sh [output_dir]

Creates a timestamped backup of the auth and character databases.
If output_dir is provided, places the timestamped folder inside it
 (default: .).

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
