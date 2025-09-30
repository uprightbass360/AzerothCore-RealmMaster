#!/bin/bash
# Real-time monitoring script for Portainer deployment
# Run this DURING deployment to monitor progress and catch issues

echo "==============================================="
echo "AzerothCore Portainer Deployment Monitor"
echo "==============================================="

# Function to monitor container logs
monitor_container() {
    local container_name=$1
    local max_wait=${2:-300}  # Default 5 minutes
    local start_time=$(date +%s)

    echo "🔍 Monitoring $container_name (max wait: ${max_wait}s)"

    while [ $(($(date +%s) - start_time)) -lt $max_wait ]; do
        if podman ps --filter "name=$container_name" --format "table {{.Names}}\t{{.Status}}" | grep -q "$container_name"; then
            local status=$(podman ps --filter "name=$container_name" --format "{{.Status}}")
            echo "[$container_name] Status: $status"

            # Show last few log lines
            echo "[$container_name] Recent logs:"
            podman logs --tail 5 "$container_name" 2>&1 | sed 's/^/  /'
            echo ""

            # Check if container exited
            if echo "$status" | grep -q "Exited"; then
                local exit_code=$(podman ps -a --filter "name=$container_name" --format "{{.Status}}" | grep -o "Exited ([0-9]*)" | grep -o "[0-9]*")
                if [ "$exit_code" = "0" ]; then
                    echo "✅ $container_name completed successfully"
                    return 0
                else
                    echo "❌ $container_name failed (exit code: $exit_code)"
                    echo "Full error logs:"
                    podman logs "$container_name" 2>&1 | tail -20 | sed 's/^/  /'
                    return 1
                fi
            fi
        else
            echo "⏳ Waiting for $container_name to start..."
        fi

        sleep 10
    done

    echo "⏰ Timeout waiting for $container_name"
    return 1
}

# Function to monitor network download progress
monitor_download() {
    local container_name="ac-client-data"
    echo "📥 Monitoring client data download progress..."

    while podman ps --filter "name=$container_name" --format "{{.Names}}" | grep -q "$container_name"; do
        # Look for download progress in logs
        podman logs "$container_name" 2>&1 | tail -10 | grep -E "(downloading|download|MB|GB|%)" | tail -3 | sed 's/^/  /'

        # Check disk usage in data directory
        if podman exec "$container_name" ls -la /azerothcore/data/ 2>/dev/null; then
            echo "  📁 Current data directory contents:"
            podman exec "$container_name" du -sh /azerothcore/data/* 2>/dev/null | sed 's/^/    /' || echo "    (empty or not accessible)"
        fi

        echo "---"
        sleep 30
    done
}

# Function to check database import progress
monitor_db_import() {
    local container_name="ac-db-import"
    echo "🗄️  Monitoring database import progress..."

    while podman ps --filter "name=$container_name" --format "{{.Names}}" | grep -q "$container_name"; do
        echo "[$container_name] Recent activity:"
        podman logs "$container_name" 2>&1 | tail -5 | sed 's/^/  /'

        # Check database size growth
        echo "  📊 Database status:"
        podman exec ac-mysql mysql -uroot -p${DOCKER_DB_ROOT_PASSWORD:-password} -e "
            SELECT
                table_schema as 'Database',
                ROUND(SUM(data_length + index_length) / 1024 / 1024, 2) as 'Size (MB)'
            FROM information_schema.tables
            WHERE table_schema IN ('acore_auth', 'acore_world', 'acore_characters')
            GROUP BY table_schema;
        " 2>/dev/null | sed 's/^/    /' || echo "    Database not accessible yet"

        echo "---"
        sleep 20
    done
}

# Main monitoring loop
echo "🚀 Starting deployment monitoring..."
echo "Press Ctrl+C to stop monitoring"
echo ""

# Load environment variables if .env exists
if [ -f ".env" ]; then
    export $(grep -v '^#' .env | xargs)
fi

# Monitor the deployment phases
echo "Phase 1: MySQL startup"
monitor_container "ac-mysql" 120

echo "Phase 2: Database initialization"
monitor_container "ac-db-init" 60

echo "Phase 3: Client data download (this will take longest)"
monitor_download &
DOWNLOAD_PID=$!
monitor_container "ac-client-data" 2400  # 40 minutes max
kill $DOWNLOAD_PID 2>/dev/null

echo "Phase 4: Database import"
monitor_db_import &
IMPORT_PID=$!
monitor_container "ac-db-import" 1800  # 30 minutes max
kill $IMPORT_PID 2>/dev/null

echo "Phase 5: Application servers"
monitor_container "ac-authserver" 120
monitor_container "ac-worldserver" 180

echo ""
echo "🏁 Monitoring complete!"
echo ""
echo "💡 If you see timeouts or failures:"
echo "1. Check 'podman-compose logs [service-name]' for detailed errors"
echo "2. Restart individual failed services with 'podman-compose up [service-name]'"
echo "3. Consider running services one at a time instead of all at once"