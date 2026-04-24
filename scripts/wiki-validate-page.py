#!/usr/bin/env python3
"""Validate a single wiki page against the v2-hardened schema.

Usage:
    wiki-validate-page.py <page-path>
    wiki-validate-page.py --wiki-root <wiki-root> <page-path>

Checks performed in every mode:
  - Page has YAML frontmatter.
  - Required fields present: title, type, tags, sources, created, updated.
    (Phase B extends this with quality.* fields via a future patch.)
  - `type` is one of: concept, entity, source, query.
  - `created` and `updated` are full ISO-8601 UTC strings
    (e.g. 2026-04-24T13:00:00Z).
  - `tags` is a flat list.
  - `sources` is a flat list of strings (no nested mappings).

Additional checks when --wiki-root is given:
  - Every relative markdown link in the page body resolves to an existing file
    under the wiki root.
  - Every entry in `sources:` resolves to an existing file relative to the
    wiki root (skipped for a raw-file pointer that uses the literal string
    "conversation" -- that's handled in Phase B origin-tracking rules).
  - For `type: source`, a raw file at `raw/<basename-of-this-page>` exists.

Exit codes:
  0 -- all checks pass
  1 -- one or more violations; each violation printed to stderr, one per line,
       prefixed with the page path.

Python 3.11+ required (for stdlib tomllib, though YAML parsing uses a tiny
vendored parser here to stay stdlib-only).
"""

import re
import sys
from pathlib import Path
from typing import Any, Optional

VALID_TYPES = {"concept", "entity", "source", "query"}
ISO_UTC_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
REQUIRED_FIELDS_BASE = ("title", "type", "tags", "sources", "created", "updated")


def _extract_frontmatter(text: str) -> Optional[str]:
    """Return the YAML frontmatter block, or None if the page has none."""
    if not text.startswith("---\n") and not text.startswith("---\r\n"):
        return None
    # Split on the closing ---
    parts = text.split("\n---\n", 1) if "\n---\n" in text else text.split("\n---\r\n", 1)
    if len(parts) < 2:
        return None
    head = parts[0]
    if not head.startswith("---"):
        return None
    # head is e.g. "---\ntitle: ...\n..."; strip leading "---\n"
    return head[4:] if head.startswith("---\n") else head[5:]


def _parse_scalar(s: str) -> Any:
    s = s.strip()
    if s == "":
        return ""
    if s == "null" or s == "~":
        return None
    if s == "true":
        return True
    if s == "false":
        return False
    # Quoted string
    if len(s) >= 2 and s[0] == '"' and s[-1] == '"':
        return s[1:-1]
    if len(s) >= 2 and s[0] == "'" and s[-1] == "'":
        return s[1:-1]
    # Try int
    try:
        return int(s)
    except ValueError:
        pass
    # Try float
    try:
        return float(s)
    except ValueError:
        pass
    return s  # bare string


def _parse_yaml(fm: str) -> dict[str, Any]:
    """Minimal YAML parser covering the subset wiki pages use.

    Supports:
      key: scalar
      key: [a, b, c]
      key:
        - item
        - item
      key:
        - nested: value
      key:
        subkey: scalar
        subkey2: scalar

    Indentation rule for nested map: two-space child indent.
    """
    result: dict[str, Any] = {}
    lines = fm.splitlines()
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i].rstrip()
        if line == "" or line.startswith("#"):
            i += 1
            continue
        if ":" not in line:
            raise ValueError(f"malformed line (no colon): {line!r}")
        key, _, rest = line.partition(":")
        key = key.strip()
        rest = rest.strip()
        if rest == "":
            # Peek next non-blank line to decide list vs nested map.
            j = i + 1
            while j < n and (lines[j].strip() == "" or lines[j].lstrip().startswith("#")):
                j += 1
            if j >= n:
                result[key] = []
                i += 1
                continue
            peek = lines[j]
            if peek.lstrip().startswith("- "):
                # Block list
                items: list[Any] = []
                k = j
                while k < n:
                    pl = lines[k].rstrip()
                    if pl == "":
                        k += 1; continue
                    s = pl.lstrip()
                    if not s.startswith("- "):
                        break
                    indent = len(pl) - len(s)
                    if indent < 2:
                        break
                    content = s[2:]
                    if ":" in content and not (content.startswith('"') or content.startswith("'")):
                        ck, _, cv = content.partition(":")
                        items.append({ck.strip(): _parse_scalar(cv.strip())})
                    else:
                        items.append(_parse_scalar(content))
                    k += 1
                result[key] = items
                i = k
                continue
            # Nested map
            sub: dict[str, Any] = {}
            k = j
            while k < n:
                pl = lines[k].rstrip()
                if pl == "":
                    k += 1; continue
                s = pl.lstrip()
                indent = len(pl) - len(s)
                if indent < 2:
                    break
                if ":" not in s:
                    raise ValueError(f"malformed nested line: {pl!r}")
                sk, _, sv = s.partition(":")
                sub[sk.strip()] = _parse_scalar(sv.strip())
                k += 1
            result[key] = sub
            i = k
            continue
        if rest.startswith("["):
            if not rest.endswith("]"):
                raise ValueError(f"unterminated inline list for {key}")
            inner = rest[1:-1].strip()
            result[key] = [] if inner == "" else [_parse_scalar(p.strip()) for p in inner.split(",")]
            i += 1
            continue
        result[key] = _parse_scalar(rest)
        i += 1
    return result


