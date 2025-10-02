#!/bin/bash

# AzerothCore Module Rebuild Script
# Automates the process of rebuilding AzerothCore with enabled modules

set -e

echo "🔧 AzerothCore Module Rebuild Script"
echo "==================================="
echo ""

# Check if source repository exists
SOURCE_COMPOSE="/tmp/acore-dev-test/docker-compose.yml"
if [ ! -f "$SOURCE_COMPOSE" ]; then
    echo "❌ Error: Source-based Docker Compose file not found at $SOURCE_COMPOSE"
    echo "Please ensure AzerothCore source repository is available for compilation."
    exit 1
fi

# Check current module configuration
echo "📋 Checking current module configuration..."

MODULES_ENABLED=0
ENABLED_MODULES=""

# Read environment file to check enabled modules
if [ -f "docker-compose-azerothcore-services.env" ]; then
    while IFS= read -r line; do
        if echo "$line" | grep -q "^MODULE_.*=1$"; then
            MODULE_NAME=$(echo "$line" | cut -d'=' -f1)
            MODULES_ENABLED=$((MODULES_ENABLED + 1))
            ENABLED_MODULES="$ENABLED_MODULES $MODULE_NAME"
        fi
    done < docker-compose-azerothcore-services.env
else
    echo "⚠️  Warning: Environment file not found, checking default configuration..."
fi

echo "🔍 Found $MODULES_ENABLED enabled modules"

if [ $MODULES_ENABLED -eq 0 ]; then
    echo "✅ No modules enabled - rebuild not required"
    echo "You can use pre-built containers for better performance."
    exit 0
fi

echo "📦 Enabled modules:$ENABLED_MODULES"
echo ""

# Confirm rebuild
read -p "🤔 Proceed with rebuild? This will take 15-45 minutes. (y/N): " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Rebuild cancelled"
    exit 0
fi

echo ""
echo "🛑 Stopping current services..."
docker compose -f docker-compose-azerothcore-services.yml down || echo "⚠️  Services may not be running"

echo ""
echo "🔧 Starting source-based compilation..."
echo "⏱️  This will take 15-45 minutes depending on your system..."
echo ""

# Build with source
cd /tmp/acore-dev-test
echo "📁 Switched to source directory: $(pwd)"

# Copy modules to source build
echo "📋 Copying modules to source build..."
if [ -d "/home/upb/src/acore-compose2/storage/azerothcore/modules" ]; then
    # Ensure modules directory exists in source
    mkdir -p modules

    # Copy enabled modules only
    echo "🔄 Syncing enabled modules..."
    for module_dir in /home/upb/src/acore-compose2/storage/azerothcore/modules/*/; do
        if [ -d "$module_dir" ]; then
            module_name=$(basename "$module_dir")
            echo "   Copying $module_name..."
            cp -r "$module_dir" modules/
        fi
    done
else
    echo "⚠️  Warning: No modules directory found"
fi

# Start build process
echo ""
echo "🚀 Building AzerothCore with modules..."
docker compose build --no-cache

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ Build completed successfully!"
    echo ""

    # Start services
    echo "🟢 Starting services with compiled modules..."
    docker compose up -d

    if [ $? -eq 0 ]; then
        echo ""
        echo "🎉 SUCCESS! AzerothCore is now running with compiled modules."
        echo ""
        echo "📊 Service status:"
        docker compose ps
        echo ""
        echo "📝 To monitor logs:"
        echo "   docker compose logs -f"
        echo ""
        echo "🌐 Server should be available on configured ports once fully started."
    else
        echo "❌ Failed to start services"
        exit 1
    fi
else
    echo "❌ Build failed"
    echo ""
    echo "🔍 Check build logs for errors:"
    echo "   docker compose logs"
    exit 1
fi

echo ""
echo "✅ Rebuild process complete!"