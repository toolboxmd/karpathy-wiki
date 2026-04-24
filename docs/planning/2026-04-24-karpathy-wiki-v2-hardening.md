# Karpathy Wiki v2 Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. This plan **extends** the v2 plan at `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/docs/planning/2026-04-22-karpathy-wiki-v2.md` — it continues the task numbering (starts at Task 30) and reuses every discipline convention from it (Files block, RED-GREEN-REFACTOR, verbatim script bodies, verbatim test bodies, verbatim commit messages).

**Goal:** Close the 10 integrity/quality/consistency gaps the post-v2 real-session audit surfaced. Turn the shipped-but-leaky v2 wiki into a trustworthy one by making the tool enforce its own spec (manifest consolidation + sha256, origin tracking, frontmatter normalization, quality ratings, tag-drift, missed-cross-link, source-pointer completeness) and fixing three specific data-quality mistakes in the live `~/wiki/`.

**Branch:** `v2-rewrite` (plan work continues here; hardening is part of "v2 shippable" before any merge or tag). Do NOT push, merge, or tag — those are user decisions per existing autonomy bounds.

**Working directory:** `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/`

**Live wiki target for backfill:** `$HOME/wiki/` (i.e. `/Users/lukaszmaj/wiki/`)

---

## Fixes motivating this plan

These 10 fixes come from a real-session audit of the shipped-v2 wiki. They are the contract this plan fulfills. Reproduced verbatim from the audit:

1. **Fix the manifest: add `sha256` to every raw file, consolidate to one manifest, repair the `lpa-robotics-action-tokenization.md` dead reference.** Without sha256, drift detection is dead. Two competing manifest files exist right now (`~/wiki/.manifest.json` and `~/wiki/raw/.manifest.json`) with different schemas. They must become ONE manifest. [SKILL.md change + one-time backfill script]

2. **Fix the origin-loss bug in the ingester.** `2026-04-24-clove-oil-dental.md` has `origin: "conversation"` when the evidence file was real and on disk. The ingester must record the `evidence` field value as `origin`, not the `evidence_type`. Enforce via validator. [SKILL.md change + validator rule]

3. **Add the 4-dimensional rating frontmatter and ingester self-rating step.** Every concept/entity/source/query page gets a `quality:` block with `accuracy`, `completeness`, `signal`, `interlinking` (each 1-5), `overall`, `rated_at`, `rated_by` (ingester|doctor|human), optional `notes`. Ingester self-rates with cheap model at ingest step 6.5 (after merge, before index update). `wiki doctor` re-rates with smart model, NEVER clobbers `rated_by: human`. Surface ratings in `index.md`. Add a Tier-2 lint: `wiki status` reports "N pages below 3.5 — run `wiki doctor`". [SKILL.md change + new behavior + index rendering]

4. **Implement a tag-drift lint** (`scripts/wiki-lint-tags.py`). Every new tag an ingester proposes must match existing tags or trigger a `schema-proposal/` capture. Detect synonyms (e.g., `dentistry` vs `dental` both exist now). Nightly Tier-2 via `wiki status`. [New script + SKILL.md change]

5. **Make source-pointer pages mandatory.** Only 1 of 4 raw files currently has a `sources/` summary page. Either every raw file gets a source pointer or the category is redundant. Plan chooses: every raw file MUST have a matching `sources/<raw-basename>.md`. Validator enforces. Backfill missing ones. [SKILL.md change + validator rule + backfill]

6. **Add a missed-cross-link check at ingest.** Tier-1 inline lint currently only checks "every markdown link resolves." Strengthen to also ask: "given this page's content, which existing wiki pages obviously should be linked and aren't?" Asked cheap model at ingest step 7.5 (after index update, before log append). [SKILL.md change — model-judgment behavior, test via GREEN fixture]

7. **Normalize frontmatter schema across all pages.** Every page must have `title, type, tags, sources, created, updated, quality`. Dates in full ISO-8601 (`2026-04-24T13:00:00Z`, not `2026-04-24`). `sources:` is a flat YAML list of strings, no nested maps. `type:` is one of: `concept, entity, source, query`. Run one-time backfill to normalize existing pages. Enforce via validator for future ingests. [SKILL.md change + validator + backfill]

8. **Ingest the missed file: `/Users/lukaszmaj/dev/bigbrain/research/2026-04-24-sensitive-teeth-toothpaste.md`.** Complementary content to the dentin-hypersensitivity page. Not done automatically by the skill; plan includes it as an explicit one-time task: the user (or the implementer, as a fixture validation) writes a capture file that references this raw, spawns the ingester, observes the result. [One-time content action]

9. **Prune or promote `entities/electron-nwjs-steam-wrapper.md`.** Currently duplicates the concept page. Either cut to a link-only stub, or add unique content (versions, integration gotchas, release timeline). Plan proposes cutting to stub since the entity-vs-concept line isn't earning its keep. [One-time content edit]

10. **Add a `personal` / `n-of-1` tag for patient-specific anecdotes.** Current dentin-hypersensitivity page mixes clinical data with a user-specific 10-year tolerance anecdote, framed as clinical signal. Add the tag to the bounded taxonomy in `schema.md`, re-tag the existing page. [Schema change + content edit]

---

## Deliberate scope cuts for v2.1-hardening

These items are NOT in scope. Implementers must not expand scope.

- **`wiki doctor` implementation remains a stub** in `bin/wiki`. The rating re-rate behavior of doctor is specified in SKILL.md prose (fix 3) so the future implementation has a contract to hit, but the command itself still exits 1 with "not implemented." Extracting doctor logic into `scripts/wiki-doctor.sh` is post-hardening.
- **No multi-wiki federation.** Project-wiki propagation prose stays exactly as v2 left it. No changes.
- **No UI, no dashboard, no web renderer.**
- **No Gemini / Codex / OpenCode / Cursor sidecars.** Still Claude-Code-only.
- **No vector search, no embeddings, no BM25 index.** Ratings are surfaced via plain markdown in `index.md`.
- **No auto-migration of the existing log.md prose format.** `log.md` stays append-only prose; only per-page YAML frontmatter is normalized by the backfill.
- **No cross-wiki propagation for the new fields.** If the user ever creates a project wiki, it will use the new schema from init — there are no existing project wikis to migrate.
- **No perf hardening** (fsync batching, parallel hash on backfill). Hardening is correctness, not speed.
- **No test coverage for model-judgment behaviors** beyond the single GREEN scenario 4 for missed-cross-link. Tag-drift synonym logic IS unit-tested because it's pure string algorithms; missed-cross-link IS NOT because it requires a real LLM call.
- **No Stop hook transcript sweep** — still a stub per v2. The rating self-rate happens inside the ingester, not via stop sweep.
- **No auto-fix for quality ratings below 3.5.** `wiki status` reports them; `wiki doctor` (stubbed) would re-rate them. That's it.

---

## Read before starting

Implementer subagents MUST read these files end-to-end before starting any task in this plan:

1. `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/docs/planning/2026-04-22-karpathy-wiki-v2.md` — the v2 plan this one extends; contains task numbering convention, style rules, commit-message rules, the existing test patterns every new test must emulate.
2. `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/docs/planning/karpathy-wiki-v2-design.md` — design rationale; explains why raw/ is hash-tracked but wiki pages are not, why the manifest is JSON not TOML, why `.wiki-config` is TOML.
3. `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md` — the v1 skill; the target of most edits in this plan. 263 lines. Current budget headroom: ~230 lines before the 500-line superpowers limit.
4. `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-manifest.py` — existing manifest tool; new validator and new migration script follow its style: `argparse`-free thin `main()`, stdlib-only, `pathlib.Path`, exit codes, print-to-stderr on error. 111 lines.
5. `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-lib.sh` — shared bash helpers; new shell scripts source this and reuse `log_info / log_warn / log_error / slugify / wiki_root_from_cwd / wiki_config_get`.
6. `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-init.sh` — existing init; style model for the new migration script (set -e, python version check, idempotent, logs to stderr, exits with clear message).
7. `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-status.sh` — existing status; must be extended (not replaced) by Task 36 for the quality-rollup report.
8. `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-manifest.sh` — canonical unit-test style: setup/teardown, PASS/FAIL prefixed lines, `ALL PASS` final line, one exit-1 on any FAIL.

Implementer should also inspect the current `~/wiki/` state once before starting Phase A (read-only):
```bash
ls $HOME/wiki/raw/ $HOME/wiki/concepts/ $HOME/wiki/entities/ $HOME/wiki/sources/
cat $HOME/wiki/.manifest.json
cat $HOME/wiki/raw/.manifest.json
```

---

## Phase structure

The plan runs **three phases sequentially**. User explicitly forbade parallelization ("abc"). Each phase must be fully green before the next begins. Every task lands as its own commit on `v2-rewrite`.

- **Phase A — Integrity** (fixes 1, 2, 7) — manifest consolidation + sha256, origin-tracking enforcement, frontmatter normalization. These are bugs where the tool silently violates its own spec. Must land first because Phase B (quality ratings) writes new frontmatter that Phase A's validator checks.
- **Phase B — Quality surface** (fixes 3, 4, 6) — quality ratings + ingester self-rating + index rendering, tag-drift lint, missed-cross-link lint. New features built on the now-normalized schema.
- **Phase C — Content & consistency** (fixes 5, 8, 9, 10) — source-pointer backfill, missed toothpaste ingest, entities-page prune, personal-anecdote tag.

The validator `scripts/wiki-validate-page.py` is built in Phase A (Task 30) because it's the enforcement engine for fixes 1, 2, 3, 5, 7, and 10. Its rules grow across phases — Phase A lands the base rules; Phase B extends it with the `quality:` block rules; Phase C relies on it unchanged.

Task numbering is global, continuing from v2:

| Phase | Tasks |
|---|---|
| A | 30, 31, 32, 33, 34 |
| B | 35, 36, 37, 38, 39 |
| C | 40, 41, 42, 43, 44 |

Final acceptance is Task 45.

---

## Per-phase exit criteria

**Phase A exit criteria (all must hold before starting Phase B):**

1. `scripts/wiki-validate-page.py` exists, is executable, and its unit tests pass (Task 30).
2. `scripts/wiki-manifest.py` has been extended with `sha256` and the unified schema, and its extended unit tests pass (Task 31).
3. `scripts/wiki-migrate-v2-hardening.sh` exists, its fixture-based unit test passes, and a dry-run against `~/wiki/` completes without errors (Task 32 steps 1-6).
4. Migration has been run against `~/wiki/` with automatic backup, and `wiki-validate-page.py` now passes on every page under `~/wiki/concepts/`, `~/wiki/entities/`, `~/wiki/sources/`, `~/wiki/queries/` (Task 32 steps 7-10).
5. The `sha256` audit fix is verified: `~/wiki/.manifest.json` has one entry per raw file, each with a `sha256` field; `~/wiki/raw/.manifest.json` has been deleted; the `lpa-robotics-action-tokenization.md` dead reference is gone.
6. The `origin` audit fix is verified: every concept/entity page's `sources:` now reflects the true evidence source, and the `clove-oil-eugenol-dental.md` page's frontmatter no longer implies "conversation" origin when the raw file exists (Task 33).
7. SKILL.md has been updated with the new ingest step 4 (origin-tracking rule) and the capture-format change (Task 34), and SKILL.md is still < 500 lines.
8. `tests/run-all.sh` is green. `tests/self-review.sh` is green.

**Phase B exit criteria:**

1. SKILL.md now documents ingest step 6.5 (self-rate) and step 7.5 (missed-cross-link check) (Task 35).
2. `scripts/wiki-validate-page.py` has been extended with `quality:` block rules and its extended tests pass (Task 35 steps 4-6).
3. `scripts/wiki-lint-tags.py` exists, is executable, and its unit tests pass (Task 37).
4. `scripts/wiki-status.sh` has been extended with the "N pages below 3.5" report and its extended tests pass (Task 38).
5. A GREEN scenario for the missed-cross-link behavior has been added (`tests/green/GREEN-scenario-4-crosslink.md`) and has been observed to pass in at least one subagent run (Task 39).
6. `tests/run-all.sh` is green.

**Phase C exit criteria:**

1. Every raw file in `~/wiki/raw/` has a matching `~/wiki/sources/<raw-basename>.md` pointer page (Task 40).
2. `/Users/lukaszmaj/dev/bigbrain/research/2026-04-24-sensitive-teeth-toothpaste.md` has been ingested — either a new page exists at `~/wiki/concepts/sensitive-teeth-toothpaste.md` OR the content has been merged into `~/wiki/concepts/dentin-hypersensitivity-diagnosis.md` with a clear merge note (Task 41).
3. `~/wiki/entities/electron-nwjs-steam-wrapper.md` has been cut to a stub per fix 9 (Task 42).
4. `~/wiki/schema.md` includes `#personal` in the tag taxonomy section, and `~/wiki/concepts/dentin-hypersensitivity-diagnosis.md` carries the `#personal` tag on its patient-specific anecdote content (Task 43).
5. `wiki-validate-page.py` passes on every page in `~/wiki/` after these content edits (Task 44).
6. `tests/run-all.sh` is green. `tests/self-review.sh` is green.

---

## Style / discipline

Every task in this plan MUST:
- Have a `**Files:**` block listing every path created/modified (absolute paths).
- Have numbered `- [ ] **Step N: ...`** checkbox items.
- End with a single `git commit -m "<message>"` line in a bash block. No Co-Authored-By trailers. No `-i`. No `--amend`. Commits are always NEW commits.
- Include verbatim test bodies and script bodies. No placeholders. No "... rest unchanged ..." elisions.
- Follow TDD where applicable: RED (write test, run, see fail) → GREEN (write script, run, see pass) → REFACTOR (if needed) → commit.
- Show the exact expected `stdout` for every test run command.

Tasks that edit existing files (SKILL.md, wiki-status.sh, wiki-manifest.py, schema.md) MUST quote the BEFORE block verbatim and the AFTER block verbatim, not just describe the change.

Shell scripts: `set -e` for fail-fast scripts; `set -uo pipefail` for hooks and best-effort scripts (matches v2 convention). Python scripts: no dependencies beyond stdlib. Python version check at script top must reject < 3.11 (matches `wiki-init.sh` fail-fast check).

---

# PHASE A — Integrity

## Task 30: `scripts/wiki-validate-page.py` — the enforcement engine (base rules)

The validator is the heart of the hardening. It enforces fixes 1, 2, 5, 7, and 10 (and, after Task 35, fix 3). It's invoked by the migration script (Task 32), by the ingester (SKILL.md change in Task 34), and will be called from `wiki status` in future iterations.

**This task lands the BASE rules only.** Phase B (Task 35) extends the validator with `quality:` block rules.

**Files:**
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-validate-page.py`
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-validate-page.sh`
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/good-concept.md`
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/missing-title.md`
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/bad-type.md`
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/date-not-iso.md`
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/sources-nested.md`
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/no-frontmatter.md`
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/wiki-root-mode/`
  (subdir with wiki layout — small but realistic)

- [ ] **Step 1: Write fixtures**

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/good-concept.md`:

```markdown
---
title: "Valid Concept"
type: concept
tags: [example, test]
sources:
  - raw/2026-04-24-example.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

Body content.
```

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/missing-title.md`:

```markdown
---
type: concept
tags: [example]
sources:
  - raw/2026-04-24-example.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

Body.
```

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/bad-type.md`:

```markdown
---
title: "Bad type"
type: idea
tags: [x]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

Body.
```

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/date-not-iso.md`:

```markdown
---
title: "Date not ISO"
type: concept
tags: [x]
sources:
  - raw/x.md
created: "2026-04-24"
updated: "2026-04-24"
---

Body.
```

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/sources-nested.md`:

```markdown
---
title: "Sources nested"
type: concept
tags: [x]
sources:
  - conversation: "2026-04-24 chat about X"
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

Body.
```

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/no-frontmatter.md`:

```markdown
# A page with no frontmatter

Just body content.
```

Create the wiki-root-mode fixture:

```bash
mkdir -p /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/wiki-root-mode/raw
mkdir -p /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/wiki-root-mode/concepts
mkdir -p /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/wiki-root-mode/sources
```

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/wiki-root-mode/raw/2026-04-24-x.md`:

```markdown
# raw content
```

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/wiki-root-mode/concepts/valid-cross-link.md`:

```markdown
---
title: "Valid Cross Link"
type: concept
tags: [x]
sources:
  - raw/2026-04-24-x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

See [the other page](other.md).
```

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/wiki-root-mode/concepts/other.md`:

```markdown
---
title: "Other"
type: concept
tags: [x]
sources:
  - raw/2026-04-24-x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

Other body.
```

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/wiki-root-mode/concepts/broken-link.md`:

```markdown
---
title: "Broken Link"
type: concept
tags: [x]
sources:
  - raw/2026-04-24-x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

See [missing](does-not-exist.md).
```

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/wiki-root-mode/concepts/missing-source.md`:

```markdown
---
title: "Missing Source"
type: concept
tags: [x]
sources:
  - raw/does-not-exist.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

Body.
```

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/wiki-root-mode/sources/2026-04-24-x.md`:

```markdown
---
title: "Source: x"
type: source
tags: [x]
sources:
  - raw/2026-04-24-x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

Source summary.
```

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/wiki-root-mode/sources/orphan-source.md`:

```markdown
---
title: "Source: orphan"
type: source
tags: [x]
sources:
  - raw/does-not-exist.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

No raw backing this.
```

- [ ] **Step 2: Write failing test**

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-validate-page.sh`:

```bash
#!/bin/bash
# Tests for wiki-validate-page.py (base rules).
# Phase A rules: required fields, type whitelist, ISO-8601 dates, flat sources list,
# markdown link resolution (wiki-root mode), raw-source existence (wiki-root mode),
# matching raw for type=source (wiki-root mode).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TOOL="${REPO_ROOT}/scripts/wiki-validate-page.py"
FIX="${REPO_ROOT}/tests/fixtures/validate-page-cases"

