#!/bin/bash
# azerothcore-rm source repository setup
set -euo pipefail

echo '🔧 Setting up AzerothCore source repository...'

# Load environment variables if .env exists
if [ -f .env ]; then
    source .env
fi

# Remember project root for path normalization
PROJECT_ROOT="$(pwd)"

# Default values
MODULE_PLAYERBOTS="${MODULE_PLAYERBOTS:-0}"
PLAYERBOT_ENABLED="${PLAYERBOT_ENABLED:-0}"
STACK_SOURCE_VARIANT="${STACK_SOURCE_VARIANT:-}"
if [ -z "$STACK_SOURCE_VARIANT" ]; then
    if [ "$MODULE_PLAYERBOTS" = "1" ] || [ "$PLAYERBOT_ENABLED" = "1" ]; then
        STACK_SOURCE_VARIANT="playerbots"
    else
        STACK_SOURCE_VARIANT="core"
    fi
fi
LOCAL_STORAGE_ROOT="${STORAGE_PATH_LOCAL:-./local-storage}"
DEFAULT_STANDARD_PATH="${LOCAL_STORAGE_ROOT%/}/source/azerothcore"
DEFAULT_PLAYERBOTS_PATH="${LOCAL_STORAGE_ROOT%/}/source/azerothcore-playerbots"

SOURCE_PATH_DEFAULT="$DEFAULT_STANDARD_PATH"
if [ "$STACK_SOURCE_VARIANT" = "playerbots" ]; then
    SOURCE_PATH_DEFAULT="$DEFAULT_PLAYERBOTS_PATH"
fi
SOURCE_PATH="${MODULES_REBUILD_SOURCE_PATH:-$SOURCE_PATH_DEFAULT}"

# Compare repo URLs ignoring case, scheme, trailing slashes and ".git"
# (same rules as manage-modules.sh).
normalize_repo_url(){
    local url="${1,,}"
    if [[ "$url" =~ ^[a-z]+:// ]]; then
        url="${url#*://}"
    fi
    while [[ "$url" == */ ]]; do url="${url%/}"; done
    url="${url%.git}"
    while [[ "$url" == */ ]]; do url="${url%/}"; done
    printf '%s' "$url"
}

# chown the checkout to the current user, through a root container when the
# user can't (same approach as repair-storage-permissions.sh, but only this
# directory).
take_source_ownership(){
    local target="$1" uid gid
    uid="$(id -u)"
    gid="$(id -g)"
    chown -R "$uid:$gid" "$target" 2>/dev/null && return 0
    command -v docker >/dev/null 2>&1 || return 1
    docker run --rm -u 0:0 -v "$target":/workspace "${ALPINE_IMAGE:-alpine:latest}" \
        chown -R "$uid:$gid" /workspace
}

# If the checkout differs from git only in file modes (e.g. a container ran
# chmod over the tree), put the modes back so pull doesn't refuse every file
# as a local change. Real edits are left alone for git to report.
restore_mode_only_changes(){
    if git diff --quiet || ! git -c core.fileMode=false diff --quiet \
        || ! git diff --cached --quiet; then
        return 0
    fi
    local meta path count=0
    while IFS= read -r -d '' meta && IFS= read -r -d '' path; do
        case "${meta%% *}" in
            :100644) chmod 644 "$path" ;;
            :100755) chmod 755 "$path" ;;
            *) continue ;;
        esac
        count=$((count + 1))
    done < <(git diff --raw -z)
    echo "🔧 Restored $count file-mode changes (no content changes) so the update can proceed"
}

show_client_data_requirement(){
    local repo_path="$1"
    local detector="$PROJECT_ROOT/scripts/bash/detect-client-data-version.sh"
    if [ ! -x "$detector" ]; then
        return
    fi

    local detection
    if ! detection="$("$detector" --no-header "$repo_path" 2>/dev/null | head -n1)"; then
        echo "⚠️  Could not detect client data version for $repo_path"
        return
    fi

    local detected_repo raw_version normalized_version
    IFS=$'\t' read -r detected_repo raw_version normalized_version <<< "$detection"
    if [ -z "$normalized_version" ] || [ "$normalized_version" = "<unknown>" ]; then
        echo "⚠️  Could not detect client data version for $repo_path"
        return
    fi

    local env_value="${CLIENT_DATA_VERSION:-}"
    if [ -n "$env_value" ] && [ "$env_value" != "$normalized_version" ]; then
        echo "⚠️  Source requires client data ${normalized_version} (raw ${raw_version}) but .env specifies ${env_value}. Update CLIENT_DATA_VERSION to avoid mismatched maps."
    elif [ -n "$env_value" ]; then
        echo "📦 Client data requirement satisfied: ${normalized_version} (raw ${raw_version})"
    else
        echo "ℹ️  Detected client data requirement: ${normalized_version} (raw ${raw_version}). Set CLIENT_DATA_VERSION in .env to avoid mismatches."
    fi
}

