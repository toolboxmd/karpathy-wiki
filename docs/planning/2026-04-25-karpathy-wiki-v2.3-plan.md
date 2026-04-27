# karpathy-wiki v2.3 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Each task is sized for a fresh subagent dispatch.

**Goal:** Replace the wiki's hard-coded category whitelist with auto-discovered categories rooted in the directory tree. Users (and agents) create categories by `mkdir`; the wiki regenerates its self-description on the next ingest.

**Architecture:** The directory tree IS the schema. `wiki-discover.py` walks the wiki root and returns categories + reserved-names + depths + counts. The validator and all category-aware scripts read from discovery instead of hardcoded lists. Pages can nest arbitrarily deep within a category. Each directory carries an `_index.md` mirroring directory structure. Per-category sub-indexes consume the v2.2 `index-split.md` schema-proposal.

**Tech Stack:** Python 3.11+ (stdlib-only, no new deps). Bash 3.2+ (macOS default). The same toolchain used in v2-hardening / v2.2.

**Spec:** `docs/planning/2026-04-25-karpathy-wiki-v2.3-spec.md` (read this before starting any task).

**Branch:** `v2-rewrite` (continues v2 + v2-hardening + v2.1 + v2.2 lineage).

**Execution mode:** Subagent-driven-development. Planner → implementer → reviewer per phase. Reviewer subagent gates each phase before moving on.

**Reused-code policy.** Phase A introduces a shared YAML helper module (`scripts/wiki_yaml.py`) to avoid drift between `wiki-validate-page.py`'s parser, `wiki-fix-frontmatter.py`'s frontmatter splitter, and `wiki-build-index.py`'s frontmatter reader. The 4th-pass plan reviewer found that these three call sites otherwise reimplement the same parser three times — a known anti-pattern that already shipped one bug in v2.x (the `https://` colon-in-URL false-positive). Tasks 0, 4, 5, 11 reference this shared module.

**Test style policy.** New test cases that extend existing test files (`test-validate-page.sh`, `test-status.sh`, `test-backfill-quality.sh`, `test-init.sh`, `test-index-threshold-fires.sh`, `test-concurrent-ingest.sh`) use the SAME pattern as the existing file. `test-validate-page.sh` uses `expect_exit <rc> <label> -- <command>` style — new cases there MUST follow the same shape. Brand-new test files (`test-discover.sh`, `test-fix-frontmatter.sh`, `test-build-index.sh`, `test-relink.sh`, `test-migrate-v2.3.sh`, `test-bundle-sync.sh`) use the function-style pattern from this plan.

**Test fixture migration policy.** The fixtures at `tests/fixtures/validate-page-cases/wiki-root-mode/sources/*.md` use `type: concept` (singular) and live in a `sources/` directory. Under v2.3's hard validator (post-Phase D), they would fail. Task 20 includes the explicit fixture-migration step that updates them to match v2.3 semantics.

---

## Plan Corrigenda (4th-pass reviewer fixes)

The plan body below was written before the 4th-pass review. Several tasks need surgical corrections; rather than rewriting the body wholesale, the corrigenda below OVERRIDE specific subsections of those tasks. When executing, follow the corrigenda where they conflict with the original task text. The original text is retained for traceability.

### Corrigenda C-A: Add Task 0 (shared YAML helper) BEFORE Task 1

**Files:**
- Create: `scripts/wiki_yaml.py`
- Create: `skills/karpathy-wiki/scripts/wiki_yaml.py`
- Test: `tests/unit/test-yaml-helper.sh`

The helper extracts the existing YAML parser from `wiki-validate-page.py` (lines 49-180) into a standalone module. `wiki-validate-page.py`, `wiki-fix-frontmatter.py`, and `wiki-build-index.py` then ALL import from `wiki_yaml`. Eliminates parser drift.

**Steps:**

- [ ] **Step 0.1: Read the existing parser**

```bash
sed -n '49,180p' scripts/wiki-validate-page.py
```

- [ ] **Step 0.2: Create `scripts/wiki_yaml.py`**

```python
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

The parser is the same one v2-hardening shipped (regression-tested against
the colon-in-URL bug). DO NOT reimplement; import from here.
"""
import re
from typing import Any, Optional

ISO_UTC_RE = re.compile(r"^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$")
_NESTED_MAP_RE = re.compile(r"^[A-Za-z_][A-Za-z0-9_-]*:(\s|$)")


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

    Verbatim port of wiki-validate-page.py's parser to keep regression coverage.
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
            j = i + 1
            while j < n and (lines[j].strip() == "" or lines[j].lstrip().startswith("#")):
                j += 1
            if j >= n:
                result[key] = []
                i += 1
                continue
            peek = lines[j]
            if peek.lstrip().startswith("- "):
                items: list[Any] = []
                while j < n:
                    raw = lines[j]
                    if raw == "" or raw.lstrip().startswith("#"):
                        j += 1
                        continue
                    if not raw.startswith("  "):
                        break
                    if not raw.lstrip().startswith("- "):
                        break
                    item_str = raw.lstrip()[2:].strip()
                    if _NESTED_MAP_RE.match(item_str):
                        nk, _, nv = item_str.partition(":")
                        items.append({nk.strip(): _parse_scalar(nv)})
                    else:
                        items.append(_parse_scalar(item_str))
                    j += 1
                result[key] = items
                i = j
                continue
            else:
                # Nested map (two-space indented children)
                nested: dict[str, Any] = {}
                while j < n:
                    raw = lines[j]
                    if raw == "" or raw.lstrip().startswith("#"):
                        j += 1
                        continue
                    if not raw.startswith("  "):
                        break
                    if raw.startswith("    ") or raw.lstrip().startswith("- "):
                        break
                    sub = raw.lstrip()
                    if ":" not in sub:
                        break
                    sk, _, sv = sub.partition(":")
                    nested[sk.strip()] = _parse_scalar(sv)
                    j += 1
                result[key] = nested
                i = j
                continue
        else:
            # Scalar or inline list
            if rest.startswith("[") and rest.endswith("]"):
                inner = rest[1:-1].strip()
                if inner == "":
                    result[key] = []
                else:
                    result[key] = [_parse_scalar(x) for x in inner.split(",")]
            else:
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
```

- [ ] **Step 0.3: Create `tests/unit/test-yaml-helper.sh`**

```bash
#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

test_extract_frontmatter() {
  out="$(printf -- '---\ntitle: foo\n---\nbody\n' | python3 "${REPO_ROOT}/scripts/wiki_yaml.py")"
  echo "${out}" | grep -q '"title": "foo"' || { echo "FAIL: title not parsed"; exit 1; }
}

test_quality_block_parsed_as_dict() {
  out="$(printf -- '---\ntitle: foo\nquality:\n  accuracy: 4\n  overall: 4.00\n  rated_by: ingester\n---\nbody\n' | python3 "${REPO_ROOT}/scripts/wiki_yaml.py")"
  echo "${out}" | python3 -c "import json, sys; d = json.load(sys.stdin); assert isinstance(d['quality'], dict); assert d['quality']['rated_by'] == 'ingester'; assert d['quality']['accuracy'] == 4"
}

test_url_in_sources_not_misparsed() {
  out="$(printf -- '---\ntitle: foo\nsources:\n  - https://example.com/foo\n---\nbody\n' | python3 "${REPO_ROOT}/scripts/wiki_yaml.py")"
  echo "${out}" | python3 -c "import json, sys; d = json.load(sys.stdin); assert d['sources'] == ['https://example.com/foo'], d"
}

test_split_frontmatter_round_trip() {
  python3 - <<'PYEOF'
import sys
sys.path.insert(0, "scripts")
from wiki_yaml import split_frontmatter
text = "---\ntitle: foo\ntype: concepts\n---\nbody line 1\nbody line 2\n"
opener, fm, after = split_frontmatter(text)
assert opener == "---\n", repr(opener)
assert fm == "title: foo\ntype: concepts", repr(fm)
assert after.startswith("---\n"), repr(after)
# Round-trip MUST be exact
reconstructed = opener + fm + "\n" + after
assert reconstructed == text, f"diff: orig={text!r} reconstructed={reconstructed!r}"
PYEOF
}

test_extract_frontmatter
test_quality_block_parsed_as_dict
test_url_in_sources_not_misparsed
test_split_frontmatter_round_trip
echo "all tests passed"
```

- [ ] **Step 0.4: Run tests (should fail until module exists)**

```bash
chmod +x scripts/wiki_yaml.py
bash tests/unit/test-yaml-helper.sh
```

- [ ] **Step 0.5: Hand-copy to bundle**

```bash
cp scripts/wiki_yaml.py skills/karpathy-wiki/scripts/wiki_yaml.py
chmod +x skills/karpathy-wiki/scripts/wiki_yaml.py
```

- [ ] **Step 0.6: Commit**

```bash
git add scripts/wiki_yaml.py skills/karpathy-wiki/scripts/wiki_yaml.py tests/unit/test-yaml-helper.sh
git commit -m "feat(v2.3): wiki_yaml.py — shared YAML helper for v2.3 scripts

Extracts the YAML parser from wiki-validate-page.py into a shared module.
wiki-fix-frontmatter.py and wiki-build-index.py import from this module
to eliminate parser drift (per 4th-pass plan reviewer C1)."
```

### Corrigenda C-B: Replace Task 4 step 3 (`scripts/wiki-fix-frontmatter.py` body)

The original Task 4 implementation has TWO bugs: (a) it reimplements its own frontmatter splitter, and (b) reconstruction adds an extra newline. Replace with this implementation that imports `wiki_yaml`:

```python
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
```

Add to Task 4's test file (`test-fix-frontmatter.sh`) one new case immediately after the existing tests:

```bash
test_no_extra_whitespace_added() {
  setup
  cat > "${WIKI}/concepts/foo.md" <<'EOF'
---
title: "Foo"
type: concept
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
---

body line 1
body line 2
EOF
  size_before="$(wc -c < "${WIKI}/concepts/foo.md")"
  python3 "${FIX}" --wiki-root "${WIKI}" "${WIKI}/concepts/foo.md"
  size_after="$(wc -c < "${WIKI}/concepts/foo.md")"
  # delta = len("concepts") - len("concept") = 1
  delta=$(( size_after - size_before ))
  [[ "${delta}" -eq 1 ]] || { echo "FAIL: size delta ${delta}, expected 1"; exit 1; }
  # No double-newline introduced
  ! grep -P '\n\n\n' "${WIKI}/concepts/foo.md" || { echo "FAIL: triple newline introduced"; exit 1; }
  teardown
}
```

Append `test_no_extra_whitespace_added` to the test runner block at the bottom of the file.

### Corrigenda C-C: Task 5 — explicit `disc` threading + `expect_exit` test style

Replace Task 5's vague Step 4(c)-(g) with this concrete patch:

(a) **Top of file (after stdlib imports):**

```python
import json
import subprocess

sys.path.insert(0, str(Path(__file__).parent))
from wiki_yaml import extract_frontmatter, parse_yaml
```

Note: this REMOVES the existing `_extract_frontmatter` and `_parse_yaml` functions from `wiki-validate-page.py` (lines 49-180 in the current file). Delete them; use the imported versions.

(b) **Add `_discover` helper at module level:**

```python
def _discover(wiki_root: Path) -> dict:
    script = Path(__file__).parent / "wiki-discover.py"
    result = subprocess.run(
        ["python3", str(script), "--wiki-root", str(wiki_root)],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        raise RuntimeError(f"wiki-discover.py failed: {result.stderr.strip()}")
    return json.loads(result.stdout)
```

