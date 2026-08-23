# azerothcore-backup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the standalone `azerothcore-backup` Docker image (scheduler + `acbackup` CLI + auto-restore) in the new repo `uprightbass360/azerothcore-backup`, with CI that lints, runs a real backup/restore e2e against MySQL 8.0 and 8.4, and publishes to Docker Hub.

**Architecture:** A single image based on `mysql:8.4` carrying three shell programs that share one library: `scripts/lib.sh` (connection, dump, verify, manifest, tier logic), `scripts/backup-scheduler.sh` (the long-running loop), and `scripts/acbackup` (list/verify/now/restore/auto-restore CLI). An entrypoint fixes tier-root ownership, drops privileges via gosu, and dispatches. Unit tests run the shell code against PATH-stubbed `mysql`/`mysqldump` with no Docker; the e2e runs the real image against real MySQL servers.

**Tech Stack:** Bash, mysql-client/mysqldump (from the `mysql:8.4` image), Docker + compose, GitHub Actions, shellcheck, hadolint.

**Spec:** `docs/superpowers/specs/2026-08-23-azerothcore-backup-extraction-design.md` (in the AzerothCore-RealmMaster repo — read it first).

## Global Constraints

- Work happens in a fresh clone of `https://github.com/uprightbass360/azerothcore-backup` (repo exists, empty, default branch `main`).
- Image base: `mysql:8.4` exactly. No runtime downloads at container start (gosu comes from the base image).
- Backup volume must work on NFS and normal mounts: never `chmod -R`/`chown -R` over the backup tree; only tier roots. No `flock`.
- Credentials: `MYSQL_PWD` env only — never `-p` on a command line. `MYSQL_PASSWORD_FILE` supported.
- Completion marker `.backup_complete` is written only when EVERY database dumped AND verified (gzip -t + "Dump completed" trailer).
- Env contract and defaults exactly as the spec table: `MYSQL_HOST=ac-database`, `MYSQL_PORT=3306`, `MYSQL_USER=root`, `BACKUP_DATABASES="acore_auth acore_world acore_characters"`, `BACKUP_INTERVAL_MINUTES=60`, `BACKUP_RETENTION_HOURS=6`, `BACKUP_RETENTION_DAYS=14`, `BACKUP_RETENTION_MONTHS=12`, `BACKUP_DAILY_TIME=09`, `BACKUP_ALERT_WEBHOOK=`, `AUTO_RESTORE=0`, `PUID=1000`, `PGID=1000`, `TZ=UTC`, `BACKUP_HEALTHCHECK_MAX_MINUTES=120`.
- `acore_playerbots` is auto-added to the database list when it exists on the server and is not already listed.
- All shell files must pass `shellcheck -S error`; Dockerfile must pass `hadolint` (warnings allowed, errors not).
- Every commit message ends with the trailer: `Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>`

---

### Task 1: Repo scaffold + shared library with stub-tested dump/verify core

**Files:**
- Create: `~/src/azerothcore-backup/` (clone), `scripts/lib.sh`, `test/unit/stubs/mysql`, `test/unit/stubs/mysqldump`, `test/unit/test-lib.sh`, `.gitignore`
- Test: `test/unit/test-lib.sh`

**Interfaces:**
- Produces (later tasks source `scripts/lib.sh` and rely on these exact names):
  - `log MSG...` — timestamped stdout line
  - `alert MSG...` — log + optional webhook POST (`BACKUP_ALERT_WEBHOOK`)
  - `init_credentials` — resolves `MYSQL_PASSWORD_FILE`→`MYSQL_PASSWORD`, exports `MYSQL_PWD`
  - `mysql_cmd ARGS...` / `mysqldump_cmd ARGS...` — client invocations carrying `-h$MYSQL_HOST -P$MYSQL_PORT -u$MYSQL_USER`
  - `db_exists NAME` → exit 0/1
  - `database_list` → one DB name per line (BACKUP_DATABASES parsed space/comma, playerbots auto-add)
  - `verify_dump FILE` → exit 0/1
  - `run_backup TARGET_DIR TIER_TYPE` → dumps every db into `TARGET_DIR`, writes `manifest.json` (`type`, `databases`, `failed_databases`, retention field per tier, performance block), writes `.backup_complete` only on full success, returns 1 if any db failed
  - `is_complete DIR` → exit 0/1 (marker exists)
  - `newest_complete_backup` → prints dir path of newest complete backup across `manual/ monthly/ daily/ hourly/` under `$BACKUP_DIR_BASE`, by directory basename timestamp; exit 1 if none
  - Globals: `BACKUP_DIR_BASE` (default `/backups`), `HOURLY_DIR`, `DAILY_DIR`, `MONTHLY_DIR`, `MANUAL_DIR`

- [ ] **Step 1: Clone the empty repo and scaffold**

```bash
cd ~/src && git clone https://github.com/uprightbass360/azerothcore-backup.git
cd azerothcore-backup
mkdir -p scripts test/unit/stubs examples .github/workflows
printf '%s\n' 'test/tmp/' > .gitignore
```

- [ ] **Step 2: Write PATH stubs for mysql/mysqldump**

`test/unit/stubs/mysql`:
```bash
#!/bin/bash
# Stub: understands the queries lib.sh issues. Behavior driven by env:
#   STUB_EXISTING_DBS  space-separated dbs that "exist" (USE succeeds)
#   STUB_ACCOUNT_TABLE 1 = acore_auth.account exists
args="$*"
case "$args" in
  *"USE "*)
    db=$(echo "$args" | sed -n 's/.*USE .\([a-z0-9_]*\).*/\1/p')
    for d in ${STUB_EXISTING_DBS:-}; do [ "$d" = "$db" ] && exit 0; done
    exit 1 ;;
  *information_schema.tables*account*) [ "${STUB_ACCOUNT_TABLE:-0}" = "1" ] && echo 1 || echo 0; exit 0 ;;
  *"SELECT VERSION()"*) echo "8.4.0-stub"; exit 0 ;;
  *size_mb*) echo "5.00"; exit 0 ;;
  *) exit 0 ;;
esac
```

`test/unit/stubs/mysqldump`:
```bash
#!/bin/bash
# Stub: last arg is the database name. STUB_FAIL_DB makes that db fail.
db="${*: -1}"
if [ "$db" = "${STUB_FAIL_DB:-}" ]; then echo "mysqldump: stub error" >&2; exit 2; fi
echo "-- MySQL dump (stub)"
echo "CREATE DATABASE IF NOT EXISTS \`$db\`;"
echo "-- Dump completed on stub"
```

Then: `chmod +x test/unit/stubs/mysql test/unit/stubs/mysqldump`

- [ ] **Step 3: Write the failing unit test**

