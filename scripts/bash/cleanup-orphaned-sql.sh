#!/usr/bin/env bash
#
# cleanup-orphaned-sql.sh
#
# Cleans up orphaned SQL update entries from the database.
# These are entries in the 'updates' table that reference files no longer on disk.
#
# This happens when:
# - Modules are removed/uninstalled
# - Modules are updated and old SQL files are deleted
# - Manual SQL cleanup occurs
#
# NOTE: These warnings are informational and don't affect server operation.
# This script is optional - it just cleans up the logs.
#

set -euo pipefail

# Configuration
MYSQL_CONTAINER="${MYSQL_CONTAINER:-ac-mysql}"
WORLDSERVER_CONTAINER="${WORLDSERVER_CONTAINER:-ac-worldserver}"
MYSQL_USER="${MYSQL_USER:-root}"
MYSQL_PASSWORD="${MYSQL_ROOT_PASSWORD:-}"
DRY_RUN=false
VERBOSE=false
DATABASES=("acore_world" "acore_characters" "acore_auth")

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Usage
usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up orphaned SQL update entries from AzerothCore databases.

OPTIONS:
    -p, --password PASSWORD    MySQL root password (or use MYSQL_ROOT_PASSWORD env var)
    -c, --container NAME       MySQL container name (default: ac-mysql)
    -w, --worldserver NAME     Worldserver container name (default: ac-worldserver)
    -d, --database DB          Clean only specific database (world, characters, auth)
    -n, --dry-run             Show what would be cleaned without making changes
    -v, --verbose             Show detailed output
    -h, --help                Show this help message

EXAMPLES:
    # Dry run to see what would be cleaned
    $0 --dry-run

    # Clean all databases
    $0 --password yourpassword

    # Clean only world database
    $0 --password yourpassword --database world

    # Verbose output
    $0 --password yourpassword --verbose

NOTES:
    - This script only removes entries from the 'updates' table
    - It does NOT remove any actual data or tables
    - It does NOT reverse any SQL that was applied
    - This is safe to run and only cleans up tracking metadata
    - Orphaned entries occur when modules are removed/updated

EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--password)
            MYSQL_PASSWORD="$2"
            shift 2
            ;;
        -c|--container)
            MYSQL_CONTAINER="$2"
            shift 2
            ;;
        -w|--worldserver)
            WORLDSERVER_CONTAINER="$2"
            shift 2
            ;;
        -d|--database)
            case $2 in
                world) DATABASES=("acore_world") ;;
                characters) DATABASES=("acore_characters") ;;
                auth) DATABASES=("acore_auth") ;;
                *) echo -e "${RED}Error: Invalid database '$2'${NC}"; exit 1 ;;
            esac
            shift 2
            ;;
        -n|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option '$1'${NC}"
            usage
            ;;
    esac
done

# Check password
if [[ -z "$MYSQL_PASSWORD" ]]; then
    echo -e "${RED}Error: MySQL password required${NC}"
    echo "Use --password or set MYSQL_ROOT_PASSWORD environment variable"
    exit 1
fi

# Check containers exist
if ! docker ps --format '{{.Names}}' | grep -q "^${MYSQL_CONTAINER}$"; then
    echo -e "${RED}Error: MySQL container '$MYSQL_CONTAINER' not found or not running${NC}"
    exit 1
fi

if ! docker ps --format '{{.Names}}' | grep -q "^${WORLDSERVER_CONTAINER}$"; then
    echo -e "${RED}Error: Worldserver container '$WORLDSERVER_CONTAINER' not found or not running${NC}"
    exit 1
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  AzerothCore Orphaned SQL Cleanup                             ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
echo

if [[ "$DRY_RUN" == true ]]; then
    echo -e "${YELLOW}DRY RUN MODE - No changes will be made${NC}"
    echo
fi

# Function to get SQL files from worldserver container
get_sql_files() {
    local db_type=$1
    docker exec "$WORLDSERVER_CONTAINER" find "/azerothcore/data/sql/updates/${db_type}/" -name "*.sql" -type f 2>/dev/null | \
        xargs -I {} basename {} 2>/dev/null || true
}