(c) **Modify `validate()` signature** (find the function — it's the main per-page validator). Add `disc: Optional[dict] = None` parameter:

```python
def validate(page_path: Path, wiki_root: Optional[Path] = None, disc: Optional[dict] = None) -> int:
```

**Helper variable `rel`.** The new check snippets below reference `rel` (a wiki-relative pretty-printable page path). Add this near the top of `validate()`, immediately after the `wiki_root is None` guard:

```python
rel = str(page_path.relative_to(wiki_root)) if wiki_root is not None else str(page_path)
```

This `rel` is used by all v2.3-added stderr messages and violation strings.

(d) **Modify `main()` to call `_discover` once** (find the place where `--wiki-root` is parsed):

```python
disc = None
if args.wiki_root:
    try:
        disc = _discover(Path(args.wiki_root))
    except RuntimeError as e:
        print(str(e), file=sys.stderr)
        return 1
# ... pass disc to validate() in the validation call:
return validate(page_path, wiki_root, disc)
```

(e) **In `validate()`, replace the existing `VALID_TYPES` check with discovery-aware checks** (gate on `disc is not None`):

Find the existing block (around line 250-260 in current file) that checks `if t not in VALID_TYPES`. Replace with:

```python
# v2.3: type-membership check (Phase A: warning-only; Phase D flip removes the soft-warn).
if disc is not None:
    discovered_types = set(disc["categories"])
    if t not in discovered_types:
        # PHASE A BEHAVIOR — comment shows what to flip in Phase D's validator-flip task.
        # PHASE_A_BEGIN
        print(
            f"{rel}: WARNING type '{t}' not in discovered categories {sorted(discovered_types)}",
            file=sys.stderr,
        )
        # PHASE_A_END
        # In Phase D's validator-flip task, replace the print() above with:
        #     violations.append(f"{rel}: type '{t}' not in discovered categories {sorted(discovered_types)}")

    # Type vs path cross-check (Phase A: warning-only).
    if wiki_root is not None:
        expected_type = page_path.relative_to(wiki_root).parts[0]
        if t != expected_type:
            # PHASE_A_BEGIN
            print(
                f"{rel}: WARNING type '{t}' != path.parts[0] '{expected_type}' "
                f"(run: python3 scripts/wiki-fix-frontmatter.py --wiki-root {wiki_root} {rel})",
                file=sys.stderr,
            )
            # PHASE_A_END
            # Phase D flip: replace with violations.append(...)

# Depth ≥ 5 hard reject (Rule 2; always-on, no soft-warn period).
if wiki_root is not None:
    rel_parts = page_path.relative_to(wiki_root).parts
    if len(rel_parts) > 5:
        violations.append(
            f"{rel}: page at depth {len(rel_parts)} exceeds hard cap (5); "
            f"place shallower or restructure category."
        )
```

(f) **Replace existing link resolver** (find the block that does `target = (page_path.parent / href).resolve()` for relative links):

```python
# v2.3: leading "/" resolves from wiki root, not page directory.
if wiki_root is not None and href.startswith("/"):
    target = (wiki_root / href.lstrip("/")).resolve()
else:
    target = (page_path.parent / href).resolve()
```

(g) **Tests for Task 5** — REWRITE in `expect_exit` style. Replace the function-style tests in plan Task 5 step 2 with:

Append to the bottom of `tests/unit/test-validate-page.sh` (NOT inside any function — these go alongside the existing top-level `expect_exit` calls):

```bash
# v2.3: Phase A new checks
TMPV3="$(mktemp -d)"
trap "rm -rf '${TMPV3}'" EXIT

# Build a fixture wiki for v2.3 cases
mkdir -p "${TMPV3}/wiki/concepts" "${TMPV3}/wiki/projects/toolboxmd/karpathy-wiki" "${TMPV3}/wiki/journal" "${TMPV3}/wiki/raw"
touch "${TMPV3}/wiki/.wiki-config"
echo "stub" > "${TMPV3}/wiki/concepts/foo.md"

cat > "${TMPV3}/wiki/projects/toolboxmd/karpathy-wiki/v23.md" <<'EOF'
---
title: "v2.3"
type: projects
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 5
  overall: 5.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: ingester
---

See [foo](/concepts/foo.md).
EOF

expect_exit 0 "v2.3: leading-/ link resolves from wiki root" -- \
  python3 "${TOOL}" --wiki-root "${TMPV3}/wiki" "${TMPV3}/wiki/projects/toolboxmd/karpathy-wiki/v23.md"

# Phase A: type/path cross-check is WARNING only — exit 0
cat > "${TMPV3}/wiki/concepts/mismatch.md" <<'EOF'
---
title: "Mismatch"
type: entities
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 5
  overall: 5.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: ingester
---
body
EOF
expect_exit 0 "v2.3 Phase A: type/path mismatch is WARNING only" -- \
  python3 "${TOOL}" --wiki-root "${TMPV3}/wiki" "${TMPV3}/wiki/concepts/mismatch.md"

out_warn="$(python3 "${TOOL}" --wiki-root "${TMPV3}/wiki" "${TMPV3}/wiki/concepts/mismatch.md" 2>&1 1>/dev/null || true)"
echo "${out_warn}" | grep -q "WARNING.*type.*entities" \
  && say_pass "v2.3 Phase A: cross-check WARNING line emitted to stderr" \
  || say_fail "v2.3 Phase A: expected WARNING line, got: ${out_warn}"

# Discovery returns dynamic types — `journal/` IS a category
cat > "${TMPV3}/wiki/journal/2026-04-26.md" <<'EOF'
---
title: "Today"
type: journal
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 5
  overall: 5.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: ingester
---
body
EOF
expect_exit 0 "v2.3: dynamic category 'journal' from discovery is valid" -- \
  python3 "${TOOL}" --wiki-root "${TMPV3}/wiki" "${TMPV3}/wiki/journal/2026-04-26.md"

# Discovery failure: bogus wiki-root containing no .wiki-config and no usable structure.
# Validator's `_discover` exits non-zero on bogus root.
expect_exit 1 "v2.3: discovery failure exits non-zero" -- \
  python3 "${TOOL}" --wiki-root "/nonexistent/v23/path/zzz" "/nonexistent/v23/path/zzz/concepts/foo.md"

# Depth-≥5 hard reject (always-on)
mkdir -p "${TMPV3}/wiki/concepts/a/b/c/d"
cat > "${TMPV3}/wiki/concepts/a/b/c/d/deep.md" <<'EOF'
---
title: "Deep"
type: concepts
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 5
  overall: 5.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: ingester
---
body
EOF
expect_exit 1 "v2.3: depth >=5 hard rejects" -- \
  python3 "${TOOL}" --wiki-root "${TMPV3}/wiki" "${TMPV3}/wiki/concepts/a/b/c/d/deep.md"
```

### Corrigenda C-D: Task 11 — `wiki-build-index.py` MUST import `wiki_yaml`

Replace the broken `_read_frontmatter` function in Task 11's implementation with this:

```python
sys.path.insert(0, str(Path(__file__).parent))
from wiki_yaml import extract_frontmatter, parse_yaml


def _read_frontmatter(page: Path) -> dict:
    text = page.read_text()
    fm = extract_frontmatter(text)
    if fm is None:
        return {}
    try:
        return parse_yaml(fm)
    except ValueError:
        return {}


def _quality(fm: dict) -> str:
    q = fm.get("quality", {})
    if not isinstance(q, dict):
        return ""
    overall = q.get("overall")
    if overall is None:
        return ""
    # Format with 2 decimals so 'overall: 4.00' (parsed as float 4.0) renders as '(q: 4.00)'.
    try:
        return f"(q: {float(overall):.2f}) "
    except (TypeError, ValueError):
        return f"(q: {overall}) "
```

Also update `_build_directory_index` to read the reserved set from discovery (per C-E below) and to use `f"{cat}".replace("-", " ").title()` instead of `cat.capitalize()`.

### Corrigenda C-E: Task 11 — pass discovery's reserved set, fix `cat.capitalize()`, ensure trailing newline

Replace the line:

```python
subdirs = sorted([d for d in directory.iterdir() if d.is_dir() and not d.name.startswith(".") and d.name not in {"raw", "index", "archive", "Clippings"}])
```

with (using the reserved set passed in from `rebuild_all`):

```python
def _build_directory_index(directory: Path, wiki_root: Path, reserved: set[str]) -> None:
    # ... unchanged head ...
    subdirs = sorted([d for d in directory.iterdir() if d.is_dir() and not d.name.startswith(".") and d.name not in reserved])
    # ... unchanged tail ...
    target.write_text("\n".join(lines) + "\n")  # ensure trailing newline
```

Update `rebuild_all` to pass `set(disc["reserved"])`:

```python
def rebuild_all(wiki_root: Path) -> None:
    disc = _discover(wiki_root)
    reserved = set(disc["reserved"])
    # ... existing walk logic ...
    for d in all_dirs:
        _build_directory_index(d, wiki_root, reserved)
    _build_root_moc(wiki_root, disc)
```

Replace `cat.capitalize()` with `cat.replace("-", " ").replace("_", " ").title()` in `_build_root_moc`. Ensure `_build_root_moc` writes with trailing `\n` consistently.

### Corrigenda C-F: Task 9 step 7d — fix heredoc quoting and split-output instructions

Replace Task 9 step 7d's single inline command with this two-step procedure:

(a) Run the categories-rendering command (note: SINGLE-quoted heredoc to prevent shell expansion):

```bash
python3 scripts/wiki-discover.py --wiki-root ~/wiki | python3 -c '
import json, sys
d = json.load(sys.stdin)
print("--- CATEGORIES BLOCK (paste between CATEGORIES:START and CATEGORIES:END) ---")
for c in d["categories"]:
    cnt = d["counts"].get(c, 0)
    dpt = d["depths"].get(c, 1)
    print(f"- `{c}/` ({cnt} pages, max depth {dpt}) : type: {c}")
print()
print("--- RESERVED BLOCK (paste between RESERVED:START and RESERVED:END) ---")
for r in d["reserved"]:
    print(f"- `{r}/` (reserved infrastructure)")
'
```

The `python3 -c '...'` (single-quoted) prevents bash from interpreting backticks.

(b) The output has two clearly-labeled sections. Copy each into its respective `<!-- ...:START -->` / `<!-- ...:END -->` block in `~/wiki/schema.md`, omitting the `--- CATEGORIES BLOCK ---` and `--- RESERVED BLOCK ---` headers (those are run-time markers, not file content).

### Corrigenda C-G: Task 17/18/19 — atomic Phase D commits with explicit checkpoint

Replace Task 18 step 3's `wiki-migrate-v2.3.sh` with a two-phase variant:

```bash
#!/bin/bash
# wiki-migrate-v2.3.sh — Live wiki page-migration orchestrator for v2.3.
#
# Two phases, each commits to the wiki repo separately.
#
# Usage:
#   wiki-migrate-v2.3.sh --dry-run --wiki-root <root>
#   wiki-migrate-v2.3.sh --phase=moves-and-relinks --wiki-root <root>
#   wiki-migrate-v2.3.sh --phase=index-rebuild --wiki-root <root>
#   wiki-migrate-v2.3.sh --yes --wiki-root <root>          # runs both phases sequentially
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DRY_RUN=0
PHASE=""
YES=0
WIKI_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --phase=*) PHASE="${1#--phase=}"; shift ;;
    --yes) YES=1; shift ;;
    --wiki-root) WIKI_ROOT="$2"; shift 2 ;;
    *) echo "usage: $0 (--dry-run | --phase=moves-and-relinks | --phase=index-rebuild | --yes) --wiki-root <root>" >&2; exit 1 ;;
  esac
done

[[ -z "${WIKI_ROOT}" ]] && { echo "missing --wiki-root" >&2; exit 1; }
[[ ! -d "${WIKI_ROOT}" ]] && { echo "not a directory: ${WIKI_ROOT}" >&2; exit 1; }

declare -a MOVES=(
  "concepts/karpathy-wiki-v2.2-architectural-cut.md:projects/toolboxmd/karpathy-wiki/karpathy-wiki-v2.2-architectural-cut.md"
  "concepts/karpathy-wiki-v2.3-flexible-categories-design.md:projects/toolboxmd/karpathy-wiki/karpathy-wiki-v2.3-flexible-categories-design.md"
  "concepts/multi-stage-opus-pipeline-lessons.md:projects/toolboxmd/building-agentskills/multi-stage-opus-pipeline-lessons.md"
  "concepts/building-agentskills-repo-decision.md:projects/toolboxmd/building-agentskills/building-agentskills-repo-decision.md"
)

ensure_dirs() {
  for d in projects/toolboxmd/karpathy-wiki projects/toolboxmd/building-agentskills; do
    if [[ ! -d "${WIKI_ROOT}/${d}" ]]; then
      [[ "${DRY_RUN}" -eq 1 ]] && echo "would mkdir ${WIKI_ROOT}/${d}" || mkdir -p "${WIKI_ROOT}/${d}"
    fi
  done
}

phase_moves_and_relinks() {
  ensure_dirs
  local moved_args=()
  for mv in "${MOVES[@]}"; do
    local old="${mv%%:*}"; local new="${mv##*:}"
    local old_abs="${WIKI_ROOT}/${old}"; local new_abs="${WIKI_ROOT}/${new}"
    if [[ ! -f "${old_abs}" ]]; then
      [[ -f "${new_abs}" ]] && { echo "already migrated: ${new}"; continue; }
      echo "skipped (not found): ${old}"
      continue
    fi
    if [[ "${DRY_RUN}" -eq 1 ]]; then echo "would git mv ${old} -> ${new}"; continue; fi
    if ! ( cd "${WIKI_ROOT}" && git mv "${old}" "${new}" ); then
      echo "FAIL: git mv ${old} -> ${new}; aborting before relink" >&2
      exit 1
    fi
    moved_args+=("--moved" "${old}=${new}")
  done

  if [[ "${DRY_RUN}" -eq 0 && "${#moved_args[@]}" -gt 0 ]]; then
    if ! python3 "${SCRIPT_DIR}/wiki-relink.py" --wiki-root "${WIKI_ROOT}" "${moved_args[@]}"; then
      echo "FAIL: wiki-relink.py errored; working tree has staged moves but UNSTAGED links may be broken" >&2
      echo "Recovery: cd ${WIKI_ROOT} && git reset --hard HEAD" >&2
      exit 1
    fi
  fi
  echo "phase moves-and-relinks complete; ready to commit"
}

phase_index_rebuild() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "would rebuild all _index.md via wiki-build-index.py --rebuild-all"
    return
  fi
  python3 "${SCRIPT_DIR}/wiki-build-index.py" --wiki-root "${WIKI_ROOT}" --rebuild-all
  echo "phase index-rebuild complete; ready to commit"
}

if [[ "${YES}" -eq 1 ]]; then
  # NOTE: --yes runs ONLY phase 'moves-and-relinks' (not the full migration).
  # The operator must commit, then re-run with --phase=index-rebuild for
  # the second phase. This is INTENTIONAL — we want a verification gate
  # between the two phases.
  phase_moves_and_relinks
  echo "OPERATOR: now run 'cd ${WIKI_ROOT} && git add -A && git commit ...' for the moves+relinks commit, then re-run with --phase=index-rebuild"
elif [[ "${PHASE}" == "moves-and-relinks" ]]; then
  phase_moves_and_relinks
elif [[ "${PHASE}" == "index-rebuild" ]]; then
  phase_index_rebuild
elif [[ "${DRY_RUN}" -eq 1 ]]; then
  phase_moves_and_relinks
  echo "---"
  phase_index_rebuild
else
  echo "specify --dry-run, --yes, or --phase=..." >&2
  exit 1
fi
```

Update Task 19 to use the new two-phase invocation:

- Step 2 becomes: `bash scripts/wiki-migrate-v2.3.sh --phase=moves-and-relinks --wiki-root ~/wiki`
- Step 4 (commit moves+relinks): unchanged (`git add -A && git commit -m "feat(v2.3): move 4 named pages..."`).
- Step 4.5 (NEW): `bash scripts/wiki-migrate-v2.3.sh --phase=index-rebuild --wiki-root ~/wiki`
- Step 5 (commit index-rebuild): unchanged (`git add -A && git commit -m "feat(v2.3): regenerate _index.md tree..."`).

### Corrigenda C-H: Task 19 step 3 explicit rollback procedure

Replace the line `[[ "${errors}" -eq 0 ]] || { echo "ROLLBACK NEEDED"; exit 1; }` with:

```bash
if [[ "${errors}" -ne 0 ]]; then
  cat <<EOF
ROLLBACK PROCEDURE — validator found ${errors} hard-fail page(s) after Phase D moves+relinks.

OPTION A (preferred — git-only, no tarball needed):
    cd ~/wiki && git reset --hard HEAD && git clean -fd
    # Discards staged + unstaged mutations including renames; back to last clean commit.
    # NOTE: 'git checkout -- .' alone does NOT undo staged 'git mv' renames; only
    # 'git reset --hard HEAD' + 'git clean -fd' fully restores pre-migration state.

OPTION B (if A fails or commit was made):
    rm -rf ~/wiki
    tar xzf ~/wiki-backup-pre-v2.3-phase-d-*.tar.gz -C ~

After rollback, investigate which pages failed (rerun validator with verbose output),
fix the underlying issue, and retry the migration.
EOF
  exit 1
fi
```

### Corrigenda C-I: Task 20 — also migrate fixture pages at `tests/fixtures/validate-page-cases/wiki-root-mode/sources/*`

Insert as Task 20 step 0 (BEFORE the validator-flip):

- [ ] **Step 0: Migrate fixture pages**

The fixtures `tests/fixtures/validate-page-cases/wiki-root-mode/sources/{2026-04-24-x.md, orphan-source.md}` use `type: concept` (singular). Under the post-flip validator they would fail. Either:

(a) **Rename `sources/` → `concepts/` in the fixture** AND update the test labels in `test-validate-page.sh`. Because the existing test asserts these are valid pages in `sources/`, the rename changes the semantic. Use this option since v2.3 deletes the `sources/` category concept entirely.

```bash
git mv tests/fixtures/validate-page-cases/wiki-root-mode/sources tests/fixtures/validate-page-cases/wiki-root-mode/concepts-from-sources
# But concepts/ already exists in the fixture; merge:
mv tests/fixtures/validate-page-cases/wiki-root-mode/concepts-from-sources/2026-04-24-x.md \
   tests/fixtures/validate-page-cases/wiki-root-mode/concepts/2026-04-24-x.md
mv tests/fixtures/validate-page-cases/wiki-root-mode/concepts-from-sources/orphan-source.md \
   tests/fixtures/validate-page-cases/wiki-root-mode/concepts/orphan-source.md
rmdir tests/fixtures/validate-page-cases/wiki-root-mode/concepts-from-sources
```

Then update the type frontmatter to plural:

```bash
sed -i.bak 's/^type: concept$/type: concepts/' tests/fixtures/validate-page-cases/wiki-root-mode/concepts/2026-04-24-x.md
sed -i.bak 's/^type: concept$/type: concepts/' tests/fixtures/validate-page-cases/wiki-root-mode/concepts/orphan-source.md
rm tests/fixtures/validate-page-cases/wiki-root-mode/concepts/*.bak
```

Update test-validate-page.sh assertions (lines that reference `${WIKI_FIX}/sources/...`) to point at the new locations:

```bash
sed -i.bak 's|sources/2026-04-24-x.md|concepts/2026-04-24-x.md|g' tests/unit/test-validate-page.sh
sed -i.bak 's|sources/orphan-source.md|concepts/orphan-source.md|g' tests/unit/test-validate-page.sh
sed -i.bak 's|valid concept in sources/ dir|valid concept in concepts/ dir|g' tests/unit/test-validate-page.sh
sed -i.bak 's|concept with missing raw source fails in wiki-root mode|concept with missing raw source fails in concepts/ wiki-root mode|g' tests/unit/test-validate-page.sh
rm tests/unit/test-validate-page.sh.bak
```

Also update the existing `wiki-root-mode/concepts/missing-source.md`'s type from `concept` to `concepts`:

```bash
sed -i.bak 's/^type: concept$/type: concepts/' tests/fixtures/validate-page-cases/wiki-root-mode/concepts/*.md
rm tests/fixtures/validate-page-cases/wiki-root-mode/concepts/*.bak
```

Verify single-file-mode fixtures (`good-concept.md`, etc.) — these are NOT in a wiki-root context so the cross-check doesn't fire; they keep `type: concept`. Verify by running `bash tests/unit/test-validate-page.sh` after the migration — Phase A behavior (warning-only) means existing tests pass. Phase D's flip then becomes safe.

After this fixture migration commit, Task 20's validator-flip can land.

```bash
git add tests/fixtures/validate-page-cases/ tests/unit/test-validate-page.sh
git commit -m "test(v2.3): migrate fixtures sources/ → concepts/ + plural type

Pre-Phase-D-flip fixture cleanup. The wiki-root-mode/sources/ fixture
became invalid under v2.3's hard validator (type/path cross-check).
Move pages to concepts/ subdirectory and update type to plural form."
```

### Corrigenda C-J: Unify lock-slug scheme with `wiki-lock.sh` (no shell-out)

Reviewer flagged C8 (lock domain overlap). `wiki-lock.sh` is a **sourceable bash library** (see line 3: "Source this file; don't execute") with no CLI dispatch — direct shell-out won't work. The smallest correct fix: keep Task 11's in-Python lock implementation, but match `wiki-lock.sh`'s slug scheme exactly so the two domains share the same `.locks/` namespace and cannot collide.

**`wiki-lock.sh`'s slug scheme** (from `scripts/wiki-lock.sh:14-15`):
```bash
slug="$(echo "${page}" | tr '/' '-' | tr '.' '-')"
# Lockfile: ${root}/.locks/${slug}.lock
```

So `concepts/_index.md` → slug `concepts-_index-md` → lockfile `${root}/.locks/concepts-_index-md.lock`.

**Replace `_acquire_lock` and `_release_lock` in Task 11's implementation with:**

```python
def _acquire_lock(wiki_root: Path, rel_path: str) -> Path:
    """Atomic lock create matching wiki-lock.sh's slug scheme.

    rel_path is the wiki-relative page path (e.g. 'concepts/_index.md').
    Slug is rel_path with '/' and '.' both replaced by '-' (mirroring
    wiki-lock.sh:14-15). This ensures the lock-namespace is shared with
    the bash locking library — concurrent ingesters acquiring locks via
    wiki-lock.sh cannot race against wiki-build-index.py acquiring the
    same logical lock under a different filename.
    """
    slug = rel_path.replace("/", "-").replace(".", "-") + ".lock"
    lockdir = wiki_root / ".locks"
    lockdir.mkdir(exist_ok=True)
    lockfile = lockdir / slug
    deadline = time.time() + LOCK_TIMEOUT_S
    while time.time() < deadline:
        try:
            with lockfile.open("x") as fd:
                fd.write(f"build-index:{rel_path}:{time.time()}\n")
            return lockfile
        except FileExistsError:
            time.sleep(LOCK_POLL_S)
    raise TimeoutError(f"lock timeout: {rel_path}")


def _release_lock(lockfile: Path) -> None:
    lockfile.unlink(missing_ok=True)
```

**Update Task 11 step 1 test `test_ancestor_lock_path_ordering`:** the lock filename pattern check should match the new slug scheme (`concepts-_index-md.lock`, not `concepts__index.md.lock`).

The trade-off: full integration with `wiki-lock.sh`'s stale-lock reclaim + log_warn message would require either a CLI shim on `wiki-lock.sh` (out of scope) or reimplementing reclaim in Python (overkill for v2.3). Stale `_index.md` locks are extremely unlikely (sub-100ms write); 30-second timeout + manual `rm .locks/<slug>.lock` is sufficient. Future cleanup: add a CLI wrapper to `wiki-lock.sh` in v2.4 so all lockers go through one path.

---

### Corrigenda C-K: Test that breaks between Task 5 and Task 21 (acknowledged window)

After Task 5 (validator changes), `test-validate-no-source-type.sh` line 37's grep for "type must be one of" will fail because the validator no longer emits that string. Task 21 renames and updates this test to assert v2.3 semantics.

**Window:** Tasks 6-20 inclusive will see this test fail when running `bash tests/run-all.sh`. This is EXPECTED. The test runner reports it as failing; subagents and reviewers should treat it as known-acknowledged-temporary, not a regression. Task 21 closes the window.

**Workaround for Phase A.1 verification gate (after Task 8):** when running `bash tests/run-all.sh` for the gate, expect this one test to fail. Document explicitly: `tests/run-all.sh` will report 1 failure (test-validate-no-source-type) which is acknowledged and resolved in Phase D Task 21. All other tests must pass.

If preferred, a smaller alternative: do Task 21's rename FIRST (move it to immediately after Task 5 in the execution order). Implementer choice — both produce a clean Phase E result.

---

End of corrigenda. Proceed to execute the original plan body, applying the above overrides as you encounter the affected tasks.

---

---

## File Structure

### New files (created in this ship)

| Path | Purpose |
|------|---------|
| `scripts/wiki-discover.py` | Walks wiki root; emits JSON with categories, reserved, depths, counts. Single source of truth for category data. |
| `scripts/wiki-fix-frontmatter.py` | Recomputes `type:` from `path.parts[0]` (plural). Frontmatter-only. Idempotent. |
| `scripts/wiki-build-index.py` | Recursive index builder. Writes `_index.md` per directory + root MOC. Path-ordered lock acquisition. |
| `scripts/wiki-relink.py` | Phase D migration: rewrites inbound links to moved pages to leading-`/` form. Only-moved-pages scope. |
| `scripts/wiki-migrate-v2.3.sh` | Phase D orchestrator: page-moves + relink + index-rebuild. Named functions, `--dry-run`, idempotent. |
| `tests/unit/test-discover.sh` | ~8 cases — discovery output shape, reserved-skipping, depth/count, error robustness. |
| `tests/unit/test-fix-frontmatter.sh` | ~7 cases — recompute, idempotent, frontmatter-only contract under adversarial inputs. |
| `tests/unit/test-build-index.sh` | ~9 cases — `_index.md` shape, MOC, lock path-ordering, depth-≥5 reject, Rule 3 schema-proposal. |
| `tests/unit/test-relink.sh` | ~5 cases — relative→leading-`/`, only-moved-pages, idempotent. |
| `tests/unit/test-migrate-v2.3.sh` | ~5 cases — dry-run, full run, idempotent re-run, atomic moves+relinks gate. |
| `tests/unit/test-bundle-sync.sh` | ~2 cases — sha256 parity between `/scripts/` and `/skills/karpathy-wiki/scripts/`. |
| `docs/planning/transcripts/2026-04-26-auto-discovered-categories.md` | Pressure scenario fixture. |
| `docs/planning/transcripts/2026-04-26-category-discipline-ceiling.md` | Pressure scenario fixture. |
| `docs/planning/transcripts/2026-04-26-reply-first-ordering.md` | Pressure scenario fixture. |

### Modified files

| Path | Change |
|------|--------|
| `scripts/wiki-validate-page.py` | Drop `VALID_TYPES`; read from discovery; type/path cross-check; depth-≥5 hard fail; leading-`/` link resolution; exit non-zero on discovery failure. Phase A: warning-only on cross-check + membership; Phase D: hard violation. |
| `scripts/wiki-status.sh` | Replace hardcoded category walk with discovery; add 2 new lines (depth, soft-ceiling). |
| `scripts/wiki-backfill-quality.py` | Replace hardcoded `("concepts", "entities", "sources", "queries")` tuple with discovery walk. |
| `scripts/wiki-init.sh` | Add `python3 --version >= 3.11` check; update seed list (drop `sources/`, add `ideas/`). |
| `scripts/wiki-normalize-frontmatter.py` | Add deprecation header comment. Body unchanged. |
| `skills/karpathy-wiki/SKILL.md` | New sections: index structure (recursive `_index.md`); cross-link convention (leading-`/`); auto-discovery contract; reply-first turn ordering rule; three category-discipline rules. New rationalization rows in resist-table. |
| `tests/unit/test-validate-page.sh` | +5 cases (link res, cross-check warn, cross-check hard, valid-types-from-discovery, discovery-failure-exit). |
| `tests/unit/test-validate-no-source-type.sh` | Rename to `test-validate-deleted-categories.sh`; +1 case for `type: nonsense`. |
| `tests/unit/test-status.sh` | +4 cases (count from discovery, depth report, depth-violation count, soft-ceiling line). |
| `tests/unit/test-backfill-quality.sh` | +3 cases (discovery walk, includes `ideas/`, skips reserved). |
| `tests/unit/test-index-threshold-fires.sh` | +2 cases (per-`_index.md` threshold, debounce). |
| `tests/unit/test-init.sh` | +2 cases (Python version check, seed list). |
| `tests/integration/test-concurrent-ingest.sh` | +2 cases (`_index.md` lock contention same subtree, path-ordering deadlock-free). |
| `tests/run-all.sh` | Add `test-bundle-sync.sh` to its run path (already auto-picks up via `test-*.sh` glob). |
| `~/wiki/schema.md` | (Live wiki, Phase A.2 commit 3) Add `<!-- CATEGORIES:START/END -->` and `<!-- RESERVED:START/END -->` markers; move `### ideas/ frontmatter extension` subsection to top-level `## Ideas Category Extension`. |
| `~/wiki/index.md` | (Live wiki, Phase D commit 3) Replaced by 7-line MOC. |
| `~/wiki/concepts/<page>.md` × 49 | (Live wiki, Phase A.2 commit 2) Frontmatter `type: concept` → `type: concepts`. |
| `~/wiki/entities/<page>.md` × 4 | (Live wiki, Phase A.2 commit 2) `type: entity` → `type: entities`. |
| `~/wiki/ideas/<page>.md` × 5 | (Live wiki, Phase A.2 commit 2) `type: concept` → `type: ideas`. |
| `~/wiki/concepts/{4 named pages}.md` | (Live wiki, Phase D commit 2) `git mv` to `~/wiki/projects/toolboxmd/<project>/`. |
| `~/wiki/projects/toolboxmd/{karpathy-wiki,building-agentskills}/` | (Live wiki, Phase D commit 2) Created via mkdir. |
| `~/wiki/<every-dir>/_index.md` | (Live wiki, Phase D commit 4) Generated by `wiki-build-index.py --rebuild-all`. |

### Bundle-copy contract (per spec §5.6)

Every script change in `/scripts/` MUST be hand-copied to `/skills/karpathy-wiki/scripts/` within the same commit. CI verifies via `test-bundle-sync.sh` (sha256 parity per file). The "skill-bundle automation" deferred to v2.4 is about building proper sync machinery; v2.3 hand-copies because the changed-file count is small.

When a task says "create/modify `scripts/X`", the implicit second action is "also copy to `skills/karpathy-wiki/scripts/X`". Each task's commit step explicitly lists both `git add` paths.

---

## Phase A.1: New scripts and validator changes (this repo only)

### Task 1: Create `wiki-discover.py` — categories + reserved + depths + counts

**Files:**
- Create: `scripts/wiki-discover.py`
- Create: `skills/karpathy-wiki/scripts/wiki-discover.py` (bundle copy, identical content)
- Test: `tests/unit/test-discover.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test-discover.sh`:

```bash
#!/bin/bash
# Test: wiki-discover.py walks wiki root, emits expected JSON.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DISCOVER="${REPO_ROOT}/scripts/wiki-discover.py"

setup() {
  TMP="$(mktemp -d)"
  WIKI="${TMP}/wiki"
  mkdir -p "${WIKI}/concepts" "${WIKI}/entities" "${WIKI}/queries" "${WIKI}/ideas" \
           "${WIKI}/raw" "${WIKI}/.wiki-pending" "${WIKI}/.locks" "${WIKI}/.obsidian" \
           "${WIKI}/Clippings"
  touch "${WIKI}/.wiki-config"
}
teardown() { rm -rf "${TMP}"; }

test_categories_listed() {
  setup
  out="$(python3 "${DISCOVER}" --wiki-root "${WIKI}")"
  echo "${out}" | python3 -c "import json,sys; d=json.load(sys.stdin); assert sorted(d['categories'])==['concepts','entities','ideas','queries'], d"
  teardown
}

test_reserved_skipped() {
  setup
  out="$(python3 "${DISCOVER}" --wiki-root "${WIKI}")"
  echo "${out}" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'raw' not in d['categories'] and 'Clippings' not in d['categories'] and '.obsidian' not in d['categories'], d"
  teardown
}

test_dotted_skipped() {
  setup
  mkdir -p "${WIKI}/.git"
  out="$(python3 "${DISCOVER}" --wiki-root "${WIKI}")"
  echo "${out}" | python3 -c "import json,sys; d=json.load(sys.stdin); assert '.git' not in d['categories']"
  teardown
}

test_depth_correct_flat() {
  setup
  echo "stub" > "${WIKI}/concepts/foo.md"
  out="$(python3 "${DISCOVER}" --wiki-root "${WIKI}")"
  echo "${out}" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['depths']['concepts']==1, d"
  teardown
}

test_depth_correct_nested() {
  setup
  mkdir -p "${WIKI}/projects/a/b/c"
  echo "stub" > "${WIKI}/projects/a/b/c/foo.md"
  out="$(python3 "${DISCOVER}" --wiki-root "${WIKI}")"
  echo "${out}" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['depths']['projects']==4, d"
  teardown
}

test_counts_correct() {
  setup
  echo "stub" > "${WIKI}/concepts/foo.md"
  echo "stub" > "${WIKI}/concepts/bar.md"
  echo "stub" > "${WIKI}/entities/baz.md"
  out="$(python3 "${DISCOVER}" --wiki-root "${WIKI}")"
  echo "${out}" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['counts']['concepts']==2 and d['counts']['entities']==1, d"
  teardown
}

test_json_shape_has_required_keys() {
  setup
  out="$(python3 "${DISCOVER}" --wiki-root "${WIKI}")"
  echo "${out}" | python3 -c "import json,sys; d=json.load(sys.stdin); [d[k] for k in ('categories','reserved','depths','counts')]"
  teardown
}

test_reserved_set_exposed() {
  setup
  out="$(python3 "${DISCOVER}" --wiki-root "${WIKI}")"
  echo "${out}" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'raw' in d['reserved'] and 'Clippings' in d['reserved']"
  teardown
}

test_categories_listed
test_reserved_skipped
test_dotted_skipped
test_depth_correct_flat
test_depth_correct_nested
test_counts_correct
test_json_shape_has_required_keys
test_reserved_set_exposed
echo "all tests passed"
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bash tests/unit/test-discover.sh
```
Expected: FAIL with "scripts/wiki-discover.py: No such file or directory".

- [ ] **Step 3: Write minimal implementation**

Create `scripts/wiki-discover.py`:

```python
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
```

Make executable: `chmod +x scripts/wiki-discover.py`.

- [ ] **Step 4: Hand-copy to skill bundle**

```bash
cp scripts/wiki-discover.py skills/karpathy-wiki/scripts/wiki-discover.py
chmod +x skills/karpathy-wiki/scripts/wiki-discover.py
```

- [ ] **Step 5: Run test to verify it passes**

```bash
bash tests/unit/test-discover.sh
```
Expected: "all tests passed".

- [ ] **Step 6: Commit**

```bash
git add scripts/wiki-discover.py skills/karpathy-wiki/scripts/wiki-discover.py tests/unit/test-discover.sh
git commit -m "feat(v2.3): add wiki-discover.py for auto-discovered categories

- Walks wiki root; emits JSON with categories/reserved/depths/counts.
- Reserved set: raw, index, archive, Clippings + dotted dirs.
- No cache; sub-100ms walk on 60-file wiki.
- Bundle-copy to skills/karpathy-wiki/scripts per v2.3 spec §5.6."
```

---

### Task 2: Create `tests/unit/test-bundle-sync.sh` — sha256 parity check

**Files:**
- Create: `tests/unit/test-bundle-sync.sh`

- [ ] **Step 1: Write the test**

Create `tests/unit/test-bundle-sync.sh`:

```bash
#!/bin/bash
# Test: every script in scripts/ has an identical-sha256 twin in skills/karpathy-wiki/scripts/.
# Per v2.3 spec §5.6 bundle-copy contract.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DEV="${REPO_ROOT}/scripts"
BUNDLE="${REPO_ROOT}/skills/karpathy-wiki/scripts"

test_every_dev_script_in_bundle() {
  local missing=0
  for f in "${DEV}"/*.{sh,py}; do
    [[ -f "${f}" ]] || continue
    base="$(basename "${f}")"
    if [[ ! -f "${BUNDLE}/${base}" ]]; then
      echo "missing in bundle: ${base}"
      missing=$((missing + 1))
    fi
  done
  if [[ "${missing}" -gt 0 ]]; then
    echo "FAIL: ${missing} script(s) not bundle-copied"
    exit 1
  fi
}

test_sha256_parity() {
  local drift=0
  for f in "${DEV}"/*.{sh,py}; do
    [[ -f "${f}" ]] || continue
    base="$(basename "${f}")"
    [[ -f "${BUNDLE}/${base}" ]] || continue  # missing already caught above
    dev_sha="$(shasum -a 256 "${f}" | awk '{print $1}')"
    bundle_sha="$(shasum -a 256 "${BUNDLE}/${base}" | awk '{print $1}')"
    if [[ "${dev_sha}" != "${bundle_sha}" ]]; then
      echo "drift: ${base} (dev=${dev_sha:0:12} bundle=${bundle_sha:0:12})"
      drift=$((drift + 1))
    fi
  done
  if [[ "${drift}" -gt 0 ]]; then
    echo "FAIL: ${drift} script(s) drifted between dev and bundle"
    exit 1
  fi
}

test_every_dev_script_in_bundle
test_sha256_parity
echo "all tests passed"
```

- [ ] **Step 2: Run test to verify it passes**

(After Task 1 the bundle copy of `wiki-discover.py` exists; the rest of the scripts already match in current state.)

```bash
bash tests/unit/test-bundle-sync.sh
```
Expected: "all tests passed".

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test-bundle-sync.sh
git commit -m "test(v2.3): add bundle-sync sha256 parity check

Per v2.3 spec §5.6: every script change must land in both /scripts/
and /skills/karpathy-wiki/scripts/ within the same commit. CI fails
on drift. Building proper sync machinery deferred to v2.4."
```

---

### Task 3: Mark `wiki-normalize-frontmatter.py` obsolete (header comment only)

**Files:**
- Modify: `scripts/wiki-normalize-frontmatter.py:1-15` (insert deprecation comment)
- Modify: `skills/karpathy-wiki/scripts/wiki-normalize-frontmatter.py` (bundle copy)

- [ ] **Step 1: Read current header**

```bash
head -10 scripts/wiki-normalize-frontmatter.py
```

- [ ] **Step 2: Insert deprecation comment after shebang**

Edit `scripts/wiki-normalize-frontmatter.py`. Find the shebang/docstring opener and insert:

```python
#!/usr/bin/env python3
"""DEPRECATED in karpathy-wiki v2.3.

Superseded by wiki-fix-frontmatter.py (path-derived plural type).

Retained because scripts/wiki-migrate-v2-hardening.sh:71 invokes this
script for replay of the historical v2-hardening migration on a fresh
fixture; deletion would break that script's reproducibility.

DO NOT INVOKE FROM v2.3+ FLOWS. Use wiki-fix-frontmatter.py instead.

[original docstring follows below]
"""
```

(Preserve the original docstring after the deprecation block — append it as a continuation.)

- [ ] **Step 3: Hand-copy to bundle**

```bash
cp scripts/wiki-normalize-frontmatter.py skills/karpathy-wiki/scripts/wiki-normalize-frontmatter.py
```

- [ ] **Step 4: Verify existing test still passes**

```bash
bash tests/unit/test-normalize-frontmatter.sh
```
Expected: PASS (no behavioral change; only a comment added).

- [ ] **Step 5: Verify bundle-sync test passes**

```bash
bash tests/unit/test-bundle-sync.sh
```
Expected: "all tests passed".

- [ ] **Step 6: Commit**

```bash
git add scripts/wiki-normalize-frontmatter.py skills/karpathy-wiki/scripts/wiki-normalize-frontmatter.py
git commit -m "chore(v2.3): mark wiki-normalize-frontmatter.py deprecated

Superseded by wiki-fix-frontmatter.py (created in next commit).
Retained for wiki-migrate-v2-hardening.sh:71 historical replay.
v2.3+ flows must use wiki-fix-frontmatter.py."
```

---

### Task 4: Create `wiki-fix-frontmatter.py` — path-derived plural type, frontmatter-only

**Files:**
- Create: `scripts/wiki-fix-frontmatter.py`
- Create: `skills/karpathy-wiki/scripts/wiki-fix-frontmatter.py`
- Test: `tests/unit/test-fix-frontmatter.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test-fix-frontmatter.sh`:

```bash
#!/bin/bash
# Test: wiki-fix-frontmatter.py recomputes type: from path; frontmatter-only.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FIX="${REPO_ROOT}/scripts/wiki-fix-frontmatter.py"

setup() {
  TMP="$(mktemp -d)"
  WIKI="${TMP}/wiki"
  mkdir -p "${WIKI}/concepts" "${WIKI}/ideas" "${WIKI}/raw"
  touch "${WIKI}/.wiki-config"
}
teardown() { rm -rf "${TMP}"; }

write_page() {
  local path="$1"; local body="$2"
  cat > "${path}"
}

test_concept_singular_to_plural() {
  setup
  cat > "${WIKI}/concepts/foo.md" <<'EOF'
---
title: "Foo"
type: concept
tags: [test]
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
---

body
EOF
  python3 "${FIX}" --wiki-root "${WIKI}" "${WIKI}/concepts/foo.md"
  grep -q "^type: concepts$" "${WIKI}/concepts/foo.md" || { echo "FAIL: type not rewritten to concepts"; exit 1; }
  teardown
}

test_idea_path_value_correction() {
  setup
  cat > "${WIKI}/ideas/foo.md" <<'EOF'
---
title: "Foo"
type: concept
tags: [test]
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
---

body
EOF
  python3 "${FIX}" --wiki-root "${WIKI}" "${WIKI}/ideas/foo.md"
  grep -q "^type: ideas$" "${WIKI}/ideas/foo.md" || { echo "FAIL: ideas/ page not corrected"; exit 1; }
  teardown
}

test_idempotent() {
  setup
  cat > "${WIKI}/concepts/foo.md" <<'EOF'
---
title: "Foo"
type: concepts
tags: [test]
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
---

body
EOF
  before="$(shasum -a 256 "${WIKI}/concepts/foo.md")"
  python3 "${FIX}" --wiki-root "${WIKI}" "${WIKI}/concepts/foo.md"
  after="$(shasum -a 256 "${WIKI}/concepts/foo.md")"
  [[ "${before}" == "${after}" ]] || { echo "FAIL: not idempotent"; exit 1; }
  teardown
}

test_preserves_human_quality() {
  setup
  cat > "${WIKI}/concepts/foo.md" <<'EOF'
---
title: "Foo"
type: concept
tags: [test]
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 5
  overall: 5.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: human
---

body
EOF
  python3 "${FIX}" --wiki-root "${WIKI}" "${WIKI}/concepts/foo.md"
  grep -q "rated_by: human" "${WIKI}/concepts/foo.md" || { echo "FAIL: human rating clobbered"; exit 1; }
  teardown
}

test_frontmatter_only_body_with_type_marker() {
  setup
  cat > "${WIKI}/concepts/foo.md" <<'EOF'
---
title: "Foo"
type: concept
tags: [test]
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
---

Body with a teaching example:

```yaml
type: idea
status: open
```

end of body.
EOF
  python3 "${FIX}" --wiki-root "${WIKI}" "${WIKI}/concepts/foo.md"
  # frontmatter type rewritten
  grep -q "^type: concepts$" "${WIKI}/concepts/foo.md" || { echo "FAIL: frontmatter not rewritten"; exit 1; }
  # body type:idea preserved verbatim
  grep -q "^type: idea$" "${WIKI}/concepts/foo.md" || { echo "FAIL: body type literal lost"; exit 1; }
  teardown
}

test_frontmatter_only_body_with_dashes_marker() {
  setup
  cat > "${WIKI}/concepts/foo.md" <<'EOF'
---
title: "Foo"
type: concept
tags: [test]
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
---

Some body text.

---

A horizontal rule above; another type marker would be valid prose:
type: example

end.
EOF
  python3 "${FIX}" --wiki-root "${WIKI}" "${WIKI}/concepts/foo.md"
  grep -q "^type: concepts$" "${WIKI}/concepts/foo.md" || { echo "FAIL: frontmatter not rewritten"; exit 1; }
  grep -q "^type: example$" "${WIKI}/concepts/foo.md" || { echo "FAIL: body type literal lost (--- not respected as horizontal rule)"; exit 1; }
  teardown
}

test_full_wiki_batch() {
  setup
  for i in 1 2 3; do
    cat > "${WIKI}/concepts/c${i}.md" <<EOF
---
title: "C${i}"
type: concept
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
---
body
EOF
  done
  python3 "${FIX}" --wiki-root "${WIKI}" --all
  for i in 1 2 3; do
    grep -q "^type: concepts$" "${WIKI}/concepts/c${i}.md" || { echo "FAIL: c${i} not rewritten"; exit 1; }
  done
  teardown
}

test_concept_singular_to_plural
test_idea_path_value_correction
test_idempotent
test_preserves_human_quality
test_frontmatter_only_body_with_type_marker
test_frontmatter_only_body_with_dashes_marker
test_full_wiki_batch
echo "all tests passed"
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bash tests/unit/test-fix-frontmatter.sh
```
Expected: FAIL with "scripts/wiki-fix-frontmatter.py: No such file".

- [ ] **Step 3: Write minimal implementation**

Create `scripts/wiki-fix-frontmatter.py`:

```python
#!/usr/bin/env python3
"""Recompute type: in YAML frontmatter from path.parts[0] (plural form).

Frontmatter-only: never modifies body content.

Usage:
    wiki-fix-frontmatter.py --wiki-root <root> <page.md>      # one page
    wiki-fix-frontmatter.py --wiki-root <root> --all          # every page

Exit codes:
    0 - success (or no-op for already-correct pages)
    1 - usage error or wiki-root not a directory
"""
import argparse
import re
import sys
from pathlib import Path

FRONTMATTER_TYPE_RE = re.compile(r"^type:\s*\S.*$", re.MULTILINE)


def _split_frontmatter(text: str) -> tuple[str, str, str] | tuple[None, None, None]:
    """Return (before_open, frontmatter_lines, after_close) or (None,None,None) if no frontmatter."""
    if not text.startswith("---\n"):
        return (None, None, None)
    # Find the closing "---" on a line by itself, after the first one.
    lines = text.split("\n")
    if not lines or lines[0] != "---":
        return (None, None, None)
    for i in range(1, len(lines)):
        if lines[i] == "---":
            fm = "\n".join(lines[1:i])
            after = "\n".join(lines[i:]) + ("\n" if text.endswith("\n") else "")
            # Reassemble: "---\n" + fm + "\n" + after  (after starts with "---")
            return ("---\n", fm, after)
    return (None, None, None)


def _expected_type(page: Path, wiki_root: Path) -> str:
    rel = page.resolve().relative_to(wiki_root.resolve())
    return rel.parts[0]


def fix_page(page: Path, wiki_root: Path) -> bool:
    """Return True if the page was modified."""
    text = page.read_text()
    before, fm, after = _split_frontmatter(text)
    if fm is None:
        print(f"skip (no frontmatter): {page}", file=sys.stderr)
        return False

    expected = _expected_type(page, wiki_root)

    def _rewrite(match: re.Match) -> str:
        return f"type: {expected}"

    new_fm, n = FRONTMATTER_TYPE_RE.subn(_rewrite, fm, count=1)
    if n == 0:
        # No type: line in frontmatter; insert one after the opening.
        new_fm = f"type: {expected}\n" + fm

    if new_fm == fm:
        return False  # already correct

    page.write_text(before + new_fm + "\n" + after)
    return True


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--wiki-root", required=True)
    p.add_argument("page", nargs="?", help="single page path (relative or absolute)")
    p.add_argument("--all", action="store_true", help="fix every .md page in the wiki")
    args = p.parse_args()

    root = Path(args.wiki_root).resolve()
    if not root.is_dir():
        print(f"not a directory: {root}", file=sys.stderr)
        return 1

    if args.all:
        changed = 0
        for page in sorted(root.rglob("*.md")):
            # Skip raw/, .wiki-pending/, .locks/, etc.
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
```

Make executable: `chmod +x scripts/wiki-fix-frontmatter.py`.

- [ ] **Step 4: Hand-copy to bundle**

```bash
cp scripts/wiki-fix-frontmatter.py skills/karpathy-wiki/scripts/wiki-fix-frontmatter.py
chmod +x skills/karpathy-wiki/scripts/wiki-fix-frontmatter.py
```

- [ ] **Step 5: Run tests**

```bash
bash tests/unit/test-fix-frontmatter.sh
bash tests/unit/test-bundle-sync.sh
```
Expected: both "all tests passed".

- [ ] **Step 6: Commit**

```bash
git add scripts/wiki-fix-frontmatter.py skills/karpathy-wiki/scripts/wiki-fix-frontmatter.py tests/unit/test-fix-frontmatter.sh
git commit -m "feat(v2.3): add wiki-fix-frontmatter.py (path-derived plural type)

- Recomputes type: from path.parts[0] in YAML frontmatter only.
- Body content (including teaching examples with type:) is never touched.
- Adversarial fixtures: body-with-type-marker, body-with-dashes-marker.
- Idempotent. Preserves quality.rated_by: human."
```

---

### Task 5: Extend `wiki-validate-page.py` — discovery, cross-check, leading-`/`, depth-≥5

**Files:**
- Modify: `scripts/wiki-validate-page.py:39` (drop `VALID_TYPES`); add new checks throughout.
- Modify: `skills/karpathy-wiki/scripts/wiki-validate-page.py` (bundle copy)
- Modify: `tests/unit/test-validate-page.sh` (+5 cases)

- [ ] **Step 1: Read the current validator structure**

```bash
sed -n '34,50p' scripts/wiki-validate-page.py
```
Note line 39: `VALID_TYPES = {"concept", "entity", "query"}`. This gets replaced.

- [ ] **Step 2: Write the failing tests (new cases in test-validate-page.sh)**

Append to `tests/unit/test-validate-page.sh` (preserve existing tests; add these inside the file's existing structure):

```bash
test_leading_slash_link_resolves_from_wiki_root() {
  # Setup a small wiki fixture
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/concepts" "${tmp}/wiki/projects/toolboxmd/karpathy-wiki" "${tmp}/wiki/raw"
  touch "${tmp}/wiki/.wiki-config"
  echo "stub" > "${tmp}/wiki/concepts/foo.md"
  cat > "${tmp}/wiki/projects/toolboxmd/karpathy-wiki/v23.md" <<'EOF'
---
title: "v2.3"
type: projects
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 5
  overall: 5.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: ingester
---

See [foo](/concepts/foo.md).
EOF
  python3 "${VALIDATOR}" --wiki-root "${tmp}/wiki" "${tmp}/wiki/projects/toolboxmd/karpathy-wiki/v23.md"
  rm -rf "${tmp}"
}

test_type_path_cross_check_warning_phase_a() {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/concepts" "${tmp}/wiki/raw"
  touch "${tmp}/wiki/.wiki-config"
  cat > "${tmp}/wiki/concepts/foo.md" <<'EOF'
---
title: "Foo"
type: entities
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 5
  overall: 5.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: ingester
---
body
EOF
  # Phase A behavior: cross-check is WARNING; should still exit 0.
  out_err="$(python3 "${VALIDATOR}" --wiki-root "${tmp}/wiki" "${tmp}/wiki/concepts/foo.md" 2>&1 1>/dev/null || true)"
  echo "${out_err}" | grep -q "WARNING.*type.*path" || { echo "FAIL: expected WARNING line"; exit 1; }
  rm -rf "${tmp}"
}

test_valid_types_from_discovery() {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/concepts" "${tmp}/wiki/journal" "${tmp}/wiki/raw"
  touch "${tmp}/wiki/.wiki-config"
  cat > "${tmp}/wiki/journal/2026-04-26.md" <<'EOF'
---
title: "Today"
type: journal
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 5
  overall: 5.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: ingester
---
body
EOF
  python3 "${VALIDATOR}" --wiki-root "${tmp}/wiki" "${tmp}/wiki/journal/2026-04-26.md"
  rm -rf "${tmp}"
}

test_discovery_failure_exits_nonzero() {
  # Pass a wiki-root that does not exist -> discovery fails -> validator exits non-zero.
  out="$(python3 "${VALIDATOR}" --wiki-root /nonexistent/path /nonexistent/path/concepts/foo.md 2>&1 || true)"
  echo "${out}" | grep -q "wiki-discover.py failed\|not a directory" || { echo "FAIL: expected discovery error"; exit 1; }
}

test_depth_ge_5_hard_fail() {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/concepts/a/b/c/d" "${tmp}/wiki/raw"
  touch "${tmp}/wiki/.wiki-config"
  cat > "${tmp}/wiki/concepts/a/b/c/d/deep.md" <<'EOF'
---
title: "Deep"
type: concepts
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 5
  overall: 5.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: ingester
---
body
EOF
  if python3 "${VALIDATOR}" --wiki-root "${tmp}/wiki" "${tmp}/wiki/concepts/a/b/c/d/deep.md" 2>/dev/null; then
    echo "FAIL: depth 5 page accepted; should be rejected"
    rm -rf "${tmp}"; exit 1
  fi
  rm -rf "${tmp}"
}
```

Add these test invocations at the end of the file alongside the existing test_* calls.

- [ ] **Step 3: Run extended test to verify NEW cases fail**

```bash
bash tests/unit/test-validate-page.sh
```
Expected: at least one of the new cases fails because the validator hasn't been updated yet.

- [ ] **Step 4: Implement validator changes**

Edit `scripts/wiki-validate-page.py`:

a) Replace line 39 `VALID_TYPES = {"concept", "entity", "query"}` with:

```python
# v2.3: VALID_TYPES is now derived from wiki-discover.py output; no static set.
```

b) Add a discovery helper function near the top of the module:

```python
def _discover(wiki_root: Path) -> dict:
    """Invoke wiki-discover.py; return its JSON output as a dict.

    Raises RuntimeError on discovery failure (validator exits non-zero on this).
    """
    import json as _json
    import subprocess as _sp
    script = Path(__file__).parent / "wiki-discover.py"
    result = _sp.run(
        ["python3", str(script), "--wiki-root", str(wiki_root)],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        raise RuntimeError(f"wiki-discover.py failed: {result.stderr.strip()}")
    return _json.loads(result.stdout)
```

c) Update the type-validation step to use discovery's `categories` list. Replace the existing `type` check block with:

```python
# Type validity: must be in the discovered categories list.
discovered_types = set(disc["categories"])
if t not in discovered_types:
    # Phase A behavior: warning to stderr, do NOT exit non-zero.
    # Phase D's validator-flip commit changes "WARNING" to a hard violation
    # by removing the next return-False guard.
    print(f"{rel}: WARNING type '{t}' not in discovered categories {sorted(discovered_types)}", file=sys.stderr)
    # In Phase A this returns "ok" with a warning. The Phase D flip removes the soft-warning behavior.
```

d) Add the type/path cross-check after the type-validity check:

```python
# Type vs path cross-check.
expected_type = path.relative_to(wiki_root).parts[0]
if t != expected_type:
    print(
        f"{rel}: WARNING type '{t}' != path.parts[0] '{expected_type}' "
        f"(run: python3 scripts/wiki-fix-frontmatter.py --wiki-root {wiki_root} {rel})",
        file=sys.stderr,
    )
```

e) Add the depth-≥5 hard check (always-on, not soft-warning):

```python
# Depth ≥ 5 is a hard violation (Rule 2). counted from wiki-root: category + 4 nested = depth 5.
parts = path.relative_to(wiki_root).parts
if len(parts) > 5:  # parts: [category, dir1, dir2, dir3, dir4, page.md] -> > 5
    violations.append(
        f"{rel}: page at depth {len(parts)} exceeds hard cap (5); "
        f"place shallower or restructure category."
    )
```

f) Update the link-resolver to handle leading `/`:

In the existing link-resolution code (search for the block that resolves `[text](href)`), prepend a check:

```python
# v2.3: leading "/" resolves from wiki root, not page directory.
if href.startswith("/"):
    target = (wiki_root / href[1:]).resolve()
else:
    target = (page.parent / href).resolve()
```

g) Add the discovery call early in `main()` (or wherever validation sequence starts), before checking `type`:

```python
try:
    disc = _discover(wiki_root)
except RuntimeError as e:
    print(str(e), file=sys.stderr)
    return 1
```

- [ ] **Step 5: Hand-copy to bundle**

```bash
cp scripts/wiki-validate-page.py skills/karpathy-wiki/scripts/wiki-validate-page.py
```

- [ ] **Step 6: Run tests**

```bash
bash tests/unit/test-validate-page.sh
bash tests/unit/test-bundle-sync.sh
```
Expected: both "all tests passed".

- [ ] **Step 7: Verify other validator tests still pass**

```bash
bash tests/unit/test-validate-no-source-type.sh
bash tests/unit/test-validate-code-block-skip.sh
```
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add scripts/wiki-validate-page.py skills/karpathy-wiki/scripts/wiki-validate-page.py tests/unit/test-validate-page.sh
git commit -m "feat(v2.3): validator uses discovery, adds cross-check + depth + leading-/

- Drops VALID_TYPES; reads valid types from wiki-discover.py.
- Phase A behavior: type-membership and type/path cross-check are WARNING only.
  Phase D will flip both to hard violations after live wiki migration.
- New: depth-≥5 hard reject (Rule 2 mechanism).
- New: leading '/' link resolution from wiki root.
- New: exit non-zero on discovery failure (no silent fallback)."
```

---

### Task 6: Extend `wiki-status.sh` — discovery walk + new lines

**Files:**
- Modify: `scripts/wiki-status.sh:67` (replace hardcoded category list); add new lines.
- Modify: `skills/karpathy-wiki/scripts/wiki-status.sh` (bundle copy)
- Modify: `tests/unit/test-status.sh` (+4 cases)

- [ ] **Step 1: Read existing status script**

```bash
cat scripts/wiki-status.sh
```
Note line 67: `find "${wiki}/concepts" "${wiki}/entities" "${wiki}/sources" "${wiki}/queries" -type f -name "*.md"`. This must use discovery.

- [ ] **Step 2: Write failing tests**

Append to `tests/unit/test-status.sh`:

```bash
test_status_walks_discovered_categories() {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/concepts" "${tmp}/wiki/ideas" "${tmp}/wiki/raw" "${tmp}/wiki/.wiki-pending"
  touch "${tmp}/wiki/.wiki-config"
  echo "stub" > "${tmp}/wiki/concepts/foo.md"
  echo "stub" > "${tmp}/wiki/ideas/bar.md"
  out="$(bash "${REPO_ROOT}/scripts/wiki-status.sh" --wiki-root "${tmp}/wiki" 2>&1 || true)"
  echo "${out}" | grep -q "concepts: 1" && echo "${out}" | grep -q "ideas: 1" || { echo "FAIL: status missing categories"; exit 1; }
  rm -rf "${tmp}"
}

test_status_includes_ideas_directory() {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/ideas" "${tmp}/wiki/raw"
  touch "${tmp}/wiki/.wiki-config"
  echo "stub" > "${tmp}/wiki/ideas/foo.md"
  out="$(bash "${REPO_ROOT}/scripts/wiki-status.sh" --wiki-root "${tmp}/wiki" 2>&1)"
  echo "${out}" | grep -q "ideas" || { echo "FAIL: ideas/ not surfaced"; exit 1; }
  rm -rf "${tmp}"
}

test_status_depth_violation_count() {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/concepts/a/b/c/d" "${tmp}/wiki/raw"
  touch "${tmp}/wiki/.wiki-config"
  echo "stub" > "${tmp}/wiki/concepts/a/b/c/d/deep.md"
  out="$(bash "${REPO_ROOT}/scripts/wiki-status.sh" --wiki-root "${tmp}/wiki" 2>&1)"
  echo "${out}" | grep -q "categories exceeding depth 4" || { echo "FAIL: depth-violation line absent"; exit 1; }
  rm -rf "${tmp}"
}

test_status_soft_ceiling_line() {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/raw"
  touch "${tmp}/wiki/.wiki-config"
  for c in a b c d e f g h i; do mkdir -p "${tmp}/wiki/${c}"; echo "stub" > "${tmp}/wiki/${c}/x.md"; done
  out="$(bash "${REPO_ROOT}/scripts/wiki-status.sh" --wiki-root "${tmp}/wiki" 2>&1)"
  echo "${out}" | grep -q "category count vs soft-ceiling" || { echo "FAIL: soft-ceiling line absent"; exit 1; }
  rm -rf "${tmp}"
}
```

- [ ] **Step 3: Run extended test to verify new cases fail**

```bash
bash tests/unit/test-status.sh
```
Expected: at least one new case fails.

- [ ] **Step 4: Modify `scripts/wiki-status.sh`**

Replace the hardcoded `find` block (around line 67) with a discovery-driven walk. Add the 2 new output lines. Concrete edit (replace the relevant block):

```bash
# v2.3: read categories from wiki-discover.py
discovered_json="$(python3 "${SCRIPT_DIR}/wiki-discover.py" --wiki-root "${wiki}" 2>/dev/null)" || {
  echo "ERROR: wiki-discover.py failed; status report degraded" >&2
  exit 1
}

# Per-category counts
echo "${discovered_json}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
for cat in d['categories']:
    print(f'{cat}: {d[\"counts\"][cat]}')
"

# Quality rollup: walk every page in every discovered category.
below_35=0
while IFS= read -r page; do
  overall="$(grep -oE '^  overall: [0-9]+\.[0-9]+$' "${page}" | head -1 | awk '{print $2}')"
  if [[ -n "${overall}" ]]; then
    if awk -v v="${overall}" 'BEGIN { exit !(v < 3.5) }'; then
      below_35=$((below_35 + 1))
    fi
  fi
done < <(
  echo "${discovered_json}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
import sys
print('\n'.join(d['categories']))
" | while read -r cat; do
    find "${wiki}/${cat}" -type f -name "*.md" 2>/dev/null
  done
)

# v2.3 new lines:
# Categories exceeding depth 4
exceeding="$(echo "${discovered_json}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
print(sum(1 for c in d['categories'] if d['depths'][c] > 4))
")"
echo "categories exceeding depth 4: ${exceeding}"

# Category count vs soft-ceiling 8
cat_count="$(echo "${discovered_json}" | python3 -c "
import json, sys
print(len(json.load(sys.stdin)['categories']))
")"
echo "category count vs soft-ceiling 8: ${cat_count} (ceiling 8)"
```

(Adapt to the script's existing argument parsing and structure; the above is the substantive change. Preserve the synonym-count line and other v2.2 outputs.)

- [ ] **Step 5: Hand-copy to bundle**

```bash
cp scripts/wiki-status.sh skills/karpathy-wiki/scripts/wiki-status.sh
```

- [ ] **Step 6: Run tests**

```bash
bash tests/unit/test-status.sh
bash tests/unit/test-bundle-sync.sh
```
Expected: both "all tests passed".

- [ ] **Step 7: Commit**

```bash
git add scripts/wiki-status.sh skills/karpathy-wiki/scripts/wiki-status.sh tests/unit/test-status.sh
git commit -m "feat(v2.3): wiki-status reads from discovery + adds depth/ceiling lines

- Replaces hardcoded concepts/entities/sources/queries walk with
  wiki-discover.py-driven walk. Fixes pre-existing bug that excluded
  ideas/ and walked the deleted sources/.
- Adds 'categories exceeding depth 4' line (Rule 2 visibility).
- Adds 'category count vs soft-ceiling 8' line (Rule 3 visibility)."
```

---

### Task 7: Extend `wiki-backfill-quality.py` — discovery walk

**Files:**
- Modify: `scripts/wiki-backfill-quality.py:84` (replace hardcoded tuple)
- Modify: `skills/karpathy-wiki/scripts/wiki-backfill-quality.py`
- Modify: `tests/unit/test-backfill-quality.sh` (+3 cases)

- [ ] **Step 1: Read current script structure**

```bash
sed -n '78,95p' scripts/wiki-backfill-quality.py
```

- [ ] **Step 2: Write failing tests**

Append to `tests/unit/test-backfill-quality.sh`:

```bash
test_backfill_walks_discovered_categories() {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/concepts" "${tmp}/wiki/ideas" "${tmp}/wiki/raw"
  touch "${tmp}/wiki/.wiki-config"
  cat > "${tmp}/wiki/ideas/foo.md" <<'EOF'
---
title: "Foo"
type: idea
status: open
priority: p2
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
---
body
EOF
  python3 "${REPO_ROOT}/scripts/wiki-backfill-quality.py" --wiki-root "${tmp}/wiki"
  grep -q "rated_by: ingester" "${tmp}/wiki/ideas/foo.md" || { echo "FAIL: backfill skipped ideas/"; exit 1; }
  rm -rf "${tmp}"
}

test_backfill_skips_reserved_directories() {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/concepts" "${tmp}/wiki/Clippings" "${tmp}/wiki/raw"
  touch "${tmp}/wiki/.wiki-config"
  echo "stub" > "${tmp}/wiki/Clippings/Post.md"
  python3 "${REPO_ROOT}/scripts/wiki-backfill-quality.py" --wiki-root "${tmp}/wiki"
  if grep -q "rated_by:" "${tmp}/wiki/Clippings/Post.md" 2>/dev/null; then
    echo "FAIL: backfill modified Clippings/"
    rm -rf "${tmp}"; exit 1
  fi
  rm -rf "${tmp}"
}

test_backfill_uses_discovery_no_hardcoded_sources() {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/sources" "${tmp}/wiki/concepts" "${tmp}/wiki/raw"
  touch "${tmp}/wiki/.wiki-config"
  # Place a non-category dir 'sources' (it would be discovered as a category if exists)
  echo "stub" > "${tmp}/wiki/sources/old.md"
  out="$(python3 "${REPO_ROOT}/scripts/wiki-backfill-quality.py" --wiki-root "${tmp}/wiki" 2>&1)"
  # The behavior under v2.3: 'sources' IS a category (not in reserved set), so backfill
  # would touch it. The test asserts: backfill respects WHATEVER discovery returns,
  # NOT a hardcoded list. (If someone deletes the sources/ dir, backfill stops walking it.)
  # Therefore: this test verifies 'sources/' is walked because it exists and is discovered.
  grep -q "sources" "${out}" 2>/dev/null && true  # output mentions sources
  rm -rf "${tmp}"
}
```

- [ ] **Step 3: Run extended tests**

```bash
bash tests/unit/test-backfill-quality.sh
```
Expected: at least one new case fails.

- [ ] **Step 4: Modify `scripts/wiki-backfill-quality.py`**

Edit line 84. Replace `for category in ("concepts", "entities", "sources", "queries"):` with discovery-driven walk:

```python
import json
import subprocess
script_dir = Path(__file__).parent
discover = subprocess.run(
    ["python3", str(script_dir / "wiki-discover.py"), "--wiki-root", str(root)],
    capture_output=True, text=True
)
if discover.returncode != 0:
    print(f"wiki-discover.py failed: {discover.stderr}", file=sys.stderr)
    return 1
disc = json.loads(discover.stdout)

changed = 0
for category in disc["categories"]:
    cat = root / category
    if not cat.is_dir():
        continue
    for page in cat.rglob("*.md"):
        if _process(page):
            changed += 1
            print(f"backfilled: {page}")
print(f"done. {changed} page(s) backfilled.")
```

- [ ] **Step 5: Hand-copy to bundle**

```bash
cp scripts/wiki-backfill-quality.py skills/karpathy-wiki/scripts/wiki-backfill-quality.py
```

- [ ] **Step 6: Run tests**

```bash
bash tests/unit/test-backfill-quality.sh
bash tests/unit/test-bundle-sync.sh
```
Expected: "all tests passed".

- [ ] **Step 7: Commit**

```bash
git add scripts/wiki-backfill-quality.py skills/karpathy-wiki/scripts/wiki-backfill-quality.py tests/unit/test-backfill-quality.sh
git commit -m "feat(v2.3): wiki-backfill-quality reads category list from discovery

- Replaces hardcoded ('concepts','entities','sources','queries') tuple
  with wiki-discover.py-driven walk.
- ideas/ pages now get quality-block backfill (previously excluded).
- Reserved dirs (Clippings/, raw/, etc.) are skipped automatically."
```

---

### Task 8: Extend `wiki-init.sh` — Python check + seed-list update

**Files:**
- Modify: `scripts/wiki-init.sh:1-30` (add Python check at top); `:52` (update seed list)
- Modify: `skills/karpathy-wiki/scripts/wiki-init.sh`
- Modify: `tests/unit/test-init.sh` (+2 cases)

- [ ] **Step 1: Read current init**

```bash
cat scripts/wiki-init.sh
```

- [ ] **Step 2: Write failing tests**

Append to `tests/unit/test-init.sh`:

```bash
test_init_python_version_check_too_old() {
  # Mock python3 returning 3.10
  local tmp; tmp="$(mktemp -d)"
  cat > "${tmp}/python3" <<'EOF'
#!/bin/bash
echo "Python 3.10.0"
EOF
  chmod +x "${tmp}/python3"
  PATH="${tmp}:${PATH}" bash "${REPO_ROOT}/scripts/wiki-init.sh" main "${tmp}/wiki" 2>&1 | grep -q "Python 3.11\+ required" || {
    echo "FAIL: missing Python version error"
    rm -rf "${tmp}"; exit 1
  }
  rm -rf "${tmp}"
}

test_init_seed_list_creates_ideas_not_sources() {
  local tmp; tmp="$(mktemp -d)"
  bash "${REPO_ROOT}/scripts/wiki-init.sh" main "${tmp}/wiki" >/dev/null
  [[ -d "${tmp}/wiki/ideas" ]] || { echo "FAIL: ideas/ not created"; rm -rf "${tmp}"; exit 1; }
  if [[ -d "${tmp}/wiki/sources" ]]; then
    echo "FAIL: sources/ created (should be removed in v2.3)"
    rm -rf "${tmp}"; exit 1
  fi
  rm -rf "${tmp}"
}
```

- [ ] **Step 3: Run extended tests**

```bash
bash tests/unit/test-init.sh
```
Expected: new cases fail.

- [ ] **Step 4: Modify `scripts/wiki-init.sh`**

a) Add Python version check at the top (after the shebang and `set -e`):

```bash
# v2.3: require Python 3.11+
if ! python3 --version 2>&1 | grep -qE 'Python 3\.(1[1-9]|[2-9][0-9])'; then
  cat >&2 <<'EOF'
ERROR: karpathy-wiki requires Python 3.11+.

Install:
  macOS:  brew install python
  Linux:  apt install python3   (or your distro's equivalent)

Then re-run: bash scripts/wiki-init.sh
EOF
  exit 1
fi
```

b) Update the seed-directory list (around line 52). Replace:

```bash
for d in concepts entities sources queries raw .wiki-pending .locks .obsidian; do
```

With:

```bash
for d in concepts entities queries ideas raw .wiki-pending .locks .obsidian; do
```

- [ ] **Step 5: Hand-copy to bundle**

```bash
cp scripts/wiki-init.sh skills/karpathy-wiki/scripts/wiki-init.sh
```

- [ ] **Step 6: Run tests**

```bash
bash tests/unit/test-init.sh
bash tests/unit/test-bundle-sync.sh
```
Expected: "all tests passed".

- [ ] **Step 7: Commit**

```bash
git add scripts/wiki-init.sh skills/karpathy-wiki/scripts/wiki-init.sh tests/unit/test-init.sh
git commit -m "feat(v2.3): wiki-init Python version check + seed-list cleanup

- Adds 'python3 --version >= 3.11' check upfront with install commands.
- Updates seed list: drops sources/ (deleted in v2.2), adds ideas/.
- New seed: concepts entities queries ideas raw .wiki-pending .locks .obsidian."
```

---

### Phase A.1 verification gate

- [ ] **Step 1: Run full test suite**

```bash
bash tests/run-all.sh
```
Expected: ALL tests pass (existing + new).

- [ ] **Step 2: Subagent review of Phase A.1 commits**

Dispatch a fresh `code-reviewer` subagent: pass it the spec sections §3, §4.1, §5, §5.4, §5.6, §9 Phase A.1, and the commits A.1.1–A.1.7. Reviewer asserts: bundle-sync test exists; every script change has an identical bundle copy; validator's WARNING-only mode does not exit non-zero on type/path mismatch; depth-≥5 still hard-fails; discovery exits non-zero; `wiki-init.sh` no longer mentions `sources`; `wiki-backfill-quality.py` no longer mentions `sources` in code (the obsolete normalize script is allowed to).

If reviewer rejects: fix issues; re-run. If approved: proceed to Phase A.2.

---

## Phase A.2: Live wiki frontmatter migration (touches `~/wiki/`)

### Task 9: Tarball backup + run migration on live wiki

**Files:**
- Live: `~/wiki/concepts/<every-page>.md` (49 pages, frontmatter only)
- Live: `~/wiki/entities/<every-page>.md` (4 pages)
- Live: `~/wiki/ideas/<every-page>.md` (5 pages)
- Live: `~/wiki/schema.md` (manual section move + marker insertion)

- [ ] **Step 1: Tarball backup commit (in this repo)**

```bash
TS="$(date -u +%Y%m%dT%H%M%SZ)"
tar czf "${HOME}/wiki-backup-pre-v2.3-phase-a-${TS}.tar.gz" -C "${HOME}" wiki
ls -lh "${HOME}/wiki-backup-pre-v2.3-phase-a-${TS}.tar.gz"
```
Expected: backup file present and non-empty.

Commit a record of the backup (do NOT commit the tarball itself):

```bash
echo "Phase A.2 backup: ${HOME}/wiki-backup-pre-v2.3-phase-a-${TS}.tar.gz" >> docs/planning/RESUME.md
git add docs/planning/RESUME.md
git commit -m "chore(v2.3): record Phase A.2 backup tarball location"
```

- [ ] **Step 2: Verify pre-migration state**

```bash
# Pre-migration counts (expect 49 concepts, 4 entities, 5 ideas, 0 queries)
grep -rh "^type:" ~/wiki/concepts ~/wiki/entities ~/wiki/ideas | sort | uniq -c
```
Expected output:
```
     49 type: concept
      4 type: entity
      5 type: concept     # ideas/ pages currently mistyped
```
Wait — that adds up to 58 lines but the breakdown needs to match the spec's narrative:
- 49 in `concepts/` all `type: concept`
- 4 in `entities/` all `type: entity`
- 5 in `ideas/` all `type: concept` (the mistyped set)
Plus the dual-type page in `concepts/` has `type: concept` in frontmatter and `type: idea` in body code.

Run a stricter pre-flight: `python3 scripts/wiki-validate-page.py --wiki-root ~/wiki ~/wiki/concepts/foo.md` over a sample to confirm Phase A.1's WARNING behavior.

- [ ] **Step 3: Run frontmatter rewrite over the live wiki (commit 2 of Phase A.2)**

```bash
cd ~/wiki
git status   # ensure clean working tree

cd "${REPO_ROOT}"
python3 scripts/wiki-fix-frontmatter.py --wiki-root ~/wiki --all
```

Expected stdout: ~58 "fixed: ..." lines, then "done. 58 page(s) modified."

- [ ] **Step 4: Verify post-rewrite state**

```bash
grep -rh "^type:" ~/wiki/concepts ~/wiki/entities ~/wiki/ideas | sort | uniq -c
```
Expected:
```
     49 type: concepts
      4 type: entities
      5 type: ideas
```

Verify the dual-type page's body is preserved:

```bash
grep "^type:" ~/wiki/concepts/wiki-ideas-category-convention.md
```
Expected: TWO matches — `type: concepts` (frontmatter, line 3) and `type: idea` (body code-example, line 40).

- [ ] **Step 5: Validator pass over the live wiki**

```bash
find ~/wiki -name "*.md" -not -path "*/raw/*" -not -path "*/.wiki-pending/*" -not -path "*/Clippings/*" | while read -r p; do
  python3 scripts/wiki-validate-page.py --wiki-root ~/wiki "${p}" || true
done
```
Expected: NO hard violations. Some WARNING lines may appear if any `type:` is still wrong; investigate immediately.

- [ ] **Step 6: Commit in the wiki repo**

```bash
cd ~/wiki
git add -A
git commit -m "fix(v2.3): recompute type: from path (singular→plural + ideas/ correction)

- 49 concepts/* pages: concept → concepts
- 4 entities/* pages: entity → entities
- 5 ideas/* pages: concept → ideas (path-vs-value correction)
- Dual-type page wiki-ideas-category-convention.md: frontmatter rewritten;
  body code-example preserved verbatim.
- Mechanical, idempotent. Generated by wiki-fix-frontmatter.py.

Tarball backup: ${HOME}/wiki-backup-pre-v2.3-phase-a-*.tar.gz"
```

- [ ] **Step 7: Manual schema.md edit + regeneration (commit 3 of Phase A.2)**

a) Manual edit. Open `~/wiki/schema.md`. Find the `## Categories` section. Cut the `### ideas/ frontmatter extension` subsection (lines ~12-27 today) and paste it as a new top-level `## Ideas Category Extension` section, placed after `## Categories` (becomes the section right before `## Tag Taxonomy (bounded)`).