`test/unit/test-lib.sh`:
```bash
#!/bin/bash
# Unit tests for scripts/lib.sh using PATH stubs. No Docker required.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
export PATH="$HERE/stubs:$PATH"
TMP="$ROOT/test/tmp/lib.$$"; mkdir -p "$TMP"; trap 'rm -rf "$TMP"' EXIT
export BACKUP_DIR_BASE="$TMP/backups"
export MYSQL_HOST=stub MYSQL_USER=root MYSQL_PASSWORD=x
export BACKUP_ALERT_WEBHOOK=""
export STUB_EXISTING_DBS="acore_auth acore_world acore_characters acore_playerbots"

pass=0; fail=0
ok(){ echo "  ok: $1"; pass=$((pass+1)); }
bad(){ echo "  FAIL: $1"; fail=$((fail+1)); }

source "$ROOT/scripts/lib.sh"
init_credentials

# database_list: defaults + playerbots auto-add
list=$(database_list | tr '\n' ' ')
[ "$list" = "acore_auth acore_world acore_characters acore_playerbots " ] \
  && ok "database_list defaults + playerbots" || bad "database_list got: $list"

# database_list: explicit BACKUP_DATABASES, comma form, no duplicate playerbots
list=$(BACKUP_DATABASES="acore_auth,acore_playerbots" database_list | tr '\n' ' ')
[ "$list" = "acore_auth acore_playerbots " ] \
  && ok "database_list comma + no dup" || bad "database_list custom got: $list"

# verify_dump: good and truncated
printf -- '-- dump\n-- Dump completed on x\n' | gzip > "$TMP/good.sql.gz"
printf -- '-- dump\nno trailer\n' | gzip > "$TMP/trunc.sql.gz"
verify_dump "$TMP/good.sql.gz" && ok "verify_dump accepts complete" || bad "verify_dump rejected good"
verify_dump "$TMP/trunc.sql.gz" && bad "verify_dump accepted truncated" || ok "verify_dump rejects truncated"

# run_backup success: marker + manifest type + empty failed list
run_backup "$BACKUP_DIR_BASE/hourly/one" interval >/dev/null 2>&1
[ -f "$BACKUP_DIR_BASE/hourly/one/.backup_complete" ] && ok "marker on success" || bad "no marker on success"
python3 - "$BACKUP_DIR_BASE/hourly/one/manifest.json" <<'PY' && ok "manifest valid+correct" || bad "manifest bad"
import json,sys
m=json.load(open(sys.argv[1]))
assert m["type"]=="interval" and m["failed_databases"]==[] and "retention_hours" in m
PY

# run_backup failure: no marker, failed db recorded, dump removed
STUB_FAIL_DB=acore_world run_backup "$BACKUP_DIR_BASE/hourly/two" interval >/dev/null 2>&1
[ ! -f "$BACKUP_DIR_BASE/hourly/two/.backup_complete" ] && ok "no marker on failure" || bad "marker written on failure"
[ ! -f "$BACKUP_DIR_BASE/hourly/two/acore_world.sql.gz" ] && ok "failed dump removed" || bad "failed dump kept"
python3 - "$BACKUP_DIR_BASE/hourly/two/manifest.json" <<'PY' && ok "failed_databases recorded" || bad "failed_databases wrong"
import json,sys; assert json.load(open(sys.argv[1]))["failed_databases"]==["acore_world"]
PY

# newest_complete_backup: prefers newest complete across tiers, skips incomplete
mkdir -p "$BACKUP_DIR_BASE/daily/20260101_000000" && touch "$BACKUP_DIR_BASE/daily/20260101_000000/.backup_complete"
mkdir -p "$BACKUP_DIR_BASE/manual/20270101_000000"   # newer but incomplete
n=$(newest_complete_backup)
case "$n" in */hourly/one) ok "newest_complete_backup picks newest complete";; *) bad "newest picked: $n";; esac

echo; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
```

Then: `chmod +x test/unit/test-lib.sh`

- [ ] **Step 4: Run test to verify it fails**

Run: `bash test/unit/test-lib.sh`
Expected: FAIL immediately — `scripts/lib.sh: No such file or directory`

- [ ] **Step 5: Write `scripts/lib.sh`**

Port from `~/src/AzerothCore-RealmMaster/scripts/bash/backup-scheduler.sh` (the hardened version — read it for reference), restructured as a sourceable library:

