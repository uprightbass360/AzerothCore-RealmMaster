#!/bin/bash
# Dynamic changelog generator for AzerothCore source repositories and modules
# Uses existing project configuration to automatically detect and track changes
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$SCRIPT_DIR"
cd "$PROJECT_ROOT"

# Load environment configuration (available on deployed servers)
if [ -f ".env" ]; then
  set -a
  source .env
  set +a
fi

# Default configuration
LOCAL_STORAGE_ROOT="${STORAGE_PATH_LOCAL:-./local-storage}"
OUTPUT_DIR="${CHANGELOG_OUTPUT_DIR:-./changelogs}"
DAYS_BACK="${CHANGELOG_DAYS_BACK:-7}"
FORMAT="${CHANGELOG_FORMAT:-markdown}"

# Colors for output
GREEN='\033[0;32m'; BLUE='\033[0;34m'; YELLOW='\033[1;33m'; NC='\033[0m'
log() { echo -e "${BLUE}[$(date '+%H:%M:%S')]${NC} $*" >&2; }
success() { echo -e "${GREEN}✅${NC} $*" >&2; }
warn() { echo -e "${YELLOW}⚠️${NC} $*" >&2; }

usage() {
  cat <<EOF
Usage: $0 [options]

Generates changelog from all source repositories and modules configured in the project.

Options:
  -d, --days DAYS       Number of days to look back (default: $DAYS_BACK)
  -o, --output DIR      Output directory for file (default: console output)
  -f, --format FORMAT   Output format: markdown, json, text, summary (default: $FORMAT)
  --since DATE          Get changes since specific date (YYYY-MM-DD)
  --include-modules     Include module changes (default: auto-detect)
  --exclude-modules     Exclude module changes
  --main-only           Only main source repository
  --save                Save to file in output directory
  -v, --verbose         Verbose output
  -h, --help            Show this help

Examples:
  $0                              # Console output with auto build detection
  $0 --days 14                    # Last 2 weeks to console
  $0 --since 2024-11-01          # Since specific date to console
  $0 --save                       # Save to file in ./changelogs/
  $0 --save -o /tmp               # Save to file in /tmp/
  $0 --format json               # JSON output to console
  $0 --format summary            # Deploy summary (commit counts)
  $0 --main-only                 # Only core changes

The script automatically detects:
- Source repository variant (standard/playerbots)
- Enabled modules from project configuration
- Repository URLs and branches from environment
- Last build time from Docker image labels
EOF
}

# Parse arguments
INCLUDE_MODULES="auto"
MAIN_ONLY=false
VERBOSE=false
SINCE_DATE=""
SAVE_TO_FILE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -d|--days)
      DAYS_BACK="$2"; shift 2;;
    -o|--output)
      OUTPUT_DIR="$2"; shift 2;;
    -f|--format)
      FORMAT="$2"; shift 2;;
    --since)
      SINCE_DATE="$2"; shift 2;;
    --include-modules)
      INCLUDE_MODULES=true; shift;;
    --exclude-modules)
      INCLUDE_MODULES=false; shift;;
    --main-only)
      MAIN_ONLY=true; shift;;
    --save)
      SAVE_TO_FILE=true; shift;;
    -v|--verbose)
      VERBOSE=true; shift;;
    -h|--help)
      usage; exit 0;;
    *)
      echo "Unknown option: $1" >&2; exit 1;;
  esac
done

