#!/usr/bin/env python3
"""
AzerothCore Configuration Manager

Reads server-overrides.conf and preset files to update actual .conf files
while preserving comments and structure.
"""

import argparse
import configparser
import os
import re
import shutil
import sys
from pathlib import Path
from typing import Dict, List, Optional, Set


class ConfigManager:
    """Manages AzerothCore configuration file updates."""

    def __init__(self, storage_path: str, overrides_file: str, dry_run: bool = False):
        self.storage_path = Path(storage_path)
        self.config_dir = self.storage_path / "config"
        self.modules_config_dir = self.storage_path / "config" / "modules"
        self.overrides_file = Path(overrides_file)
        self.dry_run = dry_run

        if not self.config_dir.exists():
            raise FileNotFoundError(f"Config directory not found: {self.config_dir}")

    def load_overrides(self) -> Dict[str, Dict[str, str]]:
        """Load configuration overrides from INI-style file."""
        if not self.overrides_file.exists():
            print(f"⚠️  Override file not found: {self.overrides_file}")
            return {}

        config = configparser.ConfigParser(interpolation=None)
        config.optionxform = str  # Preserve case sensitivity

        try:
            config.read(self.overrides_file, encoding='utf-8')
        except Exception as e:
            print(f"❌ Error reading override file: {e}")
            return {}

        overrides = {}
        for section in config.sections():
            overrides[section] = dict(config.items(section))

        return overrides

    def find_conf_file(self, filename: str) -> Optional[Path]:
        """Find a configuration file in the config directory."""
        # Check main config directory first (for core server configs)
        conf_file = self.config_dir / filename

        if conf_file.exists():
            return conf_file

        # Check modules config directory (for module configs)
        modules_conf_file = self.modules_config_dir / filename
        if modules_conf_file.exists():
            return modules_conf_file

        # Try to create from .dist file in main config directory
        dist_file = self.config_dir / f"{filename}.dist"
        if dist_file.exists():
            print(f"📄 Creating {filename} from {filename}.dist")
            if not self.dry_run:
                shutil.copy2(dist_file, conf_file)
            return conf_file

        # Try to create from .dist file in modules directory
        modules_dist_file = self.modules_config_dir / f"{filename}.dist"
        if modules_dist_file.exists():
            print(f"📄 Creating {filename} from modules/{filename}.dist")
            if not self.dry_run:
                if not self.modules_config_dir.exists():
                    self.modules_config_dir.mkdir(parents=True, exist_ok=True)
                shutil.copy2(modules_dist_file, modules_conf_file)
            return modules_conf_file

        return None

    def update_conf_file(self, conf_file: Path, settings: Dict[str, str]) -> bool:
        """Update a .conf file with new settings while preserving structure."""
        if not conf_file.exists():
            print(f"❌ Configuration file not found: {conf_file}")
            return False

        try:
            with open(conf_file, 'r', encoding='utf-8') as f:
                lines = f.readlines()
        except Exception as e:
            print(f"❌ Error reading {conf_file}: {e}")
            return False

        updated_lines = []
        updated_keys = set()

        # Process each line
        for line in lines:
            original_line = line
            stripped = line.strip()

            # Skip empty lines and comments
            if not stripped or stripped.startswith('#'):
                updated_lines.append(original_line)
                continue

            # Check if this line contains a setting we want to override
            setting_match = re.match(r'^([^=]+?)\s*=\s*(.*)$', stripped)
            if setting_match:
                key = setting_match.group(1).strip()

                if key in settings:
                    # Replace with our override value
                    new_value = settings[key]
                    # Preserve the original indentation
                    indent = len(line) - len(line.lstrip())
                    new_line = ' ' * indent + f"{key} = {new_value}\n"
                    updated_lines.append(new_line)
                    updated_keys.add(key)
                    print(f"   ✅ {key} = {new_value}")
                else:
                    # Keep original line
                    updated_lines.append(original_line)
            else:
                # Keep original line (could be section header or other content)
                updated_lines.append(original_line)

        # Add any settings that weren't found in the file
        for key, value in settings.items():
            if key not in updated_keys:
                updated_lines.append(f"{key} = {value}\n")
                print(f"   ➕ {key} = {value} (added)")

        # Write the updated file
        if not self.dry_run:
            try:
                with open(conf_file, 'w', encoding='utf-8') as f:
                    f.writelines(updated_lines)
            except Exception as e:
                print(f"❌ Error writing {conf_file}: {e}")
                return False

        return True

    def apply_overrides(self, overrides: Dict[str, Dict[str, str]],
                       filter_files: Optional[Set[str]] = None) -> bool:
        """Apply all configuration overrides."""
        success = True

        if not overrides:
            print("ℹ️  No configuration overrides to apply")
            return True

        print(f"🔧 Applying configuration overrides{' (DRY RUN)' if self.dry_run else ''}...")

        for conf_filename, settings in overrides.items():
            # Skip if we're filtering and this file isn't in the filter
            if filter_files and conf_filename not in filter_files:
                continue

            if not settings:
                continue

            print(f"\n📝 Updating {conf_filename}:")

            # Find the configuration file
            conf_file = self.find_conf_file(conf_filename)
            if not conf_file:
                print(f"   ⚠️  Configuration file not found: {conf_filename}")
                success = False
                continue

            # Update the file
            if not self.update_conf_file(conf_file, settings):
                success = False

        return success


