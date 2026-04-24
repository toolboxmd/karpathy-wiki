#!/usr/bin/env python3
"""Normalize a single wiki page's YAML frontmatter to the v2-hardening schema.

Usage:
    wiki-normalize-frontmatter.py --wiki-root <wiki_root> <page_path>

Changes applied (all idempotent):
  1. Add `type: <concept|entity|source|query>` inferred from the page's
     parent directory name. Only added when missing.
  2. If `created` or `updated` is a short date like `2026-04-24`, expand to
     `"2026-04-24T00:00:00Z"`.
  3. If `updated` is missing, copy `created`.
  4. If any entry in `sources:` is a nested mapping like `- key: value`,
     flatten it to the bare key (e.g. `- conversation`). The value is
     dropped.
  5. Legacy source-page schema migration: if the page has a top-level
     `raw:` key (scalar pointing to a raw/ path), translate to a
     `sources:` block list with that one entry. If the page has
     `captured_at:` but no `created:`, translate captured_at → created.
     Drop `pages_derived:` (the derived pages are listed as markdown
     links in the body, and the manifest's `referenced_by` is the
     machine-readable version). If `tags:` is missing after this
     migration, seed with `tags: [source]` so the validator is happy —
     the real domain tags are filled in by wiki doctor or by hand later.

This script does NOT:
  - Add the `quality:` block (Phase B, Task 36 does that).
  - Alter body content.
  - Rewrite frontmatter fields outside the list above.
  - Reorder keys unless the original key was missing and is being added.

Python 3.11+.
"""

import re
import sys
from pathlib import Path

VALID_TYPES = {"concepts": "concept", "entities": "entity",
               "sources": "concept", "queries": "query"}
SHORT_DATE_RE = re.compile(r'^(\d{4}-\d{2}-\d{2})$')


def _split_frontmatter(text: str) -> tuple[list[str], str] | tuple[None, None]:
    """Return (frontmatter-lines-without-delimiters, body) or (None, None)."""
    if not text.startswith("---\n"):
        return (None, None)
    lines = text.splitlines(keepends=True)
    # find closing "---" on a line by itself, after line 0
    for i in range(1, len(lines)):
        if lines[i].rstrip("\n") == "---":
            fm = lines[1:i]
            body = "".join(lines[i+1:])
            return (fm, body)
    return (None, None)


def _infer_type(page_path: Path, wiki_root: Path) -> str | None:
    rel = page_path.relative_to(wiki_root)
    if len(rel.parts) < 2:
        return None
    parent = rel.parts[0]
    return VALID_TYPES.get(parent)


def _expand_date(value: str) -> str:
    # Strip quotes if any
    raw = value.strip().strip('"').strip("'")
    m = SHORT_DATE_RE.match(raw)
    if m:
        return f'"{raw}T00:00:00Z"'
    # Already has time? ensure it's quoted for stability
    if 'T' in raw and raw.endswith('Z'):
        return f'"{raw}"'
    return value  # leave alone; validator will flag if still invalid


def _migrate_legacy_source_schema(fm: list[str]) -> list[str]:
    """First-pass migration of legacy source-page frontmatter to the v2-hardening
    schema. Idempotent: returns `fm` unchanged if no legacy keys present.

    Rules:
    - `raw: raw/<basename>.md` scalar -> `sources:` block list with that one entry.
    - `captured_at: <value>` -> `created: <value>` (only if `created:` not present).
    - Drop `pages_derived:` block (incl. its list body).
    - If tags: missing AFTER the above, add `tags: [source]` as a stub.
    """
    has_raw_scalar = False
    has_captured_at = False
    has_sources = False
    has_created = False
    has_tags = False
    raw_value: str | None = None
    captured_at_value: str | None = None

    # First scan: detect what's present.
    for line in fm:
        stripped = line.rstrip("\n")
        if re.match(r'^raw:\s+\S', stripped) and not stripped.startswith("raw/"):
            has_raw_scalar = True
            raw_value = stripped.split(":", 1)[1].strip()
        elif re.match(r'^captured_at:\s+', stripped):
            has_captured_at = True
            captured_at_value = stripped.split(":", 1)[1].strip()
        elif stripped == 'sources:':
            has_sources = True
        elif re.match(r'^created:\s+', stripped):
            has_created = True
        elif re.match(r'^tags:\s+', stripped) or stripped == 'tags:':
            has_tags = True

    # Fast path: no legacy keys, no-op.
    if not has_raw_scalar and not has_captured_at:
        return fm

    # Second pass: rewrite.
    out: list[str] = []
    in_pages_derived = False
    for line in fm:
        stripped = line.rstrip("\n")
        # Drop the pages_derived: block and its list body entirely.
        if stripped == 'pages_derived:':
            in_pages_derived = True
            continue
        if in_pages_derived:
            if line.startswith("  ") or line.startswith("\t") or \
               line.startswith("- ") or line.startswith(" -"):
                continue
            in_pages_derived = False
        # Translate `raw: raw/foo.md` to a `sources:` block list, unless
        # sources: already exists (then just drop the raw: line to avoid a
        # duplicate key).
        if has_raw_scalar and re.match(r'^raw:\s+\S', stripped) and \
                not stripped.startswith("raw/"):
            if not has_sources and raw_value is not None:
                out.append('sources:\n')
                out.append(f'  - {raw_value}\n')
                has_sources = True
            # else: drop the raw: scalar; sources: block already present.
            continue
        # Translate captured_at: -> created: (only if no created: yet).
        if re.match(r'^captured_at:\s+', stripped):
            if not has_created and captured_at_value is not None:
                out.append(f'created: {captured_at_value}\n')
                has_created = True
            # else: drop captured_at:; created: already present.
            continue
        out.append(line)

    # Seed tags: [source] if still missing after migration.
    if not has_tags:
        # Insert after title: line if present, else at end.
        inserted = False
        result: list[str] = []
        for line in out:
            result.append(line)
            if not inserted and line.startswith("title:"):
                result.append('tags: [source]\n')
                inserted = True
        if not inserted:
            result.append('tags: [source]\n')
        out = result

    return out


