#!/usr/bin/env python3
import json
import os
import re
import socket
import subprocess
import sys
import time
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parents[2]
ENV_FILE = PROJECT_DIR / ".env"
DEFAULT_ACORE_STANDARD_REPO = "https://github.com/azerothcore/azerothcore-wotlk.git"
DEFAULT_ACORE_PLAYERBOTS_REPO = "https://github.com/mod-playerbots/azerothcore-wotlk.git"
DEFAULT_ACORE_STANDARD_BRANCH = "master"
DEFAULT_ACORE_PLAYERBOTS_BRANCH = "Playerbot"

def load_env():
    env = {}
    if ENV_FILE.exists():
        for line in ENV_FILE.read_text().splitlines():
            if not line or line.strip().startswith('#'):
                continue
            if '=' not in line:
                continue
            key, val = line.split('=', 1)
            val = val.split('#', 1)[0].strip()
            env[key.strip()] = val
    return env

def read_env(env, key, default=""):
    return env.get(key, default)

def docker_exists(name):
    result = subprocess.run([
        "docker", "ps", "-a", "--format", "{{.Names}}"
    ], capture_output=True, text=True)
    names = set(result.stdout.split())
    return name in names

def docker_inspect(name, template):
    try:
        result = subprocess.run([
            "docker", "inspect", f"--format={template}", name
        ], capture_output=True, text=True, check=True)
        return result.stdout.strip()
    except subprocess.CalledProcessError:
        return ""

def service_snapshot(name, label):
    status = "missing"
    health = "none"
    started = ""
    image = ""
    exit_code = ""
    if docker_exists(name):
        status = docker_inspect(name, "{{.State.Status}}") or status
        health = docker_inspect(name, "{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}") or health
        started = docker_inspect(name, "{{.State.StartedAt}}") or ""
        image = docker_inspect(name, "{{.Config.Image}}") or ""
        exit_code = docker_inspect(name, "{{.State.ExitCode}}") or "0"
    return {
        "name": name,
        "label": label,
        "status": status,
        "health": health,
        "started_at": started,
        "image": image,
        "exit_code": exit_code,
    }

def port_reachable(port):
    if not port:
        return False
    try:
        port = int(port)
    except ValueError:
        return False
    try:
        with socket.create_connection(("127.0.0.1", port), timeout=1):
            return True
    except OSError:
        return False

def module_list(env):
    import json
    from pathlib import Path

    # Load module manifest
    manifest_path = PROJECT_DIR / "config" / "module-manifest.json"
    manifest_map = {}
    if manifest_path.exists():
        try:
            manifest_data = json.loads(manifest_path.read_text())
            for mod in manifest_data.get("modules", []):
                manifest_map[mod["key"]] = mod
        except Exception:
            pass

    modules = []
    pattern = re.compile(r"^MODULE_([A-Z0-9_]+)=1$")
    if ENV_FILE.exists():
        for line in ENV_FILE.read_text().splitlines():
            m = pattern.match(line.strip())
            if m:
                key = "MODULE_" + m.group(1)
                raw = m.group(1).lower().replace('_', ' ')
                title = raw.title()

                # Look up manifest info
                mod_info = manifest_map.get(key, {})
                modules.append({
                    "name": title,
                    "key": key,
                    "description": mod_info.get("description", "No description available"),
                    "category": mod_info.get("category", "unknown"),
                    "type": mod_info.get("type", "unknown")
                })
    return modules

def dir_info(path):
    p = Path(path)
    exists = p.exists()
    size = "--"
    if exists:
        try:
            result = subprocess.run(
                ["du", "-sh", str(p)],
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                check=False,
            )
            if result.stdout:
                size = result.stdout.split()[0]
        except Exception:
            size = "--"
    return {"path": str(p), "exists": exists, "size": size}

def volume_info(name, fallback=None):
    candidates = [name]
    if fallback:
        candidates.append(fallback)
    for cand in candidates:
        result = subprocess.run(["docker", "volume", "inspect", cand], capture_output=True, text=True)
        if result.returncode == 0:
            try:
                data = json.loads(result.stdout)[0]
                return {
                    "name": cand,
                    "exists": True,
                    "mountpoint": data.get("Mountpoint", "-")
                }
            except Exception:
                pass
    return {"name": name, "exists": False, "mountpoint": "-"}

def detect_source_variant(env):
    variant = read_env(env, "STACK_SOURCE_VARIANT", "").strip().lower()
    if variant in ("playerbots", "playerbot"):
        return "playerbots"
    if variant == "core":
        return "core"
    if read_env(env, "STACK_IMAGE_MODE", "").strip().lower() == "playerbots":
        return "playerbots"
    if read_env(env, "MODULE_PLAYERBOTS", "0") == "1" or read_env(env, "PLAYERBOT_ENABLED", "0") == "1":
        return "playerbots"
    return "core"

