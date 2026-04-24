# Karpathy Wiki v2.2 — Design Spec

**Date:** 2026-04-24
**Branch:** `v2-rewrite` (continues; not merged to main)
**Source audit:** `docs/planning/2026-04-24-karpathy-wiki-v2.2-audit.md` (16 findings)
**Predecessors:** v2 (29 tasks), v2-hardening (10 fixes), v2.1 missed-capture patch
**Scope:** 6 fixes from the audit, packaged as one phased plan. Headlined by an architectural cut: kill `sources/` as a wiki category.

---

## Goal

Remove an architectural mistake (`sources/` pointer-page category that duplicates information already in `manifest.json` and concept-page frontmatter) and close five mechanical gaps the audit surfaced. Net result: 31 fewer pages in the wiki, three audit findings dissolved, one quality cluster gone, and five silent quality-drift bugs sealed.

## Non-goals (deliberately deferred to v2.3 / `wiki doctor`)

- Source-pointer body floor (Finding 05) — moot once category is deleted.
- Tag-drift schema-proposal auto-write + `#`-prefix decision (Finding 07) — needs a design call separate from this plan.
- Interlinking dimension redefinition (Finding 08) — needs full inbound-link graph; doctor's job.
- Source-pointer duplicate consolidation (Finding 09) — moot once category is deleted.
- Rating staleness validator (Finding 10) — small but unrelated; ships when convenient.
- Per-dimension bias correction (Finding 11) — needs doctor's smart re-rate.
- Concept-existence short-circuit on recovery (Finding 12) — needs careful test surface; defer.
- SKILL.md prose voice (Finding 13) — cosmetic.
- Synonym false-positive allowlist (Finding 15) — small.
- `related:` vs `sources:` validator distinction (Finding 16) — small.

These items remain on TODO.md unchanged. The audit comparison will be re-run after v2.2 lands; some defers may close themselves.

## Architectural decision: kill `sources/`

### What `sources/<basename>.md` was supposed to do

A pointer page per raw file with three jobs:

1. Reverse lookup: "which concept pages cite this raw?"
2. Provenance: "where did this raw come from?"
3. Summary: "what's in the raw without opening it?"

### What already does each of those jobs

| Job | Existing replacement | Where |
|---|---|---|
| Reverse lookup | `manifest.json` → `referenced_by: [...]` | `~/wiki/.manifest.json` |
| Provenance | `manifest.json` → `origin` | `~/wiki/.manifest.json` |
| Summary | The concept page IS the summary | `~/wiki/concepts/<slug>.md` |

### Evidence the category isn't earning its keep

- 15 concept pages cite `raw/foo.md` directly in their `sources:` frontmatter.
- 3 concept pages cite `sources/foo.md` (will be migrated to `raw/foo.md`).
- Only 3 markdown links anywhere in the wiki point at `sources/...` pages.
- 5 of the 11 lowest-quality pages in the wiki are these stub pointer pages, all rated `quality.overall: 3.0`. The cluster the audit's TODO predicted.
- Audit findings 02, 05, and 09 all collapse into "this category shouldn't exist."

### What's lost

Discoverability of "what raw files do we have?" is no longer in `index.md`. Replacement: `ls ~/wiki/raw/` or `cat ~/wiki/.manifest.json`. We deliberately do NOT auto-render a Sources section in `index.md` because index.md is already over the 8KB orientation threshold (Finding 01).

### What's kept

Everything that mattered. Concept pages still cite their raws. Manifest still tracks every raw with sha256 + origin + referenced_by. `git log -- wiki/sources/` recovers any deleted page.

---

## Scope: 6 fixes, 3 phases

### Phase A — Architectural cut: kill `sources/` (Findings 02, 05, 09 — collapsed)

A1. **Remove `type: source` from validator type whitelist** (`wiki-validate-page.py`).
A2. **Remove `sources/` rules from SKILL.md:**
   - Ingest step 4 — drop the "create a `sources/<basename>.md` pointer page" sub-bullet.
   - Drop any examples of `sources/foo.md` in body or frontmatter sketches.
   - Step 6 page-touch list — drop `sources/` mention.
   - One-pass scan after surgical edits for newly-redundant prose (the D2 contract); if found, remove. If not, ship as D1.
A3. **Remove `sources/` from schema.md categories list.**
A4. **Update `wiki-status.sh`** to stop counting/reporting a `sources/` directory.
A5. **Live wiki migration (Phase D):**
   - `git rm -r ~/wiki/sources/` — 31 files removed.
   - Fix 3 concept pages whose `sources:` frontmatter cites `sources/...` → re-point to `raw/...`.
   - Backfill: re-run validator on every page in `~/wiki/`; expect green.

### Phase B — Validator + ingester safety (Findings 04, 06)

