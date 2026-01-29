#!/bin/bash

# Utility to migrate deployment images (and optionally storage) to a remote host.
# Assumes your runtime images have already been built or pulled locally.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$PROJECT_ROOT/.env"
TEMPLATE_FILE="$PROJECT_ROOT/.env.template"
source "$PROJECT_ROOT/scripts/bash/project_name.sh"

# Default project name (read from .env or template)
DEFAULT_PROJECT_NAME="$(project_name::resolve "$ENV_FILE" "$TEMPLATE_FILE")"

read_env_value(){
  local key="$1" default="$2" value=""
  if [ -f "$ENV_FILE" ]; then
    value="$(grep -E "^${key}=" "$ENV_FILE" 2>/dev/null | tail -n1 | cut -d'=' -f2- | tr -d '\r')"
  fi
  if [ -z "$value" ]; then
    value="${!key:-}"
  fi
  if [ -z "$value" ]; then
    value="$default"
  fi
  echo "$value"
}

resolve_project_name(){
  local raw_name
  raw_name="$(read_env_value COMPOSE_PROJECT_NAME "$DEFAULT_PROJECT_NAME")"
  project_name::sanitize "$raw_name"
}

resolve_project_image(){
  local tag="$1"
  local project_name
  project_name="$(resolve_project_name)"
  echo "${project_name}:${tag}"
}

declare -a DEPLOY_IMAGE_REFS=()
declare -a CLEANUP_IMAGE_REFS=()
declare -A DEPLOY_IMAGE_SET=()
declare -A CLEANUP_IMAGE_SET=()

add_deploy_image_ref(){
  local image="$1"
  [ -z "$image" ] && return
  if [[ -z "${DEPLOY_IMAGE_SET[$image]:-}" ]]; then
    DEPLOY_IMAGE_SET["$image"]=1
    DEPLOY_IMAGE_REFS+=("$image")
  fi
  add_cleanup_image_ref "$image"
}

add_cleanup_image_ref(){
  local image="$1"
  [ -z "$image" ] && return
  if [[ -z "${CLEANUP_IMAGE_SET[$image]:-}" ]]; then
    CLEANUP_IMAGE_SET["$image"]=1
    CLEANUP_IMAGE_REFS+=("$image")
  fi
}

collect_deploy_image_refs(){
  local auth_modules world_modules auth_playerbots world_playerbots db_import client_data bots_client_data
  local auth_standard world_standard client_data_standard

  auth_modules="$(read_env_value AC_AUTHSERVER_IMAGE_MODULES "$(resolve_project_image "authserver-modules-latest")")"
  world_modules="$(read_env_value AC_WORLDSERVER_IMAGE_MODULES "$(resolve_project_image "worldserver-modules-latest")")"
  auth_playerbots="$(read_env_value AC_AUTHSERVER_IMAGE_PLAYERBOTS "$(resolve_project_image "authserver-playerbots")")"
  world_playerbots="$(read_env_value AC_WORLDSERVER_IMAGE_PLAYERBOTS "$(resolve_project_image "worldserver-playerbots")")"
  db_import="$(read_env_value AC_DB_IMPORT_IMAGE "$(resolve_project_image "db-import-playerbots")")"
  client_data="$(read_env_value AC_CLIENT_DATA_IMAGE_PLAYERBOTS "$(resolve_project_image "client-data-playerbots")")"

  auth_standard="$(read_env_value AC_AUTHSERVER_IMAGE "acore/ac-wotlk-authserver:master")"
  world_standard="$(read_env_value AC_WORLDSERVER_IMAGE "acore/ac-wotlk-worldserver:master")"
  client_data_standard="$(read_env_value AC_CLIENT_DATA_IMAGE "acore/ac-wotlk-client-data:master")"

  local refs=(
    "$auth_modules"
    "$world_modules"
    "$auth_playerbots"
    "$world_playerbots"
    "$db_import"
    "$client_data"
    "$auth_standard"
    "$world_standard"
    "$client_data_standard"
  )
  for ref in "${refs[@]}"; do
    add_deploy_image_ref "$ref"
  done

  # Include default project-tagged images for cleanup even if env moved to custom tags
  local fallback_refs=(
    "$(resolve_project_image "authserver-modules-latest")"
    "$(resolve_project_image "worldserver-modules-latest")"
    "$(resolve_project_image "authserver-playerbots")"
    "$(resolve_project_image "worldserver-playerbots")"
    "$(resolve_project_image "db-import-playerbots")"
    "$(resolve_project_image "client-data-playerbots")"
  )
  for ref in "${fallback_refs[@]}"; do
    add_cleanup_image_ref "$ref"
  done
}

