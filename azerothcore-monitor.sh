#!/bin/bash
# ==============================================
# AzerothCore Advanced Monitoring Script
# ==============================================
# Real-time monitoring with alerts and health checks

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)"
LOG_DIR="$SCRIPT_DIR/monitoring-logs"
ALERT_LOG="$LOG_DIR/alerts-$(date +%Y%m%d).log"
METRICS_LOG="$LOG_DIR/metrics-$(date +%Y%m%d).log"
WEB_DIR="$SCRIPT_DIR/monitoring-web"

# Create directories
mkdir -p "$LOG_DIR" "$WEB_DIR"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Monitoring configuration
declare -A EXPECTED_SERVICES=(
    ["ac-mysql"]="MySQL Database"
    ["ac-authserver"]="Authentication Server"
    ["ac-worldserver"]="World Server"
    ["ac-backup"]="Backup Service"
)

declare -A HEALTH_THRESHOLDS=(
    ["cpu_warn"]=80
    ["cpu_critical"]=95
    ["memory_warn"]=80
    ["memory_critical"]=95
    ["disk_warn"]=85
    ["disk_critical"]=95
)

# Alert functions
send_alert() {
    local level="$1"
    local service="$2"
    local message="$3"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    case "$level" in
        "CRITICAL") echo -e "${RED}[CRITICAL]${NC} $service: $message" ;;
        "WARNING")  echo -e "${YELLOW}[WARNING]${NC} $service: $message" ;;
        "INFO")     echo -e "${BLUE}[INFO]${NC} $service: $message" ;;
        "OK")       echo -e "${GREEN}[OK]${NC} $service: $message" ;;
    esac

    echo "[$timestamp] [$level] $service: $message" >> "$ALERT_LOG"
}

# Get container stats
get_container_stats() {
    local container="$1"

    if ! docker ps --filter "name=$container" --format "{{.Names}}" | grep -q "^${container}$"; then
        echo "status=missing"
        return 1
    fi

    local stats=$(docker stats --no-stream --format "{{.CPUPerc}},{{.MemPerc}},{{.MemUsage}},{{.NetIO}},{{.BlockIO}}" "$container" 2>/dev/null || echo "0.00%,0.00%,0B / 0B,0B / 0B,0B / 0B")

    echo "status=running,$stats"
}

# Monitor service health
check_service_health() {
    local service="$1"
    local description="${EXPECTED_SERVICES[$service]}"

    local stats=$(get_container_stats "$service")

    if [[ "$stats" == "status=missing" ]]; then
        send_alert "CRITICAL" "$service" "$description is not running"
        return 1
    fi

    # Parse stats
    IFS=',' read -r status cpu_percent mem_percent mem_usage net_io block_io <<< "$stats"

    # Remove % signs for comparison
    local cpu_num=$(echo "$cpu_percent" | sed 's/%//')
    local mem_num=$(echo "$mem_percent" | sed 's/%//')

    # Convert to integers for comparison
    cpu_num=$(printf "%.0f" "$cpu_num" 2>/dev/null || echo "0")
    mem_num=$(printf "%.0f" "$mem_num" 2>/dev/null || echo "0")

    # Check thresholds
    if [[ $cpu_num -gt ${HEALTH_THRESHOLDS["cpu_critical"]} ]]; then
        send_alert "CRITICAL" "$service" "CPU usage critical: ${cpu_percent}"
    elif [[ $cpu_num -gt ${HEALTH_THRESHOLDS["cpu_warn"]} ]]; then
        send_alert "WARNING" "$service" "CPU usage high: ${cpu_percent}"
    fi

    if [[ $mem_num -gt ${HEALTH_THRESHOLDS["memory_critical"]} ]]; then
        send_alert "CRITICAL" "$service" "Memory usage critical: ${mem_percent}"
    elif [[ $mem_num -gt ${HEALTH_THRESHOLDS["memory_warn"]} ]]; then
        send_alert "WARNING" "$service" "Memory usage high: ${mem_percent}"
    fi

    # Log metrics
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "$timestamp,$service,$cpu_percent,$mem_percent,$mem_usage,$net_io,$block_io" >> "$METRICS_LOG"

    return 0
}

