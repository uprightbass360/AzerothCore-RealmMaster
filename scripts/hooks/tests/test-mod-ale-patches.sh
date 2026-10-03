#!/bin/bash
# Tests for mod-ale-patches compatibility hook.
# Runs against fixture directories in a temp dir; no docker or network needed.
#
# Usage: scripts/hooks/tests/test-mod-ale-patches.sh
set -uo pipefail

HOOKS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'chmod -R u+w "$WORK" 2>/dev/null; rm -rf "$WORK"' EXIT

PASS=0
FAIL=0

pass(){ PASS=$((PASS + 1)); echo "  ok   $1"; }
fail(){ FAIL=$((FAIL + 1)); echo "  FAIL $1"; }

assert_eq(){ [ "$1" = "$2" ] && pass "$3" || fail "$3 (expected '$2', got '$1')"; }
assert_contains(){ echo "$1" | grep -q "$2" && pass "$3" || fail "$3 (output did not contain '$2')"; }

echo "mod-ale-patches tests"

# Test 1: Invalid directory exits 2
OUT="$(env -u MODULE_DIR "$HOOKS_DIR/mod-ale-patches" 2>&1 || true)"
RC=$?
assert_contains "$OUT" "Invalid module directory" "rejects empty module directory"

# Setup fixture
M="$WORK/modules/mod-ale"
CORE="$WORK/source/azerothcore-playerbots"
PB="$WORK/modules/mod-playerbots"
mkdir -p "$M/src/LuaEngine/methods" "$M/src"
touch "$M/src/ALE_SC.cpp"
mkdir -p "$CORE/src/server/game/Server"
mkdir -p "$CORE/src/server/game/Scripting/ScriptDefines"
mkdir -p "$PB/src/Bot"

cat <<'EOF' > "$M/src/LuaEngine/methods/PlayerMethods.h"
#include "Chat.h"
#include "GameTime.h"
#include "GossipDef.h"

/***
 * Inherits all methods from: [Object], [WorldObject], [Unit]
 */
namespace LuaPlayer
{
    int IsBot(lua_State* L, Player* player)
    {
    #if defined(MOD_PLAYERBOTS)
        ALE::Push(L, player->GetSession()->IsBot());
    #else
        (void)player;
        ALE::Push(L, false);
    #endif
        return 1;
    }
}
EOF

cat <<'EOF' > "$PB/src/Bot/PlayerbotMgr.h"
#pragma once
class PlayerbotAI;
class PlayerbotMgr {
public:
    PlayerbotAI* GetPlayerbotAI(Player* player);
};
#define sPlayerbotsMgr PlayerbotsMgr::instance()
EOF

cat <<'EOF' > "$CORE/src/server/game/Server/WorldSession.h"
#pragma once
class WorldSession {
    // No IsBot method here
};
EOF

# Test 2: Patch applied when WorldSession lacks IsBot
OUT="$(MODULE_DIR="$M" MODULE_NAME="mod-ale" "$HOOKS_DIR/mod-ale-patches" 2>&1)"
RC=$?
assert_eq "$RC" 0 "hook succeeds with exit code 0"
assert_contains "$OUT" "Patched Playerbot IsBot binding to sPlayerbotsMgr.GetPlayerbotAI" "applies IsBot patch"

# Verify modified contents
assert_contains "$(cat "$M/src/LuaEngine/methods/PlayerMethods.h")" "#include \"PlayerbotMgr.h\"" "includes PlayerbotMgr.h"
assert_contains "$(cat "$M/src/LuaEngine/methods/PlayerMethods.h")" "player && sPlayerbotsMgr.GetPlayerbotAI(player) != nullptr" "replaces IsBot call"

# Test 3: Idempotent - second run skips already patched
OUT="$(MODULE_DIR="$M" MODULE_NAME="mod-ale" "$HOOKS_DIR/mod-ale-patches" 2>&1)"
RC=$?
assert_eq "$RC" 0 "second run succeeds with exit code 0"
assert_contains "$OUT" "Playerbot IsBot binding already matches mod-playerbots" "detects already patched state"

# Test 4: Feature flag disabled skips
cat <<'EOF' > "$M/src/LuaEngine/methods/PlayerMethods.h"
#include "Chat.h"
#include "GameTime.h"
#include "GossipDef.h"

namespace LuaPlayer
{
    int IsBot(lua_State* L, Player* player)
    {
    #if defined(MOD_PLAYERBOTS)
        ALE::Push(L, player->GetSession()->IsBot());
    #else
        (void)player;
        ALE::Push(L, false);
    #endif
        return 1;
    }
}
EOF

OUT="$(APPLY_PLAYERBOT_ISBOT_PATCH=0 MODULE_DIR="$M" MODULE_NAME="mod-ale" "$HOOKS_DIR/mod-ale-patches" 2>&1)"
RC=$?
assert_eq "$RC" 0 "run with flag=0 succeeds"
assert_contains "$(cat "$M/src/LuaEngine/methods/PlayerMethods.h")" "player->GetSession()->IsBot()" "flag=0 skips patch"

# Test 5: Core still declares IsBot -> skips
echo "bool IsBot() const;" >> "$CORE/src/server/game/Server/WorldSession.h"
OUT="$(MODULE_DIR="$M" MODULE_NAME="mod-ale" "$HOOKS_DIR/mod-ale-patches" 2>&1)"
RC=$?
assert_eq "$RC" 0 "run with core declaring IsBot succeeds"
assert_contains "$OUT" "Core WorldSession still declares IsBot(); nothing to do" "skips when core still has IsBot"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
