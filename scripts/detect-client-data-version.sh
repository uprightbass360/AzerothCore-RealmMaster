#!/usr/bin/env bash
#
# Detect which wowgaming/client-data release an AzerothCore checkout expects.
# Currently inspects apps/installer/includes/functions.sh for the
# inst_download_client_data version marker, but can be extended with new
# heuristics if needed.

set -euo pipefail

print_usage() {
  cat <<'EOF'
Usage: scripts/detect-client-data-version.sh [--no-header] <repo-path> [...]

Outputs a tab-separated list of repository path, raw version token found in the
source tree, and a normalized CLIENT_DATA_VERSION (e.g., v18).
EOF
}

if [[ "${1:-}" == "--help" ]]; then
  print_usage
  exit 0
fi

show_header=1
if [[ "${1:-}" == "--no-header" ]]; then
  show_header=0
  shift
fi

if [[ $# -lt 1 ]]; then
  print_usage >&2
  exit 1
fi

normalize_version() {
  local token="$1"
  token="${token//$'\r'/}"
  token="${token//\"/}"
  token="${token//\'/}"
  token="${token// /}"
  token="${token%%#*}"
  token="${token%%;*}"
  token="${token%%\)*}"
  token="${token%%\}*}"
  echo "$token"
}

detect_from_installer() {
  local repo_path="$1"
  local installer_file="$repo_path/apps/installer/includes/functions.sh"
  [[ -f "$installer_file" ]] || return 1
  local raw
  raw="$(grep -E 'local[[:space:]]+VERSION=' "$installer_file" | head -n1 | cut -d'=' -f2-)"
  [[ -n "$raw" ]] || return 1
  echo "$raw"
}

detect_version() {
  local repo_path="$1"
  if [[ ! -d "$repo_path" ]]; then
    printf '%s\t%s\t%s\n' "$repo_path" "<missing>" "<unknown>"
    return
  fi

  local raw=""
  if raw="$(detect_from_installer "$repo_path")"; then
    :
  elif [[ -f "$repo_path/.env" ]]; then
    raw="$(grep -E '^CLIENT_DATA_VERSION=' "$repo_path/.env" | head -n1 | cut -d'=' -f2-)"
  fi

  if [[ -z "$raw" ]]; then
    printf '%s\t%s\t%s\n' "$repo_path" "<unknown>" "<unknown>"
    return
  fi

  local normalized
  normalized="$(normalize_version "$raw")"
  printf '%s\t%s\t%s\n' "$repo_path" "$raw" "$normalized"
}

[[ "$show_header" -eq 0 ]] || printf 'repo\traw\tclient_data_version\n'
for repo in "$@"; do
  detect_version "$repo"
done
