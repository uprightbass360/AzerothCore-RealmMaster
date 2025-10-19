# ac-compose Deployment Guide

This guide walks through the end-to-end deployment workflow for the `ac-compose` stack. It focuses on the supported automation scripts, the order in which to run them, the default services/ports that come online, and the optional manual steps you may need when enabling additional modules.


## 1. Prerequisites

Before you begin:

- **Docker** and **Docker Compose v2** installed on the host.
- A POSIX-compatible shell (the provided scripts target Bash).
- Sufficient disk space for game assets, module clones, and source builds ( ≈ 20 GB recommended).
- Network access to GitHub (or a local mirror) for cloning AzerothCore source and modules.

> Tip: If you use a distinct user/group mapping (e.g., NFS-backed storage) the setup wizard will let you pick non-root UIDs/GIDs.


## 2. Generate `.env` via `setup.sh`

All environment configuration lives in `ac-compose/.env`. Generate or refresh it by running:

```bash
./setup.sh
```

The wizard will ask you to confirm:

1. **Deployment type** (local, LAN, or public) – sets bind address and default ports.
2. **Filesystem ownership** for container volumes.
3. **Exterior ports** for Auth (default 3784), World (8215), SOAP (7778), and MySQL (64306).
4. **Storage path** (default `./storage`) and backup retention.
5. **Module preset**. The wizard defaults to a safe set (Solo LFG, Solocraft, Autobalance, Transmog, NPC Buffer, Learn Spells, Fireworks). Manual mode lets you toggle more modules, while warning you about unsafe or incompatible ones.

### Module notes from the wizard

- **AHBot** – remains disabled until the upstream module exports `Addmod_ahbotScripts()` (linker failure otherwise).
- **Quest Count Level** – disabled: relies on deprecated ConfigMgr calls and fails to compile.
- **Eluna** – bundled with AzerothCore by default. To disable the runtime later, edit the `AC_ELUNA_ENABLED` flag under “Eluna runtime” in `.env`.
- Other disabled modules (Individual Progression, Breaking News, TimeIsTime, Pocket Portal, Random Enchants, NPC Beastmaster/Enchanter, Instance Reset, etc.) require additional SQL, DBC, or in-game configuration. Inline comments in `.env` describe these requirements.

When the wizard completes, it writes the fully populated `.env`. Re-run `./setup.sh` anytime you want to regenerate the file; make backups first if you have custom edits.


## 3. (Optional) Clone AzerothCore Source

Certain modules require recompiling the AzerothCore core. If you plan to enable any of them, clone/update the source repository first:

```bash
./scripts/setup-source.sh
```

This script:

- Reads `MODULES_REBUILD_SOURCE_PATH` (default `./source/azerothcore`).
- Clones or updates the repository (uses the Playerbot fork if `MODULE_PLAYERBOTS=1`).
- Ensures the desired branch is checked out.

You can rerun it whenever you need to pull upstream updates.


## 4. Deploy with `deploy.sh`

Use `deploy.sh` to perform a full module-aware deployment. Example:

```bash
./deploy.sh --profile modules
```

What the script does:

1. Stops any running stack (unless `--keep-running` is supplied) to avoid container-name conflicts.
2. Runs the modules manager (`docker compose --profile db --profile modules up ac-modules`) to clone missing modules, apply configuration, and execute module SQL.
3. Rebuilds AzerothCore from source if any C++ modules are enabled. The helper also tags the freshly-built images as `acore/ac-wotlk-{worldserver,authserver}:modules-latest` for subsequent compose runs.
4. Stages the runtime profile by invoking `./scripts/stage-modules.sh --yes`.
5. Tails the `ac-worldserver` logs by default (omit with `--no-watch`).

Useful flags:

- `--profile {standard|playerbots|modules}` – force a specific services profile instead of auto-detecting by module toggles.
- `--skip-rebuild` – skip the source rebuild even if modules demand it (not recommended unless you are certain rebuilt images already exist).
- `--keep-running` – do not stop existing containers before syncing modules (use sparingly; stale `ac-db-import` containers can block the rebuild stage).
- `--no-watch` – exit after staging without tailing worldserver logs.