pass_count=0
fail_count=0
say_pass() { echo "PASS: $1"; pass_count=$((pass_count+1)); }
say_fail() { echo "FAIL: $1"; fail_count=$((fail_count+1)); }

expect_exit() {
  # expect_exit <expected-rc> <label> -- <python3 ...>
  local expected="$1" label="$2"; shift 2
  shift  # consume --
  if "$@" >/dev/null 2>&1; then
    actual=0
  else
    actual=$?
  fi
  if [[ "${actual}" -eq "${expected}" ]]; then
    say_pass "${label}"
  else
    say_fail "${label} (expected rc=${expected}, got ${actual})"
  fi
}

# -- Single-file mode (no --wiki-root) --

expect_exit 0 "good-concept passes" -- python3 "${TOOL}" "${FIX}/good-concept.md"
expect_exit 1 "missing title fails" -- python3 "${TOOL}" "${FIX}/missing-title.md"
expect_exit 1 "bad type fails" -- python3 "${TOOL}" "${FIX}/bad-type.md"
expect_exit 1 "date-not-iso fails" -- python3 "${TOOL}" "${FIX}/date-not-iso.md"
expect_exit 1 "sources-nested fails" -- python3 "${TOOL}" "${FIX}/sources-nested.md"
expect_exit 1 "no-frontmatter fails" -- python3 "${TOOL}" "${FIX}/no-frontmatter.md"

# -- Wiki-root mode --
WIKI_FIX="${FIX}/wiki-root-mode"

expect_exit 0 "valid cross-link passes in wiki-root mode" -- \
  python3 "${TOOL}" --wiki-root "${WIKI_FIX}" "${WIKI_FIX}/concepts/valid-cross-link.md"

expect_exit 1 "broken link fails in wiki-root mode" -- \
  python3 "${TOOL}" --wiki-root "${WIKI_FIX}" "${WIKI_FIX}/concepts/broken-link.md"

expect_exit 1 "missing raw source fails in wiki-root mode" -- \
  python3 "${TOOL}" --wiki-root "${WIKI_FIX}" "${WIKI_FIX}/concepts/missing-source.md"

expect_exit 0 "valid type=source passes in wiki-root mode" -- \
  python3 "${TOOL}" --wiki-root "${WIKI_FIX}" "${WIKI_FIX}/sources/2026-04-24-x.md"

expect_exit 1 "orphan type=source (no raw) fails in wiki-root mode" -- \
  python3 "${TOOL}" --wiki-root "${WIKI_FIX}" "${WIKI_FIX}/sources/orphan-source.md"

# -- stderr messages --
out="$(python3 "${TOOL}" "${FIX}/missing-title.md" 2>&1 >/dev/null || true)"
echo "${out}" | grep -q "missing required field: title" \
  && say_pass "stderr: missing title mentions 'missing required field: title'" \
  || say_fail "stderr: expected 'missing required field: title', got: ${out}"

out="$(python3 "${TOOL}" "${FIX}/bad-type.md" 2>&1 >/dev/null || true)"
echo "${out}" | grep -q "type must be one of" \
  && say_pass "stderr: bad type mentions 'type must be one of'" \
  || say_fail "stderr: expected 'type must be one of', got: ${out}"

echo
echo "passed: ${pass_count}"
echo "failed: ${fail_count}"
if [[ "${fail_count}" -gt 0 ]]; then exit 1; fi
echo "ALL PASS"
```

- [ ] **Step 3: Run test to see it fail**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-validate-page.sh
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-validate-page.sh
```

Expected: FAIL — `wiki-validate-page.py` does not exist, so every `python3 ${TOOL}` run fails with rc=2 (python exit on missing file). Most `expect_exit 1` cases will coincidentally pass, but the `expect_exit 0` cases will fail, and the `grep -q` stderr checks will fail. That's the RED signal; we proceed.

- [ ] **Step 4: Write `wiki-validate-page.py`**

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-validate-page.py`:

```python
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
    """Minimal YAML parser covering the subset wiki pages use:

      key: scalar
      key: [a, b, c]
      key:
        - item
        - item
      key:
        - nested: value        # -> nested mapping in list (we flag this)
      key: "quoted"

    Raises ValueError for truly malformed input.
    """
    result: dict[str, Any] = {}
    lines = fm.splitlines()
    i = 0
    current_key: Optional[str] = None
    current_list: Optional[list] = None
    while i < len(lines):
        line = lines[i].rstrip()
        if line == "" or line.startswith("#"):
            i += 1
            continue
        # List continuation of current key
        if current_key is not None and line.startswith("  -"):
            item_text = line[3:].lstrip()
            if ":" in item_text and not (
                item_text.startswith('"') or item_text.startswith("'")
            ):
                # Nested mapping: "- foo: bar" -- preserve as dict so the
                # validator can flag it.
                k, _, v = item_text.partition(":")
                current_list.append({k.strip(): _parse_scalar(v.strip())})
            else:
                current_list.append(_parse_scalar(item_text))
            i += 1
            continue
        else:
            current_key = None
            current_list = None
        # Top-level key
        if ":" not in line:
            raise ValueError(f"malformed line (no colon): {line!r}")
        key, _, rest = line.partition(":")
        key = key.strip()
        rest = rest.strip()
        if rest == "":
            # Block list follows
            result[key] = []
            current_key = key
            current_list = result[key]
            i += 1
            continue
        if rest.startswith("["):
            # Inline list
            if not rest.endswith("]"):
                raise ValueError(f"unterminated inline list for {key}")
            inner = rest[1:-1].strip()
            if inner == "":
                result[key] = []
            else:
                result[key] = [_parse_scalar(p.strip()) for p in inner.split(",")]
            i += 1
            continue
        # Scalar value
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
```

- [ ] **Step 5: Make executable and run test**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-validate-page.py
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-validate-page.sh
```

Expected output:
```
PASS: good-concept passes
PASS: missing title fails
PASS: bad type fails
PASS: date-not-iso fails
PASS: sources-nested fails
PASS: no-frontmatter fails
PASS: valid cross-link passes in wiki-root mode
PASS: broken link fails in wiki-root mode
PASS: missing raw source fails in wiki-root mode
PASS: valid type=source passes in wiki-root mode
PASS: orphan type=source (no raw) fails in wiki-root mode
PASS: stderr: missing title mentions 'missing required field: title'
PASS: stderr: bad type mentions 'type must be one of'

passed: 13
failed: 0
ALL PASS
```

- [ ] **Step 6: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki
git add scripts/wiki-validate-page.py tests/unit/test-validate-page.sh tests/fixtures/validate-page-cases
git commit -m "feat: wiki-validate-page.py (base rules for v2 hardening)"
```

---

## Task 31: Extend `wiki-manifest.py` with `sha256` + unified schema + dead-reference cleanup

The current manifest is half-broken: `~/wiki/.manifest.json` has `{copied_at, origin}` entries without `sha256`, and `~/wiki/raw/.manifest.json` has a DIFFERENT schema `{source, added, referenced_by}`. Drift detection is dead because `sha256` is absent. The `lpa-robotics-action-tokenization.md` reference in `referenced_by` points to a page that never existed.

This task:
1. Defines the ONE canonical schema for `.manifest.json` (living at `<wiki>/.manifest.json`).
2. Extends `wiki-manifest.py` to emit that schema.
3. Updates the existing unit tests to assert the new shape.
4. Adds a `migrate` subcommand that consumes an old `~/wiki/raw/.manifest.json` plus an old `~/wiki/.manifest.json` and produces the unified one.

**Canonical schema for `<wiki>/.manifest.json`** (one per wiki; no secondary manifest):

```json
{
  "raw/2026-04-24-example.md": {
    "sha256": "abc123...",
    "origin": "/Users/lukaszmaj/dev/bigbrain/research/2026-04-24-example.md",
    "copied_at": "2026-04-24T13:00:00Z",
    "last_ingested": "2026-04-24T13:00:00Z",
    "referenced_by": [
      "concepts/example.md",
      "sources/2026-04-24-example.md"
    ]
  }
}
```

Field semantics:
- `sha256` — hex digest of the raw file on disk. Primary drift signal.
- `origin` — the literal string `conversation` OR an absolute path to the file the raw was copied from. Never the string `file` or `conversation` masquerading as the evidence type.
- `copied_at` — ISO-8601 UTC when the raw file was first placed in `raw/` by the ingester.
- `last_ingested` — ISO-8601 UTC of the most recent ingest that used this raw.
- `referenced_by` — list of wiki-root-relative paths of pages derived from this raw. Updated by the ingester. May be empty.

**Files:**
- Modify: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-manifest.py`
- Modify: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-manifest.sh`

- [ ] **Step 1: Extend the test BEFORE extending the script**

The current `tests/unit/test-manifest.sh` tests `build` and `diff`. We add four new test functions: `test_build_includes_sha256`, `test_build_preserves_origin_and_referenced_by`, `test_migrate_consolidates_two_manifests`, `test_migrate_strips_dead_references`.

Read the current test file once:
```bash
cat /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-manifest.sh
```

Replace its contents ENTIRELY with:

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TOOL="${REPO_ROOT}/scripts/wiki-manifest.py"

setup() {
  TESTDIR="$(mktemp -d)"
  WIKI="${TESTDIR}/wiki"
  mkdir -p "${WIKI}/raw"
  echo "alpha" > "${WIKI}/raw/a.md"
  echo "beta"  > "${WIKI}/raw/b.md"
}

teardown() { rm -rf "${TESTDIR}"; }

test_build_manifest_fresh() {
  setup
  python3 "${TOOL}" build "${WIKI}"
  [[ -f "${WIKI}/.manifest.json" ]] || { echo "FAIL: manifest not created"; teardown; exit 1; }
  grep -q 'raw/a.md' "${WIKI}/.manifest.json" || { echo "FAIL: a.md missing"; teardown; exit 1; }
  grep -q 'raw/b.md' "${WIKI}/.manifest.json" || { echo "FAIL: b.md missing"; teardown; exit 1; }
  echo "PASS: test_build_manifest_fresh"
  teardown
}

test_build_includes_sha256() {
  setup
  python3 "${TOOL}" build "${WIKI}"
  python3 -c "
import json, sys
m = json.load(open('${WIKI}/.manifest.json'))
for rel, entry in m.items():
    assert 'sha256' in entry, f'sha256 missing for {rel}'
    assert len(entry['sha256']) == 64, f'sha256 wrong length for {rel}: {entry[\"sha256\"]!r}'
    assert all(c in '0123456789abcdef' for c in entry['sha256']), f'sha256 not hex for {rel}'
print('ok')
" || { echo "FAIL: sha256 check"; teardown; exit 1; }
  echo "PASS: test_build_includes_sha256"
  teardown
}

test_build_preserves_origin_and_referenced_by() {
  setup
  # Seed an existing manifest with origin + referenced_by; build should preserve them.
  cat > "${WIKI}/.manifest.json" <<'EOF'
{
  "raw/a.md": {
    "sha256": "deadbeef",
    "origin": "/tmp/some/source.md",
    "copied_at": "2026-04-20T00:00:00Z",
    "last_ingested": "2026-04-20T00:00:00Z",
    "referenced_by": ["concepts/a-page.md"]
  }
}
EOF
  python3 "${TOOL}" build "${WIKI}"
  python3 -c "
import json
m = json.load(open('${WIKI}/.manifest.json'))
entry = m['raw/a.md']
assert entry['origin'] == '/tmp/some/source.md', f'origin lost: {entry}'
assert entry['referenced_by'] == ['concepts/a-page.md'], f'referenced_by lost: {entry}'
# sha256 should be rewritten to actual hash of alpha + newline
import hashlib
expected = hashlib.sha256(b'alpha\n').hexdigest()
assert entry['sha256'] == expected, f'sha256 wrong: {entry[\"sha256\"]} vs {expected}'
# copied_at should be preserved (it's historical)
assert entry['copied_at'] == '2026-04-20T00:00:00Z', f'copied_at lost: {entry}'
print('ok')
" || { echo "FAIL: preserve check"; teardown; exit 1; }
  echo "PASS: test_build_preserves_origin_and_referenced_by"
  teardown
}

test_diff_clean() {
  setup
  python3 "${TOOL}" build "${WIKI}"
  local result
  result="$(python3 "${TOOL}" diff "${WIKI}")"
  [[ "${result}" == "CLEAN" ]] || { echo "FAIL: expected CLEAN, got '${result}'"; teardown; exit 1; }
  echo "PASS: test_diff_clean"
  teardown
}

test_diff_detects_new_file() {
  setup
  python3 "${TOOL}" build "${WIKI}"
  echo "gamma" > "${WIKI}/raw/c.md"
  local result
  result="$(python3 "${TOOL}" diff "${WIKI}")"
  echo "${result}" | grep -q "NEW: raw/c.md" || {
    echo "FAIL: expected NEW detection, got: ${result}"; teardown; exit 1
  }
  echo "PASS: test_diff_detects_new_file"
  teardown
}

test_diff_detects_modified_file() {
  setup
  python3 "${TOOL}" build "${WIKI}"
  echo "ALPHA CHANGED" > "${WIKI}/raw/a.md"
  local result
  result="$(python3 "${TOOL}" diff "${WIKI}")"
  echo "${result}" | grep -q "MODIFIED: raw/a.md" || {
    echo "FAIL: expected MODIFIED detection, got: ${result}"; teardown; exit 1
  }
  echo "PASS: test_diff_detects_modified_file"
  teardown
}

test_migrate_consolidates_two_manifests() {
  setup
  # Old-style outer manifest (what Phase-A live ~/wiki had).
  cat > "${WIKI}/.manifest.json" <<'EOF'
{
  "raw/a.md": {
    "copied_at": "2026-04-20T00:00:00Z",
    "origin": "/tmp/origin/a.md"
  }
}
EOF
  # Old-style inner manifest (the parallel one we're killing).
  cat > "${WIKI}/raw/.manifest.json" <<'EOF'
{
  "a.md": {
    "source": "/tmp/origin/a.md",
    "added": "2026-04-20T00:00:00Z",
    "referenced_by": ["concepts/a-from-raw.md"]
  },
  "b.md": {
    "source": "/tmp/origin/b.md",
    "added": "2026-04-21T00:00:00Z",
    "referenced_by": ["concepts/b-from-raw.md"]
  }
}
EOF
  python3 "${TOOL}" migrate "${WIKI}"
  # After migrate: one manifest at root, inner deleted, both entries present, sha256 populated.
  [[ ! -f "${WIKI}/raw/.manifest.json" ]] || { echo "FAIL: inner manifest not deleted"; teardown; exit 1; }
  python3 -c "
import json
m = json.load(open('${WIKI}/.manifest.json'))
for rel in ('raw/a.md', 'raw/b.md'):
    assert rel in m, f'{rel} missing after migrate: {list(m.keys())}'
    e = m[rel]
    assert 'sha256' in e and len(e['sha256']) == 64, f'{rel}: sha256 bad {e.get(\"sha256\")!r}'
    assert e['origin'] == '/tmp/origin/' + rel.split('/')[1], f'{rel}: origin {e[\"origin\"]!r}'
    assert 'copied_at' in e, f'{rel}: copied_at missing'
    assert 'last_ingested' in e, f'{rel}: last_ingested missing'
    assert isinstance(e['referenced_by'], list), f'{rel}: referenced_by not a list'
assert 'concepts/a-from-raw.md' in m['raw/a.md']['referenced_by']
assert 'concepts/b-from-raw.md' in m['raw/b.md']['referenced_by']
print('ok')
" || { echo "FAIL: migrate content check"; teardown; exit 1; }
  echo "PASS: test_migrate_consolidates_two_manifests"
  teardown
}

test_migrate_strips_dead_references() {
  setup
  # Inner manifest references a page that does NOT exist on disk.
  cat > "${WIKI}/.manifest.json" <<'EOF'
{}
EOF
  cat > "${WIKI}/raw/.manifest.json" <<'EOF'
{
  "a.md": {
    "source": "/tmp/origin/a.md",
    "added": "2026-04-20T00:00:00Z",
    "referenced_by": ["concepts/real.md", "concepts/dead-ref.md"]
  }
}
EOF
  mkdir -p "${WIKI}/concepts"
  touch "${WIKI}/concepts/real.md"
  python3 "${TOOL}" migrate "${WIKI}"
  python3 -c "
import json
m = json.load(open('${WIKI}/.manifest.json'))
refs = m['raw/a.md']['referenced_by']
assert 'concepts/real.md' in refs, f'real.md dropped: {refs}'
assert 'concepts/dead-ref.md' not in refs, f'dead-ref.md not stripped: {refs}'
print('ok')
" || { echo "FAIL: dead-ref strip check"; teardown; exit 1; }
  echo "PASS: test_migrate_strips_dead_references"
  teardown
}

test_build_manifest_fresh
test_build_includes_sha256
test_build_preserves_origin_and_referenced_by
test_diff_clean
test_diff_detects_new_file
test_diff_detects_modified_file
test_migrate_consolidates_two_manifests
test_migrate_strips_dead_references
echo "ALL PASS"
```

- [ ] **Step 2: Run the test to see it fail**

Run:
```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-manifest.sh
```

Expected: the first three tests still pass (old `build`/`diff` behavior mostly still works), but `test_build_includes_sha256` will in fact pass since the existing `wiki-manifest.py` already writes `sha256` (re-read the file — it does). `test_build_preserves_origin_and_referenced_by` will FAIL because the current `cmd_build` only preserves `last_ingested` and overwrites everything else. `test_migrate_consolidates_two_manifests` will FAIL with `unknown command: migrate`. That's the RED signal.

- [ ] **Step 3: Patch `wiki-manifest.py`**

Read the current `wiki-manifest.py` once:
```bash
cat /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-manifest.py
```

Replace its contents ENTIRELY with:

