---
name: karpathy-wiki
description: |
  Load at the start of EVERY conversation. Entry is non-negotiable — once loaded, the skill's rules apply for the whole session.

  TRIGGER when (immediate capture): any research agent or research subagent completes or returns a file; new factual information is found (web search result, docs, external fact surfaced in conversation); session resolves a confusion; a gotcha, quirk, or non-obvious behavior is observed; a pattern is validated (approaches compared, one picked with reasons); an architectural decision is made with rationale; user pastes a URL or document to study; `raw/` has unprocessed files; user says "add to wiki" / "remember this" / "wiki it" / "save this"; two claims contradict each other.

  TRIGGER when (orientation + citation): the user asks "what do we know about X" / "how do we handle Y" / "what did we decide about Z" / "have we seen this before", or any question the wiki might cover.

  SKIP: routine file edits, syntax lookups, one-off debugging with trivial root causes, time-sensitive data that must be fetched fresh, or questions clearly outside any wiki's scope.

  Do NOT skip based on tone or shape — "this looks like casual chat", "there's no code here", "this isn't a wiki context" are forbidden rationalizations. If new factual info appeared, capture. Tone is not the trigger.
metadata:
  hermes:
    config:
      - key: wiki.path
        description: Path to main wiki directory
        default: ~/wiki
---

# Karpathy Wiki

Auto-capture and auto-ingest durable knowledge into a git-versioned LLM wiki. Based on Andrej Karpathy's LLM Wiki pattern.

**Announce at start:** "Using the karpathy-wiki skill to [capture this / ingest pending captures / answer from wiki]."

**User-facing output contract.** The announce line is the ONLY wiki-mechanics text the user sees. Everything after it is the user's actual answer — the research, the explanation, the result they asked for. Do NOT narrate:

- Orientation steps ("let me orient", "reading schema.md", "checking the index")
- Capture authoring ("writing the capture now", "4,971 bytes — above the 1,500 floor")
- Spawn mechanics ("capture is claimed", "ingester is running detached", "now spawn")
- Timestamps you shell out to get
- Decisions about page structure ("now I'll create concepts/foo.md")
- State-machine narration ("now close this task", "next step")

Do all of the above silently. The user does not need to know the wiki machinery ran; they need the answer. A clean turn looks like: **[announce line] → [the answer]**. Nothing in between.

## YOU DO NOT HAVE A CHOICE

Load this skill on every conversation. Entry is non-negotiable. Entry is CHEAP — it just means you have these rules loaded; it does NOT mean you run the orientation protocol every turn.

- **Entry** happens once per session, automatic.
- **Orientation protocol** runs ONLY when you are about to (a) write a capture, or (b) answer a wiki-covered question. Full spec below.
- **Capture** is a few-hundred-byte file + a detached spawn. Milliseconds. Always do it when a trigger fires.

If new factual information surfaces in a conversation — even one that "looks casual" — you capture. A chat like "wait, what's actually the difference between USB 3.0, 3.1, and 3.2?" producing a clear versioning-rename mapping is just as wiki-worthy as a research report on API rate limits. Tone is not the trigger; durable knowledge is.

## Iron laws

```
NO WIKI WRITE IN THE FOREGROUND
```

```
NO PAGE EDIT WITHOUT READING THE PAGE FIRST
```

```
NO SKIPPING A CAPTURE BECAUSE "IT DOESN'T LOOK WIKI-SHAPED"
```

Every wiki-worthy moment becomes a capture file that a detached ingester turns into wiki pages.

## When a wiki exists (orientation protocol)

Before any wiki operation, read these three files in order:

1. `schema.md` — current categories, taxonomy, thresholds
2. `index.md` — what pages exist
3. Last ~10 entries of `log.md` — recent activity

Only then decide what to do. Without this orientation, you will duplicate existing pages, miss relevant cross-references, or violate the schema.

## When no wiki exists (auto-init)

On the first wiki-worthy moment in any directory:

1. If cwd (or a parent) has a `.wiki-config` → use that wiki.
2. Otherwise, if `$HOME/wiki/.wiki-config` exists → cwd is outside a wiki; create a project wiki at `./wiki/` linked to `$HOME/wiki/`.
3. Otherwise → create the main wiki at `$HOME/wiki/`.