def repo_config_for_variant(env, variant):
    if variant == "playerbots":
        repo = read_env(env, "ACORE_REPO_PLAYERBOTS", DEFAULT_ACORE_PLAYERBOTS_REPO)
        branch = read_env(env, "ACORE_BRANCH_PLAYERBOTS", DEFAULT_ACORE_PLAYERBOTS_BRANCH)
    else:
        repo = read_env(env, "ACORE_REPO_STANDARD", DEFAULT_ACORE_STANDARD_REPO)
        branch = read_env(env, "ACORE_BRANCH_STANDARD", DEFAULT_ACORE_STANDARD_BRANCH)
    return repo, branch

def image_labels(image):
    try:
        result = subprocess.run(
            ["docker", "image", "inspect", "--format", "{{json .Config.Labels}}", image],
            capture_output=True,
            text=True,
            check=True,
            timeout=3,
        )
        labels = json.loads(result.stdout or "{}")
        if isinstance(labels, dict):
            return {k: (v or "").strip() for k, v in labels.items()}
    except Exception:
        pass
    return {}

def first_label(labels, keys):
    for key in keys:
        value = labels.get(key, "")
        if value:
            return value
    return ""

def short_commit(commit):
    commit = commit.strip()
    if re.fullmatch(r"[0-9a-fA-F]{12,}", commit):
        return commit[:12]
    return commit

def git_info_from_path(path):
    repo_path = Path(path)
    if not (repo_path / ".git").exists():
        return None

    def run_git(args):
        try:
            result = subprocess.run(
                ["git"] + args,
                cwd=repo_path,
                capture_output=True,
                text=True,
                check=True,
            )
            return result.stdout.strip()
        except Exception:
            return ""

    commit = run_git(["rev-parse", "HEAD"])
    if not commit:
        return None

    return {
        "commit": commit,
        "commit_short": run_git(["rev-parse", "--short", "HEAD"]) or short_commit(commit),
        "date": run_git(["log", "-1", "--format=%cd", "--date=iso-strict"]),
        "repo": run_git(["remote", "get-url", "origin"]),
        "branch": run_git(["rev-parse", "--abbrev-ref", "HEAD"]),
        "path": str(repo_path),
    }

def candidate_source_paths(env, variant):
    paths = []
    for key in ("MODULES_REBUILD_SOURCE_PATH", "SOURCE_DIR"):
        value = read_env(env, key, "")
        if value:
            paths.append(value)

    local_root = read_env(env, "STORAGE_PATH_LOCAL", "./local-storage")
    primary_dir = "azerothcore-playerbots" if variant == "playerbots" else "azerothcore"
    fallback_dir = "azerothcore" if variant == "playerbots" else "azerothcore-playerbots"
    paths.append(os.path.join(local_root, "source", primary_dir))
    paths.append(os.path.join(local_root, "source", fallback_dir))

    normalized = []
    for p in paths:
        expanded = expand_path(p, env)
        try:
            normalized.append(str(Path(expanded).expanduser().resolve()))
        except Exception:
            normalized.append(str(Path(expanded).expanduser()))
    # Deduplicate while preserving order
    seen = set()
    unique_paths = []
    for p in normalized:
        if p not in seen:
            seen.add(p)
            unique_paths.append(p)
    return unique_paths

def build_info(service_data, env):
    variant = detect_source_variant(env)
    repo, branch = repo_config_for_variant(env, variant)
    info = {
        "variant": variant,
        "repo": repo,
        "branch": branch,
        "image": "",
        "commit": "",
        "commit_date": "",
        "commit_source": "",
        "source_path": "",
    }

    image_candidates = []
    for svc in service_data:
        if svc.get("name") in ("ac-worldserver", "ac-authserver", "ac-db-import"):
            image = svc.get("image") or ""
            if image:
                image_candidates.append(image)

    for env_key in (
        "AC_WORLDSERVER_IMAGE_PLAYERBOTS",
        "AC_WORLDSERVER_IMAGE_MODULES",
        "AC_WORLDSERVER_IMAGE",
        "AC_AUTHSERVER_IMAGE_PLAYERBOTS",
        "AC_AUTHSERVER_IMAGE_MODULES",
        "AC_AUTHSERVER_IMAGE",
    ):
        value = read_env(env, env_key, "")
        if value:
            image_candidates.append(value)

    seen = set()
    deduped_images = []
    for img in image_candidates:
        if img not in seen:
            seen.add(img)
            deduped_images.append(img)

    commit_label_keys = [
        "build.source_commit",
        "org.opencontainers.image.revision",
        "org.opencontainers.image.version",
    ]
    date_label_keys = [
        "build.source_date",
        "org.opencontainers.image.created",
        "build.timestamp",
    ]

    for image in deduped_images:
        labels = image_labels(image)
        if not info["image"]:
            info["image"] = image
        if not labels:
            continue
        commit = short_commit(first_label(labels, commit_label_keys))
        date = first_label(labels, date_label_keys)
        if commit or date:
            info["commit"] = commit
            info["commit_date"] = date
            info["commit_source"] = "image-label"
            info["image"] = image
            return info

    for path in candidate_source_paths(env, variant):
        git_meta = git_info_from_path(path)
        if git_meta:
            info["commit"] = git_meta.get("commit_short") or short_commit(git_meta.get("commit", ""))
            info["commit_date"] = git_meta.get("date", "")
            info["commit_source"] = "source-tree"
            info["source_path"] = git_meta.get("path", "")
            info["repo"] = git_meta.get("repo") or info["repo"]
            info["branch"] = git_meta.get("branch") or info["branch"]
            return info

    return info

