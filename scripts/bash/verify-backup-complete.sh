#!/bin/bash
# Verify that a backup directory is complete before copying
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: ./verify-backup-complete.sh [options] BACKUP_DIR

Verifies that a backup directory is complete and safe to copy.

Options:
  -w, --wait SECONDS    Wait for completion (default: 0, no wait)
  -t, --timeout SECONDS Maximum wait time (default: 3600)
  -v, --verbose         Show detailed output
  -h, --help           Show this help

Exit codes:
  0 - Backup is complete
  1 - Backup is incomplete or not found
  2 - Timeout waiting for completion

Examples:
  # Check if backup is complete
  ./verify-backup-complete.sh /nfs/azerothcore/backups/hourly/20251112_170024

  # Wait up to 30 minutes for backup to complete
  ./verify-backup-complete.sh --wait 60 --timeout 1800 /path/to/backup

EOF
}

WAIT_SECONDS=0
TIMEOUT=3600
VERBOSE=false
BACKUP_DIR=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -w|--wait)
      [[ $# -ge 2 ]] || { echo "Error: --wait requires a value" >&2; exit 1; }
      WAIT_SECONDS="$2"
      shift 2
      ;;
    -t|--timeout)
      [[ $# -ge 2 ]] || { echo "Error: --timeout requires a value" >&2; exit 1; }
      TIMEOUT="$2"
      shift 2
      ;;
    -v|--verbose)
      VERBOSE=true
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    -*)
      echo "Error: Unknown option $1" >&2
      exit 1
      ;;
    *)
      [[ -z "$BACKUP_DIR" ]] || { echo "Error: Multiple backup directories specified" >&2; exit 1; }
      BACKUP_DIR="$1"
      shift
      ;;
  esac
done

[[ -n "$BACKUP_DIR" ]] || { echo "Error: Backup directory required" >&2; usage; exit 1; }

log() {
  $VERBOSE && echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >&2
}

check_backup_complete() {
  local dir="$1"

  # Check if directory exists
  if [[ ! -d "$dir" ]]; then
    log "Directory does not exist: $dir"
    return 1
  fi

  # Check for completion marker
  if [[ -f "$dir/.backup_complete" ]]; then
    log "Completion marker found: $dir/.backup_complete"
    return 0
  fi

  log "Completion marker missing: $dir/.backup_complete"

  # Additional heuristics for older backups without markers
  local manifest="$dir/manifest.json"
  if [[ -f "$manifest" ]]; then
    # Check if manifest indicates expected databases are present
    local expected_dbs
    if command -v jq >/dev/null 2>&1; then
      expected_dbs=$(jq -r '.databases[]' "$manifest" 2>/dev/null || echo "")
    elif command -v python3 >/dev/null 2>&1; then
      expected_dbs=$(python3 -c "import json; data=json.load(open('$manifest')); print('\n'.join(data.get('databases', [])))" 2>/dev/null || echo "")
    fi

    if [[ -n "$expected_dbs" ]]; then
      local missing=false
      while IFS= read -r db; do
        [[ -z "$db" ]] && continue
        if [[ ! -f "$dir/${db}.sql.gz" && ! -f "$dir/${db}.sql" ]]; then
          log "Expected database file missing: ${db}.sql.gz"
          missing=true
        fi
      done <<< "$expected_dbs"

      if ! $missing; then
        log "All expected database files present based on manifest"
        return 0
      fi
    fi
  fi

  return 1
}

# Main verification logic
start_time=$(date +%s)
waited=0

while true; do
  if check_backup_complete "$BACKUP_DIR"; then
    $VERBOSE && echo "✅ Backup is complete: $BACKUP_DIR"
    exit 0
  fi

  if [[ $WAIT_SECONDS -eq 0 ]]; then
    $VERBOSE && echo "❌ Backup is incomplete: $BACKUP_DIR"
    exit 1
  fi

  current_time=$(date +%s)
  elapsed=$((current_time - start_time))

  if [[ $elapsed -ge $TIMEOUT ]]; then
    echo "❌ Timeout waiting for backup completion after ${TIMEOUT}s" >&2
    exit 2
  fi

  log "Backup incomplete, waiting ${WAIT_SECONDS}s... (elapsed: ${elapsed}s)"
  sleep "$WAIT_SECONDS"
  waited=$((waited + WAIT_SECONDS))
done