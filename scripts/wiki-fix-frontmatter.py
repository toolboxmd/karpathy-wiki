#!/usr/bin/env python3
"""Recompute type: in YAML frontmatter from path.parts[0] (plural form).

Frontmatter-only: never modifies body content.
Imports the shared parser from wiki_yaml.py to avoid drift.
"""
import argparse
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from wiki_yaml import split_frontmatter


FRONTMATTER_TYPE_RE = re.compile(r"^type:\s*\S.*$", re.MULTILINE)


def _expected_type(page: Path, wiki_root: Path) -> str:
    rel = page.resolve().relative_to(wiki_root.resolve())
    return rel.parts[0]


def fix_page(page: Path, wiki_root: Path) -> bool:
    """Return True if the page was modified."""
    text = page.read_text()
    opener, fm, after = split_frontmatter(text)
    if fm is None:
        print(f"skip (no frontmatter): {page}", file=sys.stderr)
        return False

    expected = _expected_type(page, wiki_root)

    new_fm, n = FRONTMATTER_TYPE_RE.subn(f"type: {expected}", fm, count=1)
    if n == 0:
        # No type: line; insert immediately after the first line of frontmatter
        lines = fm.split("\n", 1)
        if len(lines) == 1:
            new_fm = f"type: {expected}\n" + fm
        else:
            new_fm = f"{lines[0]}\ntype: {expected}\n{lines[1]}"

    if new_fm == fm:
        return False  # already correct (idempotent no-op)

    # Reconstruction: opener already ends with \n; fm has no trailing \n;
    # after starts with '---\n...'. Insert exactly one \n between fm and after.
    page.write_text(opener + new_fm + "\n" + after)
    return True


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--wiki-root", required=True)
    p.add_argument("page", nargs="?")
    p.add_argument("--all", action="store_true")
    args = p.parse_args()

    root = Path(args.wiki_root).resolve()
    if not root.is_dir():
        print(f"not a directory: {root}", file=sys.stderr)
        return 1

    if args.all:
        changed = 0
        for page in sorted(root.rglob("*.md")):
            rel_parts = page.relative_to(root).parts
            if rel_parts[0] in {"raw", "index", "archive", "Clippings"}:
                continue
            if rel_parts[0].startswith("."):
                continue
            if fix_page(page, root):
                changed += 1
                print(f"fixed: {page.relative_to(root)}")
        print(f"done. {changed} page(s) modified.")
        return 0

    if not args.page:
        print("usage: wiki-fix-frontmatter.py --wiki-root <root> (<page> | --all)", file=sys.stderr)
        return 1
    page = Path(args.page).resolve()
    if not page.is_file():
        print(f"not a file: {page}", file=sys.stderr)
        return 1
    if fix_page(page, root):
        print(f"fixed: {page.relative_to(root)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