```bash
#!/bin/bash
# azerothcore-backup shared library. Source this; do not execute.

BACKUP_DIR_BASE="${BACKUP_DIR_BASE:-/backups}"
HOURLY_DIR="$BACKUP_DIR_BASE/hourly"
DAILY_DIR="$BACKUP_DIR_BASE/daily"
MONTHLY_DIR="$BACKUP_DIR_BASE/monthly"
MANUAL_DIR="$BACKUP_DIR_BASE/manual"
MYSQL_HOST="${MYSQL_HOST:-ac-database}"
MYSQL_PORT="${MYSQL_PORT:-3306}"
MYSQL_USER="${MYSQL_USER:-root}"
RETENTION_HOURS="${BACKUP_RETENTION_HOURS:-6}"
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-14}"
RETENTION_MONTHS="${BACKUP_RETENTION_MONTHS:-12}"
BACKUP_ALERT_WEBHOOK="${BACKUP_ALERT_WEBHOOK:-}"

log() { echo "[$(date '+%F %T')] $*"; }

alert() {
  log "🚨 $*"
  if [ -n "$BACKUP_ALERT_WEBHOOK" ] && command -v curl >/dev/null 2>&1; then
    curl -fsS -m 10 -d "azerothcore-backup: $*" "$BACKUP_ALERT_WEBHOOK" >/dev/null 2>&1 || \
      log "⚠️  Failed to deliver alert webhook"
  fi
}

init_credentials() {
  if [ -n "${MYSQL_PASSWORD_FILE:-}" ] && [ -f "$MYSQL_PASSWORD_FILE" ]; then
    MYSQL_PASSWORD="$(cat "$MYSQL_PASSWORD_FILE")"
  fi
  export MYSQL_PWD="${MYSQL_PASSWORD:-}"
}

mysql_cmd() { mysql -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" "$@"; }
mysqldump_cmd() { mysqldump -h"$MYSQL_HOST" -P"$MYSQL_PORT" -u"$MYSQL_USER" "$@"; }

db_exists() {
  local name="$1"
  [ -z "$name" ] && return 1
  mysql_cmd -e "USE \`${name//\`/}\`;" >/dev/null 2>&1
}

database_list() {
  local raw="${BACKUP_DATABASES:-acore_auth acore_world acore_characters}"
  local -a dbs=()
  local d
  declare -A seen=()
  for d in ${raw//,/ }; do
    [ -n "$d" ] || continue
    [ -n "${seen[$d]:-}" ] && continue
    dbs+=("$d"); seen[$d]=1
  done
  if [ -z "${seen[acore_playerbots]:-}" ] && db_exists acore_playerbots; then
    dbs+=("acore_playerbots")
    log "Detected optional database: acore_playerbots (will be backed up)" >&2
  fi
  printf '%s\n' "${dbs[@]}"
}

# A dump is only trustworthy if the gzip stream is intact and mysqldump
# reached its completion trailer (a truncated dump has neither).
verify_dump() {
  local file="$1"
  gunzip -t "$file" 2>/dev/null || return 1
  zcat "$file" 2>/dev/null | tail -1 | grep -q "Dump completed" || return 1
}

is_complete() { [ -f "$1/.backup_complete" ]; }

# run_backup TARGET_DIR TIER_TYPE — dump+verify every database.
# Marker only on full success. Returns 1 if any database failed.
run_backup() {
  local target_dir="$1" tier_type="$2"
  local ts; ts=$(basename "$target_dir")
  mkdir -p "$target_dir"
  log "Starting ${tier_type} backup to $target_dir"
  local -a dbs failed_dbs=()
  mapfile -t dbs < <(database_list)
  local t0; t0=$(date +%s)
  local total_mb=0
  local db
  for db in "${dbs[@]}"; do
    log "Backing up database: $db"
    local size_mb
    size_mb=$(mysql_cmd -s -N -e "SELECT ROUND(SUM(data_length + index_length)/1024/1024,2) AS size_mb FROM information_schema.tables WHERE table_schema = '$db';" 2>/dev/null || echo 0)
    if mysqldump_cmd --single-transaction --routines --triggers --events \
         --hex-blob --quick --lock-tables=false \
         --add-drop-database --databases "$db" 2>/dev/null \
         | gzip -c > "$target_dir/${db}.sql.gz" \
       && verify_dump "$target_dir/${db}.sql.gz"; then
      total_mb=$(awk -v a="$total_mb" -v b="$size_mb" 'BEGIN{printf "%.2f", a+b}')
      log "✅ Backed up and verified $db (${size_mb}MB)"
    else
      log "❌ Failed to back up $db (dump error or verification failure)"
      failed_dbs+=("$db")
      rm -f "$target_dir/${db}.sql.gz" 2>/dev/null || true
    fi
  done
  local dur=$(( $(date +%s) - t0 ))
  local size; size=$(du -sh "$target_dir" 2>/dev/null | cut -f1)
  local mysql_ver; mysql_ver=$(mysql_cmd -s -N -e 'SELECT VERSION();' 2>/dev/null || echo unknown)
  local rate; rate=$(awk -v u="$total_mb" -v d="$dur" 'BEGIN{printf "%.2f", (d>0)?u/d:0}')
  local retention_field="\"retention_days\": ${RETENTION_DAYS}"
  case "$tier_type" in
    hourly|interval) retention_field="\"retention_hours\": ${RETENTION_HOURS}" ;;
    monthly)         retention_field="\"retention_months\": ${RETENTION_MONTHS}" ;;
    manual)          retention_field="\"retention\": \"manual\"" ;;
  esac
  {
    printf '{\n  "timestamp": "%s",\n  "type": "%s",\n' "$ts" "$tier_type"
    printf '  "databases": [%s],\n' "$(printf '"%s",' "${dbs[@]}" | sed 's/,$//')"
    if [ ${#failed_dbs[@]} -eq 0 ]; then printf '  "failed_databases": [],\n'
    else printf '  "failed_databases": [%s],\n' "$(printf '"%s",' "${failed_dbs[@]}" | sed 's/,$//')"; fi
    printf '  "backup_size": "%s",\n  %s,\n  "mysql_version": "%s",\n' "$size" "$retention_field" "$mysql_ver"
    printf '  "performance": {"duration_seconds": %s, "uncompressed_size_mb": %s, "throughput_mb_per_second": %s}\n}\n' "$dur" "$total_mb" "$rate"
  } > "$target_dir/manifest.json"
  # Ownership drift self-heal (NFS root-squash tolerant): this dir only.
  if find "$target_dir" ! -user "$(id -un)" -print -quit 2>/dev/null | grep -q .; then
    chown -R "$(id -u):$(id -g)" "$target_dir" 2>/dev/null || true
    chmod -R u+rwX,g+rX "$target_dir" 2>/dev/null || true
  fi
  if [ ${#failed_dbs[@]} -eq 0 ]; then
    touch "$target_dir/.backup_complete"
    log "Backup complete: $target_dir (size ${size}, ${dur}s)"
    return 0
  fi
  alert "${tier_type} backup ${ts} INCOMPLETE - failed: ${failed_dbs[*]} (no completion marker written)"
  return 1
}

# Newest complete backup across all tiers, by basename timestamp.
newest_complete_backup() {
  local d best="" best_ts=""
  for d in "$MANUAL_DIR"/*/ "$MONTHLY_DIR"/*/ "$DAILY_DIR"/*/ "$HOURLY_DIR"/*/; do
    [ -d "$d" ] || continue
    is_complete "$d" || continue
    local ts; ts=$(basename "$d")
    if [ -z "$best_ts" ] || [[ "$ts" > "$best_ts" ]]; then best_ts="$ts"; best="${d%/}"; fi
  done
  [ -n "$best" ] && echo "$best" || return 1
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `bash test/unit/test-lib.sh`
Expected: `passed=10 failed=0`, exit 0. Also run `shellcheck -S error scripts/lib.sh test/unit/test-lib.sh` — clean.

- [ ] **Step 7: Commit**

```bash
git add .gitignore scripts/lib.sh test/
git commit -m "feat: shared backup library with verified dumps and honest markers

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 2: Scheduler loop

**Files:**
- Create: `scripts/backup-scheduler.sh`
- Test: `test/unit/test-scheduler.sh`

**Interfaces:**
- Consumes: everything from `scripts/lib.sh` (Task 1)
- Produces: `scripts/backup-scheduler.sh` — long-running process; also honors `SCHEDULER_ONE_SHOT=1` (run one interval backup + cleanup + exit; used by tests and `acbackup now` is separate)

- [ ] **Step 1: Write the failing test**

`test/unit/test-scheduler.sh`:
```bash
#!/bin/bash
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
export PATH="$HERE/stubs:$PATH"
TMP="$ROOT/test/tmp/sched.$$"; mkdir -p "$TMP"; trap 'rm -rf "$TMP"' EXIT
export BACKUP_DIR_BASE="$TMP/backups" MYSQL_HOST=stub MYSQL_USER=root MYSQL_PASSWORD=x
export STUB_EXISTING_DBS="acore_auth acore_world acore_characters"
pass=0; fail=0
ok(){ echo "  ok: $1"; pass=$((pass+1)); }; bad(){ echo "  FAIL: $1"; fail=$((fail+1)); }

# One-shot mode: performs an interval backup then exits 0
SCHEDULER_ONE_SHOT=1 bash "$ROOT/scripts/backup-scheduler.sh" >/dev/null 2>&1
n=$(find "$BACKUP_DIR_BASE/hourly" -mindepth 1 -maxdepth 1 -type d | wc -l)
[ "$n" -eq 1 ] && ok "one-shot produced one interval backup" || bad "expected 1 hourly dir, got $n"
d=$(find "$BACKUP_DIR_BASE/hourly" -mindepth 1 -maxdepth 1 -type d)
[ -f "$d/.backup_complete" ] && ok "one-shot backup complete" || bad "one-shot backup incomplete"

# Tier dirs all exist after startup
for t in hourly daily monthly manual; do
  [ -d "$BACKUP_DIR_BASE/$t" ] && ok "tier dir $t created" || bad "tier dir $t missing"
done

# DAILY_TIME normalization: "9" and "09" both become "09"
line=$(BACKUP_DAILY_TIME=9 SCHEDULER_ONE_SHOT=1 bash "$ROOT/scripts/backup-scheduler.sh" 2>/dev/null | grep "scheduler starting")
echo "$line" | grep -q "at 09:00" && ok "DAILY_TIME zero-padded" || bad "DAILY_TIME wrong: $line"

echo; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
```

