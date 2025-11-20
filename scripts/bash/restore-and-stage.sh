#!/bin/bash
# Refresh the module metadata after a database restore so runtime staging knows
# to re-copy SQL files.
set -euo pipefail

info(){ echo "🔧 [restore-stage] $*"; }
warn(){ echo "⚠️ [restore-stage] $*" >&2; }

MODULES_DIR="${MODULES_DIR:-/modules}"
MODULES_META_DIR="${MODULES_DIR}/.modules-meta"
RESTORE_FLAG="${MODULES_META_DIR}/.restore-prestaged"

if [ ! -d "$MODULES_DIR" ]; then
  warn "Modules directory not found at ${MODULES_DIR}; skipping restore-time staging prep."
  exit 0
fi

mkdir -p "$MODULES_META_DIR" 2>/dev/null || true
touch "$RESTORE_FLAG"
echo "restore_at=$(date -u +"%Y-%m-%dT%H:%M:%SZ")" > "$RESTORE_FLAG"

info "Flagged ${RESTORE_FLAG} to force staging on next ./scripts/bash/stage-modules.sh run."
