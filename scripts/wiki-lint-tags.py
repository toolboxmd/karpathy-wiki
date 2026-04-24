#!/usr/bin/env python3
"""Tag-drift lint for the wiki.

Modes:
    wiki-lint-tags.py --wiki-root <wiki> --all
    wiki-lint-tags.py --wiki-root <wiki> <page-path>

--all:       Walk every page; report orphan tags, synonym pairs, and a summary.
--page path: Inspect one page; for each tag, report whether it is new relative
             to the rest of the wiki. Never non-zero exit (this is a hint, not
             a gate).

Synonym heuristics (flagged as likely-same-concept):
  1. Shared prefix of >= 5 chars (case-insensitive).
  2. Case-insensitive Levenshtein distance <= 2 AND shorter tag length >= 4.
  3. Explicit pair listed under "## Tag Synonyms" in schema.md, e.g.:
         - dental == dentistry
"""

import re
import sys
from pathlib import Path

_FM_RE = re.compile(r"^---\s*\n(.*?)\n---\s*\n", re.DOTALL)
_TAG_INLINE_RE = re.compile(r"^tags:\s*\[(.*)\]\s*$", re.MULTILINE)
_TAG_BLOCK_RE = re.compile(r"^tags:\s*\n((?:  -[^\n]*\n)+)", re.MULTILINE)


def _levenshtein(a: str, b: str) -> int:
    if a == b:
        return 0
    if len(a) > len(b):
        a, b = b, a
    prev = list(range(len(a) + 1))
    for j, bc in enumerate(b, 1):
        curr = [j] + [0] * len(a)
        for i, ac in enumerate(a, 1):
            cost = 0 if ac == bc else 1
            curr[i] = min(curr[i-1] + 1, prev[i] + 1, prev[i-1] + cost)
        prev = curr
    return prev[-1]


def _extract_tags(page_text: str) -> list[str]:
    m = _FM_RE.match(page_text)
    if not m:
        return []
    fm = m.group(1)
    tags: list[str] = []
    ilm = _TAG_INLINE_RE.search(fm)
    if ilm:
        raw = ilm.group(1).strip()
        if raw:
            tags = [t.strip().strip('"').strip("'") for t in raw.split(",") if t.strip()]
        return tags
    bm = _TAG_BLOCK_RE.search(fm)
    if bm:
        for line in bm.group(1).splitlines():
            t = line.strip().lstrip("-").strip().strip('"').strip("'")
            if t:
                tags.append(t)
    return tags


def _walk_pages(wiki: Path) -> list[Path]:
    out: list[Path] = []
    for cat in ("concepts", "entities", "sources", "queries"):
        p = wiki / cat
        if p.is_dir():
            out.extend(p.rglob("*.md"))
    return out


def _load_synonym_pairs(wiki: Path) -> list[tuple[str, str]]:
    schema = wiki / "schema.md"
    pairs: list[tuple[str, str]] = []
    if not schema.is_file():
        return pairs
    text = schema.read_text()
    in_section = False
    for line in text.splitlines():
        if line.strip().startswith("## Tag Synonyms"):
            in_section = True
            continue
        if in_section and line.startswith("## "):
            break
        if in_section:
            m = re.match(r"^\s*-\s*(\S+)\s*==\s*(\S+)\s*$", line)
            if m:
                pairs.append((m.group(1).lower(), m.group(2).lower()))
    return pairs


def _is_prefix_synonym(a: str, b: str) -> bool:
    if a == b:
        return False
    al, bl = a.lower(), b.lower()
    shortest = min(len(al), len(bl))
    common = 0
    for i in range(shortest):
        if al[i] == bl[i]:
            common += 1
        else:
            break
    return common >= 5


def _is_levenshtein_synonym(a: str, b: str) -> bool:
    if a == b:
        return False
    al, bl = a.lower(), b.lower()
    if min(len(al), len(bl)) < 4:
        return False
    return _levenshtein(al, bl) <= 2


def _pairs(tags: list[str]) -> list[tuple[str, str]]:
    sorted_tags = sorted(set(tags))
    out: list[tuple[str, str]] = []
    for i in range(len(sorted_tags)):
        for j in range(i + 1, len(sorted_tags)):
            out.append((sorted_tags[i], sorted_tags[j]))
    return out


def cmd_all(wiki: Path) -> int:
    pages = _walk_pages(wiki)
    tag_counts: dict[str, int] = {}
    for p in pages:
        for t in _extract_tags(p.read_text()):
            tag_counts[t] = tag_counts.get(t, 0) + 1
    all_tags = sorted(tag_counts.keys())

    synonym_pairs_flagged: list[tuple[str, str, str]] = []  # (a, b, reason)
    for a, b in _pairs(all_tags):
        if _is_prefix_synonym(a, b):
            synonym_pairs_flagged.append((a, b, "shared prefix >=5 chars"))
        elif _is_levenshtein_synonym(a, b):
            synonym_pairs_flagged.append((a, b, "levenshtein <=2"))

    schema_pairs = _load_synonym_pairs(wiki)
    for a, b in schema_pairs:
        if a in tag_counts and b in tag_counts:
            synonym_pairs_flagged.append((a, b, "schema-listed synonym"))

    orphans = sorted([t for t, n in tag_counts.items() if n < 2])

    print(f"distinct tags: {len(all_tags)}")
    print(f"synonym pairs flagged: {len(synonym_pairs_flagged)}")
    for a, b, reason in synonym_pairs_flagged:
        print(f"  synonym: {a} <-> {b} ({reason})")
    print(f"orphan tags (used by <2 pages): {len(orphans)}")
    for o in orphans:
        print(f"  orphan: {o}")
    return 0


def cmd_page(wiki: Path, page: Path) -> int:
    all_tags: dict[str, int] = {}
    for p in _walk_pages(wiki):
        if p.resolve() == page.resolve():
            continue
        for t in _extract_tags(p.read_text()):
            all_tags[t] = all_tags.get(t, 0) + 1
    page_tags = _extract_tags(page.read_text())
    for t in page_tags:
        if t not in all_tags:
            print(f"new tag: {t}", file=sys.stderr)
    # Flag synonym candidates against existing tags.
    for t in page_tags:
        for existing in all_tags:
            if _is_prefix_synonym(t, existing) or _is_levenshtein_synonym(t, existing):
                print(f"possible synonym: {t} ~ {existing}", file=sys.stderr)
    return 0


def main() -> int:
    argv = sys.argv[1:]
    if len(argv) >= 2 and argv[0] == "--wiki-root":
        wiki = Path(argv[1]).resolve()
        rest = argv[2:]
    else:
        print("usage: wiki-lint-tags.py --wiki-root ROOT (--all | <page>)",
              file=sys.stderr)
        return 1
    if not wiki.is_dir():
        print(f"not a directory: {wiki}", file=sys.stderr)
        return 1
    if rest == ["--all"]:
        return cmd_all(wiki)
    if len(rest) == 1 and not rest[0].startswith("--"):
        return cmd_page(wiki, Path(rest[0]).resolve())
    print("usage: wiki-lint-tags.py --wiki-root ROOT (--all | <page>)",
          file=sys.stderr)
    return 1


if __name__ == "__main__":
    if sys.version_info < (3, 11):
        print("python 3.11+ required", file=sys.stderr)
        sys.exit(1)
    sys.exit(main())
