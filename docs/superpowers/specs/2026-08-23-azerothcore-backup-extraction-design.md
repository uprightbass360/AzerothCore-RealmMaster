# azerothcore-backup: standalone backup/restore for dockerized AzerothCore

**Date:** 2026-08-23
**Status:** Approved design, pending implementation
**Target repo:** https://github.com/uprightbass360/azerothcore-backup (created, empty)

## Purpose

Extract RealmMaster's hardened database backup/restore functionality into a
standalone tool that any dockerized AzerothCore stack can adopt by adding one
service block to a compose file. First-class integration targets:

1. Plain/upstream-style AC compose stacks (the standard acore docker layout:
   an `ac-database` MySQL service on a shared network, customized via the
   `docker-compose.override.yml` pattern)
2. Any similar stack with a reachable MySQL container

RealmMaster keeps its own inline copy for now; migrating it to consume this
tool is a deliberate later task, after the standalone tool has proven itself.

## Decisions (settled during brainstorming)

- **Separate repo**, publishing a Docker image; consumers never copy scripts
- **AzerothCore-focused**: database defaults `acore_auth acore_world
  acore_characters`, auto-detect of `acore_playerbots`, docs in AC terms
- **Restore = CLI + opt-in auto-restore** on empty database
- **NFS and standard mounts both first-class** for the backup volume
- **RealmMaster untouched** in this phase

## Repo layout

```
azerothcore-backup/
├── Dockerfile                    # FROM mysql:8.4 — scripts baked in
├── scripts/
│   ├── backup-scheduler.sh       # ported from RealmMaster (hardened version)
│   └── acbackup                  # CLI: list / verify / now / restore
├── examples/
│   ├── compose.yml               # minimal generic AC service block
│   └── compose.override.yml      # drop-in override for upstream-style AC stacks
├── test/                         # e2e compose + assertions (see Testing)
├── .github/workflows/ci.yml      # shellcheck + e2e matrix + publish
└── README.md
```

## Image

- **Base `mysql:8.4`** (newest LTS). Rationale: client tools (mysql,
  mysqldump) are guaranteed present and version-compatible dumping both 8.4
  and 8.0 servers (the two versions in common AC use); `gosu` ships in the official
  image, eliminating RealmMaster's runtime download of gosu from GitHub
  entirely; the base layer is typically already present on AC hosts.
- Entrypoint: fix ownership of `/backups` tier roots only (never recursive —
  NFS lesson), drop privileges via gosu to `PUID:PGID` (default 1000:1000),
  then either run the scheduler (default command) or `acbackup` (one-shot).
- `HEALTHCHECK` in the Dockerfile: DB reachable AND newest `*.sql.gz` younger
  than `BACKUP_HEALTHCHECK_MAX_MINUTES` (default 120), with a startup grace
  window.
- Published as `uprightbass360/azerothcore-backup:latest` + semver tags.

## Backup service (scheduler)

Direct port of RealmMaster's `backup-scheduler.sh` at its current hardened
state, minus RealmMaster-isms (no `/modules-meta` mount, no module SQL
awareness). All behavior preserved:

- Interval backups (default 60 min) into `hourly/`, retention
  `BACKUP_RETENTION_HOURS` (default 6)
- Daily at `BACKUP_DAILY_TIME` (default 09, zero-padding normalized, fires
  once per day at-or-after the hour, tracker seeded from disk) into `daily/`,
  retention `BACKUP_RETENTION_DAYS` (default 14)
- Monthly promotion of first complete daily each month into `monthly/`,
  retention `BACKUP_RETENTION_MONTHS` (default 12)
- Per-dump verification (gzip integrity + mysqldump completion trailer);
  `.backup_complete` marker written only when every database dumped AND
  verified; failed dumps deleted and recorded in `manifest.json`
  `failed_databases`
- `BACKUP_ALERT_WEBHOOK` (ntfy/Discord/Slack style: plain POST) fired on any
  failure
- `MYSQL_PWD` env for credentials — never on command lines
- Ownership-drift self-heal per backup directory (NFS root-squash tolerant)

### Configuration contract (env vars)

