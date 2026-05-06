#!/usr/bin/env python3
"""Shared YAML helper used by wiki-validate-page.py, wiki-fix-frontmatter.py, wiki-build-index.py.

Exports:
    extract_frontmatter(text: str) -> Optional[str]
    parse_yaml(fm: str) -> dict[str, Any]
    split_frontmatter(text: str) -> tuple[Optional[str], Optional[str], Optional[str]]
        Returns (opener, frontmatter_block, after) where:
            - opener is "---\n" (the literal opening line)
            - frontmatter_block is the YAML between delimiters (no trailing newline)
            - after is everything from the closing "---" onward, INCLUDING that closing "---" and any trailing body+newline.
        Returns (None, None, None) if no frontmatter.
        Reconstruction: opener + frontmatter_block + "\n" + after.
    RESERVED: set[str]
        Directory names that are NEVER treated as wiki categories (used by wiki-discover.py,
        wiki-fix-frontmatter.py, wiki-build-index.py to skip infrastructure dirs).

Identical-behavior port of wiki-validate-page.py's parser; an oracle test in
test-yaml-helper.sh enforces parity. DO NOT reimplement; import from here.
"""
import re
from typing import Any, Optional

ISO_UTC_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")  # exported for use by validator (not used inside this module)
_NESTED_MAP_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_-]*:(\s|$)")

# Directory names that are NEVER treated as wiki categories. Used by
# wiki-discover.py, wiki-fix-frontmatter.py, wiki-build-index.py to skip
# infrastructure dirs at any depth in the wiki tree.
RESERVED: set[str] = {"raw", "index", "archive", "inbox"}


def extract_frontmatter(text: str) -> Optional[str]:
    """Return the YAML frontmatter block, or None if the page has none."""
    if not text.startswith("---\n") and not text.startswith("---\r\n"):
        return None
    parts = text.split("\n---\n", 1) if "\n---\n" in text else text.split("\n---\r\n", 1)
    if len(parts) < 2:
        return None
    head = parts[0]
    if not head.startswith("---"):
        return None
    return head[4:] if head.startswith("---\n") else head[5:]


def split_frontmatter(text: str) -> tuple[Optional[str], Optional[str], Optional[str]]:
    """Return (opener, fm_block, after) for atomic-rewrite use cases.

    after starts with the closing '---' line and includes any body content + final newline.

    LF-only assumed; wiki content is always LF. CRLF is handled by extract_frontmatter
    but not by this function (split_frontmatter is for write paths where we control output).
    """
    if not text.startswith("---\n"):
        return (None, None, None)
    rest = text[4:]  # everything after the opening '---\n'
    sep = "\n---\n"
    idx = rest.find(sep)
    if idx < 0:
        # No closing delimiter
        return (None, None, None)
    fm_block = rest[:idx]
    after = rest[idx + 1:]  # starts at '---\n...'
    return ("---\n", fm_block, after)


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
    if len(s) >= 2 and s[0] == '"' and s[-1] == '"':
        return s[1:-1]
    if len(s) >= 2 and s[0] == "'" and s[-1] == "'":
        return s[1:-1]
    try:
        return int(s)
    except ValueError:
        pass
    try:
        return float(s)
    except ValueError:
        pass
    return s


def parse_yaml(fm: str) -> dict[str, Any]:
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
                    # Treat as a one-key nested mapping ONLY if the pre-colon token looks like a
                    # YAML identifier. Without this guard, list items like `- https://foo/bar`
                    # would be mis-parsed as {"https": "//foo/bar"}, breaking the flat-string
                    # sources check. See wiki-validate-page.py regression history (commit 731e08f).
                    if _NESTED_MAP_RE.match(content):
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


if __name__ == "__main__":
    import sys
    text = sys.stdin.read()
    fm = extract_frontmatter(text)
    if fm is None:
        print("no frontmatter", file=sys.stderr)
        sys.exit(1)
    import json
    print(json.dumps(parse_yaml(fm), indent=2, default=str))