# Get last build time from container metadata
get_last_build_time() {
  local containers=("ac-worldserver" "ac-authserver")
  local images=()

  # Require COMPOSE_PROJECT_NAME to be set
  if [[ -z "${COMPOSE_PROJECT_NAME:-}" ]]; then
    warn "COMPOSE_PROJECT_NAME not set in environment"
    return 1
  fi

  # Use actual image names from environment
  # Detect variant to check appropriate images
  if [[ "${STACK_IMAGE_MODE:-standard}" == "playerbots" ]] || [[ "${MODULE_PLAYERBOTS:-0}" == "1" ]] || [[ "${PLAYERBOT_ENABLED:-0}" == "1" ]] || [[ "${STACK_SOURCE_VARIANT:-}" == "playerbots" ]]; then
    if [[ -z "${AC_WORLDSERVER_IMAGE_PLAYERBOTS:-}" ]] || [[ -z "${AC_AUTHSERVER_IMAGE_PLAYERBOTS:-}" ]]; then
      warn "Playerbots mode detected but AC_WORLDSERVER_IMAGE_PLAYERBOTS or AC_AUTHSERVER_IMAGE_PLAYERBOTS not set"
      return 1
    fi
    images=(
      "${AC_WORLDSERVER_IMAGE_PLAYERBOTS}"
      "${AC_AUTHSERVER_IMAGE_PLAYERBOTS}"
    )
  else
    if [[ -z "${AC_WORLDSERVER_IMAGE:-}" ]] || [[ -z "${AC_AUTHSERVER_IMAGE:-}" ]]; then
      warn "Standard mode detected but AC_WORLDSERVER_IMAGE or AC_AUTHSERVER_IMAGE not set"
      return 1
    fi
    images=(
      "${AC_WORLDSERVER_IMAGE}"
      "${AC_AUTHSERVER_IMAGE}"
    )
  fi

  local latest_date=""

  # Try to get build timestamp from containers and images
  local sources=()
  for container in "${containers[@]}"; do
    sources+=("container:$container")
  done
  for image in "${images[@]}"; do
    sources+=("image:$image")
  done

  for source in "${sources[@]}"; do
    local type="${source%%:*}"
    local name="${source#*:}"
    local build_date=""

    # Try build.source_date first, then build.timestamp as fallback
    build_date=$(docker inspect "$name" --format='{{index .Config.Labels "build.source_date"}}' 2>/dev/null || echo "")

    if [[ -z "$build_date" || "$build_date" == "unknown" ]]; then
      build_date=$(docker inspect "$name" --format='{{index .Config.Labels "build.timestamp"}}' 2>/dev/null || echo "")
    fi

    if [[ -n "$build_date" && "$build_date" != "unknown" ]]; then
      # Convert ISO date to YYYY-MM-DD format
      build_date=$(echo "$build_date" | cut -d'T' -f1)

      # Keep the latest date
      if [[ -z "$latest_date" ]] || [[ "$build_date" > "$latest_date" ]]; then
        latest_date="$build_date"
      fi
    fi
  done

  echo "$latest_date"
}

# Determine date range
if [[ -n "$SINCE_DATE" ]]; then
  SINCE_OPTION="--since=$SINCE_DATE"
  DATE_DESC="since $SINCE_DATE"
else
  # Try to use last build time as default
  LAST_BUILD_DATE=$(get_last_build_time 2>/dev/null) || LAST_BUILD_DATE=""

  if [[ -n "$LAST_BUILD_DATE" ]]; then
    SINCE_OPTION="--since=$LAST_BUILD_DATE"
    DATE_DESC="since last build ($LAST_BUILD_DATE)"
    $VERBOSE && log "Using last build date: $LAST_BUILD_DATE"
  else
    SINCE_OPTION="--since=$(date -d "$DAYS_BACK days ago" +%Y-%m-%d)"
    DATE_DESC="last $DAYS_BACK days (no build metadata found)"
    $VERBOSE && warn "No build metadata found in containers, falling back to $DAYS_BACK days"
  fi
fi

