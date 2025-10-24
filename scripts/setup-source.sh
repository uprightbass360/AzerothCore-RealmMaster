#!/bin/bash
# ac-compose source repository setup
set -e

echo '🔧 Setting up AzerothCore source repository...'

# Load environment variables if .env exists
if [ -f .env ]; then
    source .env
fi

# Remember project root for path normalization
PROJECT_ROOT="$(pwd)"

# Default values
MODULE_PLAYERBOTS="${MODULE_PLAYERBOTS:-0}"
DEFAULT_STANDARD_PATH="./source/azerothcore"
DEFAULT_PLAYERBOTS_PATH="./source/azerothcore-playerbots"

SOURCE_PATH_DEFAULT="$DEFAULT_STANDARD_PATH"
if [ "$MODULE_PLAYERBOTS" = "1" ]; then
    SOURCE_PATH_DEFAULT="$DEFAULT_PLAYERBOTS_PATH"
fi
SOURCE_PATH="${MODULES_REBUILD_SOURCE_PATH:-$SOURCE_PATH_DEFAULT}"

STORAGE_PATH_VALUE="${STORAGE_PATH:-./storage}"
if [[ "$STORAGE_PATH_VALUE" != /* ]]; then
    STORAGE_PATH_ABS="$PROJECT_ROOT/${STORAGE_PATH_VALUE#./}"
else
    STORAGE_PATH_ABS="$STORAGE_PATH_VALUE"
fi

DEFAULT_SOURCE_ABS="$PROJECT_ROOT/${SOURCE_PATH_DEFAULT#./}"

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
ACORE_REPO_PLAYERBOTS="${ACORE_REPO_PLAYERBOTS:-https://github.com/uprightbass360/azerothcore-wotlk-playerbots.git}"
ACORE_BRANCH_PLAYERBOTS="${ACORE_BRANCH_PLAYERBOTS:-Playerbot}"

# Repository and branch selection based on playerbots mode
if [ "$MODULE_PLAYERBOTS" = "1" ]; then
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

# Create source directory if it doesn't exist
mkdir -p "$(dirname "$SOURCE_PATH")"

# Clone or update repository
if [ -d "$SOURCE_PATH/.git" ]; then
    echo "📂 Existing repository found, updating..."
    cd "$SOURCE_PATH"

    # Check if we're on the correct repository
    CURRENT_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
    if [ "$CURRENT_REMOTE" != "$REPO_URL" ]; then
        echo "🔄 Repository URL changed, re-cloning..."
        cd ..
        rm -rf "$(basename "$SOURCE_PATH")"
        git clone "$REPO_URL" "$(basename "$SOURCE_PATH")"
        cd "$(basename "$SOURCE_PATH")"
    fi

    # Fetch latest changes
    git fetch origin

    # Switch to target branch
    git checkout "$BRANCH"
    git pull origin "$BRANCH"

    echo "✅ Repository updated to latest $BRANCH"
else
    echo "📥 Cloning repository..."
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

echo '🎉 Source repository setup complete!'