def load_preset(preset_file: Path) -> Dict[str, Dict[str, str]]:
    """Load a preset configuration file."""
    if not preset_file.exists():
        raise FileNotFoundError(f"Preset file not found: {preset_file}")

    config = configparser.ConfigParser(interpolation=None)
    config.optionxform = str  # Preserve case sensitivity
    config.read(preset_file, encoding='utf-8')

    overrides = {}
    for section in config.sections():
        overrides[section] = dict(config.items(section))

    return overrides


def list_available_presets(preset_dir: Path) -> List[str]:
    """List available preset files."""
    if not preset_dir.exists():
        return []

    presets = []
    for preset_file in preset_dir.glob("*.conf"):
        presets.append(preset_file.stem)

    return sorted(presets)


def main():
    parser = argparse.ArgumentParser(
        description="Apply AzerothCore configuration overrides and presets"
    )
    parser.add_argument(
        "--storage-path",
        default="./storage",
        help="Path to storage directory (default: ./storage)"
    )
    parser.add_argument(
        "--overrides-file",
        default="./config/server-overrides.conf",
        help="Path to server overrides file (default: ./config/server-overrides.conf)"
    )
    parser.add_argument(
        "--preset",
        help="Apply a preset from config/presets/<name>.conf"
    )
    parser.add_argument(
        "--list-presets",
        action="store_true",
        help="List available presets"
    )
    parser.add_argument(
        "--files",
        help="Comma-separated list of .conf files to update (default: all)"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be changed without making modifications"
    )

    args = parser.parse_args()

    # Handle list presets
    if args.list_presets:
        preset_dir = Path("./config/presets")
        presets = list_available_presets(preset_dir)

        if presets:
            print("📋 Available presets:")
            for preset in presets:
                preset_file = preset_dir / f"{preset}.conf"
                print(f"   • {preset}")
                # Try to read description from preset file
                if preset_file.exists():
                    try:
                        with open(preset_file, 'r') as f:
                            first_line = f.readline().strip()
                            if first_line.startswith('#') and len(first_line) > 1:
                                description = first_line[1:].strip()
                                print(f"     {description}")
                    except:
                        pass
        else:
            print("ℹ️  No presets found in config/presets/")
        return

    try:
        # Initialize configuration manager
        config_manager = ConfigManager(
            storage_path=args.storage_path,
            overrides_file=args.overrides_file,
            dry_run=args.dry_run
        )

        # Determine which files to filter (if any)
        filter_files = None
        if args.files:
            filter_files = set(f.strip() for f in args.files.split(','))

        # Load configuration overrides
        overrides = {}

        # Load preset if specified
        if args.preset:
            preset_file = Path(f"./config/presets/{args.preset}.conf")
            print(f"📦 Loading preset: {args.preset}")
            try:
                preset_overrides = load_preset(preset_file)
                overrides.update(preset_overrides)
            except FileNotFoundError as e:
                print(f"❌ {e}")
                return 1

        # Load server overrides (this can override preset values)
        server_overrides = config_manager.load_overrides()
        overrides.update(server_overrides)

        # Apply all overrides
        success = config_manager.apply_overrides(overrides, filter_files)

        if success:
            if args.dry_run:
                print("\n✅ Configuration validation complete")
            else:
                print("\n✅ Configuration applied successfully")
                print("ℹ️  Restart your server to apply changes")
            return 0
        else:
            print("\n❌ Some configuration updates failed")
            return 1

    except Exception as e:
        print(f"❌ Error: {e}")
        return 1


if __name__ == "__main__":
    sys.exit(main())