Run the init script. All script paths below are **relative to this skill's base directory** (shown at the top of the skill as `Base directory for this skill: ...`). `cd` into that directory before invoking any script, or prefix each script with the absolute base path.

```bash
cd "<skill-base-directory>"  # from the "Base directory for this skill" preamble

# For main wiki:
bash scripts/wiki-init.sh main "$HOME/wiki"
# For project wiki:
bash scripts/wiki-init.sh project "./wiki" "$HOME/wiki"
```

No prompts. No confirmations. Initialization is automatic and idempotent.

## Capture — what, when, how

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

### What is NOT wiki-worthy

Do NOT capture:

- Routine file operations, syntax lookups, boilerplate
- One-off debugging with trivial root causes
- Questions already well-covered by the wiki (orientation protocol tells you)
- Temporary session state, current-task TODOs
- Personal preferences that don't generalize
- Speculation without evidence

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

<capture body — see "Capture body sufficiency" below for what MUST and MUST NOT go here>
```

**Field contract:**
- `evidence`: the literal string `conversation` (when the capture came from in-session discussion with no file on disk) OR an absolute filesystem path to the source file. NEVER `file`, `mixed`, or a wiki-relative path.
- `evidence_type`: one of `file`, `conversation`, `mixed`. This is a TYPE descriptor only. The ingester does not record this in the manifest; it records `evidence` (as `origin`).
- `propagated_from` (previously `origin`): renamed to prevent confusion with the manifest's `origin` field. Value: absolute path to a project wiki root, or `null`.

### Capture body sufficiency — YOU MUST WRITE ENOUGH

The ingester is a detached `claude -p` process with no access to this conversation's transcript. **Whatever you do not put in the capture body, the ingester cannot know.** A thin capture produces a thin wiki page — the main cause of low-quality wiki entries is the main agent under-writing the capture body.

**Size floors, measured in bytes of the capture body (excluding YAML frontmatter):**

- `evidence_type: file` — ≥ 200 bytes. The raw file does the heavy lifting; the body is a pointer-with-intent. A good file-type body names WHY this raw matters, WHAT categories/tags the ingester should pick, WHICH existing pages are likely relevant, and any cross-wiki links the ingester would miss. Even "this is about X, likely updates page Y" is acceptable here.
- `evidence_type: mixed` — ≥ 1000 bytes. Mixed means "the conversation added material the raw doesn't cover." You owe that delta IN FULL. Don't lean on the raw; the whole point of `mixed` is that the raw is incomplete.
- `evidence_type: conversation` — ≥ 1500 bytes. There is NO raw file. The body IS the evidence. Everything durable from the conversation must be here.

The ingester enforces these floors. A capture under the floor is rejected and dropped back to `.wiki-pending/` with `needs-more-detail: true`. You will see it on the next turn and must expand it.

**For `conversation` captures specifically, you MUST include:**

- Every durable CLAIM the conversation produced — a fact, a number, a version, a commit, a percentage, a decision with rationale. If the claim would survive the session, it goes in.
- Every CONCRETE DETAIL the ingester cannot guess — exact URLs, package names, error messages, command snippets, code examples (keep them short; 5-15 lines is usually enough), numeric thresholds, version ranges.
- Every DECISION made WITH its rationale — "we chose X because Y failed on Z" is a complete unit. `"we chose X"` alone is not.
- Every CONTRADICTION, GOTCHA, OR CAVEAT observed during the conversation — these are often the highest-value knowledge and are the first thing a summarization reflex strips.
- The SOURCES cited by you or by the user — doc URLs, arxiv IDs, GitHub repos with star counts as-of the session, upstream announcements.

**For `conversation` captures, you MUST NOT include:**

- Pleasantries, meta-commentary, "let me check", "good question".
- Process over output: wrong turns, reasoning trail, "I thought X but then realized Y". Keep the resolution; drop the detour.
- The user's questions verbatim — they're context, not content. If a question led to a durable answer, capture the ANSWER.
- Ingestion logistics (orientation protocol results, decisions about `suggested_pages`) — those belong in the frontmatter, not the body.

### Red flags — STOP and expand the body

- Capture body under the floor for its evidence_type.
- Numbers rounded away or dropped ("roughly 20 req/min" when the source said exactly 20).
- A "see conversation for full context" or "the user can fill in specifics" phrase appears anywhere.

**All of these mean: expand the body before spawning the ingester.**

### After writing a capture

Immediately spawn a detached ingester (from the skill's base directory):

```bash
bash scripts/wiki-spawn-ingester.sh "<wiki_root>" "<capture_path>"
```

This returns in milliseconds. The spawner atomically claims the capture (renames `.md` → `.md.processing`) and then launches `claude -p` detached. You continue the user's task.

**Never wait for the ingester. Never read the capture back. Move on.**

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

### If the ingester rejects a capture (`needs_more_detail: true`)

On a later turn, you may notice a capture in `.wiki-pending/` whose frontmatter has `needs_more_detail: true`. That means an earlier ingester found the body too thin for its evidence_type and sent it back.

When you see this:

1. **Read the rejection reason** (`needs_more_detail_reason` in the frontmatter). It tells you how many bytes the body was and the floor for its type.
2. **Expand the body in place.** Remove the `needs_more_detail` and `needs_more_detail_reason` lines from the frontmatter. Add the missing durable claims, concrete details, decisions-with-rationale, and sources — following the "Capture body sufficiency" rules above.
3. **Re-spawn the ingester** on the expanded capture:
   ```bash
   bash scripts/wiki-spawn-ingester.sh "<wiki_root>" "<capture_path>"
   ```
4. **Do not ignore the rejection, even if the user is mid-question.** Rejections happen in milliseconds and expanding takes seconds. Ignoring a rejection means the knowledge is lost and the capture accumulates dust in `.wiki-pending/`.

"I'll come back to it later" is a forbidden rationalization here — same class as the rationalizations in the table below.

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

## Ingest — what the headless ingester does

The ingester's job: process one already-claimed capture into wiki pages. It runs with `WIKI_ROOT` and `WIKI_CAPTURE` env vars pointing at the `.md.processing` file.

### Ingester steps

1. **The capture is already claimed for you.** Read `${WIKI_CAPTURE}` (it's a `.md.processing` file). If for some reason `${WIKI_CAPTURE}` is unset or missing, call `wiki_capture_claim "${WIKI_ROOT}"` to grab any pending capture as fallback.

1a. **Body-sufficiency check — reject if too thin.** Measure the capture body size in bytes (the content AFTER the closing `---` of frontmatter). Apply the per-evidence-type floor:
   - `evidence_type: file` → 200 bytes
   - `evidence_type: mixed` → 1000 bytes
   - `evidence_type: conversation` → 1500 bytes

   If the body is BELOW its floor:
   - Add a top-level `needs_more_detail: true` line to the capture's frontmatter.
   - Add `needs_more_detail_reason: "body is <N> bytes; floor for evidence_type=<T> is <F> bytes — main agent must expand with concrete claims, numbers, URLs, and decisions before re-spawning"` to the frontmatter.
   - Rename the file from `.md.processing` back to `.md` so the next session-start drain picks it up after the main agent has expanded it.
   - Append a line to `log.md`: `## [<timestamp>] reject | <capture-basename> — body <N>b below <F>b floor`
   - Exit 0. Do NOT write wiki pages. Do NOT commit. The main agent will see the rejection on its next turn (the capture reappears in `.wiki-pending/` with `needs_more_detail: true`) and is expected to expand the body before anything else happens.

   A thin-capture rejection is a FEATURE, not a failure. It exists to stop low-quality captures from becoming low-quality wiki pages.