Then: `chmod +x test/unit/test-scheduler.sh`

- [ ] **Step 2: Run test to verify it fails**

Run: `bash test/unit/test-scheduler.sh`
Expected: FAIL — `scripts/backup-scheduler.sh: No such file or directory`

- [ ] **Step 3: Write `scripts/backup-scheduler.sh`**

```bash
#!/bin/bash
# azerothcore-backup scheduler: interval + daily + monthly tiers.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
init_credentials

# Force base-10 (a bare printf %02d rejects "09" as invalid octal)
DAILY_TIME=$(printf '%02d' "$((10#${BACKUP_DAILY_TIME:-09}))" 2>/dev/null || echo "09")
BACKUP_INTERVAL_MINUTES="${BACKUP_INTERVAL_MINUTES:-60}"

mkdir -p "$HOURLY_DIR" "$DAILY_DIR" "$MONTHLY_DIR" "$MANUAL_DIR"

cleanup_old() {
  find "$HOURLY_DIR" -mindepth 1 -maxdepth 1 -type d -mmin +$((RETENTION_HOURS*60)) -exec rm -rf {} + 2>/dev/null || true
  find "$DAILY_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +"$RETENTION_DAYS" -exec rm -rf {} + 2>/dev/null || true
  find "$MONTHLY_DIR" -mindepth 1 -maxdepth 1 -type d -mtime +$((RETENTION_MONTHS*31)) -exec rm -rf {} + 2>/dev/null || true
}

# Promote the first complete daily backup of each month into the monthly tier.
promote_monthly() {
  local month; month=$(date '+%Y%m')
  find "$MONTHLY_DIR" -mindepth 1 -maxdepth 1 -type d -name "${month}*" -print -quit 2>/dev/null | grep -q . && return 0
  local candidate
  candidate=$(find "$DAILY_DIR" -mindepth 1 -maxdepth 1 -type d -name "${month}*" 2>/dev/null | sort | while read -r d; do
    is_complete "$d" && echo "$d" && break
  done)
  if [ -n "$candidate" ]; then
    if cp -a "$candidate" "$MONTHLY_DIR/$(basename "$candidate")"; then
      log "📦 Promoted $(basename "$candidate") to monthly tier"
    else
      log "⚠️  Failed to promote $(basename "$candidate") to monthly tier"
    fi
  fi
}

if [ "${SCHEDULER_ONE_SHOT:-0}" = "1" ]; then
  log "Backup scheduler starting: interval(${BACKUP_INTERVAL_MINUTES}m), daily(${RETENTION_DAYS}d at ${DAILY_TIME}:00), monthly(${RETENTION_MONTHS}mo)"
  run_backup "$HOURLY_DIR/$(date '+%Y%m%d_%H%M%S')" interval
  rc=$?
  cleanup_old
  exit "$rc"
fi

log "Backup scheduler starting: interval(${BACKUP_INTERVAL_MINUTES}m), daily(${RETENTION_DAYS}d at ${DAILY_TIME}:00), monthly(${RETENTION_MONTHS}mo)"
last_backup=$(date +%s)
# Seed the daily tracker from disk so a restart neither skips nor duplicates.
last_daily_date=""
if find "$DAILY_DIR" -mindepth 1 -maxdepth 1 -type d -name "$(date '+%Y%m%d')_*" -print -quit 2>/dev/null | grep -q .; then
  last_daily_date=$(date '+%F')
fi
log "ℹ️  First backup will run in ${BACKUP_INTERVAL_MINUTES} minutes"

while true; do
  now=$(date +%s); hour=$(date '+%H'); today=$(date '+%F')
  if [ $((now - last_backup)) -ge $((BACKUP_INTERVAL_MINUTES * 60)) ]; then
    run_backup "$HOURLY_DIR/$(date '+%Y%m%d_%H%M%S')" interval || true
    last_backup=$now
  fi
  # Daily fires once per day at-or-after DAILY_TIME (date-tracked, so a slow
  # interval backup spanning the top of the hour cannot skip the day).
  if [ "$hour" -ge "$DAILY_TIME" ] 2>/dev/null && [ "$last_daily_date" != "$today" ]; then
    run_backup "$DAILY_DIR/$(date '+%Y%m%d_%H%M%S')" daily || true
    last_daily_date="$today"
    promote_monthly
  fi
  cleanup_old
  sleep 60
done
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash test/unit/test-scheduler.sh && bash test/unit/test-lib.sh`
Expected: both `failed=0`. Also `shellcheck -S error scripts/backup-scheduler.sh` — clean.

- [ ] **Step 5: Commit**

```bash
git add scripts/backup-scheduler.sh test/unit/test-scheduler.sh
git commit -m "feat: scheduler loop with interval/daily/monthly tiers

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 3: acbackup CLI (list / verify / now / restore / auto-restore)

**Files:**
- Create: `scripts/acbackup`
- Test: `test/unit/test-acbackup.sh`

**Interfaces:**
- Consumes: `scripts/lib.sh` (Task 1)
- Produces: `scripts/acbackup` executable with subcommands:
  - `acbackup list`
  - `acbackup verify <dir|latest>` → exit 0 complete+verified, 1 otherwise
  - `acbackup now [--label NAME]` → backup into `$MANUAL_DIR/<NAME>-<ts>` (default label `manual`)
  - `acbackup restore <dir|latest> [--db NAME]... [--yes] [--no-safety-backup]` → exit 0 on success
  - `acbackup auto-restore` → used by entrypoint; restores newest complete backup only when the probe table is absent (`AUTO_RESTORE_PROBE`, default `acore_auth.account`); exit 0 in all no-op cases

- [ ] **Step 1: Write the failing test**

`test/unit/test-acbackup.sh`:
```bash
#!/bin/bash
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; ROOT="$(cd "$HERE/../.." && pwd)"
export PATH="$HERE/stubs:$PATH"
TMP="$ROOT/test/tmp/cli.$$"; mkdir -p "$TMP"; trap 'rm -rf "$TMP"' EXIT
export BACKUP_DIR_BASE="$TMP/backups" MYSQL_HOST=stub MYSQL_USER=root MYSQL_PASSWORD=x
export STUB_EXISTING_DBS="acore_auth acore_world acore_characters"
CLI="$ROOT/scripts/acbackup"
pass=0; fail=0
ok(){ echo "  ok: $1"; pass=$((pass+1)); }; bad(){ echo "  FAIL: $1"; fail=$((fail+1)); }

# 'now' creates a complete manual backup with label
"$CLI" now --label pretest >/dev/null 2>&1
d=$(find "$BACKUP_DIR_BASE/manual" -mindepth 1 -maxdepth 1 -type d -name 'pretest-*' | head -1)
[ -n "$d" ] && [ -f "$d/.backup_complete" ] && ok "now: labeled complete backup" || bad "now failed"

