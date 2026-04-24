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

## YOU DO NOT HAVE A CHOICE

Load this skill on every conversation. Entry is non-negotiable. Entry is CHEAP — it just means you have these rules loaded; it does NOT mean you run the orientation protocol every turn.

- **Entry** happens once per session, automatic.
- **Orientation protocol** (read schema.md → index.md → last 10 of log.md) runs ONLY when you are about to (a) write a capture to `.wiki-pending/`, or (b) answer a question the wiki might cover.
- **Capture** is a few-hundred-byte file + a detached spawn. It takes milliseconds. Always do it when a trigger fires.

If new factual information surfaces in a conversation — even one that "looks casual" — you capture. The conversation about medical parasites is just as wiki-worthy as the conversation about API rate limits. Tone is not the trigger.

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

Every wiki-worthy moment becomes a small capture file. Each capture spawns a detached headless ingester that writes pages and commits. The user continues working — ingest never blocks.

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

A **capture** is a tiny markdown file noting that something happened which the wiki should absorb.

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

<one paragraph summary. if evidence_type=conversation, include enough
detail for the ingester to write a page without re-reading the transcript>
```

**Field contract:**
- `evidence`: the literal string `conversation` (when the capture came from in-session discussion with no file on disk) OR an absolute filesystem path to the source file. NEVER `file`, `mixed`, or a wiki-relative path.
- `evidence_type`: one of `file`, `conversation`, `mixed`. This is a TYPE descriptor only. The ingester does not record this in the manifest; it records `evidence` (as `origin`).
- `propagated_from` (previously `origin`): renamed to prevent confusion with the manifest's `origin` field. Value: absolute path to a project wiki root, or `null`.

### After writing a capture

Immediately spawn a detached ingester (from the skill's base directory):

```bash
bash scripts/wiki-spawn-ingester.sh "<wiki_root>" "<capture_path>"
```

This returns in milliseconds. The spawner atomically claims the capture (renames `.md` → `.md.processing`) and then launches `claude -p` detached. You continue the user's task.

**Never wait for the ingester. Never read the capture back. Move on.**

## Ingest — what the headless ingester does

When spawned, the ingester has a single job: process one already-claimed capture into wiki pages. The spawner hands the ingester the path to a `.processing` file (already claimed), and passes `WIKI_ROOT` and `WIKI_CAPTURE` env vars.

### Ingester steps

1. **The capture is already claimed for you.** Read `${WIKI_CAPTURE}` (it's a `.md.processing` file). If for some reason `${WIKI_CAPTURE}` is unset or missing, call `wiki_capture_claim "${WIKI_ROOT}"` to grab any pending capture as fallback.
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
   - After copying to raw/, create a `sources/<basename>.md` pointer page IF one does not already exist. Template in `references/source-pointer-template.md` (if present) or inline in the skill's base prose. Every raw file MUST have a matching sources/ pointer page — the validator now enforces this.
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
8. **Append to `log.md`**.
9. **If this wiki is a project wiki** and the capture is general-interest:
   write a new capture in the main wiki's `.wiki-pending/` with `propagated_from: <project wiki path>`.
10. **Archive the capture** from `.processing` to `.wiki-pending/archive/YYYY-MM/`: `wiki_capture_archive "${WIKI_ROOT}" "${WIKI_CAPTURE}"`.
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
- `type` is one of `concept, entity, source, query`.
- Dates are full ISO-8601 UTC (`2026-04-24T13:00:00Z`, not `2026-04-24`).
- `sources:` is a flat list of strings (no nested mappings).
- For `type: source` pages: a matching raw file exists at `raw/<basename>.*`.
- Every `quality.*` field is present and in range.

If the validator exits non-zero for any page, fix the mechanical issue and re-validate. Do NOT commit a wiki state where the validator fails.

If a contradiction surfaces, add `contradictions:` frontmatter pointing to the conflicting page — do NOT resolve it during ingest. (Contradictions are a judgement call, not a validator violation.)

Additionally: after running the validator, also run `wiki-lint-tags.py` (Phase B, Task 37) if it exists in the plugin. If it reports proposed new tags, drop a schema-proposal capture in `.wiki-pending/schema-proposals/` and continue — do NOT rename tags inline.

### Numeric thresholds (from schema.md)

- **Split a concept page** when it has material from 2+ sources OR exceeds 200 lines.
- **Archive a raw source** when it's referenced by 5+ wiki pages (move to `raw/archive/`, update references).
- **Restructure a top-level category** when it contains 500+ pages.

When a threshold is reached, propose the restructure via a `schema-proposal` capture in `.wiki-pending/schema-proposals/`. Do NOT restructure during the current ingest.

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
7. **Never set `.manifest.json` `origin` to `"file"`, `"mixed"`, or the evidence type.** `origin` is the source-of-truth pointer for the raw file — the capture's `evidence` field value. If `evidence` is an absolute path, `origin` is that path. If `evidence` is the literal string `"conversation"`, `origin` is the literal string `"conversation"`. There is no third option. The clove-oil regression (Audit fix 2) happened because this distinction was fuzzy; now it is not.

## Rationalizations to resist (red flags)

When you're about to skip a capture, check these red flags:

| Rationalization | Reality |
|---|---|
| "The user will remember this" | The user will not remember. That's the whole point. |
| "It's too trivial for the wiki" | If it meets the trigger criteria, capture it. Lint will filter noise later. |
| "I'll capture it later" | Later means never. Capture now. |
| "I'm in the middle of another task" | Capture is milliseconds. Do it. |
| "It's already covered" | Orientation protocol tells you if it is. Did you check? |
| "This is obvious from context" | Context evaporates. The wiki preserves it. |
| "The user didn't ask me to save this" | Capture triggers fire automatically — no explicit user request required. |
| "I don't have a memory tool available" | This skill IS the memory tool. Its presence is the trigger. |
| "The file is already in a good place" (filing ≠ capturing) | Location isn't organization. Capture extracts concepts, not just files. |
| "I'll answer from training data; the question doesn't look wiki-shaped" | Run orientation first. The wiki's scope is whatever has been captured — you can't know without checking. |
| "This doesn't look wiki-shaped / there's no code here / this isn't a wiki context" | Tone is not the trigger. If new factual info appeared — medical facts, historical facts, library docs, anything durable — capture. The parasite-research conversation is exactly as wiki-worthy as the API-rate-limit conversation. |
| "The user asked a casual question, research was just informational" | A research subagent returning a file with findings is itself a TRIGGER line in the description. It does not matter whether the user framed it casually. |
| "The skill's description is soft / passive, so I can skip" | The description now says "Load at the start of EVERY conversation. Entry is non-negotiable." Not loading the skill is not an option. |
| "The self-rating step is subjective, I'll skip it" | Ratings are mandatory. `ingester` is the default `rated_by`; leave rating accurate but lowball over missing. Every non-meta page needs a quality block — the validator will flag missing blocks. |
| "I'll give everything 5s to be safe" | 5 is exceptional. Lowballing a page to 3 flags it for `wiki doctor` review later, which is the right outcome. False 5s silently bake errors — the exact failure mode we're guarding against. |
| "I'll rewrite a human-rated page's quality because I just touched it" | Forbidden. `rated_by: human` is sacred. Touch only the body; leave the quality block alone. |

All of these are violations of the Iron Law.

## What changes between main and project wikis

The only behavioral difference: during ingest, a project wiki evaluates whether each capture is general-interest (useful across projects) or project-specific. General-interest captures are propagated to the main wiki's `.wiki-pending/` with an `origin` marker. Main wiki ingestion is otherwise identical.

Criteria for propagation:
- **Propagate** if the capture describes a tool, concept, pattern, or principle applicable outside this project.
- **Keep local** if it uses project-specific names, references this codebase's architecture, or only applies here.
- **When ambiguous, propagate** with a short pointer page — lower risk than missing knowledge.

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
