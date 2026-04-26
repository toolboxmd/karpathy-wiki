# karpathy-wiki v2.3 Spec : Flexible Categories + Auto-Discovered Schema

**Status:** spec; brainstorm complete 2026-04-26; revised twice after two Opus reviewer passes on 2026-04-26; awaits user review before plan.
**Branch:** `v2-rewrite` (continues v2 + v2-hardening + v2.1 + v2.2 lineage)
**Source:** `docs/planning/2026-04-25-karpathy-wiki-v2.3-flexible-categories-design.md` (design notes) + brainstorm session 2026-04-26 + two Opus reviewer passes 2026-04-26.
**Execution mode:** subagent-driven-development.

---

## 1. Goal

Replace the wiki's hard-coded category whitelist with auto-discovered categories rooted in the directory tree. Users (and agents) create categories by `mkdir`; the wiki regenerates its self-description on the next ingest. Pages can nest arbitrarily deep within a category. Each directory carries an `_index.md` that mirrors directory structure, so navigation matches mental model.

The cut: today the validator's `VALID_TYPES = {"concept", "entity", "query"}` Python set fights with `schema.md`'s prose categories list. v2.3 deletes the Python set and makes schema.md's categories block auto-generated from the tree by `wiki-discover.py`. The tree is the single source of truth.

## 2. Why this ship

Two architectural decisions made in v2-hardening lock the structure:

1. **Closed type whitelist.** `wiki-validate-page.py` line 39 hard-codes `VALID_TYPES`. Adding a category requires a code change + skill reinstall.
2. **No directory-tree-as-source-of-truth.** Categories are documented as prose in `schema.md`. The validator checks the type field but not the directory; type and path are two parallel sources of truth that diverge silently.

Symptoms in the live wiki today (verified 2026-04-26):
- 49 pages in `concepts/`, 4 in `entities/`, 5 in `ideas/`, 0 in `queries/` = 58 pages total. The mega-bucket grows because the cheap model defaults to `type: concept` whenever ambiguous.
- Project-specific knowledge (e.g., `karpathy-wiki-v2.2-architectural-cut.md`) sits in `concepts/` next to general principles.
- Adding a `projects/toolboxmd/<project>/` subtree requires both a code edit and a prose update.
- Live `index.md` is 24,542 bytes (24 KB), already 3× past the 8 KB orientation-degradation threshold; this v2.3 ship consumes the v2.2 `index-split.md` schema-proposal that flagged it.
- **Type-value drift discovered during reviewer pass:** all 5 pages in `ideas/` carry `type: concept` (not `type: idea`). One page (`concepts/wiki-ideas-category-convention.md`) has frontmatter `type: concept` AND a body code-example also matching `^type:` (showing `type: idea` as a teaching example). `wiki-init.sh` line 52 still mkdir-s `sources/` (deleted in v2.2) and omits `ideas/`. `wiki-status.sh` line 67 hardcodes `concepts/entities/sources/queries/` (excludes `ideas/`, includes deleted `sources/`). `wiki-backfill-quality.py` line 84 has the same hardcoded list. `wiki-normalize-frontmatter.py` has its own VALID_TYPES map deriving singular types and referencing `sources/` — but it is invoked by the historical `wiki-migrate-v2-hardening.sh:71`, so it cannot be deleted. These are pre-existing drifts that v2.3 cleans up alongside the architecture work (with the normalize script preserved as obsolete history rather than deleted).

The user's framing: "I wanted the wiki to be fully flexible for the agents to be able to add remove directories." v2.3 fixes this.

## 3. Scope

