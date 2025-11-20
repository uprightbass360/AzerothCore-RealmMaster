#!/usr/bin/env python3
import json
import os
import re
import socket
import subprocess
import time
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parents[2]
ENV_FILE = PROJECT_DIR / ".env"

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

def user_stats(env):
    db_auth = read_env(env, "DB_AUTH_NAME", "acore_auth")
    db_characters = read_env(env, "DB_CHARACTERS_NAME", "acore_characters")
    accounts = mysql_query(env, db_auth, "SELECT COUNT(*) FROM account;")
    online = mysql_query(env, db_auth, "SELECT COUNT(*) FROM account WHERE online = 1;")
    active = mysql_query(env, db_auth, "SELECT COUNT(*) FROM account WHERE last_login >= DATE_SUB(UTC_TIMESTAMP(), INTERVAL 7 DAY);")
    characters = mysql_query(env, db_characters, "SELECT COUNT(*) FROM characters;")
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
    project = read_env(env, "COMPOSE_PROJECT_NAME", "acore-compose")
    network = read_env(env, "NETWORK_NAME", "azerothcore")

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
    }

    print(json.dumps(data))

if __name__ == "__main__":
    main()
