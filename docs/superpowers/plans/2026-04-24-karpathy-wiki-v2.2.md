# Karpathy Wiki v2.2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. This plan **extends** v2-hardening at `docs/planning/2026-04-24-karpathy-wiki-v2-hardening.md` and reuses every discipline convention from it.

**Goal:** Kill the `sources/` wiki category (architectural cut — closes audit Findings 02, 05, 09 in one move) and ship 5 mechanical fixes (Findings 01, 03, 04, 06, 14) the audit surfaced.

**Architecture:** Four phases on branch `v2-rewrite`, sequential. Phase A removes `sources/` from the contract (validator, schema, SKILL.md, status). Phase B hardens validator + ingester safety (code-block link skip, commit-gated-on-validator, manifest validate subcommand, empty-origin guard). Phase C wires three thresholds-to-mechanisms (index size, archive `.processing` strip, status last-ingest field). Phase D applies all changes to the live `~/wiki/` via one migration script.

**Tech Stack:** Bash (`set -e` / `set -uo pipefail`), Python 3.11+ stdlib-only, JSON for manifest, YAML frontmatter for pages, plain markdown for wiki content.

**Working directory:** `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/`

**Live wiki:** `/Users/lukaszmaj/wiki/` (modified only in Phase D)

**Branch:** `v2-rewrite` (do NOT push, merge, or tag — those are user decisions)

**Task numbering:** continues from v2-hardening (Tasks 30-44 shipped). v2.2 starts at Task 50.

---

## Files (overview)

**Modified:**
- `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-validate-page.py` — drop `type: source` from whitelist; skip code-block links; cross-check type vs directory IS NOT in scope (deferred to v2.3 with `wiki doctor`).
- `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-manifest.py` — add `validate` subcommand.
- `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-status.sh` — read last-ingest from manifest; surface index-size warning; drop `sources/` from category counts.
- `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md` — remove `sources/` rules, strengthen Iron Rule #7, add ingest step 7.6 (index threshold), tighten ingester commit-gate prose.
- `/Users/lukaszmaj/wiki/schema.md` — drop `sources/` from categories list (Phase D).
- `/Users/lukaszmaj/wiki/concepts/docs-fetching-methods-for-agents.md` — rewrite `sources:` field (Phase D).
- `/Users/lukaszmaj/wiki/concepts/jina-reader-vs-cloudflare-markdown.md` — rewrite `sources:` field (Phase D).
- `/Users/lukaszmaj/wiki/concepts/yazi-install-gotchas.md` — rewrite `sources:` field (Phase D).
- `/Users/lukaszmaj/wiki/concepts/agent-vs-machine-file-formats.md` — drop body links to `sources/` page (Phase D).
- `/Users/lukaszmaj/wiki/concepts/context7-cli-vs-mcp.md` — drop body link to `sources/` page (Phase D).
- `/Users/lukaszmaj/wiki/concepts/starship-terminal-theming.md` — fix 2 same-dir prefix-bug links (Phase D).
- `/Users/lukaszmaj/wiki/.manifest.json` — set `origin: conversation` on 2 entries (Phase D).

**Created:**
- `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-migrate-v2.2.sh` — one migration script, named functions, `--dry-run` flag.
- `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-validate-no-source-type.sh`
- `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-validate-code-block-skip.sh`
- `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-manifest-validate.sh`
- `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-index-threshold-fires.sh`
- `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-archive-strips-processing.sh`
- `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-status-last-ingest.sh`
- `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-migrate-v2.2.sh`

**Deleted (Phase D, via `git rm`):**
- `/Users/lukaszmaj/wiki/sources/` — all 31 files.

---

## Style / discipline

- Each task = its own commit on `v2-rewrite`. No `--amend`. No `--no-verify`.
- TDD: RED (test, run, fail) → GREEN (script, run, pass) → REFACTOR.
- `**Files:**` block on every task, absolute paths.
- Verbatim test bodies and script bodies. No placeholders.
- Shell: `set -e` for fail-fast; `set -uo pipefail` for hooks.
- Python: stdlib only; first lines reject Python < 3.11.
- SKILL.md edits: BEFORE block verbatim, AFTER block verbatim. Final SKILL.md MUST stay ≤ 500 lines (currently 455; v2.2 net change is roughly -10 lines).
- Test name → matches file basename. Test bodies emit `PASS:` / `FAIL:` lines and `ALL PASS` on green; exit 1 on any FAIL (matches v2 pattern in `test-manifest.sh`).

---

## Phase A — Architectural cut: kill `sources/`

Phase A removes `sources/` from the contract (validator, SKILL.md, schema). Live wiki is NOT touched yet — that's Phase D.

### Task 50: Remove `type: source` from validator type whitelist

**Files:**
- Modify: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-validate-page.py:40` (VALID_TYPES set), `:368-377` (type=source raw-file check)
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-validate-no-source-type.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test-validate-no-source-type.sh`:

```bash
#!/bin/bash
# Test: validator rejects type: source after v2.2 cut.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VALIDATOR="${REPO_ROOT}/scripts/wiki-validate-page.py"

tmp="$(mktemp -d)"
trap "rm -rf '${tmp}'" EXIT

mkdir -p "${tmp}/wiki/sources" "${tmp}/wiki/raw"
touch "${tmp}/wiki/.wiki-config"
cat > "${tmp}/wiki/sources/foo.md" <<'EOF'
---
title: "Source: Foo"
type: source
tags: [test]
sources:
  - raw/foo.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
quality:
  accuracy: 3
  completeness: 3
  signal: 3
  interlinking: 3
  overall: 3.00
  rated_at: "2026-04-24T12:00:00Z"
  rated_by: ingester
---
body
EOF
echo "raw" > "${tmp}/wiki/raw/foo.md"

# Run validator; expect type-not-allowed violation.
output="$(python3 "${VALIDATOR}" --wiki-root "${tmp}/wiki" "${tmp}/wiki/sources/foo.md" 2>&1 || true)"
if echo "${output}" | grep -q "type must be one of"; then
  echo "PASS: validator rejects type: source"
else
  echo "FAIL: expected type-rejection, got: ${output}"
  exit 1
fi

echo "ALL PASS"
```

- [ ] **Step 2: Run test to verify it fails**

```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-validate-no-source-type.sh
```
Expected: `FAIL: expected type-rejection, got: ` (current validator allows `source`).

- [ ] **Step 3: Modify validator — drop `source` from VALID_TYPES**

Edit `scripts/wiki-validate-page.py`. BEFORE (line 40):

```python
VALID_TYPES = {"concept", "entity", "source", "query"}
```

AFTER:

```python
VALID_TYPES = {"concept", "entity", "query"}
```

- [ ] **Step 4: Modify validator — drop the type=source raw-file check**

Edit `scripts/wiki-validate-page.py`. BEFORE (lines 368-377):

```python
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
```

AFTER: delete the entire block (lines 368-377 inclusive). Adjacent code (`return violations` at line 379) becomes the next line after the closing of the sources-existence loop.

- [ ] **Step 5: Update validator docstring**

Edit `scripts/wiki-validate-page.py`. BEFORE (lines 11-12):

```python
  - `type` is one of: concept, entity, source, query.
```

AFTER:

```python
  - `type` is one of: concept, entity, query. (`source` removed in v2.2 — `sources/` category was deleted.)
```

BEFORE (lines 23-24):

```python
  - For `type: source`, a raw file at `raw/<basename-of-this-page>` exists.
```

AFTER: delete that line entirely.

- [ ] **Step 6: Run the new test to verify it passes**

```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-validate-no-source-type.sh
```
Expected: `PASS: validator rejects type: source` then `ALL PASS`.

- [ ] **Step 7: Run existing validator unit tests to confirm no regression**

```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-validate-page.sh
```
Expected: `ALL PASS` (any tests that fixture a `type: source` page need updating in this same task — see step 8).

- [ ] **Step 8: Update existing validator tests that fixture `type: source`**

If `test-validate-page.sh` fails at step 7 because a fixture used `type: source` to verify other rules, change the fixture to `type: concept` (or whatever the rule under test allows). Re-run step 7 until green.

- [ ] **Step 9: Commit**

```bash
git add scripts/wiki-validate-page.py tests/unit/test-validate-no-source-type.sh tests/unit/test-validate-page.sh
git commit -m "feat(validator): drop type: source from whitelist (v2.2 sources/ removal)

Audit Finding 02 + the broader architectural cut: sources/ pointer pages
duplicate information already in manifest.json (origin, referenced_by) and
concept-page frontmatter (sources: raw/...). Category is being deleted in
v2.2; validator stops accepting type: source first so the contract is
narrow before live migration in Phase D.

The type=source raw-file existence check is removed at the same time --
moot once no page can carry that type."
```

---

### Task 51: Remove `sources/` rules from SKILL.md

**Files:**
- Modify: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md` (multiple sections)

- [ ] **Step 1: Identify every `sources/<basename>` mention**

```bash
grep -n 'sources/<basename>\|sources/.\*\.md\|create a `sources' /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md
```
Expected hits: ingest step 4 sub-bullet about creating source pointer; the line "Every raw file MUST have a matching sources/ pointer page".

- [ ] **Step 2: Remove ingest-step-4 source-pointer sub-bullet**

Edit `skills/karpathy-wiki/SKILL.md`. Find the section starting with `4. **Copy evidence, write manifest entry with correct origin:**` (around line 274 of current 455-line file). BEFORE (the source-pointer creation sub-bullet within step 4):

```markdown
   - After copying to raw/, create a `sources/<basename>.md` pointer page IF one does not already exist. Template in `references/source-pointer-template.md` (if present) or inline in the skill's base prose. Every raw file MUST have a matching sources/ pointer page — the validator now enforces this.
