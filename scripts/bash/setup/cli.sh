# CLI parsing for setup.sh

init_cli_defaults() {
  CLI_DEPLOYMENT_TYPE=""
  CLI_PERMISSION_SCHEME=""
  CLI_CUSTOM_UID=""
  CLI_CUSTOM_GID=""
  CLI_SERVER_ADDRESS=""
  CLI_REALM_PORT=""
  CLI_AUTH_PORT=""
  CLI_SOAP_PORT=""
  CLI_MYSQL_PORT=""
  CLI_MYSQL_PASSWORD=""
  CLI_STORAGE_PATH=""
  CLI_BACKUP_DAYS=""
  CLI_BACKUP_HOURS=""
  CLI_BACKUP_TIME=""
  CLI_MODULE_MODE=""
  CLI_MODULE_PRESET=""
  CLI_PLAYERBOT_ENABLED=""
  CLI_PLAYERBOT_MIN=""
  CLI_PLAYERBOT_MAX=""
  CLI_CONFIG_PRESET=""
  FORCE_OVERWRITE=0
  CLI_ENABLE_MODULES_RAW=()
}

print_help() {
  cat <<'HELP'
Usage: ./setup.sh [options]

Description:
  Interactive wizard that generates .env for the
  profiles-based compose. Prompts for deployment type, ports, storage,
  MySQL credentials, backup retention, and module presets or manual
  toggles.

Options:
  -h, --help                      Show this help message and exit
  --non-interactive               Use defaults/arguments without prompting
  --deployment-type TYPE          Deployment type: local, lan, or public
  --permission-scheme SCHEME      Permissions: local, nfs, or custom
  --custom-uid UID                UID when --permission-scheme=custom
  --custom-gid GID                GID when --permission-scheme=custom
  --server-address ADDRESS        Realm/public address
  --realm-port PORT               Client connection port (default 8215)
  --auth-port PORT                Authserver external port (default 3784)
  --soap-port PORT                SOAP external port (default 7778)
  --mysql-port PORT               MySQL external port (default 64306)
  --mysql-password PASSWORD       MySQL root password (default azerothcore123)
  --storage-path PATH             Storage directory
  --backup-retention-days N       Daily backup retention (default 3)
  --backup-retention-hours N      Hourly backup retention (default 6)
  --backup-daily-time HH          Daily backup hour 00-23 (default 09)
  --module-mode MODE              suggested, playerbots, manual, or none
  --module-config NAME            Use preset NAME from config/module-profiles/<NAME>.json
  --server-config NAME            Use server preset NAME from config/presets/<NAME>.conf
  --enable-modules LIST           Comma-separated module list (MODULE_* or shorthand)
  --playerbot-enabled 0|1         Override PLAYERBOT_ENABLED flag
    --playerbot-min-bots N          Override PLAYERBOT_MIN_BOTS value
    --playerbot-max-bots N          Override PLAYERBOT_MAX_BOTS value
  --force                         Overwrite existing .env without prompting
HELP
}

