#!/usr/bin/env python3
"""Insert a default quality: block into any page missing one.

Usage:
    wiki-backfill-quality.py --wiki-root <wiki-root>

Walks concepts/, entities/, sources/, queries/ recursively.
For each page WITHOUT a `quality:` key in frontmatter, appends:

  quality:
    accuracy: 3
    completeness: 3
    signal: 3
    interlinking: 3
    overall: 3.00
    rated_at: "<now>"
    rated_by: ingester
    notes: "backfilled in v2-hardening; not yet re-rated"

Pages WITH a `quality:` block are left untouched (including `rated_by: human`).
Idempotent.
"""

import re
import sys
from datetime import datetime, timezone
from pathlib import Path

QUALITY_DEFAULT_TEMPLATE = """quality:
  accuracy: 3
  completeness: 3
  signal: 3
  interlinking: 3
  overall: 3.00
  rated_at: "{now}"
  rated_by: ingester
  notes: "backfilled in v2-hardening; not yet re-rated"
"""


def _now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _split_fm(text: str) -> tuple[list[str] | None, str | None]:
    if not text.startswith("---\n"):
        return None, None
    lines = text.splitlines(keepends=True)
    for i in range(1, len(lines)):
        if lines[i].rstrip("\n") == "---":
            return lines[1:i], "".join(lines[i+1:])
    return None, None


def _has_quality(fm_lines: list[str]) -> bool:
    return any(re.match(r"^quality:\s*$", l.rstrip("\n")) for l in fm_lines)


def _process(page: Path) -> bool:
    text = page.read_text()
    fm, body = _split_fm(text)
    if fm is None:
        return False  # no frontmatter; normalize script should have handled
    if _has_quality(fm):
        return False
    insert = QUALITY_DEFAULT_TEMPLATE.format(now=_now())
    new_fm_text = "".join(fm) + insert
    new_text = "---\n" + new_fm_text + "---\n" + (body or "")
    page.write_text(new_text)
    return True


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[1] != "--wiki-root":
        print("usage: wiki-backfill-quality.py --wiki-root <wiki-root>",
              file=sys.stderr)
        return 1
    root = Path(sys.argv[2]).resolve()
    if not root.is_dir():
        print(f"not a directory: {root}", file=sys.stderr)
        return 1

    changed = 0
    for category in ("concepts", "entities", "sources", "queries"):
        cat = root / category
        if not cat.is_dir():
            continue
        for page in cat.rglob("*.md"):
            if _process(page):
                changed += 1
                print(f"backfilled: {page}")
    print(f"done. {changed} page(s) backfilled.")
    return 0


if __name__ == "__main__":
    if sys.version_info < (3, 11):
        print("python 3.11+ required", file=sys.stderr)
        sys.exit(1)
    sys.exit(main())
