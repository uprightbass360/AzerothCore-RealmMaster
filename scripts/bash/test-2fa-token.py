#!/usr/bin/env python3
"""
Test TOTP token generation for AzerothCore 2FA
"""

import base64
import hmac
import hashlib
import struct
import time
import argparse

def generate_totp(secret, timestamp=None, interval=30):
    """Generate TOTP token from Base32 secret"""
    if timestamp is None:
        timestamp = int(time.time())

    # Calculate time counter
    counter = timestamp // interval

    # Decode Base32 secret
    # Add padding if needed
    secret = secret.upper()
    missing_padding = len(secret) % 8
    if missing_padding:
        secret += '=' * (8 - missing_padding)

    key = base64.b32decode(secret)

    # Pack counter as big-endian 8-byte integer
    counter_bytes = struct.pack('>Q', counter)

    # Generate HMAC-SHA1 hash
    hmac_hash = hmac.new(key, counter_bytes, hashlib.sha1).digest()

    # Dynamic truncation
    offset = hmac_hash[-1] & 0xf
    code = struct.unpack('>I', hmac_hash[offset:offset + 4])[0]
    code &= 0x7fffffff
    code %= 1000000

    return f"{code:06d}"

def main():
    parser = argparse.ArgumentParser(description="Generate TOTP tokens for testing")
    parser.add_argument('-s', '--secret', required=True, help='Base32 secret')
    parser.add_argument('-t', '--time', type=int, help='Unix timestamp (default: current time)')
    parser.add_argument('-c', '--count', type=int, default=1, help='Number of tokens to generate')

    args = parser.parse_args()

    timestamp = args.time or int(time.time())

    print(f"Secret: {args.secret}")
    print(f"Timestamp: {timestamp} ({time.ctime(timestamp)})")
    print(f"Interval: 30 seconds")
    print()

    for i in range(args.count):
        current_time = timestamp + (i * 30)
        token = generate_totp(args.secret, current_time)
        print(f"Time: {time.ctime(current_time)} | Token: {token}")

if __name__ == "__main__":
    main()