# Karpathy Wiki v2.1 — Missed-Capture Patch Implementation Plan

> **For the implementing subagent:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` to execute this patch. The plan is SINGLE-TASK (not phased). One SKILL.md edit pass, one verification pass, one commit. Steps use checkbox (`- [ ]`) syntax for tracking. This plan **extends** the v2-hardening plan at `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/docs/planning/2026-04-24-karpathy-wiki-v2-hardening.md` — it reuses every discipline convention from it (Files block, verbatim before/after quotes, verbatim new prose, no ellipses, no Co-Authored-By, no `--amend`).

**Working directory:** `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/`
**Branch:** whatever the repo's current HEAD is on (patch commit is a new commit on it; no merge, no push, no tag).
**Scope:** one file changes — `skills/karpathy-wiki/SKILL.md`. No script changes. No test changes. No new scripts. One new commit.

---

## Goal

Close the failure mode demonstrated by real-session transcript `/Users/lukaszmaj/.claude/projects/-Users-lukaszmaj-dev-bigbrain/dde7c6cf-1951-4da3-b9f6-e097c440a13a.jsonl` (events 145-186): a research subagent's completion notification semantically triggered the karpathy-wiki skill but the main agent skipped the capture step and never returned to it. The user confirmed the bug: the capture was never written; the earlier wiki page (which was ingested from an older version of the same research file) stayed stale. No signal alerted anyone.

Two independent Opus reviewers analyzed the skill + transcript + the two newly-ingested wiki pages on file formats and headless-claude subagent lifecycle. This patch lands the modifications both reviewers agreed on, minus the two items the user explicitly rejected (budget/turn caps — a user-account concern, not a skill concern) and minus items requiring Anthropic-roadmap changes (`--bare`, `--json-schema`).

Specifically this patch:

1. Turns the "capture now, not later" rule into a **concrete pre-stop-turn check** with a runnable `ls .wiki-pending/` command. (Tier 2 Mod-A, and the synthesized fix for Mod-E — in-session recovery.)
2. Extends the 30-day durability test with a "would future-me search for this" clause. (Tier 2 Mod-B.)
3. Rewrites the rationalization row for process-narration into a **verifiable-in-moment fabrication test**. (Tier 2 Mod-C.)
4. Extends ingest step 4 with **sha256 short-circuit**, **title-scope check**, and **overwrite detection** so two different-shaped research files to the same path do not silently clobber each other's wiki pages. (Tier 2 Mod-D.)
5. Adds a **stalled-capture recovery subsection**: `.md.processing` files older than 10 minutes with no `log.md` completion entry get renamed back to `.md` and re-spawned. (Format-reviewer Must-1 — the single highest-value change.)
6. Adds an **index-size ceiling** bullet to the Numeric thresholds section (200 entries / 8KB / 2000 tokens). (Format-reviewer Should-3; evidence: Chroma Context Rot.)
7. Adds three new rationalization-table rows (turn-not-done-until-capture, fabrication-quote-test replacing the transparency row, sha-match skip rationale) — captures the specific failure mode from the transcript.
8. Deletes the stale "What changes between main and project wikis" standalone section (which duplicates step 9 and uses outdated `origin` terminology) — moves its 3-bullet propagation criteria inline into step 9 — creating the line-budget headroom for the additions.

This patch does **NOT** try to:
- Implement a Stop-hook gate that mechanically blocks turn-closure until `.wiki-pending/` is drained. (Still self-discipline until the hook is wired. Marked v2.x follow-up.)
- Add budget or turn-count caps to the spawned ingester (user rejected — those are user-account concerns).
- Re-introduce the `--bare` flag or `--json-schema` output parsing (both deferred — require roadmap changes or a real pain point).
- Run the Opus audit again. Re-audit is a separate activity after 5-10 real-session ingests elapse.
- Change any script. Change any test. The patch is prose-only in SKILL.md.

---

## Deliberate scope cuts

These items are NOT in scope. The implementer must not expand scope to include them.

- **Stop-hook gate for pre-stop-turn `.wiki-pending/` drain.** Reviewer (Mod-A) was explicit: "the skill has triggers but no gates ... relabeling 'later means never' as 'turn not over' is a rename, not a gate. A real gate lives outside the model's reasoning." This patch adds the **concrete check** to the skill prose; wiring a Stop hook that runs `ls .wiki-pending/` and refuses turn-closure on non-empty dir is a separate v2.x plan.
- **`--max-turns 40 --max-budget-usd 1.00` on the spawned ingester.** User rejected: budget and turn caps are user-account concerns, not skill concerns. The underlying concern (runaway ingester) is handled by stalled-capture recovery instead.
- **Ingester exit-code handling.** Coupled to the rejected turn/budget caps.
- **`--bare` + explicit `--allowedTools` on the spawned ingester.** Deferred — `--bare` is documented to become the default for `-p` in a future Anthropic release; re-evaluate then.
- **`--json-schema` output parsing from spawned ingesters.** Deferred — requires a real pain point first.
- **A new concept-page split discriminator ("27B MoE" vs "27B+31B comparison") beyond the title-scope rule added to step 4.** If the title-scope check flags mismatches correctly in practice, no further discriminator is needed. Revisit if it regresses.
- **Unit tests for any of the new prose rules.** This is a SKILL.md-only patch. All new rules are agent-facing prose that the agent follows at runtime; no code path to test. `tests/self-review.sh` and `tests/run-all.sh` must remain green (unchanged), which is all the mechanical verification needed.
- **Any one-time `~/wiki/` content change.** This patch does not touch the live wiki. If the implementer notices a live-wiki page that looks stale because of this bug class (e.g. `~/wiki/concepts/gemma4-27b-hardware-requirements.md` still being MoE-only), file a note; do NOT edit live pages as part of this patch.
- **Reviewer re-run.** The plan is planner → reviewer → implementer, three subagents. You (planner) produce this file; a reviewer vets it; an implementer executes it. The reviewer does not re-run the original Opus audits — they only vet this plan against the input requirements.

---

## Read before starting

The implementer MUST read these files end-to-end before touching SKILL.md:

1. `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md` — the file being edited. 415 lines as of this plan. Understand its existing section layout (the section order from the grep below is the target order; this patch preserves it):
   - `## Capture — what, when, how` (line 95)
   - `### What counts as wiki-worthy (trigger criteria)` (line 97)
   - `### What is NOT wiki-worthy` (line 110)
   - `### Capture file format` (line 121)
   - `### Capture body sufficiency — YOU MUST WRITE ENOUGH` (line 146)
   - `### Red flags — STOP and expand the body` (line 173)
   - `### After writing a capture` (line 181)
   - `### If the ingester rejects a capture (needs_more_detail: true)` (line 193)
   - `## Ingest — what the headless ingester does` (line 209)
   - `### Ingester steps` (line 213)
   - `### Tier-1 lint at ingest (inline)` (line 282)
   - `### Numeric thresholds (from schema.md)` (line 308)
   - `### Quality ratings — what the 4 dimensions mean` (line 316)
   - `## Query — how the agent uses the wiki` (line 336)
   - `## Commands (minimal surface)` (line 348)
   - `## Rules you must not break` (line 357)
   - `## Rationalizations to resist (red flags)` (line 367)
   - `## What changes between main and project wikis` (line 392) — **DELETED by this patch** (content folded into ingest step 9)
   - `## Read-before-write, in detail` (line 401)
   - `## What goes in references/` (line 413)