ensure_host_writable(){
  local path="$1"
  [ -n "$path" ] || return 0
  if [ ! -d "$path" ]; then
    mkdir -p "$path" 2>/dev/null || true
  fi
  if [ -d "$path" ]; then
    local uid gid
    uid="$(id -u)"
    gid="$(id -g)"
    if ! chown -R "$uid":"$gid" "$path" 2>/dev/null; then
      if command -v docker >/dev/null 2>&1; then
        local helper_image
        helper_image="$(read_env_value ALPINE_IMAGE "alpine:latest")"
        docker run --rm \
          -u 0:0 \
          -v "$path":/workspace \
          "$helper_image" \
          sh -c "chown -R ${uid}:${gid} /workspace" >/dev/null 2>&1 || true
      fi
    fi
    chmod -R u+rwX "$path" 2>/dev/null || true
  fi
}

usage(){
  cat <<'EOF_HELP'
Usage: $(basename "$0") --host HOST --user USER [options]

Options:
  --host HOST           Remote hostname or IP address (required)
  --user USER           SSH username on remote host (required)
  --port PORT           SSH port (default: 22)
  --identity PATH       SSH private key (passed to scp/ssh)
  --project-dir DIR     Remote project directory (default: ~/<project-name>)
  --setup-source 0|1    Auto-setup AzerothCore source on remote (0=skip, 1=setup, unset=prompt)
  --env-file PATH       Use this env file for image lookup and upload (default: ./.env)
  --tarball PATH        Output path for the image tar (default: ./local-storage/images/acore-modules-images.tar)
  --storage PATH        Remote storage directory (default: <project-dir>/storage)
  --skip-storage        Do not sync the storage directory
  --skip-env            Do not upload .env to the remote host
  --preserve-containers  Skip stopping/removing existing remote containers and images
  --clean-containers     Stop/remove existing ac-* containers and project images on remote
  --copy-source         Copy the full local project directory instead of syncing via git
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
COPY_SOURCE=0
SKIP_ENV=0
REMOTE_SETUP_SOURCE=""
PRESERVE_CONTAINERS=0
CLEAN_CONTAINERS=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2;;
    --user) USER="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    --identity) IDENTITY="$2"; shift 2;;
    --project-dir) PROJECT_DIR="$2"; shift 2;;
    --env-file) ENV_FILE="$2"; shift 2;;
    --tarball) TARBALL="$2"; shift 2;;
    --storage) REMOTE_STORAGE="$2"; shift 2;;
    --setup-source) REMOTE_SETUP_SOURCE="$2"; shift 2;;
    --skip-storage) SKIP_STORAGE=1; shift;;
    --skip-env) SKIP_ENV=1; shift;;
    --preserve-containers) PRESERVE_CONTAINERS=1; shift;;
    --clean-containers) CLEAN_CONTAINERS=1; shift;;
    --copy-source) COPY_SOURCE=1; shift;;
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

if [[ "$CLEAN_CONTAINERS" -eq 1 && "$PRESERVE_CONTAINERS" -eq 1 ]]; then
  echo "Cannot combine --clean-containers with --preserve-containers." >&2
  exit 1
fi

# Normalize env file path if provided and recompute defaults
if [ -n "$ENV_FILE" ] && [ -f "$ENV_FILE" ]; then
  ENV_FILE="$(cd "$(dirname "$ENV_FILE")" && pwd)/$(basename "$ENV_FILE")"
else
  ENV_FILE="$PROJECT_ROOT/.env"
fi
DEFAULT_PROJECT_NAME="$(project_name::resolve "$ENV_FILE" "$TEMPLATE_FILE")"

expand_remote_path(){
  local path="$1"
  case "$path" in
    "~") echo "/home/${USER}";;
    "~/"*) echo "/home/${USER}/${path#\~/}";;
    *) echo "$path";;
  esac
}