2. **Read the orientation files**: schema.md, index.md, last 10 entries of log.md.
3. **Read the capture body.**
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
   - **sha256 short-circuit.** If `raw/<basename>` already exists AND `sha256(new) == manifest[raw/<basename>].sha256`, the evidence content is identical — skip re-ingest of this capture and append `## [<timestamp>] skip | <capture-basename> — sha match, no-op` to `log.md`. Archive the capture normally (step 10). This prevents re-ingesting the same research file twice when the capture-trigger fires on a near-duplicate.
   - **Title-scope check.** Before merging into an existing wiki page in step 6, compare the new evidence's scope to the existing page's slug. Scope is the set of distinct entities (product names, versions, model names, concepts) the evidence covers. If the existing page's slug is NARROWER than the new evidence's scope (example: existing `concepts/gemma4-27b-hardware-requirements.md` vs new evidence covering a 27B+31B comparison), do NOT force-merge the broader content into the narrower-titled page. Instead, either (a) create a sibling concept page with a scope-appropriate slug (e.g. `concepts/gemma4-27b-vs-31b-hardware-comparison.md`) and cross-link both, or (b) rename the existing page's slug AND frontmatter title to cover the new scope, then merge — only if no other wiki page currently links to the old slug (if any do, use option (a) to avoid broken links). Log which option was taken in `log.md`.
   - **Overwrite-detection recovery.** If `raw/<basename>` already exists AND the new sha256 differs from the manifest entry AND the manifest's `last_ingested` is within the last 60 minutes (the evidence file on disk was replaced since the previous ingest), treat this as an overwrite situation: copy the new evidence to `raw/<basename>` AS NORMAL, but also append `## [<timestamp>] overwrite | <capture-basename> — raw sha changed since <previous_ingested_iso>, previous referenced_by: [<list>]` to `log.md`. Proceed with the rest of step 4 and the title-scope check in step 6 as above. The overwrite is not an error — it is the exact scenario from the failure-mode transcript (two research agents both wrote to `2026-04-24-gemma4-hardware.md`), and the title-scope check catches the content-divergence part.
