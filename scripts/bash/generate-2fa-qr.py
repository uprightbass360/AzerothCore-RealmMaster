#!/usr/bin/env python3
"""
AzerothCore 2FA QR Code Generator (Python version)
Generates TOTP secrets and QR codes for AzerothCore accounts
"""

import argparse
import base64
import os
import sys
import re

def validate_base32(secret):
    """Validate Base32 secret format"""
    if not re.match(r'^[A-Z2-7]+$', secret):
        print("Error: Invalid Base32 secret. Only A-Z and 2-7 characters allowed.", file=sys.stderr)
        return False
    if len(secret) != 16:
        print(f"Error: AzerothCore SOAP requires a 16-character Base32 secret (got {len(secret)}).", file=sys.stderr)
        return False
    return True

def generate_secret():
    """Generate a random 16-character Base32 secret (AzerothCore SOAP requirement)"""
    secret_bytes = os.urandom(10)
    secret_b32 = base64.b32encode(secret_bytes).decode('ascii').rstrip('=')
    return secret_b32[:16]

def generate_qr_code(uri, output_path):
    """Generate QR code using available library"""
    try:
        import qrcode
        qr = qrcode.QRCode(
            version=1,
            error_correction=qrcode.constants.ERROR_CORRECT_L,
            box_size=6,
            border=4,
        )
        qr.add_data(uri)
        qr.make(fit=True)

        img = qr.make_image(fill_color="black", back_color="white")
        img.save(output_path)
        return True
    except ImportError:
        print("Error: qrcode library not installed.", file=sys.stderr)
        print("Install it with: pip3 install qrcode[pil]", file=sys.stderr)
        return False

def main():
    parser = argparse.ArgumentParser(
        description="Generate TOTP secrets and QR codes for AzerothCore 2FA",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s -u john_doe
  %(prog)s -u john_doe -o /tmp/qr.png
  %(prog)s -u john_doe -s JBSWY3DPEHPK3PXP -i MyServer
        """
    )

    parser.add_argument('-u', '--username', required=True,
                       help='Target username for 2FA setup')
    parser.add_argument('-o', '--output',
                       help='Path to save QR code image (default: ./USERNAME_2fa_qr.png)')
    parser.add_argument('-s', '--secret',
                       help='Use existing 16-character Base32 secret (generates random if not provided)')
    parser.add_argument('-i', '--issuer', default='AzerothCore',
                       help='Issuer name for the TOTP entry (default: AzerothCore)')

    args = parser.parse_args()

    # Set default output path
    if not args.output:
        args.output = f"./{args.username}_2fa_qr.png"

    # Generate or validate secret
    if args.secret:
        print("Using provided secret...")
        if not validate_base32(args.secret):
            sys.exit(1)
        secret = args.secret
    else:
        print("Generating new TOTP secret...")
        secret = generate_secret()
        print(f"Generated secret: {secret}")

    # Create TOTP URI
    uri = f"otpauth://totp/{args.issuer}:{args.username}?secret={secret}&issuer={args.issuer}"

    # Generate QR code
    print("Generating QR code...")
    if generate_qr_code(uri, args.output):
        print(f"✓ QR code generated successfully: {args.output}")
    else:
        print("\nManual setup information:")
        print(f"Secret: {secret}")
        print(f"URI: {uri}")
        sys.exit(1)

    # Display setup information
    print("\n=== AzerothCore 2FA Setup Information ===")
    print(f"Username: {args.username}")
    print(f"Secret: {secret}")
    print(f"QR Code: {args.output}")
    print(f"Issuer: {args.issuer}")
    print("\nNext steps:")
    print("1. Share the QR code image with the user")
    print("2. User scans QR code with authenticator app")
    print("3. Run on AzerothCore console:")
    print(f"   account set 2fa {args.username} {secret}")
    print("4. User can now use 6-digit codes for login")
    print("\nSecurity Note: Keep the secret secure and delete the QR code after setup.")

if __name__ == "__main__":
    main()