All Docker Compose commands run with the project name derived from `COMPOSE_PROJECT_NAME` in `.env` (default `ac-compose`).


### If you prefer a health check after deployment

Run:

```bash
./verify-deployment.sh --skip-deploy --quick
```

This script inspects container health states and key ports without altering the running stack.


## 5. Service Inventory & Default Ports

| Service / Container        | Role                                | Ports (host → container) | Profile(s)                 |
|----------------------------|-------------------------------------|--------------------------|----------------------------|
| `ac-mysql`                 | MySQL 8.0 database                  | `64306 → 3306`           | `db`                       |
| `ac-db-import`             | One-shot DB import/update           | –                        | `db`                       |
| `ac-db-init`               | Schema bootstrap helper             | –                        | `db`                       |
| `ac-authserver`            | Auth server (no modules)            | `3784 → 3724`            | `services-standard`        |
| `ac-worldserver`           | World server (no modules)           | `8215 → 8085`, `7778 → 7878` (SOAP) | `services-standard`        |
| `ac-authserver-modules`    | Auth server w/ custom build         | `3784 → 3724`            | `services-modules`         |
| `ac-worldserver-modules`   | World server w/ custom build        | `8215 → 8085`, `7778 → 7878` | `services-modules`       |
| `ac-authserver-playerbots` | Playerbots auth image               | `3784 → 3724`            | `services-playerbots`      |
| `ac-worldserver-playerbots`| Playerbots world image              | `8215 → 8085`, `7778 → 7878` | `services-playerbots`   |
| `ac-client-data-standard`  | Client-data fetcher                 | –                        | `client-data`              |
| `ac-modules`               | Module management / SQL executor    | –                        | `modules`                  |
| `ac-phpmyadmin`            | phpMyAdmin UI                       | `8081 → 80`              | `tools`                    |
| `ac-keira3`                | Keira3 world editor                 | `4201 → 8080`            | `tools`                    |

Additional services (e.g., backups, monitoring) can be enabled by editing `.env` and the compose file as needed.


## 6. Manual Tasks & Advanced Options

- **Disabling Eluna**: Eluna’s runtime flags live near the end of `.env`. Set `AC_ELUNA_ENABLED=0` if you do not want Lua scripting loaded.
- **Enabling experimental modules**: Edit `.env` toggles. Review the inline comments carefully—some modules require additional SQL, DBC patches, or configuration files before they work safely.
- **Custom `.env` variants**: You can create `.env.custom` files and run `docker compose --env-file` if you maintain multiple environments. The setup wizard always writes `./.env`.
- **Manual source rebuild**: If you prefer to rebuild without staging services, run `./scripts/rebuild-with-modules.sh --yes`. The script now stops and cleans up its own compose project to avoid lingering containers.
- **Health check**: `verify-deployment.sh` can also be run without `--skip-deploy` to bring up a stack and verify container states using the default profiles.


## 7. Clean-Up & Re-running

- To tear down everything: `docker compose --profile db --profile services-standard --profile services-playerbots --profile services-modules --profile client-data --profile modules --profile tools down`.
- To force the module manager to re-run (e.g., after toggling modules in `.env`): `docker compose --profile db --profile modules up --build ac-modules`.
- Storage (logs, configs, client data) lives under `./storage` by default; remove directories carefully if you need a clean slate.


## 8. Further Reading

For a full description of individual modules, sample workflows, or deeper dive into AzerothCore internals, consult the original **V1 README** and linked documentation inside the `V1/` directory. Those docs provide module-specific CMake and SQL references you can adapt if you decide to maintain custom forks.

---

You now have a repeatable, script-driven deployment process:

1. Configure once with `setup.sh`.
2. (Optional) Pull upstream source via `scripts/setup-source.sh`.
3. Deploy and stage via `deploy.sh`.
4. Verify with `verify-deployment.sh` or directly inspect `docker compose ps`.

Happy adventuring!