# Auto-detect source variant and configuration
detect_source_config() {
  local variant="core"

  # Check environment variables for playerbots mode
  if [[ "${MODULE_PLAYERBOTS:-0}" == "1" ]] || [[ "${PLAYERBOT_ENABLED:-0}" == "1" ]] || [[ "${STACK_SOURCE_VARIANT:-}" == "playerbots" ]]; then
    variant="playerbots"
  fi

  # Also check which source directory actually exists (resolve relative paths)
  local playerbots_path="$LOCAL_STORAGE_ROOT/source/azerothcore-playerbots"
  local standard_path="$LOCAL_STORAGE_ROOT/source/azerothcore"

  # Convert to absolute paths if needed
  if [[ "$playerbots_path" != /* ]]; then
    if [[ -d "$PROJECT_ROOT/$playerbots_path" ]]; then
      playerbots_path="$(realpath "$PROJECT_ROOT/$playerbots_path")"
    else
      playerbots_path="$PROJECT_ROOT/$playerbots_path"
    fi
  fi
  if [[ "$standard_path" != /* ]]; then
    if [[ -d "$PROJECT_ROOT/$standard_path" ]]; then
      standard_path="$(realpath "$PROJECT_ROOT/$standard_path")"
    else
      standard_path="$PROJECT_ROOT/$standard_path"
    fi
  fi

  $VERBOSE && log "Checking absolute paths: playerbots=$playerbots_path, standard=$standard_path" >&2
  $VERBOSE && log "Playerbots exists: $([[ -d "$playerbots_path/.git" ]] && echo "yes" || echo "no")" >&2
  $VERBOSE && log "Standard exists: $([[ -d "$standard_path/.git" ]] && echo "yes" || echo "no")" >&2

  if [[ "$variant" == "core" && -d "$playerbots_path/.git" && ! -d "$standard_path/.git" ]]; then
    variant="playerbots"
    $VERBOSE && log "Switched to playerbots variant" >&2
  fi

  # Repository URLs from environment (required)
  local standard_repo="${ACORE_REPO_STANDARD}"
  local standard_branch="${ACORE_BRANCH_STANDARD}"
  local playerbots_repo="${ACORE_REPO_PLAYERBOTS}"
  local playerbots_branch="${ACORE_BRANCH_PLAYERBOTS}"

  if [[ -z "$standard_repo" ]] || [[ -z "$standard_branch" ]] || [[ -z "$playerbots_repo" ]] || [[ -z "$playerbots_branch" ]]; then
    warn "Repository configuration missing from environment"
    warn "Required: ACORE_REPO_STANDARD, ACORE_BRANCH_STANDARD, ACORE_REPO_PLAYERBOTS, ACORE_BRANCH_PLAYERBOTS"
    return 1
  fi

  if [[ "$variant" == "playerbots" ]]; then
    echo "$playerbots_repo|$playerbots_branch|$LOCAL_STORAGE_ROOT/source/azerothcore-playerbots"
  else
    echo "$standard_repo|$standard_branch|$LOCAL_STORAGE_ROOT/source/azerothcore"
  fi
}

# Get enabled modules from project configuration
get_enabled_modules() {
  local modules_file="$LOCAL_STORAGE_ROOT/modules/.modules-meta/modules-enabled.txt"
  local modules_state="$LOCAL_STORAGE_ROOT/modules/.modules_state"

  if [[ -f "$modules_file" ]]; then
    cat "$modules_file" 2>/dev/null || true
  elif [[ -f "$modules_state" ]]; then
    # Parse modules state format: MODULE_NAME=1|MODULE_NAME2=0|...
    grep -o 'MODULE_[^=]*=1' "$modules_state" 2>/dev/null | sed 's/MODULE_//; s/=1//' | tr '[:upper:]' '[:lower:]' | sed 's/_/-/g' || true
  fi
}

# Get module repository info using existing module management
get_module_repos() {
  local python_helper="$PROJECT_ROOT/scripts/python/modules.py"

  if [[ -x "$python_helper" ]]; then
    # Use existing module helper if available
    python3 "$python_helper" list --format=repo 2>/dev/null || true
  else
    # Fallback: scan module directories for git repos
    find "$LOCAL_STORAGE_ROOT/modules" -name ".git" -type d 2>/dev/null | while read -r git_dir; do
      local module_dir="$(dirname "$git_dir")"
      local module_name="$(basename "$module_dir")"
      local repo_url=""

      if [[ -f "$git_dir/config" ]]; then
        repo_url=$(grep -A1 '\[remote "origin"\]' "$git_dir/config" 2>/dev/null | grep -E '^\s*url\s*=' | sed 's/.*url\s*=\s*//' | tr -d '\r\n' || true)
      fi

      if [[ -n "$repo_url" && -n "$module_name" ]]; then
        echo "$repo_url|master|$module_dir"
      fi
    done
  fi
}

# Format changelog entry based on output format
format_changelog() {
  local repo_name="$1"
  local repo_url="$2"
  local commit_count="$3"
  local commits="$4"

  case "$FORMAT" in
    json)
      cat <<EOF
  {
    "repository": "$repo_name",
    "url": "$repo_url",
    "commit_count": $commit_count,
    "commits": [
$(echo "$commits" | sed 's/^/      /; s/$/,/; $s/,$//')
    ]
  }
EOF
      ;;
    markdown)
      cat <<EOF

## $repo_name ($commit_count commits)
**Repository:** $repo_url

$commits
EOF
      ;;
    text)
      cat <<EOF

