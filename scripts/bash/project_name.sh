#!/bin/bash

project_name::extract(){
  local file="$1"
  if [ -n "$file" ] && [ -f "$file" ]; then
    local line value
    line="$(grep -E '^COMPOSE_PROJECT_NAME=' "$file" 2>/dev/null | tail -n1)"
    if [ -n "$line" ]; then
      value="${line#*=}"
      value="${value%$'\r'}"
      value="$(printf '%s\n' "$value" | awk -F'#' '{print $1}' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      value="${value%\"}"; value="${value#\"}"
      value="${value%\'}"; value="${value#\'}"
      printf '%s\n' "$value"
    fi
  fi
}

project_name::resolve(){
  local env_file="$1" template_file="$2" value=""
  value="$(project_name::extract "$env_file")"
  if [ -z "$value" ] && [ -n "$template_file" ]; then
    value="$(project_name::extract "$template_file")"
  fi
  if [ -z "$value" ] && [ -n "${COMPOSE_PROJECT_NAME:-}" ]; then
    value="${COMPOSE_PROJECT_NAME}"
  fi
  if [ -z "$value" ]; then
    echo "Error: COMPOSE_PROJECT_NAME not defined in $env_file, $template_file, or environment." >&2
    exit 1
  fi
  printf '%s\n' "$value"
}

project_name::sanitize(){
  local raw="$1"
  local sanitized
  sanitized="$(echo "$raw" | tr '[:upper:]' '[:lower:]')"
  sanitized="${sanitized// /-}"
  sanitized="$(echo "$sanitized" | tr -cd 'a-z0-9_-')"
  if [[ -z "$sanitized" ]]; then
    echo "Error: COMPOSE_PROJECT_NAME '$raw' is invalid after sanitization." >&2
    exit 1
  fi
  if [[ ! "$sanitized" =~ ^[a-z0-9] ]]; then
    sanitized="ac${sanitized}"
  fi
  printf '%s\n' "$sanitized"
}
