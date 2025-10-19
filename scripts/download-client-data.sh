#!/bin/bash
# ac-compose
set -e

echo '🚀 Starting AzerothCore game data setup...'

# Get the latest release info from wowgaming/client-data
REQUESTED_TAG="${CLIENT_DATA_VERSION:-}"
if [ -n "$REQUESTED_TAG" ]; then
  echo "📌 Using requested client data version: $REQUESTED_TAG"
  LATEST_TAG="$REQUESTED_TAG"
  LATEST_URL="https://github.com/wowgaming/client-data/releases/download/${REQUESTED_TAG}/data.zip"
else
  echo '📡 Fetching latest client data release info...'
  RELEASE_INFO=$(wget -qO- https://api.github.com/repos/wowgaming/client-data/releases/latest 2>/dev/null)

  if [ -n "$RELEASE_INFO" ]; then
    LATEST_URL=$(echo "$RELEASE_INFO" | grep '"browser_download_url":' | grep '\.zip' | cut -d'"' -f4 | head -1)
    LATEST_TAG=$(echo "$RELEASE_INFO" | grep '"tag_name":' | cut -d'"' -f4)
    LATEST_SIZE=$(echo "$RELEASE_INFO" | grep '"size":' | head -1 | grep -o '[0-9]*')
  fi

if [ -z "$LATEST_URL" ]; then
  echo '❌ Could not fetch client-data release information. Aborting.'
  exit 1
fi
fi

echo "📍 Latest release: $LATEST_TAG"
echo "📥 Download URL: $LATEST_URL"

# Cache file paths
CACHE_DIR="/cache"
mkdir -p "$CACHE_DIR"
CACHE_FILE="${CACHE_DIR}/client-data-${LATEST_TAG}.zip"
TMP_FILE="${CACHE_FILE}.tmp"
VERSION_FILE="${CACHE_DIR}/client-data-version.txt"

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
      if 7z t "$CACHE_FILE" >/dev/null 2>&1; then
        CACHE_INTEGRITY_OK=true
      fi
    fi

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
    rm -f "${CACHE_DIR}"/client-data-*.zip "$VERSION_FILE"
  fi
fi

# Download if we don't have a valid cached file
if [ ! -f "data.zip" ]; then
  echo "📥 Downloading client data (~15GB)..."
  echo "📍 Source: $LATEST_URL"

  if command -v aria2c >/dev/null 2>&1; then
    aria2c --max-connection-per-server=8 --split=8 --min-split-size=10M \
           --summary-interval=5 --download-result=hide \
           --console-log-level=warn --show-console-readout=false \
           --dir "$CACHE_DIR" -o "$(basename "$TMP_FILE")" "$LATEST_URL" || {
      echo '⚠️ aria2c failed, falling back to wget...'
      wget --progress=dot:giga -O "$TMP_FILE" "$LATEST_URL" 2>&1 | sed 's/^/📊 /' || {
        echo '❌ wget failed, trying curl...'
        curl -L --progress-bar -o "$TMP_FILE" "$LATEST_URL" || {
          echo '❌ All download methods failed'
          rm -f "$TMP_FILE"
          exit 1
        }
      }
    }
  else
    echo "📥 Using wget (aria2c not available)..."
    wget --progress=dot:giga -O "$TMP_FILE" "$LATEST_URL" 2>&1 | sed 's/^/📊 /' || {
      echo '❌ wget failed, trying curl...'
      curl -L --progress-bar -o "$TMP_FILE" "$LATEST_URL" || {
        echo '❌ All download methods failed'
        rm -f "$TMP_FILE"
        exit 1
      }
    }
  fi

  echo "🔍 Verifying download integrity..."
  INTEGRITY_OK=false

  if command -v 7z >/dev/null 2>&1; then
    if 7z t "$TMP_FILE" >/dev/null 2>&1; then
      INTEGRITY_OK=true
    fi
  fi

  if [ "$INTEGRITY_OK" = "false" ]; then
    if unzip -t "$TMP_FILE" > /dev/null 2>&1; then
      INTEGRITY_OK=true
    fi
  fi

  if [ "$INTEGRITY_OK" = "true" ]; then
    mv "$TMP_FILE" "$CACHE_FILE"
    echo "$LATEST_TAG" > "$VERSION_FILE"
    echo '✅ Download completed and verified'
    echo "📊 File size: $(ls -lh "$CACHE_FILE" | awk '{print $5}')"
    cp "$CACHE_FILE" data.zip
  else
    echo '❌ Downloaded file is corrupted'
    rm -f "$TMP_FILE"
    exit 1
  fi
fi

echo '📂 Extracting client data (this may take some minutes)...'
rm -rf /azerothcore/data/maps /azerothcore/data/vmaps /azerothcore/data/mmaps /azerothcore/data/dbc

if command -v 7z >/dev/null 2>&1; then
  7z x -aoa -o/azerothcore/data/ data.zip >/dev/null 2>&1
else
  unzip -o -q data.zip -d /azerothcore/data/
fi

rm -f data.zip

echo '✅ Client data extraction complete!'
for dir in maps vmaps mmaps dbc; do
  if [ -d "/azerothcore/data/$dir" ] && [ -n "$(ls -A /azerothcore/data/$dir 2>/dev/null)" ]; then
    DIR_SIZE=$(du -sh /azerothcore/data/$dir 2>/dev/null | cut -f1)
    echo "✅ $dir directory: OK ($DIR_SIZE)"
  else
    echo "❌ $dir directory: MISSING or EMPTY"
    exit 1
  fi
done

echo '🎉 Game data setup complete! AzerothCore worldserver can now start.'