```python
#!/usr/bin/env python3
"""Hash manifest for raw/ files — v2-hardened schema.

Usage:
    wiki-manifest.py build   <wiki_root>
    wiki-manifest.py diff    <wiki_root>
    wiki-manifest.py migrate <wiki_root>

Canonical schema for <wiki_root>/.manifest.json (one per wiki):

    {
      "raw/2026-04-24-example.md": {
        "sha256": "<64-hex>",
        "origin": "<absolute path>" or "conversation",
        "copied_at": "<ISO-8601 UTC>",
        "last_ingested": "<ISO-8601 UTC>",
        "referenced_by": ["concepts/...", "sources/...", ...]
      }
    }

build: rewrite `.manifest.json` with current sha256 for every raw file.
       Preserves `origin`, `copied_at`, `referenced_by` from prior entries.
       `last_ingested` is refreshed to now.
diff:  compare live raw/ sha256 against manifest. Prints CLEAN or NEW/MODIFIED/
       DELETED lines.
migrate: one-time migration for v2 -> v2-hardening:
       Merges any legacy <wiki_root>/raw/.manifest.json into the unified
       <wiki_root>/.manifest.json, normalizes field names (source -> origin,
       added -> copied_at), strips `referenced_by` entries that don't exist
       on disk, and deletes the legacy raw/.manifest.json.
"""

import hashlib
import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def _hash_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _scan_raw(wiki_root: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    raw = wiki_root / "raw"
    if not raw.exists():
        return result
    for p in raw.rglob("*"):
        if p.is_file() and not p.name.startswith("."):
            rel = str(p.relative_to(wiki_root))
            result[rel] = _hash_file(p)
    return result


def _load_json(path: Path) -> dict:
    if not path.exists():
        return {}
    with path.open("r") as f:
        return json.load(f)


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def cmd_build(wiki_root: Path) -> int:
    hashes = _scan_raw(wiki_root)
    existing = _load_json(wiki_root / ".manifest.json")
    now = _now_iso()
    out: dict[str, dict] = {}
    for rel, sha in hashes.items():
        prev = existing.get(rel, {}) if isinstance(existing.get(rel), dict) else {}
        entry = {
            "sha256": sha,
            "origin": prev.get("origin", ""),
            "copied_at": prev.get("copied_at", now),
            "last_ingested": now,
            "referenced_by": prev.get("referenced_by", []),
        }
        # Normalize missing/legacy origin.
        if not entry["origin"]:
            entry["origin"] = prev.get("source", "")  # legacy key
        out[rel] = entry
    (wiki_root / ".manifest.json").write_text(
        json.dumps(out, indent=2, sort_keys=True) + "\n"
    )
    return 0


def cmd_diff(wiki_root: Path) -> int:
    manifest = _load_json(wiki_root / ".manifest.json")
    live = _scan_raw(wiki_root)

    lines: list[str] = []
    for rel, sha in live.items():
        entry = manifest.get(rel)
        if not isinstance(entry, dict):
            lines.append(f"NEW: {rel}")
        elif entry.get("sha256") != sha:
            lines.append(f"MODIFIED: {rel}")
    for rel in manifest:
        if rel not in live:
            lines.append(f"DELETED: {rel}")

    if not lines:
        print("CLEAN")
    else:
        print("\n".join(lines))
    return 0


def cmd_migrate(wiki_root: Path) -> int:
    """One-time migration: consolidate two manifests into one, strip dead refs.

    Reads:
      <wiki_root>/.manifest.json          (legacy outer, schema {copied_at, origin})
      <wiki_root>/raw/.manifest.json      (legacy inner, schema {source, added, referenced_by})

    Writes:
      <wiki_root>/.manifest.json          unified schema

    Removes:
      <wiki_root>/raw/.manifest.json      (deleted after successful merge)
    """
    outer = _load_json(wiki_root / ".manifest.json")
    inner_path = wiki_root / "raw" / ".manifest.json"
    inner = _load_json(inner_path)

    # Normalize outer -- keys are already wiki-root-relative (raw/...)
    merged: dict[str, dict] = {}
    for rel, e in outer.items():
        if not isinstance(e, dict):
            continue
        merged[rel] = {
            "sha256": e.get("sha256", ""),
            "origin": e.get("origin", e.get("source", "")),
            "copied_at": e.get("copied_at", e.get("added", "")),
            "last_ingested": e.get("last_ingested", e.get("copied_at", e.get("added", ""))),
            "referenced_by": list(e.get("referenced_by", []) or []),
        }

    # Merge inner -- keys in the inner are relative to raw/ (no "raw/" prefix).
    for inner_rel, e in inner.items():
        if not isinstance(e, dict):
            continue
        rel = f"raw/{inner_rel}" if not inner_rel.startswith("raw/") else inner_rel
        entry = merged.setdefault(rel, {
            "sha256": "",
            "origin": "",
            "copied_at": "",
            "last_ingested": "",
            "referenced_by": [],
        })
        if not entry.get("origin"):
            entry["origin"] = e.get("source", e.get("origin", ""))
        if not entry.get("copied_at"):
            entry["copied_at"] = e.get("added", e.get("copied_at", ""))
        if not entry.get("last_ingested"):
            entry["last_ingested"] = e.get("last_ingested", entry["copied_at"])
        # Union referenced_by
        inner_refs = list(e.get("referenced_by", []) or [])
        refs = entry["referenced_by"]
        for r in inner_refs:
            if r not in refs:
                refs.append(r)

    # Recompute sha256 against live files; populate where missing.
    live = _scan_raw(wiki_root)
    now = _now_iso()
    for rel, sha in live.items():
        entry = merged.setdefault(rel, {
            "sha256": "",
            "origin": "",
            "copied_at": now,
            "last_ingested": now,
            "referenced_by": [],
        })
        entry["sha256"] = sha
        if not entry.get("copied_at"):
            entry["copied_at"] = now
        if not entry.get("last_ingested"):
            entry["last_ingested"] = now

    # Strip dead references: only keep referenced_by entries whose target
    # file actually exists under wiki_root.
    for rel, entry in merged.items():
        alive = []
        for ref in entry.get("referenced_by", []):
            if (wiki_root / ref).exists():
                alive.append(ref)
        entry["referenced_by"] = alive

    # Write unified.
    (wiki_root / ".manifest.json").write_text(
        json.dumps(merged, indent=2, sort_keys=True) + "\n"
    )

    # Delete legacy inner (if it existed).
    if inner_path.exists():
        inner_path.unlink()

    return 0


def main() -> int:
    if sys.version_info < (3, 11):
        print("python 3.11+ required", file=sys.stderr)
        return 1

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


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Run test**

Run:
```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-manifest.sh
```

Expected output:
```
PASS: test_build_manifest_fresh
PASS: test_build_includes_sha256
PASS: test_build_preserves_origin_and_referenced_by
PASS: test_diff_clean
PASS: test_diff_detects_new_file
PASS: test_diff_detects_modified_file
PASS: test_migrate_consolidates_two_manifests
PASS: test_migrate_strips_dead_references
ALL PASS
```

- [ ] **Step 5: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki
git add scripts/wiki-manifest.py tests/unit/test-manifest.sh
git commit -m "feat: unified manifest schema + sha256 + migrate subcommand"
```

---

## Task 32: `scripts/wiki-migrate-v2-hardening.sh` — live wiki backfill with safety

This is the one-time migration that brings `~/wiki/` to the v2-hardening schema. It:
1. Backs up `~/wiki/` to `~/wiki.backup-<timestamp>/`.
2. Runs `wiki-manifest.py migrate` to consolidate the two manifests.
3. Normalizes frontmatter on every page under `concepts/`, `entities/`, `sources/`, `queries/` to meet the Phase A base validator rules (adds `type`, converts `created`/`updated` to full ISO-8601, flattens `sources:` from nested mappings to plain strings, adds `updated` where missing).
4. Runs `wiki-validate-page.py` (Task 30) against every page.
5. On ANY violation: restores backup, exits 1 with the violations printed.
6. On success: prompts the user (via `read`) to commit the migrated wiki.

**This task does NOT add the `quality:` block** — that's Phase B Task 36 (a separate migration step). The validator at this point only enforces the base rules, which is what the backfill produces.

**Files:**
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-migrate-v2-hardening.sh`
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-normalize-frontmatter.py`
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-migrate-v2-hardening.sh`
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-normalize-frontmatter.sh`
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/pre-hardening-wiki/` (fixture tree — see Step 1)

- [ ] **Step 1: Create the pre-hardening wiki fixture**

This fixture MUST resemble the live `~/wiki/` in shape, with deliberate violations: a page with `created: "2026-04-24"` (no time), a page with `sources: [- conversation: "foo"]` (nested), a page missing `type`, a page with `updated` missing, two manifests in the old shapes, and a raw file.

Run:
```bash
mkdir -p /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/pre-hardening-wiki/{concepts,entities,sources,queries,raw,.wiki-pending,.locks}
```

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/pre-hardening-wiki/.wiki-config`:

```toml
role = "main"
created = "2026-04-22"

[platform]
agent_cli = "claude"
headless_command = "claude -p"

[settings]
auto_commit = true
```

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/pre-hardening-wiki/schema.md`:

```markdown
# Wiki Schema

## Role
main

## Categories
- `concepts/` — ideas, patterns, principles
- `entities/` — specific tools, services, APIs
- `sources/` — one summary page per ingested source
- `queries/` — filed Q&A worth keeping

## Tag Taxonomy (bounded)
Tags are evolved by the ingester; propose changes via schema edits, not ad-hoc.
```

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/pre-hardening-wiki/index.md`:

```markdown
# Wiki Index

## Concepts
- [Short Date](concepts/short-date.md)
- [No Type](concepts/no-type.md)

## Entities
- [Nested Sources](entities/nested-sources.md)

## Sources
- [raw/2026-04-24-sample.md](sources/2026-04-24-sample.md)

## Queries
(empty)
```

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/pre-hardening-wiki/log.md`:

```markdown
# Wiki Log

## [2026-04-22] init | wiki created
```

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/pre-hardening-wiki/raw/2026-04-24-sample.md`:

```markdown
# Sample Raw

Body of a sample raw source.
```

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/pre-hardening-wiki/.manifest.json`:

```json
{
  "raw/2026-04-24-sample.md": {
    "copied_at": "2026-04-24T12:00:00Z",
    "origin": "/tmp/origin/2026-04-24-sample.md"
  }
}
```

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/pre-hardening-wiki/raw/.manifest.json`:

```json
{
  "2026-04-24-sample.md": {
    "source": "/tmp/origin/2026-04-24-sample.md",
    "added": "2026-04-24T12:00:00Z",
    "referenced_by": ["concepts/short-date.md", "entities/nested-sources.md", "sources/2026-04-24-sample.md", "concepts/never-existed.md"]
  }
}
```

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/pre-hardening-wiki/concepts/short-date.md`:

```markdown
---
title: "Short Date Concept"
tags: [example]
sources:
  - raw/2026-04-24-sample.md
created: 2026-04-24
updated: 2026-04-24
---

Body.
```

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/pre-hardening-wiki/concepts/no-type.md`:

```markdown
---
title: "No Type Concept"
tags: [example]
sources:
  - raw/2026-04-24-sample.md
created: "2026-04-24T12:00:00Z"
---

Body.
```

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/pre-hardening-wiki/entities/nested-sources.md`:

```markdown
---
title: "Nested Sources Entity"
tags: [example]
sources:
  - conversation: "2026-04-24 chat about Y"
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

Body.
```

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/pre-hardening-wiki/sources/2026-04-24-sample.md`:

```markdown
---
title: "Source: Sample"
tags: [example]
sources:
  - raw/2026-04-24-sample.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

Source summary.
```

- [ ] **Step 2: Write failing test for `wiki-normalize-frontmatter.py`**

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-normalize-frontmatter.sh`:

```bash
#!/bin/bash
# Tests for wiki-normalize-frontmatter.py -- a per-page frontmatter fixer.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TOOL="${REPO_ROOT}/scripts/wiki-normalize-frontmatter.py"

setup() {
  TESTDIR="$(mktemp -d)"
}

teardown() { rm -rf "${TESTDIR}"; }

test_adds_type_concept_for_concepts_path() {
  setup
  mkdir -p "${TESTDIR}/wiki/concepts"
  cat > "${TESTDIR}/wiki/concepts/x.md" <<'EOF'
---
title: "X"
tags: [a]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

body
EOF
  python3 "${TOOL}" --wiki-root "${TESTDIR}/wiki" "${TESTDIR}/wiki/concepts/x.md"
  grep -q '^type: concept$' "${TESTDIR}/wiki/concepts/x.md" || {
    echo "FAIL: type: concept not added"; cat "${TESTDIR}/wiki/concepts/x.md"; teardown; exit 1
  }
  echo "PASS: test_adds_type_concept_for_concepts_path"
  teardown
}

test_expands_short_date_to_iso_utc() {
  setup
  mkdir -p "${TESTDIR}/wiki/concepts"
  cat > "${TESTDIR}/wiki/concepts/x.md" <<'EOF'
---
title: "X"
tags: [a]
sources:
  - raw/x.md
created: 2026-04-24
updated: 2026-04-24
---

body
EOF
  python3 "${TOOL}" --wiki-root "${TESTDIR}/wiki" "${TESTDIR}/wiki/concepts/x.md"
  grep -q '^created: "2026-04-24T00:00:00Z"$' "${TESTDIR}/wiki/concepts/x.md" || {
    echo "FAIL: created not expanded"; cat "${TESTDIR}/wiki/concepts/x.md"; teardown; exit 1
  }
  grep -q '^updated: "2026-04-24T00:00:00Z"$' "${TESTDIR}/wiki/concepts/x.md" || {
    echo "FAIL: updated not expanded"; cat "${TESTDIR}/wiki/concepts/x.md"; teardown; exit 1
  }
  echo "PASS: test_expands_short_date_to_iso_utc"
  teardown
}

test_adds_updated_when_missing() {
  setup
  mkdir -p "${TESTDIR}/wiki/concepts"
  cat > "${TESTDIR}/wiki/concepts/x.md" <<'EOF'
---
title: "X"
tags: [a]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
---

body
EOF
  python3 "${TOOL}" --wiki-root "${TESTDIR}/wiki" "${TESTDIR}/wiki/concepts/x.md"
  grep -q '^updated: "2026-04-24T12:00:00Z"$' "${TESTDIR}/wiki/concepts/x.md" || {
    echo "FAIL: updated not added"; cat "${TESTDIR}/wiki/concepts/x.md"; teardown; exit 1
  }
  echo "PASS: test_adds_updated_when_missing"
  teardown
}

test_flattens_nested_sources() {
  setup
  mkdir -p "${TESTDIR}/wiki/entities"
  cat > "${TESTDIR}/wiki/entities/x.md" <<'EOF'
---
title: "X"
tags: [a]
sources:
  - conversation: "2026-04-24 chat"
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

body
EOF
  python3 "${TOOL}" --wiki-root "${TESTDIR}/wiki" "${TESTDIR}/wiki/entities/x.md"
  grep -q '^  - conversation$' "${TESTDIR}/wiki/entities/x.md" || {
    echo "FAIL: nested sources not flattened"; cat "${TESTDIR}/wiki/entities/x.md"; teardown; exit 1
  }
  grep -q 'conversation: "2026-04-24 chat"' "${TESTDIR}/wiki/entities/x.md" && {
    echo "FAIL: nested mapping still present"; cat "${TESTDIR}/wiki/entities/x.md"; teardown; exit 1
  }
  echo "PASS: test_flattens_nested_sources"
  teardown
}

test_is_idempotent() {
  setup
  mkdir -p "${TESTDIR}/wiki/concepts"
  cat > "${TESTDIR}/wiki/concepts/x.md" <<'EOF'
---
title: "X"
type: concept
tags: [a]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

body
EOF
  sha_before="$(shasum -a 256 "${TESTDIR}/wiki/concepts/x.md" | awk '{print $1}')"
  python3 "${TOOL}" --wiki-root "${TESTDIR}/wiki" "${TESTDIR}/wiki/concepts/x.md"
  sha_after="$(shasum -a 256 "${TESTDIR}/wiki/concepts/x.md" | awk '{print $1}')"
  [[ "${sha_before}" == "${sha_after}" ]] || {
    echo "FAIL: not idempotent"; teardown; exit 1
  }
  echo "PASS: test_is_idempotent"
  teardown
}

test_adds_type_source_for_sources_path() {
  setup
  mkdir -p "${TESTDIR}/wiki/sources"
  cat > "${TESTDIR}/wiki/sources/x.md" <<'EOF'
---
title: "Source X"
tags: [a]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

body
EOF
  python3 "${TOOL}" --wiki-root "${TESTDIR}/wiki" "${TESTDIR}/wiki/sources/x.md"
  grep -q '^type: source$' "${TESTDIR}/wiki/sources/x.md" || {
    echo "FAIL: type: source not added"; cat "${TESTDIR}/wiki/sources/x.md"; teardown; exit 1
  }
  echo "PASS: test_adds_type_source_for_sources_path"
  teardown
}

test_adds_type_entity_for_entities_path
test_adds_type_concept_for_concepts_path() {
  setup
  mkdir -p "${TESTDIR}/wiki/concepts"
  cat > "${TESTDIR}/wiki/concepts/x.md" <<'EOF'
---
title: "X"
tags: [a]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

body
EOF
  python3 "${TOOL}" --wiki-root "${TESTDIR}/wiki" "${TESTDIR}/wiki/concepts/x.md"
  grep -q '^type: concept$' "${TESTDIR}/wiki/concepts/x.md" || {
    echo "FAIL: type: concept not added"; cat "${TESTDIR}/wiki/concepts/x.md"; teardown; exit 1
  }
  echo "PASS: test_adds_type_concept_for_concepts_path"
  teardown
}

# Note: the test above shadows the earlier entity-specific test helper on
# purpose; shell interprets duplicate function definitions as re-binds.
# The caller list below drives the order; do NOT call the duplicated name.

