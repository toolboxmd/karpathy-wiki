#!/usr/bin/env python3
"""Read a TOML config value by dotted key.

Usage:
    wiki-config-read.py <path-to-.wiki-config> <dotted.key>

Exits 0 on success (prints value to stdout).
Exits 1 on missing file, missing key, or malformed TOML.
"""

import sys


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: wiki-config-read.py <path> <dotted.key>", file=sys.stderr)
        return 1

    path = sys.argv[1]
    key = sys.argv[2]

    try:
        # tomllib is stdlib in Python 3.11+
        import tomllib
    except ImportError:
        print("python3.11+ required (tomllib not available)", file=sys.stderr)
        return 1

    try:
        with open(path, "rb") as f:
            data = tomllib.load(f)
    except FileNotFoundError:
        print(f"config not found: {path}", file=sys.stderr)
        return 1
    except tomllib.TOMLDecodeError as e:
        print(f"malformed TOML: {e}", file=sys.stderr)
        return 1

    # Walk the dotted key path.
    current = data
    for part in key.split("."):
        if not isinstance(current, dict) or part not in current:
            print(f"key not found: {key}", file=sys.stderr)
            return 1
        current = current[part]

    # Print scalar values cleanly. For tables/arrays emit JSON so callers
    # can parse reliably (repr() produces Python-specific syntax).
    import json as _json
    if isinstance(current, bool):
        print("true" if current else "false")
    elif isinstance(current, (int, float, str)):
        print(current)
    elif isinstance(current, (dict, list)):
        print(_json.dumps(current))
    else:
        print(str(current))
    return 0


if __name__ == "__main__":
    sys.exit(main())