parse_cli_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -h|--help)
        print_help
        exit 0
        ;;
      --non-interactive)
        NON_INTERACTIVE=1
        shift
        ;;
      --deployment-type)
        [[ $# -ge 2 ]] || { say ERROR "--deployment-type requires a value"; exit 1; }
        CLI_DEPLOYMENT_TYPE="$2"; shift 2
        ;;
      --deployment-type=*)
        CLI_DEPLOYMENT_TYPE="${1#*=}"; shift
        ;;
      --permission-scheme)
        [[ $# -ge 2 ]] || { say ERROR "--permission-scheme requires a value"; exit 1; }
        CLI_PERMISSION_SCHEME="$2"; shift 2
        ;;
      --permission-scheme=*)
        CLI_PERMISSION_SCHEME="${1#*=}"; shift
        ;;
      --custom-uid)
        [[ $# -ge 2 ]] || { say ERROR "--custom-uid requires a value"; exit 1; }
        CLI_CUSTOM_UID="$2"; shift 2
        ;;
      --custom-uid=*)
        CLI_CUSTOM_UID="${1#*=}"; shift
        ;;
      --custom-gid)
        [[ $# -ge 2 ]] || { say ERROR "--custom-gid requires a value"; exit 1; }
        CLI_CUSTOM_GID="$2"; shift 2
        ;;
      --custom-gid=*)
        CLI_CUSTOM_GID="${1#*=}"; shift
        ;;
      --server-address)
        [[ $# -ge 2 ]] || { say ERROR "--server-address requires a value"; exit 1; }
        CLI_SERVER_ADDRESS="$2"; shift 2
        ;;
      --server-address=*)
        CLI_SERVER_ADDRESS="${1#*=}"; shift
        ;;
      --realm-port)
        [[ $# -ge 2 ]] || { say ERROR "--realm-port requires a value"; exit 1; }
        CLI_REALM_PORT="$2"; shift 2
        ;;
      --realm-port=*)
        CLI_REALM_PORT="${1#*=}"; shift
        ;;
      --auth-port)
        [[ $# -ge 2 ]] || { say ERROR "--auth-port requires a value"; exit 1; }
        CLI_AUTH_PORT="$2"; shift 2
        ;;
      --auth-port=*)
        CLI_AUTH_PORT="${1#*=}"; shift
        ;;
      --soap-port)
        [[ $# -ge 2 ]] || { say ERROR "--soap-port requires a value"; exit 1; }
        CLI_SOAP_PORT="$2"; shift 2
        ;;
      --soap-port=*)
        CLI_SOAP_PORT="${1#*=}"; shift
        ;;
      --mysql-port)
        [[ $# -ge 2 ]] || { say ERROR "--mysql-port requires a value"; exit 1; }
        CLI_MYSQL_PORT="$2"; shift 2
        ;;
      --mysql-port=*)
        CLI_MYSQL_PORT="${1#*=}"; shift
        ;;
      --mysql-password)
        [[ $# -ge 2 ]] || { say ERROR "--mysql-password requires a value"; exit 1; }
        CLI_MYSQL_PASSWORD="$2"; shift 2
        ;;
      --mysql-password=*)
        CLI_MYSQL_PASSWORD="${1#*=}"; shift
        ;;
      --storage-path)
        [[ $# -ge 2 ]] || { say ERROR "--storage-path requires a value"; exit 1; }
        CLI_STORAGE_PATH="$2"; shift 2
        ;;
      --storage-path=*)
        CLI_STORAGE_PATH="${1#*=}"; shift
        ;;
      --backup-retention-days)
        [[ $# -ge 2 ]] || { say ERROR "--backup-retention-days requires a value"; exit 1; }
        CLI_BACKUP_DAYS="$2"; shift 2
        ;;
      --backup-retention-days=*)
        CLI_BACKUP_DAYS="${1#*=}"; shift
        ;;
      --backup-retention-hours)
        [[ $# -ge 2 ]] || { say ERROR "--backup-retention-hours requires a value"; exit 1; }
        CLI_BACKUP_HOURS="$2"; shift 2
        ;;
      --backup-retention-hours=*)
        CLI_BACKUP_HOURS="${1#*=}"; shift
        ;;
      --backup-daily-time)
        [[ $# -ge 2 ]] || { say ERROR "--backup-daily-time requires a value"; exit 1; }
        CLI_BACKUP_TIME="$2"; shift 2
        ;;
      --backup-daily-time=*)
        CLI_BACKUP_TIME="${1#*=}"; shift
        ;;
      --module-mode)
        [[ $# -ge 2 ]] || { say ERROR "--module-mode requires a value"; exit 1; }
        CLI_MODULE_MODE="$2"; shift 2
        ;;
      --module-mode=*)
        CLI_MODULE_MODE="${1#*=}"; shift
        ;;
      --module-config)
        [[ $# -ge 2 ]] || { say ERROR "--module-config requires a value"; exit 1; }
        CLI_MODULE_PRESET="$2"; shift 2
        ;;
      --module-config=*)
        CLI_MODULE_PRESET="${1#*=}"; shift
        ;;
      --server-config)
        [[ $# -ge 2 ]] || { say ERROR "--server-config requires a value"; exit 1; }
        CLI_CONFIG_PRESET="$2"; shift 2
        ;;
      --server-config=*)
        CLI_CONFIG_PRESET="${1#*=}"; shift
        ;;
      --enable-modules)
        [[ $# -ge 2 ]] || { say ERROR "--enable-modules requires a value"; exit 1; }
        CLI_ENABLE_MODULES_RAW+=("$2"); shift 2
        ;;
      --enable-modules=*)
        CLI_ENABLE_MODULES_RAW+=("${1#*=}"); shift
        ;;
      --playerbot-enabled)
        [[ $# -ge 2 ]] || { say ERROR "--playerbot-enabled requires 0 or 1"; exit 1; }
        CLI_PLAYERBOT_ENABLED="$2"; shift 2
        ;;
      --playerbot-enabled=*)
        CLI_PLAYERBOT_ENABLED="${1#*=}"; shift
        ;;
      --playerbot-min-bots)
        [[ $# -ge 2 ]] || { say ERROR "--playerbot-min-bots requires a value"; exit 1; }
        CLI_PLAYERBOT_MIN="$2"; shift 2
        ;;
      --playerbot-min-bots=*)
        CLI_PLAYERBOT_MIN="${1#*=}"; shift
        ;;
      --playerbot-max-bots)
        [[ $# -ge 2 ]] || { say ERROR "--playerbot-max-bots requires a value"; exit 1; }
        CLI_PLAYERBOT_MAX="$2"; shift 2
        ;;
      --playerbot-max-bots=*)
        CLI_PLAYERBOT_MAX="${1#*=}"; shift
        ;;
      --force)
        FORCE_OVERWRITE=1
        shift
        ;;
      *)
        echo "Unknown argument: $1" >&2
        echo "Use --help for usage" >&2
        exit 1
        ;;
    esac
  done
}

apply_cli_module_flags() {
  # setup.sh -> scripts/bash/setup/modules.sh (normalize_module_name)
  # setup.sh -> scripts/bash/setup/ui.sh (say)
  if [ ${#CLI_ENABLE_MODULES_RAW[@]} -gt 0 ]; then
    local raw part norm
    for raw in "${CLI_ENABLE_MODULES_RAW[@]}"; do
      IFS=',' read -ra parts <<<"$raw"
      for part in "${parts[@]}"; do
        part="${part//[[:space:]]/}"
        [ -z "$part" ] && continue
        norm="$(normalize_module_name "$part")"
        if [ -z "${KNOWN_MODULE_LOOKUP[$norm]}" ]; then
          say WARNING "Ignoring unknown module identifier: ${part}"
          continue
        fi
        MODULE_ENABLE_SET["$norm"]=1
      done
    done
    unset raw part norm parts
  fi

  if [ ${#CLI_ENABLE_MODULES_RAW[@]} -gt 0 ] && [ -z "$CLI_MODULE_MODE" ]; then
    CLI_MODULE_MODE="manual"
  fi
}
