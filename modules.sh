#!/bin/bash
# Add, list and remove user-defined modules (config/module-manifest.local.json).
# See docs/ADDING_MODULES.md.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/bash/lib/run-log.sh
source "$ROOT_DIR/scripts/bash/lib/run-log.sh"
run_log_start modules -- "$@"; set -- "${RUN_LOG_ARGS[@]}"
python3 "$ROOT_DIR/scripts/python/local_modules.py" --root "$ROOT_DIR" "$@"