DEFAULT_REMOTE_DIR_NAME="$(basename "$PROJECT_ROOT")"
PROJECT_DIR="${PROJECT_DIR:-~/${DEFAULT_REMOTE_DIR_NAME}}"
PROJECT_DIR="$(expand_remote_path "$PROJECT_DIR")"
REMOTE_STORAGE="${REMOTE_STORAGE:-${PROJECT_DIR}/storage}"
REMOTE_STORAGE="$(expand_remote_path "$REMOTE_STORAGE")"
REMOTE_TEMP_DIR="${REMOTE_TEMP_DIR:-${PROJECT_DIR}/.rm-migrate}"
REMOTE_TEMP_DIR="$(expand_remote_path "$REMOTE_TEMP_DIR")"
LOCAL_STORAGE_ROOT="${STORAGE_PATH_LOCAL:-}"
if [ -z "$LOCAL_STORAGE_ROOT" ]; then
  LOCAL_STORAGE_ROOT="$(read_env_value STORAGE_PATH_LOCAL "./local-storage")"
fi
LOCAL_STORAGE_ROOT="${LOCAL_STORAGE_ROOT%/}"
[ -z "$LOCAL_STORAGE_ROOT" ] && LOCAL_STORAGE_ROOT="."
ensure_host_writable "$LOCAL_STORAGE_ROOT"
TARBALL="${TARBALL:-${LOCAL_STORAGE_ROOT}/images/acore-modules-images.tar}"
ensure_host_writable "$(dirname "$TARBALL")"