# Function to clean orphaned entries
clean_orphaned_entries() {
    local database=$1
    local db_type=$2

    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}Processing: $database${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

    # Get list of SQL files on disk
    local sql_files
    sql_files=$(get_sql_files "$db_type")

    if [[ -z "$sql_files" ]]; then
        echo -e "${YELLOW}⚠ No SQL files found in /azerothcore/data/sql/updates/${db_type}/${NC}"
        echo
        return
    fi

    local file_count
    file_count=$(echo "$sql_files" | wc -l)
    echo -e "📁 Found ${file_count} SQL files on disk"

    # Get entries from updates table
    local total_updates
    total_updates=$(docker exec "$MYSQL_CONTAINER" mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$database" -sN \
        -e "SELECT COUNT(*) FROM updates" 2>/dev/null || echo "0")

    echo -e "📊 Total updates in database: ${total_updates}"

    if [[ "$total_updates" == "0" ]]; then
        echo -e "${YELLOW}⚠ No updates found in database${NC}"
        echo
        return
    fi

    # Find orphaned entries (in DB but not on disk)
    # We'll create a temp table with file names and do a LEFT JOIN
    local orphaned_count=0
    local orphaned_list=""

    # Get all update names from DB
    local db_updates
    db_updates=$(docker exec "$MYSQL_CONTAINER" mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$database" -sN \
        -e "SELECT name FROM updates ORDER BY name" 2>/dev/null || true)

    if [[ -n "$db_updates" ]]; then
        # Check each DB entry against disk files
        while IFS= read -r update_name; do
            if ! echo "$sql_files" | grep -qF "$update_name"; then
                ((orphaned_count++))
                if [[ "$VERBOSE" == true ]] || [[ "$DRY_RUN" == true ]]; then
                    orphaned_list="${orphaned_list}${update_name}\n"
                fi

                # Delete if not dry run
                if [[ "$DRY_RUN" == false ]]; then
                    docker exec "$MYSQL_CONTAINER" mysql -u"$MYSQL_USER" -p"$MYSQL_PASSWORD" "$database" -e \
                        "DELETE FROM updates WHERE name='${update_name}'" 2>/dev/null
                fi
            fi
        done <<< "$db_updates"
    fi

    # Report results
    if [[ $orphaned_count -gt 0 ]]; then
        echo -e "${YELLOW}🗑️  Orphaned entries: ${orphaned_count}${NC}"

        if [[ "$VERBOSE" == true ]] || [[ "$DRY_RUN" == true ]]; then
            echo
            echo -e "${YELLOW}Orphaned files:${NC}"
            echo -e "$orphaned_list" | head -20
            if [[ $orphaned_count -gt 20 ]]; then
                echo -e "${YELLOW}... and $((orphaned_count - 20)) more${NC}"
            fi
        fi

        if [[ "$DRY_RUN" == false ]]; then
            echo -e "${GREEN}✅ Cleaned ${orphaned_count} orphaned entries${NC}"
        else
            echo -e "${YELLOW}Would clean ${orphaned_count} orphaned entries${NC}"
        fi
    else
        echo -e "${GREEN}✅ No orphaned entries found${NC}"
    fi

    echo
}

# Process each database
for db in "${DATABASES[@]}"; do
    case $db in
        acore_world)
            clean_orphaned_entries "$db" "db_world"
            ;;
        acore_characters)
            clean_orphaned_entries "$db" "db_characters"
            ;;
        acore_auth)
            clean_orphaned_entries "$db" "db_auth"
            ;;
    esac
done

# Summary
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Cleanup Complete${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

if [[ "$DRY_RUN" == true ]]; then
    echo
    echo -e "${YELLOW}This was a dry run. To actually clean orphaned entries, run:${NC}"
    echo -e "${YELLOW}  $0 --password yourpassword${NC}"
fi