```

AFTER: delete that entire bullet line.

- [ ] **Step 3: Remove the page-touch list mention of `sources/`**

In the same SKILL.md, find any list of "pages you may touch" within ingest steps (around step 6). Look for `concepts/`, `entities/`, `sources/`, `queries/` enumerations. BEFORE:

```markdown
6. **For each target page**:
```

(In the prose around step 6 itself there's no `sources/` enumeration; the orientation paragraph at the top of the skill mentions categories. Skip if no hit; this step is a guard against missed mentions.)

Run:

```bash
grep -n '`sources/' /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md
```
Any remaining hits inside example blocks: rewrite the example to use `concepts/` instead. Hits inside the now-removed step-4 bullet should be gone.

- [ ] **Step 4: Drop `sources/` from any frontmatter examples**

Find blocks that show example `suggested_pages:` lists. BEFORE:

```markdown
suggested_pages:
  - concepts/<slug>.md   # paths relative to wiki root
```

(If the example currently shows a `sources/` line, remove it. Concept-only is fine.)

Run:

```bash
grep -n 'suggested_pages\|- sources/' /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md
```
Verify no `- sources/` remains in any example. If a `## See also` or other example uses a sources path, change to `concepts/...`.

- [ ] **Step 5: One-pass redundancy scan (D2 contract)**

Re-read SKILL.md from line 1 to end. Look for prose that ONLY exists because of the source-pointer rule (e.g., a paragraph explaining why source pointers exist, a clause "and the source pointer page" within a longer rule, etc.). For each:

- If removing the prose leaves the surrounding rule self-consistent → remove it.
- If removing leaves an orphan article ("the" with no antecedent) → reword the surrounding sentence.
- If unsure → leave it (D2 fallback to D1 is acceptable).

Document every removal in the commit message body so reviewers can verify.

- [ ] **Step 6: Verify line count stays ≤ 500**

```bash
wc -l /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md
```
Expected: ≤ 500. Currently 455; this task should reduce to ~440-450.

- [ ] **Step 7: Verify no `sources/<basename>` mentions remain**

```bash
grep -n 'sources/<basename>\|create a `sources\|source pointer' /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md
```
Expected output: empty (or only mentions that explicitly say "removed in v2.2").

- [ ] **Step 8: Commit**

```bash
git add skills/karpathy-wiki/SKILL.md
git commit -m "feat(skill): remove sources/ pointer-page rules from SKILL.md (v2.2)

Sources/ category is being deleted in v2.2. SKILL.md drops:
- ingest step 4 sub-bullet about creating sources/<basename>.md pointer
- any example fragments that show sources/ paths

D2 contract: surgical edits + one-pass scan for redundancies. Found and
removed: <enumerate findings here, or 'no additional redundancies' if D1>.

Line count: 455 → <new count>. Headroom under 500-line cap preserved."
```

---

### Task 52: Drop `sources/` from schema.md categories list (live wiki)

This is one of two Phase A tasks that touches the live wiki — the schema.md is part of the wiki, but it's authoritative reference data, not page content. Edit it now (with the validator rule) so future ingests pick up the right categories.

**Files:**
- Modify: `/Users/lukaszmaj/wiki/schema.md`

- [ ] **Step 1: Read the current categories block**

```bash
grep -n -A 10 '^## Categories' /Users/lukaszmaj/wiki/schema.md
```
Expected: lists `concepts/`, `entities/`, `sources/`, `queries/`, `ideas/`.

- [ ] **Step 2: Remove the `sources/` line from categories**

Edit `/Users/lukaszmaj/wiki/schema.md`. BEFORE:

```markdown
- `sources/` — one summary page per ingested source
```

AFTER: delete that entire line.

- [ ] **Step 3: Verify schema.md remains syntactically valid**

```bash
head -30 /Users/lukaszmaj/wiki/schema.md
```
Expected: heading + role + categories list (4 entries: concepts, entities, queries, ideas), no orphan dashes.

- [ ] **Step 4: Commit (in the wiki repo)**

The wiki has its own git history. Commit there.

```bash
cd /Users/lukaszmaj/wiki
git add schema.md
git commit -m "schema: drop sources/ category (v2.2 architectural cut)

sources/ pointer pages duplicated information already in manifest.json
and concept-page frontmatter. Removed in karpathy-wiki v2.2."
cd -
```

---

## Phase A acceptance

- Validator no longer accepts `type: source`.
- SKILL.md no longer mentions `sources/<basename>` rule.
- Schema.md no longer lists `sources/` as a category.
- All Phase A unit tests green.
- `wc -l skills/karpathy-wiki/SKILL.md` ≤ 500.

Run before proceeding to Phase B:

```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-validate-no-source-type.sh
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-validate-page.sh
```
Both must end `ALL PASS`.

---

## Phase B — Validator + ingester safety (Findings 04, 06)

### Task 53: Validator skips markdown links inside fenced code blocks and inline code

**Files:**
- Modify: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-validate-page.py:194-199` (`_extract_body_links`)
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-validate-code-block-skip.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test-validate-code-block-skip.sh`:

```bash
#!/bin/bash
# Test: validator skips markdown links inside fenced and inline code spans.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VALIDATOR="${REPO_ROOT}/scripts/wiki-validate-page.py"

tmp="$(mktemp -d)"
trap "rm -rf '${tmp}'" EXIT

mkdir -p "${tmp}/wiki/concepts" "${tmp}/wiki/raw"
touch "${tmp}/wiki/.wiki-config"
cat > "${tmp}/wiki/concepts/foo.md" <<'EOF'
---
title: "Foo"
type: concept
tags: [test]
sources:
  - raw/foo.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 5
  overall: 5.00
  rated_at: "2026-04-24T12:00:00Z"
  rated_by: ingester
---

This page demonstrates portable links: `[Title](path.md)` is the format.

Inside an inline span: `[Foo](nope.md)` should not trigger the validator.

```
[Bar](also-nope.md)
```

But this real link MUST trigger: [Real](nonexistent.md).
EOF
echo "raw" > "${tmp}/wiki/raw/foo.md"

output="$(python3 "${VALIDATOR}" --wiki-root "${tmp}/wiki" "${tmp}/wiki/concepts/foo.md" 2>&1 || true)"

# Should report exactly one broken link: nonexistent.md
nonexistent_count="$(echo "${output}" | grep -c 'nonexistent.md' || true)"
path_count="$(echo "${output}" | grep -c 'path.md' || true)"
also_nope_count="$(echo "${output}" | grep -c 'also-nope.md' || true)"

if [[ "${nonexistent_count}" -ne 1 ]]; then
  echo "FAIL: expected 1 violation for nonexistent.md, got ${nonexistent_count}. Output: ${output}"
  exit 1
fi
if [[ "${path_count}" -ne 0 ]]; then
  echo "FAIL: validator flagged path.md inside inline code span (${path_count} times). Output: ${output}"
  exit 1
fi
if [[ "${also_nope_count}" -ne 0 ]]; then
  echo "FAIL: validator flagged also-nope.md inside fenced code block (${also_nope_count} times). Output: ${output}"
  exit 1
fi

echo "PASS: validator skips fenced + inline code link examples"
echo "ALL PASS"
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-validate-code-block-skip.sh
```
Expected: `FAIL: validator flagged path.md inside inline code span (1 times)` (and similar for fenced).

- [ ] **Step 3: Modify validator — strip code spans before extracting links**

Edit `scripts/wiki-validate-page.py`. BEFORE (lines 194-199):

```python
_LINK_RE = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")


def _extract_body_links(body: str) -> list[str]:
    """Return every (relative or absolute) URL target of a markdown link."""
    return _LINK_RE.findall(body)
```

AFTER:

```python
_LINK_RE = re.compile(r"\[[^\]]*\]\(([^)\s]+)\)")
_FENCED_CODE_RE = re.compile(r"```.*?```", re.DOTALL)
_INLINE_CODE_RE = re.compile(r"`[^`\n]+`")


def _extract_body_links(body: str) -> list[str]:
    """Return every (relative or absolute) URL target of a markdown link.

    Skips links that appear inside fenced code blocks (```...```) or inline
    code spans (`...`). Markdown link syntax inside code is illustrative,
    not a real link.
    """
    stripped = _FENCED_CODE_RE.sub("", body)
    stripped = _INLINE_CODE_RE.sub("", stripped)
    return _LINK_RE.findall(stripped)
```

- [ ] **Step 4: Run the new test to verify it passes**

```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-validate-code-block-skip.sh
```
Expected: `PASS: validator skips fenced + inline code link examples` then `ALL PASS`.

- [ ] **Step 5: Run existing validator tests to confirm no regression**

```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-validate-page.sh
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-validate-no-source-type.sh
```
Both must end `ALL PASS`.

- [ ] **Step 6: Commit**

```bash
git add scripts/wiki-validate-page.py tests/unit/test-validate-code-block-skip.sh
git commit -m "fix(validator): skip markdown links inside code spans (Finding 04)