def expand_path(value, env):
    storage = read_env(env, "STORAGE_PATH", "./storage")
    local_storage = read_env(env, "STORAGE_PATH_LOCAL", "./local-storage")
    value = value.replace('${STORAGE_PATH}', storage)
    value = value.replace('${STORAGE_PATH_LOCAL}', local_storage)
    return value

def mysql_query(env, database, query):
    password = read_env(env, "MYSQL_ROOT_PASSWORD")
    user = read_env(env, "MYSQL_USER", "root")
    if not password or not database:
        return 0
    cmd = [
        "docker", "exec", "ac-mysql",
        "mysql", "-N", "-B",
        f"-u{user}", f"-p{password}", database,
        "-e", query
    ]
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        value = result.stdout.strip().splitlines()[-1]
        return int(value)
    except Exception:
        return 0

def escape_like_prefix(prefix):
    # Basic escape for single quotes in SQL literals
    return prefix.replace("'", "''")

def bot_prefixes(env):
    prefixes = []
    for key in ("PLAYERBOT_ACCOUNT_PREFIXES", "PLAYERBOT_ACCOUNT_PREFIX"):
        raw = read_env(env, key, "")
        for part in raw.replace(",", " ").split():
            part = part.strip()
            if part:
                prefixes.append(part)
    # Default fallback if nothing configured
    if not prefixes:
        prefixes.extend(["playerbot", "rndbot", "bot"])
    return prefixes

def user_stats(env):
    db_auth = read_env(env, "DB_AUTH_NAME", "acore_auth")
    db_characters = read_env(env, "DB_CHARACTERS_NAME", "acore_characters")
    prefixes = bot_prefixes(env)
    account_conditions = []
    for prefix in prefixes:
        prefix = escape_like_prefix(prefix)
        upper_prefix = prefix.upper()
        account_conditions.append(f"UPPER(username) NOT LIKE '{upper_prefix}%%'")
    account_query = "SELECT COUNT(*) FROM account"
    if account_conditions:
        account_query += " WHERE " + " AND ".join(account_conditions)
    accounts = mysql_query(env, db_auth, account_query + ";")

    online_conditions = ["c.online = 1"]
    for prefix in prefixes:
        prefix = escape_like_prefix(prefix)
        upper_prefix = prefix.upper()
        online_conditions.append(f"UPPER(a.username) NOT LIKE '{upper_prefix}%%'")
    online_query = (
        f"SELECT COUNT(DISTINCT a.id) FROM `{db_characters}`.characters c "
        f"JOIN `{db_auth}`.account a ON a.id = c.account "
        f"WHERE {' AND '.join(online_conditions)};"
    )
    online = mysql_query(env, db_characters, online_query)
    active = mysql_query(env, db_auth, "SELECT COUNT(*) FROM account WHERE last_login >= DATE_SUB(UTC_TIMESTAMP(), INTERVAL 7 DAY);")
    character_conditions = []
    for prefix in prefixes:
        prefix = escape_like_prefix(prefix)
        upper_prefix = prefix.upper()
        character_conditions.append(f"UPPER(a.username) NOT LIKE '{upper_prefix}%%'")
    characters_query = (
        f"SELECT COUNT(*) FROM `{db_characters}`.characters c "
        f"JOIN `{db_auth}`.account a ON a.id = c.account"
    )
    if character_conditions:
        characters_query += " WHERE " + " AND ".join(character_conditions)
    characters = mysql_query(env, db_characters, characters_query + ";")
    return {
        "accounts": accounts,
        "online": online,
        "characters": characters,
        "active7d": active,
    }