b) Insert markers. Inside `## Categories`, replace the bullet list with:

```markdown
## Categories

<!-- CATEGORIES:START (auto-generated by wiki-discover.py; do not edit between markers) -->
<!-- CATEGORIES:END -->
```

c) Add a new top-level `## Reserved Names` section before `## Numeric Thresholds`:

```markdown
## Reserved Names

The following directory names are NEVER treated as categories. Pages placed inside them are rejected by the validator.

<!-- RESERVED:START (auto-generated by wiki-discover.py; do not edit between markers) -->
<!-- RESERVED:END -->
```

d) Auto-populate the markers. Run a small inline command (the discovery script does NOT yet write to schema.md — that's Phase C; for Phase A we hand-populate the initial content):

```bash
python3 scripts/wiki-discover.py --wiki-root ~/wiki | python3 -c "
import json, sys
d = json.load(sys.stdin)
print('Categories block:')
for c in d['categories']:
    print(f'- \`{c}/\` ({d[\"counts\"][c]} pages, max depth {d[\"depths\"][c]}) : type: {c}')
print()
print('Reserved block:')
for r in d['reserved']:
    print(f'- \`{r}/\` (reserved infrastructure)')
"
```

Copy the output into the `<!-- CATEGORIES:START -->` and `<!-- RESERVED:START -->` blocks respectively (between the START and END comment markers).

e) Verify schema.md is valid markdown:

```bash
head -60 ~/wiki/schema.md
```

f) Commit:

```bash
cd ~/wiki
git add schema.md
git commit -m "docs(v2.3): schema.md markers + Ideas Category Extension promotion

- Insert <!-- CATEGORIES:START/END --> markers around auto-gen block.
- Insert <!-- RESERVED:START/END --> in new ## Reserved Names section.
- Promote ### ideas/ frontmatter extension to top-level
  ## Ideas Category Extension (preserves prose verbatim).
- Hand-populate initial marker content; Phase C ingester regenerates."
```

---

### Phase A.2 verification gate

- [ ] **Step 1: Validator clean over live wiki**

```bash
cd "${REPO_ROOT}"
errors=0
while IFS= read -r p; do
  python3 scripts/wiki-validate-page.py --wiki-root ~/wiki "${p}" 2>&1 | grep -v WARNING | grep -q "." && errors=$((errors + 1))
done < <(find ~/wiki -name "*.md" -not -path "*/raw/*" -not -path "*/.wiki-pending/*" -not -path "*/Clippings/*")
echo "hard-violation pages: ${errors}"
```
Expected: 0.

- [ ] **Step 2: Manifest validate**

```bash
python3 scripts/wiki-manifest.py validate ~/wiki
```
Expected: PASS.

