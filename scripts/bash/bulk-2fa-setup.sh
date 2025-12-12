#!/bin/bash
#
# AzerothCore Bulk 2FA Setup Script
# Generates and configures TOTP 2FA for multiple accounts
#
# Usage: ./scripts/bash/bulk-2fa-setup.sh [OPTIONS]
#

set -e

# Script directory for relative imports
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Source common utilities
source "$SCRIPT_DIR/lib/common.sh"

# Set environment paths
ENV_PATH="${ENV_PATH:-$PROJECT_ROOT/.env}"
DEFAULT_ENV_PATH="$PROJECT_ROOT/.env"

# =============================================================================
# GLOBAL VARIABLES
# =============================================================================

# Command line options
OPT_ALL=false
OPT_ACCOUNTS=()
OPT_FORCE=false
OPT_OUTPUT_DIR=""
OPT_DRY_RUN=false
OPT_ISSUER="AzerothCore"
OPT_FORMAT="qr"

# Container and database settings
WORLDSERVER_CONTAINER="ac-worldserver"
DATABASE_CONTAINER="ac-mysql"
MYSQL_PASSWORD=""

# SOAP settings for official AzerothCore API
SOAP_HOST="localhost"
SOAP_PORT="7778"
SOAP_USERNAME=""
SOAP_PASSWORD=""

# Output paths
OUTPUT_BASE_DIR=""
QR_CODES_DIR=""
SETUP_REPORT=""
CONSOLE_COMMANDS=""
SECRETS_BACKUP=""

# =============================================================================
# USAGE AND HELP
# =============================================================================

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Bulk 2FA setup for AzerothCore accounts using official SOAP API"
    echo ""
    echo "Options:"
    echo "  --all                    Process all non-bot accounts without 2FA"
    echo "  --account USERNAME       Process specific account (can be repeated)"
    echo "  --force                  Regenerate 2FA even if already exists"
    echo "  --output-dir PATH        Custom output directory"
    echo "  --dry-run                Show what would be done without executing"
    echo "  --issuer NAME            Issuer name for TOTP (default: AzerothCore)"
    echo "  --format [qr|manual]     Output QR codes or manual setup info"
    echo "  --soap-user USERNAME     SOAP API username (required)"
    echo "  --soap-pass PASSWORD     SOAP API password (required)"
    echo "  -h, --help               Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 --all                               # Setup 2FA for all accounts"
    echo "  $0 --account user1 --account user2     # Setup for specific accounts"
    echo "  $0 --all --force --issuer MyServer     # Force regenerate with custom issuer"
    echo "  $0 --all --dry-run                     # Preview what would be done"
    echo ""
    echo "Requirements:"
    echo "  - AzerothCore worldserver with SOAP enabled on port 7778"
    echo "  - GM account with sufficient privileges for SOAP access"
    echo "  - Remote Access (Ra.Enable = 1) enabled in worldserver.conf"
}

# =============================================================================
# UTILITY FUNCTIONS
# =============================================================================

# Check if required containers are running and healthy
check_containers() {
    info "Checking container status..."

    # Check worldserver container
    if ! docker ps --format '{{.Names}}' | grep -q "^${WORLDSERVER_CONTAINER}$"; then
        fatal "Container $WORLDSERVER_CONTAINER is not running"
    fi

    # Check if database container exists
    if ! docker ps --format '{{.Names}}' | grep -q "^${DATABASE_CONTAINER}$"; then
        fatal "Container $DATABASE_CONTAINER is not running"
    fi

    # Test database connectivity
    if ! docker exec "$WORLDSERVER_CONTAINER" mysql -h "$DATABASE_CONTAINER" -u root -p"$MYSQL_PASSWORD" acore_auth -e "SELECT 1;" &>/dev/null; then
        fatal "Cannot connect to AzerothCore database"
    fi

    # Test SOAP connectivity (only if credentials are available)
    if [ -n "$SOAP_USERNAME" ] && [ -n "$SOAP_PASSWORD" ]; then
        info "Testing SOAP API connectivity..."
        if ! soap_result=$(soap_execute_command "server info"); then
            fatal "Cannot connect to SOAP API: $soap_result"
        fi
        ok "SOAP API is accessible"
    fi

    ok "Containers are healthy and accessible"
}

# Execute MySQL query via container
mysql_query() {
    local query="$1"
    local database="${2:-acore_auth}"

    docker exec "$WORLDSERVER_CONTAINER" mysql \
        -h "$DATABASE_CONTAINER" \
        -u root \
        -p"$MYSQL_PASSWORD" \
        "$database" \
        -e "$query" \
        2>/dev/null
}