test_adds_type_entity_for_entities_path_real() {
  setup
  mkdir -p "${TESTDIR}/wiki/entities"
  cat > "${TESTDIR}/wiki/entities/x.md" <<'EOF'
---
title: "Entity X"
tags: [a]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

body
EOF
  python3 "${TOOL}" --wiki-root "${TESTDIR}/wiki" "${TESTDIR}/wiki/entities/x.md"
  grep -q '^type: entity$' "${TESTDIR}/wiki/entities/x.md" || {
    echo "FAIL: type: entity not added"; cat "${TESTDIR}/wiki/entities/x.md"; teardown; exit 1
  }
  echo "PASS: test_adds_type_entity_for_entities_path_real"
  teardown
}

test_adds_type_concept_for_concepts_path
test_expands_short_date_to_iso_utc
test_adds_updated_when_missing
test_flattens_nested_sources
test_is_idempotent
test_adds_type_source_for_sources_path
test_adds_type_entity_for_entities_path_real
echo "ALL PASS"
```

(Note: the file above inadvertently re-defines `test_adds_type_concept_for_concepts_path`. Replace that with a single clean definition. Final correct version — use THIS copy:)

```bash
#!/bin/bash
# Tests for wiki-normalize-frontmatter.py -- a per-page frontmatter fixer.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TOOL="${REPO_ROOT}/scripts/wiki-normalize-frontmatter.py"

setup() { TESTDIR="$(mktemp -d)"; }
teardown() { rm -rf "${TESTDIR}"; }

test_adds_type_concept_for_concepts_path() {
  setup
  mkdir -p "${TESTDIR}/wiki/concepts"
  cat > "${TESTDIR}/wiki/concepts/x.md" <<'EOF'
---
title: "X"
tags: [a]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

body
EOF
  python3 "${TOOL}" --wiki-root "${TESTDIR}/wiki" "${TESTDIR}/wiki/concepts/x.md"
  grep -q '^type: concept$' "${TESTDIR}/wiki/concepts/x.md" || {
    echo "FAIL: type: concept not added"; cat "${TESTDIR}/wiki/concepts/x.md"; teardown; exit 1
  }
  echo "PASS: test_adds_type_concept_for_concepts_path"
  teardown
}

test_adds_type_entity_for_entities_path() {
  setup
  mkdir -p "${TESTDIR}/wiki/entities"
  cat > "${TESTDIR}/wiki/entities/x.md" <<'EOF'
---
title: "Entity X"
tags: [a]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

body
EOF
  python3 "${TOOL}" --wiki-root "${TESTDIR}/wiki" "${TESTDIR}/wiki/entities/x.md"
  grep -q '^type: entity$' "${TESTDIR}/wiki/entities/x.md" || {
    echo "FAIL: type: entity not added"; cat "${TESTDIR}/wiki/entities/x.md"; teardown; exit 1
  }
  echo "PASS: test_adds_type_entity_for_entities_path"
  teardown
}

test_adds_type_source_for_sources_path() {
  setup
  mkdir -p "${TESTDIR}/wiki/sources"
  cat > "${TESTDIR}/wiki/sources/x.md" <<'EOF'
---
title: "Source X"
tags: [a]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

body
EOF
  python3 "${TOOL}" --wiki-root "${TESTDIR}/wiki" "${TESTDIR}/wiki/sources/x.md"
  grep -q '^type: source$' "${TESTDIR}/wiki/sources/x.md" || {
    echo "FAIL: type: source not added"; cat "${TESTDIR}/wiki/sources/x.md"; teardown; exit 1
  }
  echo "PASS: test_adds_type_source_for_sources_path"
  teardown
}

test_expands_short_date_to_iso_utc() {
  setup
  mkdir -p "${TESTDIR}/wiki/concepts"
  cat > "${TESTDIR}/wiki/concepts/x.md" <<'EOF'
---
title: "X"
tags: [a]
sources:
  - raw/x.md
created: 2026-04-24
updated: 2026-04-24
---

body
EOF
  python3 "${TOOL}" --wiki-root "${TESTDIR}/wiki" "${TESTDIR}/wiki/concepts/x.md"
  grep -q '^created: "2026-04-24T00:00:00Z"$' "${TESTDIR}/wiki/concepts/x.md" || {
    echo "FAIL: created not expanded"; cat "${TESTDIR}/wiki/concepts/x.md"; teardown; exit 1
  }
  grep -q '^updated: "2026-04-24T00:00:00Z"$' "${TESTDIR}/wiki/concepts/x.md" || {
    echo "FAIL: updated not expanded"; cat "${TESTDIR}/wiki/concepts/x.md"; teardown; exit 1
  }
  echo "PASS: test_expands_short_date_to_iso_utc"
  teardown
}

test_adds_updated_when_missing() {
  setup
  mkdir -p "${TESTDIR}/wiki/concepts"
  cat > "${TESTDIR}/wiki/concepts/x.md" <<'EOF'
---
title: "X"
tags: [a]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
---

body
EOF
  python3 "${TOOL}" --wiki-root "${TESTDIR}/wiki" "${TESTDIR}/wiki/concepts/x.md"
  grep -q '^updated: "2026-04-24T12:00:00Z"$' "${TESTDIR}/wiki/concepts/x.md" || {
    echo "FAIL: updated not added"; cat "${TESTDIR}/wiki/concepts/x.md"; teardown; exit 1
  }
  echo "PASS: test_adds_updated_when_missing"
  teardown
}

test_flattens_nested_sources() {
  setup
  mkdir -p "${TESTDIR}/wiki/entities"
  cat > "${TESTDIR}/wiki/entities/x.md" <<'EOF'
---
title: "X"
tags: [a]
sources:
  - conversation: "2026-04-24 chat"
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

body
EOF
  python3 "${TOOL}" --wiki-root "${TESTDIR}/wiki" "${TESTDIR}/wiki/entities/x.md"
  grep -q '^  - conversation$' "${TESTDIR}/wiki/entities/x.md" || {
    echo "FAIL: nested sources not flattened"; cat "${TESTDIR}/wiki/entities/x.md"; teardown; exit 1
  }
  if grep -q 'conversation: "2026-04-24 chat"' "${TESTDIR}/wiki/entities/x.md"; then
    echo "FAIL: nested mapping still present"; cat "${TESTDIR}/wiki/entities/x.md"; teardown; exit 1
  fi
  echo "PASS: test_flattens_nested_sources"
  teardown
}

test_is_idempotent() {
  setup
  mkdir -p "${TESTDIR}/wiki/concepts"
  cat > "${TESTDIR}/wiki/concepts/x.md" <<'EOF'
---
title: "X"
type: concept
tags: [a]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

body
EOF
  sha_before="$(shasum -a 256 "${TESTDIR}/wiki/concepts/x.md" | awk '{print $1}')"
  python3 "${TOOL}" --wiki-root "${TESTDIR}/wiki" "${TESTDIR}/wiki/concepts/x.md"
  sha_after="$(shasum -a 256 "${TESTDIR}/wiki/concepts/x.md" | awk '{print $1}')"
  [[ "${sha_before}" == "${sha_after}" ]] || {
    echo "FAIL: not idempotent"; teardown; exit 1
  }
  echo "PASS: test_is_idempotent"
  teardown
}

test_adds_type_concept_for_concepts_path
test_adds_type_entity_for_entities_path
test_adds_type_source_for_sources_path
test_expands_short_date_to_iso_utc
test_adds_updated_when_missing
test_flattens_nested_sources
test_is_idempotent
echo "ALL PASS"
```

Use the second (cleaner) version as the file contents.

- [ ] **Step 3: Run to see failure**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-normalize-frontmatter.sh
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-normalize-frontmatter.sh
```

Expected: FAIL — script missing.

- [ ] **Step 4: Write `wiki-normalize-frontmatter.py`**

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-normalize-frontmatter.py`:

```python
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
               "sources": "source", "queries": "query"}
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


def _process_fm(fm: list[str], inferred_type: str | None) -> list[str]:
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
```

- [ ] **Step 5: Run test**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-normalize-frontmatter.py
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-normalize-frontmatter.sh
```

Expected:
```
PASS: test_adds_type_concept_for_concepts_path
PASS: test_adds_type_entity_for_entities_path
PASS: test_adds_type_source_for_sources_path
PASS: test_expands_short_date_to_iso_utc
PASS: test_adds_updated_when_missing
PASS: test_flattens_nested_sources
PASS: test_is_idempotent
ALL PASS
```

- [ ] **Step 6: Write failing test for the migration script**

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-migrate-v2-hardening.sh`:

```bash
#!/bin/bash
# Tests for wiki-migrate-v2-hardening.sh against the pre-hardening fixture.
# Does NOT touch ~/wiki/. Only runs against a copy of the fixture.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MIGRATE="${REPO_ROOT}/scripts/wiki-migrate-v2-hardening.sh"
VALIDATOR="${REPO_ROOT}/scripts/wiki-validate-page.py"
FIXTURE="${REPO_ROOT}/tests/fixtures/pre-hardening-wiki"

setup() {
  TESTDIR="$(mktemp -d)"
  WIKI="${TESTDIR}/wiki"
  cp -R "${FIXTURE}" "${WIKI}"
}

teardown() { rm -rf "${TESTDIR}"; }

test_migrate_produces_validator_green_wiki() {
  setup
  # Run with --yes so the prompt is skipped.
  "${MIGRATE}" --yes --wiki-root "${WIKI}" >/dev/null
  # Every page under concepts/entities/sources/queries must pass validator.
  local failures=0
  while IFS= read -r page; do
    if ! python3 "${VALIDATOR}" --wiki-root "${WIKI}" "${page}" 2>/dev/null; then
      echo "validator failure: ${page}"
      python3 "${VALIDATOR}" --wiki-root "${WIKI}" "${page}" 2>&1 || true
      failures=$((failures + 1))
    fi
  done < <(find "${WIKI}/concepts" "${WIKI}/entities" "${WIKI}/sources" "${WIKI}/queries" -type f -name "*.md" 2>/dev/null)
  [[ "${failures}" -eq 0 ]] || { echo "FAIL: ${failures} pages failed validator"; teardown; exit 1; }
  echo "PASS: test_migrate_produces_validator_green_wiki"
  teardown
}

test_migrate_consolidates_manifest() {
  setup
  "${MIGRATE}" --yes --wiki-root "${WIKI}" >/dev/null
  [[ -f "${WIKI}/.manifest.json" ]] || { echo "FAIL: unified manifest missing"; teardown; exit 1; }
  [[ ! -f "${WIKI}/raw/.manifest.json" ]] || { echo "FAIL: legacy inner manifest still present"; teardown; exit 1; }
  python3 -c "
import json
m = json.load(open('${WIKI}/.manifest.json'))
entry = m['raw/2026-04-24-sample.md']
assert 'sha256' in entry and len(entry['sha256']) == 64, f'sha256 bad: {entry}'
refs = entry['referenced_by']
# 'concepts/never-existed.md' was a dead ref in the fixture; must be gone.
assert 'concepts/never-existed.md' not in refs, f'dead ref leaked: {refs}'
# Live refs should be preserved.
assert 'concepts/short-date.md' in refs, f'live ref dropped: {refs}'
assert 'entities/nested-sources.md' in refs, f'live ref dropped: {refs}'
print('ok')
" || { echo "FAIL: manifest content check"; teardown; exit 1; }
  echo "PASS: test_migrate_consolidates_manifest"
  teardown
}

test_migrate_preserves_body_content() {
  setup
  "${MIGRATE}" --yes --wiki-root "${WIKI}" >/dev/null
  grep -q "^Body\.$" "${WIKI}/concepts/short-date.md" || {
    echo "FAIL: body content clobbered"; teardown; exit 1
  }
  echo "PASS: test_migrate_preserves_body_content"
  teardown
}

test_migrate_creates_backup_when_run_against_live_like_path() {
  setup
  # Pass --backup-dir to control where the backup goes.
  local backup_dir
  backup_dir="${TESTDIR}/backups"
  mkdir -p "${backup_dir}"
  "${MIGRATE}" --yes --wiki-root "${WIKI}" --backup-dir "${backup_dir}" >/dev/null
  local count
  count="$(find "${backup_dir}" -maxdepth 1 -type d -name "wiki.backup-*" 2>/dev/null | wc -l | tr -d ' ')"
  [[ "${count}" -eq 1 ]] || { echo "FAIL: expected 1 backup, got ${count}"; teardown; exit 1; }
  echo "PASS: test_migrate_creates_backup_when_run_against_live_like_path"
  teardown
}

test_migrate_rolls_back_on_validator_failure() {
  setup
  # Inject a deliberately-unfixable page that will still fail validator after
  # normalization (e.g. unknown type that doesn't match any directory heuristic).
  mkdir -p "${WIKI}/concepts"
  cat > "${WIKI}/concepts/broken.md" <<'EOF'
# No frontmatter at all
Body only.
EOF
  # Expect migration to fail and restore from backup.
  if "${MIGRATE}" --yes --wiki-root "${WIKI}" --backup-dir "${TESTDIR}/b" 2>/dev/null; then
    echo "FAIL: migrate should have failed"; teardown; exit 1
  fi
  # The WIKI should have been restored from backup.
  [[ -f "${WIKI}/concepts/broken.md" ]] || {
    echo "FAIL: restored wiki missing broken.md"; teardown; exit 1
  }
  # And crucially, short-date.md should STILL have its short date (migration rolled back).
  grep -q '^created: 2026-04-24$' "${WIKI}/concepts/short-date.md" || {
    echo "FAIL: short-date.md was not restored to pre-migration state"
    cat "${WIKI}/concepts/short-date.md"
    teardown; exit 1
  }
  echo "PASS: test_migrate_rolls_back_on_validator_failure"
  teardown
}

test_migrate_produces_validator_green_wiki
test_migrate_consolidates_manifest
test_migrate_preserves_body_content
test_migrate_creates_backup_when_run_against_live_like_path
test_migrate_rolls_back_on_validator_failure
echo "ALL PASS"
```

- [ ] **Step 7: Run to see failure**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-migrate-v2-hardening.sh
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-migrate-v2-hardening.sh
```

Expected: FAIL — migration script missing.

- [ ] **Step 8: Write `wiki-migrate-v2-hardening.sh`**

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-migrate-v2-hardening.sh`:

```bash
#!/bin/bash
# One-time migration: bring a wiki to the v2-hardening schema.
#
# Usage:
#   wiki-migrate-v2-hardening.sh [--yes] [--wiki-root DIR] [--backup-dir DIR]
#
# Without --wiki-root, defaults to $HOME/wiki.
# Without --backup-dir, backup goes to "$(dirname <wiki>)" (so $HOME for
# $HOME/wiki).
# Without --yes, prompts before committing the migrated wiki to git.
#
# What it does (in order):
#   1. Backup the wiki to <backup-dir>/wiki.backup-<timestamp>/.
#   2. Run `wiki-manifest.py migrate` to consolidate the two manifests.
#   3. Walk concepts/entities/sources/queries/*.md, run
#      `wiki-normalize-frontmatter.py` on each.
#   4. Rebuild the manifest (`wiki-manifest.py build`) to populate sha256.
#   5. Run `wiki-validate-page.py --wiki-root <wiki>` on every page.
#   6. If ANY validator violation: restore backup, exit 1, print violations.
#   7. Otherwise: prompt user to commit (skipped with --yes), then exit 0.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"

yes_mode=0
wiki=""
backup_dir=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) yes_mode=1; shift;;
    --wiki-root) wiki="$2"; shift 2;;
    --backup-dir) backup_dir="$2"; shift 2;;
    *) echo >&2 "unknown arg: $1"; exit 1;;
  esac
done

[[ -z "${wiki}" ]] && wiki="${HOME}/wiki"
wiki="$(cd "${wiki}" && pwd)" || { echo >&2 "wiki not found: ${wiki}"; exit 1; }
[[ -f "${wiki}/.wiki-config" ]] || { echo >&2 "not a wiki (no .wiki-config): ${wiki}"; exit 1; }
[[ -z "${backup_dir}" ]] && backup_dir="$(dirname "${wiki}")"
mkdir -p "${backup_dir}"

timestamp="$(date +%Y%m%d-%H%M%S)"
backup="${backup_dir}/wiki.backup-${timestamp}"

echo "backup: ${backup}"
cp -R "${wiki}" "${backup}"

restore_backup() {
  echo >&2 "restoring backup from ${backup}"
  rm -rf "${wiki}"
  cp -R "${backup}" "${wiki}"
}

# 1. Manifest consolidation
python3 "${SCRIPT_DIR}/wiki-manifest.py" migrate "${wiki}" || {
  echo >&2 "manifest migrate failed"
  restore_backup
  exit 1
}

# 2. Normalize frontmatter on every page
normalize_failed=0
for category in concepts entities sources queries; do
  if [[ -d "${wiki}/${category}" ]]; then
    while IFS= read -r page; do
      if ! python3 "${SCRIPT_DIR}/wiki-normalize-frontmatter.py" --wiki-root "${wiki}" "${page}"; then
        echo >&2 "normalize failed: ${page}"
        normalize_failed=1
      fi
    done < <(find "${wiki}/${category}" -type f -name "*.md" 2>/dev/null)
  fi
done
if [[ "${normalize_failed}" -eq 1 ]]; then
  restore_backup
  exit 1
fi

# 3. Rebuild manifest to populate sha256 for all raw files
python3 "${SCRIPT_DIR}/wiki-manifest.py" build "${wiki}" || {
  echo >&2 "manifest build failed"
  restore_backup
  exit 1
}

# 4. Validate every page
violations_found=0
while IFS= read -r page; do
  if ! python3 "${SCRIPT_DIR}/wiki-validate-page.py" --wiki-root "${wiki}" "${page}" 2>&1; then
    violations_found=1
  fi
done < <(find "${wiki}/concepts" "${wiki}/entities" "${wiki}/sources" "${wiki}/queries" -type f -name "*.md" 2>/dev/null)