def _process_fm(fm: list[str], inferred_type: str | None) -> list[str]:
    # Phase 1: migrate legacy source-page schema if applicable.
    fm = _migrate_legacy_source_schema(fm)

    out: list[str] = []
    has_type = False
    has_updated = False
    created_value: str | None = None
    i = 0
    while i < len(fm):
        line = fm[i]
        stripped = line.rstrip("\n")
        # type: ... detection
        if re.match(r'^type:\s*', stripped):
            has_type = True
            out.append(line)
            i += 1
            continue
        # updated: ...
        m_upd = re.match(r'^updated:\s*(.*)$', stripped)
        if m_upd:
            has_updated = True
            out.append(f'updated: {_expand_date(m_upd.group(1))}\n')
            i += 1
            continue
        # created: ...
        m_cre = re.match(r'^created:\s*(.*)$', stripped)
        if m_cre:
            expanded = _expand_date(m_cre.group(1))
            created_value = expanded
            out.append(f'created: {expanded}\n')
            i += 1
            continue
        # sources: on its own line (block list opener) -- scan subsequent
        # lines and flatten any "- key: value" into "- key".
        if stripped == 'sources:':
            out.append(line)
            i += 1
            while i < len(fm):
                item = fm[i]
                item_stripped = item.rstrip("\n")
                if item_stripped.startswith("  - ") or item_stripped.startswith("- "):
                    content = item_stripped.lstrip()
                    if content.startswith("- "):
                        content = content[2:]
                    if ":" in content and not (content.startswith('"') or content.startswith("'")):
                        # Flatten: "conversation: '2026-04-24 chat'" -> "conversation"
                        k = content.split(":", 1)[0].strip()
                        out.append(f'  - {k}\n')
                    else:
                        out.append(item)
                    i += 1
                    continue
                # end of block list
                break
            continue
        out.append(line)
        i += 1

    # Add missing type before closing (prepend above body -- append at end
    # of frontmatter).
    if not has_type and inferred_type is not None:
        # Insert after the first title line if present, else append.
        inserted = False
        result: list[str] = []
        for line in out:
            result.append(line)
            if not inserted and line.startswith("title:"):
                result.append(f'type: {inferred_type}\n')
                inserted = True
        if not inserted:
            result.append(f'type: {inferred_type}\n')
        out = result

    # Add missing updated: copy created
    if not has_updated and created_value is not None:
        out.append(f'updated: {created_value}\n')

    return out


def main() -> int:
    argv = sys.argv[1:]
    if len(argv) != 3 or argv[0] != "--wiki-root":
        print("usage: wiki-normalize-frontmatter.py --wiki-root ROOT <page>",
              file=sys.stderr)
        return 1
    wiki_root = Path(argv[1]).resolve()
    page = Path(argv[2]).resolve()
    if not page.is_file():
        print(f"not a file: {page}", file=sys.stderr)
        return 1
    if not wiki_root.is_dir():
        print(f"not a directory: {wiki_root}", file=sys.stderr)
        return 1

    text = page.read_text()
    fm, body = _split_frontmatter(text)
    if fm is None:
        # No frontmatter -- leave the page alone (migration script warns)
        return 0

    inferred = _infer_type(page, wiki_root)
    new_fm = _process_fm(fm, inferred)

    new_text = "---\n" + "".join(new_fm) + "---\n" + body
    if new_text != text:
        page.write_text(new_text)
    return 0


if __name__ == "__main__":
    if sys.version_info < (3, 11):
        print("python 3.11+ required", file=sys.stderr)
        sys.exit(1)
    sys.exit(main())