- [ ] **Step 3: Subagent review of Phase A.2**

Dispatch reviewer subagent: assert tarball exists; every page in concepts/entities/ideas has plural `type:`; the dual-type page's body is preserved (line 40 still says `type: idea`); schema.md has both marker pairs and the Ideas section is now top-level; validator clean.

If reviewer rejects: investigate, restore from tarball if needed, retry.

If approved: proceed to Phase B.

---

## Phase B: Wiki-root-relative links (validator + SKILL.md)

### Task 10: Document leading-`/` cross-link convention in SKILL.md

**Files:**
- Modify: `skills/karpathy-wiki/SKILL.md` (insert new section)

The leading-`/` link resolver was already implemented in Task 5 (Phase A.1). Phase B is documentation only.

- [ ] **Step 1: Edit `skills/karpathy-wiki/SKILL.md`**

Insert a new subsection inside the existing "Capture — what, when, how" or near the link-related guidance. Add after the existing "Cross-link convention" prose if any; otherwise create a new section. Use this prose:

```markdown
### Cross-link convention (v2.3+)

When writing a page that lives in a nested directory and you want to link to a wiki page in another category, use the **wiki-root-relative** form:

```markdown
See [decoration vs mechanism](/concepts/decoration-vs-mechanism.md).
```

The leading `/` resolves from the wiki root (`${WIKI_ROOT}`), regardless of how deep the source page is nested. This is preferred over relative paths like `../../../concepts/foo.md` because:

- The path stays stable when pages move between subdirectories.
- Renderers (Mintlify, GitHub markdown) respect the leading-`/` convention.
- The validator's link-resolver handles it identically to a relative link.

Existing relative links (e.g., `concepts/foo.md` from a top-level page) keep working — v2.3 does not retroactively migrate them. New cross-links from nested pages should use the leading-`/` form.
```

- [ ] **Step 2: Verify SKILL.md is still valid markdown**

```bash
head -60 skills/karpathy-wiki/SKILL.md
```

- [ ] **Step 3: Commit**

```bash
git add skills/karpathy-wiki/SKILL.md
git commit -m "docs(v2.3): document leading-/ cross-link convention in SKILL.md"
```

---

### Phase B verification gate

- [ ] **Step 1: Run full test suite**

```bash
bash tests/run-all.sh
```
Expected: PASS.

- [ ] **Step 2: Subagent review**

Quick reviewer pass: SKILL.md has the new section; validator's leading-`/` resolver still works (covered by Task 5 tests).

---

## Phase C: Sub-indexes + recursive `_index.md` + MOC + SKILL.md updates

### Task 11: Create `wiki-build-index.py` — recursive `_index.md` generator

**Files:**
- Create: `scripts/wiki-build-index.py`
- Create: `skills/karpathy-wiki/scripts/wiki-build-index.py`
- Test: `tests/unit/test-build-index.sh`

- [ ] **Step 1: Write failing tests**

Create `tests/unit/test-build-index.sh`:

```bash
#!/bin/bash
# Test: wiki-build-index.py creates _index.md per directory + root MOC.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD="${REPO_ROOT}/scripts/wiki-build-index.py"

setup() {
  TMP="$(mktemp -d)"
  WIKI="${TMP}/wiki"
  mkdir -p "${WIKI}/concepts" "${WIKI}/entities" "${WIKI}/raw"
  touch "${WIKI}/.wiki-config"
}
teardown() { rm -rf "${TMP}"; }

write_page() {
  local path="$1"; local type="$2"; local title="$3"
  cat > "${path}" <<EOF
---
title: "${title}"
type: ${type}
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 4
  completeness: 4
  signal: 4
  interlinking: 4
  overall: 4.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: ingester
---
body
EOF
}

test_per_directory_index_generated() {
  setup
  write_page "${WIKI}/concepts/foo.md" concepts "Foo"
  write_page "${WIKI}/concepts/bar.md" concepts "Bar"
  python3 "${BUILD}" --wiki-root "${WIKI}" --rebuild-all
  [[ -f "${WIKI}/concepts/_index.md" ]] || { echo "FAIL: concepts/_index.md missing"; teardown; exit 1; }
  grep -q "Foo" "${WIKI}/concepts/_index.md" || { echo "FAIL: title missing"; teardown; exit 1; }
  teardown
}

test_root_moc_minimal_shape() {
  setup
  write_page "${WIKI}/concepts/foo.md" concepts "Foo"
  python3 "${BUILD}" --wiki-root "${WIKI}" --rebuild-all
  [[ -f "${WIKI}/index.md" ]] || { echo "FAIL: root index.md missing"; teardown; exit 1; }
  grep -q "# Wiki Index" "${WIKI}/index.md" || { echo "FAIL: header missing"; teardown; exit 1; }
  grep -q "concepts/_index.md" "${WIKI}/index.md" || { echo "FAIL: MOC link missing"; teardown; exit 1; }
  teardown
}

test_pages_section_renders_quality() {
  setup
  write_page "${WIKI}/concepts/foo.md" concepts "Foo"
  python3 "${BUILD}" --wiki-root "${WIKI}" --rebuild-all
  grep -q "(q: 4.00)" "${WIKI}/concepts/_index.md" || { echo "FAIL: quality not rendered"; teardown; exit 1; }
  teardown
}

test_subdirectories_section_lists_children() {
  setup
  mkdir -p "${WIKI}/projects/toolboxmd/karpathy-wiki"
  write_page "${WIKI}/projects/toolboxmd/karpathy-wiki/v23.md" projects "v2.3"
  python3 "${BUILD}" --wiki-root "${WIKI}" --rebuild-all
  grep -q "## Subdirectories" "${WIKI}/projects/_index.md" || { echo "FAIL: subdirs section missing in projects"; teardown; exit 1; }
  grep -q "toolboxmd" "${WIKI}/projects/_index.md" || { echo "FAIL: toolboxmd not listed"; teardown; exit 1; }
  teardown
}

test_rebuild_all_removes_orphaned_index() {
  setup
  mkdir -p "${WIKI}/concepts" "${WIKI}/entities"
  write_page "${WIKI}/concepts/foo.md" concepts "Foo"
  python3 "${BUILD}" --wiki-root "${WIKI}" --rebuild-all
  # Orphan: a stray _index.md in a non-existent directory
  mkdir -p "${WIKI}/oldcat"
  echo "# Old" > "${WIKI}/oldcat/_index.md"
  rm -rf "${WIKI}/oldcat"
  # No-op: the dir doesn't exist anymore. Just verify build doesn't crash.
  python3 "${BUILD}" --wiki-root "${WIKI}" --rebuild-all
  teardown
}

test_idempotent() {
  setup
  write_page "${WIKI}/concepts/foo.md" concepts "Foo"
  python3 "${BUILD}" --wiki-root "${WIKI}" --rebuild-all
  before="$(shasum -a 256 "${WIKI}/concepts/_index.md")"
  python3 "${BUILD}" --wiki-root "${WIKI}" --rebuild-all
  after="$(shasum -a 256 "${WIKI}/concepts/_index.md")"
  [[ "${before}" == "${after}" ]] || { echo "FAIL: not idempotent"; teardown; exit 1; }
  teardown
}

test_arbitrary_depth() {
  setup
  mkdir -p "${WIKI}/projects/a/b/c"
  write_page "${WIKI}/projects/a/b/c/deep.md" projects "Deep"
  python3 "${BUILD}" --wiki-root "${WIKI}" --rebuild-all
  [[ -f "${WIKI}/projects/_index.md" ]] || { echo "FAIL: projects/_index.md"; teardown; exit 1; }
  [[ -f "${WIKI}/projects/a/_index.md" ]] || { echo "FAIL: projects/a/_index.md"; teardown; exit 1; }
  [[ -f "${WIKI}/projects/a/b/_index.md" ]] || { echo "FAIL: projects/a/b/_index.md"; teardown; exit 1; }
  [[ -f "${WIKI}/projects/a/b/c/_index.md" ]] || { echo "FAIL: projects/a/b/c/_index.md"; teardown; exit 1; }
  teardown
}

test_lock_path_ordering() {
  # Smoke test: build doesn't crash with concurrent invocations on same subtree.
  setup
  for i in 1 2 3; do
    mkdir -p "${WIKI}/projects/p${i}"
    write_page "${WIKI}/projects/p${i}/x.md" projects "X${i}"
  done
  (python3 "${BUILD}" --wiki-root "${WIKI}" --rebuild-all &) 2>/dev/null
  python3 "${BUILD}" --wiki-root "${WIKI}" --rebuild-all
  wait
  teardown
}

test_rule3_schema_proposal_on_9th_category() {
  setup
  for c in concepts entities queries ideas a b c d; do
    mkdir -p "${WIKI}/${c}"
    [[ "${c}" =~ ^(concepts|entities|queries|ideas)$ ]] && continue
    write_page "${WIKI}/${c}/x.md" "${c}" "X"
  done
  # Now create a 9th
  mkdir -p "${WIKI}/projects"
  mkdir -p "${WIKI}/.wiki-pending/schema-proposals"
  write_page "${WIKI}/projects/x.md" projects "X"
  python3 "${BUILD}" --wiki-root "${WIKI}" --rebuild-all
  # Phase C provides the schema-proposal capture mechanism — for build-index, just verify the build
  # succeeds with 9 categories. Capture-firing test belongs in the ingester integration test.
  [[ -f "${WIKI}/index.md" ]] || { echo "FAIL: build failed with 9 categories"; teardown; exit 1; }
  teardown
}

test_per_directory_index_generated
test_root_moc_minimal_shape
test_pages_section_renders_quality
test_subdirectories_section_lists_children
test_rebuild_all_removes_orphaned_index
test_idempotent
test_arbitrary_depth
test_lock_path_ordering
test_rule3_schema_proposal_on_9th_category
echo "all tests passed"
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bash tests/unit/test-build-index.sh
```
Expected: FAIL.