if [[ "${violations_found}" -eq 1 ]]; then
  echo >&2 "validator found violations; rolling back"
  restore_backup
  exit 1
fi

# 5. Optionally commit
if [[ "${yes_mode}" -eq 0 ]]; then
  echo "migration complete. review with:"
  echo "  cd ${wiki} && git status && git diff"
  echo -n "commit the migration now? [y/N] "
  read -r reply
  if [[ "${reply}" == "y" || "${reply}" == "Y" ]]; then
    (cd "${wiki}" && git add -A && git commit -m "chore: v2-hardening schema migration" >/dev/null)
    echo "committed."
  else
    echo "not committed. backup retained at ${backup}."
  fi
fi

echo "done. backup at: ${backup}"
exit 0
```

- [ ] **Step 9: Make executable, run test**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-migrate-v2-hardening.sh
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-migrate-v2-hardening.sh
```

Expected:
```
PASS: test_migrate_produces_validator_green_wiki
PASS: test_migrate_consolidates_manifest
PASS: test_migrate_preserves_body_content
PASS: test_migrate_creates_backup_when_run_against_live_like_path
PASS: test_migrate_rolls_back_on_validator_failure
ALL PASS
```

- [ ] **Step 10: DRY-RUN the migration against live `~/wiki/`**

This is a dry-run: we expect all fixtures to pass after migration, and since the live `~/wiki/` has the same classes of violations, the migration should succeed. Do NOT commit yet — just verify the backup + migration + validation chain runs clean.

Run:
```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-migrate-v2-hardening.sh
```

- Expected first line: `backup: /Users/lukaszmaj/wiki.backup-<timestamp>`
- After manifest + normalize + validate: no output on stderr about violations.
- Final line: `done. backup at: /Users/lukaszmaj/wiki.backup-<timestamp>`
- The prompt `commit the migration now? [y/N]` will appear. Respond `y` ONLY after inspecting `git status` and `git diff` in `~/wiki/` in a separate terminal. If anything looks wrong, answer `N` — the backup is retained and the implementer must investigate before proceeding.

