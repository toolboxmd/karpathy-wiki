---
title: karpathy-wiki — TODO / backlog
status: living-document
last_reviewed: 2026-04-24  # post-v2.2 ship; next audit due after 5-10 more real-session ingests
convention:
  "One ## section per issue. Each section has its own YAML frontmatter block at
  the top."
---

# karpathy-wiki — TODO / backlog

Deferred items for the plugin itself (NOT for the content the plugin produces —
that lives in the wiki). This file serves as a lightweight stand-in for GitHub
Issues while the project is pre-merge to `main`. When ready, these migrate to
GitHub Issues on `toolboxmd/karpathy-wiki` with matching labels. Until then,
edit this file: add items at the top, move shipped items to the "Shipped"
section at the bottom, delete rejected items (their rationale lives in the
commit history of this file).

**How to add an item:** append a new `##` section with the YAML block below,
fill every field, link into the referencing plan/commit/concept page.

**Frontmatter field contract:**

- `status` — `open | deferred | blocked | rejected | shipped`. `open` = fair
  game; `deferred` = has revisit criteria; `blocked` = waiting on upstream;
  `rejected` = decided against (leave in place as "don't re-propose" record);
  `shipped` = closed, moved to Shipped section below.
- `priority` — `p0 | p1 | p2 | p3`. Loose ordering. p0 = blocks next plan; p3 =
  nice-to-have.
- `effort` — `low | medium | high`. Rough T-shirt sizing.
- `labels` — free-form tags for cross-cutting categorization (e.g. `post-mvp`,
  `defers-to-anthropic`, `ux`, `test-infra`).
- `revisit_when` — short sentence naming the concrete condition under which this
  becomes priority-bumped. Required for `status: deferred | blocked`.
- `refs` — backlinks to plan docs, commits, wiki pages, GitHub issues.

---

## `wiki-migrate-v2.2.sh`: regex misses inline-list `sources:` frontmatter

```yaml
status: open
priority: p3
effort: low
labels: [post-mvp, migration-script, known-imperfection]
revisit_when:
  "Any future v2.2-style migration is planned, OR a wiki-doctor pass needs
  to rewrite frontmatter sources entries en masse."
refs:
  - scripts/wiki-migrate-v2.2.sh (`migrate_rewrite_frontmatter_sources`,
    line ~67, regex `^(  - )sources/`)
  - docs/superpowers/plans/2026-04-24-karpathy-wiki-v2.2.md (Task 60)
```

The migration script's frontmatter regex `^(  - )sources/` only matches the
block-list form (each item on its own line with `  - ` prefix), not the
inline-list form (`sources: ["sources/x"]` on one line). During Task 61's
live run against `~/wiki/`, the script silently missed
`concepts/micro-editor-over-nano.md` because that page used inline-list
form; the implementer manually rewrote it after the page validator caught
the dangling reference. No data loss, but the script is incomplete. Sharpen
to handle both forms (probably by switching from grep+sed to a YAML-aware
Python rewrite) before any v2.2-style migration reruns.

---

## Subagent reformatting hazard: TODO.md autoformatted on Task 62 commit

```yaml
status: open
priority: p3
effort: low
labels: [process, subagent-discipline, known-imperfection]
revisit_when:
  "If subagent commits keep accumulating off-scope reformatting noise, OR a
  pre-commit hook is added that enforces wrap-width."
refs:
  - commit a832fa5 (Task 62 -- 230-line diff for what should have been a
    section move + 2 frontmatter edits)
  - docs/superpowers/plans/2026-04-24-karpathy-wiki-v2.2.md (Task 62 spec)
```

The Task 62 implementer subagent reflowed the entire TODO.md to ~80-char
wrap as part of its section-move commit (171 insertions, 59 deletions for
substantively a 1-section move + 2 frontmatter line edits). The task brief
said "do not touch any other file"; technically respected (only TODO.md
changed) but spiritually violated (reformatted untouched lines). The reflow
is harmless and arguably an improvement to file readability, but creates
diff noise that obscures real changes in `git log -p`.

