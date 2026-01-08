# Installing AzerothCore RealmMaster with Docker Compose

This guide mirrors the community “Installing AzerothCore using Docker” workflow so existing AzerothCore operators feel at home, while pointing to RealmMaster-specific tooling documented in our [README](../README.md). Everything below assumes Linux or WSL2; native Windows Docker Desktop is still unsupported.


## Pre-requisites

- **Docker Engine + Docker Compose v2** in their latest versions. RealmMaster inherits every requirement from the upstream guide; follow the [Quick Start](../README.md#quick-start) section to install dependencies and clone the repo.
- **Root (sudo) access** during Docker operations. Just like the upstream warning, we recommend standard Docker with `sudo` rather than the rootless variant, because several services (MySQL tmpfs, bind mounts) need elevated capabilities.
- **Hardware**: minimally 16 GB RAM and 32 GB free disk, as noted in [README → Quick Start](../README.md#quick-start). First-run provisioning downloads ~15 GB of client data and compiles modules when enabled.


## Compose File Layout

RealmMaster keeps the familiar `docker-compose.yml` at the repo root. Instead of editing the YAML directly, run `./setup.sh` (see [README → Getting Started](../README.md#getting-started)) to generate `.env`; every setting from storage paths and ports to module toggles lives there. This mirrors the upstream “use docker-compose.override.yml” advice while preserving a single declarative stack.

- **Security**: databases stay on the internal `azerothcore` bridge and never publish MySQL ports unless you explicitly set `COMPOSE_OVERRIDE_MYSQL_EXPOSE_ENABLED=1` in `.env`. Binary logging is disabled via `MYSQL_DISABLE_BINLOG=1`, matching the upstream recommendation for playerbots.
- **Storage**: bind mounts map to `storage/` and `local-storage/`, ensuring data survives container rebuilds just like the original bind-mount instructions. `ac-volume-init` and `ac-storage-init` bootstrap ownership so you do not need to chown paths manually.
- **Networks & profiles**: all services share the `azerothcore` bridge, and Compose profiles (`services-standard`, `services-playerbots`, `services-modules`, `tools`) let you enable only what you need, similar to copying multiple override files upstream.
- **Override toggles**: drop-in files under `compose-overrides/` (like `mysql-expose.yml` for port exposure or `worldserver-debug-logging.yml` for verbose logs) can be activated by setting `COMPOSE_OVERRIDE_<NAME>_ENABLED=1` in `.env`, so you can extend the stack without editing the main compose file.
- **Module manifest**: all module metadata lives in `config/module-manifest.json`; presets surfaced in `setup.sh` come from `config/module-profiles/*.json`, so you can adapt the same workflow the upstream document used by editing those files.

### Override Examples

RealmMaster ships with two opt-in overrides to demonstrate the pattern:

- `compose-overrides/mysql-expose.yml` (`COMPOSE_OVERRIDE_MYSQL_EXPOSE_ENABLED=1`) publishes MySQL on `${MYSQL_EXTERNAL_PORT}` for IDEs or external tooling.
- `compose-overrides/worldserver-debug-logging.yml` (`COMPOSE_OVERRIDE_WORLDSERVER_DEBUG_LOGGING_ENABLED=1`) bumps `AC_LOG_LEVEL` to `3` across every worldserver profile for troubleshooting.

Add your own overrides by dropping a `.yml` file into `compose-overrides/` with a `# override-flag: ...` header and toggling the matching env flag. All project scripts automatically include enabled overrides, so the workflow mirrors the upstream “override file” approach without manual compose arguments.

### Module Layout

- **Manifest**: `config/module-manifest.json` tracks every supported module (type, repo, dependencies). Edit this if you need to add or update modules—`scripts/python/modules.py` and all container helpers consume it automatically.
- **Presets**: `config/module-profiles/*.json` replaces the old `profiles/*.json`. Each preset defines a `modules` list plus optional `label/description/order`, and `setup.sh` surfaces them in the module-selection menu or via `--module-config <name>`.

Because the manifest/preset locations mirror the upstream structure conceptually, experienced users can jump straight into editing those files without re-learning the workflow.

Example excerpt (trimmed for clarity):

```yaml
services:
  ac-mysql:
    image: ${MYSQL_IMAGE}
    container_name: ac-mysql
    volumes:
      - mysql-data:/var/lib/mysql-persistent
      - ${HOST_ZONEINFO_PATH}:/usr/share/zoneinfo:ro
    command:
      - mysqld
      - --character-set-server=${MYSQL_CHARACTER_SET}
      - --collation-server=${MYSQL_COLLATION}
      - --innodb-buffer-pool-size=${MYSQL_INNODB_BUFFER_POOL_SIZE}
    healthcheck:
      test: ["CMD","sh","-c","mysqladmin ping -h localhost -u ${MYSQL_USER} -p${MYSQL_ROOT_PASSWORD} --silent || exit 1"]
    networks: [azerothcore]

  ac-db-import:
    image: ${AC_DB_IMPORT_IMAGE}
    depends_on:
      ac-mysql:
        condition: service_healthy
      ac-storage-init:
        condition: service_completed_successfully
    volumes:
      - ${STORAGE_PATH}/config:/azerothcore/env/dist/etc
      - ${STORAGE_PATH}/logs:/azerothcore/logs
      - mysql-data:/var/lib/mysql-persistent
```

> **Tip:** Need custom bind mounts for DBC overrides like in the upstream doc? Add them to `${STORAGE_PATH}/client-data` or mount extra read-only paths under the `ac-worldserver-*` service. RealmMaster already downloads `data.zip` via `ac-client-data-*` containers, so you can drop additional files beside the cached dataset.


## Service Roles (parallels to the original guide)

| Upstream Concept | RealmMaster Equivalent | Notes |
| ---------------- | ---------------------- | ----- |
| MySQL container with bind-mounted storage | `ac-mysql` + `ac-storage-init` | Bind mounts live under `storage/` and `local-storage/`; tmpfs keeps runtime data fast and is synced to disk on graceful shutdown. |
| Manual DB import container | `ac-db-import` & `ac-db-init` | Automatically imports schemas or restores from backups; disable by skipping the `db` profile if you truly want manual control. |
| World/Auth servers with optional DBC overrides | `ac-authserver-*` / `ac-worldserver-*` | Profile-based builds cover vanilla, playerbots, and custom module binaries. DBC overrides go into the shared client data mount just like upstream. |
| Client data bind mounts | `ac-client-data-standard` (or `-playerbots`) | Runs `scripts/bash/download-client-data.sh`, caches releases, and mounts them read-only into the worldserver. |
| Optional helpers (phpMyAdmin, scripts) | `ac-phpmyadmin`, `ac-keira3`, `scripts/bash/*.sh` | Enable via `--profile tools`. Credentials still come from `MYSQL_ROOT_PASSWORD`, identical to upstream instructions. |

For a full architecture diagram, cross-reference [README → Architecture Overview](../README.md#architecture-overview).

### Storage / Bind Mount Map

| Host Path | Mounted In | Purpose / Notes |
|-----------|------------|-----------------|
| `${STORAGE_PATH}/config` | `ac-authserver-*`, `ac-worldserver-*`, `ac-db-import`, `ac-db-guard`, `ac-post-install` | Holds `authserver.conf`, `worldserver.conf`, `dbimport.conf`, and module configs. Generated from the `.dist` templates during `setup.sh` / `auto-post-install.sh`. |
| `${STORAGE_PATH}/logs` | `ac-worldserver-*`, `ac-authserver-*`, `ac-db-import`, `ac-db-guard` | Persistent server logs (mirrors upstream `logs/` bind mount). |
| `${STORAGE_PATH}/modules` | `ac-worldserver-*`, `ac-db-import`, `ac-db-guard`, `ac-modules` | Cloned module repositories live here. `ac-modules` / `stage-modules.sh` sync this tree. |
| `${STORAGE_PATH}/lua_scripts` | `ac-worldserver-*` | Custom Lua scripts (same structure as upstream `lua_scripts`). |
| `${STORAGE_PATH}/backups` | `ac-db-import`, `ac-backup`, `ac-mysql` (via `mysql-data` volume) | Automatic hourly/daily SQL dumps. `ac-db-import` restores from here on cold start. |
| `${STORAGE_PATH}/client-data` | `ac-client-data-*`, `ac-worldserver-*`, `ac-authserver-*` | Cached `Data.zip` plus optional DBC/maps/vmaps overrides. Equivalent to mounting `data` in the original instructions. |
| `${STORAGE_PATH}/module-sql-updates` *(host literal path only used when you override the default)* | *(legacy, see below)* | Prior to this update, this path stayed under `storage/`. It now defaults to `${STORAGE_PATH_LOCAL}/module-sql-updates` so it can sit on a writable share even if `storage/` is NFS read-only. |
| `${STORAGE_PATH_LOCAL}/module-sql-updates` | `ac-db-import`, `ac-db-guard` (mounted as `/modules-sql`) | **New:** `stage-modules.sh` copies every staged `MODULE_*.sql` into this directory. The guard and importer copy from `/modules-sql` into `/azerothcore/data/sql/updates/*` before running `dbimport`, so historical module SQL is preserved across container rebuilds. |
| `${STORAGE_PATH_LOCAL}/client-data-cache` | `ac-client-data-*` | Download cache for `Data.zip`. Keeps the upstream client-data instructions intact. |
| `${STORAGE_PATH_LOCAL}/source/azerothcore-playerbots/data/sql` | `ac-db-import`, `ac-db-guard` | Mounted read-only so dbimport always sees the checked-out SQL (matches the upstream “mount the source tree” advice). |
| `mysql-data` (named volume) | `ac-mysql`, `ac-db-import`, `ac-db-init`, `ac-backup` | Stores the persistent InnoDB files. Runtime tmpfs lives inside the container, just like the original guide’s “tmpfs + bind mount” pattern. |

> Hosting storage over NFS/SMB? Point `STORAGE_PATH` at your read-only export and keep `STORAGE_PATH_LOCAL` on a writable tier for caches (`client-data-cache`, `module-sql-updates`, etc.). `stage-modules.sh` and `repair-storage-permissions.sh` respect those split paths.

## Familiar Workflow Using RealmMaster Commands

The upstream document introduced `up.sh`, `down.sh`, and `boot.sh`. RealmMaster provides higher-level wrappers while keeping the same mental model:

1. **Configure** – `./setup.sh` (interactive `.env` generator). Mirrors creating `docker-compose.override.yml` without editing YAML.
2. **Build (optional)** – `./build.sh` compiles images when playerbots or C++ modules are enabled, as described in [README → Getting Started → Step 2](../README.md#getting-started). Skip if you only need vanilla binaries.
3. **Deploy** – `./deploy.sh` chooses the right profile and runs `docker compose up -d --build`, equivalent to the upstream `up.sh`.
4. **Stop** – `./scripts/bash/stop-containers.sh` or `docker compose down` (from the README [Management Commands](../README.md#management-commands)), matching the upstream `down.sh`.
5. **Reboot** – run `./scripts/bash/stop-containers.sh && ./scripts/bash/start-containers.sh`, similar to their `boot.sh`.
6. **Status & Logs** – `./status.sh` summarizes container health and exposed ports (see [README → Management & Operations → Common Workflows](../README.md#management--operations)).

If you still prefer tiny wrappers, feel free to recreate the original scripts pointing at our compose file:

```bash
#!/usr/bin/env bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")"/.. && pwd)"
if [ -f "${PROJECT_DIR}/.env" ]; then
  set -a
  source "${PROJECT_DIR}/.env"
  set +a
else
  echo "Missing ${PROJECT_DIR}/.env" >&2
  exit 1
fi
docker compose -f "${PROJECT_DIR}/docker-compose.yml" \
  --profile services-standard \
  -p "${COMPOSE_PROJECT_NAME}" up -d --build
```


## Optional Make Targets

The original doc used `make start/stop/boot`. You can mirror that by wiring our scripts:

```make
start:
	@./deploy.sh

stop:
	@./scripts/bash/stop-containers.sh

boot:
	@./scripts/bash/stop-containers.sh && ./deploy.sh

boot.log:
	@./deploy.sh && docker logs -f ac-worldserver ||:
```

Run `sudo make start` from the repo root, just as the upstream doc suggested running `sudo make boot`.


## Where to Go Next

- **Post-Installation**: Creating accounts, editing `realmlist.wtf`, and enabling SOAP are documented in [README → Post-Installation Steps](../README.md#post-installation-steps).
- **Module Catalog**: Review every module shipped with RealmMaster under [README → Complete Module Catalog](../README.md#complete-module-catalog) before toggling flags in `.env`.
- **Script Reference**: For backups, migrations, and module management, see [README → Script Reference](../README.md#script-reference); it replaces the “useful scripts” appendix from the upstream doc.
- **Management & Ops**: Automated backups, status checks, and database tooling live in [README → Management & Operations](../README.md#management--operations), covering everything that used to be manual in the older guide.

By following this document side-by-side with the original AzerothCore instructions, seasoned developers can reuse their muscle memory while benefiting from RealmMaster’s automation and profile-driven compose stack.