2. `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/docs/planning/2026-04-24-karpathy-wiki-v2-hardening.md` — the style template this plan matches. Focus on Task 34 (lines 2725-2903) — the cleanest analog: a SKILL.md-only prose patch with verbatim before/after blocks and a single commit.

3. `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/self-review.sh` — the 9 mechanical invariants SKILL.md must keep passing. Specifically:
   - `SKILL.md under 500 lines`
   - `no SKILL_DIR placeholder remains in SKILL.md`

4. `/Users/lukaszmaj/wiki/concepts/agent-vs-machine-file-formats.md` lines 150-168 — the per-surface recommendations table where the index-size ceiling is derived (Chroma Context Rot + Obsidian MOC + Starmorph). Read specifically the "Index" row to pin the exact numeric ceiling.

5. `/Users/lukaszmaj/wiki/concepts/claude-code-headless-subagents.md` lines 218-224 — issue #29642 documents headless single-agent sessions dying with SIGTERM after 3-10 minutes on Max subscription. This is the empirical basis for picking 10 minutes as the stalled-capture threshold.

6. `/Users/lukaszmaj/.claude/projects/-Users-lukaszmaj-dev-bigbrain/dde7c6cf-1951-4da3-b9f6-e097c440a13a.jsonl` events 145-186 (use `python3 -c "import json; [print(i, json.loads(l)) for i,l in enumerate(open('<path>'))][145:186]"` if needed) — the actual failure-mode transcript. The user's diagnosis in event 182 is the mental model this patch encodes: "capture after replying, but the reply isn't done until the capture is written."

---

## Line-budget accounting

Current SKILL.md: **415 lines**. Target: **< 500 lines** (hard constraint from `tests/self-review.sh`).

Additions (approximate):
- New subsection "Turn closure — before you stop": +14 lines (under `## Capture — what, when, how`, after `### After writing a capture`).
- New subsection "If an ingester died mid-run (stalled-capture recovery)": +16 lines (as a sibling to `### If the ingester rejects a capture`).
- Extension to ingest step 4 (overwrite detection — sha match, title-scope check): +12 lines.
- New bullet in `### Numeric thresholds (from schema.md)` — index-size ceiling: +1 line.
- Three new rationalization-table rows — `+3` rows of 1 line each, net `+3` lines (one row replaces the existing "I'm being transparent about my process" row in place, so that row counts as a rewrite not an add).
- Durability-test extension to the `### What counts as wiki-worthy (trigger criteria)` section: +2 lines.

Subtotal additions: **~48 lines**.

Deletions:
- `## What changes between main and project wikis` section (lines 392-399 = 8 lines, including the preceding blank line boundary) — content (the 3 propagation criteria bullets) folds into ingest step 9. Step 9 grows by 3 bullets + 1 header line = +4 lines. Net deletion: `-8 + 4 = -4 lines`.

Net delta: **+44 lines**.