Two paths to address: (a) `git revert a832fa5 && redo` for a minimal-diff
version, or (b) accept the reformat and add an explicit "do not reformat
unrelated lines" clause to future implementer prompts. Recommend (b) plus
a shared subagent prompt template that includes the no-reformat clause.

---

## Stop-hook gate for turn-closure enforcement

```yaml
status: deferred
priority: p1
effort: medium
labels: [post-mvp, architecture]
revisit_when:
  "Fresh-session tests show main agent still skipping captures despite the v2.1
  prose gate, OR 3+ real-session misses where the `ls .wiki-pending/`
  pre-stop-turn check didn't fire."
refs:
  - docs/planning/2026-04-24-karpathy-wiki-v2.1-missed-capture-patch.md#deferred-to-later
  - skills/karpathy-wiki/SKILL.md (turn-closure prose at "Turn closure — before
    you stop")
```

Wire a `hooks/stop.sh` that runs `ls .wiki-pending/ | grep -v archive` and
refuses the Stop matcher if the output is non-empty, so turn-closure becomes
mechanically enforced rather than self-disciplined. Requires schema changes in
`hooks/hooks.json`. The prose in v2.1 is the contract that hook must satisfy.
This is the "real gate" the v2.1 plan reviewer called out as the ultimate fix
for the missed-capture failure mode.

---

## SessionStart hook injects SKILL.md content (using-superpowers pattern)

```yaml
status: deferred
priority: p2
effort: low
labels: [post-mvp, architecture]
revisit_when:
  "Any of: (a) 3+ fresh sessions in a row where a durable trigger fires and the
  agent does NOT invoke karpathy-wiki; (b) pattern where keyword-rich questions
  invoke but implicit-trigger moments (research subagent return, confusion
  resolved) fail; (c) user reports missing wiki entries where retrospective
  shows the trigger should have fired."
refs:
  - ~/wiki/concepts/claude-code-skill-autoload-mechanisms.md (full revisit
    criteria + implementation sketch)
  - /Users/lukaszmaj/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.7/hooks/session-start
    (canonical reference implementation)
```

Mirror the `superpowers:using-superpowers` pattern: `hooks/session-start` reads
`skills/karpathy-wiki/SKILL.md` and emits its contents via
`hookSpecificOutput.additionalContext` wrapped in `<EXTREMELY_IMPORTANT>` tags,
so the agent reads the skill rules at session start regardless of whether it
chooses to invoke. **CRITICAL:** must ship in the SAME COMMIT as a
`<SUBAGENT-STOP>` block added to the top of SKILL.md — otherwise dispatched
subagents receive the full ~455-line orchestration body in their context, making
them loud, slow, and prone to spurious capture evaluation. Tag text: _"If you
were dispatched as a subagent to execute a specific task unrelated to wiki
capture or ingest, skip this skill."_ The "unrelated to wiki capture or ingest"
qualifier is load-bearing — an ingester subagent DOES need the full skill.

---

## Real `wiki doctor` implementation (not a stub)

```yaml
status: deferred
priority: p1
effort: high
labels: [post-mvp, quality]
revisit_when:
  "After 5-10 real-session ingests accumulate with ingester-stubbed quality
  ratings, so there's meaningful signal for the smart-model re-rate to work on.
  Also triggered if `wiki status` starts reporting a persistent cluster of pages
  below 3.5 quality."
refs:
  - bin/wiki (currently exits 1 with "not implemented")
  - skills/karpathy-wiki/SKILL.md "Quality ratings" section (defines the
    contract doctor must satisfy)
  - docs/planning/2026-04-22-karpathy-wiki-v2.md (scope-cut to stub in v1)
```