B1. **Validator skips markdown links inside fenced code blocks and inline code spans** (`wiki-validate-page.py._extract_body_links`). Closes the `[Jina Reader](concepts/jina-reader.md)` example-text false positive.
B2. **Ingester gates `wiki-commit.sh` on validator success.** SKILL.md ingest step 12 wording change: "the ingester MUST NOT call `wiki-commit.sh` if the validator exits non-zero for any touched page." Wire the assertion into the ingester prompt and into `wiki-spawn-ingester.sh`'s post-run check.
B3. **Manifest `validate` subcommand** added to `wiki-manifest.py`. Verifies every entry has non-empty `origin` matching either the literal `"conversation"` or an absolute path. Returns nonzero on any violation.
B4. **SKILL.md Iron Rule #7 strengthened** — explicit "empty origin is a violation" clause. Currently the enumeration omits the empty case (which is how the 2 live empty-origin entries slipped through).
B5. **Live wiki migration (Phase D):**
   - Fix the 7 broken markdown links surfaced by Finding 04 (in 5 pages: `wiki-obsidian-integration.md`, `starship-terminal-theming.md`, two source pages now-deleted in Phase A, `2026-04-24T17-27-08Z-starship-terminal-themes.md`).
   - Fix the 2 empty-origin manifest entries (`2026-04-24-copyparty-serve-deny-limits.md`, `2026-04-24-yazi-install-gotchas.md`) — set `origin: conversation`.

### Phase C — Mechanism wiring (Findings 01, 03, 14)

C1. **Index.md threshold actually fires.** Add ingest step 7.6: after updating `index.md`, measure byte size. If > 8 KB, append a `.wiki-pending/schema-proposals/<ts>-index-split.md` capture. Do not block ingest. Do not split inline.
C2. **`wiki-status.sh` surfaces the index-size warning** alongside the existing rollups. Format: `index.md: 25 KB / 76 entries — over 8 KB threshold; consider atom-ization`.
C3. **Atom-ization shape decision (in this design doc, not the plan):** when the threshold fires, what does the schema-proposal recommend? Recommendation: **per-category sub-indexes** (`index/concepts.md`, `index/entities.md`, `index/ideas.md`, `index/queries.md`), with `index.md` becoming a 5-line MOC pointing at each. Rationale: matches existing wiki structure (one dir per category), each sub-index can grow independently, agents reading `index.md` get cheap orientation and can drill down. Per-tag MOCs were considered but rejected as premature (only 4 categories now; tags would multiply files).
C4. **`.processing` suffix archive bug.** `wiki_capture_archive()` in `wiki-lib.sh` strips trailing `.processing` before `mv`. SKILL.md step 10 prose tightened to state the suffix is stripped.
C5. **`wiki-status.sh` "last ingest" bug.** Read max `last_ingested` from `manifest.json` instead of whatever it currently does (likely greps log.md or asks git).
C6. **Live wiki migration (Phase D):**
   - Rename 4 stalled archive files: `~/wiki/.wiki-pending/archive/2026-04/*.md.processing` → `*.md`.
   - Fire one schema-proposal capture for the existing 25 KB index.md (so the proposal exists in the wiki even though the threshold check just got wired).

### Phase D — Live wiki migration (single backfill script)

D1. **Backup tarball** as Task 0 of Phase D: `tar czf ~/wiki-backup-pre-v2.2-<utc-iso>.tar.gz ~/wiki/`.
D2. **One script: `scripts/wiki-migrate-v2.2.sh`** — named functions for each migration:
   - `migrate_remove_sources_category()` — git-rm of `sources/`, plus rewriting the 3 concept page `sources:` refs.
   - `migrate_manifest_repair()` — set `origin: conversation` on 2 entries.
   - `migrate_archive_processing_suffix()` — rename 4 `.md.processing` → `.md` in archive.
   - `migrate_broken_links()` — repair 7 broken links (mostly the `## See also` paths that use `concepts/` prefix when both linker and linkee are in the same dir).
   - `migrate_fire_index_split_proposal()` — write the one-time schema-proposal capture for the index.
   - `main()` orchestrates with `--dry-run` flag.
D3. **Run validator over every page in `~/wiki/`**; expect green.
D4. **Run `wiki-manifest.py validate`** on `~/wiki/.manifest.json`; expect green.

---

## Test surface

Each phase adds unit tests following v2 conventions (`tests/unit/test-*.sh`, PASS/FAIL prefix, exit-1 on any FAIL).

