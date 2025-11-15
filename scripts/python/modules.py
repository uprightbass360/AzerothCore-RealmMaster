#!/usr/bin/env python3
"""
Module manifest helper.

Reads config/module-manifest.json and .env to produce canonical module state that
downstream shell scripts can consume for staging, rebuild detection, and
dependency validation.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import textwrap
from dataclasses import dataclass, asdict, field
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple
import shlex


STRICT_TRUE = {"1", "true", "yes", "on"}


def parse_bool(value: str) -> bool:
    if value is None:
        return False
    return str(value).strip().lower() in STRICT_TRUE


def load_env_file(env_path: Path) -> Dict[str, str]:
    if not env_path.exists():
        return {}
    env: Dict[str, str] = {}
    for raw_line in env_path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("export "):
            line = line[len("export ") :].strip()
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if value.startswith('"') and value.endswith('"'):
            value = value[1:-1]
        elif value.startswith("'") and value.endswith("'"):
            value = value[1:-1]
        env[key] = value
    return env


def load_manifest(manifest_path: Path) -> List[Dict[str, object]]:
    if not manifest_path.exists():
        raise FileNotFoundError(f"Manifest file not found: {manifest_path}")
    with manifest_path.open("r", encoding="utf-8") as fh:
        manifest = json.load(fh)
    modules = manifest.get("modules")
    if not isinstance(modules, list):
        raise ValueError("Manifest must define a top-level 'modules' array")
    validated: List[Dict[str, object]] = []
    seen_keys: set[str] = set()
    for entry in modules:
        if not isinstance(entry, dict):
            raise ValueError("Each manifest entry must be an object")
        key = entry.get("key")
        name = entry.get("name")
        repo = entry.get("repo")
        if not key or not isinstance(key, str):
            raise ValueError("Manifest entry missing 'key'")
        if key in seen_keys:
            raise ValueError(f"Duplicate manifest key detected: {key}")
        seen_keys.add(key)
        if not name or not isinstance(name, str):
            raise ValueError(f"Manifest entry {key} missing 'name'")
        if not repo or not isinstance(repo, str):
            raise ValueError(f"Manifest entry {key} missing 'repo'")
        validated.append(entry)
    return validated


@dataclass
class ModuleState:
    key: str
    name: str
    repo: str
    needs_build: bool
    module_type: str
    requires: List[str] = field(default_factory=list)
    ref: Optional[str] = None
    status: str = "active"
    block_reason: Optional[str] = None
    post_install_hooks: List[str] = field(default_factory=list)
    config_cleanup: List[str] = field(default_factory=list)
    sql: Optional[object] = None
    notes: Optional[str] = None
    enabled_raw: bool = False
    enabled_effective: bool = False
    value: str = "0"
    dependency_issues: List[str] = field(default_factory=list)
    warnings: List[str] = field(default_factory=list)
    errors: List[str] = field(default_factory=list)

    @property
    def blocked(self) -> bool:
        return self.status.lower() == "blocked"


@dataclass
class ModuleCollectionState:
    manifest_path: Path
    env_path: Path
    modules: List[ModuleState]
    generated_at: datetime
    warnings: List[str]
    errors: List[str]

    def enabled_modules(self) -> List[ModuleState]:
        return [module for module in self.modules if module.enabled_effective]

    def compile_modules(self) -> List[ModuleState]:
        return [
            module
            for module in self.modules
            if module.enabled_effective and module.needs_build
        ]

    def requires_playerbot_source(self) -> bool:
        module_map = {m.key: m for m in self.modules}
        playerbots_enabled = module_map.get("MODULE_PLAYERBOTS")
        return bool(playerbots_enabled and playerbots_enabled.enabled_effective)

    def requires_custom_build(self) -> bool:
        return any(module.needs_build and module.enabled_effective for module in self.modules)


def build_state(env_path: Path, manifest_path: Path) -> ModuleCollectionState:
    env_map = load_env_file(env_path)
    manifest_entries = load_manifest(manifest_path)
    modules: List[ModuleState] = []
    errors: List[str] = []
    warnings: List[str] = []

    # Track which manifest keys appear in .env for coverage validation
    env_keys_in_manifest: set[str] = set()

    for entry in manifest_entries:
        key = entry["key"]
        name = entry["name"]
        repo = entry["repo"]
        module_type = str(entry.get("type", "cpp"))
        needs_build_flag = entry.get("needs_build")
        if needs_build_flag is None:
            needs_build = module_type.lower() == "cpp"
        else:
            needs_build = bool(needs_build_flag)
        requires = entry.get("requires") or []
        if not isinstance(requires, list):
            raise ValueError(f"Manifest entry {key} has non-list 'requires'")
        requires = [str(dep) for dep in requires]

        status = entry.get("status", "active")
        block_reason = entry.get("block_reason")
        post_install_hooks = entry.get("post_install_hooks") or []
        if not isinstance(post_install_hooks, list):
            raise ValueError(f"Manifest entry {key} has non-list 'post_install_hooks'")
        post_install_hooks = [str(hook) for hook in post_install_hooks]
        config_cleanup = entry.get("config_cleanup") or []
        if not isinstance(config_cleanup, list):
            raise ValueError(f"Manifest entry {key} has non-list 'config_cleanup'")
        config_cleanup = [str(pattern) for pattern in config_cleanup]
        sql = entry.get("sql")
        ref = entry.get("ref")
        notes = entry.get("notes")

        raw_value = env_map.get(key, os.environ.get(key, "0"))
        env_keys_in_manifest.add(key)
        enabled_raw = parse_bool(raw_value)

        module = ModuleState(
            key=key,
            name=name,
            repo=repo,
            needs_build=needs_build,
            module_type=module_type,
            requires=requires,
            ref=ref,
            status=status,
            block_reason=block_reason,
            post_install_hooks=post_install_hooks,
            config_cleanup=config_cleanup,
            sql=sql,
            notes=notes,
            enabled_raw=enabled_raw,
        )

        if module.blocked and enabled_raw:
            module.warnings.append(
                f"{module.key} is blocked: {module.block_reason or 'blocked in manifest'}"
            )

        # Effective enablement respects block status
        module.enabled_effective = enabled_raw and not module.blocked
        module.value = "1" if module.enabled_effective else "0"

        modules.append(module)

    module_map: Dict[str, ModuleState] = {module.key: module for module in modules}

    # Dependency validation
    for module in modules:
        if not module.enabled_effective:
            continue
        missing: List[str] = []
        for dependency in module.requires:
            dep_state = module_map.get(dependency)
            if not dep_state or not dep_state.enabled_effective:
                missing.append(dependency)
        if missing:
            plural = "modules" if len(missing) > 1 else "module"
            list_str = ", ".join(missing)
            message = f"{module.key} requires {plural}: {list_str}"
            module.errors.append(message)

    # Collect warnings/errors
    for module in modules:
        if module.errors:
            errors.extend(module.errors)
        if module.warnings:
            warnings.extend(module.warnings)

    # Warn if .env defines modules not in manifest
    extra_env_modules = [
        key for key in env_map.keys() if key.startswith("MODULE_") and key not in module_map
    ]
    for unknown_key in extra_env_modules:
        warnings.append(f".env defines {unknown_key} but it is missing from the manifest")

    # Warn if manifest entry lacks .env toggle
    for module in modules:
        if module.key not in env_map and module.key not in os.environ:
            warnings.append(
                f"Manifest includes {module.key} but .env does not define it (defaulting to 0)"
            )

    return ModuleCollectionState(
        manifest_path=manifest_path,
        env_path=env_path,
        modules=modules,
        generated_at=datetime.now(timezone.utc),
        warnings=warnings,
        errors=errors,
    )


def write_outputs(state: ModuleCollectionState, output_dir: Path) -> None:
    output_dir.mkdir(parents=True, exist_ok=True)

    env_lines: List[str] = [
        "# Autogenerated by scripts/python/modules.py",
        f"# Generated at {state.generated_at.isoformat()}",
        f'export MODULES_MANIFEST="{state.manifest_path}"',
        f'export MODULES_ENV_PATH="{state.env_path}"',
    ]

    enabled_names: List[str] = []
    compile_names: List[str] = []
    enabled_keys: List[str] = []
    compile_keys: List[str] = []

    for module in state.modules:
        env_lines.append(f"export {module.key}={module.value}")
        if module.enabled_effective:
            enabled_names.append(module.name)
            enabled_keys.append(module.key)
        if module.enabled_effective and module.needs_build:
            compile_names.append(module.name)
            compile_keys.append(module.key)

    env_lines.append(f'export MODULES_ENABLED="{ " ".join(enabled_names) }"'.rstrip())
    env_lines.append(f'export MODULES_COMPILE="{ " ".join(compile_names) }"'.rstrip())
    env_lines.append(f'export MODULES_ENABLED_LIST="{",".join(enabled_keys)}"')
    env_lines.append(f'export MODULES_CPP_LIST="{",".join(compile_keys)}"')
    env_lines.append(
        f"export MODULES_REQUIRES_PLAYERBOT_SOURCE="
        f'{"1" if state.requires_playerbot_source() else "0"}'
    )
    env_lines.append(
        f"export MODULES_REQUIRES_CUSTOM_BUILD="
        f'{"1" if state.requires_custom_build() else "0"}'
    )
    env_lines.append(f"export MODULES_WARNING_COUNT={len(state.warnings)}")
    env_lines.append(f"export MODULES_ERROR_COUNT={len(state.errors)}")

    modules_env_path = output_dir / "modules.env"
    modules_env_path.write_text("\n".join(env_lines) + "\n", encoding="utf-8")

    state_payload = {
        "generated_at": state.generated_at.isoformat(),
        "manifest_path": str(state.manifest_path),
        "env_path": str(state.env_path),
        "warnings": state.warnings,
        "errors": state.errors,
        "modules": [
            {
                **asdict(module),
                "enabled_raw": module.enabled_raw,
                "enabled_effective": module.enabled_effective,
                "blocked": module.blocked,
            }
            for module in state.modules
        ],
        "enabled_modules": [module.name for module in state.enabled_modules()],
        "compile_modules": [module.name for module in state.compile_modules()],
        "requires_playerbot_source": state.requires_playerbot_source(),
        "requires_custom_build": state.requires_custom_build(),
    }

    modules_state_path = output_dir / "modules-state.json"
    modules_state_path.write_text(
        json.dumps(state_payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )

    meta_dir = output_dir / ".modules-meta"
    meta_dir.mkdir(parents=True, exist_ok=True)

    compile_list_path = meta_dir / "modules-compile.txt"
    compile_list_path.write_text(
        "\n".join(state_payload["compile_modules"]) + ("\n" if compile_names else ""),
        encoding="utf-8",
    )

    enabled_list_path = meta_dir / "modules-enabled.txt"
    enabled_list_path.write_text(
        "\n".join(state_payload["enabled_modules"]) + ("\n" if enabled_names else ""),
        encoding="utf-8",
    )


def print_list(state: ModuleCollectionState, selector: str) -> None:
    if selector == "compile":
        items = [module.name for module in state.compile_modules()]
    elif selector == "enabled":
        items = [module.name for module in state.enabled_modules()]
    elif selector == "keys":
        items = [module.key for module in state.enabled_modules()]
    else:
        raise ValueError(f"Unknown list selector: {selector}")
    for item in items:
        print(item)


def print_requires_playerbot(state: ModuleCollectionState) -> None:
    print("1" if state.requires_playerbot_source() else "0")



def print_requires_custom_build(state: ModuleCollectionState) -> None:
    print("1" if state.requires_custom_build() else "0")


def print_state(state: ModuleCollectionState, fmt: str) -> None:
    payload = {
        "generated_at": state.generated_at.isoformat(),
        "warnings": state.warnings,
        "errors": state.errors,
        "modules": [
            {
                "key": module.key,
                "name": module.name,
                "enabled": module.enabled_effective,
                "needs_build": module.needs_build,
                "requires": module.requires,
                "blocked": module.blocked,
                "dependency_issues": module.dependency_issues,
                "post_install_hooks": module.post_install_hooks,
                "config_cleanup": module.config_cleanup,
            }
            for module in state.modules
        ],
        "enabled_modules": [module.name for module in state.enabled_modules()],
        "compile_modules": [module.name for module in state.compile_modules()],
        "requires_playerbot_source": state.requires_playerbot_source(),
    }
    if fmt == "json":
        json.dump(payload, sys.stdout, indent=2, sort_keys=True)
        sys.stdout.write("\n")
    elif fmt == "shell":
        keys = [module.key for module in state.modules]
        quoted_keys = " ".join(shlex.quote(key) for key in keys)
        print(f"MODULE_KEYS=({quoted_keys})")
        print(
            "declare -A MODULE_NAME MODULE_REPO MODULE_REF MODULE_TYPE MODULE_ENABLED "
            "MODULE_NEEDS_BUILD MODULE_BLOCKED MODULE_POST_INSTALL MODULE_REQUIRES "
            "MODULE_CONFIG_CLEANUP "
            "MODULE_NOTES MODULE_STATUS MODULE_BLOCK_REASON"
        )
        for module in state.modules:
            key = module.key
            post_install = ",".join(module.post_install_hooks)
            dependencies = ",".join(module.requires)
            block_reason = module.block_reason or ""
            ref = module.ref or ""
            notes = module.notes or ""
            config_cleanup = ",".join(module.config_cleanup)
            print(f"MODULE_NAME[{key}]={shlex.quote(module.name)}")
            print(f"MODULE_REPO[{key}]={shlex.quote(module.repo)}")
            print(f"MODULE_REF[{key}]={shlex.quote(ref)}")
            print(f"MODULE_TYPE[{key}]={shlex.quote(module.module_type)}")
            print(f"MODULE_ENABLED[{key}]={1 if module.enabled_effective else 0}")
            print(f"MODULE_NEEDS_BUILD[{key}]={1 if module.needs_build else 0}")
            print(f"MODULE_BLOCKED[{key}]={1 if module.blocked else 0}")
            print(f"MODULE_POST_INSTALL[{key}]={shlex.quote(post_install)}")
            print(f"MODULE_REQUIRES[{key}]={shlex.quote(dependencies)}")
            print(f"MODULE_CONFIG_CLEANUP[{key}]={shlex.quote(config_cleanup)}")
            print(f"MODULE_NOTES[{key}]={shlex.quote(notes)}")
            print(f"MODULE_STATUS[{key}]={shlex.quote(module.status)}")
            print(f"MODULE_BLOCK_REASON[{key}]={shlex.quote(block_reason)}")
    else:
        raise ValueError(f"Unsupported format: {fmt}")


def handle_generate(args: argparse.Namespace) -> int:
    env_path = Path(args.env_path).resolve()
    manifest_path = Path(args.manifest).resolve()
    output_dir = Path(args.output_dir).resolve()
    state = build_state(env_path, manifest_path)
    write_outputs(state, output_dir)

    if state.warnings:
        warning_block = "\n".join(f"- {warning}" for warning in state.warnings)
        print(
            textwrap.dedent(
                f"""\
                ⚠️  Module manifest warnings detected:
                {warning_block}
                """
            ),
            file=sys.stderr,
        )
    if state.errors:
        error_block = "\n".join(f"- {error}" for error in state.errors)
        print(
            textwrap.dedent(
                f"""\
                ❌ Module manifest errors detected:
                {error_block}
                """
            ),
            file=sys.stderr,
        )
        return 1
    return 0


def configure_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Module manifest helper")
    parser.add_argument(
        "--env-path",
        default=".env",
        help="Path to .env file (default: .env)",
    )
    parser.add_argument(
        "--manifest",
        default="config/module-manifest.json",
        help="Path to module manifest (default: config/module-manifest.json)",
    )

    subparsers = parser.add_subparsers(dest="command", required=True)

    generate_parser = subparsers.add_parser("generate", help="Generate module state files")
    generate_parser.add_argument(
        "--output-dir",
        default="local-storage/modules",
        help="Directory for generated module artifacts (default: local-storage/modules)",
    )
    generate_parser.set_defaults(func=handle_generate)

    list_parser = subparsers.add_parser("list", help="Print module lists")
    list_parser.add_argument(
        "--type",
        choices=["compile", "enabled", "keys"],
        default="compile",
        help="List selector (default: compile)",
    )

    def handle_list(args: argparse.Namespace) -> int:
        state = build_state(Path(args.env_path).resolve(), Path(args.manifest).resolve())
        print_list(state, args.type)
        return 1 if state.errors else 0

    list_parser.set_defaults(func=handle_list)

    rps_parser = subparsers.add_parser(
        "requires-playerbot", help="Print 1 if playerbot source is required else 0"
    )

    def handle_requires_playerbot(args: argparse.Namespace) -> int:
        state = build_state(Path(args.env_path).resolve(), Path(args.manifest).resolve())
        print_requires_playerbot(state)
        return 1 if state.errors else 0

    rps_parser.set_defaults(func=handle_requires_playerbot)

    rcb_parser = subparsers.add_parser(
        "requires-custom-build",
        help="Print 1 if a custom source build is required else 0",
    )

    def handle_requires_custom_build(args: argparse.Namespace) -> int:
        state = build_state(Path(args.env_path).resolve(), Path(args.manifest).resolve())
        print_requires_custom_build(state)
        return 1 if state.errors else 0

    rcb_parser.set_defaults(func=handle_requires_custom_build)

    dump_parser = subparsers.add_parser("dump", help="Dump module state (JSON format)")
    dump_parser.add_argument(
        "--format",
        choices=["json", "shell"],
        default="json",
        help="Output format (default: json)",
    )

    def handle_dump(args: argparse.Namespace) -> int:
        state = build_state(Path(args.env_path).resolve(), Path(args.manifest).resolve())
        print_state(state, args.format)
        return 1 if state.errors else 0

    dump_parser.set_defaults(func=handle_dump)

    return parser


def main(argv: Optional[Iterable[str]] = None) -> int:
    parser = configure_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