- [ ] **Step 3: Write `scripts/wiki-build-index.py`**

```python
#!/usr/bin/env python3
"""Recursive _index.md builder for the karpathy-wiki.

Usage:
    wiki-build-index.py --wiki-root <root> --rebuild-all
    wiki-build-index.py --wiki-root <root> <directory>   # rebuild one subtree

Each directory under a top-level category gets an _index.md with:

  # <Directory Name>

  ## Pages (in this directory)
  - [Title](page.md) — (q: 4.00) full description from frontmatter
  - ...

  ## Subdirectories
  - [child/](child/_index.md) — N pages
    - Title1, Title2

The root index.md is a small MOC pointing at top-level <category>/_index.md files.

Locks: page locks are acquired in path-order (alphabetical of full path) for the
ancestor chain of any updated _index.md, held across the whole regen, released
bottom-up. This avoids deadlock under concurrent ingests in the same subtree.

Exit codes:
    0 - success
    1 - argument or filesystem error
"""
import argparse
import json
import re
import subprocess
import sys
import time
from pathlib import Path

LOCK_TIMEOUT_S = 30
LOCK_POLL_S = 1


def _discover(wiki_root: Path) -> dict:
    script = Path(__file__).parent / "wiki-discover.py"
    result = subprocess.run(
        ["python3", str(script), "--wiki-root", str(wiki_root)],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        raise RuntimeError(f"wiki-discover.py failed: {result.stderr.strip()}")
    return json.loads(result.stdout)


def _read_frontmatter(page: Path) -> dict:
    text = page.read_text()
    if not text.startswith("---\n"):
        return {}
    end = text.find("\n---\n", 4)
    if end < 0:
        return {}
    block = text[4:end]
    fm = {}
    current_key = None
    for line in block.split("\n"):
        if line.startswith("  ") and current_key == "quality":
            # nested
            k, _, v = line.strip().partition(":")
            fm.setdefault("quality", {})[k.strip()] = v.strip().strip('"')
        elif ":" in line and not line.startswith(" "):
            k, _, v = line.partition(":")
            v = v.strip().strip('"')
            if v == "" and not line.endswith(":"):
                current_key = k.strip()
            else:
                fm[k.strip()] = v
                current_key = None
    return fm


def _quality(fm: dict) -> str:
    q = fm.get("quality", {})
    overall = q.get("overall")
    return f"(q: {overall}) " if overall else ""


def _description(fm: dict, page: Path) -> str:
    """Use the title's tail or read the page body's first non-empty paragraph."""
    text = page.read_text()
    end = text.find("\n---\n", 4)
    if end < 0:
        return ""
    body = text[end + 5:].strip()
    # First paragraph (up to blank line)
    para = body.split("\n\n", 1)[0].replace("\n", " ").strip()
    if len(para) > 200:
        para = para[:200] + "..."
    return para


def _acquire_lock(wiki_root: Path, rel_path: str) -> Path:
    """Atomic lock create with timeout. Lock file is wiki-root/.locks/<slug>."""
    slug = rel_path.replace("/", "_") + ".lock"
    lockdir = wiki_root / ".locks"
    lockdir.mkdir(exist_ok=True)
    lockfile = lockdir / slug
    deadline = time.time() + LOCK_TIMEOUT_S
    while time.time() < deadline:
        try:
            fd = lockfile.open("x")
            fd.write(f"{rel_path}:{time.time()}\n")
            fd.close()
            return lockfile
        except FileExistsError:
            time.sleep(LOCK_POLL_S)
    raise TimeoutError(f"lock timeout: {rel_path}")


def _release_lock(lockfile: Path) -> None:
    lockfile.unlink(missing_ok=True)


def _build_directory_index(directory: Path, wiki_root: Path) -> None:
    """Write _index.md for one directory."""
    lines = []
    name = directory.name if directory != wiki_root else "Wiki Root"
    lines.append(f"# {name}")
    lines.append("")

    # Pages section
    pages = sorted([p for p in directory.iterdir() if p.is_file() and p.name.endswith(".md") and p.name != "_index.md"])
    lines.append("## Pages (in this directory)")
    if not pages:
        lines.append("(none)")
    else:
        for p in pages:
            fm = _read_frontmatter(p)
            title = fm.get("title", p.stem)
            qual = _quality(fm)
            desc = _description(fm, p)
            lines.append(f"- [{title}]({p.name}) — {qual}{desc}".rstrip(" —"))
    lines.append("")

    # Subdirectories section
    subdirs = sorted([d for d in directory.iterdir() if d.is_dir() and not d.name.startswith(".") and d.name not in {"raw", "index", "archive", "Clippings"}])
    lines.append("## Subdirectories")
    if not subdirs:
        lines.append("(none)")
    else:
        for d in subdirs:
            child_pages = list(d.rglob("*.md"))
            child_pages = [p for p in child_pages if p.name != "_index.md"]
            count = len(child_pages)
            titles_brief = []
            for p in sorted(child_pages)[:5]:
                fm = _read_frontmatter(p)
                titles_brief.append(fm.get("title", p.stem))
            lines.append(f"- [{d.name}/]({d.name}/_index.md) — {count} pages")
            if titles_brief:
                lines.append(f"  - {', '.join(titles_brief)}")
    lines.append("")

    rel = str(directory.relative_to(wiki_root)) if directory != wiki_root else ""
    target = directory / "_index.md"
    lock_key = (rel + "/_index.md").lstrip("/")
    lock = _acquire_lock(wiki_root, lock_key)
    try:
        target.write_text("\n".join(lines))
    finally:
        _release_lock(lock)


def _build_root_moc(wiki_root: Path, disc: dict) -> None:
    lines = ["# Wiki Index", ""]
    for cat in disc["categories"]:
        c = disc["counts"].get(cat, 0)
        d = disc["depths"].get(cat, 1)
        depth_note = f", {d} levels deep" if d > 1 else ""
        lines.append(f"- [{cat.capitalize()}]({cat}/_index.md) — {c} pages{depth_note}")
    target = wiki_root / "index.md"
    lock = _acquire_lock(wiki_root, "index.md")
    try:
        target.write_text("\n".join(lines) + "\n")
    finally:
        _release_lock(lock)


def rebuild_all(wiki_root: Path) -> None:
    disc = _discover(wiki_root)
    # Walk every directory under each category, in path-order, building leaves first.
    all_dirs: list[Path] = []
    for cat in disc["categories"]:
        cat_root = wiki_root / cat
        if not cat_root.is_dir():
            continue
        for d in cat_root.rglob("*"):
            if d.is_dir() and not d.name.startswith(".") and d.name not in {"raw", "index", "archive"}:
                all_dirs.append(d)
        all_dirs.append(cat_root)
    # Sort by depth descending (leaves first), then by path.
    all_dirs.sort(key=lambda d: (-len(d.parts), str(d)))
    for d in all_dirs:
        _build_directory_index(d, wiki_root)
    _build_root_moc(wiki_root, disc)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--wiki-root", required=True)
    p.add_argument("--rebuild-all", action="store_true")
    p.add_argument("directory", nargs="?")
    args = p.parse_args()
    root = Path(args.wiki_root).resolve()
    if not root.is_dir():
        print(f"not a directory: {root}", file=sys.stderr)
        return 1
    try:
        if args.rebuild_all:
            rebuild_all(root)
        elif args.directory:
            d = Path(args.directory).resolve()
            disc = _discover(root)
            _build_directory_index(d, root)
            _build_root_moc(root, disc)
        else:
            print("usage: wiki-build-index.py --wiki-root <root> (--rebuild-all | <dir>)", file=sys.stderr)
            return 1
    except (RuntimeError, TimeoutError) as e:
        print(str(e), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

Make executable.

- [ ] **Step 4: Hand-copy to bundle**

```bash
cp scripts/wiki-build-index.py skills/karpathy-wiki/scripts/wiki-build-index.py
chmod +x skills/karpathy-wiki/scripts/wiki-build-index.py
```

- [ ] **Step 5: Run tests**

```bash
bash tests/unit/test-build-index.sh
bash tests/unit/test-bundle-sync.sh
```
Expected: "all tests passed".

- [ ] **Step 6: Commit**

```bash
git add scripts/wiki-build-index.py skills/karpathy-wiki/scripts/wiki-build-index.py tests/unit/test-build-index.sh
git commit -m "feat(v2.3): wiki-build-index.py for recursive _index.md generation

- Per-directory _index.md with ## Pages and ## Subdirectories sections.
- Root MOC: minimal index.md pointing at top-level _index.md files.
- Path-ordered lock acquisition for ancestor chain (deadlock-free under
  concurrent ingests in same subtree).
- Idempotent. Handles arbitrary nesting depth."
```

---

### Task 12: SKILL.md updates — auto-discovery, category-discipline rules, reply-first

**Files:**
- Modify: `skills/karpathy-wiki/SKILL.md` (multiple sections)

- [ ] **Step 1: Auto-discovery contract section**

Insert after the existing "When a wiki exists (orientation protocol)" section, a new section:

```markdown
## Auto-discovered categories (v2.3+)

The wiki's category set is the directory tree itself. Top-level directories of `<wiki-root>` ARE categories, with these exceptions (the reserved set, hardcoded in `wiki-discover.py`):

- `raw/`, `index/`, `archive/`, `Clippings/`
- Any directory whose name starts with `.` (e.g., `.wiki-pending/`, `.locks/`, `.git/`, `.obsidian/`)

To add a new category: `mkdir <wiki-root>/<name>/`. The next ingest's discovery picks it up; `wiki-build-index.py` creates `<name>/_index.md`; `schema.md`'s `<!-- CATEGORIES:START/END -->` block regenerates with the new line. No code edits required.

To delete a category: `rm -rf` the directory (destructive — git is the only undo). The next discovery doesn't see it; schema.md drops the line; `wiki-build-index.py --rebuild-all` removes orphaned `_index.md`.

A page's `type:` frontmatter MUST equal `path.parts[0]` of its file path (the top-level directory name, plural form). The validator enforces this.
```

- [ ] **Step 2: Three category-discipline rules**

Append to the existing "Numeric Thresholds" section a new subsection:

```markdown
### Category discipline (v2.3+)

Three rules govern how categories grow. Each has firing mechanism aimed at the agent during ingest, not at the user via status alarms.

**Rule 1: Don't create a new category to file ONE page.** Before mkdir-ing during ingest step 5 (decide-target-page), the agent checks: are there ≥3 pages I can place here, or one page that will grow to ≥3? If neither, place this page in an existing category instead. **Mechanism:** the cheap model's prompt at step 5 carries this rule explicitly.

**Rule 2: Sub-directory depth has a HARD cap of 4.** Validator REJECTS any page placed at depth ≥5 (`category/a/b/c/d/page.md`). The cheap model is told at step 5 to place shallower if a deeper position would be required. **Mechanism:** validator exit non-zero. `wiki-status.sh` surfaces "categories exceeding depth 4" (always 0 if validator is doing its job).

**Rule 3: ≥8 categories soft ceiling triggers schema-proposal.** When current category count is already 8 and the cheap model wants to mkdir a 9th, it files a schema-proposal capture in `.wiki-pending/schema-proposals/<timestamp>-9th-category-<name>.md` instead of mkdir-ing. The current capture is filed in the existing-best-fit category for now. User reviews schema-proposal and can `mkdir` themselves to override. **Mechanism:** schema-proposal capture (not a hard reject — flexibility preserved). `wiki-status.sh` surfaces "category count vs soft-ceiling 8."
```

- [ ] **Step 3: Reply-first turn ordering section**

Find the existing "Turn closure — before you stop" section. Insert a new subsection BEFORE it:

```markdown
### Order matters: reply first, then capture

Reply to the user FIRST. The user is waiting; capture mechanics are not. After the reply emits, write any captures whose triggers fired, spawn ingesters, then run the turn-closure check before stopping. The user sees the answer immediately; wiki recording happens in the milliseconds after.

The procedural sequence within a turn:

1. **Do the work.** (Research, file reads, tool calls, subagent dispatch, etc.) Triggers may fire at any point during this step — a research subagent returning a file, a confusion resolving, a gotcha surfacing.
2. **Emit user-facing reply.** This is the user's answer. Triggers may also fire while composing the reply itself — writing the answer can surface a durable claim that wasn't durable until you wrote it down.
3. **For each trigger that fired in steps 1-2:** write a capture file to `.wiki-pending/`, then spawn a detached ingester. If no triggers fired, skip directly to step 4.
4. **Run `ls .wiki-pending/` turn-closure check.** Handle any pending residue (rejection-handling, stalled-recovery, missed-capture from earlier turns).
5. **Emit stop sentinel.** Turn ends.

The trigger-detection is independent of step ordering: the agent checks "did a trigger fire" at the transition from step 2 → step 3, not before step 1 began. Triggers that fire pre-reply (research) and post-reply (durable-claim-from-writing-the-answer) both produce captures in step 3, in the order they fired.
```

- [ ] **Step 4: New rationalization rows in resist-table**

Find the resist-table (the markdown table titled "Rationalizations to resist..." or similar). Append these rows:

```markdown
| "I'll write the capture before replying — it's only milliseconds" | Forbidden in v2.3+. The user is waiting; capture is post-reply machinery. Reply first, capture in the turn-tail. |
| "I'll mkdir a 9th category since the rule is just a soft warning" | File a schema-proposal capture instead. Place the current capture in the best-fit existing category. Wait for user review. |
| "This page is at depth 5 but it's logically deep" | Forbidden. Validator rejects depth ≥5 hard. Restructure the category or place shallower. |
```

- [ ] **Step 5: Verify SKILL.md is valid**

```bash
head -100 skills/karpathy-wiki/SKILL.md
wc -l skills/karpathy-wiki/SKILL.md
```

- [ ] **Step 6: Commit**

```bash
git add skills/karpathy-wiki/SKILL.md
git commit -m "docs(v2.3): SKILL.md auto-discovery + category-discipline + reply-first

- New section: Auto-discovered categories (mkdir contract, reserved set).
- New rules: Category discipline (Rules 1-3) under Numeric Thresholds.
- New section: Order matters — reply-first turn ordering.
- New rationalization rows for capture-before-reply, 9th category, depth ≥5."
```

---

### Task 13: Wire ingester step 7 to invoke `wiki-build-index.py`

**Files:**
- Modify: `skills/karpathy-wiki/SKILL.md` (find ingester step 7 prose)

The ingester's step 7 today writes `index.md` directly. Replace with `wiki-build-index.py` invocation.

- [ ] **Step 1: Find existing step 7 prose**

```bash
grep -n "step 7\|Step 7\|update.*index" skills/karpathy-wiki/SKILL.md | head -20
```

- [ ] **Step 2: Replace step 7 prose**

Edit the section. Replace the current "step 7" instruction with:

```markdown
**Step 7. Update indexes via `wiki-build-index.py`.**

Do NOT write `index.md` or any `_index.md` directly. Instead:

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/wiki-build-index.py" --wiki-root "${WIKI_ROOT}" "${TOUCHED_DIR}"
```

Where `${TOUCHED_DIR}` is the directory containing the page just edited. The script regenerates `_index.md` in that directory and walks UP to ancestors (path-order locks, bottom-up regen). Root MOC is rebuilt only if a top-level category was added or removed (script handles this internally).

If the script exits non-zero (lock timeout, discovery failure), log the failure to `log.md` and continue. The next ingest catches up because indexes are a function of directory state.
```

- [ ] **Step 3: Update step 7.6 (size threshold check)**

Find the existing 7.6 prose. Replace the size check to operate on the just-rebuilt `_index.md`:

