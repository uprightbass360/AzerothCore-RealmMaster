#!/usr/bin/env bash

# Helper utilities for dynamically including docker compose override files
# based on FEATURE_NAME_ENABLED style environment flags.

compose_overrides::trim() {
  local value="$1"
  # shellcheck disable=SC2001
  value="$(echo "$value" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
  printf '%s' "$value"
}

compose_overrides::derive_flag_from_name() {
  local file="$1"
  local base
  base="$(basename "$file")"
  base="${base%.*}"
  base="${base//[^[:alnum:]]/_}"
  base="${base^^}"
  printf 'COMPOSE_OVERRIDE_%s_ENABLED' "$base"
}

compose_overrides::extract_tag() {
  local file="$1" tag="$2"
  local line
  line="$(grep -m1 "^# *${tag}:" "$file" 2>/dev/null || true)"
  if [ -z "$line" ]; then
    return 1
  fi
  line="${line#*:}"
  compose_overrides::trim "$line"
}

compose_overrides::extract_all_tags() {
  local file="$1" tag="$2"
  grep "^# *${tag}:" "$file" 2>/dev/null | cut -d':' -f2- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

compose_overrides::read_env_value() {
  local env_path="$1" key="$2" default="${3:-}"
  local value=""
  if [ -f "$env_path" ]; then
    value="$(grep -E "^${key}=" "$env_path" | tail -n1 | cut -d'=' -f2- | tr -d '\r')"
  fi
  if [ -z "$value" ]; then
    value="$default"
  fi
  printf '%s' "$value"
}

compose_overrides::list_enabled_files() {
  local root_dir="$1" env_path="$2" result_var="$3"
  local overrides_dir="${root_dir}/compose-overrides"
  local -n __result="$result_var"
  __result=()

  [ -d "$overrides_dir" ] || return 0

  local -a override_files=()
  while IFS= read -r -d '' file; do
    override_files+=("$file")
  done < <(find "$overrides_dir" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) -print0 | sort -z)

  local file flag flag_value legacy_default legacy_flags legacy_flag
  for file in "${override_files[@]}"; do
    flag="$(compose_overrides::extract_tag "$file" "override-flag" || true)"
    if [ -z "$flag" ]; then
      flag="$(compose_overrides::derive_flag_from_name "$file")"
    fi

    legacy_default="0"
    legacy_flags="$(compose_overrides::extract_all_tags "$file" "legacy-flag" || true)"
    if [ -n "$legacy_flags" ]; then
      while IFS= read -r legacy_flag; do
        [ -z "$legacy_flag" ] && continue
        legacy_default="$(compose_overrides::read_env_value "$env_path" "$legacy_flag" "$legacy_default")"
        # Stop at first legacy flag that yields a value
        if [ -n "$legacy_default" ]; then
          break
        fi
      done <<< "$legacy_flags"
    fi

    flag_value="$(compose_overrides::read_env_value "$env_path" "$flag" "$legacy_default")"
    if [ "$flag_value" = "1" ]; then
      __result+=("$file")
    fi
  done
}

compose_overrides::build_compose_args() {
  local root_dir="$1" env_path="$2" default_compose="$3" result_var="$4"
  local -n __result="$result_var"
  __result=(-f "$default_compose")

  local -a enabled_files=()
  compose_overrides::list_enabled_files "$root_dir" "$env_path" enabled_files
  for file in "${enabled_files[@]}"; do
    __result+=(-f "$file")
  done
}
