#!/bin/bash
# Shared helpers for hooks that stage module Lua scripts for ALE.
#
# Each module's scripts go into their own subfolder,
# $LUA_SCRIPTS_TARGET/<module name>/, which is wiped and rebuilt on every run so
# scripts removed upstream disappear. ALE loads subfolders recursively and adds
# each one to the Lua require path, so the subfolder layout needs no config.
#
# LUA_SCRIPTS_TARGET is set by the ac-modules container (the storage/lua_scripts
# mount the worldserver reads). When it is unset (host-side build runs), staging
# is skipped: the ac-modules run at deploy time does it.
#
# Exit codes follow manage-modules.sh: 0 ok, 1 warning, 2+ error.

# lua_stage_init <hook name>
lua_stage_init(){
  LUA_STAGE_HOOK="$1"

  if [ -z "${MODULE_DIR:-}" ] || [ ! -d "$MODULE_DIR" ]; then
    echo "❌ $LUA_STAGE_HOOK: Invalid module directory: ${MODULE_DIR:-}"
    exit 2
  fi

  LUA_STAGE_NAME="${MODULE_NAME:-}"
  [ -n "$LUA_STAGE_NAME" ] || LUA_STAGE_NAME="$(basename "$MODULE_DIR")"
  case "$LUA_STAGE_NAME" in
    */*|.|..) echo "❌ $LUA_STAGE_HOOK: Refusing unsafe module name '$LUA_STAGE_NAME'"; exit 2;;
  esac

  echo "📜 $LUA_STAGE_HOOK: Processing $LUA_STAGE_NAME"

  if [ -z "${LUA_SCRIPTS_TARGET:-}" ]; then
    echo "ℹ️  $LUA_STAGE_HOOK: LUA_SCRIPTS_TARGET not set; skipping Lua staging (ac-modules stages Lua at deploy time)"
    exit 0
  fi

  if ! mkdir -p "$LUA_SCRIPTS_TARGET" 2>/dev/null || [ ! -w "$LUA_SCRIPTS_TARGET" ]; then
    echo "❌ $LUA_STAGE_HOOK: Lua target $LUA_SCRIPTS_TARGET is not writable; scripts for $LUA_STAGE_NAME were NOT staged"
    exit 2
  fi

  LUA_STAGE_DEST="$LUA_SCRIPTS_TARGET/$LUA_STAGE_NAME"
  if ! rm -rf "$LUA_STAGE_DEST" || ! mkdir -p "$LUA_STAGE_DEST"; then
    echo "❌ $LUA_STAGE_HOOK: Cannot reset $LUA_STAGE_DEST"
    exit 2
  fi
  LUA_STAGE_COUNT=0
}

_lua_stage_copy(){
  local src="$1" rel="$2"
  if ! mkdir -p "$(dirname "$LUA_STAGE_DEST/$rel")" || ! cp "$src" "$LUA_STAGE_DEST/$rel"; then
    echo "      ⚠️  Failed to copy $rel"
    return 0
  fi
  echo "      ✅ Copied $rel"
  LUA_STAGE_COUNT=$((LUA_STAGE_COUNT + 1))
}

# lua_stage_files <dir> <label>
# Copies <dir>/*.lua (not recursive) flat into the module subfolder.
lua_stage_files(){
  local dir="$1" label="$2" file
  [ -d "$dir" ] || return 0
  local -a files=()
  while IFS= read -r -d '' file; do
    files+=("$file")
  done < <(find "$dir" -maxdepth 1 -type f -name '*.lua' -print0 | sort -z)
  [ "${#files[@]}" -gt 0 ] || return 0
  echo "   📂 Found $label"
  for file in "${files[@]}"; do
    _lua_stage_copy "$file" "$(basename "$file")"
  done
}

# lua_stage_tree <dir> <label>
# Copies every .lua under <dir>, preserving its relative layout.
lua_stage_tree(){
  local dir="$1" label="$2" file
  [ -d "$dir" ] || return 0
  local -a files=()
  while IFS= read -r -d '' file; do
    files+=("$file")
  done < <(cd "$dir" && find . -type f -name '*.lua' -print0 | sort -z)
  [ "${#files[@]}" -gt 0 ] || return 0
  echo "   📂 Found $label"
  for file in "${files[@]}"; do
    _lua_stage_copy "$dir/${file#./}" "${file#./}"
  done
}

# lua_stage_finish
# Exits 1 (warning) and removes the empty subfolder when nothing was staged.
lua_stage_finish(){
  if [ "$LUA_STAGE_COUNT" -eq 0 ]; then
    rmdir "$LUA_STAGE_DEST" 2>/dev/null || true
    echo "   ⚠️  $LUA_STAGE_HOOK: No Lua scripts found for $LUA_STAGE_NAME"
    exit 1
  fi
  echo "   ✅ Staged $LUA_STAGE_COUNT Lua script(s) to $LUA_STAGE_DEST"
  exit 0
}