def docker_stats():
    """Get CPU and memory stats for running containers"""
    try:
        result = subprocess.run([
            "docker", "stats", "--no-stream", "--no-trunc",
            "--format", "{{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.MemPerc}}"
        ], capture_output=True, text=True, check=True, timeout=4)

        stats = {}
        for line in result.stdout.strip().splitlines():
            parts = line.split('\t')
            if len(parts) == 4:
                name, cpu, mem_usage, mem_perc = parts
                # Parse CPU percentage (e.g., "0.50%" -> 0.50)
                cpu_val = cpu.replace('%', '').strip()
                try:
                    cpu_float = float(cpu_val)
                except ValueError:
                    cpu_float = 0.0

                # Parse memory percentage
                mem_perc_val = mem_perc.replace('%', '').strip()
                try:
                    mem_perc_float = float(mem_perc_val)
                except ValueError:
                    mem_perc_float = 0.0

                stats[name] = {
                    "cpu": cpu_float,
                    "memory": mem_usage.strip(),
                    "memory_percent": mem_perc_float
                }
        return stats
    except Exception:
        return {}

def main():
    env = load_env()
    project = read_env(env, "COMPOSE_PROJECT_NAME")
    if not project:
        print(json.dumps({"error": "COMPOSE_PROJECT_NAME not set in environment"}), file=sys.stderr)
        sys.exit(1)
    network = read_env(env, "NETWORK_NAME")
    if not network:
        print(json.dumps({"error": "NETWORK_NAME not set in environment"}), file=sys.stderr)
        sys.exit(1)

    services = [
        ("ac-mysql", "MySQL"),
        ("ac-backup", "Backup"),
        ("ac-volume-init", "Volume Init"),
        ("ac-storage-init", "Storage Init"),
        ("ac-db-init", "DB Init"),
        ("ac-db-import", "DB Import"),
        ("ac-authserver", "Auth Server"),
        ("ac-worldserver", "World Server"),
        ("ac-client-data", "Client Data"),
        ("ac-modules", "Module Manager"),
        ("ac-post-install", "Post Install"),
        ("ac-phpmyadmin", "phpMyAdmin"),
        ("ac-keira3", "Keira3"),
    ]

    service_data = [service_snapshot(name, label) for name, label in services]

    port_entries = [
        {"name": "Auth", "port": read_env(env, "AUTH_EXTERNAL_PORT"), "reachable": port_reachable(read_env(env, "AUTH_EXTERNAL_PORT"))},
        {"name": "World", "port": read_env(env, "WORLD_EXTERNAL_PORT"), "reachable": port_reachable(read_env(env, "WORLD_EXTERNAL_PORT"))},
        {"name": "SOAP", "port": read_env(env, "SOAP_EXTERNAL_PORT"), "reachable": port_reachable(read_env(env, "SOAP_EXTERNAL_PORT"))},
        {"name": "MySQL", "port": read_env(env, "MYSQL_EXTERNAL_PORT"), "reachable": port_reachable(read_env(env, "MYSQL_EXTERNAL_PORT")) if read_env(env, "COMPOSE_OVERRIDE_MYSQL_EXPOSE_ENABLED", "0") == "1" else False},
        {"name": "phpMyAdmin", "port": read_env(env, "PMA_EXTERNAL_PORT"), "reachable": port_reachable(read_env(env, "PMA_EXTERNAL_PORT"))},
        {"name": "Keira3", "port": read_env(env, "KEIRA3_EXTERNAL_PORT"), "reachable": port_reachable(read_env(env, "KEIRA3_EXTERNAL_PORT"))},
    ]

    storage_path = expand_path(read_env(env, "STORAGE_PATH", "./storage"), env)
    local_storage_path = expand_path(read_env(env, "STORAGE_PATH_LOCAL", "./local-storage"), env)
    client_data_path = expand_path(read_env(env, "CLIENT_DATA_PATH", f"{storage_path}/client-data"), env)

    storage_info = {
        "storage": dir_info(storage_path),
        "local_storage": dir_info(local_storage_path),
        "client_data": dir_info(client_data_path),
        "modules": dir_info(os.path.join(storage_path, "modules")),
        "local_modules": dir_info(os.path.join(local_storage_path, "modules")),
    }

    volumes = {
        "client_cache": volume_info(f"{project}_client-data-cache"),
        "mysql_data": volume_info(f"{project}_mysql-data", "mysql-data"),
    }

    build = build_info(service_data, env)

    data = {
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "project": project,
        "network": network,
        "services": service_data,
        "ports": port_entries,
        "modules": module_list(env),
        "storage": storage_info,
        "volumes": volumes,
        "users": user_stats(env),
        "stats": docker_stats(),
        "build": build,
    }

    print(json.dumps(data))

if __name__ == "__main__":
    main()