### In-scope
- Top-level directory IS the category. Any `mkdir <name>/` at wiki root creates a valid category, no code change required.
- `type:` frontmatter stays, derived as `path.parts[0]`. Validator enforces `type == path.parts[0]` directly (plural form). See **§4.1 Type-naming convention** for how the live wiki's existing singular values (`concept`, `entity`, `idea`) get migrated.
- Arbitrary nesting allowed within each category.
- Wiki-root-relative cross-links via leading `/` (`[X](/concepts/foo.md)`).
- Per-directory `_index.md` files; recursive structure mirroring the content tree.
- Root `index.md` becomes a small MOC pointing at top-level `_index.md` files (one line per top-level category, plus header).
- `schema.md` partially auto-generated (categories block + reserved-names block, between markers).
- `wiki-status.sh` reads category counts from auto-discovery, not hard-coded list.
- Three category-discipline rules added to SKILL.md (≥3 pages per category — agent-side prompt only, no user-facing alarm; depth ≤4 hard cap — validator-rejected; ≥8 categories soft ceiling — fires schema-proposal). See §5.1 for mechanism per rule.
- **Reply-first turn ordering** added to SKILL.md as a new procedural rule (Phase C). Today the skill's prose is read by agents as capture-before-reply; v2.3 makes the order explicit: reply first, then capture (if a trigger fired), then turn-closure check.
- **Live wiki frontmatter migration:** every existing page in `concepts/`, `entities/`, `ideas/` gets `type:` recomputed from `path.parts[0]` (plural form). 58 pages affected. Mechanical, idempotent, batched in Phase A.2 as multiple commits with verification gates (must happen in Phase A so the new validator's plural-membership check passes; see §4.1 "Migration timing").
- **Live wiki content migration:** 4 named pages (enumerated in Q4 below) move from `concepts/` to `projects/toolboxmd/<project>/`.
- **`Clippings/` reserved.** The live wiki's existing `Clippings/` directory (Obsidian Web Clipper output) is added to the reserved-names set so it never becomes a category.
- **`wiki-init.sh` seed-list updated.** Phase A fixes the stale seed list (currently creates `sources/`, deleted in v2.2; missing `ideas/`). New seed: `concepts entities queries ideas raw .wiki-pending .locks .obsidian`.
- **`wiki-status.sh` and `wiki-backfill-quality.py` rewired to read from discovery.** Both currently hardcode `concepts/entities/sources/queries/` (omitting `ideas/`, including deleted `sources/`). Phase A changes both to walk the categories `wiki-discover.py` returns. Folds the architectural-coherence fix into the same ship that delivers `wiki-discover.py`.
- **`wiki-normalize-frontmatter.py` marked obsolete (NOT deleted).** Header comment says "deprecated; superseded by `wiki-fix-frontmatter.py`; retained because `wiki-migrate-v2-hardening.sh` still references it for replay of the v2-hardening migration." Test `test-normalize-frontmatter.sh` stays in the reused-unchanged list. The new `wiki-fix-frontmatter.py` is what current and future flows use.
- `python3 --version >= 3.11` check added to `wiki-init.sh`.

### Out-of-scope (deferred)
- **Cross-wiki schema discovery.** Each wiki discovers its own categories.
- **Symlink categories.** Symlinks under wiki root are not supported as categories.
- **Per-category schema enforcement** beyond the existing `ideas/` extension.
- **Global retroactive migration of all relative links to leading-`/` form.** Existing relative links keep working. Phase D rewrites only inbound links pointing at the moved pages, to the new leading-`/` form. Other relative links throughout the wiki are not touched.
- **Tag-driven categories.** Categories stay directory-based; tags stay independent.
- **`wiki doctor` integration with v2.3.** Doctor remains the v1 stub. Note for the future implementation: without `category_path:` in frontmatter, `wiki doctor` queries like "all toolboxmd project pages" must walk paths, not grep frontmatter. Trivial but worth flagging.
- **`wiki create-category` CLI.** `mkdir` is the contract.
- **Removing Python from the dependency stack.** Python 3.11+ stays as the wiki's runtime; rewriting in pure bash is its own future ship and is not v2.3.
- **Cosmetic reorg of historical migration scripts to `scripts/historical/`.** Deferred to v2.4.
- **Automated skill-bundling sync mechanism between `/scripts/` and `/skills/karpathy-wiki/scripts/`.** Building the sync infrastructure (a sync script, a build step, a CI check) is deferred to v2.4. **However: v2.3 still hand-copies every script change to BOTH locations within the same commit** — see §5.1.5 "Bundle-copy contract" below. The deferred work is automation, not delivery. The live wiki gets the v2.3 fixes immediately because every script edit lands in both copies before the commit closes.

## 4. Resolved design questions (from brainstorm)

| # | Question | Decision |
|---|----------|----------|
| Q1 | Sub-index render shape | **Inline `_index.md` per directory.** Each file: `## Pages (in this directory)` with full entries, `## Subdirectories` with one-line-per-child + child page titles only (titles ~30 bytes vs full ~150 bytes; parent stays compact even with busy subtree). |
| Q2 | `category_path:` frontmatter field | **Drop entirely.** File path encodes nested address; extra field would create drift. `type:` stays as the bucket. |
| Q3 | `projects/` vs `concepts/` rule | **"projects/ for ship/decision/timeline knowledge tied to a specific named product. concepts/ for principles, patterns, mechanisms that survive renaming the product."** Rename-test: would this still be true if the product were renamed? |
| Q4 | Migration aggressiveness | **Move exactly 4 pages**, all currently in `~/wiki/concepts/`: (1) `karpathy-wiki-v2.2-architectural-cut.md` → `projects/toolboxmd/karpathy-wiki/`; (2) `karpathy-wiki-v2.3-flexible-categories-design.md` → `projects/toolboxmd/karpathy-wiki/`; (3) `multi-stage-opus-pipeline-lessons.md` → `projects/toolboxmd/building-agentskills/`; (4) `building-agentskills-repo-decision.md` → `projects/toolboxmd/building-agentskills/`. The v2.3 spec lives in `docs/planning/` (this repo), not in the wiki — it does not migrate. Wiki-* mechanism pages (`wiki-quality-rating-system.md`, `wiki-capture-byte-floors.md`, `wiki-ideas-category-convention.md`, `wiki-obsidian-integration.md`) stay in `concepts/` (they survive the rename test from Q3). |
| Q5 | Pre-populate other-brand `projects/` | **No.** Only `projects/toolboxmd/`; other brands accrete when content lands. |
| Q6 | Per-sub-index size threshold | **8 KB per `_index.md` file.** Each independently fires schema-proposal. Recursive tree handles depth; threshold prevents any single file from blowing out. The root MOC is exempt from this 8 KB threshold (capped via Rule 3's ≥8-categories soft ceiling instead). |
| Q7 | `wiki create-category` CLI | **No.** `mkdir` is the contract; auto-discovery picks it up. |
| Q8 | Reserved-names list location | **Python constant in `wiki-discover.py` + auto-generated mirror in schema.md** (between `<!-- RESERVED:START/END -->`). One source of truth (the script's set), two readers (script itself, schema.md regeneration for humans). Initial set: `{"raw", "index", "archive", "Clippings"}` plus any `.*` directory. Extensible via `.wiki-config` `[discovery] reserved = [...]`. |

### 4.1 Type-naming convention (Opus reviewer C2 resolution + 3rd-pass refinement)

**Issue.** Today's live wiki has 49 pages in `concepts/` (all `type: concept`), 4 in `entities/` (all `type: entity`), 5 in `ideas/` (ALL with `type: concept`, none with `type: idea`), 0 in `queries/`. The naive cross-check `type == path.parts[0]` fails on EVERY existing page (singular-vs-plural plus value-vs-path mismatches in `ideas/`).

**Decision: type values are PLURAL, matching `path.parts[0]` literally.** No singularization map. `wiki-fix-frontmatter.py` recomputes `type:` from path for every page in one mechanical pass.

**Rationale.**
- The singularization map (option B in the brainstorm) is brittle for future categories. `mkdir analyses/` has no clean singular; user creates `mkdir studies/`, what's the singular? Singularization is locale-dependent in English (mouse → mice) — a known anti-pattern.
- The migration is mechanical (58 pages, one-pass batch) and reversible (tarball backup as the outermost rollback; per-commit `git revert` for finer granularity).
- Audit (run during 3rd reviewer pass): `wiki-manifest.py` does not read frontmatter `type:`; `wiki-lint-tags.py` iterates paths not types; `wiki-backfill-quality.py` checks `quality.rated_by` only but DOES walk a hardcoded category list (Phase A fix); `wiki-status.sh` does not grep `type:` for value semantics but DOES walk a hardcoded category list (Phase A fix); `wiki-normalize-frontmatter.py` has its own `VALID_TYPES` map deriving SINGULAR types — this script is marked OBSOLETE in Phase A but NOT deleted (it is invoked by `wiki-migrate-v2-hardening.sh:71` for replay of the historical hardening migration; deletion would break replay reproducibility). The only consumer that reads `type:` for value at runtime is the validator itself (the very thing being changed).

**Migration is two-axis, not one-axis.** Naive "singular→plural" framing understates the migration: 5 pages in `ideas/` carry `type: concept` (path-vs-value mismatch, not just singular-vs-plural). The script is path-derives-the-truth: it computes `path.parts[0]` and writes that value, period. Effects:
- 49 `concepts/foo.md` files: `concept` → `concepts`. (One of these, `wiki-ideas-category-convention.md`, has a body code-example showing `type: idea`; that body line is NOT touched — see frontmatter-only contract below.)
- 4 `entities/foo.md` files: `entity` → `entities`.
- 5 `ideas/foo.md` files: `concept` → `ideas` (semantic correction, not just plural rename).
- Total: 58 pages get rewritten.

**Frontmatter-only contract (hard rule).** `wiki-fix-frontmatter.py` parses the YAML block between the two `---` delimiters at the top of the file. It NEVER modifies the body. The page `concepts/wiki-ideas-category-convention.md` has TWO `^type:` matches — `type: concept` in frontmatter (line 3) and `type: idea` in a body code-example (line 40). Only the frontmatter line is touched. A test fixture in `test-fix-frontmatter.sh` uses this exact page (or a synthetic equivalent including a body containing `---` markers) to lock the contract under adversarial inputs.

**Migration timing.** The page rewrite happens in **Phase A**, not Phase D as originally planned. Reasoning: when Phase A drops `VALID_TYPES` from the validator, the type-membership check `type ∈ valid_types` becomes a HARD fail because every existing page has singular `type:` while discovery returns plural names. Even with the type/path cross-check downgraded to WARNING, the membership check would break the live wiki on day 1 of Phase A. Folding the page rewrite into Phase A solves this: Phase A ships discovery + new validator + the rewrite, all together. Phase D's previous "type-recompute commit" is no-op-by-then; Phase D focuses on page moves, link rewrites, and index rebuild. Validator-flip from WARNING-only-cross-check to hard-fail-cross-check still happens at the end of Phase D.

**Phase A's rewrite is itself a multi-commit operation** per migration discipline:
1. Tarball backup commit.
2. `wiki-fix-frontmatter.py` rewrite commit (all 58 pages get plural `type:`).
3. Verification: validator passes clean (the membership check now passes; the cross-check still warns until Phase D's flip).

If commit 2 fails, `git revert` it and the wiki is back to v2.2 state.

## 5. Architecture

### Component map

| Component | Status | Role |
|-----------|--------|------|
| `wiki-discover.py` | **NEW** | Walks wiki root; emits JSON to stdout with `categories`, `reserved`, `depths`, `counts`. Reserved set is a Python constant: `{"raw", "index", "archive", "Clippings"}` plus any directory whose name starts with `.`. **No cache file in v2.3.** Discovery is cheap (sub-100ms walk on a 60-file wiki); every consumer recomputes on each call. If profiling later shows pain, a cache can be added with proper file-locking — out of scope for v2.3. |
| `wiki-validate-page.py` | **EXTENDED** | Drops `VALID_TYPES`; reads valid types from discovery output. Adds `type == path.parts[0]` cross-check. Adds depth-≥5 hard reject. Resolves leading-`/` links from wiki root. **On discovery failure: exits non-zero with "wiki-discover.py failed" message** (no silent fallback). Phase A behavior: emits the type/path cross-check as a WARNING (stderr) but does not exit non-zero, until Phase D's frontmatter migration runs. After Phase D's pages-rewrite commit, a separate validator-flip commit changes the cross-check to a hard violation. |
| `wiki-build-index.py` | **NEW** | Recursive index builder. Walks each top-level category, writes `_index.md` in every directory. Per-file shape: `## Pages` (full entries) + `## Subdirectories` (one-line-per-child + titles). **Acquires page locks in path-order (alphabetical of full path), holds the entire ancestor chain for the duration of the regen, releases bottom-up.** **Performance estimate (unmeasured):** ~50 ms per `_index.md` write × max 5 ancestors at depth 5 ≈ 250 ms latency per ingest. Plan-writing adds a measurement step early in Phase C; if the actual number is materially higher, the lock-hold strategy is revisited. |
| `wiki-fix-frontmatter.py` | **NEW** | Maintenance: recomputes `type:` from `path.parts[0]` (plural form), updates frontmatter if mismatched. **Frontmatter-only — never modifies the body.** Parses YAML between the two `---` delimiters at the top; ignores any `^type:` matches in body content (e.g., teaching code examples). Idempotent. Preserves `quality.rated_by: human`. **Invocation contract:** invoked as a one-shot tool (Phase A.2 migration calls it on every page; user can call it manually). NOT auto-invoked by the ingester on existing pages — the ingester's step 5 sets `type:` correctly when CREATING a page, but never silently rewrites an existing page's type. |
| `wiki-relink.py` | **NEW** | Phase D migration helper: rewrites inbound links to **moved pages only** to the new leading-`/` form. Does NOT touch any other links throughout the wiki. Idempotent. |
| `wiki-status.sh` | **EXTENDED** | Two changes. (1) Replaces hardcoded `concepts/entities/sources/queries/` directory list (line 67) with calls to `wiki-discover.py` to walk the actual category set — fixes pre-existing bug that excluded `ideas/` and walked deleted `sources/`. (2) Reads category counts/depths from `wiki-discover.py` output. Adds two new lines: "categories exceeding depth 4" (always 0 if validator is doing its job; non-zero indicates manual file placement that bypassed validation), "category count vs soft-ceiling 8". (Rule 1's "<3 pages" check has no `wiki-status.sh` line — it's an agent-side prompt only, see §5.1.) |
| `wiki-backfill-quality.py` | **EXTENDED** | Replaces hardcoded `("concepts", "entities", "sources", "queries")` directory tuple (line 84) with calls to `wiki-discover.py`. Same pre-existing-bug fix as `wiki-status.sh` above. No semantic change to its quality-block maintenance logic. |
| `wiki-init.sh` | **EXTENDED** | Adds `python3 --version >= 3.11` check upfront with clear error message. **Updates the seed-directory list:** drops `sources/` (deleted in v2.2 but never removed from init), adds `ideas/` (created post-v2 but missing from init). New seed: `concepts entities queries ideas raw .wiki-pending .locks .obsidian`. |
| `wiki-migrate-v2.3.sh` | **NEW** | Live wiki migration orchestrator (Phase D's page-move + relink + index-rebuild). Named functions, `--dry-run`, idempotent. Same shape as `wiki-migrate-v2.2.sh`. Phase A's frontmatter rewrite uses `wiki-fix-frontmatter.py` directly (not orchestrated by this script). |
| `wiki-normalize-frontmatter.py` | **MARKED OBSOLETE** | NOT deleted. Header comment added in Phase A: "deprecated; superseded by `wiki-fix-frontmatter.py`. Retained because `wiki-migrate-v2-hardening.sh:71` invokes it to replay the historical v2-hardening migration on a fresh fixture; deletion would break that script's reproducibility." `tests/unit/test-normalize-frontmatter.sh` stays in the reused-unchanged list. New v2.3+ flows use `wiki-fix-frontmatter.py` exclusively. |
| `SKILL.md` | **EXTENDED** | New sections: category-discipline rules (3 rules); cross-link convention (leading-`/`); auto-discovery contract; **reply-first turn ordering rule**. New rationalization rows in resist-table. |
| `schema.md` | **EXTENDED** | Adds `<!-- CATEGORIES:START/END -->` (placed after the existing `## Categories` section header) and `<!-- RESERVED:START/END -->` (placed after a new `## Reserved Names` section header) markers. `wiki-discover.py` regenerates the blocks. Hand-written prose lives outside markers. Documented warning: "do not hand-edit between markers." |
| `index.md` | **REPLACED** | Small MOC: `# Wiki Index` header + blank line + one bullet per top-level category linking to `<category>/_index.md` with page count. Today's 24,542-byte index becomes ~10 lines / ~500 bytes. |

### 5.1 Three category-discipline rules

These land in SKILL.md prose. **Each rule has a firing mechanism aimed at the AGENT during ingest, not at the user via status alarms.** The user wants the wiki to work, not to be warned about category sizes; the rules exist to keep the cheap model from over-fragmenting categories during page placement.

1. **Don't create a new category to file ONE page.** Before mkdir-ing, the agent must answer: are there ≥3 pages I can place here, or one page that will grow to ≥3 within the foreseeable future? **Mechanism: agent-side at ingester step 5.** The cheap model's "decide target page" prompt explicitly states: "if placing this page would create a new category that won't reach 3 pages within reasonable horizon, place this page in an existing category instead." No `wiki-status.sh` line. No schema-proposal capture. The check fires at the decision point, before mkdir happens — that's the only point where the rule can prevent the failure mode. After-the-fact warnings would be decoration.
2. **Sub-directory depth has a HARD cap of 4.** Validator REJECTS any page placed at depth ≥5 (`category/a/b/c/d/page.md`). The cheap model is told at step 5: "if placing this page would exceed depth 4, place it shallower." **Mechanism: validator exit non-zero.** `wiki-status.sh` surfaces "categories exceeding depth 4" (always 0 if validator is doing its job; non-zero only if a file was placed manually bypassing validation). **Note:** depth 4 = `wiki-root/category/a/b/c/page.md`. Counting from inside the category, the cap is 3 nested subdirectories.
3. **≥8 categories soft ceiling triggers schema-proposal.** When current category count is already 8 and the cheap model wants to mkdir a 9th, it files a schema-proposal capture in `.wiki-pending/schema-proposals/<timestamp>-9th-category-<name>.md` instead of mkdir-ing. The current capture is filed in the existing-best-fit category for now. User reviews the schema-proposal and can `mkdir` themselves to override. **Mechanism: schema-proposal capture** (not a hard reject — flexibility preserved, but the agent's instinct gets a speed bump). `wiki-status.sh` surfaces "category count vs soft-ceiling 8."

### 5.2 Reply-first turn ordering (Opus reviewer additional finding)

**Issue.** Today's SKILL.md prose at lines 191-203 reads (to a fresh agent following procedural instructions top-to-bottom): write capture → spawn ingester → run turn-closure `ls .wiki-pending/` check → emit final assistant message. The user waits on capture machinery before getting their answer. The line at 444 ("Reply-first-capture-later is fine") is in the resist-table where most agents skim past.

**Fix in v2.3.** New explicit ordering paragraph in SKILL.md, landing in Phase C alongside the other SKILL.md updates. Concrete prose:

> **Order matters.** Reply to the user FIRST. The user is waiting; capture mechanics are not. After the reply emits, write any captures whose triggers fired, spawn ingesters, then run the turn-closure check before stopping. The user sees the answer immediately; wiki recording happens in the milliseconds after.
>
> The procedural sequence within a turn — each step is unconditional unless explicitly conditioned on trigger state:
>
> 1. **Do the work.** (Research, file reads, tool calls, subagent dispatch, etc.) Triggers may fire at any point during this step — a research subagent returning a file, a confusion resolving, a gotcha surfacing.
> 2. **Emit user-facing reply.** This is the user's answer. Triggers may also fire while composing the reply itself — writing the answer can surface a durable claim that wasn't durable until you wrote it down.
> 3. **For each trigger that fired in steps 1-2:** write a capture file to `.wiki-pending/`, then spawn a detached ingester. If no triggers fired, skip directly to step 4.
> 4. **Run `ls .wiki-pending/` turn-closure check.** Handle any pending residue (rejection-handling, stalled-recovery, missed-capture from earlier turns).
> 5. **Emit stop sentinel.** Turn ends.

The trigger-detection is independent of step ordering: the agent checks "did a trigger fire" at the transition from step 2 → step 3, not before step 1 began. Triggers that fire pre-reply (research) and post-reply (durable-claim-from-writing-the-answer) both produce captures in step 3, in the order they fired.

Existing line 444 ("Reply-first-capture-later is fine") stays as the resist-table entry; the new paragraph promotes the rule from descriptive to prescriptive.

**Pressure scenario.** Fresh agent + today's SKILL.md → produces capture-before-reply. Same agent + revised SKILL.md → produces reply-then-capture (or skip-capture-when-no-trigger). Saved as third transcript fixture in `docs/planning/transcripts/`.

### 5.3 Ingester flow changes (the v2.3 deltas)

Numbered against the existing SKILL.md ingester steps:

- **Step 2 (orientation)** — schema.md's categories block is now auto-generated. Same orientation cost; source-of-truth shifts.
- **Step 5 (decide target page)** — cheap model gets `wiki-discover.py` output as additional context (current categories + counts + depths). The depth display is per-category: "concepts: depth 1 (45 pages); projects: depth 3 (4 pages)." Prompt includes the three category-discipline rules + the depth-≥5 hard reject. `type:` frontmatter is auto-set to `path.parts[0]` (plural) for newly-created pages.
- **Step 7 (update index)** — invokes `wiki-build-index.py` for the affected category instead of writing `index.md` directly. Walks bottom-up: leaf `_index.md` first, then ancestors. Locks in path-order across the ancestor chain to avoid deadlock under concurrent ingests in the same subtree. Rebuilds root MOC if a category was added/removed.
- **Step 7.5 (cross-link check)** — passes the relevant `_index.md` (page's parent directory) to the cheap model instead of root `index.md`. Tighter context.
- **Step 7.6 (size threshold)** — runs per `_index.md` file, not just root. Each can independently fire schema-proposal. 24-hour debounce (existing pattern). Root MOC is exempt (it's bounded by Rule 3 instead).

### 5.4 Validator flow changes

- `type:` validity is `type ∈ wiki-discover.py output's categories`, not hardcoded. **In Phase A, mismatch is WARNING only.** Phase A's frontmatter rewrite (see §4.1) makes every page pass the membership check on the same commit; the warning behavior is a safety net for any page the rewrite missed.
- New check: `type == path.parts[0]` (plural form). **In Phase A: WARNING only** (stderr; does not exit non-zero). After Phase D's last commit (validator-flip): **HARD violation** (exit non-zero) with exact fix command: `python3 scripts/wiki-fix-frontmatter.py --wiki-root <root> <page>`.
- Both checks (membership + cross-check) are downgraded together in Phase A. The validator-flip at the end of Phase D promotes BOTH to hard-fail simultaneously.
- New check: depth ≥5 is a hard violation from Phase A onward (Rule 2 mechanism — no soft-warning period; depth violations are user-error not migration drift).
- Link resolver: leading `/` resolves from wiki root.
- **On `wiki-discover.py` failure: exit non-zero with the discovery error.** No fallback to a frozen set. The whole point of v2.3 is that the tree is the source of truth; if discovery can't read the tree, the wiki has bigger problems than category validation.
- All other v2.2 checks unchanged.

### 5.5 Recursive lock ordering (Opus reviewer C5 resolution)

**Issue.** Concurrent ingests touching different pages in the same subtree both want to rewrite the same ancestor `_index.md` files. Without a stable lock order, two ingests could deadlock (each holding one lock, waiting on another).

**Decision.** `wiki-build-index.py` acquires locks in **path-order (alphabetical of full path)**. For a page at `projects/toolboxmd/karpathy-wiki/v2.3.md`, the lock-acquisition sequence is:
1. `projects/_index.md`
2. `projects/toolboxmd/_index.md`
3. `projects/toolboxmd/karpathy-wiki/_index.md`

Then the regen runs bottom-up (leaf first, parents next), holding all three locks for the duration of the regen sequence. Locks released bottom-up after each individual file's lock-aware update.

**Worst-case latency.** Depth 5 page = 5 ancestor locks held simultaneously. Each `_index.md` write is ~50 ms. Total: ~250 ms latency per ingest at depth 5; ~50 ms at depth 1. Well under the existing ingest cost.

**Concurrent ingest behavior.** Two ingests in the same subtree serialize on the shared ancestors. The ingest that gets there first runs to completion; the second waits 30s on the first lock; if first finishes within 30s, second proceeds. If first deadlocks (shouldn't happen with path-ordering, but defense in depth), second times out, logs "lock timeout; index regen skipped," and the next ingest catches up.

### 5.6 Bundle-copy contract (4th-pass reviewer C4 resolution)

**Issue.** Scripts exist in TWO locations: `/scripts/` (the working dev-repo copy) and `/skills/karpathy-wiki/scripts/` (the bundled-with-plugin copy that gets installed when someone installs the plugin). The live wiki's running ingester loads the bundled copy via `${CLAUDE_PLUGIN_ROOT}/scripts/...` (verified in SKILL.md line 356). If v2.3 only updates the dev-repo copy, the live wiki keeps running OLD code — the rewires to `wiki-status.sh`/`wiki-backfill-quality.py` don't take effect, AND worse: when Phase A.2's frontmatter rewrite changes pages from singular to plural `type:`, the OLD bundled validator (`VALID_TYPES = {"concept", "entity", "query"}`) rejects every rewritten page until Phase A.1's new validator reaches the bundle.

**Decision: hand-copy every script change to BOTH locations within the same commit.** This is a hard contract for v2.3 — every commit that touches `/scripts/foo` ALSO touches `/skills/karpathy-wiki/scripts/foo` with identical content. Verified by a CI check (file sha256 comparison, fold into `tests/run-all.sh`).

**Why this is fine for v2.3.** The script count is small (3-5 files changed). Hand-copying is mechanical (`cp /scripts/X /skills/karpathy-wiki/scripts/X` plus a sha256 verification). The manual operation is idempotent and verifiable. Building proper sync machinery — a build step that auto-syncs, or symlinks (which break on Windows package install), or a CI script — is its own design problem and is correctly deferred to v2.4.

**What v2.4 ultimately delivers (out of scope here):** a sync mechanism that doesn't require hand-copying. Could be (a) a build-time sync script invoked by a Makefile/`uv` task, (b) symlinks with documented Windows caveats, (c) a single canonical location with a manifest pointing the skill at it. v2.4 picks one; v2.3 ships hand-copy + CI-check verifying both copies match.

**Phase A.1 includes a `tests/test-bundle-sync.sh` case** that asserts every file in `/scripts/` has an identical-sha256 twin in `/skills/karpathy-wiki/scripts/`. CI fails if any drift exists. The test is added to `tests/run-all.sh`.

## 6. Data flow examples

### 6.1 User creates a new category manually

1. User: `mkdir ~/wiki/journal/`.
2. User drops `~/wiki/journal/2026-04-26.md` with `type: journal`.
3. **Nothing immediate triggers.** The directory exists; no script fires.
4. **On the next ingest** (any unrelated capture flowing through):
   - `wiki-discover.py` walks the tree, sees `journal/`, adds it to categories JSON.
   - Validator reads discovery output; `type: journal` is now valid; the page passes.
   - `wiki-build-index.py` creates `journal/_index.md`. Updates root MOC to add `- [Journal](journal/_index.md) — 1 page`.
   - `schema.md`'s `<!-- CATEGORIES:START/END -->` block regenerates with the new line.
5. **Without an ingest:** `wiki status` still shows the category (calls discovery directly). The user can force regeneration with `python3 scripts/wiki-build-index.py --wiki-root ~/wiki --rebuild-all`.

### 6.2 User deletes a category

`rm -rf ~/wiki/concepts/` is destructive. v2.3 does not protect against it (git is the only undo). On the next ingest, discovery doesn't see `concepts/`; schema.md drops the line; the validator's `type:` check now fails for any page that had `type: concept`/`concepts` (none survive in this scenario, since we just removed all of them). User reads stderr of failed ingest, restores from git or tarball. **Asymmetry note:** category creation is reversible (rmdir), category deletion is destructive — different risk profiles, same machinery.

### 6.3 `_index.md` shape (per-file)

`projects/toolboxmd/karpathy-wiki/_index.md`:

```markdown
# karpathy-wiki

## Pages (in this directory)
- [v2.2 Architectural Cut](v2.2-architectural-cut.md) — (q: 4.75) full description ...
- [v2.3 Flexible Categories](v2.3-flexible-categories.md) — (q: 4.75) full description ...

## Subdirectories
(none)
```

`projects/toolboxmd/_index.md`:

```markdown
# toolboxmd

## Pages (in this directory)
(none)

## Subdirectories
- [karpathy-wiki/](karpathy-wiki/_index.md) — 2 pages
  - v2.2 Architectural Cut, v2.3 Flexible Categories
- [building-agentskills/](building-agentskills/_index.md) — 2 pages
  - Repo Decision, v0 Build Pipeline Lessons
```

Root `index.md`:

```markdown
# Wiki Index

- [Concepts](concepts/_index.md) — 45 pages
- [Entities](entities/_index.md) — 4 pages
- [Queries](queries/_index.md) — 0 pages
- [Ideas](ideas/_index.md) — 5 pages
- [Projects](projects/_index.md) — 4 pages, 2 levels deep
```

(Pre-migration: 49 in `concepts/`. Post-migration: 49 − 4 moved = 45 in `concepts/`, plus 4 newly under `projects/toolboxmd/<project>/`.)

### 6.4 Frontmatter (representative project page)

```yaml
---
title: "karpathy-wiki v2.2: kill sources/, decoration-vs-mechanism pattern"
type: projects                           # MUST equal path.parts[0]
tags: [karpathy-wiki, skill-authoring, meta-pattern]
sources:
  - raw/2026-04-24T20-06-48Z-karpathy-wiki-v2.2-architectural-cut.md
created: "2026-04-24T20:06:48Z"
updated: "2026-04-26T00:00:00Z"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 5
  overall: 5.00
  rated_at: "2026-04-26T00:00:00Z"
  rated_by: ingester
---
```

### 6.5 Cross-link convention

Page at `projects/toolboxmd/karpathy-wiki/v2.3.md` linking to `concepts/decoration-vs-mechanism.md`:

```markdown
See [decoration vs mechanism](/concepts/decoration-vs-mechanism.md).
```

Leading `/` is wiki-root-relative. Validator resolves from `${WIKI_ROOT}`. Mintlify and GitHub markdown rendering both respect this convention; raw `cat` shows the leading slash but is acceptable trade-off.

## 7. Error handling

| Failure mode | Detection | Behavior |
|--------------|-----------|----------|
| `wiki-discover.py` returns non-zero | Each consumer (validator, ingester step 5, status) checks return code. | **Exit non-zero with explicit error message: "wiki-discover.py failed: <discovery's stderr>. Run `python3 scripts/wiki-discover.py --wiki-root <root>` directly to diagnose."** No silent fallback. The wiki refuses to operate in a degraded state. |
| `type:` frontmatter mismatches path (Phase A behavior) | Validator. | WARNING to stderr (does not exit non-zero). Allows Phase A to ship without breaking the live wiki's existing pages. |
| `type:` frontmatter mismatches path (post-Phase D) | Validator. | Hard violation, exit non-zero. One-line per page, prints exact fix command. Ingester does NOT auto-fix during normal ingest (would mask user mistakes). |
| Page placed at depth ≥5 | Validator. | Hard violation, exit non-zero. Message: "page at depth ≥5 (cap is 4); place shallower or restructure category." |
| Reserved-name collision (`mkdir wiki/raw-data/`) | Discovery skips the directory. | Directory exists but isn't a category. Pages inside it have no valid `type:`; validator rejects with "directory '<name>' is reserved; cannot be a wiki category." |
| Two ingesters race on the same `_index.md` ancestor | Path-ordered lock acquisition (§5.5). | Second ingester waits up to 30s on first lock. If first finishes: second proceeds. If first deadlocks (defense in depth — shouldn't happen with path-ordering): second times out, logs "lock timeout; index regen skipped this run," next ingest catches up. |
| Migration script interrupted mid-run | `git status` shows partial state. | `wiki-migrate-v2.3.sh` is idempotent; re-running picks up where left off. Tarball backup is the rollback. |
| Migration breaks inbound links | Validator's link resolver in step 8 of migration. | Migration does not commit until validator passes clean. User fixes flagged links manually or re-runs `wiki-relink.py` with adjusted patterns. |
| `_index.md` exceeds 8 KB | Step 7.6 size check after write. | File is written (correctness over size). Schema-proposal capture dropped in `.wiki-pending/schema-proposals/<timestamp>-<path>-index-split.md`. 24-hour debounce. Over-size index keeps working. |
| Cheap model creates new category that ends up with <3 pages (Rule 1) | Agent-side at ingester step 5 (decide-target-page prompt). | The cheap model is told before mkdir to consider whether the category will reach 3 pages. The check is preventive (decision-time), not post-hoc (warning-time). No status alarm; no schema-proposal capture. If the model creates the small category anyway, the wiki keeps working — the category is real, it's just small. |
| Cheap model attempts to mkdir 9th category despite ≥8 already (Rule 3) | Ingester step 5 prompt enforcement. | Cheap model files schema-proposal instead of mkdir-ing; current capture is filed in best-fit existing category. User reviews schema-proposal. If the model bypasses the prompt: discovery picks up the new category on next ingest, `wiki-status.sh` flags. No hard reject — flexibility wins, schema-proposal layer slows the instinct. |
| Python missing on fresh install | `wiki-init.sh` upfront check. | Init fails before any directory created. Error message: "karpathy-wiki requires Python 3.11+; install via `brew install python` (macOS) or `apt install python3` (Linux), then re-run init." |
| User hand-edits between schema.md markers | No detection at write-time; gets overwritten on next ingest. | Documented in schema.md prose: "do not hand-edit between markers." Hand-written prose outside markers is sacred. |
| User adds editor-plugin output dir (Obsidian, VSCode) | Discovery picks up new top-level dir as candidate category. | Initial reserved set includes `Clippings/`. User can extend via `.wiki-config` `[discovery] reserved = ["..."]`. Without extension, the dir is treated as a category and the validator rejects pages inside that lack proper frontmatter. |

## 8. Testing

### Layer 1 — unit tests

**Reused unchanged** (existing 21 unit tests live on disk; 15 of 21 stay unchanged + 2 of 3 integration tests = 17 files): `test-capture.sh`, `test-commit.sh`, `test-config-read.sh`, `test-lib.sh`, `test-lint-tags.sh`, `test-locks.sh`, `test-manifest.sh`, `test-manifest-validate.sh`, `test-migrate-v2-hardening.sh`, `test-migrate-v2.2.sh`, `test-normalize-frontmatter.sh` (kept; its script is marked obsolete but remains), `test-spawn-ingester.sh`, `test-archive-strips-processing.sh`, `test-status-last-ingest.sh`, `test-validate-code-block-skip.sh`, plus integration `test-end-to-end-plumbing.sh` and `test-session-start.sh`.

**Extended in place** (6 unit + 1 integration = 7 files; ~17 new cases):
- `test-validate-page.sh` — +5 cases (leading-`/` link resolution, type/path cross-check warning in Phase A, type/path cross-check hard fail post-Phase D, valid-types-from-discovery, discovery-failure exit-non-zero).
- `test-validate-no-source-type.sh` — rename to `test-validate-deleted-categories.sh` (more general intent). Fixture: page with `type: source` in `concepts/foo.md` asserts validator rejects (post-Phase-D-flip) with the type/path mismatch error message — this also defends "v2.2 deleted sources/, never accidentally re-add it." +1 new case: validator rejects `type: nonsense` in `concepts/foo.md` for the same reason (any non-discovered type fails the membership check).
- `test-status.sh` — +4 cases (category count from discovery, depth report, "categories exceeding depth 4", "category count vs soft-ceiling 8"). NO case for "<3 pages" — that rule is agent-side at ingester step 5, not a status-line check.
- `test-backfill-quality.sh` — +3 cases (script reads category list from discovery, not hardcoded; covers `ideas/` (previously excluded); skips reserved categories like `Clippings/`).
- `test-index-threshold-fires.sh` — +2 cases (per-`_index.md` threshold, debounce).
- `test-init.sh` — +2 cases (Python version check fails clean when python3 < 3.11; updated seed-list creates ideas/ and does NOT create sources/).
- `test-concurrent-ingest.sh` — +2 cases (`_index.md` lock contention with two ingesters touching pages in same SUBTREE; ancestor-lock path-ordering verified deadlock-free).

**Brand-new test files** (5 files; ~32 new cases):
- `test-discover.sh` — categories listed, reserved skipped (incl. `Clippings`), dotted skipped, `.wiki-config` extension, depths correct, counts correct, JSON shape valid, permission-error robustness. (No cache test — there is no cache.) ~8 cases.
- `test-build-index.sh` — per-directory `_index.md` generated, agreed shape, root MOC has minimal-line shape, `--rebuild-all` removes orphaned files, lock acquisition path-order, idempotency, arbitrary depth, depth-≥5 page rejected, **Rule 3 schema-proposal flow** (agent attempts to mkdir 9th category, schema-proposal capture lands in `.wiki-pending/schema-proposals/`). ~9 cases.
- `test-fix-frontmatter.sh` — recompute from path (concept→concepts plural rename for 49 pages; concept→ideas semantic correction for 5 ideas/ pages; idempotent on already-correct pages), preserves human-rated quality, no-frontmatter handling, full-wiki batch run, **frontmatter-only contract verified using fixture that includes a body code-example matching `^type:` AND a body containing `---` markers** (only frontmatter line gets rewritten; bodies untouched under both adversarial inputs). ~7 cases.
- `test-relink.sh` — relative link rewrite to leading-`/`, leading-`/` rewrite, only-moved-pages-touched (other links untouched), unresolved reported, idempotent. ~5 cases.
- `test-migrate-v2.3.sh` — dry-run, full run, idempotent re-run, atomic moves+relinks commit gate (verify validator passes after the combined commit, before index-rebuild), validator passes end-to-end, manifest validates. ~5 cases.
- `test-bundle-sync.sh` — sha256 parity between `/scripts/*` and `/skills/karpathy-wiki/scripts/*` for every script that exists in both locations; CI fails on any drift. Per §5.6 bundle-copy contract. ~2 cases.

**Approximate tally:** ~17 cases added to existing files + ~36 cases in new files = ~53 new cases total. Plan-writer recomputes exact counts per task. v2.2 added ~30-35; v2.3 is moderately larger but proportional to scope.

### Layer 2 — integration tests

- End-to-end ingest with auto-discovered category (NEW category mid-flight).
- Ingest race on `_index.md` ancestor (covered by extension to `test-concurrent-ingest.sh`).
- Validator catches type/path mismatch (warning Phase A, hard fail post-Phase D).
- Discovery failure exits non-zero (no silent fallback).
- **Reply-first ordering compliance test:** transcript-mode test that an ingester following the revised SKILL.md does not call `wiki-spawn-ingester.sh` before its final user-facing message in scenarios with no actual capture trigger.

### Layer 3 — migration test

Fixture wiki simulating today's `~/wiki/` state (49 concept pages with singular `type: concept`, 4 entity pages, 5 idea pages with `type: concept` (mismatch), the `Clippings/` directory with one file, the dual-`type:` page `wiki-ideas-category-convention.md`). Run `wiki-migrate-v2.3.sh --dry-run` first; verify planned moves match. Run for-real on fixture. Verify:
- All 4 named pages moved (per Q4 enumeration).
- Every page in the fixture has `type:` rewritten to plural form.
- Inbound links to moved pages rewritten (test cases include cross-references between moved pages).
- `_index.md` files generated for the new tree.
- `Clippings/` ignored by discovery (not a category).
- Validator + manifest both clean.
- `wiki-status.sh` reflects new state.
- Re-running migration is no-op.

### Pressure scenarios for SKILL.md changes (project TDD discipline)

Per project CLAUDE.md: "Every SKILL.md change must be preceded by a pressure scenario showing an agent failing without the change."

**Three transcript fixtures saved to `docs/planning/transcripts/`:**

1. **Auto-discovered categories rule.** Fresh agent session, fixture wiki with `concepts/` only. Capture flows that should produce `projects/foo.md`. Without the SKILL.md update, agent puts it in `concepts/`. With the update, agent creates `projects/`.
2. **Category-discipline rules (8-cat ceiling).** Fresh agent session, fixture wiki with 8 categories. Capture flows that *would* create a 9th. Without the SKILL.md update, agent mkdir-s a 9th. With the update, agent files a schema-proposal capture instead.
3. **Reply-first ordering.** Fresh agent session, fixture trigger that requires capture. Without the SKILL.md update, agent's transcript shows capture written, ingester spawned, then user-facing message. With the update, transcript shows user-facing message first, capture/spawn after, turn-closure check, stop sentinel.

These transcripts are produced during plan-writing (TDD: red before green). Agent-failure scenarios are concrete sessions, not aspirational descriptions.

### What's NOT tested (deliberate)

- Live `~/wiki/` migration verified manually after Phase D, not in CI. CI fixture exercises script logic; live run is the user's call.
- Cross-platform shell tests; macOS + Linux only (already true in v2.2).
- Performance for `wiki-build-index.py`; tree walks are sub-second on a 1000-page wiki.

### Test deletions

**None.** Every existing test exercises a script that still exists in v2.3. Migration scripts (`wiki-migrate-v2-hardening.sh`, `wiki-migrate-v2.2.sh`) and their tests stay as historical reference; they're documentation-by-test for the migration discipline that v2.3's migration script follows. Cosmetic moves to `scripts/historical/` deferred to v2.4.

## 9. Phasing

Five phases, ordered by risk (cheapest first; live migration last). Mirrors v2-hardening / v2.2 cadence.

### Phase A — Discovery + soft validator + script cleanups + live frontmatter rewrite

Phase A is the architectural foundation AND the live frontmatter migration. Per migration discipline (multiple commits with verification gates), the live-wiki mutations land in their own gated commits at the end of the phase.

**Sub-phase A.1 — New scripts and validator changes (this repo only, no live wiki touch). Per §5.6 bundle-copy contract: every script change in this sub-phase lands in BOTH `/scripts/` and `/skills/karpathy-wiki/scripts/` within the same commit. CI verifies sha256 parity:**
- New `wiki-discover.py` (no cache; stdout-only JSON output) with reserved-names list (incl. `Clippings`).
- `wiki-validate-page.py` extended: drop `VALID_TYPES`; type-membership check and type/path cross-check BOTH **as WARNING only**; depth-≥5 hard fail; **exit non-zero on discovery failure** (no silent fallback).
- New `wiki-fix-frontmatter.py` — frontmatter-only, path-derived plural type. Adversarial fixture in tests (page with `^type:` in body code-example, page with `---` markers in body).
- **Mark `wiki-normalize-frontmatter.py` obsolete** (header comment only — script body and test stay). Reason: `wiki-migrate-v2-hardening.sh:71` invokes it; deletion breaks historical migration replay.
- **`wiki-status.sh` rewired** to read categories from `wiki-discover.py` instead of hardcoded `concepts/entities/sources/queries/`. Adds two new lines (depth-violation count, soft-ceiling indicator).
- **`wiki-backfill-quality.py` rewired** with the same fix.
- `wiki-init.sh` extended: `python3 --version >= 3.11` check + updated seed-directory list (`concepts entities queries ideas raw .wiki-pending .locks .obsidian`).
- `schema.md` gets `<!-- CATEGORIES:START/END -->` and `<!-- RESERVED:START/END -->` markers. Placement: markers wrap ONLY the auto-generated bullet list inside `## Categories`; the existing `### ideas/ frontmatter extension` subsection moves out and becomes its own top-level section `## Ideas Category Extension` (this is a one-time manual schema.md edit; subsequent edits stay outside markers).
- Unit tests for all new/changed scripts: ~17 cases.

**Sub-phase A.2 — Live wiki frontmatter rewrite (touches `~/wiki/`, multiple commits):**
1. **Tarball backup commit (in this repo):** `tar czf ~/wiki-backup-pre-v2.3-phase-a-<utc>.tar.gz ~/wiki/`. Outermost rollback.
2. **Wiki-repo commit — frontmatter rewrite:** `python3 scripts/wiki-fix-frontmatter.py --wiki-root ~/wiki` over every page. 58 pages get `type:` rewritten to plural. Body content untouched. **Verification gate:** validator passes clean (membership check passes; cross-check no longer warns since `type` now equals `path.parts[0]`); manifest validate clean. If gate fails, `git revert` the commit and diagnose.
3. **Wiki-repo commit — schema.md one-time manual edit + regeneration:** TWO mutations in this commit. (a) MANUAL: move the existing `### ideas/ frontmatter extension` subsection out of `## Categories` and into its own top-level section `## Ideas Category Extension`. Insert `<!-- CATEGORIES:START/END -->` markers around the (now empty) categories bullet list and a new `## Reserved Names` section header followed by `<!-- RESERVED:START/END -->` markers. (b) AUTOMATED: run `wiki-discover.py` to populate the marker blocks. **Verification gate:** schema.md is a valid markdown structure (header hierarchy preserved); content between markers reflects discovery output exactly; `### ideas/ frontmatter extension` content is preserved verbatim under its new top-level header.

**Risk:** Phase A IS now a migration phase, but the rewrite is the simplest possible change (one frontmatter field per page, batched). The pre-rewrite WARNING-only validator behavior + tarball backup + per-commit rollback give the same risk profile as v2.2's Phase D, which shipped clean. No flexibility lost: between Phase A.1 and A.2, the wiki keeps validating (warnings only); after A.2, every page passes both checks cleanly even though the cross-check is still warning-only until Phase D's final flip.

### Phase B — Wiki-root-relative links

- Validator's link resolver: leading `/` resolves from wiki root.
- SKILL.md prose update: document the `/category/page.md` cross-link convention.
- Unit tests: ~3 cases inside extended `test-validate-page.sh`.

**Risk:** zero migration risk; new code path is additive (existing relative links keep working).

### Phase C — Sub-indexes + recursive `_index.md` + MOC + SKILL.md updates

- New `wiki-build-index.py` with the agreed per-file shape and path-ordered lock acquisition.
- Ingester step 7 invokes `wiki-build-index.py` for affected category.
- Step 7.6 size threshold propagates to per-`_index.md`.
- New `index.md` MOC (small).
- `wiki-status.sh` reads from discovery; adds three new lines.
- SKILL.md updated:
  - New section: index structure (recursive `_index.md`).
  - New section: category-discipline rules (Rules 1-3, all with mechanism).
  - **New section: reply-first turn ordering.**
  - New rationalization rows in resist-table.
- All three pressure scenario fixtures saved to `docs/planning/transcripts/` (auto-discovered categories, category-discipline ceiling, reply-first ordering).
- Consume + archive the v2.2 `index-split.md` schema-proposal capture.
- Unit tests: ~8 build-index cases + ~7 extended status/threshold cases + ~2 reply-first compliance cases.

**Risk:** zero migration risk; index regeneratable from tree state. SKILL.md changes are prose-only; the procedural reordering doesn't break existing behavior (a fresh agent reading the new prose still hits the turn-closure gate before stop).

### Phase D — Live wiki page migration (multi-commit, verification gates)

Phase D handles the page MOVES (frontmatter rewrite already happened in Phase A.2). Multiple commits with verification gates between them.

**Pre-migration setup (in this repo):**
- New `wiki-migrate-v2.3.sh` (named functions, `--dry-run`, idempotent orchestrator).
- New `wiki-relink.py` (only-moved-pages scope).
- Unit tests: ~5 migrate-v2.3 cases + ~5 relink cases.
- Update `test-validate-no-source-type.sh` for the new mismatch semantic.

**Migration commits:**

1. **Tarball backup commit (in this repo, not the wiki):** `tar czf ~/wiki-backup-pre-v2.3-phase-d-<utc>.tar.gz ~/wiki/`. The tarball is the outermost rollback if every per-commit revert fails.

2. **Wiki-repo commit — Page moves + inbound link rewrites (atomic).** This is one commit, not two: `mkdir projects/toolboxmd/{karpathy-wiki,building-agentskills}/`; `git mv` the 4 named pages into their new homes; immediately run `wiki-relink.py` to rewrite all inbound links to those pages to the new leading-`/` form. **Verification gate:** validator passes clean over every page (link-resolution check now succeeds because both moves and relinks are in the commit); `git status` shows only the expected mutations; manifest unchanged. Reasoning for atomic: page moves alone produce broken links; running validator between move and relink would always fail by design. The two operations are halves of the same logical change.

3. **Wiki-repo commit — Index rebuild.** Run `wiki-build-index.py --rebuild-all` to regenerate the entire `_index.md` tree + root MOC. **Verification gate:** `_index.md` files render correctly in Obsidian (smoke test); root MOC reflects new structure; sub-indexes have correct page counts.

4. **This-repo commit — Validator flip.** Change `wiki-validate-page.py` to make BOTH checks (type-membership AND type/path cross-check) HARD violations (were WARNING since Phase A.1). Update tests that asserted warning-only to now assert hard-fail. **Verification gate:** run validator over the live wiki — every page must pass clean. If any page still fails (a manual-edit oddity the Phase A.2 rewrite missed), `git revert` this commit; the wiki keeps working under WARNING-only behavior; fix the page; retry the flip.

**Manifest validate** runs after every gate above (cheap).

**Cross-repo dependency:** the validator-flip in step 4 must land in this repo AFTER the migration commits land in the wiki repo. There's no automated checkpoint — the operator runs the migration script, verifies in `~/wiki/`, then opens this-repo to commit the flip. Plan-writer documents this sequence explicitly so it's not skipped.

**Risk:** moderate (lower than originally planned, since Phase A.2 absorbed the riskier type-rewrite work). Mitigation: tarball backup as outer rollback; per-commit `git revert` as inner rollback; idempotent script; atomic moves+relinks commit avoids the by-design-broken intermediate state. Same risk profile as v2.2's Phase D — which shipped clean using exactly this multi-commit pattern.

### Phase E — TODO + post-flight

- Mark v2.3 items shipped in karpathy-wiki TODO.md.
- Add v2.4 deferrals: automated retroactive global link migration, optional `wiki-create-category` CLI, scripts/historical/ reorg.
- Optional: write a v2.3 ship retrospective for `building-agentskills` case studies.

## 10. Acceptance criteria

- Validator no longer hard-codes any category list. Discovery is the single source of truth; failure mode is exit non-zero, not silent fallback.
- `mkdir ~/wiki/<new-category>/` is picked up on next ingest with no code edits.
- The 4 named pages from Q4 live under `projects/toolboxmd/<project>/`; cross-links to them resolve via leading `/`.
- Every page in `~/wiki/concepts/`, `~/wiki/entities/`, `~/wiki/ideas/`, `~/wiki/projects/...` has `type:` matching `path.parts[0]` (plural form).
- `index.md` is a small MOC; per-directory `_index.md` files hold real entries; v2.2 index-split schema-proposal is consumed and archived.
- All Tier-1 lint passes; manifest validate passes; live `~/wiki/` validates clean.
- Three category-discipline rules documented in SKILL.md, each with mechanism aimed at the agent during ingest (not at the user via status alarms; Rule 2 also enforced by validator).
- Reply-first turn ordering documented in SKILL.md as a procedural rule, not just a resist-table entry. Captures are conditional on trigger-firing; if no trigger fired, the agent skips capture/spawn entirely.
- `Clippings/` directory is ignored by discovery; pages inside it (none in v2.3 scope) would be rejected by validator.
- `wiki-init.sh` no longer creates the deleted `sources/` directory; it does create `ideas/`.
- `wiki-normalize-frontmatter.py` is marked obsolete (header comment) but not deleted; `wiki-migrate-v2-hardening.sh` continues to function for historical replay; no v2.3+ flow invokes the obsolete script.
- `wiki-status.sh` and `wiki-backfill-quality.py` no longer hardcode category lists; both read from `wiki-discover.py`. Quality-rating maintenance covers `ideas/` (which today is silently excluded).
- A future user reading `schema.md` understands the auto-discovery contract from prose alone.

## 11. Risks and mitigations

| Risk | Mitigation |
|------|-----------|
| Auto-discovery picks up an unintended directory (`tmp/`, editor-created folder) | Reserved set: `{raw, index, archive, Clippings}` + dotted directories. Extensible via `.wiki-config`. Documented in schema.md mirror. |
| Existing 58 pages have `type:` mismatching the new path-derived rule (singular vs plural, plus 5 ideas/ pages with `type: concept`) | Phase A's BOTH validator checks (membership + cross-check) downgraded to WARNING. Phase A.2 runs `wiki-fix-frontmatter.py` over every page (concept→concepts, entity→entities, ideas/* concept→ideas) so warnings stop firing. Phase D's last commit promotes both checks to HARD violation; if any page slipped through, the flip is reverted, the page is fixed, the flip is retried. |
| Wiki-root-relative links break on Mintlify / non-root URLs | Validator uses filesystem path (always works). Mintlify and GitHub respect leading-`/`; smoke test in `building-agentskills` Mintlify deployment before B1. |
| Sub-indexes go stale if `wiki-build-index.py` not invoked on category change | Ingester step 7 invokes it automatically; `--rebuild-all` is the manual catch-up. Never hand-write `_index.md` from v2.3 forward. |
| Phase D page moves break inbound links | Page moves and `wiki-relink.py` invocation are in ONE atomic commit; validator gate runs after both. The intermediate broken-link state never lands in git. Tarball backup as outer rollback. |
| Quality-rating or status logic breaks when type values change | Audit complete (3rd reviewer pass): `wiki-manifest.py`, `wiki-lint-tags.py` do not read `type:` for value. `wiki-status.sh` line 67 and `wiki-backfill-quality.py` line 84 walk hardcoded category lists (excluding `ideas/`, including deleted `sources/`) — pre-existing bugs that v2.3 Phase A.1 fixes by rewiring both to read from `wiki-discover.py`. `wiki-normalize-frontmatter.py` produces singular types — marked obsolete in Phase A.1 (header comment); not deleted because `wiki-migrate-v2-hardening.sh:71` invokes it for historical replay. The validator is the only runtime consumer that reads `type:` for value; that's the one v2.3 changes. |
| User wants a category that conflicts with reserved name | Reserved list documented; validator rejects pages inside reserved-name directories. |
| Cheap model creates too many small categories | Rule 1 (agent-side prompt at decision time, before mkdir) + Rule 3 (schema-proposal on attempted 9th category). Decision-time prevention beats after-the-fact warning. |
| Python missing on fresh install | `wiki-init.sh` upfront check; clear error message with install commands. |
| Schema.md hand-edited between markers | Documented in prose; next ingest overwrites. Same convention as gitpix's marker injection (proven). |
| Discovery script crashes silently or returns malformed JSON | Each consumer exits non-zero with the discovery error. No silent fallback that could hide bugs. The user sees a hard failure and a path to diagnose. |
| Concurrent ingests in same subtree deadlock on ancestor `_index.md` locks | Path-ordered lock acquisition (§5.5). Defense in depth: 30s timeout + log + next-ingest catch-up. |
| Reply-first ordering is added to SKILL.md but agents skim past it | Pressure scenario (Phase C) is the falsifier: a fresh agent producing capture-before-reply on the new SKILL.md is a regression. The scenario lives in CI alongside the other transcript fixtures. |

## 12. Execution mode

**Subagent-driven-development.** Three reasons specific to v2.3:

1. Test surface is non-trivial (~53 new test cases across 13 files). Subagents isolate context per task; single-agent context bloat would degrade code quality.
2. Phase A has three scripts (`wiki-discover.py`, `wiki-fix-frontmatter.py`, validator extensions) that can be developed in parallel — independent test surfaces, independent files.
3. Phase D migration is the highest-risk piece and benefits from a fresh-context reviewer subagent that hasn't seen Phases A-C — exactly the catch-bugs role the planner-reviewer-implementer pattern documents.

Same toolkit as v2.2: planner → implementer → reviewer per phase. Plan file structures tasks for subagent dispatch.

**Branch:** `v2-rewrite` continues. PR opens at end of Phase E.

**Commit count target:** ~20-24 commits across the 5 phases. Higher than v2-hardening's ~17 / v2.2's ~20 because (a) Phase A absorbs the live-wiki frontmatter rewrite that previously lived in Phase D (split into A.1 script work + A.2 multi-commit live mutation), (b) Phase A also includes the `wiki-status.sh` and `wiki-backfill-quality.py` discover-rewiring as separate commits, (c) the obsolete-marker on `wiki-normalize-frontmatter.py` is its own small commit, (d) Phase D is split into tarball + atomic moves+relinks + index-rebuild + validator-flip = 4 commits.

---

End of spec.