| Phase | Test |
|---|---|
| A | `tests/unit/test-validate-no-source-type.sh`: fixture page in `sources/` dir with `type: source` → validator emits "type 'source' is not in allowed types" (whitelist no longer includes it). |
| A | `tests/unit/test-skill-md-no-source-rule.sh`: `grep -c 'sources/<basename>' SKILL.md` returns 0. |
| B | `tests/unit/test-validate-code-block-skip.sh`: fixture page with `[broken](nope.md)` inside ` ```fenced``` ` and inside `` `inline` `` → validator emits 0 violations. |
| B | `tests/unit/test-manifest-validate.sh`: fixture manifest with `"origin": ""` → `wiki-manifest.py validate` exits 1. |
| B | `tests/unit/test-ingester-commit-gate.sh`: fixture ingest where validator emits violation → `wiki-commit.sh` is NOT called (mock the commit script, assert it didn't fire). |
| C | `tests/unit/test-index-threshold-fires.sh`: fixture wiki with `index.md` of 9 KB → after a mocked ingest step 7.6, a `.wiki-pending/schema-proposals/*-index-split.md` capture exists. |
| C | `tests/unit/test-archive-strips-processing.sh`: call `wiki_capture_archive` on `<x>.md.processing` → archived basename ends in `.md`, not `.md.processing`. |
| C | `tests/unit/test-status-last-ingest.sh`: fixture manifest with `last_ingested: 2026-05-01T12:00:00Z` → `wiki status` output line matches `last ingest: 2026-05-01`. |
| D | `tests/integration/test-migration-dry-run.sh`: run `wiki-migrate-v2.2.sh --dry-run` against the live wiki snapshot; verify expected mutations are listed but no files change. |

---

## Out of scope (do not litigate during implementation)

- New wiki categories
- `wiki doctor` implementation
- Stop-hook gate
- SessionStart hook injection
- `--bare` / `--max-turns` ingester flags
- Cross-platform support
- Performance / fsync / parallel ingest
- Anything in TODO.md not explicitly named in scope above

---

## Risks

| Risk | Mitigation |
|---|---|
| `git rm sources/` deletes a page someone wanted to keep | Backup tarball at Phase D start. `git log -- wiki/sources/` recovers any page. |
| The 3 concept-page `sources:` rewrites break frontmatter | Validator runs after rewrite; any malformed YAML surfaces. |
| Validator code-block skip regex over-strips | Unit test (`test-validate-code-block-skip.sh`) covers fenced + inline. |
| Empty-origin guard breaks an existing legitimate use case | Audit found 0 cases where empty-origin was intentional. The 2 live cases are bugs. |
| Index threshold proposal fires on every ingest after threshold met | Step 7.6 should check whether a recent (≤24h) `index-split` schema-proposal already exists; skip if so. Document this in SKILL.md. |
| Migration script `--dry-run` lies (says it will do X but live run does Y) | Dry-run uses the same code paths, just suppresses mv/rm/write. Test asserts dry-run output matches live-run mutation list. |
| Live wiki has accumulated state we don't know about | Phase D step 1 is `validator-run-everywhere`; surfaces unknowns before mutation. |

---

## Style / discipline (carries over from v2-hardening)

- Each task lands as its own commit on `v2-rewrite`.
- TDD where applicable: RED (test, run, fail) → GREEN (script, run, pass) → REFACTOR.
- `**Files:**` block on every task listing absolute paths.
- Numbered `- [ ] **Step N: ...`** checkbox steps.
- Verbatim test bodies and script bodies. No placeholders.
- Shell: `set -e` for fail-fast, `set -uo pipefail` for hooks. Python: stdlib only, version check rejects < 3.11.
- SKILL.md edits: BEFORE block verbatim, AFTER block verbatim. Not just a description.
- Final SKILL.md MUST stay ≤ 500 lines. Currently 455. Phase A removals give ~15 lines of additional headroom.

## Acceptance

Phase A done when:
- Validator no longer accepts `type: source`.
- SKILL.md no longer mentions `sources/<basename>.md` rule.
- Schema.md no longer lists `sources/` as a category.
- All Phase A unit tests green.

Phase B done when:
- Validator skips code-block links.
- Manifest `validate` subcommand exists and works.
- SKILL.md Iron Rule #7 covers empty-origin case.
- Ingester commit-gate wording in SKILL.md.
- All Phase B unit tests green.

Phase C done when:
- Index threshold fires schema-proposal capture (verified via fixture).
- `wiki-status.sh` surfaces index-size warning.
- `wiki_capture_archive` strips `.processing`.
- `wiki-status.sh` reads last-ingest from manifest.
- All Phase C unit tests green.

Phase D done when:
- `~/wiki/sources/` removed.
- 3 concept-page `sources:` refs fixed.
- 2 manifest entries repaired.
- 4 archived `.processing` files renamed.
- Validator passes on every page in `~/wiki/`.
- `wiki-manifest.py validate` passes on `~/wiki/.manifest.json`.
- One schema-proposal capture for index.md split exists in `.wiki-pending/schema-proposals/`.

Plan acceptance: all four phases complete, `tests/run-all.sh` green, the live `~/wiki/` validates clean.

---

End of design.
