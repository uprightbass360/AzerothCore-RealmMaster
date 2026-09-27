#!/bin/bash
# setup.sh must initialise module defaults when config/module-manifest.local.json
# adds modules that .env.template has no default for (they default to 0), while
# still failing on upstream keys missing from the template (template drift).
# Sources the real scripts/bash/setup/modules.sh against a temp project root.
#
# Usage: scripts/bash/tests/test-setup-local-modules.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

PASS=0
FAIL=0
check(){ if [ "$2" = "$3" ]; then PASS=$((PASS + 1)); echo "  ok   $1"; else FAIL=$((FAIL + 1)); echo "  FAIL $1 (expected '$3', got '$2')"; fi; }

# make_root <name> <template-lines>: temp project root sharing the real scripts/.
make_root(){
  local root="$WORK/$1"
  mkdir -p "$root/config"
  ln -s "$REPO_ROOT/scripts" "$root/scripts"
  cat > "$root/config/module-manifest.json" <<'EOF'
{"modules": [
  {"key": "MODULE_A", "name": "mod-a", "repo": "https://example.com/mod-a.git", "type": "cpp"},
  {"key": "MODULE_B", "name": "mod-b", "repo": "https://example.com/mod-b.git", "type": "lua"}
]}
EOF
  cat > "$root/config/module-manifest.local.json" <<'EOF'
{"modules": [
  {"key": "MODULE_MINE", "name": "mod-mine", "repo": "https://example.com/mod-mine.git", "type": "lua"},
  {"key": "MODULE_B", "ref": "v1"}
]}
EOF
  printf '%s\n' "$2" > "$root/.env.template"
  echo "$root"
}

# Prints "<MODULE_A>|<MODULE_B>|<MODULE_MINE>" after initialize_module_defaults.
run_init(){
  SCRIPT_DIR="$1" bash -c '
    set -e
    source "$SCRIPT_DIR/scripts/bash/setup/modules.sh"
    initialize_module_defaults
    echo "${MODULE_A}|${MODULE_B}|${MODULE_MINE-unset}|${MODULE_DEFAULT_VALUES[MODULE_MINE]-unset}"
  ' 2>"$WORK/err"
}

echo "local module without a .env.template default"
root="$(make_root ok $'MODULE_A=1\nMODULE_B=0')"
out="$(run_init "$root")"; rc=$?
check "initialize_module_defaults succeeds" "$rc" "0"
check "upstream defaults come from the template, local key defaults to 0" "$out" "1|0|0|0"

echo "upstream key missing from .env.template"
root="$(make_root drift 'MODULE_A=1')"
out="$(run_init "$root")"; rc=$?
check "still fails" "$rc" "1"
grep -q "missing default value for MODULE_B" "$WORK/err"
check "names the missing upstream key" "$?" "0"

echo
echo "passed: $PASS  failed: $FAIL"
[ "$FAIL" -eq 0 ]