_LINK_RE = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")


def _extract_body_links(body: str) -> list[str]:
    """Return every (relative or absolute) URL target of a markdown link."""
    return _LINK_RE.findall(body)


def _is_external(link: str) -> bool:
    return (
        link.startswith("http://")
        or link.startswith("https://")
        or link.startswith("mailto:")
        or link.startswith("#")
    )


def validate(page_path: Path, wiki_root: Optional[Path]) -> list[str]:
    """Return list of violation strings. Empty list = pass."""
    violations: list[str] = []
    if not page_path.is_file():
        return [f"{page_path}: file does not exist"]

    text = page_path.read_text()
    fm = _extract_frontmatter(text)
    if fm is None:
        return [f"{page_path}: no YAML frontmatter"]

    try:
        data = _parse_yaml(fm)
    except ValueError as e:
        return [f"{page_path}: malformed frontmatter: {e}"]

    # Required fields
    for field in REQUIRED_FIELDS_BASE:
        if field not in data:
            violations.append(f"{page_path}: missing required field: {field}")

    # type whitelist
    if "type" in data:
        t = data["type"]
        if t not in VALID_TYPES:
            sorted_types = sorted(VALID_TYPES)
            violations.append(
                f"{page_path}: type must be one of {sorted_types}, got {t!r}"
            )

    # dates
    for field in ("created", "updated"):
        if field in data:
            v = data[field]
            if not isinstance(v, str) or not ISO_UTC_RE.match(v):
                violations.append(
                    f"{page_path}: {field} must be ISO-8601 UTC "
                    f"(e.g. 2026-04-24T13:00:00Z), got {v!r}"
                )

    # tags flat list
    if "tags" in data:
        tags = data["tags"]
        if not isinstance(tags, list):
            violations.append(f"{page_path}: tags must be a list")
        else:
            for t in tags:
                if not isinstance(t, str):
                    violations.append(
                        f"{page_path}: every tag must be a string, got {t!r}"
                    )

    # sources flat list of strings (no nested maps)
    if "sources" in data:
        srcs = data["sources"]
        if not isinstance(srcs, list):
            violations.append(f"{page_path}: sources must be a flat list")
        else:
            for s in srcs:
                if isinstance(s, dict):
                    violations.append(
                        f"{page_path}: sources entries must be flat strings, "
                        f"got nested mapping: {s!r}"
                    )
                elif not isinstance(s, str):
                    violations.append(
                        f"{page_path}: sources entries must be strings, got {s!r}"
                    )

    # Phase B: quality block
    VALID_RATED_BY = {"ingester", "doctor", "human"}
    QUALITY_SCORE_FIELDS = ("accuracy", "completeness", "signal", "interlinking")
    if "quality" not in data:
        violations.append(f"{page_path}: missing required field: quality")
    else:
        q = data["quality"]
        if not isinstance(q, dict):
            violations.append(f"{page_path}: quality must be a nested mapping")
        else:
            for field in QUALITY_SCORE_FIELDS:
                if field not in q:
                    violations.append(f"{page_path}: missing quality.{field}")
                else:
                    v = q[field]
                    if not isinstance(v, int) or not (1 <= v <= 5):
                        violations.append(
                            f"{page_path}: quality.{field} must be int 1..5, got {v!r}"
                        )
            if "overall" not in q:
                violations.append(f"{page_path}: missing quality.overall")
            else:
                try:
                    scores = [q[f] for f in QUALITY_SCORE_FIELDS if isinstance(q.get(f), int)]
                    if len(scores) == 4:
                        expected = round(sum(scores) / 4, 2)
                        actual = float(q["overall"])
                        if abs(expected - actual) > 1e-6:
                            violations.append(
                                f"{page_path}: quality.overall must be mean of four "
                                f"scores rounded to 2 decimals. expected={expected}, "
                                f"got={actual}"
                            )
                except (TypeError, ValueError):
                    violations.append(f"{page_path}: quality.overall not numeric")
            if "rated_at" not in q:
                violations.append(f"{page_path}: missing quality.rated_at")
            else:
                v = q["rated_at"]
                if not isinstance(v, str) or not ISO_UTC_RE.match(v):
                    violations.append(
                        f"{page_path}: quality.rated_at must be ISO-8601 UTC, got {v!r}"
                    )
            if "rated_by" not in q:
                violations.append(f"{page_path}: missing quality.rated_by")
            else:
                v = q["rated_by"]
                if v not in VALID_RATED_BY:
                    violations.append(
                        f"{page_path}: quality.rated_by must be one of "
                        f"{sorted(VALID_RATED_BY)}, got {v!r}"
                    )

    # Wiki-root-mode additional checks
    if wiki_root is not None:
        # Body markdown link resolution
        # Body starts AFTER the closing ---
        body_split = text.split("\n---\n", 1)
        body = body_split[1] if len(body_split) == 2 else ""
        for link in _extract_body_links(body):
            if _is_external(link):
                continue
            # Strip any #anchor suffix
            link_clean = link.split("#", 1)[0]
            if link_clean == "":
                continue
            # Resolve relative to the page's own directory
            target = (page_path.parent / link_clean).resolve()
            if not target.exists():
                violations.append(
                    f"{page_path}: broken markdown link: {link}"
                )

        # Sources existence
        if "sources" in data and isinstance(data["sources"], list):
            for s in data["sources"]:
                if not isinstance(s, str):
                    continue
                if s == "conversation":
                    # Phase B origin-tracking rules govern this; not a
                    # filesystem check.
                    continue
                src_path = (wiki_root / s).resolve()
                if not src_path.exists():
                    violations.append(
                        f"{page_path}: sources entry does not exist on disk: {s}"
                    )

        # type=source must have a matching raw file
        if data.get("type") == "source":
            # Basename of the page (without .md) must correspond to a raw file
            base = page_path.stem  # e.g. 2026-04-24-x
            candidates = list((wiki_root / "raw").glob(f"{base}.*"))
            if not candidates:
                violations.append(
                    f"{page_path}: type=source but no matching raw file at "
                    f"raw/{base}.*"
                )

    return violations


def main() -> int:
    argv = sys.argv[1:]
    wiki_root: Optional[Path] = None
    if argv and argv[0] == "--wiki-root":
        if len(argv) < 3:
            print("usage: wiki-validate-page.py [--wiki-root ROOT] <page>",
                  file=sys.stderr)
            return 1
        wiki_root = Path(argv[1]).resolve()
        page = Path(argv[2])
        if not wiki_root.is_dir():
            print(f"not a directory: {wiki_root}", file=sys.stderr)
            return 1
    elif len(argv) == 1:
        page = Path(argv[0])
    else:
        print("usage: wiki-validate-page.py [--wiki-root ROOT] <page>",
              file=sys.stderr)
        return 1

    # Fail-fast on Python < 3.11 (stay consistent with wiki-init.sh).
    if sys.version_info < (3, 11):
        print("python 3.11+ required", file=sys.stderr)
        return 1

    violations = validate(page, wiki_root)
    if not violations:
        return 0
    for v in violations:
        print(v, file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