5. **Decide target pages**: `suggested_pages` is a hint; orientation may change it.
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
7.6. **Index size threshold check.** After updating `index.md` in step 7, measure its byte size:
   ```bash
   size="$(wc -c < "${WIKI_ROOT}/index.md" | tr -d ' ')"
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
   Audit Finding 01 surfaced index.md at 25 KB / 76 entries / ~12,500 tokens; over 3x the 8 KB ceiling and ~12x the Chroma Context Rot inflection point. The thresholds existed in prose but had no firing mechanism; this step closes the loop.
8. **Append to `log.md`**.
9. **If this wiki is a project wiki, decide propagation.** A project wiki evaluates whether each capture is general-interest (useful across projects) or project-specific, using these criteria:
   - **Propagate** if the capture describes a tool, concept, pattern, or principle applicable outside this project. Write a new capture in the main wiki's `.wiki-pending/` with `propagated_from: <project wiki path>`.
   - **Keep local** if the capture uses project-specific names, references this codebase's architecture, or only applies here.
   - **When ambiguous, propagate** with a short pointer page — lower risk than missing knowledge.

   Main wiki ingestion is otherwise identical to project wiki ingestion.
10. **Archive the capture** from `.processing` to `.wiki-pending/archive/YYYY-MM/`: `wiki_capture_archive "${WIKI_ROOT}" "${WIKI_CAPTURE}"`. The helper strips the `.processing` suffix on rename, so archived basenames end in `.md`. Audit Finding 03 surfaced 4 legacy archive files still carrying `.md.processing` from older code paths; Phase D of v2.2 backfilled them.
11. **Call auto-commit** (from skill's base dir): `bash scripts/wiki-commit.sh "${WIKI_ROOT}" "ingest: <capture title>"`
12. **Exit.**

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
- `type` is one of `concept, entity, query`.
- Dates are full ISO-8601 UTC (`2026-04-24T13:00:00Z`, not `2026-04-24`).
- `sources:` is a flat list of strings (no nested mappings).
- Every `quality.*` field is present and in range.

If the validator exits non-zero for any page, fix the mechanical issue and re-validate. Do NOT commit a wiki state where the validator fails. The ingester MUST NOT call `wiki-commit.sh` (step 11) until every touched page passes the validator. Audit Finding 04 traced 7 broken links to this gate being permissive: ingester logs showed `ingest |` entries with no validator-failure follow-up, meaning the success log fired before the validator was consulted (or its failure was ignored). Wire the validator's exit code into the commit decision; do not paper over it with a log line.

If a contradiction surfaces, add `contradictions:` frontmatter pointing to the conflicting page — do NOT resolve it during ingest. (Contradictions are a judgement call, not a validator violation.)

Additionally: after running the validator, also run `wiki-lint-tags.py` (Phase B, Task 37) if it exists in the plugin. If it reports proposed new tags, drop a schema-proposal capture in `.wiki-pending/schema-proposals/` and continue — do NOT rename tags inline.

### Numeric thresholds (from schema.md)

- **Split a concept page** when it has material from 2+ sources OR exceeds 200 lines.
- **Archive a raw source** when it's referenced by 5+ wiki pages (move to `raw/archive/`, update references).
- **Restructure a top-level category** when it contains 500+ pages.
- **Split or atom-ize `index.md`** when it exceeds ~200 entries / 8KB / 2000 tokens — orientation degrades beyond that. Evidence: Chroma Context Rot research shows retrieval accuracy starts degrading around 1,000 tokens of preamble; Obsidian MOC practitioners cap at 25 items per MOC; Starmorph flags 100-200 pages as the scale-out point.

When a threshold is reached, propose the restructure via a `schema-proposal` capture in `.wiki-pending/schema-proposals/`. Do NOT restructure during the current ingest.

### Quality ratings — what the 4 dimensions mean

Every non-meta page (concept, entity, query) carries a `quality:` block in frontmatter. The block is maintained by the ingester at every ingest (step 6.5), re-rated by `wiki doctor` with a smarter model (post-MVP), and never clobbered once a human has rated.

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

## Query — how the agent uses the wiki

When the user asks a question that the wiki might answer:

1. Run the orientation protocol.
2. Read relevant pages identified from `index.md` and known cross-references.
3. Answer with citations: `[Jina Reader](concepts/jina-reader.md)`.
4. If the answer synthesizes across multiple pages in a new way → capture it as a query page to `queries/`.
5. If the wiki clearly does not cover the topic → answer from general knowledge, and note "wiki does not cover this."

Never invoke a separate "wiki query" command. The wiki is a tool, not a destination.

## Commands (minimal surface)

There are only two user commands:

- `wiki doctor` — deep lint + fix pass. Uses the smartest available model. Post-MVP placeholder in v1.
- `wiki status` — read-only health report.

Everything else is automatic. There is no `wiki init`, no `wiki ingest`, no `wiki query`, no `wiki flush`, no `wiki promote`.

## Rules you must not break

1. **Never write to the wiki in the foreground.** Every write goes through a detached ingester or `wiki doctor`.
2. **Never overwrite a page you haven't just read.** The read-before-write rule preserves user manual edits.
3. **Never skip a capture because it seems trivial in the moment.** If it meets the trigger criteria, capture it. Rationalizations like "the user will remember" or "it's too small" are forbidden.
4. **Never block the user on ingest.** Ingestion is asynchronous. If you find yourself waiting for an ingester, you are doing it wrong.
5. **Never modify files in `raw/`** once the ingester has copied them. They are immutable source of truth.
6. **Never answer a wiki-eligible question from training data without running orientation first.** If the user's question could plausibly be covered by the wiki, `ls` the cwd and walk up to check for a wiki before answering. Skipping orientation because "the question looks like general knowledge" is a forbidden rationalization — the whole point is that the wiki knows things your training data doesn't.
7. **Never set `.manifest.json` `origin` to `"file"`, `"mixed"`, the evidence type, the empty string, or a relative path.** `origin` is the source-of-truth pointer for the raw file; the capture's `evidence` field value. If `evidence` is an absolute path, `origin` is that path. If `evidence` is the literal string `"conversation"`, `origin` is the literal string `"conversation"`. There is no third option. Empty-origin (`""`) means the per-capture write of step 4 was skipped or failed; bail with a `## [...] reject |` log line rather than writing a manifest entry without provenance. The clove-oil regression (Audit fix 2) and the v2.2 copyparty/yazi empty-origin regression both trace to this distinction being fuzzy; now it is not. Run `python3 scripts/wiki-manifest.py validate "${WIKI_ROOT}"` to audit at any time.

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

## Read-before-write, in detail

Every wiki page edit follows:

1. Acquire the page's lock (`wiki_lock_wait_and_acquire "${WIKI_ROOT}" "<page-relative-path>" "<capture-id>" 30`).
2. Read the current content from disk.
3. Produce new content as a merge (additions, not replacements).
4. Write the merged content.
5. Release the lock (`wiki_lock_release "${WIKI_ROOT}" "<page-relative-path>"`).

If between steps 2 and 4 another process writes to the page, the lock acquisition would have failed in step 1 (atomic exclusive create). If the lock is held when we arrive, we wait (polling every 1s, 30s timeout) and re-read after acquiring.

## What goes in references/

Nothing for v1. The skill is a single file under the 500-line superpowers budget. If later iterations exceed the budget, split specific operations (ingest-detail, lint-detail) to `references/*.md`, flat (never nested).