Projected final line count: **415 + 55 = ~470 lines** (revised after per-step recount; initial estimate of ~459 undercounted the stalled-capture subsection by ~6 lines and step 4's extension by ~3 lines). Budget headroom: **~30 lines** below the 500-line limit.

**If the implementer's actual edit overshoots this estimate and exceeds 500 lines**, the required compression is: split the `### Quality ratings — what the 4 dimensions mean` subsection into a new file `skills/karpathy-wiki/references/quality-ratings.md` and leave a short pointer in SKILL.md. This frees ~20 lines. Do NOT compress any of the new prose added by this patch — every sentence in the new prose is load-bearing.

---

## The patch

One task. One commit. Done.

**Files:**
- Modify: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md`

### Numbered steps

- [ ] **Step 1: Extend the `### What counts as wiki-worthy (trigger criteria)` section with the durability-test rewrite**

BEFORE (lines 97-108 of current SKILL.md; quote verbatim):

```markdown
### What counts as wiki-worthy (trigger criteria)

Write a capture when any of these fire:

- A research subagent returned a file with durable findings
- You and the user resolved a confusion — something neither of you knew before
- You discovered a gotcha, quirk, or non-obvious behavior in a tool
- You validated a pattern (compared approaches, picked one, with reasons)
- An architectural decision was made with explicit rationale
- External knowledge was found that updates an existing wiki page
- Two claims contradict each other
- The user adds a file to `raw/`
```

AFTER (replace the entire subsection verbatim):

```markdown
### What counts as wiki-worthy (trigger criteria)

Write a capture when any of these fire:

- A research subagent returned a file with durable findings
- You and the user resolved a confusion — something neither of you knew before
- You discovered a gotcha, quirk, or non-obvious behavior in a tool
- You validated a pattern (compared approaches, picked one, with reasons)
- An architectural decision was made with explicit rationale
- External knowledge was found that updates an existing wiki page
- Two claims contradict each other
- The user adds a file to `raw/`

**Durability test.** A capture is wiki-worthy when (a) the information is still true in 30 days AND (b) future-you would search for it. If (a) fails it is version-bump noise; if (b) fails it is a personal-preference / task-scratch detail. Both must hold. Personal-preference carve-outs that the user has asked you to remember (explicit "remember this") bypass this test — capture them but tag them `#personal`.
```

Rationale: Tier 2 Mod-B. Preserves the existing personal-preferences carve-out (which is implicit now but the new sentence makes it visible), filters version-bump noise.

- [ ] **Step 2: Add a new subsection "### Turn closure — before you stop" after `### After writing a capture`**

This subsection is new. Insert it between the existing `### After writing a capture` section (ends line 191 with the "Never wait for the ingester..." sentence) and the existing `### If the ingester rejects a capture (needs_more_detail: true)` section (starts line 193).

Insert verbatim:

```markdown
### Turn closure — before you stop

Before emitting your final assistant message in any turn, run this single check:

```bash
ls "<wiki_root>/.wiki-pending/" 2>/dev/null | grep -v '^archive$\|^schema-proposals$' | head -20
```

If the output lists any `.md` file OR any `.md.processing` file older than 10 minutes (see next subsection), the turn is NOT done. Handle the pending captures first, then re-check, then close the turn.

Covered cases, both must be handled before turn-closure:

1. **You forgot to write a capture this turn.** A trigger fired (research subagent returned a file, confusion resolved, gotcha surfaced) and you answered the user without calling `wiki-spawn-ingester.sh`. The `.wiki-pending/` check catches nothing, but the trigger criteria in the previous subsections still apply: if a trigger fired, write the capture before closing the turn.
2. **A previous turn's capture was never written.** Session drain runs on session-start only; it cannot catch mid-session misses. A capture from an earlier turn may be sitting in `.wiki-pending/` with `needs_more_detail: true`, or a `.md.processing` file may be stalled. The `ls` command surfaces both; the rejection-handling and stalled-recovery subsections tell you what to do.

This is a self-discipline rule until a Stop-hook gate is wired (v2.x). The check is cheap; run it every turn.
```

Rationale: Tier 2 Mod-A + Mod-E combined. The `ls` command is concrete and runnable. The "covered cases" list explicitly binds Mod-E (in-session recovery) into the same mechanism as Mod-A (turn closure) — both are caught by the same `ls` check, so there is one checkpoint, not two.

- [ ] **Step 3: Add a new subsection "### If an ingester died mid-run (stalled-capture recovery)" after `### If the ingester rejects a capture (needs_more_detail: true)`**

This subsection is new. Insert it after the existing `### If the ingester rejects a capture` section (ends line 207 with the "I'll come back to it later" sentence) and before the existing `## Ingest — what the headless ingester does` section header (line 209).

Insert verbatim:

```markdown
### If an ingester died mid-run (stalled-capture recovery)

`.wiki-pending/*.md.processing` files that are still present 10+ minutes after their rename are stalled — the ingester that claimed them either crashed, was SIGTERMed by the runtime (documented behaviour on Max subscription; see `~/wiki/concepts/claude-code-headless-subagents.md` issue #29642, 3-10 min), or was orphaned when a `claude -p` parent exited (the in-process Node worker dies with the parent).

A capture is definitively stalled when:

1. `<capture>.md.processing` exists in `.wiki-pending/`, AND
2. The file's mtime is older than 10 minutes, AND
3. No `log.md` line within the last N turns references this capture, by EITHER its basename OR the title from its frontmatter. Search for both: the `reject | <basename>` / `skip | <basename>` / `stalled | <basename>` / `overwrite | <basename>` forms use basename; the `ingest | <title>` form uses the title. If either form matches, the capture is NOT stalled — it completed or was deliberately rejected. Only the absence of both forms flags a stall.

All three conditions together — NEVER act on mtime alone; a legitimate in-flight ingester on a large page may legitimately take several minutes.

When all three hold:

1. Rename the file back from `.md.processing` to `.md` (leaves it in `.wiki-pending/` — the next turn's turn-closure check will see it).
2. Append a line to `log.md`: `## [<timestamp>] stalled | <capture-basename> — reclaimed after 10+ min, no ingest or reject entry found`.
3. Re-spawn the ingester: `bash scripts/wiki-spawn-ingester.sh "<wiki_root>" "<capture_path>"`.

Do NOT delete the stalled `.md.processing` file — the rename is the recovery. Do NOT attempt to resume the dead ingester's session — `claude -p` subagent transcripts persist but the worker is gone (documented: resume starts a fresh worker, it does not resurrect an in-flight one). Start clean.
```

Rationale: Format-reviewer Must-1. The 10-minute threshold matches the documented SIGTERM worst case; the three-condition gate (processing file + age + no log entry) prevents false positives on legitimate in-flight ingesters.

- [ ] **Step 4: Extend ingest step 4 with sha256 short-circuit + title-scope check + overwrite-detection recovery**

BEFORE (lines 233-249 of current SKILL.md; quote verbatim):

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
   - After copying to raw/, create a `sources/<basename>.md` pointer page IF one does not already exist. Template in `references/source-pointer-template.md` (if present) or inline in the skill's base prose. Every raw file MUST have a matching sources/ pointer page — the validator now enforces this.
```

AFTER (replace the entire step 4 verbatim; preserves every rule from before and adds the three new sub-rules at the end):

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
   - After copying to raw/, create a `sources/<basename>.md` pointer page IF one does not already exist. Template in `references/source-pointer-template.md` (if present) or inline in the skill's base prose. Every raw file MUST have a matching sources/ pointer page — the validator now enforces this.
   - **sha256 short-circuit.** If `raw/<basename>` already exists AND `sha256(new) == manifest[raw/<basename>].sha256`, the evidence content is identical — skip re-ingest of this capture and append `## [<timestamp>] skip | <capture-basename> — sha match, no-op` to `log.md`. Archive the capture normally (step 10). This prevents re-ingesting the same research file twice when the capture-trigger fires on a near-duplicate.
   - **Title-scope check.** Before merging into an existing wiki page in step 6, compare the new evidence's scope to the existing page's slug. Scope is the set of distinct entities (product names, versions, model names, concepts) the evidence covers. If the existing page's slug is NARROWER than the new evidence's scope (example: existing `concepts/gemma4-27b-hardware-requirements.md` vs new evidence covering a 27B+31B comparison), do NOT force-merge the broader content into the narrower-titled page. Instead, either (a) create a sibling concept page with a scope-appropriate slug (e.g. `concepts/gemma4-27b-vs-31b-hardware-comparison.md`) and cross-link both, or (b) rename the existing page's slug AND frontmatter title to cover the new scope, then merge — only if no other wiki page currently links to the old slug (if any do, use option (a) to avoid broken links). Log which option was taken in `log.md`.
   - **Overwrite-detection recovery.** If `raw/<basename>` already exists AND the new sha256 differs from the manifest entry AND the manifest's `last_ingested` is within the last 60 minutes (the evidence file on disk was replaced since the previous ingest), treat this as an overwrite situation: copy the new evidence to `raw/<basename>` AS NORMAL, but also append `## [<timestamp>] overwrite | <capture-basename> — raw sha changed since <previous_ingested_iso>, previous referenced_by: [<list>]` to `log.md`. Proceed with the rest of step 4 and the title-scope check in step 6 as above. The overwrite is not an error — it is the exact scenario from the failure-mode transcript (two research agents both wrote to `2026-04-24-gemma4-hardware.md`), and the title-scope check catches the content-divergence part.
```

Rationale: Tier 2 Mod-D (all three sub-rules: sha match short-circuit, title-scope check, overwrite detection). Directly addresses the user's failure-mode transcript where two research agents wrote different-scope content to the same file path and the wiki page stayed stale.

- [ ] **Step 5: Fold the main-vs-project propagation criteria into ingest step 9, then delete the standalone section**

This step is two file-edits in one: first expand step 9, then delete the now-duplicate `## What changes between main and project wikis` section.

5a. BEFORE (lines 276-277 of current SKILL.md; quote verbatim):

```markdown
9. **If this wiki is a project wiki** and the capture is general-interest:
   write a new capture in the main wiki's `.wiki-pending/` with `propagated_from: <project wiki path>`.
```

AFTER (replace step 9 verbatim):

```markdown
9. **If this wiki is a project wiki, decide propagation.** A project wiki evaluates whether each capture is general-interest (useful across projects) or project-specific, using these criteria:
   - **Propagate** if the capture describes a tool, concept, pattern, or principle applicable outside this project. Write a new capture in the main wiki's `.wiki-pending/` with `propagated_from: <project wiki path>`.
   - **Keep local** if the capture uses project-specific names, references this codebase's architecture, or only applies here.
   - **When ambiguous, propagate** with a short pointer page — lower risk than missing knowledge.

   Main wiki ingestion is otherwise identical to project wiki ingestion.
```

5b. BEFORE (lines 392-399 of current SKILL.md; quote verbatim — note this section goes away entirely, and the preceding blank line at 391 should also go so the structural boundary between "Rationalizations" at 390 and "Read-before-write" at 401 becomes one blank line):

```markdown
## What changes between main and project wikis

The only behavioral difference: during ingest, a project wiki evaluates whether each capture is general-interest (useful across projects) or project-specific. General-interest captures are propagated to the main wiki's `.wiki-pending/` with an `origin` marker. Main wiki ingestion is otherwise identical.

Criteria for propagation:
- **Propagate** if the capture describes a tool, concept, pattern, or principle applicable outside this project.
- **Keep local** if it uses project-specific names, references this codebase's architecture, or only applies here.
- **When ambiguous, propagate** with a short pointer page — lower risk than missing knowledge.
```

AFTER: **delete the entire section including the preceding blank line**. After the delete, the line after "All of these are violations of the Iron Law." (previously line 390) should be a single blank line (previously line 391), followed directly by `## Read-before-write, in detail` (previously line 401).

Rationale: The deleted section duplicated ingest step 9 and used the older `origin` terminology (stale after the v2-hardening `propagated_from` rename). The criteria bullets (propagate / keep local / when ambiguous) survive inside step 9. Net deletion of 4 lines (8 removed - 4 added to step 9 expansion) creates budget headroom for the additions.

- [ ] **Step 6: Add the index-size ceiling bullet to the Numeric thresholds section**

BEFORE (lines 308-314 of current SKILL.md; quote verbatim):

```markdown
### Numeric thresholds (from schema.md)

- **Split a concept page** when it has material from 2+ sources OR exceeds 200 lines.
- **Archive a raw source** when it's referenced by 5+ wiki pages (move to `raw/archive/`, update references).
- **Restructure a top-level category** when it contains 500+ pages.

When a threshold is reached, propose the restructure via a `schema-proposal` capture in `.wiki-pending/schema-proposals/`. Do NOT restructure during the current ingest.
```

AFTER (replace the section verbatim; adds one bullet):

```markdown
### Numeric thresholds (from schema.md)

- **Split a concept page** when it has material from 2+ sources OR exceeds 200 lines.
- **Archive a raw source** when it's referenced by 5+ wiki pages (move to `raw/archive/`, update references).
- **Restructure a top-level category** when it contains 500+ pages.
- **Split or atom-ize `index.md`** when it exceeds ~200 entries / 8KB / 2000 tokens — orientation degrades beyond that. Evidence: Chroma Context Rot research shows retrieval accuracy starts degrading around 1,000 tokens of preamble; Obsidian MOC practitioners cap at 25 items per MOC; Starmorph flags 100-200 pages as the scale-out point.

When a threshold is reached, propose the restructure via a `schema-proposal` capture in `.wiki-pending/schema-proposals/`. Do NOT restructure during the current ingest.
```

Rationale: Format-reviewer Should-3. The number triplet (200 entries / 8KB / 2000 tokens) is redundant on purpose — the implementer of `wiki status` can pick whichever they can measure cheaply.

- [ ] **Step 7: Update the rationalization table: add three new rows, rewrite the transparency row**

BEFORE (lines 367-390 of current SKILL.md; quote verbatim — entire "Rationalizations" section):

```markdown
## Rationalizations to resist (red flags)

When you're about to skip a capture, check these red flags:

| Rationalization | Reality |
|---|---|
| "The user will remember this / it's obvious from context" | The user won't; context evaporates. That's the whole point of the wiki. |
| "It's too trivial for the wiki" | If it meets the trigger criteria, capture it. Lint filters noise later. |
| "I'll capture it later / I'm mid-task" | Later means never. Capture is milliseconds. Do it now. |
| "It's already covered" | Orientation protocol tells you if it is. Did you check? |
| "The user didn't ask me to save this" | Capture triggers fire automatically — no explicit user request required. |
| "I don't have a memory tool available" | This skill IS the memory tool. Its presence is the trigger. |
| "The file is already in a good place" (filing ≠ capturing) | Location isn't organization. Capture extracts concepts, not just files. |
| "I'll answer from training data; the question doesn't look wiki-shaped" | Run orientation first. The wiki's scope is whatever has been captured — you can't know without checking. |
| "This doesn't look wiki-shaped / there's no code here / this isn't a wiki context" | Tone is not the trigger. If new factual info appeared — a USB version mapping, a library quirk, a historical date, anything durable — capture. A casual "what's the difference between USB 3.0, 3.1, 3.2" exchange is as wiki-worthy as a full research report on API rate limits. |
| "The user asked a casual question, research was just informational" | A research subagent returning a file with findings is itself a TRIGGER line in the description. User framing doesn't override that. |
| "The self-rating step is subjective, I'll skip it" | Ratings are mandatory. Lowball over missing; the validator flags missing blocks. |
| "I'll give everything 5s to be safe" | 5 is exceptional. Lowballing a page to 3 flags it for `wiki doctor` later, which is the right outcome. False 5s silently bake errors. |
| "I'll rewrite a human-rated page's quality because I just touched it" | Forbidden. `rated_by: human` is sacred. Touch only the body; leave the quality block alone. |
| "My conversation capture can be short — short chat, or the ingester figures it out" | The ingester has no transcript access. Whatever you omit is gone. Body-size floor is about information density, not conversation length. |
| "I'll skip this `needs_more_detail` rejection; the user just asked something else" | Forbidden. Expanding takes seconds. Ignoring it means the knowledge is lost and `.wiki-pending/` fills with dust. Handle the rejection before answering the new turn. |
| "I'm being transparent about my process" (narrating the capture/spawn/orientation steps) | Transparency about process IS noise. The user wanted the answer, not a tour of the wiki mechanics. Capture, spawn, orient — silently. Speak only the announce line and the answer. |

All of these are violations of the Iron Law.
```

AFTER (replace the entire section verbatim; preserves every row above, adds 3 new rows near the `"I'll capture it later"` row where they thematically fit, and rewrites the transparency row into the fabrication-quote-test):

```markdown
## Rationalizations to resist (red flags)

When you're about to skip a capture, check these red flags:

| Rationalization | Reality |
|---|---|
| "The user will remember this / it's obvious from context" | The user won't; context evaporates. That's the whole point of the wiki. |
| "It's too trivial for the wiki" | If it meets the trigger criteria, capture it. Lint filters noise later. |
| "I'll capture it later / I'm mid-task" | Later means never. Capture is milliseconds. Do it now. |
| "I responded to the user already, I'll capture separately" | Turn isn't done until the capture is written. Reply-first-capture-later is fine; reply-first-never-capture is the failure mode this skill was hardened against. Run the `ls .wiki-pending/` check before you emit the stop sentinel. |
| "It's already covered" | Orientation protocol tells you if it is. Did you check? |
| "The user didn't ask me to save this" | Capture triggers fire automatically — no explicit user request required. |
| "I don't have a memory tool available" | This skill IS the memory tool. Its presence is the trigger. |
| "The file is already in a good place" (filing ≠ capturing) | Location isn't organization. Capture extracts concepts, not just files. |
| "I'll answer from training data; the question doesn't look wiki-shaped" | Run orientation first. The wiki's scope is whatever has been captured — you can't know without checking. |
| "This doesn't look wiki-shaped / there's no code here / this isn't a wiki context" | Tone is not the trigger. If new factual info appeared — a USB version mapping, a library quirk, a historical date, anything durable — capture. A casual "what's the difference between USB 3.0, 3.1, 3.2" exchange is as wiki-worthy as a full research report on API rate limits. |
| "The user asked a casual question, research was just informational" | A research subagent returning a file with findings is itself a TRIGGER line in the description. User framing doesn't override that. |
| "The research file hasn't changed, I'll skip re-capture" | Correct *only if* sha256 of the file matches `manifest[raw/<basename>].sha256`. Different sha = different content = new capture. Ingest step 4's sha-match short-circuit is the only valid place to skip; skipping in the foreground is fabrication. |
| "The self-rating step is subjective, I'll skip it" | Ratings are mandatory. Lowball over missing; the validator flags missing blocks. |
| "I'll give everything 5s to be safe" | 5 is exceptional. Lowballing a page to 3 flags it for `wiki doctor` later, which is the right outcome. False 5s silently bake errors. |
| "I'll rewrite a human-rated page's quality because I just touched it" | Forbidden. `rated_by: human` is sacred. Touch only the body; leave the quality block alone. |
| "My conversation capture can be short — short chat, or the ingester figures it out" | The ingester has no transcript access. Whatever you omit is gone. Body-size floor is about information density, not conversation length. |
| "I'll skip this `needs_more_detail` rejection; the user just asked something else" | Forbidden. Expanding takes seconds. Ignoring it means the knowledge is lost and `.wiki-pending/` fills with dust. Handle the rejection before answering the new turn. |
| "I have a good reason to skip this capture" (any rationalization not literally in this table) | Cite the exact SKILL.md line that justifies skipping. If you cannot quote it, you are fabricating — capture now. Transparency-about-process is a subset: the user wanted the answer, not a tour of the wiki mechanics. Capture, spawn, orient — silently. Speak only the announce line and the answer. |

All of these are violations of the Iron Law.
```

Rationale: Three changes at once:
- New row after "I'll capture it later" — encodes the exact failure mode from transcript event 182. The user's formulation ("the reply isn't done until the capture is written") is the test sentence.
- New row after "The user asked a casual question" — encodes the sha-match short-circuit rationale so the agent does not confuse "same filename = no new capture" (wrong) with "same sha = no new ingest" (right).
- The final row replaces the transparency-row-in-place with Tier 2 Mod-C's sharpened framing ("Cite the exact SKILL.md line that justifies skipping"). The transparency content survives as the row's second sentence.

- [ ] **Step 8: Verify SKILL.md line count is under 500**

Run:
```bash
wc -l /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md
```

Expected: line count **less than 500**. Based on the revised line-budget accounting above, projected count is ~470 lines. If actual exceeds 500, the required compression is: move `### Quality ratings — what the 4 dimensions mean` (currently lines 316-334 in the original file, ~19 lines) into a new file `skills/karpathy-wiki/references/quality-ratings.md` and leave this 2-line pointer in its place:

```markdown
### Quality ratings — what the 4 dimensions mean

See [`references/quality-ratings.md`](references/quality-ratings.md) for the 4-dimension semantics, the `rated_by` value ladder (ingester / doctor / human), and the "never clobber `rated_by: human`" rule.
```

Saves ~17 lines. Commit the new file with the same commit as the SKILL.md change. Do NOT compress any of the new prose added by steps 1-7.

- [ ] **Step 9: Run self-review to confirm invariants still hold**

Run:
```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/self-review.sh
```

Expected: every check passes (9 PASS lines, exit 0). The check that matters most: `SKILL.md under 500 lines`. The check `no SKILL_DIR placeholder remains in SKILL.md` must also pass — do not re-introduce `SKILL_DIR` anywhere in the new prose.

- [ ] **Step 10: Run full test suite**

Run:
```bash
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/run-all.sh
```

Expected: `passed: 17`, `failed: 0`. The suite is 14 unit tests + 3 integration tests. None of them exercise SKILL.md prose, so they should all pass unchanged. If any fail, investigate — likely a pre-existing failure unrelated to this patch, surface it to the user; do NOT attempt to fix unrelated failures in this commit.

- [ ] **Step 11: Final SKILL.md inspection**

Run:
```bash
wc -l /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md
grep -c "^## \|^### " /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md
grep -n "Turn closure\|stalled-capture\|sha256 short-circuit\|title-scope check\|overwrite-detection\|index-size ceiling\|stalled | \|\\.wiki-pending\|Durability test\|cite the exact SKILL.md line" /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md
```

Expected:
- Line count under 500 and above 440.
- Section-heading count: original had 23 headings (all `##` + `###`); after this patch: original 23 minus 1 deleted (`## What changes between main and project wikis`) plus 2 new (`### Turn closure — before you stop` and `### If an ingester died mid-run (stalled-capture recovery)`) = **24 headings**. If the count differs, recount and verify no heading was accidentally added or removed.
- The grep for new keywords should return matches for: `Turn closure` (step 2), `stalled-capture recovery` (step 3), `sha256 short-circuit` / `title-scope check` / `overwrite-detection recovery` (step 4), `index-size ceiling` or `Split or atom-ize` (step 6), `stalled | ` (the log.md entry format, step 3), `.wiki-pending/` (multiple), `Durability test` (step 1), and `cite the exact SKILL.md line` (step 7). Every one of these confirms a step-specific edit landed. If any keyword returns zero matches, the corresponding step was silently skipped — investigate and re-run that step.

- [ ] **Step 12: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki
git add skills/karpathy-wiki/SKILL.md
git commit -m "$(cat <<'EOF'
feat(skill): v2.1 missed-capture patch — turn-closure check, stalled recovery, overwrite detection

Closes the failure mode from transcript dde7c6cf-1951-4da3-b9f6-e097c440a13a
(events 145-186): research subagent completion triggered the capture rule
semantically but the main agent skipped the capture and never returned to
it; the earlier ingested wiki page stayed stale with no signal.

Changes to skills/karpathy-wiki/SKILL.md:
- Add "Turn closure — before you stop" subsection with concrete
  ls .wiki-pending/ check; covers both forgot-capture-this-turn and
  forgot-capture-earlier-turn cases in one pre-stop-turn mechanism
  (Tier 2 reviewer Mod-A + Mod-E).
- Add "If an ingester died mid-run (stalled-capture recovery)"
  subsection: .md.processing files older than 10 min with no matching
  log.md ingest|reject entry get renamed back to .md and re-spawned
  (format reviewer Must-1). Threshold picked against #29642 SIGTERM
  3-10 min upper bound documented in claude-code-headless-subagents wiki
  page.
- Extend ingest step 4 with sha256 short-circuit, title-scope check,
  and overwrite-detection recovery (Tier 2 reviewer Mod-D). Addresses
  the transcript's root cause: two research agents wrote different-scope
  content to the same file path; previously silent clobber.
- Add durability test to trigger criteria: still true in 30 days AND
  future-me would search for it, with personal-preferences carve-out
  preserved via #personal tag (Tier 2 reviewer Mod-B).
- Add index-size ceiling (200 entries / 8KB / 2000 tokens) to Numeric
  thresholds; cited to Chroma Context Rot / Obsidian MOC / Starmorph
  via the agent-vs-machine-file-formats wiki page (format reviewer
  Should-3).
- Rationalization table: add three rows (replied-but-not-captured,
  sha-match skip rationale, cite-the-line-or-fabricating), with the
  transparency row folded into the cite-the-line row (Tier 2 reviewer
  Mod-C).
- Delete standalone "What changes between main and project wikis"
  section — duplicated step 9 and used stale origin terminology;
  propagation criteria folded into step 9 directly.

Line-count delta: +44 lines (estimated), well under the 500-line limit
enforced by tests/self-review.sh. No script changes, no test changes.

Out of scope (deliberate, per user instruction): --max-turns /
--max-budget-usd caps on the spawned ingester (user's position: budget
is a user-account concern); Stop-hook gate for mechanical turn-closure
enforcement (v2.x follow-up); --bare / --json-schema (roadmap-dependent).
EOF
)"
```

Verify with `git log -1 --stat`:
```bash
cd /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki
git log -1 --stat
```

Expected: `skills/karpathy-wiki/SKILL.md` listed as modified with an insertion/deletion count consistent with +44 net lines (e.g. ~55 insertions, ~11 deletions for the delete-and-fold work, roughly).

---

## Verification

The implementer runs these three commands at the end and confirms all three pass:

```bash
wc -l /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/self-review.sh
bash /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/run-all.sh
```

Expected output:

1. `wc -l` prints a single integer strictly less than 500 (projected ~470).
2. `self-review.sh` prints 9 PASS lines and exits 0.
3. `run-all.sh` prints `passed: 17` and `failed: 0` and exits 0.

If all three pass, the patch is green. Commit is already made in step 12.

---

## Commit message (verbatim — already embedded in step 12)

```
feat(skill): v2.1 missed-capture patch — turn-closure check, stalled recovery, overwrite detection

Closes the failure mode from transcript dde7c6cf-1951-4da3-b9f6-e097c440a13a
(events 145-186): research subagent completion triggered the capture rule
semantically but the main agent skipped the capture and never returned to
it; the earlier ingested wiki page stayed stale with no signal.

Changes to skills/karpathy-wiki/SKILL.md:
- Add "Turn closure — before you stop" subsection with concrete
  ls .wiki-pending/ check; covers both forgot-capture-this-turn and
  forgot-capture-earlier-turn cases in one pre-stop-turn mechanism
  (Tier 2 reviewer Mod-A + Mod-E).
- Add "If an ingester died mid-run (stalled-capture recovery)"
  subsection: .md.processing files older than 10 min with no matching
  log.md ingest|reject entry get renamed back to .md and re-spawned
  (format reviewer Must-1). Threshold picked against #29642 SIGTERM
  3-10 min upper bound documented in claude-code-headless-subagents wiki
  page.
- Extend ingest step 4 with sha256 short-circuit, title-scope check,
  and overwrite-detection recovery (Tier 2 reviewer Mod-D). Addresses
  the transcript's root cause: two research agents wrote different-scope
  content to the same file path; previously silent clobber.
- Add durability test to trigger criteria: still true in 30 days AND
  future-me would search for it, with personal-preferences carve-out
  preserved via #personal tag (Tier 2 reviewer Mod-B).
- Add index-size ceiling (200 entries / 8KB / 2000 tokens) to Numeric
  thresholds; cited to Chroma Context Rot / Obsidian MOC / Starmorph
  via the agent-vs-machine-file-formats wiki page (format reviewer
  Should-3).
- Rationalization table: add three rows (replied-but-not-captured,
  sha-match skip rationale, cite-the-line-or-fabricating), with the
  transparency row folded into the cite-the-line row (Tier 2 reviewer
  Mod-C).
- Delete standalone "What changes between main and project wikis"
  section — duplicated step 9 and used stale origin terminology;
  propagation criteria folded into step 9 directly.

Line-count delta: +44 lines (estimated), well under the 500-line limit
enforced by tests/self-review.sh. No script changes, no test changes.

Out of scope (deliberate, per user instruction): --max-turns /
--max-budget-usd caps on the spawned ingester (user's position: budget
is a user-account concern); Stop-hook gate for mechanical turn-closure
enforcement (v2.x follow-up); --bare / --json-schema (roadmap-dependent).
```

No Co-Authored-By trailers. No `--amend`. A new commit. If the pre-commit hook fails, investigate and fix, then create another new commit.

---

## Deferred to later (explicit v2.x / v3 backlog)

Not in this plan; tracked so future-you knows where the gaps are:

- **Stop-hook gate.** Wire a `hooks/stop.sh` that runs `ls .wiki-pending/ | grep -v archive` and refuses the Stop matcher if the output is non-empty, so turn-closure becomes mechanically enforced rather than self-disciplined. Requires schema changes in `hooks/hooks.json`. The prose in this patch is the contract that hook must satisfy.
- **`--max-turns` and `--max-budget-usd` on spawned ingester.** User rejected for v2.1; revisit when the skill is used in more constrained contexts (e.g., GitHub Actions).
- **`--bare` + explicit `--allowedTools` JSON.** Revisit when Anthropic ships the announced `--bare`-as-default-for-`-p` change (documented but undated).
- **`--json-schema` structured ingester output.** Revisit if the ingester starts producing malformed output in the wild; currently no pain point.
- **Test coverage for the new prose.** Agent-facing rules are not unit-testable without a harness that runs `claude -p` against a fixture transcript and inspects the resulting capture file. Post-v2.x if the rules start regressing.
- **Re-run the Opus reviewers after 5-10 real-session ingests.** Separate activity, not this patch.

---

## Reviewer checklist (for the vetting subagent)

Before approving, confirm:

1. The plan's seven SKILL.md edits match the seven reviewer inputs:
   - Mod-A (turn-closure) → step 2
   - Mod-B (durability test) → step 1
   - Mod-C (cite-the-line) → step 7 (rewritten transparency row)
   - Mod-D (sha / scope / overwrite) → step 4
   - Mod-E (in-session recovery) → folded into step 2
   - Format Must-1 (stalled recovery) → step 3
   - Format Should-3 (index-size ceiling) → step 6
   - Three rationalization rows → step 7
2. User-rejected items are absent: no `--max-turns`, no `--max-budget-usd`, no `--bare`, no `--json-schema`, no Stop hook.
3. No script changes (check `Files:` block — only SKILL.md).
4. No test changes.
5. No `SKILL_DIR` placeholder introduced in new prose (would fail self-review.sh).
6. No `${CLAUDE_PLUGIN_ROOT}` variable introduced in new prose (the file uses relative-from-base-directory paths only).
7. The projected line count (~459) is safely below 500. If you suspect an overshoot, mentally re-count the AFTER blocks against the BEFORE blocks.
8. Commit message has no Co-Authored-By trailers.
9. The verification commands at the end are the exact three specified by the user.
10. Deferred items are listed so the backlog is visible.

If any of these 10 fail, reject with the specific failure. Otherwise approve and the implementer executes.

---

## Execution

Plan complete. The implementing subagent runs steps 1-12 in order. Expected outcome: one new commit on the repo's current branch, SKILL.md grown by ~44 lines to ~459, all 17 tests green, all 9 self-review checks green.

---

### Critical Files for Implementation

- `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md` — the only file modified; every edit in steps 1-7 targets a specific section in this file.
- `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/self-review.sh` — the 9 mechanical invariants the edit must not break; step 9 verifies.
- `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/run-all.sh` — the 17-test suite; step 10 verifies.
- `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/docs/planning/2026-04-24-karpathy-wiki-v2-hardening.md` — style template; Task 34 (lines 2725-2903) is the closest analog.
- `/Users/lukaszmaj/wiki/concepts/claude-code-headless-subagents.md` — issue #29642 (lines 222-224) is the empirical basis for the 10-minute stalled threshold; referenced in step 3's prose.
