#!/bin/bash
#
# Safe wrapper to update to the latest commit on the current branch and run deploy.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT_DIR"

BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info(){ printf '%b\n' "${BLUE}ℹ️  $*${NC}"; }
ok(){ printf '%b\n' "${GREEN}✅ $*${NC}"; }
warn(){ printf '%b\n' "${YELLOW}⚠️  $*${NC}"; }
err(){ printf '%b\n' "${RED}❌ $*${NC}"; }

FORCE_DIRTY=0
DEPLOY_ARGS=()
SKIP_BUILD=0
AUTO_DEPLOY=0

usage(){
  cat <<'EOF'
Usage: ./update-latest.sh [--force] [--help] [deploy args...]

Updates the current git branch with a fast-forward pull, runs a fresh build,
and optionally runs ./deploy.sh with any additional arguments you provide
(e.g., --yes --no-watch).

Options:
  --force        Skip the dirty-tree check (not recommended; you may lose changes)
  --skip-build   Do not run ./build.sh after updating
  --deploy       Auto-run ./deploy.sh after build (non-interactive)
  --help         Show this help

Examples:
  ./update-latest.sh --yes --no-watch
  ./update-latest.sh --deploy --yes --no-watch
  ./update-latest.sh --force --skip-build
  ./update-latest.sh --force --deploy --remote --remote-host my.host --remote-user sam --yes
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force) FORCE_DIRTY=1; shift;;
    --skip-build) SKIP_BUILD=1; shift;;
    --deploy) AUTO_DEPLOY=1; shift;;
    --help|-h) usage; exit 0;;
    *) DEPLOY_ARGS+=("$1"); shift;;
  esac
done

command -v git >/dev/null 2>&1 || { err "git is required"; exit 1; }

if [ "$FORCE_DIRTY" -ne 1 ]; then
  if [ -n "$(git status --porcelain)" ]; then
    err "Working tree is dirty. Commit/stash or re-run with --force."
    exit 1
  fi
fi

current_branch="$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
if [ -z "$current_branch" ] || [ "$current_branch" = "HEAD" ]; then
  err "Cannot update: detached HEAD or unknown branch."
  exit 1
fi

if ! git ls-remote --exit-code --heads origin "$current_branch" >/dev/null 2>&1; then
  err "Remote branch origin/$current_branch not found."
  exit 1
fi

info "Fetching latest changes from origin/$current_branch"
git fetch --prune origin

info "Fast-forwarding to origin/$current_branch"
if ! git merge --ff-only "origin/$current_branch"; then
  err "Fast-forward failed. Resolve manually or rebase, then rerun."
  exit 1
fi

ok "Repository updated to $(git rev-parse --short HEAD)"

if [ "$SKIP_BUILD" -ne 1 ]; then
  info "Running build.sh --yes"
  if ! "$ROOT_DIR/build.sh" --yes; then
    err "Build failed. Resolve issues and re-run."
    exit 1
  fi
  ok "Build completed"
else
  warn "Skipping build (--skip-build set)"
fi

# Offer to run deploy
if [ "$AUTO_DEPLOY" -eq 1 ]; then
  info "Auto-deploy enabled; running deploy.sh ${DEPLOY_ARGS[*]:-(no extra args)}"
  exec "$ROOT_DIR/deploy.sh" "${DEPLOY_ARGS[@]}"
fi

if [ -t 0 ]; then
  read -r -p "Run deploy.sh now? [y/N]: " reply
  reply="${reply:-n}"
  case "$reply" in
    [Yy]*)
      info "Running deploy.sh ${DEPLOY_ARGS[*]:-(no extra args)}"
      exec "$ROOT_DIR/deploy.sh" "${DEPLOY_ARGS[@]}"
      ;;
    *)
      ok "Update (and build) complete. Run ./deploy.sh ${DEPLOY_ARGS[*]} when ready."
      exit 0
      ;;
  esac
else
  warn "Non-interactive mode and --deploy not set; skipping deploy."
  ok "Update (and build) complete. Run ./deploy.sh ${DEPLOY_ARGS[*]} when ready."
fi
