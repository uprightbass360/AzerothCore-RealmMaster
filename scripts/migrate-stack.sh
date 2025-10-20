#!/bin/bash

# Utility to migrate module images (and optionally storage) to a remote host.
# Assumes module images have already been rebuilt locally.

set -euo pipefail

usage(){
  cat <<'EOF_HELP'
Usage: $(basename "$0") --host HOST --user USER [options]

Options:
  --host HOST           Remote hostname or IP address (required)
  --user USER           SSH username on remote host (required)
  --port PORT           SSH port (default: 22)
  --identity PATH       SSH private key (passed to scp/ssh)
  --project-dir DIR     Remote project directory (default: ~/acore-compose)
  --tarball PATH        Output path for the image tar (default: ./images/acore-modules-images.tar)
  --storage PATH        Remote storage directory (default: <project-dir>/storage)
  --skip-storage        Do not sync the storage directory
  --help                Show this help
EOF_HELP
}

HOST=""
USER=""
PORT=22
IDENTITY=""
PROJECT_DIR=""
TARBALL=""
REMOTE_STORAGE=""
SKIP_STORAGE=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2;;
    --user) USER="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    --identity) IDENTITY="$2"; shift 2;;
    --project-dir) PROJECT_DIR="$2"; shift 2;;
    --tarball) TARBALL="$2"; shift 2;;
    --storage) REMOTE_STORAGE="$2"; shift 2;;
    --skip-storage) SKIP_STORAGE=1; shift;;
    --help|-h) usage; exit 0;;
    *) echo "Unknown option: $1" >&2; usage; exit 1;;
  esac
 done

if [[ -z "$HOST" || -z "$USER" ]]; then
  echo "--host and --user are required" >&2
  usage
  exit 1
fi

PROJECT_DIR="${PROJECT_DIR:-/home/${USER}/acore-compose}"
REMOTE_STORAGE="${REMOTE_STORAGE:-${PROJECT_DIR}/storage}"
TARBALL="${TARBALL:-$(pwd)/images/acore-modules-images.tar}"

SCP_OPTS=(-P "$PORT")
SSH_OPTS=(-p "$PORT")
if [[ -n "$IDENTITY" ]]; then
  SCP_OPTS+=(-i "$IDENTITY")
  SSH_OPTS+=(-i "$IDENTITY")
fi

run_ssh(){
  ssh "${SSH_OPTS[@]}" "$USER@$HOST" "$@"
}

run_scp(){
  scp "${SCP_OPTS[@]}" "$@"
}

echo "⋅ Exporting module images to $TARBALL"
mkdir -p "$(dirname "$TARBALL")"
IMAGES_TO_SAVE=(
  acore/ac-wotlk-worldserver:modules-latest
  acore/ac-wotlk-authserver:modules-latest
)
if docker image inspect uprightbass360/azerothcore-wotlk-playerbots:worldserver-Playerbot >/dev/null 2>&1; then
  IMAGES_TO_SAVE+=(uprightbass360/azerothcore-wotlk-playerbots:worldserver-Playerbot)
fi
if docker image inspect uprightbass360/azerothcore-wotlk-playerbots:authserver-Playerbot >/dev/null 2>&1; then
  IMAGES_TO_SAVE+=(uprightbass360/azerothcore-wotlk-playerbots:authserver-Playerbot)
fi
docker image save "${IMAGES_TO_SAVE[@]}" > "$TARBALL"

if [[ $SKIP_STORAGE -eq 0 ]]; then
  if [[ -d storage ]]; then
    echo "⋅ Syncing storage to remote"
    run_ssh "mkdir -p '$REMOTE_STORAGE'"
    find storage -mindepth 1 -maxdepth 1 -print0 | xargs -0 -I{} scp "${SCP_OPTS[@]}" -r '{}' "$USER@$HOST:$REMOTE_STORAGE/"
  else
    echo "⋅ Skipping storage sync (storage/ missing)"
  fi
else
  echo "⋅ Skipping storage sync"
fi

echo "⋅ Loading images on remote"
run_scp "$TARBALL" "$USER@$HOST:/tmp/acore-modules-images.tar"
run_ssh "docker load < /tmp/acore-modules-images.tar && rm /tmp/acore-modules-images.tar"

echo "⋅ Remote prepares completed"
echo "Run on the remote host to deploy:"
echo "  cd $PROJECT_DIR && ./deploy.sh --skip-rebuild --no-watch"
