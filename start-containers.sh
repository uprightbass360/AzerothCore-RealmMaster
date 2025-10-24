#!/bin/bash

# Thin wrapper to bring the AzerothCore stack online without triggering rebuilds.
# Reuses deploy.sh so all profile detection and tagging logic stay consistent.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec "${SCRIPT_DIR}/deploy.sh" --skip-rebuild --yes --no-watch
