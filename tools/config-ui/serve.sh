#!/bin/bash
# Local mode for the config UI: regenerate config/index.json (gitignored)
# and serve the repo checkout so the page reads live working-copy data.
set -e
cd "$(dirname "$0")/../.."
python3 tools/config-ui/gen_index.py config
echo "Open: http://localhost:8321/tools/config-ui/"
exec python3 -m http.server 8321
