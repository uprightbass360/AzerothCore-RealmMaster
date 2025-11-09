#!/usr/bin/env python3
"""
Parse configuration preset metadata for setup.sh
"""

import sys
import argparse
from pathlib import Path


def parse_preset_metadata(preset_file: Path):
    """Parse CONFIG_NAME and CONFIG_DESCRIPTION from a preset file."""
    if not preset_file.exists():
        return None, None

    config_name = None
    config_description = None

    try:
        with open(preset_file, 'r', encoding='utf-8') as f:
            for line in f:
                line = line.strip()
                if line.startswith('# CONFIG_NAME:'):
                    config_name = line[14:].strip()
                elif line.startswith('# CONFIG_DESCRIPTION:'):
                    config_description = line[21:].strip()
                elif not line.startswith('#'):
                    # Stop at first non-comment line
                    break
    except Exception:
        return None, None

    return config_name, config_description


def list_presets(presets_dir: Path):
    """List all available presets with their metadata."""
    if not presets_dir.exists():
        return

    presets = []
    for preset_file in presets_dir.glob("*.conf"):
        preset_key = preset_file.stem
        config_name, config_description = parse_preset_metadata(preset_file)

        if config_name is None:
            config_name = preset_key.replace('-', ' ').title()
        if config_description is None:
            config_description = f"Configuration preset: {preset_key}"

        presets.append((preset_key, config_name, config_description))

    # Sort presets, but ensure 'none' comes first
    presets.sort(key=lambda x: (0 if x[0] == 'none' else 1, x[0]))

    for preset_key, config_name, config_description in presets:
        print(f"{preset_key}\t{config_name}\t{config_description}")


def get_preset_info(presets_dir: Path, preset_key: str):
    """Get information for a specific preset."""
    preset_file = presets_dir / f"{preset_key}.conf"
    config_name, config_description = parse_preset_metadata(preset_file)

    if config_name is None:
        config_name = preset_key.replace('-', ' ').title()
    if config_description is None:
        config_description = f"Configuration preset: {preset_key}"

    print(f"{config_name}\t{config_description}")


def main():
    parser = argparse.ArgumentParser(description="Parse configuration preset metadata")
    parser.add_argument("command", choices=["list", "info"], help="Command to execute")
    parser.add_argument("--presets-dir", default="./config/presets", help="Presets directory")
    parser.add_argument("--preset", help="Preset name for 'info' command")

    args = parser.parse_args()
    presets_dir = Path(args.presets_dir)

    if args.command == "list":
        list_presets(presets_dir)
    elif args.command == "info":
        if not args.preset:
            print("Error: --preset required for 'info' command", file=sys.stderr)
            sys.exit(1)
        get_preset_info(presets_dir, args.preset)


if __name__ == "__main__":
    main()