#!/usr/bin/env python3
"""List required rewrite-job tokens for a wiki.

Prints one token per line:
  cluster tokens from schema Objects (6+ knowledge objects)
  catalog entities: entity pages with 6 or more sources:

Usage:
    wiki-required-rewrite-jobs.py --wiki-root <wiki>
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from wiki_yaml import RESERVED, extract_frontmatter, parse_yaml

OBJECTS_HEADING = "## Objects"
SKIP_NAMES = {"_index.md", "index.md", "schema.md", "log.md", "README.md"}
CATALOG_SOURCE_FLOOR = 6


def _schema_objects(wiki: Path) -> list[str]:
    schema = wiki / "schema.md"
    if not schema.is_file():
        return []
    text = schema.read_text(encoding="utf-8", errors="replace")
    collecting = False
    tokens: list[str] = []
    for line in text.splitlines():
        if line.startswith("## "):
            collecting = line.strip() == OBJECTS_HEADING
            continue
        if collecting and line.startswith("- "):
            token = line[2:].strip()
            if token and token != "(none yet)":
                tokens.append(token)
    return tokens


def _catalog_entities(wiki: Path) -> list[str]:
    entities = wiki / "entities"
    if not entities.is_dir():
        return []
    found: list[str] = []
    for path in sorted(entities.glob("*.md")):
        if path.name in SKIP_NAMES:
            continue
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        raw = extract_frontmatter(text)
        if not raw:
            continue
        try:
            parsed = parse_yaml(raw)
        except ValueError:
            continue
        if not isinstance(parsed, dict):
            continue
        sources = parsed.get("sources") or []
        if isinstance(sources, list) and len(sources) >= CATALOG_SOURCE_FLOOR:
            found.append(path.stem)
    return found


def required_tokens(wiki: Path) -> list[str]:
    seen: set[str] = set()
    out: list[str] = []
    for token in _schema_objects(wiki) + _catalog_entities(wiki):
        if token in seen:
            continue
        seen.add(token)
        out.append(token)
    return out


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="List required rewrite-job tokens.")
    parser.add_argument("--wiki-root", required=True)
    args = parser.parse_args(argv)
    wiki = Path(args.wiki_root)
    if not wiki.is_dir():
        print(f"wiki-required-rewrite-jobs: wiki root missing: {wiki}", file=sys.stderr)
        return 2
    for token in required_tokens(wiki):
        print(token)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