# 'verify' passes the good backup, fails a corrupted copy
"$CLI" verify "$d" >/dev/null 2>&1 && ok "verify accepts complete backup" || bad "verify rejected good"
cp -r "$d" "$TMP/corrupt"; truncate -s 20 "$TMP/corrupt/acore_world.sql.gz"
"$CLI" verify "$TMP/corrupt" >/dev/null 2>&1 && bad "verify accepted corrupt" || ok "verify rejects corrupt"

# 'verify latest' resolves to newest complete
"$CLI" verify latest >/dev/null 2>&1 && ok "verify latest resolves" || bad "verify latest failed"

# 'list' shows the backup and its status
"$CLI" list 2>/dev/null | grep -q "pretest" && ok "list shows backup" || bad "list missing backup"

# 'restore' refuses an incomplete backup
mkdir -p "$BACKUP_DIR_BASE/manual/20200101_000000"   # no marker
"$CLI" restore "$BACKUP_DIR_BASE/manual/20200101_000000" --yes --no-safety-backup >/dev/null 2>&1 \
  && bad "restore accepted incomplete" || ok "restore refuses incomplete"

# 'restore --yes' on complete backup: stub mysql accepts piped input -> success
"$CLI" restore "$d" --yes --no-safety-backup >/dev/null 2>&1 && ok "restore applies complete backup" || bad "restore failed"

# 'restore' without --yes and no TTY: refuses (no hang)
echo | "$CLI" restore "$d" --no-safety-backup >/dev/null 2>&1 && bad "restore ran without confirmation" || ok "restore requires confirmation"

# auto-restore: probe says empty -> restores; probe says populated -> no-op
out=$(STUB_ACCOUNT_TABLE=0 "$CLI" auto-restore 2>&1); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -qi "restoring" && ok "auto-restore restores when empty" || bad "auto-restore empty path: rc=$rc"
out=$(STUB_ACCOUNT_TABLE=1 "$CLI" auto-restore 2>&1); rc=$?
[ "$rc" -eq 0 ] && echo "$out" | grep -qi "populated" && ok "auto-restore no-op when populated" || bad "auto-restore populated path: rc=$rc"

echo; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
```

Then: `chmod +x test/unit/test-acbackup.sh`

- [ ] **Step 2: Run test to verify it fails**

Run: `bash test/unit/test-acbackup.sh`
Expected: FAIL — `scripts/acbackup: No such file or directory`

- [ ] **Step 3: Write `scripts/acbackup`**

```bash
#!/bin/bash
# acbackup — list / verify / now / restore / auto-restore for azerothcore-backup.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$SCRIPT_DIR/lib.sh"
init_credentials

usage() {
  cat <<'EOF'
Usage: acbackup <command> [args]

Commands:
  list                          Show all backups in every tier with status
  verify <dir|latest>           Check marker + gzip + dump trailer of a backup
  now [--label NAME]            Take an on-demand backup into manual/
  restore <dir|latest> [opts]   Restore a backup into MySQL
      --db NAME                 Restore only this database (repeatable)
      --yes                     Skip interactive confirmation
      --no-safety-backup        Skip the automatic pre-restore backup
  auto-restore                  Restore newest complete backup if DB is empty
                                (probe table: $AUTO_RESTORE_PROBE)
EOF
  exit 1
}

resolve_dir() {
  local arg="$1"
  if [ "$arg" = "latest" ]; then
    newest_complete_backup || { log "❌ No complete backup found in $BACKUP_DIR_BASE"; exit 1; }
  else
    [ -d "$arg" ] || { log "❌ Not a directory: $arg"; exit 1; }
    echo "${arg%/}"
  fi
}