=== $repo_name ===
Repository: $repo_url
Commits: $commit_count

$commits
EOF
      ;;
  esac
}

# Get commits from a repository
get_repo_commits() {
  local repo_path="$1"
  local repo_name="$(basename "$repo_path")"

  if [[ ! -d "$repo_path/.git" ]]; then
    $VERBOSE && warn "No git repository found at $repo_path" >&2
    return
  fi

  # Handle git ownership issues on deployed servers
  local original_dir="$PWD"
  cd "$repo_path"

  # Ensure git can access this repository
  git config --global --add safe.directory "$repo_path" 2>/dev/null || true

  # Get remote URL
  local repo_url
  repo_url=$(git remote get-url origin 2>/dev/null || echo "local")

  # Get commits in the specified timeframe
  local commits
  commits=$(git log --oneline --no-merges $SINCE_OPTION 2>/dev/null | head -50 || echo "")

  cd "$original_dir"

  if [[ -z "$commits" ]]; then
    $VERBOSE && log "No commits found in $repo_name for $DATE_DESC" >&2
    return
  fi

  local commit_count=$(echo "$commits" | wc -l)
  $VERBOSE && log "Found $commit_count commits in $repo_name" >&2

  # For summary format, just return the count
  if [[ "$FORMAT" == "summary" ]]; then
    echo "$commit_count"
    return
  fi

  # Format commits based on output format
  local formatted_commits
  case "$FORMAT" in
    json)
      formatted_commits=$(echo "$commits" | sed 's/^\([^ ]*\) \(.*\)$/      {"hash": "\1", "message": "\2"}/')
      ;;
    markdown)
      formatted_commits=$(echo "$commits" | sed 's/^\([^ ]*\) \(.*\)$/- **\1**: \2/')
      ;;
    text)
      formatted_commits=$(echo "$commits" | sed 's/^/  /')
      ;;
  esac

  format_changelog "$repo_name" "$repo_url" "$commit_count" "$formatted_commits"
}