# Resolve module SQL staging paths (local and remote)
resolve_path_relative_to_project(){
  local path="$1" root="$2"
  if [[ "$path" != /* ]]; then
    # drop leading ./ if present
    path="${path#./}"
    path="${root%/}/$path"
  fi
  echo "${path%/}"
}

STAGE_SQL_PATH_RAW="$(read_env_value STAGE_PATH_MODULE_SQL "${LOCAL_STORAGE_ROOT:-./local-storage}/module-sql-updates")"
# Ensure STORAGE_PATH_LOCAL is defined to avoid set -u failures during expansion
if [ -z "${STORAGE_PATH_LOCAL:-}" ]; then
  STORAGE_PATH_LOCAL="$LOCAL_STORAGE_ROOT"
fi
# Ensure STORAGE_PATH is defined to avoid set -u failures during expansion
if [ -z "${STORAGE_PATH:-}" ]; then
  STORAGE_PATH="$(read_env_value STORAGE_PATH "./storage")"
fi
# Ensure STORAGE_MODULE_SQL_PATH is defined to avoid set -u failures during expansion
if [ -z "${STORAGE_MODULE_SQL_PATH:-}" ]; then
  STORAGE_MODULE_SQL_PATH="$(read_env_value STORAGE_MODULE_SQL_PATH "${STORAGE_PATH}/module-sql-updates")"
fi
# Expand any env references (e.g., ${STORAGE_PATH_LOCAL}, ${STORAGE_MODULE_SQL_PATH})
STAGE_SQL_PATH_RAW="$(eval "echo \"$STAGE_SQL_PATH_RAW\"")"
LOCAL_STAGE_SQL_DIR="$(resolve_path_relative_to_project "$STAGE_SQL_PATH_RAW" "$PROJECT_ROOT")"
REMOTE_STAGE_SQL_DIR="$(resolve_path_relative_to_project "$STAGE_SQL_PATH_RAW" "$PROJECT_DIR")"

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

ensure_remote_temp_dir(){
  run_ssh "mkdir -p '$REMOTE_TEMP_DIR'"
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
    if [ "$PRESERVE_CONTAINERS" -eq 1 ]; then
      echo "⚠️  Found $running_containers running AzerothCore containers; --preserve-containers set, leaving them running."
      if [ "$ASSUME_YES" != "1" ]; then
        read -r -p "   Continue without stopping containers? [y/N]: " reply
        case "$reply" in
          [Yy]*) echo "   Proceeding with migration (containers preserved)..." ;;
          *) echo "   Migration cancelled."; exit 1 ;;
        esac
      fi
    elif [ "$CLEAN_CONTAINERS" -eq 1 ]; then
      echo "⚠️  Found $running_containers running AzerothCore containers"
      echo "   --clean-containers set: they will be stopped/removed during migration."
      if [ "$ASSUME_YES" != "1" ]; then
        read -r -p "   Continue with cleanup? [y/N]: " reply
        case "$reply" in
          [Yy]*) echo "   Proceeding with cleanup..." ;;
          *) echo "   Migration cancelled."; exit 1 ;;
        esac
      fi
    else
      echo "⚠️  Warning: Found $running_containers running AzerothCore containers"
      echo "   Migration will NOT stop them automatically. Use --clean-containers to stop/remove."
      if [ "$ASSUME_YES" != "1" ]; then
        read -r -p "   Continue with migration? [y/N]: " reply
        case "$reply" in
          [Yy]*) echo "   Proceeding with migration..." ;;
          *) echo "   Migration cancelled."; exit 1 ;;
        esac
      fi
    fi
  fi

  # 5. Ensure remote project files are up to date
  echo "  • Ensuring remote project files are current..."
  if [ "$COPY_SOURCE" -eq 1 ]; then
    copy_source_tree
  else
    setup_remote_repository
  fi

  ensure_remote_temp_dir
  echo "✅ Remote environment validation complete"
}

confirm_remote_storage_overwrite(){
  if [[ $SKIP_STORAGE -ne 0 ]]; then
    return
  fi
  if [[ "$ASSUME_YES" = "1" ]]; then
    return
  fi
  local has_content
  has_content=$(run_ssh "if [ -d '$REMOTE_STORAGE' ]; then find '$REMOTE_STORAGE' -mindepth 1 -maxdepth 1 -print -quit; fi")
  if [ -n "$has_content" ]; then
    echo "⚠️  Remote storage at $REMOTE_STORAGE contains existing data."
    read -r -p "   Continue and sync local storage over it? [y/N]: " reply
    case "${reply,,}" in
      y|yes) echo "   Proceeding with storage sync..." ;;
      *) echo "   Skipping storage sync for this run."; SKIP_STORAGE=1 ;;
    esac
  fi
}

copy_source_tree(){
  echo "   • Copying full local project directory..."
  ensure_remote_temp_dir
  local tmp_tar
  tmp_tar="$(mktemp)"
  if ! tar --exclude='./storage' --exclude='./local-storage' -C "$PROJECT_ROOT" -cf "$tmp_tar" .; then
    echo "❌ Failed to archive local project directory."
    rm -f "$tmp_tar"
    exit 1
  fi

  run_ssh "rm -rf '$PROJECT_DIR' && mkdir -p '$PROJECT_DIR'"
  run_scp "$tmp_tar" "$USER@$HOST:$REMOTE_TEMP_DIR/acore-project-src.tar"
  rm -f "$tmp_tar"

  if ! run_ssh "cd '$PROJECT_DIR' && tar -xf '$REMOTE_TEMP_DIR/acore-project-src.tar' && rm '$REMOTE_TEMP_DIR/acore-project-src.tar'"; then
    echo "❌ Failed to extract project archive on remote host."
    exit 1
  fi

  run_ssh "chmod +x '$PROJECT_DIR'/deploy.sh 2>/dev/null || true"
  echo "   • Source tree synchronized ✓"
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

  # Create local-storage directory structure with proper ownership
  run_ssh "mkdir -p '$PROJECT_DIR/local-storage/modules' && chown -R $USER: '$PROJECT_DIR/local-storage' 2>/dev/null || true"

  echo "   • Repository synchronized ✓"
}

setup_source_if_needed(){
  local should_setup="${REMOTE_SETUP_SOURCE:-}"

  # Check if source already exists and is populated
  echo "   • Checking for existing AzerothCore source repository..."
  if run_ssh "[ -d '$PROJECT_DIR/local-storage/source/azerothcore-playerbots/data/sql/base/db_world' ] && [ -n \"\$(ls -A '$PROJECT_DIR/local-storage/source/azerothcore-playerbots/data/sql/base/db_world' 2>/dev/null)\" ]" 2>/dev/null; then
    echo "   ✅ Source repository already populated on remote"
    return 0
  elif run_ssh "[ -d '$PROJECT_DIR/local-storage/source/azerothcore/data/sql/base/db_world' ] && [ -n \"\$(ls -A '$PROJECT_DIR/local-storage/source/azerothcore/data/sql/base/db_world' 2>/dev/null)\" ]" 2>/dev/null; then
    echo "   ✅ Source repository already populated on remote"
    return 0
  fi

  echo "   ⚠️  Source repository not found or empty on remote"

  # If not set, ask user (unless --yes)
  if [ -z "$should_setup" ]; then
    if [ "$ASSUME_YES" = "1" ]; then
      # Auto-yes in non-interactive: default to YES for safety
      echo "   ℹ️  Auto-confirming source setup (--yes flag)"
      should_setup=1
    else
      echo ""
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo "📦 AzerothCore Source Repository Setup"
      echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
      echo ""
      echo "The remote server needs AzerothCore source code for database schemas."
      echo "This will clone ~2GB repository (one-time operation, takes 2-5 minutes)."
      echo ""
      echo "Without this, database initialization will FAIL."
      echo ""
      read -rp "Set up source repository now? [Y/n]: " answer
      answer="${answer:-Y}"
      case "${answer,,}" in
        y|yes) should_setup=1 ;;
        *) should_setup=0 ;;
      esac
    fi
  fi

  if [ "$should_setup" != "1" ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "⚠️  WARNING: Source setup skipped"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "You MUST run this manually on the remote host BEFORE starting services:"
    echo ""
    echo "  ssh $USER@$HOST"
    echo "  cd $PROJECT_DIR"
    echo "  ./scripts/bash/setup-source.sh"
    echo ""
    return 0
  fi

  echo "   🔧 Setting up AzerothCore source repository on remote..."
  echo "   ⏳ Cloning AzerothCore (this may take 2-5 minutes)..."

  # Run setup-source.sh on remote, capturing output
  if run_ssh "cd '$PROJECT_DIR' && ./scripts/bash/setup-source.sh" 2>&1 | sed 's/^/      /'; then
    echo "   ✅ Source repository setup complete"
    return 0
  else
    echo "   ❌ Source setup failed (check output above for details)"
    echo "   ⚠️  Run manually: ssh $USER@$HOST 'cd $PROJECT_DIR && ./scripts/bash/setup-source.sh'"
    return 1
  fi
}

cleanup_stale_docker_resources(){
  if [ "$PRESERVE_CONTAINERS" -eq 1 ]; then
    echo "⋅ Skipping remote container/image cleanup (--preserve-containers)"
    return
  fi
  if [ "$CLEAN_CONTAINERS" -ne 1 ]; then
    echo "⋅ Skipping remote runtime cleanup (containers and images preserved)."
    return
  fi
  echo "⋅ Cleaning up stale Docker resources on remote..."

  # Stop and remove old containers
  echo "  • Removing old containers..."
  run_ssh "docker ps -a --filter 'name=ac-' --format '{{.Names}}' | xargs -r docker rm -f 2>/dev/null || true"

  # Remove old project images to force fresh load
  echo "  • Removing old project images..."
  for img in "${CLEANUP_IMAGE_REFS[@]}"; do
    run_ssh "docker rmi '$img' 2>/dev/null || true"
  done

  # Prune dangling images and build cache
  echo "  • Pruning dangling images and build cache..."
  run_ssh "docker image prune -f >/dev/null 2>&1 || true"
  run_ssh "docker builder prune -f >/dev/null 2>&1 || true"

  echo "✅ Docker cleanup complete"
}

validate_remote_environment

# Set up source repository if needed (after project files are synced)
setup_source_if_needed || true  # Don't fail entire deployment if source setup fails

collect_deploy_image_refs

echo "⋅ Exporting deployment images to $TARBALL"
# Ensure destination directory exists
ensure_host_writable "$(dirname "$TARBALL")"

# Check which images are available and collect them
IMAGES_TO_SAVE=()
MISSING_IMAGES=()
for image in "${DEPLOY_IMAGE_REFS[@]}"; do
  if docker image inspect "$image" >/dev/null 2>&1; then
    IMAGES_TO_SAVE+=("$image")
  else
    MISSING_IMAGES+=("$image")
  fi
done

if [ ${#IMAGES_TO_SAVE[@]} -eq 0 ]; then
  echo "❌ No AzerothCore images found to migrate. Run './build.sh' first or pull the images defined in your .env."
  exit 1
fi

echo "⋅ Found ${#IMAGES_TO_SAVE[@]} images to migrate:"
printf '  • %s\n' "${IMAGES_TO_SAVE[@]}"
docker image save "${IMAGES_TO_SAVE[@]}" > "$TARBALL"

if [ ${#MISSING_IMAGES[@]} -gt 0 ]; then
  echo "⚠️  Skipping ${#MISSING_IMAGES[@]} images not present locally (will need to pull on remote if required):"
  printf '  • %s\n' "${MISSING_IMAGES[@]}"
fi

confirm_remote_storage_overwrite

if [[ $SKIP_STORAGE -eq 0 ]]; then
  if [[ -d storage ]]; then
    echo "⋅ Syncing storage to remote"
    run_ssh "mkdir -p '$REMOTE_STORAGE'"
    while IFS= read -r -d '' entry; do
      base_name="$(basename "$entry")"
      if [[ "$base_name" = modules ]]; then
        continue
      fi
      if [ -L "$entry" ]; then
        target_path="$(readlink -f "$entry")"
        run_scp "$target_path" "$USER@$HOST:$REMOTE_STORAGE/$base_name"
      else
        run_scp -r "$entry" "$USER@$HOST:$REMOTE_STORAGE/"
      fi
    done < <(find storage -mindepth 1 -maxdepth 1 -print0)
  else
    echo "⋅ Skipping storage sync (storage/ missing)"
  fi
else
  echo "⋅ Skipping storage sync"
fi

if [[ $SKIP_STORAGE -eq 0 ]]; then
  LOCAL_MODULES_DIR="${LOCAL_STORAGE_ROOT}/modules"
  if [[ -d "$LOCAL_MODULES_DIR" ]]; then
    echo "⋅ Syncing module staging to remote"
    run_ssh "rm -rf '$REMOTE_STORAGE/modules' && mkdir -p '$REMOTE_STORAGE/modules'"
    modules_tar=$(mktemp)
    tar -cf "$modules_tar" -C "$LOCAL_MODULES_DIR" .
    ensure_remote_temp_dir
    run_scp "$modules_tar" "$USER@$HOST:$REMOTE_TEMP_DIR/acore-modules.tar"
    rm -f "$modules_tar"
    run_ssh "tar -xf '$REMOTE_TEMP_DIR/acore-modules.tar' -C '$REMOTE_STORAGE/modules' && rm '$REMOTE_TEMP_DIR/acore-modules.tar'"
  fi

  # Sync module SQL staging directory (STAGE_PATH_MODULE_SQL)
  if [[ -d "$LOCAL_STAGE_SQL_DIR" ]]; then
    echo "⋅ Syncing module SQL staging to remote"
    run_ssh "rm -rf '$REMOTE_STAGE_SQL_DIR' && mkdir -p '$REMOTE_STAGE_SQL_DIR'"
    sql_tar=$(mktemp)
    tar -cf "$sql_tar" -C "$LOCAL_STAGE_SQL_DIR" .
    ensure_remote_temp_dir
    run_scp "$sql_tar" "$USER@$HOST:$REMOTE_TEMP_DIR/acore-module-sql.tar"
    rm -f "$sql_tar"
    run_ssh "tar -xf '$REMOTE_TEMP_DIR/acore-module-sql.tar' -C '$REMOTE_STAGE_SQL_DIR' && rm '$REMOTE_TEMP_DIR/acore-module-sql.tar'"
  fi
fi

reset_remote_post_install_marker(){
  local marker_dir="$REMOTE_STORAGE/install-markers"
  local marker_path="$marker_dir/post-install-completed"
  echo "⋅ Resetting remote post-install markers"
  run_ssh "mkdir -p '$marker_dir' && rm -f '$marker_path'"
}

reset_remote_post_install_marker

# Clean up stale Docker resources before loading new images
cleanup_stale_docker_resources

echo "⋅ Loading images on remote"
ensure_remote_temp_dir
run_scp "$TARBALL" "$USER@$HOST:$REMOTE_TEMP_DIR/acore-modules-images.tar"
run_ssh "docker load < '$REMOTE_TEMP_DIR/acore-modules-images.tar' && rm '$REMOTE_TEMP_DIR/acore-modules-images.tar'"

if [[ -f "$ENV_FILE" ]]; then
  if [[ $SKIP_ENV -eq 1 ]]; then
    echo "⋅ Skipping .env upload (--skip-env)"
  else
    remote_env_path="$PROJECT_DIR/.env"
    upload_env=1

    if run_ssh "test -f '$remote_env_path'"; then
      if [ "$ASSUME_YES" = "1" ]; then
        echo "⋅ Overwriting existing remote .env (auto-confirm)"
      elif [ -t 0 ]; then
        read -r -p "⚠️  Remote .env exists at $remote_env_path. Overwrite? [y/N]: " reply
        case "$reply" in
          [Yy]*) ;;
          *) upload_env=0 ;;
        esac
      else
        echo "⚠️  Remote .env exists at $remote_env_path; skipping upload (no confirmation available)"
        upload_env=0
      fi
    fi

    if [[ $upload_env -eq 1 ]]; then
      echo "⋅ Uploading .env"
      run_scp "$ENV_FILE" "$USER@$HOST:$remote_env_path"
    else
      echo "⋅ Keeping existing remote .env"
    fi
  fi
fi

echo "⋅ Remote prepares completed"
echo "Run on the remote host to deploy:"
echo "  cd '$PROJECT_DIR' && ./deploy.sh --no-watch"