**If the migration FAILS** on live data (a page has a shape the normalizer doesn't handle): roll back happens automatically, the backup is retained. The implementer should:
1. Add the failing shape as a new fixture under `tests/fixtures/pre-hardening-wiki/`.
2. Extend `wiki-normalize-frontmatter.py` to handle it.
3. Re-run the unit tests (both `test-normalize-frontmatter.sh` and `test-migrate-v2-hardening.sh`).
4. Re-run the live migration.

- [ ] **Step 11: Commit (two commits — one for the repo work, one for the live wiki migration if you accepted the prompt)**

Repo commit:
```bash
cd /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki
git add scripts/wiki-migrate-v2-hardening.sh scripts/wiki-normalize-frontmatter.py tests/unit/test-migrate-v2-hardening.sh tests/unit/test-normalize-frontmatter.sh tests/fixtures/pre-hardening-wiki
git commit -m "feat: v2-hardening migration script + per-page frontmatter normalizer"
```

If you accepted the live-wiki commit in Step 10, that was already committed inside `~/wiki/` — no additional work needed.

---

## Task 33: Fix the origin-loss bug in `clove-oil-eugenol-dental.md` (Fix 2)

The live page `~/wiki/concepts/clove-oil-eugenol-dental.md` currently has `sources: [raw/2026-04-24-clove-oil-dental.md]` — this part is FINE (that's the correct normalized sources list). The bug is different: the OUTER `.manifest.json` recorded `origin: "conversation"` for `raw/2026-04-24-clove-oil-dental.md`, which is wrong — the evidence file was real. The live inner `raw/.manifest.json` correctly recorded `source: /Users/lukaszmaj/dev/bigbrain/research/2026-04-24-clove-oil-dental.md`. Task 31's `migrate` subcommand merged these, preferring `origin` then `source`. Verify the merged result has `origin: "/Users/lukaszmaj/dev/bigbrain/research/2026-04-24-clove-oil-dental.md"` not `origin: "conversation"`.

**Files:**
- Modify: `/Users/lukaszmaj/wiki/.manifest.json` (live; one-time correction)
- Modify: `/Users/lukaszmaj/wiki/concepts/clove-oil-eugenol-dental.md` (live; re-run normalizer if manifest correction forces re-hash)

- [ ] **Step 1: Inspect the migrated manifest entry**

Run:
```bash
python3 -c "import json; m=json.load(open('$HOME/wiki/.manifest.json')); print(json.dumps(m['raw/2026-04-24-clove-oil-dental.md'], indent=2))"
```

Expected (post-migration): `origin` should already be `/Users/lukaszmaj/dev/bigbrain/research/2026-04-24-clove-oil-dental.md` (the inner manifest's `source` field was merged in by Task 31's migrate).

If the output still shows `"origin": "conversation"`, that means the outer manifest's `"origin": "conversation"` won the merge because it was non-empty. This was wrong — `"conversation"` was the buggy default. Correct it manually:

- [ ] **Step 2: Manual correction (only if Step 1 shows "conversation")**

Edit `~/wiki/.manifest.json`: change the `origin` value for `raw/2026-04-24-clove-oil-dental.md` from `"conversation"` to `"/Users/lukaszmaj/dev/bigbrain/research/2026-04-24-clove-oil-dental.md"`.

Verify the evidence file exists:
```bash
test -f "/Users/lukaszmaj/dev/bigbrain/research/2026-04-24-clove-oil-dental.md" && echo OK || echo MISSING
```

Expected: `OK`. If `MISSING`, leave `origin: "conversation"` but add a note in `~/wiki/log.md`: the original evidence path is unknown; the raw file was transcribed during conversation.

- [ ] **Step 3: Re-run validator on clove-oil page**

Run:
```bash
python3 /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-validate-page.py --wiki-root "$HOME/wiki" "$HOME/wiki/concepts/clove-oil-eugenol-dental.md"
```

Expected: exit 0, no stderr output.

- [ ] **Step 4: Commit in `~/wiki/`**

Run:
```bash
cd "$HOME/wiki"
git add .manifest.json
git commit -m "fix: correct origin for clove-oil raw (was 'conversation', now real path)"
```

No repo commit in this task.

---

## Task 34: SKILL.md updates — capture-format + ingest-step-4 enforce origin tracking

The skill currently tells the ingester: "If `evidence_type=file`, copy the evidence into `<wiki>/raw/` preserving basename. Update `.manifest.json`." This permits the origin-loss bug. Tighten the prose.

Changes land in SKILL.md:
1. **Capture-format section**: rename `evidence` to make its role clearer (it IS the origin), and tighten the wording so the ingester doesn't conflate `evidence_type` with `origin`.
2. **Ingest step 4**: explicit rule — `origin` in the manifest entry MUST equal the capture's `evidence` field value when `evidence_type == "file"`, or the literal string `"conversation"` when `evidence_type == "conversation"`. Never the string `"file"`.
3. **Tier-1 lint at ingest**: add a bullet — `wiki-validate-page.py --wiki-root <wiki> <page>` MUST pass on every edited page before the ingester exits.
4. **New rule in "Rules you must not break"**: "Never set `.manifest.json` `origin` to `file` / `mixed` / `conversation` when the capture's `evidence` field is a real path. `origin` is the source-of-truth pointer, not the evidence type."

**Files:**
- Modify: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md`

- [ ] **Step 1: Read the current SKILL.md capture-format section**

Quote from the current SKILL.md (lines 112-131):

```markdown
### Capture file format

Append a file to `<wiki>/.wiki-pending/` named `<ISO-timestamp>-<slug>.md`:

```markdown
---
title: "<one-line title>"
evidence: "<absolute path to evidence file, OR 'conversation'>"
evidence_type: "file"  # or "conversation" or "mixed"
suggested_action: "create"  # or "update" or "augment"
suggested_pages:
  - concepts/<slug>.md   # paths relative to wiki root
captured_at: "<ISO-8601 UTC timestamp>"
captured_by: "in-session-agent"
origin: null  # set to wiki path if propagated from satellite
---

<one paragraph summary. if evidence_type=conversation, include enough
detail for the ingester to write a page without re-reading the transcript>
```
```

Replace the `### Capture file format` subsection with the AFTER block below (same subsection boundaries):

```markdown
### Capture file format

Append a file to `<wiki>/.wiki-pending/` named `<ISO-timestamp>-<slug>.md`:

```markdown
---
title: "<one-line title>"
evidence: "<absolute path to evidence file, OR the literal string conversation>"
evidence_type: "file"  # or "conversation" or "mixed"
suggested_action: "create"  # or "update" or "augment"
suggested_pages:
  - concepts/<slug>.md   # paths relative to wiki root
captured_at: "<ISO-8601 UTC timestamp>"
captured_by: "in-session-agent"
propagated_from: null  # set to originating wiki path if propagated from satellite
---

<one paragraph summary. if evidence_type=conversation, include enough
detail for the ingester to write a page without re-reading the transcript>
```

**Field contract:**
- `evidence`: the literal string `conversation` (when the capture came from in-session discussion with no file on disk) OR an absolute filesystem path to the source file. NEVER `file`, `mixed`, or a wiki-relative path.
- `evidence_type`: one of `file`, `conversation`, `mixed`. This is a TYPE descriptor only. The ingester does not record this in the manifest; it records `evidence` (as `origin`).
- `propagated_from` (previously `origin`): renamed to prevent confusion with the manifest's `origin` field. Value: absolute path to a project wiki root, or `null`.
```

- [ ] **Step 2: Rewrite the ingest step 4**

The current SKILL.md lines 154 (ingest step 4):

```markdown
4. **If evidence_type=file**, copy the evidence into `<wiki>/raw/` preserving basename. Update `.manifest.json`.
```

Replace with:

```markdown
4. **Copy evidence, write manifest entry with correct origin:**
   - If `evidence_type` is `file` or `mixed`: `cp` the evidence file to `<wiki>/raw/<basename>` preserving basename.
   - In ALL cases (including `evidence_type=conversation`): write or update the manifest entry for the raw file in `<wiki>/.manifest.json`:
     ```json
     {
       "raw/<basename>": {
         "sha256": "<sha256 of raw file>",
         "origin": "<exact value of capture's `evidence` field>",
         "copied_at": "<iso-8601 utc, preserve if already present>",
         "last_ingested": "<iso-8601 utc, now>",
         "referenced_by": ["<pages added to this list below>"]
       }
     }
     ```
   - Always call `bash scripts/wiki-manifest.py build "${WIKI_ROOT}"` at the end of ingest to refresh sha256 and `last_ingested`. This is mandatory; the manifest is the drift-detection source of truth.
   - **Iron rule:** `origin` is the capture's `evidence` field value — never the string `"file"`, `"conversation"` (when a real path was available), `"mixed"`, or the evidence_type. If `evidence_type == "conversation"` AND the capture has no real path, `origin` is the literal string `"conversation"`. Any other value is a validator failure.
```

- [ ] **Step 3: Extend Tier-1 lint section**

Current SKILL.md lines 169-177:

```markdown
### Tier-1 lint at ingest (inline)

Before exiting, check the pages you just touched:

- Every markdown link resolves (file exists).
- Every YAML frontmatter field is valid (dates parseable, required fields present).
- `index.md` has an entry for every new page.

Fix mechanical issues silently. If a contradiction surfaces, add `contradictions:` frontmatter pointing to the conflicting page — do NOT resolve it during ingest.
```

Replace with:

```markdown
### Tier-1 lint at ingest (inline)

Before exiting, run the validator on every page you just touched:

```bash
for page in "${touched_pages[@]}"; do
  python3 "${CLAUDE_PLUGIN_ROOT}/scripts/wiki-validate-page.py" \
    --wiki-root "${WIKI_ROOT}" "${page}"
done
```

The validator checks:
- Every markdown link in the page resolves to an existing file.
- Required frontmatter fields (`title`, `type`, `tags`, `sources`, `created`, `updated`) present.
- `type` is one of `concept, entity, source, query`.
- Dates are full ISO-8601 UTC (`2026-04-24T13:00:00Z`, not `2026-04-24`).
- `sources:` is a flat list of strings (no nested mappings).
- For `type: source` pages: a matching raw file exists at `raw/<basename>.*`.
- In Phase B (post this task), also: every `quality.*` field is present and in range.

If the validator exits non-zero for any page, fix the mechanical issue and re-validate. Do NOT commit a wiki state where the validator fails.

If a contradiction surfaces, add `contradictions:` frontmatter pointing to the conflicting page — do NOT resolve it during ingest. (Contradictions are a judgement call, not a validator violation.)

Additionally: after running the validator, also run `wiki-lint-tags.py` (Phase B, Task 37) if it exists in the plugin. If it reports proposed new tags, drop a schema-proposal capture in `.wiki-pending/schema-proposals/` and continue — do NOT rename tags inline.
```

- [ ] **Step 4: Add rule 7 to "Rules you must not break"**

Current SKILL.md ends the numbered list at rule 6. Add rule 7 immediately after rule 6:

```markdown
7. **Never set `.manifest.json` `origin` to `"file"`, `"mixed"`, or the evidence type.** `origin` is the source-of-truth pointer for the raw file — the capture's `evidence` field value. If `evidence` is an absolute path, `origin` is that path. If `evidence` is the literal string `"conversation"`, `origin` is the literal string `"conversation"`. There is no third option. The clove-oil regression (Audit fix 2) happened because this distinction was fuzzy; now it is not.
```

- [ ] **Step 5: Verify SKILL.md is still < 500 lines**

Run:
```bash
wc -l /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md
```

Expected: line count should still be below 500. Current is 263; additions total roughly +35-40 lines. If above 500, move the "Tier-1 lint at ingest" expanded bullet list into `skills/karpathy-wiki/references/tier-1-lint.md` (create a new file) and leave a short pointer in SKILL.md. (Only do this if necessary.)

- [ ] **Step 6: Run self-review to confirm SKILL.md invariants still hold**

Run:
```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/self-review.sh
```

Expected: every check passes.

- [ ] **Step 7: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki
git add skills/karpathy-wiki/SKILL.md
git commit -m "feat(skill): enforce origin tracking at ingest step 4 + validator in Tier-1 lint"
```

**Phase A exit gate:** verify `bash tests/run-all.sh` is green (unit + integration) and `bash tests/self-review.sh` is green. Inspect `~/wiki/` manually — every page should now have `type`, ISO-8601 dates, flat sources, and `.manifest.json` entries should have `sha256` and correct `origin`. Only then proceed to Phase B.

---

# PHASE B — Quality surface

## Task 35: Extend `wiki-validate-page.py` with `quality:` block rules + SKILL.md ingest step 6.5

The validator from Task 30 enforces base rules. This task adds the rules for the `quality:` block (fix 3) and updates SKILL.md to document the new ingest step 6.5 (self-rate) and step 7.5 (missed-cross-link) — though the missed-cross-link BEHAVIOR itself is prose-only (no unit test; GREEN scenario 4 in Task 39 covers it).

Quality block schema (appended to the frontmatter of every `type: concept|entity|source|query` page):

```yaml
quality:
  accuracy: 4
  completeness: 3
  signal: 4
  interlinking: 3
  overall: 3.50
  rated_at: "2026-04-24T13:00:00Z"
  rated_by: "ingester"   # one of: ingester, doctor, human
  notes: "optional free-form"  # may be omitted
```

Validator rules for `quality:`:
1. Must be present on every `type: concept|entity|source|query` page.
2. `quality.accuracy`, `quality.completeness`, `quality.signal`, `quality.interlinking`: integers in `1..5`.
3. `quality.overall`: float, MUST equal `round(mean(the four scores), 2)`.
4. `quality.rated_at`: ISO-8601 UTC string.
5. `quality.rated_by`: one of `ingester`, `doctor`, `human`.
6. `quality.notes`: optional string (if present, must be string).

**Files:**
- Modify: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-validate-page.py`
- Modify: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-validate-page.sh`
- Create fixtures: `tests/fixtures/validate-page-cases/good-with-quality.md`, `quality-missing.md`, `quality-score-out-of-range.md`, `quality-overall-mismatch.md`, `quality-bad-rated-by.md`
- Modify: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md`

- [ ] **Step 1: Write the new fixtures**

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/good-with-quality.md`:

```markdown
---
title: "Good with quality"
type: concept
tags: [x]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
quality:
  accuracy: 4
  completeness: 3
  signal: 4
  interlinking: 3
  overall: 3.50
  rated_at: "2026-04-24T12:00:00Z"
  rated_by: ingester
---

Body.
```

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/quality-missing.md`:

```markdown
---
title: "Quality Missing"
type: concept
tags: [x]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

Body.
```

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/quality-score-out-of-range.md`:

```markdown
---
title: "Quality score out of range"
type: concept
tags: [x]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
quality:
  accuracy: 7
  completeness: 3
  signal: 4
  interlinking: 3
  overall: 4.25
  rated_at: "2026-04-24T12:00:00Z"
  rated_by: ingester
---

Body.
```

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/quality-overall-mismatch.md`:

```markdown
---
title: "Quality overall mismatch"
type: concept
tags: [x]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
quality:
  accuracy: 4
  completeness: 3
  signal: 4
  interlinking: 3
  overall: 9.99
  rated_at: "2026-04-24T12:00:00Z"
  rated_by: ingester
---

Body.
```

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/validate-page-cases/quality-bad-rated-by.md`:

```markdown
---
title: "Quality bad rated_by"
type: concept
tags: [x]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
quality:
  accuracy: 4
  completeness: 3
  signal: 4
  interlinking: 3
  overall: 3.50
  rated_at: "2026-04-24T12:00:00Z"
  rated_by: robot
---

Body.
```

- [ ] **Step 2: Extend the test**

Append to `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-validate-page.sh`, right before the `echo` stats block at the bottom:

```bash
# -- Phase B: quality block --
expect_exit 0 "good-with-quality passes" -- python3 "${TOOL}" "${FIX}/good-with-quality.md"
expect_exit 1 "quality-missing fails" -- python3 "${TOOL}" "${FIX}/quality-missing.md"
expect_exit 1 "quality-score-out-of-range fails" -- python3 "${TOOL}" "${FIX}/quality-score-out-of-range.md"
expect_exit 1 "quality-overall-mismatch fails" -- python3 "${TOOL}" "${FIX}/quality-overall-mismatch.md"
expect_exit 1 "quality-bad-rated-by fails" -- python3 "${TOOL}" "${FIX}/quality-bad-rated-by.md"

out="$(python3 "${TOOL}" "${FIX}/quality-missing.md" 2>&1 >/dev/null || true)"
echo "${out}" | grep -q "missing required field: quality" \
  && say_pass "stderr: quality-missing mentions missing quality" \
  || say_fail "stderr: expected 'missing required field: quality', got: ${out}"

out="$(python3 "${TOOL}" "${FIX}/quality-overall-mismatch.md" 2>&1 >/dev/null || true)"
echo "${out}" | grep -q "quality.overall" \
  && say_pass "stderr: overall-mismatch mentions quality.overall" \
  || say_fail "stderr: expected 'quality.overall' in stderr, got: ${out}"
```

- [ ] **Step 3: Run test to see failure**

Run:
```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-validate-page.sh
```

Expected: the new cases fail (validator doesn't know about `quality:` yet).

- [ ] **Step 4: Patch `wiki-validate-page.py`**

Open `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-validate-page.py`. Two changes:

(a) In the minimal YAML parser, add support for nested mappings one level deep — the `quality:` block. Extend `_parse_yaml` to handle:
```
quality:
  accuracy: 4
  completeness: 3
  ...
```
Represent the nested block as a `dict` under the top-level key.

Replace the body of `_parse_yaml` with this version:

```python
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
```

(b) In `validate()`, after the base rule checks and before the wiki-root-mode checks, add this block:

```python
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
```

Also extend `REQUIRED_FIELDS_BASE` rename to be `REQUIRED_FIELDS` (it now includes quality) — OR keep the quality check separate (preferred, so error messages are more specific). Leave `REQUIRED_FIELDS_BASE` as is and let the explicit quality check handle it.

- [ ] **Step 5: Run tests**

Run:
```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-validate-page.sh
```

Expected output (counts will include new cases):
```
PASS: good-concept passes
PASS: missing title fails
PASS: bad type fails
PASS: date-not-iso fails
PASS: sources-nested fails
PASS: no-frontmatter fails
PASS: valid cross-link passes in wiki-root mode
PASS: broken link fails in wiki-root mode
PASS: missing raw source fails in wiki-root mode
PASS: valid type=source passes in wiki-root mode
PASS: orphan type=source (no raw) fails in wiki-root mode
PASS: stderr: missing title mentions 'missing required field: title'
PASS: stderr: bad type mentions 'type must be one of'
PASS: good-with-quality passes
PASS: quality-missing fails
PASS: quality-score-out-of-range fails
PASS: quality-overall-mismatch fails
PASS: quality-bad-rated-by fails
PASS: stderr: quality-missing mentions missing quality
PASS: stderr: overall-mismatch mentions quality.overall

passed: 20
failed: 0
ALL PASS
```

Note: at this point, the base-rule tests that used NOT to have a `quality:` block (like `good-concept.md`) will NOW fail validation because quality is required. Update those fixture files to include a quality block:

Add the following lines to the frontmatter of `tests/fixtures/validate-page-cases/good-concept.md`, `wiki-root-mode/concepts/valid-cross-link.md`, `wiki-root-mode/concepts/other.md`, `wiki-root-mode/sources/2026-04-24-x.md` (NOT the deliberately-broken ones like `missing-title.md`, `broken-link.md`, etc. — those should retain their pre-quality shape since they fail other checks anyway):

```yaml
quality:
  accuracy: 4
  completeness: 4
  signal: 4
  interlinking: 4
  overall: 4.00
  rated_at: "2026-04-24T12:00:00Z"
  rated_by: ingester
```

For the `sources-nested.md`, `date-not-iso.md`, `bad-type.md`, `missing-source.md`, `orphan-source.md`, and `broken-link.md` fixtures: leave them without the quality block. They will still fail for their original reasons; the now-added "missing quality" violation is an extra violation (which is fine — multiple violations are expected).

Re-run the test. Expected: `ALL PASS` with all 20 cases.

- [ ] **Step 6: SKILL.md updates — add ingest step 6.5 and 7.5**

Current SKILL.md ingest steps (lines 149-167) list 1 through 12. Replace steps 6 through 11 with the AFTER block below (steps 1-5 and 12 remain unchanged; only inner steps change):

BEFORE (steps 6 through 11):
```markdown
6. **For each target page**:
   a. Acquire a page lock (`wiki_lock_wait_and_acquire`).
   b. Read current page content (read-before-write).
   c. Merge new material. Do NOT replace existing claims — add dated findings, use `contradictions:` frontmatter if they disagree.
   d. Release lock (`wiki_lock_release`).
7. **Update `index.md`** (locked).
8. **Append to `log.md`**.
9. **If this wiki is a project wiki** and the capture is general-interest:
   write a new capture in the main wiki's `.wiki-pending/` with `origin: <project wiki path>`.
10. **Archive the capture** from `.processing` to `.wiki-pending/archive/YYYY-MM/`: `wiki_capture_archive "${WIKI_ROOT}" "${WIKI_CAPTURE}"`.
11. **Call auto-commit** (from skill's base dir): `bash scripts/wiki-commit.sh "${WIKI_ROOT}" "ingest: <capture title>"`
```

AFTER:
```markdown
6. **For each target page**:
   a. Acquire a page lock (`wiki_lock_wait_and_acquire`).
   b. Read current page content (read-before-write).
   c. Merge new material. Do NOT replace existing claims — add dated findings, use `contradictions:` frontmatter if they disagree.
   d. Release lock (`wiki_lock_release`).
6.5. **Self-rate every page you just touched.** For each page, use the cheap model to score on four dimensions (1-5 each), compute `overall` as `round(mean, 2)`, and write the following into the page's frontmatter (creating the `quality:` block if missing, preserving `rated_by: human` if the page already has it):
   ```yaml
   quality:
     accuracy: <1-5>       # does the page match the evidence?
     completeness: <1-5>    # does the page cover the subject adequately?
     signal: <1-5>          # is the content high-signal vs filler?
     interlinking: <1-5>    # are cross-links to related pages present and correct?
     overall: <float>
     rated_at: "<ISO-8601 UTC now>"
     rated_by: ingester
   ```
   Rating criteria in one line each:
   - accuracy: does every claim map to evidence in `sources:`?
   - completeness: would a future-you searching for this topic find enough to act?
   - signal: dense knowledge vs restatement?
   - interlinking: does it link to every related page the wiki contains?
   **Never clobber `rated_by: human`.** If the existing page has `quality.rated_by == "human"`, skip this step for that page entirely.
7. **Update `index.md`** (locked). When rendering a page entry, append its overall rating: `- [Title](path/page.md) — (q: 4.25) short description`.
7.5. **Missed-cross-link check.** Pass the freshly-edited page content AND the current `index.md` content to the cheap model with this prompt: "Identify any existing wiki page in index.md that this page obviously should link to but currently does not. Return a list of (target-page-path, anchor-text) pairs, or an empty list. Do not propose new pages; only propose links to pages already in index.md." For each returned pair, insert a markdown link at a relevant point in the page (or append to a `## See also` section, creating it if absent), re-acquire the page lock, save, release. Re-validate.
8. **Append to `log.md`**.
9. **If this wiki is a project wiki** and the capture is general-interest:
   write a new capture in the main wiki's `.wiki-pending/` with `propagated_from: <project wiki path>`.
10. **Archive the capture** from `.processing` to `.wiki-pending/archive/YYYY-MM/`: `wiki_capture_archive "${WIKI_ROOT}" "${WIKI_CAPTURE}"`.
11. **Call auto-commit** (from skill's base dir): `bash scripts/wiki-commit.sh "${WIKI_ROOT}" "ingest: <capture title>"`
```

- [ ] **Step 7: SKILL.md — add rating reference section**

Append this subsection immediately after the "Numeric thresholds (from schema.md)" subsection:

```markdown
### Quality ratings — what the 4 dimensions mean

Every non-meta page (concept, entity, source, query) carries a `quality:` block in frontmatter. The block is maintained by the ingester at every ingest (step 6.5), re-rated by `wiki doctor` with a smarter model (post-MVP), and never clobbered once a human has rated.

The four dimensions (1 = terrible, 5 = excellent):

- **accuracy** — how confident we are that every claim is faithful to the cited sources. Low if the page asserts things beyond what `sources:` justifies.
- **completeness** — does the page answer what a future-you will ask? Low if the page is a thin summary of a rich source.
- **signal** — ratio of durable knowledge to restatement/filler. Low if the page is mostly boilerplate or speculation.
- **interlinking** — does the page link to every other wiki page it should link to? Low on islands.

`overall` is `round(mean(accuracy, completeness, signal, interlinking), 2)`.

`rated_by` values and semantics:
- `ingester` — set by the ingest background worker (cheap model). This is the default.
- `doctor` — set by `wiki doctor` (smartest model). Overwrites `ingester`, never `human`.
- `human` — set by the user editing the page directly. **Ingesters and doctor must never overwrite this.** Detect by `rated_by: human` in the current page's frontmatter; skip self-rating entirely for that page.

Surfaced in `index.md` per-page ( e.g. `- [Title](concepts/x.md) — (q: 3.25) description`) and in `wiki status` as a rollup ("N pages below 3.5 — run `wiki doctor`").
```

- [ ] **Step 8: Add new rationalization row to the red-flags table**

In SKILL.md, find the rationalization table (lines 221-236 in the current version). Add these new rows at the end of the table (before the `All of these are violations of the Iron Law.` sentence):

```markdown
| "The self-rating step is subjective, I'll skip it" | Ratings are mandatory. `ingester` is the default `rated_by`; leave rating accurate but lowball over missing. Every non-meta page needs a quality block — the validator will flag missing blocks. |
| "I'll give everything 5s to be safe" | 5 is exceptional. Lowballing a page to 3 flags it for `wiki doctor` review later, which is the right outcome. False 5s silently bake errors — the exact failure mode we're guarding against. |
| "I'll rewrite a human-rated page's quality because I just touched it" | Forbidden. `rated_by: human` is sacred. Touch only the body; leave the quality block alone. |
```

- [ ] **Step 9: Verify SKILL.md line count**

Run:
```bash
wc -l /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md
```

Expected: < 500. (Approx 350 after Phase B additions.)

- [ ] **Step 10: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki
git add scripts/wiki-validate-page.py tests/unit/test-validate-page.sh tests/fixtures/validate-page-cases skills/karpathy-wiki/SKILL.md
git commit -m "feat(validator+skill): quality block rules + ingest steps 6.5 and 7.5"
```

---

## Task 36: Backfill `quality:` block on every live wiki page (Fix 3)

Every page in `~/wiki/concepts/`, `~/wiki/entities/`, `~/wiki/sources/`, `~/wiki/queries/` currently has NO `quality:` block. The validator now REQUIRES one. Either:
- Run the ingester against a synthetic "re-rate" capture for each page (too expensive, requires live LLM).
- Do a one-time backfill with a deterministic default, then let the user or `wiki doctor` re-rate later.

The plan chooses the latter: create `scripts/wiki-backfill-quality.py` that walks every page, checks for `quality:`, and if missing, inserts a sentinel block:

```yaml
quality:
  accuracy: 3
  completeness: 3
  signal: 3
  interlinking: 3
  overall: 3.00
  rated_at: "<ISO-8601 UTC of now>"
  rated_by: ingester
  notes: "backfilled in v2-hardening; not yet re-rated"
```

All-3s is a deliberate "needs review" signal — `wiki status` will flag "below 3.5" for these pages (Task 38).

**Files:**
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-backfill-quality.py`
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-backfill-quality.sh`

- [ ] **Step 1: Failing test**

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-backfill-quality.sh`:

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TOOL="${REPO_ROOT}/scripts/wiki-backfill-quality.py"

setup() {
  TESTDIR="$(mktemp -d)"
  WIKI="${TESTDIR}/wiki"
  mkdir -p "${WIKI}/concepts" "${WIKI}/entities" "${WIKI}/sources" "${WIKI}/queries"
  cat > "${WIKI}/concepts/no-quality.md" <<'EOF'
---
title: "No Quality"
type: concept
tags: [x]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
---

Body.
EOF
  cat > "${WIKI}/concepts/already-has-quality.md" <<'EOF'
---
title: "Already Rated"
type: concept
tags: [x]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 5
  overall: 5.00
  rated_at: "2026-04-24T12:00:00Z"
  rated_by: human
---

Body.
EOF
}

teardown() { rm -rf "${TESTDIR}"; }

test_adds_default_quality_block() {
  setup
  python3 "${TOOL}" --wiki-root "${WIKI}"
  grep -q '^quality:$' "${WIKI}/concepts/no-quality.md" || { echo "FAIL: no-quality.md not patched"; teardown; exit 1; }
  grep -q 'rated_by: ingester' "${WIKI}/concepts/no-quality.md" || { echo "FAIL: rated_by missing"; teardown; exit 1; }
  grep -q 'overall: 3.00' "${WIKI}/concepts/no-quality.md" || { echo "FAIL: overall wrong"; teardown; exit 1; }
  echo "PASS: test_adds_default_quality_block"
  teardown
}

test_preserves_human_rated() {
  setup
  python3 "${TOOL}" --wiki-root "${WIKI}"
  grep -q 'rated_by: human' "${WIKI}/concepts/already-has-quality.md" || { echo "FAIL: human rating lost"; teardown; exit 1; }
  grep -q 'accuracy: 5' "${WIKI}/concepts/already-has-quality.md" || { echo "FAIL: scores lost"; teardown; exit 1; }
  echo "PASS: test_preserves_human_rated"
  teardown
}

test_is_idempotent() {
  setup
  python3 "${TOOL}" --wiki-root "${WIKI}"
  sha_before="$(shasum -a 256 "${WIKI}/concepts/no-quality.md" | awk '{print $1}')"
  python3 "${TOOL}" --wiki-root "${WIKI}"
  sha_after="$(shasum -a 256 "${WIKI}/concepts/no-quality.md" | awk '{print $1}')"
  [[ "${sha_before}" == "${sha_after}" ]] || { echo "FAIL: not idempotent"; teardown; exit 1; }
  echo "PASS: test_is_idempotent"
  teardown
}

test_validator_passes_after_backfill() {
  setup
  python3 "${TOOL}" --wiki-root "${WIKI}"
  python3 "${REPO_ROOT}/scripts/wiki-validate-page.py" --wiki-root "${WIKI}" "${WIKI}/concepts/no-quality.md" 2>/dev/null || {
    # The page references raw/x.md which doesn't exist -- so the other source-check would fail.
    # Create a stub raw file.
    mkdir -p "${WIKI}/raw"
    touch "${WIKI}/raw/x.md"
    python3 "${REPO_ROOT}/scripts/wiki-validate-page.py" --wiki-root "${WIKI}" "${WIKI}/concepts/no-quality.md" || {
      echo "FAIL: validator still failing after backfill"; teardown; exit 1
    }
  }
  echo "PASS: test_validator_passes_after_backfill"
  teardown
}

test_adds_default_quality_block
test_preserves_human_rated
test_is_idempotent
test_validator_passes_after_backfill
echo "ALL PASS"
```

- [ ] **Step 2: Run test to see failure**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-backfill-quality.sh
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-backfill-quality.sh
```

Expected: FAIL — script missing.

- [ ] **Step 3: Write `wiki-backfill-quality.py`**

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-backfill-quality.py`:

```python
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
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


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
```

- [ ] **Step 4: Run tests**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-backfill-quality.py
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-backfill-quality.sh
```

Expected:
```
PASS: test_adds_default_quality_block
PASS: test_preserves_human_rated
PASS: test_is_idempotent
PASS: test_validator_passes_after_backfill
ALL PASS
```

- [ ] **Step 5: Backfill live `~/wiki/`**

Run:
```bash
python3 /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-backfill-quality.py --wiki-root "$HOME/wiki"
```

Expected output: `backfilled: /Users/lukaszmaj/wiki/concepts/<each>.md` for every page missing quality, followed by `done. N page(s) backfilled.`

Then validate:
```bash
find "$HOME/wiki/concepts" "$HOME/wiki/entities" "$HOME/wiki/sources" "$HOME/wiki/queries" -type f -name "*.md" -exec python3 /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-validate-page.py --wiki-root "$HOME/wiki" {} \;
```

Expected: every page exits 0. If any exits 1, stderr will show the violation; fix manually before proceeding.

Commit in `~/wiki/`:
```bash
cd "$HOME/wiki"
git add -A
git commit -m "chore: backfill quality block on all non-meta pages"
```

- [ ] **Step 6: Commit in plan repo**

Run:
```bash
cd /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki
git add scripts/wiki-backfill-quality.py tests/unit/test-backfill-quality.sh
git commit -m "feat: wiki-backfill-quality.py + one-time live wiki backfill"
```

---

## Task 37: Tag-drift lint — `scripts/wiki-lint-tags.py` (Fix 4)

Given the set of tags currently in use (`{dentistry, dental, ...}` shows the synonym bug from the audit), every new tag an ingester proposes should either:
- match exactly an existing tag, OR
- trigger a `schema-proposal/` capture so the user (or doctor) can consolidate.

The script's rules for flagging a proposed-new tag as a synonym of an existing tag (pragmatic heuristics):
1. **Case-insensitive exact match** — not a synonym, accept.
2. **Shared prefix of >= 5 chars (case-insensitive)** — flag. `dentistry` vs `dental` share `dent` (4 chars) → not flagged. `dental` vs `dentist` share `dentist` / `dental` which share `dent` (4) → not flagged. HOWEVER `dentistry` vs `dentistries` share `dentistr` (8) → flagged.
3. **Case-insensitive Levenshtein distance <= 2 AND shorter tag length >= 4** — flag. `dental` vs `dentist` → distance 4, not flagged. `dental` vs `dentl` → distance 1, length 5 → flagged. `cat` vs `dog` → distance 3, not flagged anyway.
4. **The specific `dentistry` vs `dental` pair** — NOT flagged by the heuristics above (shared prefix only 4, distance > 2). The audit called these out as a real synonym problem, but the general heuristic does not catch them. Solution: `wiki-lint-tags.py` also reads an optional `schema.md`-embedded synonym list. If `schema.md` contains a `## Tag Synonyms` section with pairs like `- dental == dentistry`, the pair is flagged whenever both appear. (Maintained by hand; the ingester adds to the list when doctor resolves.)

Usage:
```bash
# Lint a single page's tags:
python3 wiki-lint-tags.py --wiki-root <wiki> <page-path>

# Lint all pages, report drift summary:
python3 wiki-lint-tags.py --wiki-root <wiki> --all
```

Modes:
- Single page: for each tag in the page's frontmatter, check against existing tag set (built from every other page in the wiki). Print flagged pairs on stderr. Exit 0 (never block ingest); the ingester writes a schema-proposal capture instead.
- `--all`: walk every page, build tag set, report:
  - Synonym pairs detected (via heuristics + schema synonym list).
  - Tags used by fewer than 2 pages (orphans).
  - One-line summary: "N distinct tags, M synonym pairs flagged."

**Files:**
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-lint-tags.py`
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-lint-tags.sh`

- [ ] **Step 1: Failing test**

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-lint-tags.sh`:

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TOOL="${REPO_ROOT}/scripts/wiki-lint-tags.py"

make_page() {
  local path="$1" tags="$2"
  mkdir -p "$(dirname "${path}")"
  cat > "${path}" <<EOF
---
title: "$(basename "${path}" .md)"
type: concept
tags: ${tags}
sources:
  - raw/x.md
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
}

setup() {
  TESTDIR="$(mktemp -d)"
  WIKI="${TESTDIR}/wiki"
  mkdir -p "${WIKI}/concepts"
}

teardown() { rm -rf "${TESTDIR}"; }

test_all_mode_flags_prefix_synonym() {
  setup
  make_page "${WIKI}/concepts/a.md" '[dentistry]'
  make_page "${WIKI}/concepts/b.md" '[dentistries]'
  out="$(python3 "${TOOL}" --wiki-root "${WIKI}" --all 2>&1 || true)"
  echo "${out}" | grep -q "dentistry" && echo "${out}" | grep -q "dentistries" \
    && echo "${out}" | grep -qi "synonym" \
    || { echo "FAIL: prefix synonym not flagged. out: ${out}"; teardown; exit 1; }
  echo "PASS: test_all_mode_flags_prefix_synonym"
  teardown
}

test_all_mode_flags_levenshtein_synonym() {
  setup
  make_page "${WIKI}/concepts/a.md" '[dental]'
  make_page "${WIKI}/concepts/b.md" '[dentl]'
  out="$(python3 "${TOOL}" --wiki-root "${WIKI}" --all 2>&1 || true)"
  echo "${out}" | grep -q "dental" && echo "${out}" | grep -q "dentl" \
    || { echo "FAIL: levenshtein synonym not flagged. out: ${out}"; teardown; exit 1; }
  echo "PASS: test_all_mode_flags_levenshtein_synonym"
  teardown
}

test_all_mode_respects_schema_synonym_list() {
  setup
  # Heuristics alone do NOT catch dentistry vs dental (prefix only 4,
  # distance > 2). Schema list should catch it.
  make_page "${WIKI}/concepts/a.md" '[dental]'
  make_page "${WIKI}/concepts/b.md" '[dentistry]'
  cat > "${WIKI}/schema.md" <<'EOF'
# Wiki Schema

## Tag Synonyms
- dental == dentistry
EOF
  out="$(python3 "${TOOL}" --wiki-root "${WIKI}" --all 2>&1 || true)"
  echo "${out}" | grep -qi "schema-listed synonym" \
    || { echo "FAIL: schema synonym not detected. out: ${out}"; teardown; exit 1; }
  echo "PASS: test_all_mode_respects_schema_synonym_list"
  teardown
}

test_single_page_mode_reports_new_tag() {
  setup
  make_page "${WIKI}/concepts/existing.md" '[a, b]'
  make_page "${WIKI}/concepts/new.md" '[c]'
  out="$(python3 "${TOOL}" --wiki-root "${WIKI}" "${WIKI}/concepts/new.md" 2>&1 || true)"
  echo "${out}" | grep -q "new tag: c" \
    || { echo "FAIL: new tag not surfaced. out: ${out}"; teardown; exit 1; }
  echo "PASS: test_single_page_mode_reports_new_tag"
  teardown
}

test_single_page_exit_is_zero_even_when_flagged() {
  setup
  make_page "${WIKI}/concepts/existing.md" '[a]'
  make_page "${WIKI}/concepts/new.md" '[b]'
  python3 "${TOOL}" --wiki-root "${WIKI}" "${WIKI}/concepts/new.md" 2>/dev/null
  echo "PASS: test_single_page_exit_is_zero_even_when_flagged"
  teardown
}

test_all_mode_flags_prefix_synonym
test_all_mode_flags_levenshtein_synonym
test_all_mode_respects_schema_synonym_list
test_single_page_mode_reports_new_tag
test_single_page_exit_is_zero_even_when_flagged
echo "ALL PASS"
```

- [ ] **Step 2: Run to see failure**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-lint-tags.sh
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-lint-tags.sh
```

Expected: FAIL — script missing.

- [ ] **Step 3: Write `wiki-lint-tags.py`**

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-lint-tags.py`:

```python
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
```

- [ ] **Step 4: Run tests**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-lint-tags.py
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-lint-tags.sh
```

Expected:
```
PASS: test_all_mode_flags_prefix_synonym
PASS: test_all_mode_flags_levenshtein_synonym
PASS: test_all_mode_respects_schema_synonym_list
PASS: test_single_page_mode_reports_new_tag
PASS: test_single_page_exit_is_zero_even_when_flagged
ALL PASS
```

- [ ] **Step 5: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki
git add scripts/wiki-lint-tags.py tests/unit/test-lint-tags.sh
git commit -m "feat: wiki-lint-tags.py (prefix + levenshtein + schema synonym detection)"
```

---

## Task 38: Extend `wiki-status.sh` with quality rollup + tag-drift summary (Fix 3 + Fix 4)

`wiki status` currently prints role, page count, pending/processing, locks, last ingest, drift, git. Add two new lines:
- `pages below 3.5 quality: N` (from rolling `quality.overall` across all non-meta pages)
- `tag synonyms flagged: M` (from `wiki-lint-tags.py --all`)

**Files:**
- Modify: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-status.sh`
- Modify: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-status.sh`

- [ ] **Step 1: Extend the test**

Open `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-status.sh`. Add two new test functions and extend `test_status_on_empty_wiki`:

```bash
test_status_reports_quality_rollup() {
  setup
  mkdir -p "${WIKI}/concepts"
  cat > "${WIKI}/concepts/low.md" <<'EOF'
---
title: "Low"
type: concept
tags: [x]
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
quality:
  accuracy: 2
  completeness: 2
  signal: 2
  interlinking: 2
  overall: 2.00
  rated_at: "2026-04-24T12:00:00Z"
  rated_by: ingester
---

body
EOF
  cat > "${WIKI}/concepts/high.md" <<'EOF'
---
title: "High"
type: concept
tags: [x]
sources:
  - raw/x.md
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

body
EOF
  local output
  output="$(bash "${STATUS}" "${WIKI}")"
  echo "${output}" | grep -q "pages below 3.5 quality: 1" || {
    echo "FAIL: quality rollup wrong. output: ${output}"; teardown; exit 1
  }
  echo "PASS: test_status_reports_quality_rollup"
  teardown
}

test_status_reports_tag_synonyms() {
  setup
  mkdir -p "${WIKI}/concepts"
  cat > "${WIKI}/concepts/a.md" <<'EOF'
---
title: "A"
type: concept
tags: [dentistry]
sources:
  - raw/x.md
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
  cat > "${WIKI}/concepts/b.md" <<'EOF'
---
title: "B"
type: concept
tags: [dentistries]
sources:
  - raw/x.md
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
  local output
  output="$(bash "${STATUS}" "${WIKI}")"
  echo "${output}" | grep -qE "tag synonyms flagged: [1-9]" || {
    echo "FAIL: tag synonym report missing. output: ${output}"; teardown; exit 1
  }
  echo "PASS: test_status_reports_tag_synonyms"
  teardown
}

test_status_on_empty_wiki
test_status_counts_pending
test_status_reports_quality_rollup
test_status_reports_tag_synonyms
echo "ALL PASS"
```

Also update `test_status_on_empty_wiki` so it also asserts `pages below 3.5 quality:` appears (with value 0). Update its grep block to include:
```bash
echo "${output}" | grep -q "pages below 3.5 quality:" || { echo "FAIL: quality line missing"; teardown; exit 1; }
echo "${output}" | grep -q "tag synonyms flagged:" || { echo "FAIL: synonyms line missing"; teardown; exit 1; }
```

- [ ] **Step 2: Run test to see failure**

Run:
```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-status.sh
```

Expected: new tests fail — `wiki-status.sh` doesn't emit these lines yet.

- [ ] **Step 3: Extend `wiki-status.sh`**

Open `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-status.sh`. Between the existing `git_status` block and the final `cat <<EOF` heredoc, insert:

```bash
# Quality rollup: count pages with overall < 3.5
below_35=0
while IFS= read -r page; do
  overall="$(grep -oE '^  overall: [0-9]+\.[0-9]+$' "${page}" | head -1 | awk '{print $2}')"
  if [[ -n "${overall}" ]]; then
    if awk -v v="${overall}" 'BEGIN { exit !(v < 3.5) }'; then
      below_35=$((below_35 + 1))
    fi
  fi
done < <(find "${wiki}/concepts" "${wiki}/entities" "${wiki}/sources" "${wiki}/queries" -type f -name "*.md" 2>/dev/null)

# Tag synonym count
synonym_count=0
if [[ -x "${SCRIPT_DIR}/wiki-lint-tags.py" ]]; then
  synonym_count="$(python3 "${SCRIPT_DIR}/wiki-lint-tags.py" --wiki-root "${wiki}" --all 2>/dev/null | grep -oE 'synonym pairs flagged: [0-9]+' | awk '{print $NF}')"
  [[ -z "${synonym_count}" ]] && synonym_count=0
fi
```

And update the final heredoc to include the two new lines (as the last two lines before `EOF`):

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

- [ ] **Step 4: Run tests**

Run:
```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/unit/test-status.sh
```

Expected:
```
PASS: test_status_on_empty_wiki
PASS: test_status_counts_pending
PASS: test_status_reports_quality_rollup
PASS: test_status_reports_tag_synonyms
ALL PASS
```

- [ ] **Step 5: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki
git add scripts/wiki-status.sh tests/unit/test-status.sh
git commit -m "feat(status): rollup below-3.5 quality + tag synonym count"
```

---

## Task 39: GREEN scenario 4 — missed-cross-link behavior (Fix 6)

The missed-cross-link behavior (ingest step 7.5) is model-judgment; no unit test can cover it directly. Mirror the v2 plan's GREEN-scenario pattern with a new fourth scenario.

**Files:**
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/green/GREEN-scenario-4-crosslink.md`

- [ ] **Step 1: Write scenario**

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/green/GREEN-scenario-4-crosslink.md`:

```markdown
# GREEN Scenario 4 — Missed-cross-link at ingest

**Goal:** Verify the ingester adds cross-links to obviously-related existing pages when introducing a new page on the same topic.

## Setup

- Clean `/tmp/karpathy-wiki-test-green4/`.
- Copy `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/small-wiki/` to `/tmp/karpathy-wiki-test-green4/wiki/`.
- Add a NEW raw source at `/tmp/karpathy-wiki-test-green4/wiki/raw/2026-04-24-rate-limit-detection.md` with this body:
  ```markdown
  # Detecting rate-limit hits programmatically

  When your client gets a 429, you want to know which provider returned it
  (Jina, Cloudflare Browser Rendering, etc.) so you can apply the right
  backoff. Most providers expose X-RateLimit-* headers.

  Example: Jina Reader uses X-RateLimit-Remaining. Cloudflare Browser
  Rendering uses cf-ray plus 429 status without a dedicated header.
  ```
- The existing fixture already contains `concepts/jina-reader.md`, `concepts/cloudflare-browser-rendering.md`, `concepts/rate-limiting.md` and an `index.md` listing them.

The karpathy-wiki skill IS installed.

## Scenario prompt

Run (verbatim) as a Task-tool subagent prompt:

```
You are a headless ingester invoked by the karpathy-wiki skill. WIKI_ROOT is
/tmp/karpathy-wiki-test-green4/wiki/. A new raw file exists at raw/2026-04-24-rate-limit-detection.md.
Write a capture, claim it, and ingest it per the skill's ingest steps 1-12,
including step 7.5 (missed-cross-link check).

After ingest, stop and report:
1. What concept page did you create?
2. Which existing pages did you link to from the new page?
3. Which existing pages gained backlinks to the new page?
4. Full text of the new page.
```

## Expected compliance

- Field 1: a page at `concepts/rate-limit-detection.md` (or similar slug).
- Field 2: new page links to `concepts/jina-reader.md`, `concepts/cloudflare-browser-rendering.md`, AND `concepts/rate-limiting.md` (all three are obviously related and are in the pre-existing index).
- Field 3: at least ONE of the existing pages (jina-reader, cloudflare-browser-rendering, rate-limiting) gained a backlink to the new page, either via a "## See also" section or inline reference. This is the whole point of step 7.5.
- Field 4: new page has valid frontmatter (validator-green), with `quality:` block populated, and body references at least two of the three prior pages by wiki-path.

## Failure patterns to watch for

- Agent creates the new page but links to nothing in the existing wiki. Step 7.5 SHOULD have added links.
- Agent links from the NEW page to existing pages but doesn't update the existing pages with backlinks. Step 7.5's contract is bidirectional — if page B is "obviously related", page B should gain a link too (or a "See also" entry).
- Agent "over-propagates" — creates spurious links to every page in the index. Step 7.5 limits itself to pages `index.md` and the obvious-related-to test; over-linking is also a failure.

Document failures and patch SKILL.md step 7.5 to close rationalizations (same REFACTOR loop as Scenarios 1-3 in Task 23).
```

- [ ] **Step 2: Run the scenario once and document results**

Use the Task tool with the verbatim prompt from the scenario file. Record the subagent's output in a new `## Scenario 4` section of `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/green/GREEN-results.md` (append — do NOT overwrite earlier scenarios' results).

Each of the four expected-compliance fields gets a Pass/Fail row.

- [ ] **Step 3: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki
git add tests/green/GREEN-scenario-4-crosslink.md tests/green/GREEN-results.md
git commit -m "test(GREEN): scenario 4 -- missed-cross-link at ingest (step 7.5)"
```

**Phase B exit gate:** `bash tests/run-all.sh` is green, scenario 4 has a documented GREEN pass, and `~/wiki/` has `quality:` blocks on every non-meta page.

---

# PHASE C — Content & consistency

## Task 40: Backfill missing `sources/<raw>.md` pointer pages (Fix 5)

Only `sources/2026-04-24-claude-code-dotclaude-sync-plan.md` exists. The other 4 raw files (`2026-04-23-agent-action-tokenization.md`, `2026-04-24-apple-notes-llm-integration.md`, `2026-04-24-clove-oil-dental.md`, `2026-04-24-dentin-hypersensitivity-diagnosis.md`) lack pointer pages. The validator now requires that every `type: source` have a matching raw; conversely, policy (SKILL.md) will now require every raw file to have a matching source-pointer page.

This is a one-time content backfill, not a script. The pointer page template:

```markdown
---
title: "Source: <human title>"
type: source
tags: [<copied from the concept/entity page(s) derived from this raw>]
sources:
  - raw/<basename>.md
created: "<ISO-8601 UTC of raw's copied_at>"
updated: "<ISO-8601 UTC of now>"
quality:
  accuracy: 3
  completeness: 3
  signal: 3
  interlinking: 3
  overall: 3.00
  rated_at: "<ISO-8601 UTC of now>"
  rated_by: ingester
  notes: "backfilled source-pointer page"
---

# Source: <human title>

One-paragraph summary of the raw source. Who/what/when/why.

Full document: [raw/<basename>.md](../raw/<basename>.md)

## Derived pages

- [<Title>](../concepts/<slug>.md)
- [<Title>](../entities/<slug>.md)
```

**Files (all live in `~/wiki/`):**
- Create: `/Users/lukaszmaj/wiki/sources/2026-04-23-agent-action-tokenization.md`
- Create: `/Users/lukaszmaj/wiki/sources/2026-04-24-apple-notes-llm-integration.md`
- Create: `/Users/lukaszmaj/wiki/sources/2026-04-24-clove-oil-dental.md`
- Create: `/Users/lukaszmaj/wiki/sources/2026-04-24-dentin-hypersensitivity-diagnosis.md`
- Modify: `/Users/lukaszmaj/wiki/index.md` — add four new entries under `## Sources`

- [ ] **Step 1: Create the four pointer pages**

For each raw file, produce a pointer page at `~/wiki/sources/<basename>`. Use `~/wiki/.manifest.json` to look up the `copied_at` and `referenced_by` for each raw; use that to populate the template's `created` field and the "Derived pages" section.

Example for `2026-04-23-agent-action-tokenization.md`:

```markdown
---
title: "Source: Agent Action Tokenization research (2026-04-23)"
type: source
tags: [llm-agents, tokenization, research-gap, vla]
sources:
  - raw/2026-04-23-agent-action-tokenization.md
created: "2026-04-23T21:11:21Z"
updated: "<now>"
quality:
  accuracy: 3
  completeness: 3
  signal: 3
  interlinking: 3
  overall: 3.00
  rated_at: "<now>"
  rated_by: ingester
  notes: "backfilled source-pointer page"
---

# Source: Agent Action Tokenization research (2026-04-23)

Deep research report on agent action tokenization novelty and prior art. Covers BPE/VQ-VAE applied to LLM software agent tool-call sequences and the published VLA robotics literature as comparison.

Full document: [raw/2026-04-23-agent-action-tokenization.md](../raw/2026-04-23-agent-action-tokenization.md)

## Derived pages

- [Agent Action Tokenization](../concepts/agent-action-tokenization.md)
- [Robotics Action Tokenization](../concepts/robotics-action-tokenization.md)
```

Repeat for the other three, populating fields from the manifest entries. For tags, copy from the primary derived concept page. Use the current UTC timestamp for `updated` and `rated_at`.

- [ ] **Step 2: Update `~/wiki/index.md`**

In `~/wiki/index.md`, replace the `## Sources` section with one that lists ALL five source pointer pages:

```markdown
## Sources
- [sources/2026-04-23-agent-action-tokenization.md](sources/2026-04-23-agent-action-tokenization.md) — deep research report on agent action tokenization novelty and prior art
- [sources/2026-04-24-apple-notes-llm-integration.md](sources/2026-04-24-apple-notes-llm-integration.md) — research on Apple Notes access methods, token efficiency, and MCP server landscape
- [sources/2026-04-24-claude-code-dotclaude-sync-plan.md](sources/2026-04-24-claude-code-dotclaude-sync-plan.md) — synthesized research on syncing ~/.claude across machines (git + cron pattern, pitfalls, two-tier architecture)
- [sources/2026-04-24-clove-oil-dental.md](sources/2026-04-24-clove-oil-dental.md) — Polish-language report on clove oil/eugenol in dentistry
- [sources/2026-04-24-dentin-hypersensitivity-diagnosis.md](sources/2026-04-24-dentin-hypersensitivity-diagnosis.md) — research on tooth sensitivity differential diagnosis
```

- [ ] **Step 3: Validate every new page**

Run:
```bash
for page in $HOME/wiki/sources/*.md; do
  python3 /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-validate-page.py --wiki-root "$HOME/wiki" "${page}" || echo "FAIL: ${page}"
done
```

Expected: no `FAIL:` lines.

- [ ] **Step 4: SKILL.md — add the source-pointer rule**

In SKILL.md's "Ingest → Ingester steps → step 4" (edited in Task 34), add this at the end of step 4:

```markdown
   - After copying to raw/, create a `sources/<basename>.md` pointer page IF one does not already exist. Template in `references/source-pointer-template.md` (if present) or inline in the skill's base prose. Every raw file MUST have a matching sources/ pointer page — the validator now enforces this.
```

- [ ] **Step 5: Commit both sides**

In `~/wiki/`:
```bash
cd "$HOME/wiki"
git add sources/ index.md
git commit -m "chore: backfill source-pointer pages for all raw files"
```

In plan repo:
```bash
cd /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki
git add skills/karpathy-wiki/SKILL.md
git commit -m "feat(skill): source-pointer pages are mandatory at ingest"
```

---

## Task 41: One-time ingest of the missed `sensitive-teeth-toothpaste.md` (Fix 8)

**Files:**
- Create: `/Users/lukaszmaj/wiki/.wiki-pending/<ISO-timestamp>-sensitive-teeth-toothpaste.md` (capture; will be archived)
- Expected downstream: `~/wiki/raw/2026-04-24-sensitive-teeth-toothpaste.md`, `~/wiki/sources/2026-04-24-sensitive-teeth-toothpaste.md`, and either a new `~/wiki/concepts/sensitive-teeth-toothpaste.md` OR a merged update to `~/wiki/concepts/dentin-hypersensitivity-diagnosis.md`.

- [ ] **Step 1: Write the capture by hand**

Create `/Users/lukaszmaj/wiki/.wiki-pending/2026-04-24T20-00-sensitive-teeth-toothpaste.md`:

```markdown
---
title: "Sensitive teeth: why most toothpastes hurt and what to do"
evidence: "/Users/lukaszmaj/dev/bigbrain/research/2026-04-24-sensitive-teeth-toothpaste.md"
evidence_type: "file"
suggested_action: "create"
suggested_pages:
  - concepts/sensitive-teeth-toothpaste.md
captured_at: "2026-04-24T20:00:00Z"
captured_by: "human-one-time-backfill"
propagated_from: null
---

Polish-language research report on toothpaste ingredient tolerance for patients with sensitive teeth and mucosa. Complements the differential-diagnosis framing in concepts/dentin-hypersensitivity-diagnosis.md with concrete toothpaste choice criteria (SLS-free, RDA thresholds, compatible-with-DH brands). Ingester should either create concepts/sensitive-teeth-toothpaste.md and cross-link both pages, OR merge the toothpaste-specific content into the existing differential-diagnosis page with clear section separation — the ingester judges based on content overlap.
```

- [ ] **Step 2: Spawn the ingester**

Run:
```bash
cd "$HOME/wiki"
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-spawn-ingester.sh \
  "$HOME/wiki" \
  "$HOME/wiki/.wiki-pending/2026-04-24T20-00-sensitive-teeth-toothpaste.md"
```

Expected: spawn returns in < 2s. The ingester runs in the background; output goes to `~/wiki/.ingest.log`. After a minute or two (real LLM call):
- The capture is archived to `~/wiki/.wiki-pending/archive/2026-04/`.
- The raw file exists at `~/wiki/raw/2026-04-24-sensitive-teeth-toothpaste.md`.
- A source-pointer page exists at `~/wiki/sources/2026-04-24-sensitive-teeth-toothpaste.md`.
- Either `~/wiki/concepts/sensitive-teeth-toothpaste.md` exists OR `~/wiki/concepts/dentin-hypersensitivity-diagnosis.md` has been updated with a new section.
- `~/wiki/index.md` has been updated.
- `~/wiki/.manifest.json` has a new entry with `sha256`, `origin: "/Users/lukaszmaj/dev/bigbrain/research/2026-04-24-sensitive-teeth-toothpaste.md"`, and `referenced_by` listing the new / updated pages.
- Git log in `~/wiki/` shows a new `ingest: ...` commit.

- [ ] **Step 3: Validate result**

Run:
```bash
find $HOME/wiki/concepts $HOME/wiki/entities $HOME/wiki/sources $HOME/wiki/queries -type f -name "*.md" \
  -exec python3 /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-validate-page.py --wiki-root "$HOME/wiki" {} \;
```

Expected: all pages exit 0. If any fail, fix manually (the ingester should have produced a validator-green result; if it didn't, that's a real ingester regression — investigate before continuing).

- [ ] **Step 4: No repo commit needed**

All state changed in `~/wiki/`. If the ingester's auto-commit ran, the work is already committed there.

---

## Task 42: Prune `entities/electron-nwjs-steam-wrapper.md` to a stub (Fix 9)

The entities page duplicates content from `concepts/threejs-steam-publishing.md`. Cut to a link-only stub.

**Files:**
- Modify: `/Users/lukaszmaj/wiki/entities/electron-nwjs-steam-wrapper.md`

- [ ] **Step 1: Replace page content**

Overwrite `/Users/lukaszmaj/wiki/entities/electron-nwjs-steam-wrapper.md` entirely with:

```markdown
---
title: "Electron / NW.js as Steam Wrapper for Web Games"
type: entity
tags: [electron, nwjs, steam, wrapper, webgl, gamedev]
sources:
  - raw/2026-04-24-threejs-steam.md
created: "2026-04-24T00:00:00Z"
updated: "<now>"
quality:
  accuracy: 3
  completeness: 2
  signal: 2
  interlinking: 4
  overall: 2.75
  rated_at: "<now>"
  rated_by: ingester
  notes: "stub -- content lives on concepts/threejs-steam-publishing.md; keep this page only if unique entity metadata accrues"
---

# Electron / NW.js as Steam Wrapper for Web Games

Stub entity page. All substantive content lives on
[Publishing a Three.js WebGL Game on Steam](../concepts/threejs-steam-publishing.md).

This page exists so that future-you searching the entity name lands somewhere.
When enough unique entity-level content accumulates (version history,
integration-gotcha timeline, per-vendor Steam Workshop compatibility notes),
promote it back to a full page.
```

Replace `<now>` with the current ISO-8601 UTC timestamp.

- [ ] **Step 2: Remove the raw source reference if no such raw exists**

Check: does `~/wiki/raw/2026-04-24-threejs-steam.md` exist?
```bash
test -f "$HOME/wiki/raw/2026-04-24-threejs-steam.md" && echo OK || echo MISSING
```

If MISSING: change the `sources:` value to `- conversation` (a flat string, per the frontmatter rules). This matches the concept page's original `sources: - conversation: "2026-04-24 research session"` which, after Phase A normalization, became `sources: - conversation`.

- [ ] **Step 3: Validate**

Run:
```bash
python3 /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-validate-page.py --wiki-root "$HOME/wiki" "$HOME/wiki/entities/electron-nwjs-steam-wrapper.md"
```

Expected: exit 0.

- [ ] **Step 4: Commit in `~/wiki/`**

Run:
```bash
cd "$HOME/wiki"
git add entities/electron-nwjs-steam-wrapper.md
git commit -m "refactor: prune electron-nwjs entity to stub pointing at concept page"
```

---

## Task 43: Add `#personal` tag to taxonomy and re-tag dentin-hypersensitivity anecdote (Fix 10)

The dentin-hypersensitivity page mixes clinical content with a 10-year patient-specific anecdote. Tag the anecdote. Add `#personal` to the bounded taxonomy in `schema.md`.

**Files:**
- Modify: `/Users/lukaszmaj/wiki/schema.md`
- Modify: `/Users/lukaszmaj/wiki/concepts/dentin-hypersensitivity-diagnosis.md`

- [ ] **Step 1: Update `~/wiki/schema.md`**

Read current `~/wiki/schema.md`. Replace the `## Tag Taxonomy (bounded)` section with:

```markdown
## Tag Taxonomy (bounded)

The following tags are evolved by the ingester; `wiki-lint-tags.py` flags drift. Propose new tags via schema-proposal captures, not inline.

### Reserved meta-tags

- `#personal` — patient-specific, user-specific, or otherwise n-of-1 observations. Adding this tag to a page (or to a section anchor) marks the content as not-generalizable evidence. Clinical, scientific, and how-to pages that cite personal experience MUST apply `#personal` either page-wide (if the page is primarily anecdotal) or inline via a `> personal` blockquote before the anecdote.
- `#research-gap` — documents absence of evidence; not a claim.
- `#contradicts` — applied to a page that explicitly disagrees with another page in the wiki.

### Domain tags

Grow organically; no closed list. See `wiki-lint-tags.py --all` for the live set.
```

- [ ] **Step 2: Add `#personal` to the dentin-hypersensitivity page**

Open `~/wiki/concepts/dentin-hypersensitivity-diagnosis.md`. In the frontmatter, extend `tags:` to include `personal`:

```yaml
tags: [dental, health, diagnosis, sensitivity, SLS, allergy, bruxism, personal]
```

Additionally, wrap the "10-year exclusive tolerance" paragraph in a blockquote and prefix it with `> personal`:

Find this paragraph (around section 5):

```markdown
**10-year exclusive tolerance of Elmex Sensitive Pro OptiNamel** (no SLS, RDA <40, olaflur + chitosan) strongly points to SLS and/or high-RDA abrasion as the primary driver -- but requires clinical confirmation.
```

Replace with:

```markdown
> personal
>
> **10-year exclusive tolerance of Elmex Sensitive Pro OptiNamel** (no SLS, RDA <40, olaflur + chitosan) strongly points to SLS and/or high-RDA abrasion as the primary driver for this specific patient -- but requires clinical confirmation and is n-of-1 evidence, not a population finding.
```

- [ ] **Step 3: Validate**

Run:
```bash
python3 /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-validate-page.py --wiki-root "$HOME/wiki" "$HOME/wiki/concepts/dentin-hypersensitivity-diagnosis.md"
```

Expected: exit 0.

Also confirm the lint-tags script recognizes `personal` as a tag:
```bash
python3 /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-lint-tags.py --wiki-root "$HOME/wiki" --all
```

Expected: `personal` appears in the tag list (no synonym warning — it is unique).

- [ ] **Step 4: Commit in `~/wiki/`**

Run:
```bash
cd "$HOME/wiki"
git add schema.md concepts/dentin-hypersensitivity-diagnosis.md
git commit -m "chore: add #personal reserved meta-tag; tag dentin-hypersensitivity anecdote"
```

---

## Task 44: End-of-Phase-C validation sweep

After Tasks 40-43, every page in `~/wiki/` MUST pass the validator. This task is a gate, not a change.

**Files:** none modified.

- [ ] **Step 1: Run validator on every page**

Run:
```bash
find "$HOME/wiki/concepts" "$HOME/wiki/entities" "$HOME/wiki/sources" "$HOME/wiki/queries" \
  -type f -name "*.md" \
  -exec python3 /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-validate-page.py --wiki-root "$HOME/wiki" {} \;
```

Expected: NO stderr output. If ANY page fails, investigate and fix before continuing. Failures at this point usually mean the ingester in Task 41 produced a page that doesn't meet the new schema — that's a real bug and must be fixed (either patch the page manually, or re-ingest with the missing fields supplied).

- [ ] **Step 2: Run full test suite**

Run:
```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/run-all.sh
```

Expected: `failed: 0`.

- [ ] **Step 3: Run self-review**

Run:
```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/self-review.sh
```

Expected: every check passes.

- [ ] **Step 4: No commit needed**

This task changes no files.

---

## Task 45: Final acceptance

**Files:**
- Create: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/hardening-acceptance.md`

- [ ] **Step 1: Write acceptance notes**

Create `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/hardening-acceptance.md`:

```markdown
# v2-hardening acceptance (Tasks 30-44)

Date: <fill at execution>

## Acceptance checks

- [ ] `bash tests/run-all.sh` exits 0 (unit + integration).
- [ ] `bash tests/self-review.sh` exits 0 (mechanical invariants green).
- [ ] For every page under `~/wiki/concepts|entities|sources|queries`, `wiki-validate-page.py --wiki-root ~/wiki` exits 0.
- [ ] `~/wiki/.manifest.json` has exactly one entry per file under `~/wiki/raw/`, each with sha256, origin (non-empty or the literal "conversation"), copied_at, last_ingested, referenced_by.
- [ ] `~/wiki/raw/.manifest.json` does not exist.
- [ ] `~/wiki/entities/electron-nwjs-steam-wrapper.md` is a stub (< 20 lines) pointing at `concepts/threejs-steam-publishing.md`.
- [ ] `~/wiki/concepts/dentin-hypersensitivity-diagnosis.md` has `personal` in its tag list and the 10-year anecdote is in a `> personal` blockquote.
- [ ] `~/wiki/schema.md` has the "Reserved meta-tags" section with `#personal`.
- [ ] GREEN-results.md has a Scenario 4 section documenting the missed-cross-link behavior.
- [ ] User has manually inspected `wiki status` output from inside `~/wiki/` and confirms the new lines (`pages below 3.5 quality`, `tag synonyms flagged`) read sensibly.

## Manual sign-off

Signed off by user: ____________   Date: ____________
```

- [ ] **Step 2: Walk the checklist**

Perform every check-box above against the live state. For each: check the box, or surface the gap back to the plan. Don't commit until every box is checked.

- [ ] **Step 3: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki
git add tests/hardening-acceptance.md
git commit -m "test: v2-hardening acceptance checklist"
```

---

## Deferred to later

This plan lands the 10 fixes cleanly. It does NOT re-run the Opus audit.

After the user has used the post-hardening wiki for a period of real-session work and accumulated 5-10 more ingests, we re-run the Opus audit against the then-current `~/wiki/`, diff the findings against this plan's fixes, and decide what (if anything) needs a v2.2-hardening plan. This is a separate activity from this plan; this plan ends at the fixes landing cleanly.

Likely future audit targets (not commitments):
- Whether `quality.overall < 3.5` pages cluster in any particular category or tag — signal the ingester is chronically over-cautious in a domain.
- Whether tag-drift repeats despite `wiki-lint-tags.py` — heuristics may need tuning.
- Whether `sources/` pointer pages degenerate into dead formality (only 1-2 lines each) and should merge into `raw/` metadata.
- Whether the `quality:` block should carry a per-dimension rationale field (currently only overall `notes`).
- Whether `wiki doctor` should actually be implemented now that there is a rating surface to rate against.

Re-audit is not scoped here. This plan ends.

---

## Execution

Plan complete. The executing subagent dispatcher should run each task as its own Task-tool spawn in Phase order (A → B → C), with the subagent-driven-development skill loaded. Expected task count: 16 commits in this repo (Tasks 30-44, plus Task 45 acceptance file), plus approximately 3-5 commits inside `~/wiki/` (Task 32 migration if accepted, Task 33 manifest correction, Task 36 quality backfill, Task 40 source-pointer pages, Task 41 toothpaste ingest auto-commit, Task 42 stub, Task 43 tag + schema).

---

### Critical Files for Implementation

- `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-validate-page.py` (new, Task 30 + extended in Task 35) — enforcement engine.
- `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-manifest.py` (extended Task 31) — adds `sha256` + `migrate` subcommand.
- `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-migrate-v2-hardening.sh` (new, Task 32) — backup + rollback-safe live-wiki migration.
- `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/scripts/wiki-normalize-frontmatter.py` (new, Task 32) — per-page frontmatter normalization.
- `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md` (modified Tasks 34, 35, 40) — ingest-step prose is the contract every ingest subagent reads.