#!/bin/bash
# Helper to push a fresh build to a remote host with minimal downtime and no data touch by default.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DEFAULT_PROJECT_DIR="~$(printf '/%s' "$(basename "$ROOT_DIR")")"

HOST=""
USER=""
PORT=22
IDENTITY=""
PROJECT_DIR="$DEFAULT_PROJECT_DIR"
PUSH_ENV=0
PUSH_STORAGE=0
CLEAN_CONTAINERS=0
AUTO_DEPLOY=1
ASSUME_YES=0

usage(){
  cat <<'EOF'
Usage: scripts/bash/update-remote.sh --host HOST --user USER [options]

Options:
  --host HOST           Remote hostname or IP (required)
  --user USER           SSH username on remote host (required)
  --port PORT           SSH port (default: 22)
  --identity PATH       SSH private key
  --project-dir DIR     Remote project directory (default: ~/<repo-name>)
  --remote-path DIR     Alias for --project-dir (backward compat)
  --push-env            Upload local .env to remote (default: skip)
  --push-storage        Sync ./storage to remote (default: skip)
  --clean-containers    Stop/remove remote ac-* containers & project images during migration (default: preserve)
  --no-auto-deploy      Do not trigger remote deploy after migration
  --yes                 Auto-confirm prompts
  --help                Show this help
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2;;
    --user) USER="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    --identity) IDENTITY="$2"; shift 2;;
    --project-dir) PROJECT_DIR="$2"; shift 2;;
    --remote-path) PROJECT_DIR="$2"; shift 2;;
    --push-env) PUSH_ENV=1; shift;;
    --push-storage) PUSH_STORAGE=1; shift;;
    --clean-containers) CLEAN_CONTAINERS=1; shift;;
    --no-auto-deploy) AUTO_DEPLOY=0; shift;;
    --yes) ASSUME_YES=1; shift;;
    --help|-h) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage; exit 1;;
  esac
done

if [[ -z "$HOST" || -z "$USER" ]]; then
  echo "--host and --user are required" >&2
  usage
  exit 1
fi

deploy_args=(--remote --remote-host "$HOST" --remote-user "$USER")

if [ -n "$PROJECT_DIR" ]; then
  deploy_args+=(--remote-project-dir "$PROJECT_DIR")
fi
if [ -n "$IDENTITY" ]; then
  deploy_args+=(--remote-identity "$IDENTITY")
fi
if [ "$PORT" != "22" ]; then
  deploy_args+=(--remote-port "$PORT")
fi

if [ "$PUSH_STORAGE" -ne 1 ]; then
  deploy_args+=(--remote-skip-storage)
fi
if [ "$PUSH_ENV" -ne 1 ]; then
  deploy_args+=(--remote-skip-env)
fi

if [ "$CLEAN_CONTAINERS" -eq 1 ]; then
  deploy_args+=(--remote-clean-containers)
else
  deploy_args+=(--remote-preserve-containers)
fi

if [ "$AUTO_DEPLOY" -eq 1 ]; then
  deploy_args+=(--remote-auto-deploy)
fi

deploy_args+=(--no-watch)

if [ "$ASSUME_YES" -eq 1 ]; then
  deploy_args+=(--yes)
fi

echo "Remote update plan:"
echo "  Host/User     : ${USER}@${HOST}:${PORT}"
echo "  Project Dir   : ${PROJECT_DIR}"
echo "  Push .env     : $([ "$PUSH_ENV" -eq 1 ] && echo yes || echo no)"
echo "  Push storage  : $([ "$PUSH_STORAGE" -eq 1 ] && echo yes || echo no)"
echo "  Cleanup mode  : $([ "$CLEAN_CONTAINERS" -eq 1 ] && echo 'clean containers' || echo 'preserve containers')"
echo "  Auto deploy   : $([ "$AUTO_DEPLOY" -eq 1 ] && echo yes || echo no)"
if [ "$AUTO_DEPLOY" -eq 1 ] && [ "$PUSH_ENV" -ne 1 ]; then
  echo "  ⚠️  Auto-deploy is enabled but push-env is off; remote deploy will fail without a valid .env."
fi

if [ "$ASSUME_YES" -ne 1 ]; then
  read -r -p "Proceed with remote update? [y/N]: " reply
  reply="${reply:-n}"
  case "${reply,,}" in
    y|yes) ;;
    *) echo "Aborted."; exit 1 ;;
  esac
  deploy_args+=(--yes)
fi

cd "$ROOT_DIR"
./deploy.sh "${deploy_args[@]}"
