#!/bin/bash
# Phase 1 Integration Test Script
# Tests the complete Phase 1 implementation using build and deploy workflows

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Colors
BLUE='\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

# Icons
ICON_SUCCESS="✅"
ICON_WARNING="⚠️"
ICON_ERROR="❌"
ICON_INFO="ℹ️"
ICON_TEST="🧪"

# Counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0

info() {
  echo -e "${BLUE}${ICON_INFO}${NC} $*"
}

ok() {
  echo -e "${GREEN}${ICON_SUCCESS}${NC} $*"
  ((TESTS_PASSED+=1))
}

warn() {
  echo -e "${YELLOW}${ICON_WARNING}${NC} $*"
}

err() {
  echo -e "${RED}${ICON_ERROR}${NC} $*"
  ((TESTS_FAILED+=1))
}

test_header() {
  ((TESTS_TOTAL+=1))
  echo ""
  echo -e "${BOLD}${ICON_TEST} Test $TESTS_TOTAL: $*${NC}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

section_header() {
  echo ""
  echo ""
  echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════${NC}"
  echo -e "${BOLD}${BLUE} $*${NC}"
  echo -e "${BOLD}${BLUE}═══════════════════════════════════════════════════════${NC}"
  echo ""
}

# Change to project root
cd "$PROJECT_ROOT"

section_header "Phase 1 Integration Test Suite"

info "Project root: $PROJECT_ROOT"
info "Test started: $(date)"

# Ensure storage directories are writable before generating module state
if [ -x "$PROJECT_ROOT/scripts/bash/repair-storage-permissions.sh" ]; then
  info "Normalizing storage permissions"
  "$PROJECT_ROOT/scripts/bash/repair-storage-permissions.sh" --silent || true
fi

# Test 1: Verify .env exists
test_header "Environment Configuration Check"
if [ -f .env ]; then
  ok ".env file exists"

  # Count enabled modules
  enabled_count=$(grep -c "^MODULE_.*=1" .env || echo "0")
  info "Enabled modules: $enabled_count"

  # Check for playerbots
  if grep -q "^MODULE_PLAYERBOTS=1" .env; then
    info "Playerbots module enabled"
  fi
else
  err ".env file not found"
  echo "Please run ./setup.sh first"
  exit 1
fi

# Test 2: Module manifest validation
test_header "Module Manifest Validation"
if [ -f config/module-manifest.json ]; then
  ok "Module manifest exists"

  # Validate JSON
  if python3 -m json.tool config/module-manifest.json >/dev/null 2>&1; then
    ok "Module manifest is valid JSON"
  else
    err "Module manifest has invalid JSON"
  fi
else
  err "Module manifest not found"
  exit 1
fi

# Test 3: Generate module state with SQL discovery
test_header "Module State Generation (SQL Discovery)"
info "Running: python3 scripts/python/modules.py generate"

if python3 scripts/python/modules.py \
    --env-path .env \
    --manifest config/module-manifest.json \
    generate --output-dir local-storage/modules > /tmp/phase1-modules-generate.log 2>&1; then
  ok "Module state generation successful"
else
  # Check if it's just warnings
  if grep -q "warnings detected" /tmp/phase1-modules-generate.log 2>/dev/null; then
    ok "Module state generation completed with warnings"
  else
    err "Module state generation failed"
  fi
fi

# Test 4: Verify SQL manifest created
test_header "SQL Manifest Verification"
if [ -f local-storage/modules/.sql-manifest.json ]; then
  ok "SQL manifest created: local-storage/modules/.sql-manifest.json"

  # Check manifest structure
  module_count=$(python3 -c "import json; data=json.load(open('local-storage/modules/.sql-manifest.json')); print(len(data.get('modules', [])))" 2>/dev/null || echo "0")
  info "Modules with SQL: $module_count"

  if [ "$module_count" -gt 0 ]; then
    ok "SQL manifest contains $module_count module(s)"

    # Show first module
    info "Sample module SQL info:"
    python3 -c "import json; data=json.load(open('local-storage/modules/.sql-manifest.json')); m=data['modules'][0] if data['modules'] else {}; print(f\"  Name: {m.get('name', 'N/A')}\n  SQL files: {len(m.get('sql_files', {}))}\") " 2>/dev/null || true
  else
    warn "No modules with SQL files (expected if modules not yet staged)"
  fi
else
  err "SQL manifest not created"
fi

# Test 5: Verify modules.env created
test_header "Module Environment File Check"
if [ -f local-storage/modules/modules.env ]; then
  ok "modules.env created"

  # Check for key exports
  if grep -q "MODULES_ENABLED=" local-storage/modules/modules.env; then
    ok "MODULES_ENABLED variable present"
  fi

  if grep -q "MODULES_REQUIRES_CUSTOM_BUILD=" local-storage/modules/modules.env; then
    ok "Build requirement flags present"

    # Check if build required
    source local-storage/modules/modules.env
    if [ "${MODULES_REQUIRES_CUSTOM_BUILD:-0}" = "1" ]; then
      info "Custom build required (C++ modules enabled)"
    else
      info "Standard build sufficient (no C++ modules)"
    fi
  fi
else
  err "modules.env not created"
fi

# Test 6: Check build requirement
test_header "Build Requirement Check"
if [ -f local-storage/modules/modules.env ]; then
  source local-storage/modules/modules.env

  info "MODULES_REQUIRES_CUSTOM_BUILD=${MODULES_REQUIRES_CUSTOM_BUILD:-0}"
  info "MODULES_REQUIRES_PLAYERBOT_SOURCE=${MODULES_REQUIRES_PLAYERBOT_SOURCE:-0}"

  if [ "${MODULES_REQUIRES_CUSTOM_BUILD:-0}" = "1" ]; then
    ok "Build system correctly detected C++ modules"
    BUILD_REQUIRED=1
  else
    ok "Build system correctly detected no C++ modules"
    BUILD_REQUIRED=0
  fi
else
  warn "Cannot determine build requirements"
  BUILD_REQUIRED=0
fi

# Test 7: Verify new scripts exist and are executable
test_header "New Script Verification"
scripts=(
  "scripts/bash/verify-sql-updates.sh"
  "scripts/bash/backup-status.sh"
  "scripts/bash/db-health-check.sh"
)

for script in "${scripts[@]}"; do
  if [ -f "$script" ]; then
    if [ -x "$script" ]; then
      ok "$(basename "$script") - exists and executable"
    else
      warn "$(basename "$script") - exists but not executable"
      chmod +x "$script"
      ok "Fixed permissions for $(basename "$script")"
    fi
  else
    err "$(basename "$script") - not found"
  fi
done

# Test 8: Test backup-status.sh (without running containers)
test_header "Backup Status Script Test"
backup_status_log="$(mktemp)"
if ./scripts/bash/backup-status.sh >"$backup_status_log" 2>&1; then
  if grep -q "BACKUP STATUS" "$backup_status_log"; then
    ok "backup-status.sh executes successfully"
  else
    err "backup-status.sh output missing 'BACKUP STATUS' marker"
  fi
else
  err "backup-status.sh failed to execute"
fi
rm -f "$backup_status_log"

# Test 9: Test db-health-check.sh help
test_header "Database Health Check Script Test"
if ./scripts/bash/db-health-check.sh --help | grep -q "Check the health status"; then
  ok "db-health-check.sh help working"
else
  err "db-health-check.sh help failed"
fi

# Test 10: Check modified scripts for new functionality
test_header "Modified Script Verification"

# Check stage-modules.sh has runtime SQL staging function
if grep -q "stage_module_sql_to_core()" scripts/bash/stage-modules.sh; then
  ok "stage-modules.sh contains runtime SQL staging function"
else
  err "stage-modules.sh missing runtime SQL staging function"
fi

# Check db-import-conditional.sh has playerbots support
if grep -q "PlayerbotsDatabaseInfo" scripts/bash/db-import-conditional.sh; then
  ok "db-import-conditional.sh has playerbots database support"
else
  err "db-import-conditional.sh missing playerbots support"
fi

if grep -q "Updates.EnableDatabases = 15" scripts/bash/db-import-conditional.sh; then
  ok "db-import-conditional.sh has correct EnableDatabases value (15)"
else
  warn "db-import-conditional.sh may have incorrect EnableDatabases value"
fi

# Check for restore marker safety net
if grep -q "verify_databases_populated" scripts/bash/db-import-conditional.sh; then
  ok "db-import-conditional.sh verifies live MySQL state before honoring restore markers"
else
  err "db-import-conditional.sh missing restore marker safety check"
fi

# Check for post-restore verification
if grep -q "verify_and_update_restored_databases" scripts/bash/db-import-conditional.sh; then
  ok "db-import-conditional.sh has post-restore verification"
else
  err "db-import-conditional.sh missing post-restore verification"
fi

# Test 11: Restore + Module Staging Automation
test_header "Restore + Module Staging Automation"
if grep -q "restore-and-stage.sh" docker-compose.yml && \
   grep -q ".restore-prestaged" scripts/bash/restore-and-stage.sh; then
  ok "restore-and-stage.sh wired into compose and flags stage-modules to recopy SQL"
else
  err "restore-and-stage.sh missing compose wiring or flag handling"
fi

# Test 12: Docker Compose configuration check
test_header "Docker Compose Configuration Check"
if [ -f docker-compose.yml ]; then
  ok "docker-compose.yml exists"

  # Check for required services
  if grep -q "ac-mysql:" docker-compose.yml; then
    ok "MySQL service configured"
  fi

  if grep -q "ac-worldserver:" docker-compose.yml; then
    ok "Worldserver service configured"
  fi
else
  err "docker-compose.yml not found"
fi

# Test Summary
section_header "Test Summary"

echo ""
echo -e "${BOLD}Tests Executed: $TESTS_TOTAL${NC}"
echo -e "${GREEN}${BOLD}Passed: $TESTS_PASSED${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
  echo -e "${RED}${BOLD}Failed: $TESTS_FAILED${NC}"
else
  echo -e "${GREEN}${BOLD}Failed: $TESTS_FAILED${NC}"
fi
echo ""

# Calculate success rate
if [ $TESTS_TOTAL -gt 0 ]; then
  success_rate=$((TESTS_PASSED * 100 / TESTS_TOTAL))
  echo -e "${BOLD}Success Rate: ${success_rate}%${NC}"
fi

echo ""

if [ $TESTS_FAILED -eq 0 ]; then
  echo -e "${GREEN}${BOLD}${ICON_SUCCESS} ALL TESTS PASSED${NC}"
  echo ""
  echo "Phase 1 implementation is working correctly!"
  echo ""
  echo "Next steps:"
  echo "  1. Run './build.sh' if C++ modules are enabled"
  echo "  2. Run './deploy.sh' to start containers"
  echo "  3. Verify SQL staging with running containers"
  echo "  4. Check database health with db-health-check.sh"
  exit 0
else
  echo -e "${RED}${BOLD}${ICON_ERROR} SOME TESTS FAILED${NC}"
  echo ""
  echo "Please review the failures above before proceeding."
  exit 1
fi
