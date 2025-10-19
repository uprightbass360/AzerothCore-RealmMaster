#!/bin/bash
# ac-compose source repository setup
set -e

echo '🔧 Setting up AzerothCore source repository...'

# Load environment variables if .env exists
if [ -f .env ]; then
    source .env
fi

# Default values
SOURCE_PATH="${MODULES_REBUILD_SOURCE_PATH:-./source/azerothcore}"

# Convert to absolute path if relative
if [[ "$SOURCE_PATH" != /* ]]; then
    SOURCE_PATH="$(pwd)/$SOURCE_PATH"
fi
MODULE_PLAYERBOTS="${MODULE_PLAYERBOTS:-0}"

# Repository and branch selection based on playerbots mode
if [ "$MODULE_PLAYERBOTS" = "1" ]; then
    REPO_URL="https://github.com/liyunfan1223/azerothcore-wotlk.git"
    BRANCH="Playerbot"
    echo "📌 Playerbots mode: Using liyunfan1223 fork, Playerbot branch"
else
    REPO_URL="https://github.com/azerothcore/azerothcore-wotlk.git"
    BRANCH="master"
    echo "📌 Standard mode: Using official AzerothCore, master branch"
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