# Check database connectivity
check_database_health() {
    if docker run --rm --network azerothcore mysql:8.0 \
        mysql -h ac-mysql -uroot -p"${MYSQL_ROOT_PASSWORD:-azerothcore123}" \
        -e "SELECT 1;" &>/dev/null; then
        send_alert "OK" "database" "Database connectivity verified"
        return 0
    else
        send_alert "CRITICAL" "database" "Database connectivity failed"
        return 1
    fi
}

# Check game server ports
check_game_ports() {
    local auth_port="3784"
    local world_port="8215"

    # Check auth server port
    if timeout 5 bash -c "</dev/tcp/localhost/$auth_port" 2>/dev/null; then
        send_alert "OK" "authserver" "Port $auth_port responding"
    else
        send_alert "WARNING" "authserver" "Port $auth_port not responding"
    fi

    # Check world server port
    if timeout 5 bash -c "</dev/tcp/localhost/$world_port" 2>/dev/null; then
        send_alert "OK" "worldserver" "Port $world_port responding"
    else
        send_alert "WARNING" "worldserver" "Port $world_port not responding"
    fi
}

# Generate HTML status page
generate_web_status() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    local uptime=$(uptime -p 2>/dev/null || echo "Unknown")

    cat > "$WEB_DIR/index.html" << EOF