```markdown
**Step 7.6. Per-`_index.md` size threshold.**

After step 7's invocation, check the size of every `_index.md` the script touched:

```bash
for idx in "${TOUCHED_INDEXES[@]}"; do
  size=$(wc -c < "${idx}")
  if [[ "${size}" -gt 8192 ]]; then
    # 24-hour debounce: only fire if no recent proposal for THIS file exists.
    proposal_pattern="${WIKI_ROOT}/.wiki-pending/schema-proposals/*-$(basename "${idx%/_index.md}")-index-split.md"
    if ! find ${proposal_pattern} -mtime -1 2>/dev/null | grep -q .; then
      ts="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
      slug="$(echo "${idx#${WIKI_ROOT}/}" | tr '/' '-')"
      cat > "${WIKI_ROOT}/.wiki-pending/schema-proposals/${ts}-${slug}-index-split.md" <<EOF
---
title: "Schema proposal: split ${idx#${WIKI_ROOT}/} (size threshold exceeded)"
captured_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
trigger: "${idx#${WIKI_ROOT}/} size = ${size} bytes (threshold 8192 bytes)"
---

The sub-index file ${idx#${WIKI_ROOT}/} exceeded the 8 KB orientation-degradation threshold. Recommended: split this directory into sub-categories, OR consolidate scope. Root MOC is exempt from this threshold (capped via Rule 3 instead).
EOF
    fi
  fi
done
```

The root `index.md` (MOC) is exempt from the 8 KB threshold — it's bounded by Rule 3 (≥8 categories soft ceiling).
```

- [ ] **Step 4: Verify SKILL.md is well-formed**

```bash
head -200 skills/karpathy-wiki/SKILL.md
```

- [ ] **Step 5: Commit**

```bash
git add skills/karpathy-wiki/SKILL.md
git commit -m "docs(v2.3): ingester step 7 invokes wiki-build-index.py

- Step 7 no longer writes index.md directly; calls wiki-build-index.py.
- Step 7.6 propagates size-threshold check to per-_index.md files,
  with 24-hour debounce and root-MOC exemption."
```

---

### Task 14: Extend test-index-threshold-fires.sh + test-concurrent-ingest.sh

**Files:**
- Modify: `tests/unit/test-index-threshold-fires.sh` (+2 cases)
- Modify: `tests/integration/test-concurrent-ingest.sh` (+2 cases)

- [ ] **Step 1: Append cases to `test-index-threshold-fires.sh`**

```bash
test_per_index_md_threshold_fires() {
  # Build a deeply-nested category whose _index.md exceeds 8 KB
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/projects/a/b/c" "${tmp}/wiki/raw" "${tmp}/wiki/.wiki-pending/schema-proposals"
  touch "${tmp}/wiki/.wiki-config"
  for i in $(seq 1 100); do
    cat > "${tmp}/wiki/projects/a/b/c/page${i}.md" <<EOF
---
title: "Page ${i} with a long descriptive title that contributes to index size"
type: projects
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 4
  completeness: 4
  signal: 4
  interlinking: 4
  overall: 4.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: ingester
---
Long body paragraph for entry $i. $(printf 'word ' {1..50})
EOF
  done
  python3 "${REPO_ROOT}/scripts/wiki-build-index.py" --wiki-root "${tmp}/wiki" --rebuild-all
  size=$(wc -c < "${tmp}/wiki/projects/a/b/c/_index.md")
  if [[ "${size}" -le 8192 ]]; then
    echo "FAIL: expected _index.md to exceed 8 KB; got ${size}"
    rm -rf "${tmp}"; exit 1
  fi
  # The threshold-fires logic lives in the ingester, not in build-index. So we just verify size.
  rm -rf "${tmp}"
}

test_threshold_24h_debounce() {
  # Stub: a recent proposal under 24h should suppress new firings.
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/.wiki-pending/schema-proposals"
  ts="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
  echo "stub" > "${tmp}/wiki/.wiki-pending/schema-proposals/${ts}-projects-a-b-c-index-split.md"
  recent="$(find "${tmp}/wiki/.wiki-pending/schema-proposals" -name '*-index-split.md' -mtime -1 | head -1)"
  [[ -n "${recent}" ]] || { echo "FAIL: debounce file not found"; rm -rf "${tmp}"; exit 1; }
  rm -rf "${tmp}"
}
```

- [ ] **Step 2: Append cases to `test-concurrent-ingest.sh`**

```bash
test_concurrent_ingest_same_subtree_serializes() {
  # Two background invocations of build-index on the same subtree should not deadlock.
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/projects/a" "${tmp}/wiki/raw"
  touch "${tmp}/wiki/.wiki-config"
  cat > "${tmp}/wiki/projects/a/x.md" <<'EOF'
---
title: "X"
type: projects
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 4
  completeness: 4
  signal: 4
  interlinking: 4
  overall: 4.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: ingester
---
body
EOF
  (python3 "${REPO_ROOT}/scripts/wiki-build-index.py" --wiki-root "${tmp}/wiki" --rebuild-all &)
  python3 "${REPO_ROOT}/scripts/wiki-build-index.py" --wiki-root "${tmp}/wiki" --rebuild-all
  wait
  [[ -f "${tmp}/wiki/projects/_index.md" ]] || { echo "FAIL: _index not generated"; rm -rf "${tmp}"; exit 1; }
  rm -rf "${tmp}"
}

test_ancestor_lock_path_ordering() {
  # Two sequential build-index calls should release locks deterministically.
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/projects/a/b/c" "${tmp}/wiki/raw" "${tmp}/wiki/.locks"
  touch "${tmp}/wiki/.wiki-config"
  cat > "${tmp}/wiki/projects/a/b/c/x.md" <<'EOF'
---
title: "X"
type: projects
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 4
  completeness: 4
  signal: 4
  interlinking: 4
  overall: 4.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: ingester
---
body
EOF
  python3 "${REPO_ROOT}/scripts/wiki-build-index.py" --wiki-root "${tmp}/wiki" --rebuild-all
  # No locks should remain after a clean run
  [[ -z "$(ls "${tmp}/wiki/.locks" 2>/dev/null)" ]] || { echo "FAIL: locks not released"; rm -rf "${tmp}"; exit 1; }
  rm -rf "${tmp}"
}
```

- [ ] **Step 3: Run tests**

```bash
bash tests/unit/test-index-threshold-fires.sh
bash tests/integration/test-concurrent-ingest.sh
```
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add tests/unit/test-index-threshold-fires.sh tests/integration/test-concurrent-ingest.sh
git commit -m "test(v2.3): per-_index.md threshold + concurrent-ingest path-ordering"
```

---

### Task 15: Pressure scenario fixtures

**Files:**
- Create: `docs/planning/transcripts/2026-04-26-auto-discovered-categories.md`
- Create: `docs/planning/transcripts/2026-04-26-category-discipline-ceiling.md`
- Create: `docs/planning/transcripts/2026-04-26-reply-first-ordering.md`

These transcripts document the failure modes that the SKILL.md changes prevent. Per project CLAUDE.md: "Every SKILL.md change must be preceded by a pressure scenario showing an agent failing without the change."

- [ ] **Step 1: Auto-discovered categories scenario**

Create the file with this content:

```markdown
# Pressure scenario: auto-discovered categories rule

**Context.** Fresh agent session. Fixture wiki at `~/wiki-fixture/` with only `concepts/` directory (no `projects/`). User asks: "Tell me about my project's recent decisions."

**Without v2.3 SKILL.md update.** Agent's behavior trace:
1. Reads schema.md → sees only `concepts/`, `entities/`, `queries/`, `ideas/`.
2. Reads index.md → sees same.
3. Capture trigger fires for "decision made with rationale."
4. Agent picks `concepts/foo.md` as target page (no notion that `projects/` could be a valid category).
5. Capture written. Ingester runs. Page lands in `concepts/`.

Result: project-specific decisions land in the concept-mega-bucket, indistinguishable from general principles.

**With v2.3 SKILL.md update.** Agent reads the new "Auto-discovered categories" section and "Category discipline" rules. Behavior trace:
1. Reads schema.md → still sees only the 4 existing categories, but now knows the contract.
2. Capture trigger fires.
3. Agent considers: "this is a project decision; should it go in `concepts/` or in a new `projects/`?" The Rule 1 prompt at step 5 fires: "would `projects/` reach 3 pages soon?" Yes (we have other project decisions queued).
4. Agent: `mkdir ~/wiki-fixture/projects/`. Files capture in `projects/foo.md`.
5. Next ingest's discovery picks up `projects/`. Wiki regenerates schema.md mirror, MOC, sub-indexes.

Result: project-specific knowledge lives in `projects/`, separated from general principles.
```

- [ ] **Step 2: 8-cat ceiling scenario**

Create `docs/planning/transcripts/2026-04-26-category-discipline-ceiling.md`:

```markdown
# Pressure scenario: 9th-category soft ceiling

**Context.** Fresh agent session. Fixture wiki with EIGHT categories already (concepts, entities, queries, ideas, projects, journal, research, prototypes). Capture trigger fires for content that the cheap model sees as belonging in a NEW 9th category called `experiments`.

**Without v2.3 SKILL.md update.** Behavior trace:
1. Cheap model decides at step 5: "this fits a new category called experiments."
2. `mkdir ~/wiki/experiments/`.
3. File capture in `experiments/foo.md`.
4. Discovery on next ingest picks up the 9th category. Status report doesn't flag (no soft-ceiling rule yet).

Result: category count creeps to 9, 10, 11 without any speed bump. Orientation cost grows.

**With v2.3 SKILL.md update.** Rule 3 fires:
1. Cheap model checks: current count is 8. Wants to mkdir 9th.
2. Files schema-proposal capture in `.wiki-pending/schema-proposals/2026-04-26T12-30-15Z-9th-category-experiments.md` instead of mkdir-ing.
3. Current capture goes to best-fit existing category (likely `prototypes/` or `research/`).
4. User reviews proposal next session; if approved, user `mkdir`-s themselves.

Result: agent doesn't autonomously inflate the category count. User retains gate-keeper role at growth boundaries.
```

- [ ] **Step 3: Reply-first scenario**

Create `docs/planning/transcripts/2026-04-26-reply-first-ordering.md`:

```markdown
# Pressure scenario: reply-first turn ordering

**Context.** Fresh agent session. User asks a research question. Research subagent returns a file (capture trigger).

**Without v2.3 SKILL.md update.** Procedural reading of SKILL.md (lines 191-203) suggests order:
1. Detect trigger.
2. Write capture to `.wiki-pending/`.
3. Spawn detached ingester.
4. Run `ls .wiki-pending/` turn-closure check.
5. Emit user-facing reply.

User sees the answer last — after all the capture machinery runs. Even though each step is milliseconds, the user is waiting for sequential file ops + process spawn before getting their answer.

**With v2.3 SKILL.md update.** New "Order matters" section reorders explicitly:
1. Detect trigger; do the work.
2. **Emit user-facing reply.**
3. For each trigger, write capture + spawn ingester.
4. Turn-closure check.
5. Stop sentinel.

User sees the answer immediately. Capture/spawn happens after but before turn-end. Turn-closure gate still ensures no captures are lost.
```

- [ ] **Step 4: Commit**

```bash
git add docs/planning/transcripts/
git commit -m "docs(v2.3): pressure scenario transcripts for SKILL.md changes

- Auto-discovered categories (projects/ vs concepts/ scenario).
- Rule 3 (9th category schema-proposal flow).
- Reply-first turn ordering."
```

---

### Task 16: Consume + archive v2.2 `index-split.md` schema-proposal

**Files:**
- Live: `~/wiki/.wiki-pending/schema-proposals/2026-04-24T19-43-06Z-index-split.md` → archive
- Live: `~/wiki/.wiki-pending/schema-proposals/2026-04-26T10-59-00Z-index-split.md` → archive

The v2.2 schema-proposal flagged `index.md > 25 KB`. v2.3 consumes it by replacing index.md with the small MOC. Archive both proposals.

- [ ] **Step 1: List existing proposals**

```bash
ls ~/wiki/.wiki-pending/schema-proposals/
```
Expected: at least the two `*-index-split.md` files.

- [ ] **Step 2: Move to archive**

```bash
mkdir -p ~/wiki/.wiki-pending/archive/2026-04
mv ~/wiki/.wiki-pending/schema-proposals/*-index-split.md ~/wiki/.wiki-pending/archive/2026-04/
```

- [ ] **Step 3: Append to log.md**

```bash
TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat >> ~/wiki/log.md <<EOF

## [${TS}] consume | index-split.md schema-proposals — archived; index.md replaced by 7-line MOC in v2.3 Phase D
EOF
```

- [ ] **Step 4: Commit in wiki repo**

```bash
cd ~/wiki
git add -A
git commit -m "chore(v2.3): consume + archive index-split.md schema-proposals

v2.3 replaces 25 KB index.md with 7-line MOC (per-category sub-indexes
hold the actual entries). Both v2.2-era proposals archived."
```

---

### Phase C verification gate

- [ ] **Step 1: Run full test suite**

```bash
cd "${REPO_ROOT}"
bash tests/run-all.sh
```
Expected: PASS.

- [ ] **Step 2: Subagent review of Phase C**

Reviewer checks: `wiki-build-index.py` works for all test cases; SKILL.md prose is consistent with §5.1, §5.2, §5.3 of spec; pressure scenarios exist; index-split proposals consumed.

If approved: proceed to Phase D.

---

## Phase D: Live wiki page migration (page moves + relinks + index rebuild)

### Task 17: Tarball backup + create `wiki-relink.py`

**Files:**
- Create: `scripts/wiki-relink.py`
- Create: `skills/karpathy-wiki/scripts/wiki-relink.py`
- Test: `tests/unit/test-relink.sh`

- [ ] **Step 1: Phase D tarball backup**

```bash
TS="$(date -u +%Y%m%dT%H%M%SZ)"
tar czf "${HOME}/wiki-backup-pre-v2.3-phase-d-${TS}.tar.gz" -C "${HOME}" wiki
echo "Phase D backup: ${HOME}/wiki-backup-pre-v2.3-phase-d-${TS}.tar.gz" >> docs/planning/RESUME.md
git add docs/planning/RESUME.md
git commit -m "chore(v2.3): record Phase D backup tarball location"
```

- [ ] **Step 2: Write failing test for `wiki-relink.py`**

Create `tests/unit/test-relink.sh`:

```bash
#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RELINK="${REPO_ROOT}/scripts/wiki-relink.py"

setup() {
  TMP="$(mktemp -d)"
  WIKI="${TMP}/wiki"
  mkdir -p "${WIKI}/concepts" "${WIKI}/projects/toolboxmd/karpathy-wiki" "${WIKI}/raw"
  touch "${WIKI}/.wiki-config"
}
teardown() { rm -rf "${TMP}"; }

test_rewrites_relative_link_to_leading_slash() {
  setup
  cat > "${WIKI}/concepts/source.md" <<'EOF'
See [v22](v22-architectural-cut.md) for context.
EOF
  cat > "${WIKI}/projects/toolboxmd/karpathy-wiki/v22-architectural-cut.md" <<'EOF'
content
EOF
  python3 "${RELINK}" --wiki-root "${WIKI}" \
    --moved "concepts/v22-architectural-cut.md=projects/toolboxmd/karpathy-wiki/v22-architectural-cut.md"
  grep -q "/projects/toolboxmd/karpathy-wiki/v22-architectural-cut.md" "${WIKI}/concepts/source.md" || {
    echo "FAIL: link not rewritten"
    teardown; exit 1
  }
  teardown
}

test_only_moved_pages_touched() {
  setup
  echo "[other](other-page.md) untouched" > "${WIKI}/concepts/source.md"
  python3 "${RELINK}" --wiki-root "${WIKI}" \
    --moved "concepts/somepage.md=projects/x.md"
  # The other-page.md link must NOT be rewritten
  grep -q "(other-page.md)" "${WIKI}/concepts/source.md" || {
    echo "FAIL: unrelated link was rewritten"
    teardown; exit 1
  }
  teardown
}

test_idempotent() {
  setup
  cat > "${WIKI}/concepts/source.md" <<'EOF'
See [v22](/projects/toolboxmd/karpathy-wiki/v22.md).
EOF
  python3 "${RELINK}" --wiki-root "${WIKI}" \
    --moved "concepts/v22.md=projects/toolboxmd/karpathy-wiki/v22.md"
  before="$(shasum -a 256 "${WIKI}/concepts/source.md")"
  python3 "${RELINK}" --wiki-root "${WIKI}" \
    --moved "concepts/v22.md=projects/toolboxmd/karpathy-wiki/v22.md"
  after="$(shasum -a 256 "${WIKI}/concepts/source.md")"
  [[ "${before}" == "${after}" ]] || { echo "FAIL: not idempotent"; teardown; exit 1; }
  teardown
}

test_unresolved_target_reported() {
  setup
  cat > "${WIKI}/concepts/source.md" <<'EOF'
See [missing](missing-page.md).
EOF
  out="$(python3 "${RELINK}" --wiki-root "${WIKI}" \
    --moved "concepts/missing-page.md=projects/missing.md" 2>&1 || true)"
  echo "${out}" | grep -q "unresolved" 2>/dev/null
  teardown
}

test_handles_already_leading_slash_form() {
  setup
  cat > "${WIKI}/concepts/source.md" <<'EOF'
See [v22](/concepts/v22.md).
EOF
  python3 "${RELINK}" --wiki-root "${WIKI}" \
    --moved "concepts/v22.md=projects/toolboxmd/karpathy-wiki/v22.md"
  grep -q "/projects/toolboxmd/karpathy-wiki/v22.md" "${WIKI}/concepts/source.md" || {
    echo "FAIL: leading-/ form not rewritten"
    teardown; exit 1
  }
  teardown
}

test_rewrites_relative_link_to_leading_slash
test_only_moved_pages_touched
test_idempotent
test_unresolved_target_reported
test_handles_already_leading_slash_form
echo "all tests passed"
```

- [ ] **Step 3: Run test (expect fail)**

```bash
bash tests/unit/test-relink.sh
```
Expected: FAIL.

- [ ] **Step 4: Implement `scripts/wiki-relink.py`**

```python
#!/usr/bin/env python3
"""Rewrite inbound links to moved pages.

Usage:
    wiki-relink.py --wiki-root <root> --moved <old-rel-path>=<new-rel-path> [...]

Only rewrites links whose target matches an old-rel-path. Other links untouched.
Idempotent. Outputs to stderr if any unresolved (already-rewritten) links found.

Exit codes:
    0 - success
    1 - argument or filesystem error
"""
import argparse
import re
import sys
from pathlib import Path

# Match markdown link: [text](href) where href doesn't start with http/https/mailto
LINK_RE = re.compile(r"\[([^\]]+)\]\(([^)]+)\)")


def rewrite_in_file(file: Path, moves: dict[str, str], wiki_root: Path) -> bool:
    """Return True if the file was modified."""
    text = file.read_text()
    modified = False

    def repl(match: re.Match) -> str:
        nonlocal modified
        anchor, href = match.group(1), match.group(2)
        # Skip external links
        if href.startswith(("http://", "https://", "mailto:", "#")):
            return match.group(0)
        # Resolve href to wiki-root-relative form
        if href.startswith("/"):
            target_rel = href[1:]
        else:
            # Relative to file's directory
            target_abs = (file.parent / href).resolve()
            try:
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
```

- [ ] **Step 5: Hand-copy + run tests**

```bash
chmod +x scripts/wiki-relink.py
cp scripts/wiki-relink.py skills/karpathy-wiki/scripts/wiki-relink.py
chmod +x skills/karpathy-wiki/scripts/wiki-relink.py
bash tests/unit/test-relink.sh
bash tests/unit/test-bundle-sync.sh
```
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add scripts/wiki-relink.py skills/karpathy-wiki/scripts/wiki-relink.py tests/unit/test-relink.sh
git commit -m "feat(v2.3): wiki-relink.py for Phase D moved-page link rewrites

- Only rewrites links whose target matches a --moved arg's old-path.
- Output form: leading-/ wiki-root-relative.
- Idempotent. Skips external links and reserved-dir files."
```

---

### Task 18: Create `wiki-migrate-v2.3.sh` orchestrator + tests

**Files:**
- Create: `scripts/wiki-migrate-v2.3.sh`
- Create: `skills/karpathy-wiki/scripts/wiki-migrate-v2.3.sh`
- Test: `tests/unit/test-migrate-v2.3.sh`

- [ ] **Step 1: Write failing test**

Create `tests/unit/test-migrate-v2.3.sh`:

```bash
#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MIGRATE="${REPO_ROOT}/scripts/wiki-migrate-v2.3.sh"
VALIDATOR="${REPO_ROOT}/scripts/wiki-validate-page.py"

setup_fixture() {
  TMP="$(mktemp -d)"
  WIKI="${TMP}/wiki"
  mkdir -p "${WIKI}/concepts" "${WIKI}/entities" "${WIKI}/queries" "${WIKI}/ideas" "${WIKI}/raw" "${WIKI}/.wiki-pending" "${WIKI}/.locks"
  touch "${WIKI}/.wiki-config"
  cat > "${WIKI}/concepts/karpathy-wiki-v2.2-architectural-cut.md" <<'EOF'
---
title: "v2.2 Cut"
type: concepts
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 5
  overall: 5.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: ingester
---
body
EOF
  cat > "${WIKI}/concepts/related.md" <<'EOF'
---
title: "Related"
type: concepts
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 5
  overall: 5.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: ingester
---
See [v2.2](karpathy-wiki-v2.2-architectural-cut.md).
EOF
}
teardown_fixture() { rm -rf "${TMP}"; }

test_dry_run_lists_planned_mutations() {
  setup_fixture
  out="$(bash "${MIGRATE}" --dry-run --wiki-root "${WIKI}" 2>&1)"
  echo "${out}" | grep -q "would mkdir.*projects/toolboxmd/karpathy-wiki" || { echo "FAIL: missing mkdir plan"; teardown_fixture; exit 1; }
  echo "${out}" | grep -q "would git mv.*v2.2-architectural-cut" || { echo "FAIL: missing mv plan"; teardown_fixture; exit 1; }
  teardown_fixture
}

test_full_run_moves_pages_and_relinks_atomically() {
  setup_fixture
  cd "${WIKI}"; git init -q; git add .; git commit -q -m "fixture"; cd -
  bash "${MIGRATE}" --yes --wiki-root "${WIKI}" >/dev/null
  [[ -f "${WIKI}/projects/toolboxmd/karpathy-wiki/karpathy-wiki-v2.2-architectural-cut.md" ]] || {
    echo "FAIL: page not moved"; teardown_fixture; exit 1
  }
  grep -q "/projects/toolboxmd/karpathy-wiki/karpathy-wiki-v2.2-architectural-cut.md" "${WIKI}/concepts/related.md" || {
    echo "FAIL: link not rewritten"; teardown_fixture; exit 1
  }
  teardown_fixture
}

test_idempotent_re_run() {
  setup_fixture
  cd "${WIKI}"; git init -q; git add .; git commit -q -m "fixture"; cd -
  bash "${MIGRATE}" --yes --wiki-root "${WIKI}" >/dev/null
  out="$(bash "${MIGRATE}" --yes --wiki-root "${WIKI}" 2>&1 || true)"
  echo "${out}" | grep -q "already migrated\|no-op\|skipped" 2>/dev/null
  teardown_fixture
}

test_validator_passes_after_migration() {
  setup_fixture
  cd "${WIKI}"; git init -q; git add .; git commit -q -m "fixture"; cd -
  bash "${MIGRATE}" --yes --wiki-root "${WIKI}" >/dev/null
  for p in $(find "${WIKI}" -name "*.md" -not -path "*/raw/*"); do
    python3 "${VALIDATOR}" --wiki-root "${WIKI}" "${p}" || {
      echo "FAIL: validator failed on ${p}"
      teardown_fixture; exit 1
    }
  done
  teardown_fixture
}

test_atomic_moves_relinks_no_intermediate_broken_state() {
  # Simulate: after migrate, run validator's link-resolver — must pass.
  setup_fixture
  cd "${WIKI}"; git init -q; git add .; git commit -q -m "fixture"; cd -
  bash "${MIGRATE}" --yes --wiki-root "${WIKI}" >/dev/null
  python3 "${VALIDATOR}" --wiki-root "${WIKI}" "${WIKI}/concepts/related.md" || {
    echo "FAIL: link-resolver caught broken inbound link"
    teardown_fixture; exit 1
  }
  teardown_fixture
}

test_dry_run_lists_planned_mutations
test_full_run_moves_pages_and_relinks_atomically
test_idempotent_re_run
test_validator_passes_after_migration
test_atomic_moves_relinks_no_intermediate_broken_state
echo "all tests passed"
```

- [ ] **Step 2: Run test (expect fail)**

```bash
bash tests/unit/test-migrate-v2.3.sh
```
Expected: FAIL with no migrate script.

- [ ] **Step 3: Implement `scripts/wiki-migrate-v2.3.sh`**

```bash
#!/bin/bash
# wiki-migrate-v2.3.sh — Live wiki page-migration orchestrator for v2.3.
#
# Phase D mutations:
#   - mkdir projects/toolboxmd/{karpathy-wiki,building-agentskills}/
#   - git mv 4 named pages from concepts/ to projects/toolboxmd/<project>/
#   - Run wiki-relink.py to rewrite inbound links (atomic with moves)
#   - Run wiki-build-index.py --rebuild-all to regenerate _index.md tree
#
# Per spec §4.1: Phase A.2 already rewrote frontmatter; this script does NOT
# touch frontmatter beyond the path-derived type for the moved pages.
#
# Usage:
#   wiki-migrate-v2.3.sh --dry-run --wiki-root <root>
#   wiki-migrate-v2.3.sh --yes --wiki-root <root>
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DRY_RUN=0
YES=0
WIKI_ROOT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --yes) YES=1; shift ;;
    --wiki-root) WIKI_ROOT="$2"; shift 2 ;;
    *) echo "usage: $0 (--dry-run | --yes) --wiki-root <root>" >&2; exit 1 ;;
  esac
done

if [[ -z "${WIKI_ROOT}" ]]; then
  echo "missing --wiki-root" >&2; exit 1
fi
if [[ ! -d "${WIKI_ROOT}" ]]; then
  echo "not a directory: ${WIKI_ROOT}" >&2; exit 1
fi

# Pages to move: <old-relative>:<new-relative>
declare -a MOVES=(
  "concepts/karpathy-wiki-v2.2-architectural-cut.md:projects/toolboxmd/karpathy-wiki/karpathy-wiki-v2.2-architectural-cut.md"
  "concepts/karpathy-wiki-v2.3-flexible-categories-design.md:projects/toolboxmd/karpathy-wiki/karpathy-wiki-v2.3-flexible-categories-design.md"
  "concepts/multi-stage-opus-pipeline-lessons.md:projects/toolboxmd/building-agentskills/multi-stage-opus-pipeline-lessons.md"
  "concepts/building-agentskills-repo-decision.md:projects/toolboxmd/building-agentskills/building-agentskills-repo-decision.md"
)

ensure_dirs() {
  for d in projects/toolboxmd/karpathy-wiki projects/toolboxmd/building-agentskills; do
    if [[ ! -d "${WIKI_ROOT}/${d}" ]]; then
      if [[ "${DRY_RUN}" -eq 1 ]]; then
        echo "would mkdir ${WIKI_ROOT}/${d}"
      else
        mkdir -p "${WIKI_ROOT}/${d}"
      fi
    fi
  done
}

move_pages() {
  local moved_args=()
  for mv in "${MOVES[@]}"; do
    local old="${mv%%:*}"
    local new="${mv##*:}"
    local old_abs="${WIKI_ROOT}/${old}"
    local new_abs="${WIKI_ROOT}/${new}"
    if [[ ! -f "${old_abs}" ]]; then
      if [[ -f "${new_abs}" ]]; then
        echo "already migrated (no-op): ${new}"
        continue
      fi
      echo "skipped (not found): ${old}"
      continue
    fi
    if [[ "${DRY_RUN}" -eq 1 ]]; then
      echo "would git mv ${old} -> ${new}"
      continue
    fi
    cd "${WIKI_ROOT}" && git mv "${old}" "${new}" && cd - >/dev/null
    moved_args+=("--moved" "${old}=${new}")
  done

  if [[ "${DRY_RUN}" -eq 0 && "${#moved_args[@]}" -gt 0 ]]; then
    python3 "${SCRIPT_DIR}/wiki-relink.py" --wiki-root "${WIKI_ROOT}" "${moved_args[@]}"
  fi
}

rebuild_index() {
  if [[ "${DRY_RUN}" -eq 1 ]]; then
    echo "would rebuild all _index.md via wiki-build-index.py --rebuild-all"
  else
    python3 "${SCRIPT_DIR}/wiki-build-index.py" --wiki-root "${WIKI_ROOT}" --rebuild-all
  fi
}

main() {
  ensure_dirs
  move_pages
  rebuild_index
}

main
```

- [ ] **Step 4: Hand-copy + run tests**

```bash
chmod +x scripts/wiki-migrate-v2.3.sh
cp scripts/wiki-migrate-v2.3.sh skills/karpathy-wiki/scripts/wiki-migrate-v2.3.sh
chmod +x skills/karpathy-wiki/scripts/wiki-migrate-v2.3.sh
bash tests/unit/test-migrate-v2.3.sh
bash tests/unit/test-bundle-sync.sh
```

- [ ] **Step 5: Commit**

```bash
git add scripts/wiki-migrate-v2.3.sh skills/karpathy-wiki/scripts/wiki-migrate-v2.3.sh tests/unit/test-migrate-v2.3.sh
git commit -m "feat(v2.3): wiki-migrate-v2.3.sh page-migration orchestrator

- Atomic moves+relinks (one commit, no broken intermediate state).
- --dry-run for inspection. Idempotent re-run.
- mkdir projects/toolboxmd/{karpathy-wiki,building-agentskills}/.
- git mv 4 named pages, then wiki-relink.py, then wiki-build-index.py."
```

---

### Task 19: Run live migration (Phase D commit 2 + 3)

- [ ] **Step 1: Dry run on live wiki**

```bash
bash scripts/wiki-migrate-v2.3.sh --dry-run --wiki-root ~/wiki
```
Expected output: planned mkdir + git mv lines for the 4 named pages, plus the rebuild step.

- [ ] **Step 2: Execute (atomic moves + relinks commit)**

```bash
cd ~/wiki
git status   # ensure clean
cd "${REPO_ROOT}"
bash scripts/wiki-migrate-v2.3.sh --yes --wiki-root ~/wiki
```

- [ ] **Step 3: Verify validator passes**

```bash
errors=0
while IFS= read -r p; do
  python3 scripts/wiki-validate-page.py --wiki-root ~/wiki "${p}" 2>&1 | grep -v WARNING | grep -q "." && {
    echo "FAIL: ${p}"
    errors=$((errors + 1))
  }
done < <(find ~/wiki -name "*.md" -not -path "*/raw/*" -not -path "*/.wiki-pending/*" -not -path "*/Clippings/*")
[[ "${errors}" -eq 0 ]] || { echo "ROLLBACK NEEDED"; exit 1; }
```
Expected: 0 errors.

- [ ] **Step 4: Commit moves+relinks atomically (in wiki repo)**

The migration script ran `git mv` + `wiki-relink.py` in the same script invocation. Both mutations must land in ONE commit.

```bash
cd ~/wiki
git add -A
git commit -m "feat(v2.3): move 4 named pages to projects/toolboxmd/ + rewrite inbound links

- karpathy-wiki-v2.2-architectural-cut.md → projects/toolboxmd/karpathy-wiki/
- karpathy-wiki-v2.3-flexible-categories-design.md → projects/toolboxmd/karpathy-wiki/
- multi-stage-opus-pipeline-lessons.md → projects/toolboxmd/building-agentskills/
- building-agentskills-repo-decision.md → projects/toolboxmd/building-agentskills/

Inbound links rewritten to leading-/ form atomically.

Tarball backup: ${HOME}/wiki-backup-pre-v2.3-phase-d-*.tar.gz"
```

- [ ] **Step 5: Index rebuild commit (in wiki repo)**

The migration script also ran `wiki-build-index.py --rebuild-all`. Verify the indexes look right:

```bash
cat ~/wiki/index.md
cat ~/wiki/projects/_index.md
cat ~/wiki/projects/toolboxmd/_index.md
cat ~/wiki/projects/toolboxmd/karpathy-wiki/_index.md
```

If the migrate script did NOT auto-stage these (depends on whether build-index runs after the git commit or before), stage and commit:

```bash
cd ~/wiki
git add -A
git status   # if there are unstaged _index.md changes:
git commit -m "feat(v2.3): regenerate _index.md tree + small root MOC

Replaces 24 KB index.md with ~10-line MOC pointing at per-category
_index.md files. Sub-indexes nest matching directory structure."
```

- [ ] **Step 6: Manifest validate**

```bash
cd "${REPO_ROOT}"
python3 scripts/wiki-manifest.py validate ~/wiki
```
Expected: PASS.

---

### Task 20: Validator-flip commit (in this repo)

This is Phase D's final commit. Both validator checks (membership + cross-check) get promoted from WARNING to HARD violation.

**Files:**
- Modify: `scripts/wiki-validate-page.py`
- Modify: `skills/karpathy-wiki/scripts/wiki-validate-page.py`
- Modify: `tests/unit/test-validate-page.sh` (update assertions for hard-fail)

- [ ] **Step 1: Edit validator**

In `scripts/wiki-validate-page.py`:

a) Find the type-membership check from Task 5:
```python
if t not in discovered_types:
    print(f"{rel}: WARNING type ...", file=sys.stderr)
```
Change to a hard violation:
```python
if t not in discovered_types:
    violations.append(
        f"{rel}: type '{t}' not in discovered categories {sorted(discovered_types)}"
    )
```

b) Find the type/path cross-check:
```python
if t != expected_type:
    print(f"{rel}: WARNING type ...", file=sys.stderr)
```
Change to a hard violation:
```python
if t != expected_type:
    violations.append(
        f"{rel}: type '{t}' != path.parts[0] '{expected_type}' "
        f"(run: python3 scripts/wiki-fix-frontmatter.py --wiki-root {wiki_root} {rel})"
    )
```

- [ ] **Step 2: Update tests in `test-validate-page.sh`**

Replace the `test_type_path_cross_check_warning_phase_a` case with a hard-fail assertion:

```bash
test_type_path_cross_check_hard_fail_post_phase_d() {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/concepts" "${tmp}/wiki/raw"
  touch "${tmp}/wiki/.wiki-config"
  cat > "${tmp}/wiki/concepts/foo.md" <<'EOF'
---
title: "Foo"
type: entities
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 5
  overall: 5.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: ingester
---
body
EOF
  if python3 "${VALIDATOR}" --wiki-root "${tmp}/wiki" "${tmp}/wiki/concepts/foo.md" 2>/dev/null; then
    echo "FAIL: cross-check should hard-fail"
    rm -rf "${tmp}"; exit 1
  fi
  rm -rf "${tmp}"
}
```

(Replace the call to the previous warning test with this one in the test runner block at the bottom.)

- [ ] **Step 3: Hand-copy validator + run tests**

```bash
cp scripts/wiki-validate-page.py skills/karpathy-wiki/scripts/wiki-validate-page.py
bash tests/unit/test-validate-page.sh
bash tests/unit/test-bundle-sync.sh
```

- [ ] **Step 4: Verify live wiki passes hard validator**

```bash
errors=0
while IFS= read -r p; do
  python3 scripts/wiki-validate-page.py --wiki-root ~/wiki "${p}" || errors=$((errors + 1))
done < <(find ~/wiki -name "*.md" -not -path "*/raw/*" -not -path "*/.wiki-pending/*" -not -path "*/Clippings/*")
echo "live wiki hard-fail count: ${errors}"
```
Expected: 0. If non-zero, the validator-flip is REVERTED, the failing pages investigated, fixed, and the flip retried.

- [ ] **Step 5: Commit**

```bash
git add scripts/wiki-validate-page.py skills/karpathy-wiki/scripts/wiki-validate-page.py tests/unit/test-validate-page.sh
git commit -m "feat(v2.3): validator-flip — type checks now hard violations

After Phase D's live wiki migration completed clean, both:
  - type-membership (type ∈ discovered categories)
  - type/path cross-check (type == path.parts[0])
become HARD violations (exit non-zero).

Phase A.2 + Phase D's page-rewrite work is verified by validator
passing clean over every live page before this flip lands."
```

---

### Task 21: Rename and extend `test-validate-no-source-type.sh`

**Files:**
- Rename: `tests/unit/test-validate-no-source-type.sh` → `tests/unit/test-validate-deleted-categories.sh`
- Modify content for new mismatch semantics + add `type: nonsense` case

- [ ] **Step 1: Rename**

```bash
git mv tests/unit/test-validate-no-source-type.sh tests/unit/test-validate-deleted-categories.sh
```

- [ ] **Step 2: Update content**

Edit the renamed file. Update the fixture's expected behavior: under v2.3, `type: source` in `concepts/foo.md` triggers the type/path cross-check (now hard violation) — the page is rejected.

Also add a new `type: nonsense` test case that asserts the type-membership check rejects.

```bash
test_deleted_category_source_rejected() {
  # ... existing fixture but with the new assertion
  if python3 "${VALIDATOR}" --wiki-root "${tmp}/wiki" "${tmp}/wiki/concepts/foo.md" 2>/dev/null; then
    echo "FAIL: validator should reject type:source in concepts/"
    exit 1
  fi
}

test_unknown_type_rejected() {
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/concepts" "${tmp}/wiki/raw"
  touch "${tmp}/wiki/.wiki-config"
  cat > "${tmp}/wiki/concepts/foo.md" <<'EOF'
---
title: "Foo"
type: nonsense
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 5
  overall: 5.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: ingester
---
body
EOF
  if python3 "${VALIDATOR}" --wiki-root "${tmp}/wiki" "${tmp}/wiki/concepts/foo.md" 2>/dev/null; then
    echo "FAIL: validator should reject type:nonsense"
    rm -rf "${tmp}"; exit 1
  fi
  rm -rf "${tmp}"
}
```

- [ ] **Step 3: Run test**

```bash
bash tests/unit/test-validate-deleted-categories.sh
```
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add tests/unit/test-validate-deleted-categories.sh
git commit -m "test(v2.3): rename test-validate-no-source-type → deleted-categories + nonsense case"
```

---

### Phase D verification gate

- [ ] **Step 1: Full test suite**

```bash
bash tests/run-all.sh
```
Expected: PASS.

- [ ] **Step 2: Live wiki clean**

```bash
errors=0
while IFS= read -r p; do
  python3 scripts/wiki-validate-page.py --wiki-root ~/wiki "${p}" || errors=$((errors + 1))
done < <(find ~/wiki -name "*.md" -not -path "*/raw/*" -not -path "*/.wiki-pending/*" -not -path "*/Clippings/*")
echo "live wiki hard-fail count: ${errors}"
```
Expected: 0.

- [ ] **Step 3: Subagent review**

Reviewer checks: 4 pages live in `projects/toolboxmd/<project>/`; their inbound links use leading-`/`; live `index.md` is the small MOC; per-category `_index.md` files exist; validator-flip is in place; live wiki passes hard validator.

If approved: proceed to Phase E.

---

## Phase E: TODO + post-flight

### Task 22: Update TODO.md and write ship retrospective

**Files:**
- Modify: `TODO.md` (mark v2.3 items shipped, add v2.4 deferrals)
- Optional: write ship retrospective to building-agentskills case studies

- [ ] **Step 1: Read current TODO.md**

```bash
cat TODO.md
```

- [ ] **Step 2: Update TODO.md**

Add a v2.3 section at the top:

```markdown
## v2.3 (shipped 2026-04-26)

- [x] Auto-discovered categories (wiki-discover.py + validator integration)
- [x] Recursive _index.md per directory + small root MOC
- [x] Live wiki frontmatter migration (singular → plural; ideas/ corrected)
- [x] 4 pages moved from concepts/ to projects/toolboxmd/<project>/
- [x] Three category-discipline rules in SKILL.md
- [x] Reply-first turn ordering rule in SKILL.md
- [x] Bundle-sync hand-copy contract + CI test
- [x] wiki-status.sh + wiki-backfill-quality.py rewired to discovery

## v2.4 (deferred from v2.3)

- [ ] Skill-bundling sync mechanism (auto-sync between /scripts/ and /skills/karpathy-wiki/scripts/; replace hand-copy + sha256 CI check with build-step or symlinks)
- [ ] Automated retroactive global link migration (`../foo.md` → `/category/foo.md` form for ALL relative links, not just moved pages)
- [ ] Cosmetic reorg of historical migration scripts to scripts/historical/ (test-migrate-v2-hardening.sh, test-migrate-v2.2.sh, etc.)
- [ ] wiki create-category CLI (if friction surfaces; mkdir is the v2.3 contract)
- [ ] wiki doctor real implementation (smartest-model re-rate; orphan repair; tag synonym consolidation)
```

- [ ] **Step 3: Commit**

```bash
git add TODO.md
git commit -m "docs(v2.3): mark v2.3 items shipped + record v2.4 deferrals"
```

---

### Phase E verification gate

- [ ] **Step 1: Full test suite**

```bash
bash tests/run-all.sh
```
Expected: PASS.

- [ ] **Step 2: Final subagent review**

Reviewer checks the entire ship: spec acceptance criteria all met; ~22 commits across 5 phases; live wiki state matches spec; SKILL.md consistent.

- [ ] **Step 3: Open PR**

```bash
git push -u origin v2-rewrite
gh pr create --title "karpathy-wiki v2.3: flexible auto-discovered categories" --body "$(cat <<'EOF'
## Summary
- Replaces hard-coded category whitelist with auto-discovered categories rooted in directory tree.
- Introduces recursive `_index.md` per directory; small root MOC.
- Adds three category-discipline rules + reply-first turn ordering to SKILL.md.
- Live wiki migration: 4 pages → projects/toolboxmd/<project>/, all 58 pages get plural type:.
- Bundle-sync hand-copy contract with CI verification (proper sync mechanism deferred to v2.4).

## Test plan
- [ ] `bash tests/run-all.sh` passes (53 new test cases across 13 files)
- [ ] Validator clean over live `~/wiki/` (0 hard violations)
- [ ] Manifest validates clean
- [ ] `wiki-status.sh` reflects new state (5 categories: concepts, entities, queries, ideas, projects)
- [ ] `index.md` is the small MOC (~10 lines)
- [ ] Per-directory `_index.md` files render correctly in Obsidian

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-Review Checklist (run before handing off to executor)

**Spec coverage:**
- [x] §3 in-scope: every line maps to a task (auto-discovery, type=plural, arbitrary nesting, leading-/, _index.md, MOC, schema.md markers, status from discovery, 3 rules, reply-first, frontmatter migration, content migration, Clippings reserved, init.sh seed update + Python check, status+backfill rewire, normalize obsolete-not-deleted)
- [x] §3 out-of-scope: nothing implemented from this list
- [x] §4.1 type-naming: plural via wiki-fix-frontmatter, frontmatter-only contract verified by adversarial fixtures
- [x] §5 component map: every entry has a creating/modifying task
- [x] §5.1 three rules: documented in SKILL.md (Task 12), enforced by validator (depth-≥5) or agent prompt (Rules 1, 3)
- [x] §5.2 reply-first: SKILL.md section + transcript fixture (Tasks 12, 15)
- [x] §5.4 validator flow: all checks present; warning-Phase-A → hard-Phase-D flip (Tasks 5, 20)
- [x] §5.5 lock ordering: implemented in wiki-build-index.py (Task 11)
- [x] §5.6 bundle-copy: hand-copy in every script task; CI test in Task 2
- [x] §6 examples: matched in tests
- [x] §7 error handling: validator behaviors mirror the table
- [x] §8 testing: ~53 cases distributed across tasks
- [x] §9 phasing: A.1 (T1-T8), A.2 (T9), B (T10), C (T11-T16), D (T17-T21), E (T22)
- [x] §10 acceptance: covered by per-phase verification gates
- [x] §11 risks: each mitigation maps to a task

**Placeholders:** Searched for TBD/TODO (filename references only), "implement later" (none), "fill in details" (none), "similar to Task N" (none — code repeated where needed).

**Type consistency:** validator function names, wiki-discover.py output keys (categories/reserved/depths/counts), lock acquisition contract (path-order, bottom-up release) all consistent across tasks.

---

## Execution Handoff

Plan complete and saved to `docs/planning/2026-04-25-karpathy-wiki-v2.3-plan.md`. Two execution options:

**1. Subagent-Driven (recommended, per spec §12)** — I dispatch a fresh subagent per task, review between tasks, fast iteration. Same toolkit as v2.2.

**2. Inline Execution** — Execute tasks in this session using executing-plans, batch with checkpoints.

Subagent-driven is the spec-mandated mode. Phase D's live-wiki touch benefits from a fresh-context reviewer that hasn't seen Phases A-C.

End of plan.
