#!/bin/bash
set -e

echo '🚀 Starting AzerothCore game data setup...'

# Get the latest release info from wowgaming/client-data
echo '📡 Fetching latest client data release info...'
RELEASE_INFO=$(wget -qO- https://api.github.com/repos/wowgaming/client-data/releases/latest 2>/dev/null)

if [ -n "$RELEASE_INFO" ]; then
  LATEST_URL=$(echo "$RELEASE_INFO" | grep '"browser_download_url":' | grep '\.zip' | cut -d'"' -f4 | head -1)
  LATEST_TAG=$(echo "$RELEASE_INFO" | grep '"tag_name":' | cut -d'"' -f4)
  LATEST_SIZE=$(echo "$RELEASE_INFO" | grep '"size":' | head -1 | grep -o '[0-9]*')
fi

if [ -z "$LATEST_URL" ]; then
  echo '❌ Could not fetch latest release URL'
  echo '📥 Using fallback: direct download from v16 release'
  LATEST_URL='https://github.com/wowgaming/client-data/releases/download/v16/data.zip'
  LATEST_TAG='v16'
  LATEST_SIZE='0'
fi

echo "📍 Latest release: $LATEST_TAG"
echo "📥 Download URL: $LATEST_URL"

# Cache file paths
CACHE_FILE="/cache/client-data-$LATEST_TAG.zip"
VERSION_FILE="/cache/client-data-version.txt"

# Check if we have a cached version
if [ -f "$CACHE_FILE" ] && [ -f "$VERSION_FILE" ]; then
  CACHED_VERSION=$(cat "$VERSION_FILE" 2>/dev/null)
  if [ "$CACHED_VERSION" = "$LATEST_TAG" ]; then
    echo "✅ Found cached client data version $LATEST_TAG"
    echo "📊 Cached file size: $(ls -lh "$CACHE_FILE" | awk '{print $5}')"

    # Verify cache file integrity
    if unzip -t "$CACHE_FILE" > /dev/null 2>&1; then
      echo "✅ Cache file integrity verified"
      echo "⚡ Using cached download - skipping download phase"
      cp "$CACHE_FILE" data.zip
    else
      echo "⚠️ Cache file corrupted, will re-download"
      rm -f "$CACHE_FILE" "$VERSION_FILE"
    fi
  else
    echo "📦 Cache version ($CACHED_VERSION) differs from latest ($LATEST_TAG)"
    echo "🗑️ Removing old cache"
    rm -f /cache/client-data-*.zip "$VERSION_FILE"
  fi
fi

# Download if we don't have a valid cached file
if [ ! -f "data.zip" ]; then
  echo "📥 Downloading client data (~15GB, may take 10-30 minutes)..."
  echo "📍 Source: $LATEST_URL"

  # Download with clean progress indication
  echo "📥 Starting download..."
  wget --progress=dot:giga -O "$CACHE_FILE.tmp" "$LATEST_URL" 2>&1 | sed 's/^/📊 /' || {
    echo '❌ wget failed, trying curl...'
    curl -L --progress-bar -o "$CACHE_FILE.tmp" "$LATEST_URL" || {
      echo '❌ All download methods failed'
      rm -f "$CACHE_FILE.tmp"
      exit 1
    }
  }

  # Verify download integrity
  if unzip -t "$CACHE_FILE.tmp" > /dev/null 2>&1; then
    mv "$CACHE_FILE.tmp" "$CACHE_FILE"
    echo "$LATEST_TAG" > "$VERSION_FILE"
    echo '✅ Download completed and verified'
    echo "📊 File size: $(ls -lh "$CACHE_FILE" | awk '{print $5}')"
    cp "$CACHE_FILE" data.zip
  else
    echo '❌ Downloaded file is corrupted'
    rm -f "$CACHE_FILE.tmp"
    exit 1
  fi
fi

echo '📂 Extracting client data (this may take 10-15 minutes)...'
echo '⏳ Please wait while extracting...'

# Clear existing data if extraction failed previously
rm -rf /azerothcore/data/maps /azerothcore/data/vmaps /azerothcore/data/mmaps /azerothcore/data/dbc

# Extract with detailed progress tracking
echo '🔄 Starting extraction with progress monitoring...'

# Start extraction in background with overwrite
unzip -o -q data.zip -d /azerothcore/data/ &

UNZIP_PID=$!
LAST_CHECK_TIME=0

# Monitor progress with directory size checks
while kill -0 "$UNZIP_PID" 2>/dev/null; do
  CURRENT_TIME=$(date +%s)
  if [ $((CURRENT_TIME - LAST_CHECK_TIME)) -ge 30 ]; then
    LAST_CHECK_TIME=$CURRENT_TIME

    # Check what's been extracted so far
    PROGRESS_MSG="📊 Progress at $(date '+%H:%M:%S'):"

    if [ -d "/azerothcore/data/dbc" ] && [ -n "$(ls -A /azerothcore/data/dbc 2>/dev/null)" ]; then
      DBC_SIZE=$(du -sh /azerothcore/data/dbc 2>/dev/null | cut -f1)
      PROGRESS_MSG="$PROGRESS_MSG DBC($DBC_SIZE)"
    fi

    if [ -d "/azerothcore/data/maps" ] && [ -n "$(ls -A /azerothcore/data/maps 2>/dev/null)" ]; then
      MAPS_SIZE=$(du -sh /azerothcore/data/maps 2>/dev/null | cut -f1)
      PROGRESS_MSG="$PROGRESS_MSG Maps($MAPS_SIZE)"
    fi

    if [ -d "/azerothcore/data/vmaps" ] && [ -n "$(ls -A /azerothcore/data/vmaps 2>/dev/null)" ]; then
      VMAPS_SIZE=$(du -sh /azerothcore/data/vmaps 2>/dev/null | cut -f1)
      PROGRESS_MSG="$PROGRESS_MSG VMaps($VMAPS_SIZE)"
    fi

    if [ -d "/azerothcore/data/mmaps" ] && [ -n "$(ls -A /azerothcore/data/mmaps 2>/dev/null)" ]; then
      MMAPS_SIZE=$(du -sh /azerothcore/data/mmaps 2>/dev/null | cut -f1)
      PROGRESS_MSG="$PROGRESS_MSG MMaps($MMAPS_SIZE)"
    fi

    echo "$PROGRESS_MSG"
  fi
  sleep 5
done

wait "$UNZIP_PID"
UNZIP_EXIT_CODE=$?

if [ $UNZIP_EXIT_CODE -ne 0 ]; then
  echo '❌ Extraction failed'
  rm -f data.zip
  exit 1
fi

# Clean up temporary extraction file (keep cached version)
rm -f data.zip

echo '✅ Client data extraction complete!'
echo '📁 Verifying extracted directories:'

# Verify required directories exist and have content
ALL_GOOD=true
for dir in maps vmaps mmaps dbc; do
  if [ -d "/azerothcore/data/$dir" ] && [ -n "$(ls -A /azerothcore/data/$dir 2>/dev/null)" ]; then
    DIR_SIZE=$(du -sh /azerothcore/data/$dir 2>/dev/null | cut -f1)
    echo "✅ $dir directory: OK ($DIR_SIZE)"
  else
    echo "❌ $dir directory: MISSING or EMPTY"
    ALL_GOOD=false
  fi
done

if [ "$ALL_GOOD" = "true" ]; then
  echo '🎉 Game data setup complete! AzerothCore worldserver can now start.'
  echo "💾 Cached version $LATEST_TAG for future use"
else
  echo '❌ Some directories are missing or empty'
  exit 1
fi