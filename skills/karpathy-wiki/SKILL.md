---
name: karpathy-wiki
description: Use when a session produces durable knowledge a future-you would search for — a research finding, resolved confusion, validated pattern, gotcha, or documented decision; when a research subagent returns a file; when the user pastes a URL or document to study; when `raw/` has unprocessed files; when the user says "add to wiki" / "remember this" / "wiki it" / "save this"; when the user asks "what do we know about X", "how do we handle Y", "what did we decide about Z", "have we seen this before". Do NOT use for routine lookups, obvious code edits, questions clearly outside the wiki's scope, or time-sensitive data that should be fetched fresh.
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

## Iron laws

```
NO WIKI WRITE IN THE FOREGROUND
```

```
NO PAGE EDIT WITHOUT READING THE PAGE FIRST
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

Run the init script (script paths below resolve via `$CLAUDE_PLUGIN_ROOT`, which Claude Code sets to the plugin's root directory):

```bash
# For main wiki:
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wiki-init.sh" main "$HOME/wiki"
# For project wiki:
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wiki-init.sh" project "./wiki" "$HOME/wiki"
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

### After writing a capture

Immediately spawn a detached ingester:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wiki-spawn-ingester.sh" "<wiki_root>" "<capture_path>"
```

This returns in milliseconds. The spawner atomically claims the capture (renames `.md` → `.md.processing`) and then launches `claude -p` detached. You continue the user's task.

**Never wait for the ingester. Never read the capture back. Move on.**

## Ingest — what the headless ingester does

When spawned, the ingester has a single job: process one already-claimed capture into wiki pages. The spawner hands the ingester the path to a `.processing` file (already claimed), and passes `WIKI_ROOT` and `WIKI_CAPTURE` env vars.

### Ingester steps

1. **The capture is already claimed for you.** Read `${WIKI_CAPTURE}` (it's a `.md.processing` file). If for some reason `${WIKI_CAPTURE}` is unset or missing, call `wiki_capture_claim "${WIKI_ROOT}"` to grab any pending capture as fallback.
2. **Read the orientation files**: schema.md, index.md, last 10 entries of log.md.
3. **Read the capture body.**
4. **If evidence_type=file**, copy the evidence into `<wiki>/raw/` preserving basename. Update `.manifest.json`.
5. **Decide target pages**: `suggested_pages` is a hint; orientation may change it.
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
11. **Call auto-commit**: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/wiki-commit.sh" "${WIKI_ROOT}" "ingest: <capture title>"`
12. **Exit.**

### Tier-1 lint at ingest (inline)

Before exiting, check the pages you just touched:

- Every markdown link resolves (file exists).
- Every YAML frontmatter field is valid (dates parseable, required fields present).
- `index.md` has an entry for every new page.

Fix mechanical issues silently. If a contradiction surfaces, add `contradictions:` frontmatter pointing to the conflicting page — do NOT resolve it during ingest.

### Numeric thresholds (from schema.md)

- **Split a concept page** when it has material from 2+ sources OR exceeds 200 lines.
- **Archive a raw source** when it's referenced by 5+ wiki pages (move to `raw/archive/`, update references).
- **Restructure a top-level category** when it contains 500+ pages.

When a threshold is reached, propose the restructure via a `schema-proposal` capture in `.wiki-pending/schema-proposals/`. Do NOT restructure during the current ingest.

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