# Execute SOAP command via AzerothCore official API
soap_execute_command() {
    local command="$1"
    local response

    # Construct SOAP XML request
    local soap_request='<?xml version="1.0" encoding="UTF-8"?>
<SOAP-ENV:Envelope
  xmlns:SOAP-ENV="http://schemas.xmlsoap.org/soap/envelope/"
  xmlns:SOAP-ENC="http://schemas.xmlsoap.org/soap/encoding/"
  xmlns:xsi="http://www.w3.org/1999/XMLSchema-instance"
  xmlns:xsd="http://www.w3.org/1999/XMLSchema"
  xmlns:ns1="urn:AC">
  <SOAP-ENV:Body>
    <ns1:executeCommand>
      <command>'"$command"'</command>
    </ns1:executeCommand>
  </SOAP-ENV:Body>
</SOAP-ENV:Envelope>'

    # Execute SOAP request
    response=$(curl -s -X POST \
        -H "Content-Type: text/xml" \
        --user "$SOAP_USERNAME:$SOAP_PASSWORD" \
        -d "$soap_request" \
        "http://$SOAP_HOST:$SOAP_PORT/" 2>/dev/null)

    # Flatten response for reliable parsing
    local flat_response
    flat_response=$(echo "$response" | tr -d '\n' | sed 's/\r//g')

    # Check if response contains fault
    if echo "$flat_response" | grep -q "SOAP-ENV:Fault"; then
        # Extract fault string for error reporting
        echo "$flat_response" | sed -n 's/.*<faultstring>\(.*\)<\/faultstring>.*/\1/p' | sed 's/&#xD;//g'
        return 1
    fi

    # Extract successful result
    echo "$flat_response" | sed -n 's/.*<result>\(.*\)<\/result>.*/\1/p' | sed 's/&#xD;//g'
    return 0
}

# Generate Base32 TOTP secret
generate_totp_secret() {
    # Use existing generation logic from generate-2fa-qr.sh
    if command -v base32 >/dev/null 2>&1; then
        openssl rand 10 | base32 -w0 | head -c16
    else
        # Fallback using Python
        python3 -c "
import base64
import os
secret_bytes = os.urandom(10)
secret_b32 = base64.b32encode(secret_bytes).decode('ascii').rstrip('=')
print(secret_b32[:16])
"
    fi
}