cmd_list() {
  local tier d status size age
  for tier in hourly daily monthly manual; do
    local dir="$BACKUP_DIR_BASE/$tier"
    [ -d "$dir" ] || continue
    echo "== $tier =="
    local found=0
    for d in "$dir"/*/; do
      [ -d "$d" ] || continue
      found=1
      status=incomplete; is_complete "$d" && status=complete
      size=$(du -sh "$d" 2>/dev/null | cut -f1)
      age=$(basename "$d")
      printf '  %s  %-10s %s\n' "$age" "$status" "$size"
    done
    [ "$found" -eq 0 ] && echo "  (none)"
  done
}

cmd_verify() {
  local dir; dir=$(resolve_dir "${1:?usage: acbackup verify <dir|latest>}")
  is_complete "$dir" || { log "❌ $dir has no completion marker"; return 1; }
  local f bad=0
  for f in "$dir"/*.sql.gz; do
    [ -f "$f" ] || { log "❌ no dumps in $dir"; return 1; }
    if verify_dump "$f"; then log "✅ $(basename "$f") verified"
    else log "❌ $(basename "$f") FAILED verification"; bad=1; fi
  done
  [ "$bad" -eq 0 ] && log "✅ $dir verified" || return 1
}

cmd_now() {
  local label="manual"
  while [ $# -gt 0 ]; do case "$1" in
    --label) label="${2:?--label needs a value}"; shift 2;;
    *) usage;;
  esac; done
  mkdir -p "$MANUAL_DIR"
  run_backup "$MANUAL_DIR/${label}-$(date '+%Y%m%d_%H%M%S')" manual
}

cmd_restore() {
  local target="${1:?usage: acbackup restore <dir|latest>}"; shift
  local -a only_dbs=()
  local yes=0 safety=1
  while [ $# -gt 0 ]; do case "$1" in
    --db) only_dbs+=("${2:?--db needs a value}"); shift 2;;
    --yes) yes=1; shift;;
    --no-safety-backup) safety=0; shift;;
    *) usage;;
  esac; done
  local dir; dir=$(resolve_dir "$target")
  is_complete "$dir" || { log "❌ Refusing to restore: $dir has no completion marker"; return 1; }
  local -a files=()
  local f
  for f in "$dir"/*.sql.gz; do
    [ -f "$f" ] || continue
    if [ ${#only_dbs[@]} -gt 0 ]; then
      local db_name; db_name=$(basename "$f" .sql.gz)
      local want=0 o; for o in "${only_dbs[@]}"; do [ "$o" = "$db_name" ] && want=1; done
      [ "$want" -eq 1 ] || continue
    fi
    verify_dump "$f" || { log "❌ Refusing to restore: $(basename "$f") failed verification"; return 1; }
    files+=("$f")
  done
  [ ${#files[@]} -gt 0 ] || { log "❌ Nothing to restore from $dir"; return 1; }
  log "Restore plan from $dir:"
  for f in "${files[@]}"; do log "  - $(basename "$f" .sql.gz)"; done
  if [ "$yes" -ne 1 ]; then
    if [ -t 0 ]; then
      read -r -p "Type RESTORE to proceed (drops and recreates these databases): " reply
      [ "$reply" = "RESTORE" ] || { log "Cancelled."; return 1; }
    else
      log "❌ Confirmation required: re-run with --yes"; return 1
    fi
  fi
  if [ "$safety" -eq 1 ]; then
    log "Taking pre-restore safety backup..."
    run_backup "$MANUAL_DIR/pre-restore-$(date '+%Y%m%d_%H%M%S')" manual || \
      log "⚠️  Pre-restore safety backup incomplete (continuing; source backup is verified)"
  fi
  for f in "${files[@]}"; do
    log "Restoring $(basename "$f" .sql.gz)..."
    if ! zcat "$f" | mysql_cmd; then
      alert "restore of $(basename "$f") from $dir FAILED"
      return 1
    fi
  done
  log "✅ Restore complete from $dir"
}

cmd_auto_restore() {
  local probe="${AUTO_RESTORE_PROBE:-acore_auth.account}"
  local schema="${probe%%.*}" table="${probe##*.}"
  local n
  n=$(mysql_cmd -s -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='$schema' AND table_name='$table';" 2>/dev/null || echo probe-failed)
  case "$n" in
    1) log "Database populated ($probe exists) - auto-restore not needed"; return 0;;
    0) : ;;
    *) log "⚠️  Auto-restore probe failed (cannot reach MySQL); skipping"; return 0;;
  esac
  local dir
  if ! dir=$(newest_complete_backup); then
    log "Database empty but no complete backup available - starting fresh"
    return 0
  fi
  alert "auto-restore: database empty, restoring newest complete backup $(basename "$dir")"
  log "Restoring $dir ..."
  cmd_restore "$dir" --yes --no-safety-backup
}

cmd="${1:-}"; shift 2>/dev/null || true
case "$cmd" in
  list) cmd_list "$@";;
  verify) cmd_verify "$@";;
  now) cmd_now "$@";;
  restore) cmd_restore "$@";;
  auto-restore) cmd_auto_restore "$@";;
  *) usage;;
esac
```

Then: `chmod +x scripts/acbackup`

- [ ] **Step 4: Run all unit tests to verify they pass**

Run: `bash test/unit/test-acbackup.sh && bash test/unit/test-lib.sh && bash test/unit/test-scheduler.sh`
Expected: all `failed=0`. `shellcheck -S error scripts/acbackup` — clean.

- [ ] **Step 5: Commit**

```bash
git add scripts/acbackup test/unit/test-acbackup.sh
git commit -m "feat: acbackup CLI - list, verify, now, restore, auto-restore

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 4: Image (Dockerfile, entrypoint, healthcheck)

**Files:**
- Create: `Dockerfile`, `entrypoint.sh`, `scripts/healthcheck.sh`

**Interfaces:**
- Consumes: `scripts/*` from Tasks 1-3
- Produces: image `azerothcore-backup:dev` (local tag for e2e). Container contract: default command runs the scheduler; `docker exec <c> acbackup ...` works; `AUTO_RESTORE=1` triggers `acbackup auto-restore` before the scheduler starts; `PUID`/`PGID` own `/backups` output.

- [ ] **Step 1: Write `entrypoint.sh`**

```bash
#!/bin/bash
# Entrypoint: fix tier-root ownership, drop privileges, dispatch.
set -u

PUID="${PUID:-1000}"
PGID="${PGID:-1000}"
BACKUP_DIR_BASE="${BACKUP_DIR_BASE:-/backups}"

# Tier roots only - never recursive over months of (possibly NFS) backups.
mkdir -p "$BACKUP_DIR_BASE"/{hourly,daily,monthly,manual}
chown "$PUID:$PGID" "$BACKUP_DIR_BASE" "$BACKUP_DIR_BASE"/{hourly,daily,monthly,manual} 2>/dev/null || true
chmod u+rwx "$BACKUP_DIR_BASE" "$BACKUP_DIR_BASE"/{hourly,daily,monthly,manual} 2>/dev/null || true

run_as() { gosu "$PUID:$PGID" "$@"; }

if [ "$#" -gt 0 ] && [ "$1" != "scheduler" ]; then
  # One-shot mode: e.g. `docker run ... acbackup list`
  exec gosu "$PUID:$PGID" "$@"
fi

if [ "${AUTO_RESTORE:-0}" = "1" ]; then
  run_as /opt/acbackup/acbackup auto-restore || echo "⚠️  auto-restore failed; continuing to scheduler" >&2
fi

exec gosu "$PUID:$PGID" /opt/acbackup/backup-scheduler.sh
```

Then: `chmod +x entrypoint.sh`

- [ ] **Step 2: Write `scripts/healthcheck.sh`**

```bash
#!/bin/bash
# Healthy when MySQL is reachable AND a recent dump exists (or still in grace).
set -u
MAX_MIN="${BACKUP_HEALTHCHECK_MAX_MINUTES:-120}"
GRACE_S="${BACKUP_HEALTHCHECK_GRACE_SECONDS:-4500}"
BACKUP_DIR_BASE="${BACKUP_DIR_BASE:-/backups}"
export MYSQL_PWD="${MYSQL_PASSWORD:-}"
mysql -h"${MYSQL_HOST:-ac-database}" -P"${MYSQL_PORT:-3306}" -u"${MYSQL_USER:-root}" -e 'SELECT 1' >/dev/null 2>&1 || exit 1
find "$BACKUP_DIR_BASE" -name '*.sql.gz' -mmin "-$MAX_MIN" -print -quit 2>/dev/null | grep -q . && exit 0
awk -v limit="$GRACE_S" 'NR==1 { exit ($1 < limit) ? 0 : 1 }' /proc/uptime
```

Then: `chmod +x scripts/healthcheck.sh`

- [ ] **Step 3: Write `Dockerfile`**

```dockerfile
FROM mysql:8.4

# mysql:8.4 ships mysql, mysqldump, gzip, and gosu - no downloads needed.
COPY scripts/lib.sh scripts/backup-scheduler.sh scripts/acbackup scripts/healthcheck.sh /opt/acbackup/
COPY entrypoint.sh /opt/acbackup/entrypoint.sh
RUN chmod +x /opt/acbackup/backup-scheduler.sh /opt/acbackup/acbackup \
             /opt/acbackup/healthcheck.sh /opt/acbackup/entrypoint.sh \
    && ln -s /opt/acbackup/acbackup /usr/local/bin/acbackup

ENV BACKUP_DIR_BASE=/backups
VOLUME /backups

HEALTHCHECK --interval=60s --timeout=30s --start-period=120s --retries=3 \
  CMD ["/opt/acbackup/healthcheck.sh"]

ENTRYPOINT ["/opt/acbackup/entrypoint.sh"]
CMD ["scheduler"]
```

- [ ] **Step 4: Build and smoke-test the image**

Run:
```bash
docker build -t azerothcore-backup:dev .
docker run --rm --entrypoint /bin/bash azerothcore-backup:dev -c \
  'command -v gosu && command -v mysqldump && command -v acbackup && bash -n /opt/acbackup/lib.sh && echo IMAGE-OK'
```
Expected: paths printed, then `IMAGE-OK`. Also `shellcheck -S error entrypoint.sh scripts/healthcheck.sh` — clean.

- [ ] **Step 5: Commit**

```bash
git add Dockerfile entrypoint.sh scripts/healthcheck.sh
git commit -m "feat: image with entrypoint, privilege drop, and freshness healthcheck

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 5: End-to-end test (real MySQL, backup, corrupt, restore, auto-restore)

**Files:**
- Create: `test/e2e/compose.yml`, `test/e2e/seed.sql`, `test/e2e/run.sh`

**Interfaces:**
- Consumes: image `azerothcore-backup:dev` (Task 4)
- Produces: `test/e2e/run.sh [MYSQL_TAG]` — exit 0 on full pass; used verbatim by CI (Task 7) with tags `8.0` and `8.4`

- [ ] **Step 1: Write `test/e2e/seed.sql`**

```sql
CREATE DATABASE IF NOT EXISTS acore_auth;
CREATE DATABASE IF NOT EXISTS acore_world;
CREATE DATABASE IF NOT EXISTS acore_characters;
CREATE DATABASE IF NOT EXISTS acore_playerbots;
CREATE TABLE acore_auth.account (id INT PRIMARY KEY AUTO_INCREMENT, username VARCHAR(32));
INSERT INTO acore_auth.account (username) VALUES ('ARTIMAGE'),('HAMSAMMY');
CREATE TABLE acore_characters.characters (guid INT PRIMARY KEY, name VARCHAR(24), level INT);
INSERT INTO acore_characters.characters VALUES (1,'Testchar',80),(2,'Otherchar',42);
CREATE TABLE acore_world.version (v VARCHAR(16));
INSERT INTO acore_world.version VALUES ('e2e');
CREATE TABLE acore_playerbots.bots (id INT PRIMARY KEY);
INSERT INTO acore_playerbots.bots VALUES (1),(2),(3);
```

- [ ] **Step 2: Write `test/e2e/compose.yml`**

```yaml
services:
  db:
    image: mysql:${MYSQL_TAG:-8.4}
    environment:
      MYSQL_ROOT_PASSWORD: e2epass
    healthcheck:
      test: ["CMD-SHELL", "mysql -uroot -pe2epass -e 'SELECT 1' >/dev/null 2>&1"]
      interval: 3s
      timeout: 5s
      retries: 40
  backup:
    image: azerothcore-backup:dev
    environment:
      MYSQL_HOST: db
      MYSQL_PASSWORD: e2epass
      BACKUP_INTERVAL_MINUTES: 60
      PUID: "1234"      # deliberately mismatched vs the bind mount owner
      PGID: "1234"
    volumes:
      - ./volume:/backups
    depends_on:
      db:
        condition: service_healthy
```

- [ ] **Step 3: Write `test/e2e/run.sh`**

```bash
#!/bin/bash
# e2e: seed -> backup -> verify -> corrupt-detect -> wipe -> restore -> auto-restore.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$HERE"
export MYSQL_TAG="${1:-8.4}"
C="docker compose -f compose.yml -p acbk-e2e"
fail(){ echo "E2E FAIL: $*"; $C logs backup | tail -20; $C down -v --remove-orphans >/dev/null 2>&1; exit 1; }
cleanup(){ $C down -v --remove-orphans >/dev/null 2>&1 || true; sudo rm -rf ./volume 2>/dev/null || rm -rf ./volume; }
trap cleanup EXIT

echo "=== e2e against mysql:$MYSQL_TAG ==="
rm -rf ./volume && mkdir -p ./volume   # owned by runner uid, container uses 1234 (NFS-ish skew)
$C up -d --wait db
$C exec -T db mysql -uroot -pe2epass < seed.sql

$C up -d backup
sleep 5

echo "--- backup via acbackup now ---"
$C exec -T backup acbackup now --label e2e || fail "acbackup now failed"
B=$($C exec -T backup sh -c 'ls -d /backups/manual/e2e-* | head -1' | tr -d '\r')
[ -n "$B" ] || fail "no manual backup dir"
$C exec -T backup sh -c "test -f $B/.backup_complete" || fail "missing completion marker"
$C exec -T backup sh -c "ls $B/acore_playerbots.sql.gz" >/dev/null || fail "playerbots not auto-detected"

echo "--- verify passes, corrupt copy fails ---"
$C exec -T backup acbackup verify "$B" || fail "verify rejected good backup"
$C exec -T backup sh -c "cp -r $B /backups/manual/corrupt && truncate -s 30 /backups/manual/corrupt/acore_world.sql.gz"
$C exec -T backup acbackup verify /backups/manual/corrupt && fail "verify accepted corrupt backup" || true

echo "--- wipe and restore ---"
$C exec -T db mysql -uroot -pe2epass -e "DROP DATABASE acore_characters; DROP DATABASE acore_auth;"
$C exec -T backup acbackup restore "$B" --yes --no-safety-backup || fail "restore failed"
N=$($C exec -T db mysql -uroot -pe2epass -N -B -e "SELECT COUNT(*) FROM acore_characters.characters;" | tr -d '\r')
[ "$N" = "2" ] || fail "row count after restore: $N (want 2)"

echo "--- auto-restore on empty server ---"
$C exec -T db mysql -uroot -pe2epass -e "DROP DATABASE acore_auth;"
$C stop backup >/dev/null
$C rm -f backup >/dev/null 2>&1 || true
AUTO_RESTORE=1 $C up -d backup
$C exec -T backup true  # wait for container
for i in $(seq 1 30); do
  R=$($C exec -T db mysql -uroot -pe2epass -N -B -e "SELECT COUNT(*) FROM acore_auth.account;" 2>/dev/null | tr -d '\r' || echo "")
  [ "$R" = "2" ] && break
  sleep 2
done
[ "$R" = "2" ] || fail "auto-restore did not repopulate acore_auth (got '$R')"

echo "=== E2E PASS (mysql:$MYSQL_TAG) ==="
```

Note for the compose `AUTO_RESTORE` passthrough: add `AUTO_RESTORE: ${AUTO_RESTORE:-0}` to the backup service `environment:` block in `compose.yml` (do this now).

Then: `chmod +x test/e2e/run.sh`

- [ ] **Step 4: Run the e2e locally against both server versions**

Run: `bash test/e2e/run.sh 8.4 && bash test/e2e/run.sh 8.0`
Expected: `E2E PASS` for both. Debug failures via `docker compose -p acbk-e2e logs backup`.

- [ ] **Step 5: Commit**

```bash
git add test/e2e/
git commit -m "test: end-to-end backup/verify/restore/auto-restore against real MySQL

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 6: Examples and README

**Files:**
- Create: `examples/compose.yml`, `examples/compose.override.yml`, `README.md`

**Interfaces:**
- Consumes: env contract from Task 1/spec
- Produces: user-facing docs; no code consumed by later tasks

- [ ] **Step 1: Write `examples/compose.override.yml`** (drop-in for upstream-style AC stacks)

```yaml
# Drop this next to an upstream-style AzerothCore docker-compose.yml as
# docker-compose.override.yml (or merge into an existing override file).
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

- [ ] **Step 2: Write `examples/compose.yml`** (minimal self-contained reference)

```yaml
# Minimal reference: an AzerothCore-style MySQL plus the backup service.
services:
  ac-database:
    image: mysql:8.4
    environment:
      MYSQL_ROOT_PASSWORD: ${DB_ROOT_PASSWORD:?set DB_ROOT_PASSWORD}
    volumes:
      - db-data:/var/lib/mysql
    healthcheck:
      test: ["CMD-SHELL", "mysql -uroot -p$$MYSQL_ROOT_PASSWORD -e 'SELECT 1' >/dev/null 2>&1"]
      interval: 5s
      timeout: 10s
      retries: 40

  ac-backup:
    image: uprightbass360/azerothcore-backup:latest
    environment:
      MYSQL_HOST: ac-database
      MYSQL_PASSWORD: ${DB_ROOT_PASSWORD:?set DB_ROOT_PASSWORD}
      # AUTO_RESTORE: "1"          # uncomment to self-restore an empty DB
      # BACKUP_ALERT_WEBHOOK: https://ntfy.sh/your-topic
    volumes:
      - ./backups:/backups
    depends_on:
      ac-database:
        condition: service_healthy
    restart: always

volumes:
  db-data:
```

- [ ] **Step 3: Write `README.md`** with these sections (write real prose, not stubs):
  - **What it is** — verified, tiered MySQL backups + restore CLI for dockerized AzerothCore; one service block to adopt.
  - **Quick start** — the `examples/compose.override.yml` block inline; `docker compose up -d`; where backups appear.
  - **How backups work** — interval/daily/monthly tiers, verification, honest `.backup_complete` markers, `manifest.json` fields, retention defaults.
  - **Configuration** — the full env table copied from the spec (all variables, defaults, notes; include `MYSQL_PASSWORD_FILE`, `AUTO_RESTORE`, `AUTO_RESTORE_PROBE`, `PUID/PGID`, `BACKUP_HEALTHCHECK_MAX_MINUTES`).
  - **Restore runbook** — `acbackup list` → `acbackup verify latest` → `acbackup restore latest`; what the pre-restore safety backup is; `--db` partial restore; auto-restore semantics and its loud logging/webhook.
  - **NFS and permissions** — PUID/PGID, tier-root-only ownership fixes, drift self-heal, root-squash notes.
  - **Alerting** — `BACKUP_ALERT_WEBHOOK` with an ntfy example; the healthcheck's freshness window.
  - **Development** — run unit tests (`bash test/unit/test-*.sh`), run e2e (`bash test/e2e/run.sh 8.4`).

- [ ] **Step 4: Sanity-check the examples**

Run: `docker compose -f examples/compose.yml config >/dev/null && echo EXAMPLES-OK` (with `DB_ROOT_PASSWORD=x` exported).
Expected: `EXAMPLES-OK`.

- [ ] **Step 5: Commit**

```bash
git add examples/ README.md
git commit -m "docs: examples and README

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
```

---

### Task 7: CI (lint + e2e matrix + publish) and Dependabot

**Files:**
- Create: `.github/workflows/ci.yml`, `.github/dependabot.yml`

**Interfaces:**
- Consumes: `test/unit/test-*.sh`, `test/e2e/run.sh` (Tasks 1-5)
- Produces: published image `uprightbass360/azerothcore-backup:latest` on pushes to `main`. Requires repo secrets `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` (same values as the RealmMaster repo — the human must set these in the new repo's settings; flag it in the task report if not yet set).

- [ ] **Step 1: Write `.github/workflows/ci.yml`**

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:
  workflow_dispatch:

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - name: shellcheck
        run: |
          sudo apt-get update -qq && sudo apt-get install -y shellcheck
          shellcheck -S error scripts/lib.sh scripts/backup-scheduler.sh \
            scripts/acbackup scripts/healthcheck.sh entrypoint.sh \
            test/unit/test-*.sh test/e2e/run.sh
      - name: hadolint
        uses: hadolint/hadolint-action@v3.3.0
        with:
          dockerfile: Dockerfile
          failure-threshold: error

  unit:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v7
      - name: unit tests (stubbed, no docker)
        run: |
          bash test/unit/test-lib.sh
          bash test/unit/test-scheduler.sh
          bash test/unit/test-acbackup.sh

  e2e:
    runs-on: ubuntu-latest
    needs: [lint, unit]
    strategy:
      matrix:
        mysql: ["8.0", "8.4"]
    steps:
      - uses: actions/checkout@v7
      - name: build image
        run: docker build -t azerothcore-backup:dev .
      - name: e2e
        run: bash test/e2e/run.sh "${{ matrix.mysql }}"

  publish:
    runs-on: ubuntu-latest
    needs: [e2e]
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v7
      - uses: docker/setup-buildx-action@v4
      - uses: docker/login-action@v4
        with:
          username: ${{ secrets.DOCKERHUB_USERNAME }}
          password: ${{ secrets.DOCKERHUB_TOKEN }}
      - name: build and push
        run: |
          IMG=${{ secrets.DOCKERHUB_USERNAME }}/azerothcore-backup
          docker build -t "$IMG:latest" -t "$IMG:$(date +%Y%m%d)" .
          docker push "$IMG:latest"
          docker push "$IMG:$(date +%Y%m%d)"
```

- [ ] **Step 2: Write `.github/dependabot.yml`**

```yaml
version: 2
updates:
  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "sunday"
    groups:
      actions:
        patterns: ["*"]
    labels: ["ci"]
    commit-message:
      prefix: "chore"
  - package-ecosystem: "docker"
    directory: "/"
    schedule:
      interval: "weekly"
      day: "sunday"
    labels: ["ci"]
    commit-message:
      prefix: "chore"
```

- [ ] **Step 3: Validate, commit, push, watch CI**

```bash
python3 -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml')); yaml.safe_load(open('.github/dependabot.yml')); print('YAML-OK')"
git add .github/
git commit -m "ci: lint, unit, e2e matrix (mysql 8.0/8.4), publish to Docker Hub

Co-Authored-By: Claude Fable 5 <noreply@anthropic.com>"
git push origin main
gh run watch --repo uprightbass360/azerothcore-backup "$(gh run list --repo uprightbass360/azerothcore-backup --limit 1 --json databaseId --jq '.[0].databaseId')" --exit-status
```
Expected: lint, unit, and both e2e matrix legs green. The `publish` job fails only if `DOCKERHUB_USERNAME`/`DOCKERHUB_TOKEN` secrets are not yet set on the new repo — if so, report that to the human as the single remaining manual step and re-run after they add them.

- [ ] **Step 4: Verify the published image (after secrets exist)**

Run: `docker pull uprightbass360/azerothcore-backup:latest && docker run --rm uprightbass360/azerothcore-backup:latest acbackup list`
Expected: pull succeeds; `acbackup list` prints tier headers (empty tiers) and exits 0.

---

## Self-Review Notes

- Spec coverage: image/base+gosu+healthcheck (Task 4), scheduler behaviors incl. tiers/verification/markers/webhook/daily-seeding (Tasks 1-2), full CLI + auto-restore (Task 3), NFS/permission-skew handling (entrypoint tier-roots Task 4; e2e mismatched-uid volume Task 5), env contract (lib defaults Task 1, README table Task 6), upstream-style override example (Task 6), CI lint+matrix+publish+Dependabot (Task 7). Out-of-scope items from spec remain untouched.
- `BACKUP_DATABASES` replaces RealmMaster's per-DB env trio; playerbots auto-detect preserved (spec table).
- Type/name consistency: `run_backup DIR TIER`, `newest_complete_backup`, `is_complete`, `verify_dump`, tier globals — used identically in Tasks 2, 3, 5.