| Variable | Default | Notes |
|---|---|---|
| `MYSQL_HOST` | `ac-database` | matches the standard AC compose service name |
| `MYSQL_PORT` | `3306` | |
| `MYSQL_USER` | `root` | |
| `MYSQL_PASSWORD` | — | or `MYSQL_PASSWORD_FILE` for secrets |
| `BACKUP_DATABASES` | `acore_auth acore_world acore_characters` | space/comma separated |
| (auto) | | `acore_playerbots` auto-added when present |
| `BACKUP_INTERVAL_MINUTES` | `60` | |
| `BACKUP_RETENTION_HOURS` | `6` | |
| `BACKUP_RETENTION_DAYS` | `14` | |
| `BACKUP_RETENTION_MONTHS` | `12` | |
| `BACKUP_DAILY_TIME` | `09` | hour, container TZ |
| `BACKUP_ALERT_WEBHOOK` | empty | plain-text POST on failure |
| `AUTO_RESTORE` | `0` | see Restore |
| `PUID` / `PGID` | `1000` / `1000` | backup file ownership |
| `TZ` | `UTC` | |

Volume: `/backups` (named volume, bind mount, or NFS — all supported; no
flock dependence, tier-root-only chown).

## Restore

`acbackup` CLI, baked into the image. Invocable as `docker exec ac-backup
acbackup …` on a running service or as a one-shot `docker run`.

- `acbackup list` — all tiers (hourly/daily/monthly/manual): age, size,
  databases, complete/incomplete status
- `acbackup verify <dir|latest>` — marker + gzip + trailer for every dump
- `acbackup now [--label X]` — on-demand backup into `manual/`
- `acbackup restore <dir|latest> [--db NAME …] [--yes]` —
  - refuses incomplete backups (no marker, or failed verification)
  - takes a pre-restore safety backup into `manual/pre-restore-<ts>/` first
  - applies dumps (they carry `--add-drop-database`: clean drop-and-recreate)
  - interactive confirmation unless `--yes`

**Auto-restore** (`AUTO_RESTORE=1`): at container start, probe whether the
target databases exist and are non-trivial (test: `acore_auth.account` table
exists). If absent/empty AND a complete backup exists: restore the newest
complete backup, log loudly, fire the webhook. Never touches non-empty
databases; no marker files — the database itself is the state. Enables
"compose file + backup directory = rebuilt server".

## Upstream-style stack integration

`examples/compose.override.yml` — matches the `docker-compose.override.yml`
customization pattern used by standard AC docker stacks:

```yaml
services:
  ac-backup:
    image: uprightbass360/azerothcore-backup:latest
    container_name: ac-backup
    networks: [ac-network]
    environment:
      MYSQL_HOST: ac-database
      MYSQL_PASSWORD: ${DOCKER_DB_ROOT_PASSWORD:-password}
      BACKUP_ALERT_WEBHOOK: ${BACKUP_ALERT_WEBHOOK:-}
    volumes:
      - ${DOCKER_VOL_BACKUPS:-./backups}:/backups
    depends_on:
      ac-database:
        condition: service_healthy
    restart: always
```

Defaults are chosen so this block works with zero extra configuration on any
stack following the standard AC compose conventions (`ac-database` host
default, root user, standard AC database names, playerbots auto-detect).

## CI & testing

GitHub Actions in the new repo:

1. **Lint**: shellcheck on all scripts, hadolint on the Dockerfile
2. **e2e matrix** (mysql server `8.0` and `8.4`): compose up a server +
   backup service with a bind-mounted volume owned by a mismatched uid (NFS
   simulation); seed an AC-shaped schema incl. `acore_playerbots`; force an
   immediate backup; assert marker/manifest; corrupt a copy and assert
   `verify` fails it; `acbackup restore` into a wiped server; assert row
   counts match; test `AUTO_RESTORE=1` boot path on an empty server
3. **Publish** on main/tags: build + push `latest` and semver tags to Docker
   Hub (same credentials pattern as RealmMaster's workflow, current action
   majors, Dependabot enabled from day one)

## Error handling summary

- Any dump failure → no completion marker, manifest records it, webhook fires
- Restore refuses anything unverified; pre-restore safety backup always taken
- Auto-restore is opt-in, empty-DB-gated, loud
- Healthcheck goes unhealthy at 2h staleness (configurable)

## Out of scope (this phase)

- RealmMaster consuming the new image (later task)
- ExportBackup-style host-migration packaging (`backup-export/import`)
- Non-AzerothCore database layouts beyond `BACKUP_DATABASES` override
- Remote/offsite replication (S3, rsync targets)