# Validate Base32 secret format
validate_base32_secret() {
    local secret="$1"
    if [[ ! "$secret" =~ ^[A-Z2-7]+$ ]]; then
        return 1
    fi
    if [ ${#secret} -ne 16 ]; then
        err "AzerothCore SOAP requires a 16-character Base32 secret (got ${#secret})"
        return 1
    fi
    return 0
}

# =============================================================================
# ACCOUNT DISCOVERY FUNCTIONS
# =============================================================================

# Get all accounts that need 2FA setup
get_accounts_needing_2fa() {
    local force="$1"
    local query

    if [ "$force" = "true" ]; then
        # Include accounts that already have 2FA when force is enabled
        query="SELECT username FROM account
               WHERE username NOT LIKE 'rndbot%'
               AND username NOT LIKE 'playerbot%'
               ORDER BY username;"
    else
        # Only accounts without 2FA
        query="SELECT username FROM account
               WHERE (totp_secret IS NULL OR totp_secret = '')
               AND username NOT LIKE 'rndbot%'
               AND username NOT LIKE 'playerbot%'
               ORDER BY username;"
    fi

    mysql_query "$query" | tail -n +2  # Remove header row
}

# Check if specific account exists
account_exists() {
    local username="$1"
    local result

    result=$(mysql_query "SELECT COUNT(*) FROM account WHERE username = '$username';" | tail -n +2)
    [ "$result" -eq 1 ]
}

# Check if account already has 2FA
account_has_2fa() {
    local username="$1"
    local result

    result=$(mysql_query "SELECT COUNT(*) FROM account WHERE username = '$username' AND totp_secret IS NOT NULL AND totp_secret != '';" | tail -n +2)
    [ "$result" -eq 1 ]
}

# =============================================================================
# 2FA SETUP FUNCTIONS
# =============================================================================

# Generate and set up 2FA for a single account
setup_2fa_for_account() {
    local username="$1"
    local force="$2"
    local secret=""
    local qr_output=""

    info "Processing account: $username"

    # Check if account exists
    if ! account_exists "$username"; then
        err "Account '$username' does not exist, skipping"
        return 1
    fi

    # Check if account already has 2FA
    if account_has_2fa "$username" && [ "$force" != "true" ]; then
        warn "Account '$username' already has 2FA configured, use --force to regenerate"
        return 0
    fi

    # Generate TOTP secret
    secret=$(generate_totp_secret)
    if [ -z "$secret" ] || ! validate_base32_secret "$secret"; then
        err "Failed to generate valid TOTP secret for $username"
        return 1
    fi

    if [ "$OPT_DRY_RUN" = "true" ]; then
        log "DRY RUN: Would set 2FA secret for $username: $secret"
        return 0
    fi

    # Set 2FA using official AzerothCore SOAP API
    local soap_result
    if ! soap_result=$(soap_execute_command ".account set 2fa $username $secret"); then
        err "Failed to set 2FA for $username via SOAP API: $soap_result"
        return 1
    fi

    # Verify success message
    if ! echo "$soap_result" | grep -q "Successfully enabled two-factor authentication"; then
        err "Unexpected SOAP response for $username: $soap_result"
        return 1
    fi

    # Generate QR code if format is 'qr'
    if [ "$OPT_FORMAT" = "qr" ]; then
        qr_output="$QR_CODES_DIR/${username}_2fa_qr.png"

        if ! "$SCRIPT_DIR/generate-2fa-qr.sh" -u "$username" -s "$secret" -i "$OPT_ISSUER" -o "$qr_output" >/dev/null; then
            warn "Failed to generate QR code for $username, but secret was saved"
        fi
    fi

    # Log setup information
    echo "$username,$secret,$(date -u +"%Y-%m-%d %H:%M:%S UTC")" >> "$SECRETS_BACKUP"
    echo "account set 2fa $username $secret" >> "$CONSOLE_COMMANDS"

    ok "2FA configured for account: $username"
    return 0
}

# =============================================================================
# OUTPUT AND REPORTING FUNCTIONS
# =============================================================================

# Create output directory structure
create_output_structure() {
    local timestamp
    timestamp=$(date +"%Y%m%d%H%M%S")

    if [ -n "$OPT_OUTPUT_DIR" ]; then
        OUTPUT_BASE_DIR="$OPT_OUTPUT_DIR"
    else
        OUTPUT_BASE_DIR="$PROJECT_ROOT/2fa-setup-$timestamp"
    fi

    # Create directories
    mkdir -p "$OUTPUT_BASE_DIR"
    QR_CODES_DIR="$OUTPUT_BASE_DIR/qr-codes"
    mkdir -p "$QR_CODES_DIR"

    # Set up output files
    SETUP_REPORT="$OUTPUT_BASE_DIR/setup-report.txt"
    CONSOLE_COMMANDS="$OUTPUT_BASE_DIR/console-commands.txt"
    SECRETS_BACKUP="$OUTPUT_BASE_DIR/secrets-backup.csv"

    # Initialize files
    echo "# AzerothCore 2FA Console Commands" > "$CONSOLE_COMMANDS"
    echo "# Generated on $(date)" >> "$CONSOLE_COMMANDS"
    echo "" >> "$CONSOLE_COMMANDS"

    echo "username,secret,generated_date" > "$SECRETS_BACKUP"

    info "Output directory: $OUTPUT_BASE_DIR"
}

# Generate final setup report
generate_setup_report() {
    local total_processed="$1"
    local successful="$2"
    local failed="$3"

    {
        echo "AzerothCore Bulk 2FA Setup Report"
        echo "================================="
        echo ""
        echo "Generated: $(date)"
        echo "Command: $0 $*"
        echo ""
        echo "Summary:"
        echo "--------"
        echo "Total accounts processed: $total_processed"
        echo "Successfully configured: $successful"
        echo "Failed: $failed"
        echo ""
        echo "Output Files:"
        echo "-------------"
        echo "- QR Codes: $QR_CODES_DIR/"
        echo "- Console Commands: $CONSOLE_COMMANDS"
        echo "- Secrets Backup: $SECRETS_BACKUP"
        echo ""
        echo "Next Steps:"
        echo "-----------"
        echo "1. Distribute QR codes to users securely"
        echo "2. Users scan QR codes with authenticator apps"
        echo "3. Verify setup using console commands if needed"
        echo "4. Store secrets backup securely and delete when no longer needed"
        echo ""
        echo "Security Notes:"
        echo "--------------"
        echo "- QR codes contain sensitive TOTP secrets"
        echo "- Secrets backup file contains plaintext secrets"
        echo "- Delete or encrypt these files after distribution"
        echo "- Secrets are also stored in AzerothCore database"
    } > "$SETUP_REPORT"

    info "Setup report generated: $SETUP_REPORT"
}

# =============================================================================
# MAIN SCRIPT LOGIC
# =============================================================================

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --all)
                OPT_ALL=true
                shift
                ;;
            --account)
                if [ -z "$2" ]; then
                    fatal "Option --account requires a username argument"
                fi
                OPT_ACCOUNTS+=("$2")
                shift 2
                ;;
            --force)
                OPT_FORCE=true
                shift
                ;;
            --output-dir)
                if [ -z "$2" ]; then
                    fatal "Option --output-dir requires a path argument"
                fi
                OPT_OUTPUT_DIR="$2"
                shift 2
                ;;
            --dry-run)
                OPT_DRY_RUN=true
                shift
                ;;
            --issuer)
                if [ -z "$2" ]; then
                    fatal "Option --issuer requires a name argument"
                fi
                OPT_ISSUER="$2"
                shift 2
                ;;
            --format)
                if [ -z "$2" ]; then
                    fatal "Option --format requires qr or manual"
                fi
                if [[ "$2" != "qr" && "$2" != "manual" ]]; then
                    fatal "Format must be 'qr' or 'manual'"
                fi
                OPT_FORMAT="$2"
                shift 2
                ;;
            --soap-user)
                if [ -z "$2" ]; then
                    fatal "Option --soap-user requires a username argument"
                fi
                SOAP_USERNAME="$2"
                shift 2
                ;;
            --soap-pass)
                if [ -z "$2" ]; then
                    fatal "Option --soap-pass requires a password argument"
                fi
                SOAP_PASSWORD="$2"
                shift 2
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                fatal "Unknown option: $1"
                ;;
        esac
    done
}

