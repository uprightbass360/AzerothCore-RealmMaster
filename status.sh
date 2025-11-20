#!/bin/bash
# Wrapper that ensures the statusdash TUI is built before running.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR"
BINARY_PATH="$PROJECT_DIR/statusdash"
SOURCE_DIR="$PROJECT_DIR/scripts/go"
CACHE_DIR="$PROJECT_DIR/.gocache"

usage() {
  cat <<EOF
statusdash wrapper

Usage: $0 [options] [-- statusdash-args]

Options:
  --rebuild         Force rebuilding the statusdash binary
  -h, --help        Show this help text

All arguments after '--' are passed directly to the statusdash binary.
Go must be installed locally to build statusdash (https://go.dev/doc/install).
EOF
}

force_rebuild=0
statusdash_args=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --rebuild)
      force_rebuild=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      statusdash_args+=("$@")
      break
      ;;
    *)
      statusdash_args+=("$1")
      shift
      ;;
  esac
done

ensure_go() {
  if ! command -v go >/dev/null 2>&1; then
    cat >&2 <<'ERR'
Go toolchain not found.
statusdash requires Go to build. Install Go from https://go.dev/doc/install and retry.
ERR
    exit 1
  fi
}

build_statusdash() {
  ensure_go
  mkdir -p "$CACHE_DIR"
  echo "Building statusdash..."
  (
    cd "$SOURCE_DIR"
    GOCACHE="$CACHE_DIR" go build -o "$BINARY_PATH" .
  )
}

if [[ $force_rebuild -eq 1 ]]; then
  rm -f "$BINARY_PATH"
fi

if [[ ! -x "$BINARY_PATH" ]]; then
  build_statusdash
fi

exec "$BINARY_PATH" "${statusdash_args[@]}"