STORAGE_PATH_VALUE="${STORAGE_PATH:-./storage}"
if [[ "$STORAGE_PATH_VALUE" != /* ]]; then
    STORAGE_PATH_ABS="$PROJECT_ROOT/${STORAGE_PATH_VALUE#./}"
else
    STORAGE_PATH_ABS="$STORAGE_PATH_VALUE"
fi

if [[ "$SOURCE_PATH_DEFAULT" != /* ]]; then
    DEFAULT_SOURCE_ABS="$PROJECT_ROOT/${SOURCE_PATH_DEFAULT#./}"
else
    DEFAULT_SOURCE_ABS="$SOURCE_PATH_DEFAULT"
fi

# Convert to absolute path if relative and ensure we stay local
if [[ "$SOURCE_PATH" != /* ]]; then
    SOURCE_PATH="$PROJECT_ROOT/${SOURCE_PATH#./}"
fi
if [[ "$SOURCE_PATH" == "$STORAGE_PATH_ABS"* ]]; then
    echo "⚠️  Source path $SOURCE_PATH is inside shared storage ($STORAGE_PATH_ABS). Using local workspace $DEFAULT_SOURCE_ABS instead."
    SOURCE_PATH="$DEFAULT_SOURCE_ABS"
    MODULES_REBUILD_SOURCE_PATH="$SOURCE_PATH_DEFAULT"
fi

ACORE_REPO_STANDARD="${ACORE_REPO_STANDARD:-https://github.com/azerothcore/azerothcore-wotlk.git}"
ACORE_BRANCH_STANDARD="${ACORE_BRANCH_STANDARD:-master}"
ACORE_REPO_PLAYERBOTS="${ACORE_REPO_PLAYERBOTS:-https://github.com/mod-playerbots/azerothcore-wotlk.git}"
ACORE_BRANCH_PLAYERBOTS="${ACORE_BRANCH_PLAYERBOTS:-Playerbot}"

# Repository and branch selection based on source variant
if [ "$STACK_SOURCE_VARIANT" = "playerbots" ]; then
    REPO_URL="$ACORE_REPO_PLAYERBOTS"
    BRANCH="$ACORE_BRANCH_PLAYERBOTS"
    echo "📌 Playerbots mode: Using $REPO_URL, branch $BRANCH"
else
    REPO_URL="$ACORE_REPO_STANDARD"
    BRANCH="$ACORE_BRANCH_STANDARD"
    echo "📌 Standard mode: Using $REPO_URL, branch $BRANCH"
fi

echo "📍 Repository: $REPO_URL"
echo "🌿 Branch: $BRANCH"
echo "📂 Source path: $SOURCE_PATH"

# Ensure destination directories exist
echo "📂 Preparing local workspace at $(dirname "$SOURCE_PATH")"
mkdir -p "$(dirname "$SOURCE_PATH")"

# Clone or update repository
if [ -d "$SOURCE_PATH/.git" ]; then
  echo "📂 Existing repository found, updating..."
  cd "$SOURCE_PATH"

  # Never delete an existing checkout: it holds build output and may hold
  # local work. If the origin can't be read (e.g. git refuses a checkout owned
  # by another user) or points at another repo, stop and say why.
  # A checkout owned by another user (e.g. created by a root container) makes
  # git refuse it; take ownership of the checkout (only) once and retry.
  if ! CURRENT_REMOTE=$(git remote get-url origin 2>&1) \
      && [[ "$CURRENT_REMOTE" == *"dubious ownership"* ]]; then
    echo "🔧 $SOURCE_PATH is owned by another user; taking ownership..."
    take_source_ownership "$SOURCE_PATH" || true
  fi
  if ! CURRENT_REMOTE=$(git remote get-url origin 2>&1); then
    echo "❌ Cannot read the origin of $SOURCE_PATH:" >&2
    echo "   $CURRENT_REMOTE" >&2
    echo "   If the checkout is owned by another user (e.g. root), fix ownership with:" >&2
    echo "   sudo chown -R \"\$(id -u):\$(id -g)\" \"$SOURCE_PATH\"" >&2
    exit 1
  fi
  if [ "$(normalize_repo_url "$CURRENT_REMOTE")" != "$(normalize_repo_url "$REPO_URL")" ]; then
    echo "❌ $SOURCE_PATH points at a different repository:" >&2
    echo "   origin:   $CURRENT_REMOTE" >&2
    echo "   expected: $REPO_URL" >&2
    echo "   Move or remove that directory to clone $REPO_URL there, or point it at the new repo with:" >&2
    echo "   git -C \"$SOURCE_PATH\" remote set-url origin \"$REPO_URL\"" >&2
    exit 1
  fi
  restore_mode_only_changes
  echo "🔄 Fetching latest changes from origin..."
  git fetch origin --progress
  echo "🔀 Switching to branch $BRANCH..."
  git checkout "$BRANCH"
  echo "⬇️  Pulling latest commits..."
  git pull --ff-only origin "$BRANCH"
  echo "✅ Repository updated to latest $BRANCH"
else
  echo "📥 Cloning repository..."
  echo "⏳ Cloning $REPO_URL (branch $BRANCH) into $SOURCE_PATH"
  git clone -b "$BRANCH" "$REPO_URL" "$SOURCE_PATH"
  echo "✅ Repository cloned successfully"
fi

cd "$SOURCE_PATH"

# Display current status
CURRENT_COMMIT=$(git rev-parse --short HEAD)
CURRENT_BRANCH=$(git branch --show-current)
echo "📊 Current status:"
echo "   Branch: $CURRENT_BRANCH"
echo "   Commit: $CURRENT_COMMIT"
echo "   Last commit: $(git log -1 --pretty=format:'%s (%an, %ar)')"
show_client_data_requirement "$SOURCE_PATH"

echo '🎉 Source repository setup complete!'
