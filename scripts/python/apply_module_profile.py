#!/usr/bin/env python3
"""
Apply a module profile to .env file for CI/CD builds.

This script reads a module profile JSON and enables the specified modules
in the .env file, ready for automated builds.
"""

import argparse
import json
import sys
from pathlib import Path
from typing import List, Set


def load_profile(profile_path: Path) -> List[str]:
    """Load module list from a profile JSON file."""
    try:
        with open(profile_path, 'r') as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"ERROR: Profile not found: {profile_path}", file=sys.stderr)
        sys.exit(1)
    except json.JSONDecodeError as e:
        print(f"ERROR: Invalid JSON in profile: {e}", file=sys.stderr)
        sys.exit(1)

    modules = data.get('modules', [])
    if not isinstance(modules, list):
        print("ERROR: 'modules' must be a list in profile JSON", file=sys.stderr)
        sys.exit(1)

    return [m.strip() for m in modules if m.strip()]


def read_env_template(template_path: Path) -> List[str]:
    """Read the .env.template file."""
    try:
        with open(template_path, 'r') as f:
            return f.readlines()
    except FileNotFoundError:
        print(f"ERROR: Template not found: {template_path}", file=sys.stderr)
        sys.exit(1)


def apply_profile_to_env(template_lines: List[str], enabled_modules: Set[str]) -> List[str]:
    """
    Process template lines and enable specified modules.

    Sets MODULE_* variables to 1 if they're in enabled_modules, otherwise keeps template value.
    """
    output_lines = []

    for line in template_lines:
        stripped = line.strip()

        # Check if this is a MODULE_ variable line
        if stripped.startswith('MODULE_') and '=' in stripped:
            # Extract the module name (before the =)
            module_name = stripped.split('=')[0].strip()

            if module_name in enabled_modules:
                # Enable this module
                output_lines.append(f"{module_name}=1\n")
            else:
                # Keep original line (usually =0 or commented)
                output_lines.append(line)
        else:
            # Not a module line, keep as-is
            output_lines.append(line)

    return output_lines


def write_env_file(env_path: Path, lines: List[str]):
    """Write the processed lines to .env file."""
    try:
        with open(env_path, 'w') as f:
            f.writelines(lines)
        print(f"✅ Applied profile to {env_path}")
    except IOError as e:
        print(f"ERROR: Failed to write .env file: {e}", file=sys.stderr)
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(
        description='Apply a module profile to .env file for automated builds'
    )
    parser.add_argument(
        'profile',
        help='Name of the profile (e.g., RealmMaster) or path to profile JSON'
    )
    parser.add_argument(
        '--env-template',
        default='.env.template',
        help='Path to .env.template file (default: .env.template)'
    )
    parser.add_argument(
        '--env-output',
        default='.env',
        help='Path to output .env file (default: .env)'
    )
    parser.add_argument(
        '--profiles-dir',
        default='config/module-profiles',
        help='Directory containing profile JSON files (default: config/module-profiles)'
    )
    parser.add_argument(
        '--list-modules',
        action='store_true',
        help='List modules that will be enabled and exit'
    )

    args = parser.parse_args()

    # Resolve profile path
    profile_path = Path(args.profile)
    if not profile_path.exists():
        # Try treating it as a profile name
        profile_path = Path(args.profiles_dir) / f"{args.profile}.json"

    if not profile_path.exists():
        print(f"ERROR: Profile not found: {args.profile}", file=sys.stderr)
        print(f"  Tried: {Path(args.profile)}", file=sys.stderr)
        print(f"  Tried: {profile_path}", file=sys.stderr)
        sys.exit(1)

    # Load the profile
    print(f"📋 Loading profile: {profile_path.name}")
    enabled_modules = set(load_profile(profile_path))

    if args.list_modules:
        print(f"\nModules to be enabled ({len(enabled_modules)}):")
        for module in sorted(enabled_modules):
            print(f"  • {module}")
        return

    print(f"✓ Found {len(enabled_modules)} modules in profile")

    # Read template
    template_path = Path(args.env_template)
    template_lines = read_env_template(template_path)

    # Apply profile
    output_lines = apply_profile_to_env(template_lines, enabled_modules)

    # Write output
    env_path = Path(args.env_output)
    write_env_file(env_path, output_lines)

    print(f"✓ Profile '{profile_path.stem}' applied successfully")
    print(f"\nEnabled modules:")
    for module in sorted(enabled_modules)[:10]:  # Show first 10
        print(f"  • {module}")
    if len(enabled_modules) > 10:
        print(f"  ... and {len(enabled_modules) - 10} more")


if __name__ == '__main__':
    main()