# Main execution function
main() {
    local accounts_to_process=()
    local total_processed=0
    local successful=0
    local failed=0

    # Parse arguments
    parse_arguments "$@"

    # Validate options
    if [ "$OPT_ALL" = "false" ] && [ ${#OPT_ACCOUNTS[@]} -eq 0 ]; then
        fatal "Must specify either --all or --account USERNAME"
    fi

    if [ "$OPT_ALL" = "true" ] && [ ${#OPT_ACCOUNTS[@]} -gt 0 ]; then
        fatal "Cannot use --all with specific --account options"
    fi

    # Load environment variables
    MYSQL_PASSWORD=$(read_env "MYSQL_ROOT_PASSWORD" "")
    if [ -z "$MYSQL_PASSWORD" ]; then
        fatal "MYSQL_ROOT_PASSWORD not found in environment"
    fi

    # Require SOAP credentials via CLI flags
    if [ -z "$SOAP_USERNAME" ] || [ -z "$SOAP_PASSWORD" ]; then
        fatal "SOAP credentials required. Provide --soap-user and --soap-pass."
    fi

    # Check container health
    check_containers

    # Create output structure
    create_output_structure

    # Determine accounts to process
    if [ "$OPT_ALL" = "true" ]; then
        info "Discovering accounts that need 2FA setup..."
        readarray -t accounts_to_process < <(get_accounts_needing_2fa "$OPT_FORCE")

        if [ ${#accounts_to_process[@]} -eq 0 ]; then
            if [ "$OPT_FORCE" = "true" ]; then
                warn "No accounts found in database"
            else
                ok "All accounts already have 2FA configured"
            fi
            exit 0
        fi

        info "Found ${#accounts_to_process[@]} accounts to process"
    else
        accounts_to_process=("${OPT_ACCOUNTS[@]}")
    fi

    # Display dry run information
    if [ "$OPT_DRY_RUN" = "true" ]; then
        warn "DRY RUN MODE - No changes will be made"
        info "Would process the following accounts:"
        for account in "${accounts_to_process[@]}"; do
            echo "  - $account"
        done
        echo ""
    fi

    # Process each account
    info "Processing ${#accounts_to_process[@]} accounts..."
    for account in "${accounts_to_process[@]}"; do
        total_processed=$((total_processed + 1))

        if setup_2fa_for_account "$account" "$OPT_FORCE"; then
            successful=$((successful + 1))
        else
            failed=$((failed + 1))
        fi
    done

    # Generate final report
    if [ "$OPT_DRY_RUN" = "false" ]; then
        generate_setup_report "$total_processed" "$successful" "$failed"

        # Summary
        echo ""
        ok "Bulk 2FA setup completed"
        info "Processed: $total_processed accounts"
        info "Successful: $successful"
        info "Failed: $failed"
        info "Output directory: $OUTPUT_BASE_DIR"

        if [ "$failed" -gt 0 ]; then
            warn "Some accounts failed to process. Check the output for details."
            exit 1
        fi
    else
        info "Dry run completed. Use without --dry-run to execute."

        if [ "$failed" -gt 0 ]; then
            warn "Some accounts would fail to process."
            exit 1
        fi
    fi
}

# Execute main function with all arguments
main "$@"