`wiki doctor` is stubbed in v2 (`bin/wiki doctor` exits 1 with "not
implemented"). Real implementation re-rates every page's `quality:` block with
the smartest available model, fixes broken cross-references, consolidates
tag-drift synonyms, and auto-archives raw sources that are referenced by 5+ wiki
pages. Must NEVER clobber `rated_by: human` blocks. Should emit a summary of
changes made for user review.

---

## `--max-turns` / `--max-budget-usd` on spawned ingester

```yaml
status: rejected
priority: p3
effort: low
labels: [defers-to-user-policy]
revisit_when:
  "N/A — user explicitly rejected in v2.1 planning. Budget and turn caps are
  user-account concerns, not skill concerns. Revisit ONLY if the skill gets used
  in constrained contexts (e.g., GitHub Actions CI) where a runaway ingester
  would block the pipeline."
refs:
  - docs/planning/2026-04-24-karpathy-wiki-v2.1-missed-capture-patch.md#deliberate-scope-cuts
```

Kept in this file with `status: rejected` specifically so future-us doesn't
re-propose the same thing without seeing the prior reasoning. The underlying
concern (runaway ingester) is handled by the stalled-capture recovery mechanism
shipped in v2.1.

---

## `--bare` + explicit `--allowedTools` on the spawned ingester

```yaml
status: blocked
priority: p2
effort: medium
labels: [defers-to-anthropic]
revisit_when:
  "Anthropic ships the announced `--bare`-as-default-for-`-p` change (documented
  but undated as of 2026-04-24). When that lands, the `--bare` flag becomes
  default and the karpathy-wiki ingester should explicitly opt IN to loading the
  karpathy-wiki skill via `--append-system-prompt` to avoid breaking."
refs:
  - ~/wiki/concepts/claude-code-headless-subagents.md (flag documentation)
  - docs/planning/2026-04-24-karpathy-wiki-v2.1-missed-capture-patch.md#deliberate-scope-cuts
```

Token savings and CI reproducibility. The ingester currently relies on skill
discovery to know how to act (its prompt says "Follow the karpathy-wiki skill's
INGEST operation exactly"). `--bare` skips skill discovery, so this change
requires either passing the skill path via `--append-system-prompt` or
documenting the tradeoff explicitly.

---

## `--json-schema` structured ingester output

```yaml
status: deferred
priority: p3
effort: high
labels: [post-mvp, reliability]
revisit_when:
  "Ingester starts producing malformed output in the wild — e.g. missing quality
  blocks, wrong date format, or the existing Tier-1 lint (read back every page
  link) starts failing regularly. Currently no pain point."
refs:
  - ~/wiki/concepts/claude-code-headless-subagents.md (--json-schema
    documentation)
  - scripts/wiki-validate-page.py (the current pain-point surface if malformed
    output lands)
```

Cleaner success signal than parsing `.ingest.log`. Let the ingester emit a
structured summary object (pages created, pages updated, manifest entries
written, validator result) that the parent can parse to decide whether to retry
or surface an error.

---

## Real test coverage for SKILL.md prose rules

```yaml
status: deferred
priority: p2
effort: high
labels: [test-infra, post-mvp]
revisit_when:
  "Any SKILL.md regression where a prose rule stops being followed. Currently
  the rules are validated manually via real-session observation; no automated
  check."
refs:
  - tests/green/GREEN-results.md (current manual RED-GREEN-REFACTOR evidence)
  - docs/planning/2026-04-24-karpathy-wiki-v2.1-missed-capture-patch.md#deliberate-scope-cuts
```

Agent-facing rules (turn closure, body floor, orientation protocol,
missed-cross-link check) are not unit-testable without a harness that spawns
`claude -p` against a fixture transcript and inspects the resulting capture file
/ wiki pages. Build one post-MVP when the rules start regressing enough to hurt.

---

## Obsidian: pre-enable core plugins in wiki init script

```yaml
status: open
priority: p2
effort: low
labels: [ux, init-script]
revisit_when: N/A
refs:
  - ~/wiki/concepts/wiki-obsidian-integration.md (full spec — when that capture
    lands)
  - scripts/wiki-init.sh (target of the change)
```

The init script writes a minimal `.obsidian/app.json` with just filters. Extend
it to also write `.obsidian/core-plugins.json` enabling Backlinks, Outgoing
Links, Graph View, Tags Pane, Page Preview, Properties View — all built-in
Obsidian core plugins that make the wiki's cross-referenced structure actually
usable. Without this, every new user has to open Settings → Core plugins and
toggle each manually. Takes ~5 minutes to add to the init script; saves every
future user ~5 minutes and a lot of "wait why doesn't Obsidian show backlinks."

---

## Consider migration: TODO.md → GitHub Issues when repo goes public

```yaml
status: open
priority: p3
effort: low
labels: [process]
revisit_when:
  "Repo gets pushed to `toolboxmd/karpathy-wiki` and made public. GitHub Issues
  is the natural home once there are external contributors / visibility."
refs:
  - TODO.md (this file; one-shot migration via `gh issue create` per entry)
```

Once the v2-rewrite branch merges to `main` and the repo goes public, migrate
each open / deferred item in this file to a GitHub Issue with matching labels.
Preserve the YAML frontmatter fields as issue labels/milestones where possible.
`status: rejected` items stay in this file as historical record (don't migrate —
issues don't want to be "closed as rejected" with full rationale; that belongs
in the repo's history). Close this `TODO.md` file once migration is complete (or
leave it as a pointer to the Issues tracker).

---

# Shipped

Items closed here rather than deleted, so the commit history of this file
captures "what was once on the list." When a TODO item ships:

1. Move its `##` section here.
2. Change `status: shipped`.
3. Add `shipped_in:` field pointing at the closing commit SHA.
4. Keep the original body paragraph for posterity.

## Re-run the Opus auditor after real-session usage accumulates

```yaml
status: shipped
priority: p1
effort: low
labels: [quality, validation]
shipped_in: 5a1d209
refs:
  - docs/planning/2026-04-24-karpathy-wiki-v2-hardening.md#deferred-to-later
    (enumerated targets)
  - tests/green/GREEN-results.md (convergence baseline)
```

Likely future audit targets (not commitments):

- Whether `quality.overall < 3.5` pages cluster in any particular category or
  tag — signal the ingester is chronically over-cautious in a domain.
- Whether tag-drift repeats despite `wiki-lint-tags.py` — heuristics may need
  tuning.
- Whether `sources/` pointer pages degenerate into dead formality (only 1-2
  lines each) and should merge into `raw/` metadata.
- Whether the `quality:` block should carry a per-dimension rationale field
  (currently only overall `notes`).
- Whether `wiki doctor` should actually be implemented now that there is a
  rating surface to rate against.

Audit shipped 2026-04-24 (`docs/planning/2026-04-24-karpathy-wiki-v2.2-audit.md`); v2.2-hardening plan executed Tasks 50-62 closing 6 of the 16 findings (architectural cut + 5 mechanical fixes). The remaining 10 findings remain on TODO.md or defer to v2.3 / `wiki doctor`.

## `ideas/` category in the wiki schema

```yaml
status: shipped
priority: p3
effort: medium
labels: [wiki-schema]
shipped_in: 2b91706
refs:
  - ~/wiki/concepts/wiki-ideas-category-convention.md (the convention page)
  - ~/wiki/schema.md (now contains "## Ideas Category Extension" section per v2.3)
  - scripts/wiki-validate-page.py (validates type: ideas via discovery; no special-case needed)
```

The `ideas/` category was already a wiki-level convention pre-v2.3 (with required `status:` and `priority:` frontmatter fields). v2.3 cemented it into the auto-discovery contract: `ideas/` is one of the four seed categories `wiki-init.sh` creates, validator accepts `type: ideas` because discovery returns it from the directory tree, `wiki-status.sh` counts it, `wiki-backfill-quality.py` walks it. The decision "keep or drop" is settled — the wiki has 5 idea pages today (action-tokenization-v0-build, obsidian-rich-init, sessionstart-hook-inject-skill, validate-idea-pages, wiki-doctor-real-implementation), all earning their keep as durable forward-looking items distinct from this plugin's TODO backlog. Different scopes: TODO.md = plugin-development backlog (in-repo). `ideas/` = wiki-knowledge forward-looking items (in the wiki itself, surfaced to agents via index/discovery).

## v2.3: flexible auto-discovered categories + recursive _index.md tree

```yaml
status: shipped
priority: p1
effort: high
labels: [v2.3, architecture, schema]
shipped_in: 2b91706
refs:
  - docs/planning/2026-04-25-karpathy-wiki-v2.3-flexible-categories-design.md
  - docs/planning/2026-04-25-karpathy-wiki-v2.3-spec.md
  - docs/planning/2026-04-25-karpathy-wiki-v2.3-plan.md
  - docs/planning/transcripts/2026-04-26-auto-discovered-categories.md
  - docs/planning/transcripts/2026-04-26-category-discipline-ceiling.md
  - docs/planning/transcripts/2026-04-26-reply-first-ordering.md
```

v2.3 deletes the validator's hardcoded `VALID_TYPES` whitelist and makes the directory tree the single source of truth for categories. A user/agent can `mkdir <wiki-root>/<name>/` to create a category — discovery picks it up on the next ingest, schema.md regenerates, sub-indexes auto-build. `type:` frontmatter equals `path.parts[0]` (plural form); validator enforces this as a hard violation.

Other shipped pieces:
- Recursive per-directory `_index.md` files replace the legacy 25 KB monolithic `index.md`. Root MOC ~10 lines.
- Wiki-root-relative cross-link convention (`/concepts/foo.md`) for nested pages.
- Three category-discipline rules (≥3 pages per category, depth ≤4 hard cap, ≥8 categories soft ceiling).
- Reply-first turn ordering rule documented in SKILL.md (was implicit in line 444 of the resist-table; now prescriptive).
- Live wiki migrated: 60 pages got `type:` rewritten plural; 4 named pages moved from `concepts/` to `projects/toolboxmd/<project>/`; outbound + inbound cross-links rewritten to leading-`/` form; 8 new `_index.md` files generated.
- Pre-existing bugs cleaned up alongside: `wiki-init.sh` no longer seeds deleted `sources/` and now seeds `ideas/`; `wiki-status.sh` and `wiki-backfill-quality.py` rewired from hardcoded category lists to discovery-driven walks.
- Bundle directory is a symlink to `/scripts/` (verified, structurally drift-proof). Symlink-guard test in `test-bundle-sync.sh`.

Plan executed via subagent-driven-development (~30 commits across phases A.1, A.2, B, C, D, E). Both reviewer passes (spec-compliance + code-quality) caught real bugs: parser drift in Task 0 (4 silent divergences from the existing validator parser, fixed via oracle test), reserved-dir descendant leak in Task 11's index builder (would have inflated subdirectory counts), and root-dir double-write in single-directory mode. Phase D's atomic moves+relinks contract held — validator passed clean between every commit. Two tarballs preserved at `~/wiki-backup-pre-v2.3-phase-{a,d}-*.tar.gz` as outermost rollbacks.

## v2.4 deferrals (out of scope from v2.3)

```yaml
status: open
priority: p2
effort: medium
labels: [v2.4, follow-up]
refs:
  - docs/planning/2026-04-25-karpathy-wiki-v2.3-spec.md (out-of-scope section)
```

Items deferred from v2.3:

- **Automated retroactive global link migration** — v2.3 only rewrote inbound links to the 4 moved pages; ~50+ other relative links throughout the wiki stayed in their existing form. A bulk migration script that converts every `../foo.md` to `/category/foo.md` would polish the wiki but is non-urgent.
- **Skill-bundling sync mechanism** — currently `/skills/karpathy-wiki/scripts/` is a symlink to `../../scripts/`, which works for development but breaks if the plugin is installed via `claude plugin install` (which resolves the symlink to a real copy). A proper sync mechanism (build step, symlink-aware install, single canonical location) would be cleaner. v2.3 ships hand-copy + symlink + CI guard; v2.4 picks the right machinery.
- **`wiki create-category <name>` CLI** — v2.3 contract is `mkdir`. If friction surfaces from heavy use, a small CLI wrapper that does `mkdir + name validation + initial _index.md skeleton` is straightforward.
- **Cosmetic reorg of historical migration scripts to `scripts/historical/`** — `wiki-migrate-v2-hardening.sh`, `wiki-migrate-v2.2.sh`, `wiki-migrate-v2.3.sh` accumulate. Moving them to `scripts/historical/` (or similar) keeps the active scripts dir clean.
- **`wiki doctor` real implementation** — still a stub. Now with the recursive `_index.md` tree, the smartest-model re-rate path is unblocked; orphan repair and tag-synonym consolidation also become cleaner.
- **Per-`_index.md` schema-proposal firing** — the SKILL.md ingester step 7.6 has prose for this but it's not exercised by an actual ingester run yet (would happen during an organic ingest after v2.3 ships).
- **Singular `type:` orphan recovery** — if anyone hand-writes a page with singular `type:` post-v2.3, the validator hard-rejects. A friendlier `wiki fix-type` CLI that runs `wiki-fix-frontmatter.py` on the offending page would smooth this.

Each of these is a candidate for a future ship; none block v2.3.

## Raw-direct ingest path (architectural — surfaced 2026-04-27 post-v2.3 ship)

```yaml
status: open
priority: p1
effort: medium
labels: [v2.4, architecture, ingest]
refs:
  - skills/karpathy-wiki/SKILL.md (line 121: "user adds a file to raw/" trigger)
  - skills/karpathy-wiki/SKILL.md (line 502: Iron Rule 5 "Never modify files in raw/")
```

**Bug surfaced post-v2.3-ship.** The capture-driven ingest architecture conflates two distinct semantic flows:

1. **Capture-driven ingest** (conversation IS the source): A conversation surfaced durable knowledge → agent writes a capture → ingester reads capture body → generates wiki page. The capture is the canonical encoding of what the conversation produced; the file (if any) is supporting evidence.

2. **Raw-direct ingest** (file IS the source): A file appears on disk (Obsidian Clippings, manual download, research-tool export). The file IS the durable content. There is no conversation context to encode.

Today's design only supports flow 1. SKILL.md line 121 lists "user adds a file to raw/" as a capture trigger — but that's misleading: the actual mechanism requires the agent to write a capture WRAPPING the raw file (`evidence: <abs-path>`, `evidence_type: file`), which is a fabrication step for material with no conversation behind it. The capture body becomes meta-text like "this is a Clippings file, please process it," failing the body-floor sufficiency rule and producing low-information wiki pages.

**The cleaner architecture (v2.4 work):**

Add a `wiki-ingest-raw.py` mode (or `--from-file` flag on the existing ingester) that:
- Copies file to `raw/<basename>` with manifest entry (`origin: <original-path>`).
- Reads the file directly (no capture middleman).
- Generates a wiki page from file content; `sources:` points at `raw/<basename>`.
- Logs `raw-ingest |` (new verb distinct from `ingest |` for capture-driven runs).

Open design questions to settle in the v2.4 brainstorm:

- **Trigger mechanism:** SessionStart hook scanning `Clippings/`? CLI command (`wiki ingest-raw <file>`)? Filesystem watcher?
- **Agent involvement:** pure auto-ingest, or the raw-direct path produces a draft for next-session agent review (categorization, cross-link enrichment, quality rating)?
- **What about Clippings/?** Currently reserved (validator skips, discovery skips). Either keep reserved + require explicit move to a "queue" dir, OR auto-process Clippings/ via the raw-direct path on session start.

**Why this matters for the wiki use case:** Obsidian Web Clipper users will drop external content (articles, X posts, technical docs) into Clippings/ regularly. Without raw-direct, every clipping requires the user to invoke an agent + write a thin capture + spawn ingester. With raw-direct, drop-and-go works.

**Why this didn't ship in v2.3:** the bug surfaced AFTER v2.3 shipped, in conversation about Obsidian Clipper behavior. The architectural fix is non-trivial (new ingest path, new tests, new log verb, design choices about agent involvement). Shipping it would have been scope creep.

**What v2.3 ships in the meantime:** the misleading "user adds a file to raw/" trigger remains in SKILL.md. Pragmatically the agent can still read a Clippings file and write a thin capture, but it's a workaround, not the right architecture. v2.4 fixes properly.
