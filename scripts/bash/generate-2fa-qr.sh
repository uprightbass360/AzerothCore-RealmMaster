#!/bin/bash

# AzerothCore 2FA QR Code Generator
# Generates TOTP secrets and QR codes for AzerothCore accounts

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to display usage
show_usage() {
    echo "Usage: $0 -u USERNAME [-o OUTPUT_PATH] [-s SECRET] [-i ISSUER]"
    echo ""
    echo "Options:"
    echo "  -u USERNAME     Target username for 2FA setup (required)"
    echo "  -o OUTPUT_PATH  Path to save QR code image (default: ./USERNAME_2fa_qr.png)"
    echo "  -s SECRET       Use existing 16-character Base32 secret (generates random if not provided)"
    echo "  -i ISSUER       Issuer name for the TOTP entry (default: AzerothCore)"
    echo "  -h              Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 -u john_doe"
    echo "  $0 -u john_doe -o /tmp/qr.png"
    echo "  $0 -u john_doe -s JBSWY3DPEHPK3PXP -i MyServer"
}

# Function to validate Base32
validate_base32() {
    local secret="$1"
    if [[ ! "$secret" =~ ^[A-Z2-7]+$ ]]; then
        echo -e "${RED}Error: Invalid Base32 secret. Only A-Z and 2-7 characters allowed.${NC}" >&2
        return 1
    fi
    if [ ${#secret} -ne 16 ]; then
        echo -e "${RED}Error: AzerothCore SOAP requires a 16-character Base32 secret (got ${#secret}).${NC}" >&2
        return 1
    fi
}

# Function to generate Base32 secret
generate_secret() {
    # Generate 10 random bytes and encode as 16-character Base32 (AzerothCore SOAP requirement)
    if command -v base32 >/dev/null 2>&1; then
        openssl rand 10 | base32 -w0 | head -c16
    else
        # Fallback using Python if base32 command not available
        python3 -c "
import base64
import os
secret_bytes = os.urandom(10)
secret_b32 = base64.b32encode(secret_bytes).decode('ascii').rstrip('=')
print(secret_b32[:16])
"
    fi
}

# Default values
USERNAME=""
OUTPUT_PATH=""
SECRET=""
ISSUER="AzerothCore"

# Parse command line arguments
while getopts "u:o:s:i:h" opt; do
    case ${opt} in
        u )
            USERNAME="$OPTARG"
            ;;
        o )
            OUTPUT_PATH="$OPTARG"
            ;;
        s )
            SECRET="$OPTARG"
            ;;
        i )
            ISSUER="$OPTARG"
            ;;
        h )
            show_usage
            exit 0
            ;;
        \? )
            echo -e "${RED}Invalid option: $OPTARG${NC}" 1>&2
            show_usage
            exit 1
            ;;
        : )
            echo -e "${RED}Invalid option: $OPTARG requires an argument${NC}" 1>&2
            show_usage
            exit 1
            ;;
    esac
done

# Validate required parameters
if [ -z "$USERNAME" ]; then
    echo -e "${RED}Error: Username is required.${NC}" >&2
    show_usage
    exit 1
fi

# Set default output path if not provided
if [ -z "$OUTPUT_PATH" ]; then
    OUTPUT_PATH="./${USERNAME}_2fa_qr.png"
fi

# Generate secret if not provided
if [ -z "$SECRET" ]; then
    echo -e "${BLUE}Generating new TOTP secret...${NC}"
    SECRET=$(generate_secret)
    if [ -z "$SECRET" ]; then
        echo -e "${RED}Error: Failed to generate secret.${NC}" >&2
        exit 1
    fi
    echo -e "${GREEN}Generated secret: $SECRET${NC}"
else
    echo -e "${BLUE}Using provided secret...${NC}"
    if ! validate_base32 "$SECRET"; then
        exit 1
    fi
fi

# Create TOTP URI
URI="otpauth://totp/${ISSUER}:${USERNAME}?secret=${SECRET}&issuer=${ISSUER}"

# Check if qrencode is available
if ! command -v qrencode >/dev/null 2>&1; then
    echo -e "${RED}Error: qrencode is not installed.${NC}" >&2
    echo "Install it with: sudo apt-get install qrencode (Ubuntu/Debian) or brew install qrencode (macOS)"
    echo ""
    echo -e "${BLUE}Manual setup information:${NC}"
    echo "Secret: $SECRET"
    echo "URI: $URI"
    exit 1
fi

# Generate QR code
echo -e "${BLUE}Generating QR code...${NC}"
if echo "$URI" | qrencode -s 6 -o "$OUTPUT_PATH"; then
    echo -e "${GREEN}✓ QR code generated successfully: $OUTPUT_PATH${NC}"
else
    echo -e "${RED}Error: Failed to generate QR code.${NC}" >&2
    exit 1
fi

# Display setup information
echo ""
echo -e "${YELLOW}=== AzerothCore 2FA Setup Information ===${NC}"
echo "Username: $USERNAME"
echo "Secret: $SECRET"
echo "QR Code: $OUTPUT_PATH"
echo "Issuer: $ISSUER"
echo ""
echo -e "${BLUE}Next steps:${NC}"
echo "1. Share the QR code image with the user"
echo "2. User scans QR code with authenticator app"
echo "3. Run on AzerothCore console:"
echo -e "   ${GREEN}account set 2fa $USERNAME $SECRET${NC}"
echo "4. User can now use 6-digit codes for login"
echo ""
echo -e "${YELLOW}Security Note: Keep the secret secure and delete the QR code after setup.${NC}"
