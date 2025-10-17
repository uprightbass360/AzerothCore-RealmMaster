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
    echo "🔍 Verifying cached file integrity..."
    CACHE_INTEGRITY_OK=false

    if command -v 7z >/dev/null 2>&1; then
      # Use 7z for integrity check if available (faster and more reliable)
      if 7z t "$CACHE_FILE" >/dev/null 2>&1; then
        CACHE_INTEGRITY_OK=true
      fi
    fi

    # Fallback to unzip if 7z check failed or is not available
    if [ "$CACHE_INTEGRITY_OK" = "false" ]; then
      if unzip -t "$CACHE_FILE" > /dev/null 2>&1; then
        CACHE_INTEGRITY_OK=true
      fi
    fi

    if [ "$CACHE_INTEGRITY_OK" = "true" ]; then
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
  echo "📥 Downloading client data (~15GB, may take 5-20 minutes with multi-connection)..."
  echo "📍 Source: $LATEST_URL"

  # Download with multi-connection support for speed
  echo "📥 Starting download with multi-connection support..."
  if command -v aria2c >/dev/null 2>&1; then
    echo "🚀 Using aria2c for faster multi-connection download..."
    aria2c --max-connection-per-server=8 --split=8 --min-split-size=10M \
           --summary-interval=5 --download-result=hide \
           --console-log-level=warn --show-console-readout=false \
           -o "$CACHE_FILE.tmp" "$LATEST_URL" || {
      echo '⚠️ aria2c failed, falling back to wget...'
      wget --progress=dot:giga -O "$CACHE_FILE.tmp" "$LATEST_URL" 2>&1 | sed 's/^/📊 /' || {
        echo '❌ wget failed, trying curl...'
        curl -L --progress-bar -o "$CACHE_FILE.tmp" "$LATEST_URL" || {
          echo '❌ All download methods failed'
          rm -f "$CACHE_FILE.tmp"
          exit 1
        }
      }
    }
  else
    echo "📥 Using wget (aria2c not available)..."
    wget --progress=dot:giga -O "$CACHE_FILE.tmp" "$LATEST_URL" 2>&1 | sed 's/^/📊 /' || {
      echo '❌ wget failed, trying curl...'
      curl -L --progress-bar -o "$CACHE_FILE.tmp" "$LATEST_URL" || {
        echo '❌ All download methods failed'
        rm -f "$CACHE_FILE.tmp"
        exit 1
      }
    }
  fi

  # Verify download integrity
  echo "🔍 Verifying download integrity..."
  INTEGRITY_OK=false

  if command -v 7z >/dev/null 2>&1; then
    # Use 7z for integrity check if available (faster and more reliable)
    if 7z t "$CACHE_FILE.tmp" >/dev/null 2>&1; then
      INTEGRITY_OK=true
    fi
  fi

  # Fallback to unzip if 7z check failed or is not available
  if [ "$INTEGRITY_OK" = "false" ]; then
    if unzip -t "$CACHE_FILE.tmp" > /dev/null 2>&1; then
      INTEGRITY_OK=true
    fi
  fi

  if [ "$INTEGRITY_OK" = "true" ]; then
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

echo '📂 Extracting client data (this may take 5-10 minutes with parallel extraction)...'
echo '⏳ Please wait while extracting...'

# Clear existing data if extraction failed previously
rm -rf /azerothcore/data/maps /azerothcore/data/vmaps /azerothcore/data/mmaps /azerothcore/data/dbc

# Extract with detailed progress tracking using 7z for parallel processing
echo '🔄 Starting parallel extraction with progress monitoring...'

# Use 7z if available for parallel extraction, fallback to unzip
if command -v 7z >/dev/null 2>&1; then
  echo '🚀 Using 7z for faster parallel extraction...'
  # Start extraction in background with overwrite and parallel processing
  7z x -aoa -o/azerothcore/data/ data.zip >/dev/null 2>&1 &
  EXTRACT_PID=$!
  EXTRACT_CMD="7z"
else
  echo '📥 Using unzip (7z not available)...'
  # Start extraction in background with overwrite
  unzip -o -q data.zip -d /azerothcore/data/ &
  EXTRACT_PID=$!
  EXTRACT_CMD="unzip"
fi
LAST_CHECK_TIME=0

# Monitor progress with directory size checks
while kill -0 "$EXTRACT_PID" 2>/dev/null; do
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

wait "$EXTRACT_PID"
EXTRACT_EXIT_CODE=$?

if [ $EXTRACT_EXIT_CODE -ne 0 ]; then
  echo "❌ Extraction failed ($EXTRACT_CMD returned exit code $EXTRACT_EXIT_CODE)"
  rm -f data.zip
  exit 1
fi

# Handle nested Data directory issue - move contents if extracted to Data subdirectory
if [ -d "/azerothcore/data/Data" ] && [ -n "$(ls -A /azerothcore/data/Data 2>/dev/null)" ]; then
  echo '🔧 Fixing data directory structure (moving from Data/ subdirectory)...'

  # Move all contents from Data subdirectory to the root data directory
  for item in /azerothcore/data/Data/*; do
    if [ -e "$item" ]; then
      mv "$item" /azerothcore/data/ 2>/dev/null || {
        echo "⚠️  Could not move $(basename "$item"), using copy instead..."
        cp -r "$item" /azerothcore/data/
        rm -rf "$item"
      }
    fi
  done

  # Remove empty Data directory
  rmdir /azerothcore/data/Data 2>/dev/null || true
  echo '✅ Data directory structure fixed'
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