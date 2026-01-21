#!/bin/bash
set -e
clear

# ==============================================
# AzerothCore-RealmMaster - Interactive .env generator
# ==============================================
# Mirrors options from scripts/setup-server.sh but targets .env

# === Paths / project identity ===
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
TEMPLATE_FILE="$SCRIPT_DIR/.env.template"

# === Helper sources ===
# setup.sh -> scripts/bash/project_name.sh (project naming helpers)
source "$SCRIPT_DIR/scripts/bash/project_name.sh"
# setup.sh -> scripts/bash/project_name.sh (project_name::resolve)
DEFAULT_PROJECT_NAME="$(project_name::resolve "$ENV_FILE" "$TEMPLATE_FILE")"

# setup.sh -> scripts/bash/setup/defaults.sh (template-backed defaults)
source "$SCRIPT_DIR/scripts/bash/setup/defaults.sh"
# setup.sh -> scripts/bash/setup/ui.sh (prompting/UI helpers)
source "$SCRIPT_DIR/scripts/bash/setup/ui.sh"
# setup.sh -> scripts/bash/setup/cli.sh (CLI parsing)
source "$SCRIPT_DIR/scripts/bash/setup/cli.sh"
# setup.sh -> scripts/bash/setup/modules.sh (module metadata)
source "$SCRIPT_DIR/scripts/bash/setup/modules.sh"
# setup.sh -> scripts/bash/setup/config_flow.sh (interactive config flow)
source "$SCRIPT_DIR/scripts/bash/setup/config_flow.sh"
# setup.sh -> scripts/bash/setup/module_selection.sh (module selection flow)
source "$SCRIPT_DIR/scripts/bash/setup/module_selection.sh"
# setup.sh -> scripts/bash/setup/output_flow.sh (summary/output flow)
source "$SCRIPT_DIR/scripts/bash/setup/output_flow.sh"
# setup.sh -> scripts/bash/setup/env.sh (.env rendering)
source "$SCRIPT_DIR/scripts/bash/setup/env.sh"

# === Runtime flags ===
NON_INTERACTIVE=0

main(){
  # === Init / CLI ===
  # setup.sh -> scripts/bash/setup/cli.sh (initialize CLI defaults)
  init_cli_defaults

  # setup.sh -> scripts/bash/setup/modules.sh (module metadata defaults)
  initialize_module_defaults
  reset_modules_to_defaults

  # setup.sh -> scripts/bash/setup/cli.sh (parse CLI args)
  parse_cli_args "$@"

  # === CLI overrides / flags ===
  # setup.sh -> scripts/bash/setup/cli.sh (apply CLI module flags)
  apply_cli_module_flags

  # === Intro ===
  # setup.sh -> scripts/bash/setup/ui.sh (banner)
  show_wow_header
  say INFO "This will create .env for compose profiles."

  # === Interactive configuration ===
  select_deployment_type
  configure_server
  choose_permission_scheme
  configure_database
  configure_storage
  configure_backups
  select_server_preset

  # === Modules ===
  # setup.sh -> scripts/bash/setup/module_selection.sh (module selection workflow)
  setup_select_modules

  # === Summary ===
  print_summary

  # === Paths / exports ===
  configure_local_storage_paths
  handle_rebuild_sentinel
  set_rebuild_source_path

  # === Render output ===
  # setup.sh -> scripts/bash/setup/env.sh (.env rendering)
  setup_write_env
  # setup.sh -> scripts/bash/setup/ui.sh (final status)
  show_realm_configured
  print_final_next_steps
}

main "$@"
