#!/usr/bin/env python3
"""Rewrite inbound links to moved pages.

Usage:
    wiki-relink.py --wiki-root <root> --moved <old-rel-path>=<new-rel-path> [...]

Only rewrites links whose target matches an old-rel-path (after resolution).
Other links untouched. External links (http://, https://, mailto:, #anchor)
are skipped. Idempotent.

Exit codes:
    0 - success
    1 - argument or filesystem error
"""
import argparse
import re
import sys
from pathlib import Path

# Match markdown link: [text](href)
LINK_RE = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")


def rewrite_in_file(file: Path, moves: dict[str, str], wiki_root: Path) -> bool:
    """Return True if the file was modified."""
    text = file.read_text()
    modified = False

    def repl(match: re.Match) -> str:
        nonlocal modified
        anchor, href = match.group(1), match.group(2)
        # Skip external links and anchors
        if href.startswith(("http://", "https://", "mailto:", "#")):
            return match.group(0)
        # Resolve href to wiki-root-relative form
        if href.startswith("/"):
            target_rel = href[1:]
        else:
            try:
                target_abs = (file.parent / href).resolve()
                target_rel = str(target_abs.relative_to(wiki_root))
            except ValueError:
                return match.group(0)  # outside wiki
        if target_rel in moves:
            new_target = moves[target_rel]
            modified = True
            return f"[{anchor}](/{new_target})"
        return match.group(0)

    new_text = LINK_RE.sub(repl, text)
    if new_text != text:
        file.write_text(new_text)
    return modified


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--wiki-root", required=True)
    p.add_argument("--moved", action="append", default=[],
                   help="OLD=NEW (wiki-relative paths). Repeatable.")
    args = p.parse_args()

    root = Path(args.wiki_root).resolve()
    if not root.is_dir():
        print(f"not a directory: {root}", file=sys.stderr)
        return 1

    moves = {}
    for mv in args.moved:
        if "=" not in mv:
            print(f"invalid --moved: {mv}", file=sys.stderr)
            return 1
        old, new = mv.split("=", 1)
        moves[old] = new

    changed = 0
    for md in root.rglob("*.md"):
        # Skip files in reserved/dotted dirs
        rel_parts = md.relative_to(root).parts
        if any(p in {"raw", "index", "archive", "Clippings"} or p.startswith(".") for p in rel_parts[:-1]):
            continue
        if rewrite_in_file(md, moves, root):
            changed += 1
            print(f"rewrote: {md.relative_to(root)}")
    print(f"done. {changed} file(s) updated.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
