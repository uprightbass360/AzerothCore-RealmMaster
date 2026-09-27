#!/bin/bash
# Record of the C++ modules the current server images were compiled with, kept
# at <local storage>/modules/.built-modules. deploy.sh and build.sh compare it
# with the currently enabled C++ modules so enabling or disabling one triggers
# a rebuild; without it, a changed .env deployed onto the old image silently.
# Sourced by deploy.sh, build.sh and rebuild-with-modules.sh.

# module_build_record_file <local storage path>
module_build_record_file(){
  printf '%s/modules/.built-modules\n' "${1%/}"
}

_module_build_record_normalize(){
  printf '%s\n' "$@" | sed '/^$/d' | LC_ALL=C sort -u
}

# module_build_record_write <file> [module...]
module_build_record_write(){
  local file="$1"; shift
  mkdir -p "$(dirname "$file")" || return 1
  _module_build_record_normalize "$@" > "${file}.tmp" && mv "${file}.tmp" "$file"
}

# module_build_record_reason <file> [enabled module...]
# Prints a rebuild reason when the enabled set differs from the record.
# Installs that predate the record get the current set recorded, with a
# notice on stderr, rather than an unplanned rebuild.
module_build_record_reason(){
  local file="$1"; shift
  if [ ! -f "$file" ]; then
    if module_build_record_write "$file" "$@"; then
      echo "ℹ️  No record of which C++ modules the current images were built with; recorded the enabled set." >&2
      echo "   If you changed C++ modules since your last build, run ./build.sh --force." >&2
    fi
    return 0
  fi

  local current added removed
  current="$(_module_build_record_normalize "$@")"
  added="$(LC_ALL=C comm -13 "$file" <(printf '%s\n' "$current" | sed '/^$/d') | tr '\n' ' ')"
  removed="$(LC_ALL=C comm -23 "$file" <(printf '%s\n' "$current" | sed '/^$/d') | tr '\n' ' ')"
  if [ -n "$added$removed" ]; then
    local detail=""
    [ -n "$added" ] && detail="added: ${added% }"
    [ -n "$removed" ] && detail="${detail:+$detail; }removed: ${removed% }"
    echo "Enabled C++ modules changed since last build ($detail)"
  fi
  return 0
}
