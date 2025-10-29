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
  --tarball PATH        Output path for the image tar (default: ./local-storage/images/acore-modules-images.tar)
  --storage PATH        Remote storage directory (default: <project-dir>/storage)
  --skip-storage        Do not sync the storage directory
  --yes, -y             Auto-confirm prompts (for existing deployments)
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
ASSUME_YES=0

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
    --yes|-y) ASSUME_YES=1; shift;;
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
LOCAL_STORAGE_ROOT="${STORAGE_PATH_LOCAL:-./local-storage}"
LOCAL_STORAGE_ROOT="${LOCAL_STORAGE_ROOT%/}"
[ -z "$LOCAL_STORAGE_ROOT" ] && LOCAL_STORAGE_ROOT="."
TARBALL="${TARBALL:-${LOCAL_STORAGE_ROOT}/images/acore-modules-images.tar}"

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

validate_remote_environment(){
  echo "⋅ Validating remote environment..."

  # 1. Check Docker daemon is running
  echo "  • Checking Docker daemon..."
  if ! run_ssh "docker info >/dev/null 2>&1"; then
    echo "❌ Docker daemon not running or not accessible on remote host"
    echo "   Please ensure Docker is installed and running on $HOST"
    exit 1
  fi

  # 2. Check disk space (need at least 5GB for images + storage)
  echo "  • Checking disk space..."
  local available_gb
  available_gb=$(run_ssh "df /tmp | tail -1 | awk '{print int(\$4/1024/1024)}'")
  if [ "$available_gb" -lt 5 ]; then
    echo "❌ Insufficient disk space on remote host"
    echo "   Available: ${available_gb}GB, Required: 5GB minimum"
    echo "   Please free up disk space on $HOST"
    exit 1
  fi
  echo "   Available: ${available_gb}GB ✓"

  # 3. Check/create project directory with proper permissions
  echo "  • Validating project directory permissions..."
  if ! run_ssh "mkdir -p '$PROJECT_DIR' && test -w '$PROJECT_DIR'"; then
    echo "❌ Cannot create or write to project directory: $PROJECT_DIR"
    echo "   Please ensure $USER has write permissions to $PROJECT_DIR"
    exit 1
  fi

  # 4. Check for existing deployment and warn if running
  echo "  • Checking for existing deployment..."
  local running_containers
  running_containers=$(run_ssh "docker ps --filter 'name=ac-' --format '{{.Names}}' 2>/dev/null | wc -l")
  if [ "$running_containers" -gt 0 ]; then
    echo "⚠️  Warning: Found $running_containers running AzerothCore containers"
    echo "   Migration will overwrite existing deployment"
    if [ "$ASSUME_YES" != "1" ]; then
      read -r -p "   Continue with migration? [y/N]: " reply
      case "$reply" in
        [Yy]*) echo "   Proceeding with migration..." ;;
        *) echo "   Migration cancelled."; exit 1 ;;
      esac
    fi
  fi

  # 5. Ensure remote repository is up to date
  echo "  • Ensuring remote repository is current..."
  setup_remote_repository

  echo "✅ Remote environment validation complete"
}

setup_remote_repository(){
  # Check if git is available
  if ! run_ssh "command -v git >/dev/null 2>&1"; then
    echo "❌ Git not found on remote host. Please install git."
    exit 1
  fi

  # Check if project directory has a git repository
  if run_ssh "test -d '$PROJECT_DIR/.git'"; then
    echo "   • Updating existing repository..."
    # Fetch latest changes and reset to match origin
    run_ssh "cd '$PROJECT_DIR' && git fetch origin && git reset --hard origin/\$(git rev-parse --abbrev-ref HEAD) && git clean -fd"
  else
    echo "   • Cloning repository..."
    # Determine the git repository URL from local repo
    local repo_url
    repo_url=$(git config --get remote.origin.url 2>/dev/null || echo "")
    if [ -z "$repo_url" ]; then
      echo "❌ Cannot determine repository URL. Please ensure local directory is a git repository."
      exit 1
    fi

    # Clone the repository to remote
    run_ssh "rm -rf '$PROJECT_DIR' && git clone '$repo_url' '$PROJECT_DIR'"
  fi

  # Verify essential scripts exist
  if ! run_ssh "test -f '$PROJECT_DIR/deploy.sh' && test -x '$PROJECT_DIR/deploy.sh'"; then
    echo "❌ deploy.sh not found or not executable in remote repository"
    exit 1
  fi

  # Create local-storage directory structure
  run_ssh "mkdir -p '$PROJECT_DIR/local-storage/modules'"

  echo "   • Repository synchronized ✓"
}

validate_remote_environment

echo "⋅ Exporting module images to $TARBALL"
mkdir -p "$(dirname "$TARBALL")"
# Check which images are available and collect them
IMAGES_TO_SAVE=()

# Check for custom module images (built by build.sh)
if docker image inspect uprightbass360/azerothcore-wotlk-playerbots:authserver-modules-latest >/dev/null 2>&1; then
  IMAGES_TO_SAVE+=(uprightbass360/azerothcore-wotlk-playerbots:authserver-modules-latest)
fi
if docker image inspect uprightbass360/azerothcore-wotlk-playerbots:worldserver-modules-latest >/dev/null 2>&1; then
  IMAGES_TO_SAVE+=(uprightbass360/azerothcore-wotlk-playerbots:worldserver-modules-latest)
fi

# Check for pre-compiled playerbots images
if docker image inspect uprightbass360/azerothcore-wotlk-playerbots:worldserver-Playerbot >/dev/null 2>&1; then
  IMAGES_TO_SAVE+=(uprightbass360/azerothcore-wotlk-playerbots:worldserver-Playerbot)
fi
if docker image inspect uprightbass360/azerothcore-wotlk-playerbots:authserver-Playerbot >/dev/null 2>&1; then
  IMAGES_TO_SAVE+=(uprightbass360/azerothcore-wotlk-playerbots:authserver-Playerbot)
fi

# Check for standard AzerothCore images (fallback)
if docker image inspect acore/ac-wotlk-worldserver:modules-latest >/dev/null 2>&1; then
  IMAGES_TO_SAVE+=(acore/ac-wotlk-worldserver:modules-latest)
fi
if docker image inspect acore/ac-wotlk-authserver:modules-latest >/dev/null 2>&1; then
  IMAGES_TO_SAVE+=(acore/ac-wotlk-authserver:modules-latest)
fi

if [ ${#IMAGES_TO_SAVE[@]} -eq 0 ]; then
  echo "❌ No AzerothCore images found to migrate. Run './build.sh' first or pull standard images."
  exit 1
fi

echo "⋅ Found ${#IMAGES_TO_SAVE[@]} images to migrate:"
printf '  • %s\n' "${IMAGES_TO_SAVE[@]}"
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

if [[ -f .env ]]; then
  echo "⋅ Uploading .env"
  run_scp .env "$USER@$HOST:$PROJECT_DIR/.env"
fi

echo "⋅ Remote prepares completed"
echo "Run on the remote host to deploy:"
echo "  cd $PROJECT_DIR && ./deploy.sh --no-watch"
