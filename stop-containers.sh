#!/bin/bash

# Thin wrapper to stop all AzerothCore project containers while preserving data.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "${SCRIPT_DIR}/cleanup.sh" --soft --force
