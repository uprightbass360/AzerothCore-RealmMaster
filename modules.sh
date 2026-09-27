#!/bin/bash
# Add, list and remove user-defined modules (config/module-manifest.local.json).
# See docs/ADDING_MODULES.md.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$ROOT_DIR/scripts/python/local_modules.py" --root "$ROOT_DIR" "$@"
