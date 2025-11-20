#!/bin/bash
# Normalize permissions across storage/ and local-storage/ so host processes
# (and CI tools) can read/write module metadata without manual chown.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
TEMPLATE_FILE="$PROJECT_ROOT/.env.template"

usage(){
  cat <<'EOF'
Usage: repair-storage-permissions.sh [options]

Ensures common storage directories are writable by the current host user.

Options:
  --path <dir>     Additional directory to fix (can be passed multiple times)
  --silent         Reduce output (only errors/warnings)
  -h, --help       Show this help message
EOF
}

read_env(){
  local key="$1" default="$2" env_path="$ENV_FILE" value=""
  if [ -f "$env_path" ]; then
    value="$(grep -E "^${key}=" "$env_path" | tail -n1 | cut -d'=' -f2- | tr -d '\r')"
  fi
  if [ -z "$value" ] && [ -f "$TEMPLATE_FILE" ]; then
    value="$(grep -E "^${key}=" "$TEMPLATE_FILE" | tail -n1 | cut -d'=' -f2- | tr -d '\r')"
  fi
  if [ -z "$value" ]; then
    value="$default"
  fi
  printf '%s\n' "$value"
}

silent=0
declare -a extra_paths=()
while [ $# -gt 0 ]; do
  case "$1" in
    --path)
      shift
      [ $# -gt 0 ] || { echo "Missing value for --path" >&2; exit 1; }
      extra_paths+=("$1")
      ;;
    --silent)
      silent=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

log(){ [ "$silent" -eq 1 ] || echo "$*"; }
warn(){ echo "⚠️  $*" >&2; }

resolve_path(){
  local path="$1"
  if [[ "$path" != /* ]]; then
    path="${path#./}"
    path="$PROJECT_ROOT/$path"
  fi
  printf '%s\n' "$(cd "$(dirname "$path")" 2>/dev/null && pwd 2>/dev/null)/$(basename "$path")"
}

ensure_host_writable(){
  local target="$1"
  [ -n "$target" ] || return 0
  mkdir -p "$target" 2>/dev/null || true
  [ -d "$target" ] || { warn "Path not found: $target"; return 0; }

  local uid gid
  uid="$(id -u)"
  gid="$(id -g)"

  if chown -R "$uid":"$gid" "$target" 2>/dev/null; then
    :
  elif command -v docker >/dev/null 2>&1; then
    local helper_image
    helper_image="$(read_env ALPINE_IMAGE "alpine:latest")"
    if ! docker run --rm -u 0:0 -v "$target":/workspace "$helper_image" \
      sh -c "chown -R ${uid}:${gid} /workspace" >/dev/null 2>&1; then
      warn "Failed to adjust ownership for $target"
      return 1
    fi
  else
    warn "Cannot adjust ownership for $target (docker unavailable)"
    return 1
  fi

  chmod -R ug+rwX "$target" 2>/dev/null || true
  return 0
}

STORAGE_PATH="$(read_env STORAGE_PATH "./storage")"
LOCAL_STORAGE_PATH="$(read_env STORAGE_PATH_LOCAL "./local-storage")"

declare -a targets=(
  "$STORAGE_PATH"
  "$STORAGE_PATH/modules"
  "$STORAGE_PATH/modules/.modules-meta"
  "$STORAGE_PATH/backups"
  "$STORAGE_PATH/logs"
  "$STORAGE_PATH/lua_scripts"
  "$STORAGE_PATH/install-markers"
  "$STORAGE_PATH/client-data"
  "$STORAGE_PATH/config"
  "$LOCAL_STORAGE_PATH"
  "$LOCAL_STORAGE_PATH/modules"
  "$LOCAL_STORAGE_PATH/client-data-cache"
  "$LOCAL_STORAGE_PATH/source"
  "$LOCAL_STORAGE_PATH/images"
)

targets+=("${extra_paths[@]}")

declare -A seen=()
for raw in "${targets[@]}"; do
  [ -n "$raw" ] || continue
  resolved="$(resolve_path "$raw")"
  if [ -n "${seen[$resolved]:-}" ]; then
    continue
  fi
  seen["$resolved"]=1
  log "🔧 Fixing permissions for $resolved"
  ensure_host_writable "$resolved"
done

log "✅ Storage permissions refreshed"
