#!/usr/bin/env python3
"""Walk a wiki root and emit categories, reserved set, depths, and counts as JSON.

Usage:
    wiki-discover.py --wiki-root <wiki-root>

Output (stdout): JSON with keys:
    categories: list[str]   - top-level dirs that ARE categories (sorted)
    reserved:   list[str]   - directory names that are NEVER categories (the constant set)
    depths:     dict[str, int]  - max depth of any .md file under this category
                                  (1 = flat; 2 = one level of subdir; ...)
    counts:     dict[str, int]  - total .md file count under this category (recursive)

A "top-level dir" is a direct subdirectory of <wiki-root>.
A "category" is a top-level dir whose name is NOT in the reserved set AND does NOT start with "." .

Exit codes:
    0 - success
    1 - argument error or wiki-root not a directory
"""
import argparse
import json
import sys
from pathlib import Path

# Reserved names (Python constant, also mirrored to schema.md by Phase A.1 of v2.3).
RESERVED = {"raw", "index", "archive", "Clippings"}


def _is_category(name: str) -> bool:
    return name not in RESERVED and not name.startswith(".")


def _walk_category(root: Path) -> tuple[int, int]:
    """Return (count_of_md_files, max_depth) for a category root.

    depth 1 means files directly under the category (e.g. concepts/foo.md).
    depth 2 means one level of subdir (e.g. projects/a/foo.md).
    """
    count = 0
    max_depth = 0
    for path in root.rglob("*.md"):
        # Skip files in reserved or dotted subdirectories at any depth.
        rel_parts = path.relative_to(root).parts
        if any(p in RESERVED or p.startswith(".") for p in rel_parts[:-1]):
            continue
        count += 1
        depth = len(rel_parts)  # filename is the last part
        if depth > max_depth:
            max_depth = depth
    return count, max_depth


def discover(wiki_root: Path) -> dict:
    if not wiki_root.is_dir():
        raise NotADirectoryError(f"not a directory: {wiki_root}")
    categories: list[str] = []
    depths: dict[str, int] = {}
    counts: dict[str, int] = {}
    for entry in sorted(wiki_root.iterdir()):
        if not entry.is_dir():
            continue
        if not _is_category(entry.name):
            continue
        categories.append(entry.name)
        c, d = _walk_category(entry)
        counts[entry.name] = c
        depths[entry.name] = d
    return {
        "categories": categories,
        "reserved": sorted(RESERVED),
        "depths": depths,
        "counts": counts,
    }


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--wiki-root", required=True, help="absolute path to wiki root")
    args = p.parse_args()
    try:
        data = discover(Path(args.wiki_root).resolve())
    except NotADirectoryError as e:
        print(str(e), file=sys.stderr)
        return 1
    json.dump(data, sys.stdout, indent=2, sort_keys=True)
    sys.stdout.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