# Main execution
main() {
  $VERBOSE && log "Generating changelog for $DATE_DESC"

  # Determine output destination
  local output_file=""
  local use_stdout=true

  if [[ "$SAVE_TO_FILE" == "true" ]]; then
    use_stdout=false
    mkdir -p "$OUTPUT_DIR"
    local timestamp=$(date +"%Y%m%d_%H%M%S")
    output_file="$OUTPUT_DIR/changelog_${timestamp}.${FORMAT}"
  fi

  # Function to write output (either to file or stdout)
  write_output() {
    if [[ "$use_stdout" == "true" ]]; then
      echo "$1"
    else
      echo "$1" >> "$output_file"
    fi
  }

  # Start output
  case "$FORMAT" in
    json)
      if [[ "$use_stdout" == "false" ]]; then
        echo "{" > "$output_file"
      else
        echo "{"
      fi
      write_output "  \"generated\": \"$(date -Iseconds)\","
      write_output "  \"period\": \"$DATE_DESC\","
      write_output "  \"repositories\": ["
      ;;
    markdown)
      write_output "# AzerothCore Changelog"
      write_output ""
      write_output "**Generated:** $(date)"
      write_output "**Period:** $DATE_DESC"
      write_output ""
      ;;
    text)
      write_output "AzerothCore Changelog"
      write_output "Generated: $(date)"
      write_output "Period: $DATE_DESC"
      write_output "$(printf '=%.0s' {1..50})"
      ;;
    summary)
      # Summary format will be handled after collecting data
      ;;
  esac

  local first_repo=true

  # Collect all output in a variable first for console display
  local changelog_content=""
  local main_commits=0
  local module_commits=0
  local total_repos=0

  # Function to collect output
  collect_output() {
    changelog_content+="$1"$'\n'
  }

  # Main source repository
  if ! $MAIN_ONLY; then
    $VERBOSE && log "Processing main source repository..."
    local source_config
    source_config="$(detect_source_config)"
    $VERBOSE && log "Source config: $source_config" >&2
    IFS='|' read -r repo_url branch repo_path <<< "$source_config"

    local repo_output
    repo_output=$(get_repo_commits "$repo_path")
    if [[ -n "$repo_output" ]]; then
      if [[ "$FORMAT" == "summary" ]]; then
        main_commits="$repo_output"
        total_repos=$((total_repos + 1))
      else
        if [[ "$FORMAT" == "json" && ! $first_repo ]]; then
          collect_output ","
        fi
        collect_output "$repo_output"
        first_repo=false
      fi
    fi
  fi

  # Module repositories
  if [[ "$INCLUDE_MODULES" != "false" && ! $MAIN_ONLY ]]; then
    # Auto-detect if modules should be included
    if [[ "$INCLUDE_MODULES" == "auto" ]]; then
      local enabled_modules=$(get_enabled_modules)
      if [[ -n "$enabled_modules" ]]; then
        INCLUDE_MODULES=true
      else
        INCLUDE_MODULES=false
      fi
    fi

    if [[ "$INCLUDE_MODULES" == "true" ]]; then
      $VERBOSE && log "Processing module repositories..."

      while IFS='|' read -r repo_url branch repo_path; do
        [[ -z "$repo_path" ]] && continue

        local repo_output
        repo_output=$(get_repo_commits "$repo_path")
        if [[ -n "$repo_output" ]]; then
          if [[ "$FORMAT" == "summary" ]]; then
            module_commits=$((module_commits + repo_output))
            total_repos=$((total_repos + 1))
          else
            if [[ "$FORMAT" == "json" && ! $first_repo ]]; then
              collect_output ","
            fi
            collect_output "$repo_output"
            first_repo=false
          fi
        fi
      done < <(get_module_repos)
    fi
  fi

  # Handle different output formats
  case "$FORMAT" in
    summary)
      local total_commits=$((main_commits + module_commits))
      if [[ $total_commits -eq 0 ]]; then
        write_output "No changes since last build"
      else
        write_output "Changes since last build: ${total_commits} commits"
        if [[ $main_commits -gt 0 ]]; then
          write_output "  Core: ${main_commits} commits"
        fi
        if [[ $module_commits -gt 0 ]]; then
          write_output "  Modules: ${module_commits} commits"
        fi
        write_output "  Repositories: ${total_repos}"
      fi
      ;;
    *)
      # Output collected content (if any)
      if [[ -n "$changelog_content" ]]; then
        write_output "$changelog_content"
      fi

      # Close output
      case "$FORMAT" in
        json)
          write_output "  ]"
          write_output "}"
          ;;
      esac
      ;;
  esac

  # Show completion message
  if [[ "$use_stdout" == "false" ]]; then
    success "Changelog generated: $output_file"
    if $VERBOSE; then
      log "File size: $(du -h "$output_file" | cut -f1)"
    fi
  fi

  # Show summary if verbose
  if $VERBOSE; then
    local repo_count=0
    case "$FORMAT" in
      json)
        repo_count=$(echo "$changelog_content" | grep -c '"repository":' 2>/dev/null || echo "0")
        ;;
      *)
        repo_count=$(echo "$changelog_content" | grep -E '^(## |=== )' | wc -l)
        ;;
    esac
    log "Repositories processed: $repo_count"
  fi
}

# Run main function
main "$@"