<!DOCTYPE html>
<html>
<head>
    <title>AzerothCore Status</title>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta http-equiv="refresh" content="30">
    <style>
        body { font-family: Arial, sans-serif; margin: 20px; background: #f5f5f5; }
        .container { max-width: 1200px; margin: 0 auto; background: white; padding: 20px; border-radius: 8px; box-shadow: 0 2px 4px rgba(0,0,0,0.1); }
        .header { text-align: center; margin-bottom: 30px; }
        .status-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 20px; }
        .service-card { border: 1px solid #ddd; border-radius: 8px; padding: 15px; }
        .service-running { border-left: 4px solid #4CAF50; }
        .service-warning { border-left: 4px solid #FF9800; }
        .service-critical { border-left: 4px solid #F44336; }
        .service-missing { border-left: 4px solid #9E9E9E; }
        .metric { display: flex; justify-content: space-between; margin: 5px 0; }
        .timestamp { text-align: center; color: #666; margin-top: 20px; }
        table { width: 100%; border-collapse: collapse; margin: 10px 0; }
        th, td { border: 1px solid #ddd; padding: 8px; text-align: left; }
        th { background-color: #f2f2f2; }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🏰 AzerothCore Server Status</h1>
            <p>System Uptime: $uptime</p>
        </div>

        <div class="status-grid">
EOF

    # Add service status cards
    for service in "${!EXPECTED_SERVICES[@]}"; do
        local description="${EXPECTED_SERVICES[$service]}"
        local stats=$(get_container_stats "$service")
        local css_class="service-missing"
        local status_text="Not Running"

        if [[ "$stats" != "status=missing" ]]; then
            IFS=',' read -r status cpu_percent mem_percent mem_usage net_io block_io <<< "$stats"
            css_class="service-running"
            status_text="Running"

            # Check for warnings
            local cpu_num=$(echo "$cpu_percent" | sed 's/%//' | cut -d. -f1)
            local mem_num=$(echo "$mem_percent" | sed 's/%//' | cut -d. -f1)

            if [[ ${cpu_num:-0} -gt ${HEALTH_THRESHOLDS["cpu_warn"]} ]] || [[ ${mem_num:-0} -gt ${HEALTH_THRESHOLDS["memory_warn"]} ]]; then
                css_class="service-warning"
                status_text="Warning"
            fi
        fi

        cat >> "$WEB_DIR/index.html" << EOF
            <div class="service-card $css_class">
                <h3>$description</h3>
                <div class="metric"><strong>Service:</strong> <span>$service</span></div>
                <div class="metric"><strong>Status:</strong> <span>$status_text</span></div>
EOF

        if [[ "$stats" != "status=missing" ]]; then
            cat >> "$WEB_DIR/index.html" << EOF
                <div class="metric"><strong>CPU:</strong> <span>$cpu_percent</span></div>
                <div class="metric"><strong>Memory:</strong> <span>$mem_percent</span></div>
                <div class="metric"><strong>Memory Usage:</strong> <span>$mem_usage</span></div>
                <div class="metric"><strong>Network I/O:</strong> <span>$net_io</span></div>
EOF
        fi

        cat >> "$WEB_DIR/index.html" << EOF
            </div>
EOF
    done

    # Add recent alerts
    cat >> "$WEB_DIR/index.html" << EOF
        </div>

        <h2>Recent Alerts</h2>
        <table>
            <tr><th>Time</th><th>Level</th><th>Service</th><th>Message</th></tr>
EOF

    if [[ -f "$ALERT_LOG" ]]; then
        tail -10 "$ALERT_LOG" | while IFS= read -r line; do
            if [[ -n "$line" ]]; then
                # Parse log line: [timestamp] [level] service: message
                local timestamp=$(echo "$line" | sed -n 's/\[\([^]]*\)\].*/\1/p')
                local level=$(echo "$line" | sed -n 's/.*\[\([^]]*\)\] [^:]*:.*/\1/p')
                local service=$(echo "$line" | sed -n 's/.*\] \([^:]*\):.*/\1/p')
                local message=$(echo "$line" | sed -n 's/.*: \(.*\)/\1/p')

                cat >> "$WEB_DIR/index.html" << EOF
            <tr><td>$timestamp</td><td>$level</td><td>$service</td><td>$message</td></tr>
EOF
            fi
        done
    fi

    cat >> "$WEB_DIR/index.html" << EOF
        </table>

        <div class="timestamp">
            Last updated: $timestamp
        </div>
    </div>
</body>
</html>
EOF
}

# Main monitoring loop
main_monitor() {
    echo "Starting AzerothCore monitoring..."
    echo "Logs: $LOG_DIR"
    echo "Web status: $WEB_DIR/index.html"
    echo "Press Ctrl+C to stop"

    while true; do
        echo -e "\n$(date '+%Y-%m-%d %H:%M:%S') - Running health checks..."

        # Check each service
        for service in "${!EXPECTED_SERVICES[@]}"; do
            check_service_health "$service"
        done

        # Additional health checks
        check_database_health
        check_game_ports

        # Generate web status
        generate_web_status

        # System resource check
        local disk_usage=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
        if [[ ${disk_usage:-0} -gt ${HEALTH_THRESHOLDS["disk_critical"]} ]]; then
            send_alert "CRITICAL" "system" "Disk usage critical: ${disk_usage}%"
        elif [[ ${disk_usage:-0} -gt ${HEALTH_THRESHOLDS["disk_warn"]} ]]; then
            send_alert "WARNING" "system" "Disk usage high: ${disk_usage}%"
        fi

        sleep 30
    done
}

# Command handling
case "${1:-monitor}" in
    "monitor")
        main_monitor
        ;;
    "status")
        generate_web_status
        echo "Status page generated: $WEB_DIR/index.html"
        ;;
    "alerts")
        if [[ -f "$ALERT_LOG" ]]; then
            tail -n 20 "$ALERT_LOG"
        else
            echo "No alerts found"
        fi
        ;;
    "metrics")
        if [[ -f "$METRICS_LOG" ]]; then
            tail -n 20 "$METRICS_LOG"
        else
            echo "No metrics found"
        fi
        ;;
    *)
        echo "Usage: $0 [monitor|status|alerts|metrics]"
        exit 1
        ;;
esac