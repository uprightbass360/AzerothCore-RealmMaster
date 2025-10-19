#!/bin/bash

# Utility to migrate the current acore-compose stack to a remote host.
# It assumes the module images have already been rebuilt locally.

set -euo pipefail

usage(){
  cat <<EOF
Usage: $(basename "$0") --host HOST --user USER [options]

Options:
  --host HOST           Remote hostname or IP address (required)
  --user USER           SSH username on remote host (required)
  --port PORT           SSH port (default: 22)
  --identity PATH       SSH private key (passed to scp/ssh)
  --project-dir DIR     Remote directory for the project (default: ~/acore-compose)
  --tarball PATH        Output path for the image tar (default: ./acore-modules-images.tar)
  --storage PATH        Remote storage directory (default: <project-dir>/storage)
  --skip-images         Do not export/import Docker images
  --help                Show this help

Example:
  $(basename "$0") --host wow.example.com --user deploy --identity ~/.ssh/id_ed25519 \
    --project-dir /opt/acore-compose
EOF
}

HOST=""
USER=""
PORT=22
IDENTITY=""
PROJECT_DIR=""
TARBALL=""
REMOTE_STORAGE=""
SKIP_IMAGES=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2;;
    --user) USER="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    --identity) IDENTITY="$2"; shift 2;;
    --project-dir) PROJECT_DIR="$2"; shift 2;;
    --tarball) TARBALL="$2"; shift 2;;
    --storage) REMOTE_STORAGE="$2"; shift 2;;
    --skip-images) SKIP_IMAGES=1; shift;;
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
TARBALL="${TARBALL:-$(pwd)/acore-modules-images.tar}"

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

echo "⋅ Preparing project archive"
TMP_PROJECT_ARCHIVE="$(mktemp -u acore-compose-XXXXXX.tar.gz)"
tar --exclude '.git' --exclude 'storage/backups' --exclude 'storage/logs' \
    --exclude 'acore-modules-images.tar' -czf "$TMP_PROJECT_ARCHIVE" -C "$(pwd)/.." "$(basename "$(pwd)")"

if [[ $SKIP_IMAGES -eq 0 ]]; then
  echo "⋅ Exporting module images to $TARBALL"
  docker image save \
    acore/ac-wotlk-worldserver:modules-latest \
    acore/ac-wotlk-authserver:modules-latest \
    > "$TARBALL"
fi

echo "⋅ Removing rebuild sentinel"
rm -f storage/modules/.requires_rebuild || true

echo "⋅ Syncing project to remote $USER@$HOST:$PROJECT_DIR"
run_ssh "mkdir -p '$PROJECT_DIR'"
run_scp "$TMP_PROJECT_ARCHIVE" "$USER@$HOST:/tmp/acore-compose.tar.gz"
run_ssh "tar -xzf /tmp/acore-compose.tar.gz -C '$PROJECT_DIR' --strip-components=1 && rm /tmp/acore-compose.tar.gz"

echo "⋅ Syncing storage to remote"
run_ssh "mkdir -p '$REMOTE_STORAGE'"
run_scp -r storage/* "$USER@$HOST:$REMOTE_STORAGE/"

if [[ $SKIP_IMAGES -eq 0 ]]; then
  echo "⋅ Transferring docker images"
  run_scp "$TARBALL" "$USER@$HOST:/tmp/acore-modules-images.tar"
  run_ssh "docker load < /tmp/acore-modules-images.tar && rm /tmp/acore-modules-images.tar"
fi

echo "⋅ Remote prepares completed"
echo "Run the following on the remote host to deploy:"
echo "  cd $PROJECT_DIR && ./deploy.sh --skip-rebuild --no-watch"

rm -f "$TMP_PROJECT_ARCHIVE"
echo "Migration script finished"