The Tier-1 broken-link check previously flagged example URLs inside
fenced code blocks and inline code spans (e.g. \`[Title](path.md)\` shown
as portable-link demo). These are illustrative, not real links.

Audit Finding 04 evidence:
  concepts/wiki-obsidian-integration.md: broken link path.md (inline span)
  sources/2026-04-24T14-08-32Z-wiki-obsidian-integration.md: same

Fix strips fenced ('''...''') and inline (\`...\`) code regions before
extracting markdown link targets."
```

---

### Task 54: Manifest `validate` subcommand + empty-origin guard

**Files:**
- Modify: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-manifest.py:217-240` (main dispatcher); add `cmd_validate`
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-manifest-validate.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test-manifest-validate.sh`:

```bash
#!/bin/bash
# Test: wiki-manifest.py validate catches empty origin and bad-shape origin.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MANIFEST="${REPO_ROOT}/scripts/wiki-manifest.py"

tmp="$(mktemp -d)"
trap "rm -rf '${tmp}'" EXIT

mkdir -p "${tmp}/wiki/raw"
touch "${tmp}/wiki/.wiki-config"
cat > "${tmp}/wiki/.manifest.json" <<'EOF'
{
  "raw/good-path.md": {
    "sha256": "abc123",
    "origin": "/Users/x/research/good.md",
    "copied_at": "2026-04-24T12:00:00Z",
    "last_ingested": "2026-04-24T12:00:00Z",
    "referenced_by": ["concepts/good.md"]
  },
  "raw/good-conv.md": {
    "sha256": "def456",
    "origin": "conversation",
    "copied_at": "2026-04-24T12:00:00Z",
    "last_ingested": "2026-04-24T12:00:00Z",
    "referenced_by": ["concepts/good.md"]
  },
  "raw/bad-empty.md": {
    "sha256": "ghi789",
    "origin": "",
    "copied_at": "2026-04-24T12:00:00Z",
    "last_ingested": "2026-04-24T12:00:00Z",
    "referenced_by": []
  },
  "raw/bad-typename.md": {
    "sha256": "jkl012",
    "origin": "file",
    "copied_at": "2026-04-24T12:00:00Z",
    "last_ingested": "2026-04-24T12:00:00Z",
    "referenced_by": []
  },
  "raw/bad-relpath.md": {
    "sha256": "mno345",
    "origin": "research/foo.md",
    "copied_at": "2026-04-24T12:00:00Z",
    "last_ingested": "2026-04-24T12:00:00Z",
    "referenced_by": []
  }
}
EOF

# Run validate; expect exit 1 with violations for the 3 bad entries.
output="$(python3 "${MANIFEST}" validate "${tmp}/wiki" 2>&1 || true)"
rc=$?
if [[ ${rc} -eq 0 ]]; then
  # 'set -e' will not trigger because we ||true'd, but rc captured pre-true
  : # rc=0 means no exit; check violations in output
fi

# Should mention all 3 bad entries.
if ! echo "${output}" | grep -q "bad-empty.md.*empty origin"; then
  echo "FAIL: expected bad-empty.md flagged. Output: ${output}"
  exit 1
fi
if ! echo "${output}" | grep -q "bad-typename.md.*literal evidence_type"; then
  echo "FAIL: expected bad-typename.md flagged. Output: ${output}"
  exit 1
fi
if ! echo "${output}" | grep -q "bad-relpath.md.*absolute path"; then
  echo "FAIL: expected bad-relpath.md flagged. Output: ${output}"
  exit 1
fi
# Should NOT flag the two good entries.
if echo "${output}" | grep -q "good-path.md\|good-conv.md"; then
  echo "FAIL: validator falsely flagged a good entry. Output: ${output}"
  exit 1
fi

# Final exit code check.
python3 "${MANIFEST}" validate "${tmp}/wiki" >/dev/null 2>&1 && {
  echo "FAIL: expected non-zero exit on bad manifest"
  exit 1
}

echo "PASS: wiki-manifest.py validate catches empty / typename / relative-path origins"
echo "ALL PASS"
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-manifest-validate.sh
```
Expected: `FAIL: ...` because `validate` is not yet a known subcommand.

- [ ] **Step 3: Add `cmd_validate` to `wiki-manifest.py`**

Edit `scripts/wiki-manifest.py`. After the existing `cmd_migrate` function (around line 215, before `def main()`), insert:

```python
def cmd_validate(wiki_root: Path) -> int:
    """Verify every manifest entry has a non-empty `origin` matching either
    the literal "conversation" or an absolute filesystem path. Empty,
    evidence-type-as-origin ("file"/"mixed"/"conversation" used wrongly),
    and relative-path origins are violations.
    """
    manifest_path = wiki_root / ".manifest.json"
    if not manifest_path.is_file():
        print(f"no manifest at {manifest_path}", file=sys.stderr)
        return 1
    manifest = _load_json(manifest_path)
    bad: list[str] = []
    for k, v in manifest.items():
        if not isinstance(v, dict):
            bad.append(f"{k}: entry is not an object")
            continue
        o = v.get("origin", "")
        if not isinstance(o, str):
            bad.append(f"{k}: origin must be a string, got {type(o).__name__}")
            continue
        if o == "":
            bad.append(f"{k}: empty origin")
        elif o in ("file", "mixed"):
            bad.append(f"{k}: origin is literal evidence_type {o!r}")
        elif o != "conversation" and not o.startswith("/"):
            bad.append(
                f"{k}: origin must be 'conversation' or an absolute path, "
                f"got {o!r}"
            )
    for line in bad:
        print(line, file=sys.stderr)
    return 0 if not bad else 1
```

- [ ] **Step 4: Wire `validate` into the dispatcher**

Edit `scripts/wiki-manifest.py`. BEFORE (around line 222-240, inside `main()`):

```python
    if len(sys.argv) != 3:
        print("usage: wiki-manifest.py {build|diff|migrate} <wiki_root>",
              file=sys.stderr)
        return 1

    cmd = sys.argv[1]
    wiki_root = Path(sys.argv[2]).resolve()
    if not wiki_root.is_dir():
        print(f"not a directory: {wiki_root}", file=sys.stderr)
        return 1

    if cmd == "build":
        return cmd_build(wiki_root)
    if cmd == "diff":
        return cmd_diff(wiki_root)
    if cmd == "migrate":
        return cmd_migrate(wiki_root)
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 1
```

AFTER:

```python
    if len(sys.argv) != 3:
        print("usage: wiki-manifest.py {build|diff|migrate|validate} <wiki_root>",
              file=sys.stderr)
        return 1

    cmd = sys.argv[1]
    wiki_root = Path(sys.argv[2]).resolve()
    if not wiki_root.is_dir():
        print(f"not a directory: {wiki_root}", file=sys.stderr)
        return 1

    if cmd == "build":
        return cmd_build(wiki_root)
    if cmd == "diff":
        return cmd_diff(wiki_root)
    if cmd == "migrate":
        return cmd_migrate(wiki_root)
    if cmd == "validate":
        return cmd_validate(wiki_root)
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 1
```

- [ ] **Step 5: Run the new test to verify it passes**

```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-manifest-validate.sh
```
Expected: `PASS:` then `ALL PASS`.

- [ ] **Step 6: Run existing manifest tests to confirm no regression**

```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-manifest.sh
```
Expected: `ALL PASS`.

- [ ] **Step 7: Commit**

```bash
git add scripts/wiki-manifest.py tests/unit/test-manifest-validate.sh
git commit -m "feat(manifest): add validate subcommand with origin guard (Finding 06)

Audit found 2 manifest entries with empty origin (copyparty, yazi-install).
Iron Rule #7 prose enumerates 'file', 'mixed', 'conversation', and
absolute-path cases but didn't cover the empty case -- so the validator
silently accepted ''.

cmd_validate enforces:
- origin is non-empty
- origin is NOT the literal evidence_type ('file' / 'mixed')
- origin is either 'conversation' or starts with '/' (absolute path)

Returns non-zero on any violation. Wired into the dispatcher; usage line
updated to advertise 'validate'."
```

---

### Task 55: SKILL.md — strengthen Iron Rule #7 + commit-gate prose for ingester

**Files:**
- Modify: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md` (Iron Rule #7 section, ingest step 12)

- [ ] **Step 1: Locate Iron Rule #7**

```bash
grep -n -A 5 "Never set \`.manifest.json\` \`origin\`" /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md
```
Expected: shows the rule (around line 380-390 in current SKILL.md).

- [ ] **Step 2: Strengthen Iron Rule #7 with empty-origin clause**

Edit `skills/karpathy-wiki/SKILL.md`. BEFORE (Iron Rule #7 body):

```markdown
7. **Never set `.manifest.json` `origin` to `"file"`, `"mixed"`, or the evidence type.** `origin` is the source-of-truth pointer for the raw file — the capture's `evidence` field value. If `evidence` is an absolute path, `origin` is that path. If `evidence` is the literal string `"conversation"`, `origin` is the literal string `"conversation"`. There is no third option. The clove-oil regression (Audit fix 2) happened because this distinction was fuzzy; now it is not.
```

AFTER:

```markdown
7. **Never set `.manifest.json` `origin` to `"file"`, `"mixed"`, the evidence type, the empty string, or a relative path.** `origin` is the source-of-truth pointer for the raw file — the capture's `evidence` field value. If `evidence` is an absolute path, `origin` is that path. If `evidence` is the literal string `"conversation"`, `origin` is the literal string `"conversation"`. There is no third option. Empty-origin (`""`) means the per-capture write of step 4 was skipped or failed — bail with a `## [...] reject |` log line rather than writing a manifest entry without provenance. The clove-oil regression (Audit fix 2) and the v2.2 copyparty/yazi empty-origin regression both trace to this distinction being fuzzy; now it is not. Run `python3 scripts/wiki-manifest.py validate "${WIKI_ROOT}"` to audit at any time.
```

- [ ] **Step 3: Locate ingest step 12 (Tier-1 lint at ingest)**

```bash
grep -n "Tier-1 lint at ingest" /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md
```
Expected: matches the section header (around line 328-348).

- [ ] **Step 4: Add commit-gate clause to ingest step 12**

Find the section "### Tier-1 lint at ingest (inline)" and the surrounding prose. BEFORE (the closing paragraph, around line 348):

```markdown
If the validator exits non-zero for any page, fix the mechanical issue and re-validate. Do NOT commit a wiki state where the validator fails.
```

AFTER:

```markdown
If the validator exits non-zero for any page, fix the mechanical issue and re-validate. Do NOT commit a wiki state where the validator fails. The ingester MUST NOT call `wiki-commit.sh` (step 11) until every touched page passes the validator. Audit Finding 04 traced 7 broken links to this gate being permissive: ingester logs showed `ingest |` entries with no validator-failure follow-up, meaning the success log fired before the validator was consulted (or its failure was ignored). Wire the validator's exit code into the commit decision; do not paper over it with a log line.
```

- [ ] **Step 5: Verify SKILL.md still under 500 lines**

```bash
wc -l /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md
```
Expected: ≤ 500. (Net change here is small — adds ~5 lines of prose but Task 51 reduced ~10.)

- [ ] **Step 6: Commit**

```bash
git add skills/karpathy-wiki/SKILL.md
git commit -m "feat(skill): strengthen Iron Rule #7 (empty origin) + commit-gate prose

Two prose tightenings backing Phase B's mechanical changes:
1. Iron Rule #7 now enumerates empty-string and relative-path origin as
   violations, in addition to the existing 'file'/'mixed'/evidence-type
   cases. References the new wiki-manifest.py validate subcommand.
2. Tier-1 lint section gates wiki-commit.sh on validator success.
   Audit Finding 04 traced 7 broken-link regressions to ingester
   skipping the gate."
```

---

## Phase B acceptance

- Validator skips code-block links (Finding 04 false positives gone).
- Manifest `validate` subcommand exists, catches empty / wrong-type / relative-path origins.
- SKILL.md Iron Rule #7 covers empty-origin case.
- SKILL.md ingest step 12 explicitly gates commit on validator success.
- All Phase B unit tests green.

```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/run-all.sh
```
Expected: `ALL PASS` across all unit tests.

---

## Phase C — Mechanism wiring (Findings 01, 03, 14)

### Task 56: Wire index.md threshold to fire schema-proposal capture (Finding 01)

**Files:**
- Modify: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md` (add ingest step 7.6)
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-index-threshold-fires.sh`

This task is prose-and-test only — there is no script invocation in step 7.6 because the ingester is itself a `claude -p` process executing prose. The test verifies the wiki ends up in the right state given a fixture.

- [ ] **Step 1: Write the failing test (fixture-based)**

Create `tests/unit/test-index-threshold-fires.sh`:

```bash
#!/bin/bash
# Test: a fixture wiki with index.md > 8 KB has a corresponding schema-proposal
# capture written by the ingest mechanism. We model the mechanism with an
# inline shell snippet that mirrors the SKILL.md step 7.6 prose; the real
# ingester is a `claude -p` process, but the mechanical contract is testable.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

tmp="$(mktemp -d)"
trap "rm -rf '${tmp}'" EXIT

mkdir -p "${tmp}/wiki/.wiki-pending/schema-proposals"
touch "${tmp}/wiki/.wiki-config"

# Fixture index.md at 9 KB (just over the 8 KB threshold).
python3 -c "
content = '# Wiki Index\n\n## Concepts\n'
# Each entry is roughly 100 bytes; 90 entries = ~9000 bytes.
for i in range(90):
    content += f'- [Page {i}](concepts/page-{i:03d}.md) — descriptive prose for entry {i:03d}\n'
open('${tmp}/wiki/index.md', 'w').write(content)
"

# Sanity: confirm size is > 8192.
size="$(wc -c < "${tmp}/wiki/index.md")"
if [[ ${size} -le 8192 ]]; then
  echo "FAIL: fixture index.md is ${size} bytes; expected > 8192"
  exit 1
fi

# Inline mechanism: mirrors the SKILL.md step 7.6 prose.
# A schema-proposal capture should exist in .wiki-pending/schema-proposals/
# only IF threshold is exceeded AND no recent (≤24h) such proposal exists.
INDEX_SIZE_THRESHOLD=8192
recent_proposal="$(find "${tmp}/wiki/.wiki-pending/schema-proposals" -name '*-index-split.md' -mtime -1 2>/dev/null | head -1)"
if [[ ${size} -gt ${INDEX_SIZE_THRESHOLD} && -z "${recent_proposal}" ]]; then
  ts="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
  cat > "${tmp}/wiki/.wiki-pending/schema-proposals/${ts}-index-split.md" <<EOF
---
title: "Schema proposal: split index.md (size threshold exceeded)"
captured_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
trigger: "index.md size = ${size} bytes (threshold ${INDEX_SIZE_THRESHOLD} bytes)"
---

index.md exceeded the orientation-degradation threshold. Recommended atom-ization:
- index/concepts.md
- index/entities.md
- index/queries.md
- index/ideas.md

index.md becomes a 5-line MOC pointing at each sub-index.
EOF
fi

# Assert exactly one schema-proposal capture exists.
proposals="$(find "${tmp}/wiki/.wiki-pending/schema-proposals" -name '*-index-split.md' | wc -l | tr -d ' ')"
if [[ "${proposals}" -ne 1 ]]; then
  echo "FAIL: expected 1 index-split proposal capture, got ${proposals}"
  exit 1
fi

echo "PASS: index.md > 8 KB triggers schema-proposal capture"
echo "ALL PASS"
```

- [ ] **Step 2: Run the test to verify it passes immediately**

```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-index-threshold-fires.sh
```
Expected: `PASS:` then `ALL PASS`. (The test embeds the mechanism inline; no SKILL.md change is needed for the test to pass. The SKILL.md addition in step 3 makes the contract reproducible by the actual ingester.)

- [ ] **Step 3: Add ingest step 7.6 to SKILL.md**

Locate the existing step 7.5 (missed-cross-link check). After it, insert a new step 7.6.

```bash
grep -n "^7.5\." /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md
```
Expected: matches the missed-cross-link section header.

Edit `skills/karpathy-wiki/SKILL.md`. AFTER the existing `7.5. **Missed-cross-link check.**` paragraph, insert:

```markdown
7.6. **Index size threshold check.** After updating `index.md` in step 7, measure its byte size:
   ```bash
   size="$(wc -c < "${WIKI_ROOT}/index.md")"
   ```
   If `size > 8192` AND no `*-index-split.md` capture exists in `.wiki-pending/schema-proposals/` with mtime within the last 24 hours, write a new schema-proposal capture (do NOT block ingest, do NOT split inline):
   ```bash
   if [[ ${size} -gt 8192 ]]; then
     recent="$(find "${WIKI_ROOT}/.wiki-pending/schema-proposals" -name '*-index-split.md' -mtime -1 2>/dev/null | head -1)"
     if [[ -z "${recent}" ]]; then
       ts="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
       cat > "${WIKI_ROOT}/.wiki-pending/schema-proposals/${ts}-index-split.md" <<EOF
   ---
   title: "Schema proposal: split index.md (size threshold exceeded)"
   captured_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
   trigger: "index.md size = ${size} bytes (threshold 8192 bytes)"
   ---

   index.md exceeded the orientation-degradation threshold. Recommended atom-ization: split into per-category sub-indexes (index/concepts.md, index/entities.md, index/queries.md, index/ideas.md), with index.md becoming a 5-line MOC pointing at each. Rationale: per-category matches existing wiki structure; agents reading index.md get cheap orientation and can drill down.
   EOF
     fi
   fi
   ```
   Audit Finding 01 surfaced index.md at 25 KB / 76 entries / ~12,500 tokens — over 3x the 8 KB ceiling and ~12x the Chroma Context Rot inflection point. The thresholds existed in prose but had no firing mechanism; this step closes the loop.
```

- [ ] **Step 4: Re-run the test to confirm it still passes**

```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-index-threshold-fires.sh
```
Expected: `PASS:` then `ALL PASS`.

- [ ] **Step 5: Verify SKILL.md still ≤ 500 lines**

```bash
wc -l /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md
```
Expected: ≤ 500.

- [ ] **Step 6: Commit**

```bash
git add skills/karpathy-wiki/SKILL.md tests/unit/test-index-threshold-fires.sh
git commit -m "feat(skill): wire index.md size threshold to schema-proposal (Finding 01)

Audit Finding 01: index.md is 25 KB (3x the 8 KB orientation-degradation
threshold the skill itself prescribes); the prose was correct but had no
firing mechanism, so the agent never authored a schema-proposal.

Adds ingest step 7.6: after updating index.md, measure size; if over 8 KB
AND no recent (≤24h) split proposal exists, write one. Recommended
atom-ization: per-category sub-indexes (index/concepts.md, etc.) with
index.md becoming a 5-line MOC.

Test fixture mirrors the mechanism inline (the real ingester is a 'claude
-p' process executing this prose; the test verifies the contract)."
```

---

### Task 57: Surface index-size warning in `wiki-status.sh`

**Files:**
- Modify: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-status.sh`
- Modify: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-status.sh` (add assertions)

- [ ] **Step 1: Locate the existing status output block**

```bash
sed -n '60,75p' /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-status.sh
```
Expected: the `cat <<EOF ... EOF` rendering block.

- [ ] **Step 2: Add index-size measurement to status script**

Edit `scripts/wiki-status.sh`. AFTER the `synonym_count="..."` block (around line 58, before the `cat <<EOF`):

BEFORE (the rendering block):

```bash
cat <<EOF
wiki: ${wiki}
role: ${role}
total pages: ${total_pages}
pending: ${pending}
processing: ${processing}
active locks: ${locks}
last ingest: ${last_ingest}
drift: ${drift}
git: ${git_status}
pages below 3.5 quality: ${below_35}
tag synonyms flagged: ${synonym_count}
EOF
```

AFTER:

```bash
# Index size (Finding 01 — surface warning when over 8 KB threshold)
index_size=0
index_warn=""
if [[ -f "${wiki}/index.md" ]]; then
  index_size="$(wc -c < "${wiki}/index.md" | tr -d ' ')"
  if [[ "${index_size}" -gt 8192 ]]; then
    index_kb=$(( (index_size + 512) / 1024 ))
    index_warn=" -- over 8 KB threshold; consider atom-ization"
    index_size="${index_kb} KB"
  else
    index_size="${index_size} bytes"
  fi
fi

cat <<EOF
wiki: ${wiki}
role: ${role}
total pages: ${total_pages}
pending: ${pending}
processing: ${processing}
active locks: ${locks}
last ingest: ${last_ingest}
drift: ${drift}
git: ${git_status}
pages below 3.5 quality: ${below_35}
tag synonyms flagged: ${synonym_count}
index.md: ${index_size}${index_warn}
EOF
```

- [ ] **Step 3: Update existing status test to allow the new line**

Open `tests/unit/test-status.sh` and check whether it greps for an exact line count or uses pattern matching. If exact count, add `index.md:` matchers; if pattern, no change needed.

```bash
cat /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-status.sh | head -60
```

If the test does an exact-output diff, add an `index.md:` assertion. If it greps for individual fields, add:

```bash
echo "${output}" | grep -q "^index.md:" || { echo "FAIL: status output missing index.md field"; exit 1; }
```

- [ ] **Step 4: Run existing status test to confirm green**

```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-status.sh
```
Expected: `ALL PASS`.

- [ ] **Step 5: Commit**

```bash
git add scripts/wiki-status.sh tests/unit/test-status.sh
git commit -m "feat(status): surface index.md size + over-threshold warning (Finding 01)

wiki-status.sh now reports 'index.md: <N> bytes' or 'index.md: <N> KB --
over 8 KB threshold; consider atom-ization' when the threshold is
breached. Pairs with ingest step 7.6 (Task 56): the schema-proposal fires
on ingest; the user sees the warning at any 'wiki status' check."
```

---

### Task 58: `wiki-status.sh` — read last-ingest from manifest (Finding 14)

**Files:**
- Modify: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-status.sh:25-28`
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-status-last-ingest.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test-status-last-ingest.sh`:

```bash
#!/bin/bash
# Test: wiki-status.sh reports last_ingest from the manifest, not log.md.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STATUS="${REPO_ROOT}/scripts/wiki-status.sh"

tmp="$(mktemp -d)"
trap "rm -rf '${tmp}'" EXIT

mkdir -p "${tmp}/wiki/raw" "${tmp}/wiki/.wiki-pending"
cat > "${tmp}/wiki/.wiki-config" <<'EOF'
role = "main"
created = "2026-04-22"
EOF

# Manifest claims last_ingested 2026-05-01.
cat > "${tmp}/wiki/.manifest.json" <<'EOF'
{
  "raw/foo.md": {
    "sha256": "abc",
    "origin": "conversation",
    "copied_at": "2026-04-24T12:00:00Z",
    "last_ingested": "2026-05-01T15:30:00Z",
    "referenced_by": []
  },
  "raw/bar.md": {
    "sha256": "def",
    "origin": "conversation",
    "copied_at": "2026-04-24T12:00:00Z",
    "last_ingested": "2026-04-24T12:00:00Z",
    "referenced_by": []
  }
}
EOF
echo "raw" > "${tmp}/wiki/raw/foo.md"
echo "raw" > "${tmp}/wiki/raw/bar.md"

# log.md has an OLDER date than the manifest's max — to prove status reads
# from the manifest, not from log.md.
cat > "${tmp}/wiki/log.md" <<'EOF'
# Wiki Log

## [2026-04-22] init | wiki created
EOF

output="$(bash "${STATUS}" "${tmp}/wiki" 2>&1 || true)"
if echo "${output}" | grep -q "^last ingest: 2026-05-01"; then
  echo "PASS: status reads last ingest from manifest (max last_ingested)"
else
  echo "FAIL: expected 'last ingest: 2026-05-01', output: ${output}"
  exit 1
fi

echo "ALL PASS"
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-status-last-ingest.sh
```
Expected: `FAIL: expected 'last ingest: 2026-05-01' ...` (current code reads from log.md and gets 2026-04-22).

- [ ] **Step 3: Modify status script — read last_ingested from manifest**

Edit `scripts/wiki-status.sh`. BEFORE (lines 25-28):

```bash
last_ingest="never"
if [[ -f "${wiki}/log.md" ]]; then
  last_ingest="$(grep -oE '^## \[[0-9]{4}-[0-9]{2}-[0-9]{2}\]' "${wiki}/log.md" | tail -1 | tr -d '[]# ')"
fi
```

AFTER:

```bash
last_ingest="never"
if [[ -f "${wiki}/.manifest.json" ]]; then
  last_ingest="$(python3 -c "
import json, sys
try:
    m = json.load(open('${wiki}/.manifest.json'))
    if not isinstance(m, dict) or not m:
        sys.exit(0)
    iso = max(
        v.get('last_ingested', '')
        for v in m.values()
        if isinstance(v, dict) and v.get('last_ingested')
    )
    print(iso[:10] if iso else '')
except Exception:
    pass
" 2>/dev/null)"
  [[ -z "${last_ingest}" ]] && last_ingest="never"
fi
```

- [ ] **Step 4: Run the new test to verify it passes**

```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-status-last-ingest.sh
```
Expected: `PASS:` then `ALL PASS`.

- [ ] **Step 5: Run existing status test for regression**

```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-status.sh
```
Expected: `ALL PASS`. Update fixture(s) if they assumed log-derived last_ingest.

- [ ] **Step 6: Commit**

```bash
git add scripts/wiki-status.sh tests/unit/test-status-last-ingest.sh
git commit -m "fix(status): read last ingest from manifest, not log.md (Finding 14)

Audit Finding 14: 'wiki status' reported 'last ingest: 2026-04-23' despite
30+ ingests on 2026-04-24. The script greps log.md for '## [YYYY-MM-DD]'
headings, but log.md uses full ISO timestamps in its actual ingest entries
('## [2026-04-24T17:45:00Z]') -- the date-only regex matched only legacy
'## [YYYY-MM-DD] init |' lines from wiki creation.

Fix: read max 'last_ingested' from .manifest.json (which the ingester
maintains as part of every successful ingest, per SKILL.md step 4)."
```

---

### Task 59: Verify `wiki_capture_archive` strips `.processing` (Finding 03)

**Files:**
- Modify: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-capture.sh:37-50` (or no change if already correct — see step 1)
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-archive-strips-processing.sh`

- [ ] **Step 1: Inspect current `wiki_capture_archive` behavior**

```bash
sed -n '37,50p' /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-capture.sh
```
Expected output (line 47 calls `basename "${processing}" .processing` which DOES strip the suffix). The helper IS correct as of v2.1; the 4 stuck `.md.processing` files in `~/wiki/.wiki-pending/archive/2026-04/` come from older versions. This task verifies-and-tests the helper, then Phase D backfills the 4 stuck files.

- [ ] **Step 2: Write the test that verifies the helper**

Create `tests/unit/test-archive-strips-processing.sh`:

```bash
#!/bin/bash
# Test: wiki_capture_archive strips .processing suffix when archiving.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

tmp="$(mktemp -d)"
trap "rm -rf '${tmp}'" EXIT

mkdir -p "${tmp}/wiki/.wiki-pending"
touch "${tmp}/wiki/.wiki-config"

# Create a fake .processing capture.
cat > "${tmp}/wiki/.wiki-pending/2026-04-24T12-00-00Z-foo.md.processing" <<'EOF'
---
title: "test"
---
body
EOF

# Source the lib + capture helpers.
source "${REPO_ROOT}/scripts/wiki-lib.sh"
source "${REPO_ROOT}/scripts/wiki-capture.sh"

# Set ingest log var so log_info doesn't try to walk the cwd.
WIKI_INGEST_LOG="${tmp}/wiki/.ingest.log"
export WIKI_INGEST_LOG

wiki_capture_archive "${tmp}/wiki" "${tmp}/wiki/.wiki-pending/2026-04-24T12-00-00Z-foo.md.processing"

# Assert: archive/YYYY-MM/2026-04-24T12-00-00Z-foo.md exists (no .processing).
date_dir="$(date +%Y-%m)"
expected="${tmp}/wiki/.wiki-pending/archive/${date_dir}/2026-04-24T12-00-00Z-foo.md"
if [[ ! -f "${expected}" ]]; then
  echo "FAIL: expected archived file at ${expected}"
  echo "Found: $(find "${tmp}/wiki/.wiki-pending/archive" -type f)"
  exit 1
fi

# Assert: no .processing file remains anywhere under .wiki-pending.
strays="$(find "${tmp}/wiki/.wiki-pending" -name '*.processing' | wc -l | tr -d ' ')"
if [[ "${strays}" -ne 0 ]]; then
  echo "FAIL: ${strays} .processing files remain after archive"
  exit 1
fi

echo "PASS: wiki_capture_archive strips .processing suffix"
echo "ALL PASS"
```

- [ ] **Step 3: Run the test — expected to PASS immediately (helper is correct)**

```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-archive-strips-processing.sh
```
Expected: `PASS:` then `ALL PASS`.

If the test FAILS, the helper has regressed — fix it (the canonical implementation strips suffix via `basename "${processing}" .processing`).

- [ ] **Step 4: Tighten SKILL.md prose for step 10 to make the contract explicit**

```bash
grep -n "Archive the capture from .processing" /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md
```
Expected: matches the step 10 prose (around line 324).

Edit `skills/karpathy-wiki/SKILL.md`. BEFORE (step 10):

```markdown
10. **Archive the capture** from `.processing` to `.wiki-pending/archive/YYYY-MM/`: `wiki_capture_archive "${WIKI_ROOT}" "${WIKI_CAPTURE}"`.
```

AFTER:

```markdown
10. **Archive the capture** from `.processing` to `.wiki-pending/archive/YYYY-MM/`: `wiki_capture_archive "${WIKI_ROOT}" "${WIKI_CAPTURE}"`. The helper strips the `.processing` suffix on rename, so archived basenames end in `.md`. Audit Finding 03 surfaced 4 legacy archive files still carrying `.md.processing` from older code paths; Phase D of v2.2 backfilled them.
```

- [ ] **Step 5: Verify SKILL.md still ≤ 500 lines**

```bash
wc -l /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md
```
Expected: ≤ 500.

- [ ] **Step 6: Commit**

```bash
git add tests/unit/test-archive-strips-processing.sh skills/karpathy-wiki/SKILL.md
git commit -m "test(archive): assert wiki_capture_archive strips .processing (Finding 03)

The helper at scripts/wiki-capture.sh:47 already strips the .processing
suffix correctly (basename ... .processing). This test pins that
contract so future refactors can't silently re-introduce the bug.

The 4 archived .md.processing files surfaced by audit Finding 03 come
from older code paths predating the fix; they are backfilled in Phase D's
migration script.

SKILL.md step 10 prose tightened to explicitly state the suffix is
stripped, citing the audit-finding context."
```

---

## Phase C acceptance

- Index threshold fires schema-proposal capture on ingest (verified by fixture test).
- `wiki status` surfaces index-size warning when over threshold.
- `wiki status` reads last-ingest from manifest, not log.md.
- `wiki_capture_archive` strips `.processing` suffix (verified by test; helper already correct).
- All Phase C unit tests green.

```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/run-all.sh
```
Expected: `ALL PASS`.

---

## Phase D — Live wiki migration

One script does all backfills. Backup tarball first.

### Task 60: Build `wiki-migrate-v2.2.sh` migration script

**Files:**
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-migrate-v2.2.sh`
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-migrate-v2.2.sh`

- [ ] **Step 1: Write the failing test**

Create `tests/unit/test-migrate-v2.2.sh`:

```bash
#!/bin/bash
# Test: wiki-migrate-v2.2.sh in --dry-run mode lists every mutation it WOULD
# perform, given a fixture wiki that mirrors the v2.2 audit's findings.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MIGRATE="${REPO_ROOT}/scripts/wiki-migrate-v2.2.sh"

tmp="$(mktemp -d)"
trap "rm -rf '${tmp}'" EXIT

# Fixture: minimal wiki with each Phase D mutation target represented.
mkdir -p "${tmp}/wiki/concepts" \
         "${tmp}/wiki/sources" \
         "${tmp}/wiki/raw" \
         "${tmp}/wiki/.wiki-pending/archive/2026-04"
touch "${tmp}/wiki/.wiki-config"

# 1. Sources/ pages to delete.
echo "stub" > "${tmp}/wiki/sources/2026-04-24-foo.md"
echo "stub" > "${tmp}/wiki/sources/2026-04-24-bar.md"

# 2. A concept page citing sources/ in frontmatter (will be rewritten).
cat > "${tmp}/wiki/concepts/foo.md" <<'EOF'
---
title: "Foo"
type: concept
sources:
  - sources/2026-04-24-foo.md
---
body
EOF

# 3. A concept page with a body link to sources/ (will be cleaned).
cat > "${tmp}/wiki/concepts/bar.md" <<'EOF'
---
title: "Bar"
type: concept
sources:
  - raw/2026-04-24-bar.md
---
See [the source](../sources/2026-04-24-bar.md) for details.
EOF

# 4. starship-style same-dir-prefix-bug links.
cat > "${tmp}/wiki/concepts/starship.md" <<'EOF'
---
title: "Starship"
type: concept
sources:
  - "conversation"
---
- [Cyberpunk](concepts/cyberpunk.md)
- [Zellij](concepts/zellij.md)
EOF
echo "stub" > "${tmp}/wiki/concepts/cyberpunk.md"
echo "stub" > "${tmp}/wiki/concepts/zellij.md"

# 5. Manifest with empty-origin entries.
cat > "${tmp}/wiki/.manifest.json" <<'EOF'
{
  "raw/2026-04-24-bar.md": {
    "sha256": "x",
    "origin": "",
    "copied_at": "2026-04-24T12:00:00Z",
    "last_ingested": "2026-04-24T12:00:00Z",
    "referenced_by": []
  }
}
EOF
echo "raw" > "${tmp}/wiki/raw/2026-04-24-bar.md"

# 6. Archive .md.processing legacy files.
echo "stub" > "${tmp}/wiki/.wiki-pending/archive/2026-04/2026-04-24T12-00-00Z-old.md.processing"

# Run dry-run; capture output.
output="$(bash "${MIGRATE}" --dry-run "${tmp}/wiki" 2>&1)"
rc=$?
if [[ ${rc} -ne 0 ]]; then
  echo "FAIL: --dry-run exited ${rc}. Output: ${output}"
  exit 1
fi

# Assert each migration is announced in dry-run output.
for needle in \
  "would-remove sources/2026-04-24-foo.md" \
  "would-remove sources/2026-04-24-bar.md" \
  "would-rewrite concepts/foo.md sources: sources/ -> raw/" \
  "would-rewrite concepts/bar.md body-link sources/" \
  "would-fix-prefix concepts/starship.md" \
  "would-set-origin raw/2026-04-24-bar.md = conversation" \
  "would-rename .wiki-pending/archive/2026-04/2026-04-24T12-00-00Z-old.md.processing -> .md"; do
  if ! echo "${output}" | grep -q "${needle}"; then
    echo "FAIL: dry-run missing announcement: ${needle}"
    echo "Output was:"
    echo "${output}"
    exit 1
  fi
done

# Assert dry-run did NOT mutate anything.
[[ -f "${tmp}/wiki/sources/2026-04-24-foo.md" ]] || { echo "FAIL: dry-run deleted file"; exit 1; }
[[ "$(grep -c 'sources/2026-04-24-foo' "${tmp}/wiki/concepts/foo.md")" -eq 1 ]] || { echo "FAIL: dry-run rewrote frontmatter"; exit 1; }

echo "PASS: --dry-run announces every mutation without mutating"

# Now run for real.
bash "${MIGRATE}" "${tmp}/wiki" >/dev/null 2>&1

# Assert outcomes.
[[ ! -d "${tmp}/wiki/sources" ]] || [[ -z "$(ls -A "${tmp}/wiki/sources" 2>/dev/null)" ]] || { echo "FAIL: sources/ not removed"; ls "${tmp}/wiki/sources"; exit 1; }
grep -q '^  - raw/2026-04-24-foo.md' "${tmp}/wiki/concepts/foo.md" || { echo "FAIL: concepts/foo.md frontmatter not rewritten"; cat "${tmp}/wiki/concepts/foo.md"; exit 1; }
! grep -q 'sources/' "${tmp}/wiki/concepts/bar.md" || { echo "FAIL: concepts/bar.md body still references sources/"; cat "${tmp}/wiki/concepts/bar.md"; exit 1; }
grep -q '^- \[Cyberpunk\](cyberpunk.md)' "${tmp}/wiki/concepts/starship.md" || { echo "FAIL: starship.md prefix not fixed"; cat "${tmp}/wiki/concepts/starship.md"; exit 1; }
grep -q '"origin": "conversation"' "${tmp}/wiki/.manifest.json" || { echo "FAIL: manifest origin not set"; cat "${tmp}/wiki/.manifest.json"; exit 1; }
[[ -f "${tmp}/wiki/.wiki-pending/archive/2026-04/2026-04-24T12-00-00Z-old.md" ]] || { echo "FAIL: archive .processing not renamed"; ls "${tmp}/wiki/.wiki-pending/archive/2026-04"; exit 1; }
[[ ! -f "${tmp}/wiki/.wiki-pending/archive/2026-04/2026-04-24T12-00-00Z-old.md.processing" ]] || { echo "FAIL: archive .processing still present after rename"; exit 1; }

echo "PASS: live run applied every migration correctly"
echo "ALL PASS"
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-migrate-v2.2.sh
```
Expected: `FAIL` because the migration script does not yet exist.

- [ ] **Step 3: Write the migration script**

Create `scripts/wiki-migrate-v2.2.sh`:

```bash
#!/bin/bash
# wiki-migrate-v2.2.sh — apply v2.2 hardening to a live wiki.
#
# Usage:
#   wiki-migrate-v2.2.sh <wiki_root>            # apply
#   wiki-migrate-v2.2.sh --dry-run <wiki_root>  # report only
#
# Mutations performed:
#   1. Remove sources/ category (every file inside).
#   2. Rewrite any concept-page sources: frontmatter that points at
#      sources/<basename>.md to point at raw/<basename>.md instead.
#   3. Strip body-prose markdown links to sources/ pages.
#   4. Fix same-dir-prefix-bug links (e.g. concept page links to
#      "concepts/foo.md" when the linker also lives in concepts/).
#   5. Set origin = "conversation" on manifest entries with empty origin.
#   6. Rename archive/*.md.processing files to *.md.

set -uo pipefail

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=1
  shift
fi

wiki="${1:-}"
[[ -n "${wiki}" ]] || { echo >&2 "usage: $0 [--dry-run] <wiki_root>"; exit 1; }
[[ -d "${wiki}" ]] || { echo >&2 "not a directory: ${wiki}"; exit 1; }
[[ -f "${wiki}/.wiki-config" ]] || { echo >&2 "not a wiki: ${wiki}"; exit 1; }

say() { echo "$@"; }

# 1. Remove sources/ category.
migrate_remove_sources_category() {
  if [[ -d "${wiki}/sources" ]]; then
    while IFS= read -r f; do
      rel="${f#${wiki}/}"
      if (( DRY_RUN )); then
        say "would-remove ${rel}"
      else
        rm -- "${f}"
      fi
    done < <(find "${wiki}/sources" -type f -name "*.md")
    if (( ! DRY_RUN )); then
      rmdir "${wiki}/sources" 2>/dev/null || true
    fi
  fi
}

# 2. Rewrite frontmatter sources: lines pointing at sources/<x>.md → raw/<x>.md.
migrate_rewrite_frontmatter_sources() {
  while IFS= read -r f; do
    if grep -qE '^  - sources/' "${f}"; then
      rel="${f#${wiki}/}"
      if (( DRY_RUN )); then
        say "would-rewrite ${rel} sources: sources/ -> raw/"
      else
        # In-place sed; portable form (works on BSD + GNU).
        python3 - "${f}" <<'PY'
import sys, re
path = sys.argv[1]
text = open(path).read()
text = re.sub(r'^(  - )sources/', r'\1raw/', text, flags=re.MULTILINE)
open(path, 'w').write(text)
PY
      fi
    fi
  done < <(find "${wiki}/concepts" "${wiki}/entities" "${wiki}/ideas" "${wiki}/queries" -type f -name "*.md" 2>/dev/null)
}

# 3. Strip body-prose markdown links to sources/ pages.
#    Heuristic: remove the entire markdown link [text](path) where path
#    contains 'sources/'. Keep the surrounding prose.
migrate_strip_body_sources_links() {
  while IFS= read -r f; do
    if grep -qE '\]\([^)]*sources/' "${f}"; then
      rel="${f#${wiki}/}"
      if (( DRY_RUN )); then
        say "would-rewrite ${rel} body-link sources/"
      else
        python3 - "${f}" <<'PY'
import sys, re
path = sys.argv[1]
text = open(path).read()
# Match [...](path-containing-sources/...) and replace with the link text only.
text = re.sub(r'\[([^\]]*)\]\([^)]*sources/[^)]*\)', r'\1', text)
open(path, 'w').write(text)
PY
      fi
    fi
  done < <(find "${wiki}/concepts" "${wiki}/entities" "${wiki}/ideas" "${wiki}/queries" -type f -name "*.md" 2>/dev/null)
}

# 4. Fix same-dir-prefix-bug links.
#    Heuristic: in concepts/X.md, a link target like "concepts/Y.md" is
#    wrong (should be "Y.md"). Apply per category.
migrate_fix_same_dir_prefix_links() {
  for category in concepts entities ideas queries; do
    [[ -d "${wiki}/${category}" ]] || continue
    while IFS= read -r f; do
      if grep -qE "\]\(${category}/" "${f}"; then
        rel="${f#${wiki}/}"
        if (( DRY_RUN )); then
          say "would-fix-prefix ${rel}"
        else
          python3 - "${f}" "${category}" <<'PY'
import sys, re
path, cat = sys.argv[1], sys.argv[2]
text = open(path).read()
text = re.sub(rf'\]\({re.escape(cat)}/', '](', text)
open(path, 'w').write(text)
PY
        fi
      fi
    done < <(find "${wiki}/${category}" -type f -name "*.md")
  done
}

# 5. Manifest empty-origin → "conversation" backfill.
migrate_manifest_empty_origin() {
  local manifest="${wiki}/.manifest.json"
  [[ -f "${manifest}" ]] || return 0
  while IFS= read -r key; do
    if (( DRY_RUN )); then
      say "would-set-origin ${key} = conversation"
    fi
  done < <(python3 -c "
import json
m = json.load(open('${manifest}'))
for k, v in m.items():
    if isinstance(v, dict) and v.get('origin', '') == '':
        print(k)
")
  if (( ! DRY_RUN )); then
    python3 - "${manifest}" <<'PY'
import json, sys
path = sys.argv[1]
m = json.load(open(path))
changed = False
for k, v in m.items():
    if isinstance(v, dict) and v.get('origin', '') == '':
        v['origin'] = 'conversation'
        changed = True
if changed:
    open(path, 'w').write(json.dumps(m, indent=2) + '\n')
PY
  fi
}

# 6. Rename archive/*.md.processing → *.md.
migrate_archive_processing_suffix() {
  while IFS= read -r f; do
    rel="${f#${wiki}/}"
    new="${f%.processing}"
    new_rel="${new#${wiki}/}"
    if (( DRY_RUN )); then
      say "would-rename ${rel} -> .md"
    else
      mv -- "${f}" "${new}"
    fi
  done < <(find "${wiki}/.wiki-pending/archive" -type f -name "*.processing" 2>/dev/null)
}

main() {
  migrate_remove_sources_category
  migrate_rewrite_frontmatter_sources
  migrate_strip_body_sources_links
  migrate_fix_same_dir_prefix_links
  migrate_manifest_empty_origin
  migrate_archive_processing_suffix
  if (( DRY_RUN )); then
    say ""
    say "(dry-run complete; no files modified)"
  fi
}

main
```

Make it executable:

```bash
chmod +x /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-migrate-v2.2.sh
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-migrate-v2.2.sh
```
Expected: `PASS: --dry-run announces every mutation without mutating` then `PASS: live run applied every migration correctly` then `ALL PASS`.

- [ ] **Step 5: Run all unit tests for regression**

```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/run-all.sh
```
Expected: `ALL PASS`.

- [ ] **Step 6: Commit**

```bash
git add scripts/wiki-migrate-v2.2.sh tests/unit/test-migrate-v2.2.sh
git commit -m "feat(migrate): wiki-migrate-v2.2.sh for live wiki backfill (Phase D)

Single-script migration with --dry-run flag. Six named functions, each
addressing one Phase D mutation:

1. migrate_remove_sources_category — git rm sources/ (Phase A live cut)
2. migrate_rewrite_frontmatter_sources — sources: sources/x -> raw/x
3. migrate_strip_body_sources_links — drop [text](sources/x.md) links
4. migrate_fix_same_dir_prefix_links — fix concept page links of form
   concepts/foo.md when the linker is also in concepts/ (Finding 04)
5. migrate_manifest_empty_origin — set origin: conversation on empty
   entries (Finding 06 backfill of copyparty + yazi)
6. migrate_archive_processing_suffix — rename legacy .md.processing in
   archive/ to .md (Finding 03)

Test fixture mirrors all 6 mutation targets; --dry-run is asserted to be
read-only; live run is asserted to produce the expected end state."
```

---

### Task 61: Backup the live wiki, run dry-run, run migration

**Files:** None created. Live wiki + backup tarball.

- [ ] **Step 1: Create backup tarball**

```bash
ts="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
tar czf "${HOME}/wiki-backup-pre-v2.2-${ts}.tar.gz" -C "${HOME}" wiki
ls -lh "${HOME}/wiki-backup-pre-v2.2-${ts}.tar.gz"
```
Expected: tarball file ~hundreds of KB to a few MB.

- [ ] **Step 2: Run the migration in `--dry-run` mode**

```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-migrate-v2.2.sh --dry-run /Users/lukaszmaj/wiki
```
Expected announcements (paraphrased):
- 31 `would-remove sources/...` lines
- 3 `would-rewrite concepts/... sources: sources/ -> raw/` lines
- 3 `would-rewrite concepts/... body-link sources/` lines
- 1 `would-fix-prefix concepts/starship-terminal-theming.md` line
- 2 `would-set-origin raw/...` lines (copyparty + yazi)
- 4 `would-rename .wiki-pending/archive/2026-04/...` lines

Total: ~44 announcements. Inspect the list against your own expectations before proceeding.

- [ ] **Step 3: Run the migration live**

```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-migrate-v2.2.sh /Users/lukaszmaj/wiki
```
Expected: silent (no `say` calls in non-dry-run paths). Exit 0.

- [ ] **Step 4: Verify with `wiki-manifest.py validate`**

```bash
python3 /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-manifest.py validate /Users/lukaszmaj/wiki
echo "Exit: $?"
```
Expected: no output to stderr; exit 0.

- [ ] **Step 5: Run validator over every page in the live wiki**

```bash
fail=0
for page in $(find /Users/lukaszmaj/wiki/concepts /Users/lukaszmaj/wiki/entities /Users/lukaszmaj/wiki/ideas /Users/lukaszmaj/wiki/queries -type f -name "*.md" 2>/dev/null); do
  if ! python3 /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-validate-page.py --wiki-root /Users/lukaszmaj/wiki "${page}" 2>/dev/null; then
    fail=$((fail + 1))
    python3 /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-validate-page.py --wiki-root /Users/lukaszmaj/wiki "${page}"
  fi
done
echo "Total failures: ${fail}"
```
Expected: `Total failures: 0`.

- [ ] **Step 6: Spot-check the live wiki state**

```bash
ls /Users/lukaszmaj/wiki/sources/ 2>&1 | head -5
echo "---"
grep -A 1 '^sources:' /Users/lukaszmaj/wiki/concepts/yazi-install-gotchas.md | head -3
echo "---"
python3 -c "
import json
m = json.load(open('/Users/lukaszmaj/wiki/.manifest.json'))
print('empty origins:', sum(1 for v in m.values() if v.get('origin', '') == ''))
print('total entries:', len(m))
"
echo "---"
find /Users/lukaszmaj/wiki/.wiki-pending/archive -name "*.processing" | wc -l
```
Expected:
- `sources/` either missing or empty (`No such file or directory` or empty `ls` output).
- yazi page sources line shows `raw/2026-04-24-yazi-install-gotchas.md` (or similar — depends on rewrite path).
- `empty origins: 0`, `total entries: <unchanged>`.
- `0` archive `.processing` files.

- [ ] **Step 7: Commit the live wiki state**

```bash
cd /Users/lukaszmaj/wiki
git add -A
git commit -m "v2.2 migration: remove sources/, repair manifest, backfill archive

Applied via scripts/wiki-migrate-v2.2.sh. Mutations:
- Removed 31 sources/ pointer pages (architectural cut, audit Findings 02/05/09)
- Rewrote 3 concept pages' sources: frontmatter (sources/ -> raw/)
- Stripped 3 concept pages' body links to sources/ pages
- Fixed 2 same-dir-prefix-bug links in concepts/starship-terminal-theming.md
- Set origin: conversation on 2 manifest entries (copyparty, yazi-install)
- Renamed 4 archive .md.processing files to .md (Finding 03 legacy backfill)

Backup tarball: ~/wiki-backup-pre-v2.2-<ts>.tar.gz"
cd -
```

- [ ] **Step 8: Re-run wiki status to confirm health**

```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-status.sh /Users/lukaszmaj/wiki
```
Expected: `last ingest:` shows recent ISO date (from manifest), `index.md:` shows current size + warning (still over 8 KB until atom-ization in v2.3), `drift: CLEAN`.

- [ ] **Step 9: Trigger one ingest-step-7.6 fire by hand for the existing index.md state**

The existing index.md is over 8 KB but no ingest has fired since the threshold was wired. Drop one schema-proposal capture by hand to bootstrap the proposal queue:

```bash
ts="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
size="$(wc -c < /Users/lukaszmaj/wiki/index.md | tr -d ' ')"
mkdir -p /Users/lukaszmaj/wiki/.wiki-pending/schema-proposals
cat > "/Users/lukaszmaj/wiki/.wiki-pending/schema-proposals/${ts}-index-split.md" <<EOF
---
title: "Schema proposal: split index.md (size threshold exceeded)"
captured_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
trigger: "index.md size = ${size} bytes (threshold 8192 bytes); v2.2 backfill"
---

index.md exceeded the orientation-degradation threshold. Recommended atom-ization: split into per-category sub-indexes (index/concepts.md, index/entities.md, index/queries.md, index/ideas.md), with index.md becoming a 5-line MOC pointing at each. Rationale: per-category matches existing wiki structure; agents reading index.md get cheap orientation and can drill down.
EOF
ls "/Users/lukaszmaj/wiki/.wiki-pending/schema-proposals/${ts}-index-split.md"
```

- [ ] **Step 10: Final repo commit (v2.2 acceptance)**

```bash
cd /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki
git status
git log --oneline v2-rewrite | head -20
```
Confirm v2.2 task commits (50-61) are present. The v2.2 plan is complete on the `v2-rewrite` branch; do NOT push or merge — that's the user's call.

---

## Phase D acceptance

- `~/wiki/sources/` removed.
- All concept-page `sources:` refs to `sources/...` rewritten.
- All body links to `sources/` pages cleaned.
- 2 same-dir-prefix-bug links fixed.
- 2 manifest entries repaired.
- 4 archived `.md.processing` files renamed.
- Validator passes on every page in `~/wiki/`.
- `wiki-manifest.py validate` passes.
- One schema-proposal capture for index.md split exists.

---

## Plan acceptance

- All four phases complete.
- `bash tests/run-all.sh` green.
- Live `~/wiki/` validates clean.
- All v2.2 commits (Tasks 50-61) on `v2-rewrite`.
- TODO.md updated: "Re-run the Opus auditor" item moved to Shipped section, with `shipped_in: <commit-sha-of-Task-61>`.

Final acceptance is task 62.

### Task 62: Update TODO.md — mark audit re-run as shipped

**Files:**
- Modify: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/TODO.md`

- [ ] **Step 1: Locate the relevant TODO entry**

```bash
grep -n "Re-run the Opus auditor" /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/TODO.md
```
Expected: matches the section header.

- [ ] **Step 2: Move the entry to the Shipped section**

Edit `TODO.md`. Cut the entire `## Re-run the Opus auditor after real-session usage accumulates` section (header + frontmatter + body). Paste it under the `# Shipped` heading at the bottom. Update its frontmatter:

BEFORE:

```yaml
status: deferred
priority: p1
```

AFTER:

```yaml
status: shipped
priority: p1
shipped_in: <git-sha-of-Task-61-commit>
```

To get the SHA:

```bash
git log --oneline v2-rewrite | grep -i "v2.2 migration" | head -1 | awk '{print $1}'
```

- [ ] **Step 3: Update `last_reviewed` date**

In TODO.md frontmatter:

BEFORE:

```yaml
last_reviewed: 2026-04-24
```

AFTER:

```yaml
last_reviewed: 2026-04-24  # post-v2.2 ship; next audit due after 5-10 more real-session ingests
```

- [ ] **Step 4: Commit**

```bash
git add TODO.md
git commit -m "docs(TODO): mark audit re-run as shipped (v2.2)

The Opus auditor re-run TODO item shipped via the v2.2 audit + plan +
implementation. Moved to Shipped section with the Phase D migration
commit SHA. Next audit revisit criteria reset to '5-10 more real-session
ingests'."
```

---

## Self-review checklist (run before handoff)

Performed inline during plan write-up:

1. **Spec coverage:** Every spec section has a task.
   - Phase A architectural cut → Tasks 50, 51, 52 ✓
   - Phase B validator/ingester safety → Tasks 53, 54, 55 ✓
   - Phase C mechanism wiring → Tasks 56, 57, 58, 59 ✓
   - Phase D migration → Tasks 60, 61 ✓
   - TODO update → Task 62 ✓

2. **Placeholder scan:** Searched for "TBD", "TODO", "fill in", "Add appropriate", "similar to". None found in plan body. (One TODO mention in Task 62 is a file-name reference, not a placeholder.)

3. **Type/method consistency:** `cmd_validate` (Task 54) called with `wiki_root: Path` matches dispatcher signature. `wiki_capture_archive` (Task 59) signature matches `wiki-capture.sh:37`. `_extract_body_links` signature unchanged (Task 53). `VALID_TYPES` set referenced consistently as `{"concept", "entity", "query"}` after Task 50.

4. **Path correctness:** All paths absolute. Repo paths under `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/`. Live wiki paths under `/Users/lukaszmaj/wiki/`. Skill resolves via the symlink at `~/.claude/skills/karpathy-wiki/`.

5. **Order safety:** Task 50 (drop `type: source`) before Task 51 (SKILL.md drops mentions) — correct order: validator first, then docs. Task 52 (schema.md edit) Phase A — happens before Phase D mutations. Task 60 (build migration) before Task 61 (run it) — correct.

6. **Risk: Task 61 step 5 validator-over-everything could fail because the live wiki has historic-but-untouched issues.** Mitigation: pre-Phase-D validator failures are surfaced by the audit's existing list (5 broken-link issues, all in `sources/` pages or covered by Phase B/D fixes). After Task 61, the only candidates for remaining failures are pages we didn't touch. If any surface, surface to user; do not auto-fix.

---

End of plan.
