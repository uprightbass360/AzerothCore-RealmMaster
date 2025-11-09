#!/bin/bash

# Thin wrapper to stop all AzerothCore project containers while preserving data.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

exec "${PROJECT_ROOT}/cleanup.sh" --soft --force
