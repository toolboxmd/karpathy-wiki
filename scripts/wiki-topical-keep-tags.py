#!/usr/bin/env python3
"""Strip provenance tags and untopical spray tags. Never touch sources or body.

Usage:
    wiki-topical-keep-tags.py --wiki-root <wiki-root>
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from wiki_yaml import RESERVED, extract_frontmatter, parse_yaml, split_frontmatter

SKIP_NAMES = {"_index.md", "index.md", "schema.md", "log.md", "README.md"}
PROVENANCE_TAGS = frozenset({"external-opinion", "external-expert"})
INLINE_TAGS_RE = re.compile(r"^tags:\s*\[[^\]]*\][^\n]*\n?", re.MULTILINE)
BLOCK_TAGS_RE = re.compile(
    r"^tags:\s*\n(?:[ \t]*-[^\n]*\n)+",
    re.MULTILINE,
)
WORD_RE = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*")
OBJECTS_HEADING = "## Objects"


def _pages(wiki: Path) -> list[Path]:
    found: list[Path] = []
    for path in wiki.rglob("*.md"):
        rel = path.relative_to(wiki)
        if any(part.startswith(".") or part in RESERVED for part in rel.parts[:-1]):
            continue
        if path.name in SKIP_NAMES:
            continue
        found.append(path)
    return found


def _parse_page(path: Path) -> dict | None:
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return None
    raw = extract_frontmatter(text)
    if not raw:
        return None
    try:
        parsed = parse_yaml(raw)
    except ValueError:
        return None
    if not isinstance(parsed, dict):
        return None
    parsed["_text"] = text
    return parsed


def _owner_tag(parsed: dict) -> str:
    owner = parsed.get("source_owner")
    if not isinstance(owner, str) or not owner.strip():
        return ""
    return "-".join(WORD_RE.findall(owner.lower()))


def _schema_objects(wiki: Path) -> set[str]:
    schema = wiki / "schema.md"
    if not schema.is_file():
        return set()
    text = schema.read_text(encoding="utf-8", errors="replace")
    collecting = False
    objects: set[str] = set()
    for line in text.splitlines():
        if line.startswith("## "):
            collecting = line.strip() == OBJECTS_HEADING
            continue
        if collecting and line.startswith("- "):
            token = line[2:].strip().lower()
            if token:
                objects.add(token)
    return objects


def _tag_df(pages: list[Path]) -> dict[str, int]:
    counts: dict[str, int] = {}
    for path in pages:
        parsed = _parse_page(path)
        if not parsed:
            continue
        tags = parsed.get("tags") or []
        if not isinstance(tags, list):
            continue
        seen: set[str] = set()
        for item in tags:
            tag = str(item).strip().lower()
            if not tag or tag in seen:
                continue
            seen.add(tag)
            counts[tag] = counts.get(tag, 0) + 1
    return counts


def _keep_tag(
    tag: str,
    *,
    title: str,
    summary: str,
    owner: str,
    objects: set[str],
    df: dict[str, int],
    n_pages: int,
) -> bool:
    if tag in PROVENANCE_TAGS:
        return False
    if tag == "pointer":
        return True
    if owner and tag == owner:
        return True
    blob = f"{title} {summary}".lower()
    if tag in blob:
        return True
    if tag in objects:
        return True
    if n_pages >= 2 and df.get(tag, 0) * 2 >= n_pages:
        return False
    return True


def _rewrite_tags(path: Path, new_tags: list[str]) -> bool:
    text = path.read_text(encoding="utf-8")
    opener, fm_block, after = split_frontmatter(text)
    if opener is None or fm_block is None or after is None:
        return False
    rendered = "tags: [" + ", ".join(new_tags) + "]\n"
    if INLINE_TAGS_RE.search(fm_block):
        new_fm = INLINE_TAGS_RE.sub(rendered, fm_block, count=1)
    elif BLOCK_TAGS_RE.search(fm_block):
        new_fm = BLOCK_TAGS_RE.sub(rendered, fm_block, count=1)
    else:
        return False
    if new_fm == fm_block:
        return False
    path.write_text(opener + new_fm + "\n" + after)
    return True


def apply_keep(wiki: Path) -> int:
    pages = _pages(wiki)
    objects = _schema_objects(wiki)
    df = _tag_df(pages)
    n_pages = len(pages)
    changed = 0
    for path in pages:
        parsed = _parse_page(path)
        if not parsed:
            continue
        tags = parsed.get("tags") or []
        if not isinstance(tags, list):
            continue
        title = str(parsed.get("title") or "")
        summary = str(parsed.get("summary") or "")
        owner = _owner_tag(parsed)
        kept: list[str] = []
        seen: set[str] = set()
        for item in tags:
            tag = str(item).strip()
            key = tag.lower()
            if not key or key in seen:
                continue
            if not _keep_tag(
                key,
                title=title,
                summary=summary,
                owner=owner,
                objects=objects,
                df=df,
                n_pages=n_pages,
            ):
                continue
            seen.add(key)
            kept.append(tag if tag.lower() == key else key)
        original = [str(t).strip() for t in tags if str(t).strip()]
        if kept == original:
            continue
        if _rewrite_tags(path, kept):
            changed += 1
    if changed:
        rebuild = Path(__file__).parent / "wiki-build-index.py"
        subprocess.run(
            [sys.executable, str(rebuild), "--wiki-root", str(wiki), "--rebuild-all"],
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    return changed


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Strip provenance and untopical spray tags; never edit sources."
    )
    parser.add_argument("--wiki-root", required=True)
    args = parser.parse_args(argv)
    wiki = Path(args.wiki_root)
    if not wiki.is_dir():
        print(f"wiki-topical-keep-tags: wiki root missing: {wiki}", file=sys.stderr)
        return 2
    apply_keep(wiki)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
