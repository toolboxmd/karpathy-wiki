# karpathy-wiki v2.4 — Leg 1: Auto-load + skill split

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Force-load a thin loader skill into every conversation via the SessionStart hook, mirroring the `superpowers:using-superpowers` pattern. Split the monolithic `karpathy-wiki/SKILL.md` into three skills (`using-karpathy-wiki`, `karpathy-wiki-capture`, `karpathy-wiki-ingest`) with a single canonical home for each rule.

**Architecture:** A new `using-karpathy-wiki` skill becomes the always-loaded loader. The hook reads it and emits `hookSpecificOutput.additionalContext` wrapped in `<EXTREMELY_IMPORTANT>` tags. The loader points at the on-demand `karpathy-wiki-capture` skill (for the main agent) and `karpathy-wiki-ingest` skill (loaded only by spawned ingesters via the spawn prompt). The old `skills/karpathy-wiki/SKILL.md` is kept in place during the transition; its description is updated to point at the new skills. Removal is a separate cleanup commit after v2.4 ships.

**Tech Stack:** bash hooks, markdown skill files with YAML frontmatter, JSON Schema-ish `hookSpecificOutput.additionalContext` API.

**Spec reference:** `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/docs/superpowers/specs/2026-05-05-karpathy-wiki-v2.4-executable-protocol-design.md` (Leg 1 — Skill auto-load via session-start injection; lines ~146-289 and the skill rule ownership table at ~2105).

**Inter-leg dependency:** Leg 2 and Leg 3 plans depend on this leg's loader and skill split being in place. Reverting Leg 1 requires Legs 2 and 3 to already be reverted.

**Verification gate:** After this plan ships, the following must hold:
- Fresh agent session in any directory emits the `using-karpathy-wiki` body in `additionalContext` wrapped in `<EXTREMELY_IMPORTANT>` tags.
- Spawned ingester (`WIKI_CAPTURE` set) receives no `additionalContext` from the hook.
- Subagent dispatch (`CLAUDE_AGENT_PARENT` set) receives no `additionalContext` from the hook.
- Old `skills/karpathy-wiki/SKILL.md` still loads when invoked by name (description updated to redirect; body unchanged).

---

## File structure

| File | Action | Purpose |
|---|---|---|
| `skills/using-karpathy-wiki/SKILL.md` | Create | Force-loaded loader: triggers, iron laws, announce-line contract, pointers to capture/ingest skills, `<SUBAGENT-STOP>` block. ~80 lines max. |
| `skills/karpathy-wiki-capture/SKILL.md` | Create | For main agent on-demand: trigger detection, capture file format, body floors per `capture_kind`, spawn command, `wiki use` directive, subagent-report workflow. |
| `skills/karpathy-wiki-capture/references/capture-schema.md` | Create | Canonical capture frontmatter contract: `capture_kind` enum, body floors per kind, `evidence` rules, legacy backward-compat. |
| `skills/karpathy-wiki-ingest/SKILL.md` | Create | For spawned ingester only: orientation, deep orientation (Leg 4), page format, role guardrail, validator, manifest, commit, issue reporting (Leg 4). |
| `skills/karpathy-wiki-ingest/references/page-conventions.md` | Create | Cross-link convention (wiki-relative leading `/`), frontmatter standards, quality block format. |
| `skills/karpathy-wiki/SKILL.md` | Modify (description only) | Redirect description to point at the new skills. Body unchanged. |
| `hooks/session-start` | Modify | Add steps 1-2 (subagent guard + loader injection) before the existing drift/drain logic. |
| `tests/unit/test-using-karpathy-wiki-loader.sh` | Create | Loader file exists, has `<SUBAGENT-STOP>` block at top, has pointers to capture and ingest skills, frontmatter matches spec. |
| `tests/unit/test-session-start-loader-injection.sh` | Create | Hook emits valid JSON with `additionalContext` containing the loader body wrapped in `<EXTREMELY_IMPORTANT>`. Three guards: WIKI_CAPTURE set, CLAUDE_AGENT_PARENT set, no-wiki cwd. |
| `tests/unit/test-skill-split-no-overlap.sh` | Create | Capture and ingest skills do not contain >80 contiguous-word substring overlap (drift prevention). |
| `tests/integration/test-leg1-end-to-end.sh` | Create | Run hook with controlled env: assert loader present in normal session, absent in subagent/ingester contexts. |
| `tests/red/RED-leg1-no-loader.md` | Create | RED scenario showing an agent failing to invoke karpathy-wiki rules without the loader, demonstrating the change is needed. |

---

### Task 1: RED scenario — agent fails without loader

**Files:**
- Create: `tests/red/RED-leg1-no-loader.md`

- [ ] **Step 1: Document the RED scenario**

Per CLAUDE.md, every SKILL.md change must be preceded by a pressure scenario showing an agent failing without the change. This file is that record for Leg 1's loader injection.

Write this file:

````markdown
# RED scenario — agent skips wiki capture without forced loader

**Date:** 2026-05-06
**Skill change this justifies:** v2.4 Leg 1 — `using-karpathy-wiki` loader force-loaded via SessionStart hook.

## The scenario

A user starts a fresh Claude Code session in `~/dev/myproject/`. The wiki at `~/wiki/` is configured but the agent has never been told to use it (the `karpathy-wiki` skill is in the plugin's skill list but not auto-invoked).

User asks: *"What's the difference between USB 3.0, 3.1, and 3.2? I keep getting confused by the version-rename."*

Expected behavior post-Leg 1: the agent has the loader's trigger taxonomy in context. When it answers, it recognizes "version-rename mapping" as a wiki-worthy durable trigger and writes a capture before stopping the turn.

Observed behavior pre-Leg 1: agent answers correctly but does not capture. The `karpathy-wiki` skill description is in the system reminder, but the agent reads "TRIGGER when..." prose only if it chooses to invoke the skill — and a casual-shaped question like this does not pattern-match the agent's heuristic for "should I read this skill body in full." Capture is missed; durable knowledge is lost.

## Why prose alone doesn't fix this

The current `skills/karpathy-wiki/SKILL.md` already says *"YOU DO NOT HAVE A CHOICE — load this skill on every conversation"*. That sentence sits inside the skill body. The agent only reads the skill body if it invokes the skill. The instruction is unreachable from outside the skill.

The fix is structural: the SessionStart hook injects the loader into `additionalContext` so the rules are present in every conversation regardless of agent judgment. The `superpowers:using-superpowers` skill is the canonical reference for this pattern.

## Pass criterion

After Leg 1 ships, a fresh session in any directory shows the loader body inside `<EXTREMELY_IMPORTANT>` tags as part of the conversation context. Tests/integration/test-leg1-end-to-end.sh verifies this mechanically.
````

- [ ] **Step 2: Commit**

```bash
git add tests/red/RED-leg1-no-loader.md
git commit -m "test(red): RED scenario for v2.4 Leg 1 loader force-load"
```

---

### Task 2: Failing test — `using-karpathy-wiki/SKILL.md` exists with required structure

**Files:**
- Create: `tests/unit/test-using-karpathy-wiki-loader.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/bin/bash
# Verify the using-karpathy-wiki loader skill exists and has the required structure.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOADER="${REPO_ROOT}/skills/using-karpathy-wiki/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "${LOADER}" ]] || fail "loader file missing: ${LOADER}"

# Frontmatter has name, description, and is short
head -20 "${LOADER}" | grep -q '^name: using-karpathy-wiki' || fail "frontmatter missing name"
head -20 "${LOADER}" | grep -q '^description:' || fail "frontmatter missing description"

# <SUBAGENT-STOP> block at the top of the body (after the second `---`)
# Find the second `---` (end of frontmatter), then check the next 30 lines.
awk '/^---/ {n++; if (n==2) {flag=1; next}} flag && n==2 {print}' "${LOADER}" | head -30 \
  | grep -q '<SUBAGENT-STOP>' || fail "missing <SUBAGENT-STOP> block near top of body"

# Pointers to the two on-demand skills
grep -q 'karpathy-wiki-capture' "${LOADER}" || fail "no pointer to karpathy-wiki-capture"
grep -q 'karpathy-wiki-ingest' "${LOADER}" || fail "no pointer to karpathy-wiki-ingest"

# Iron laws and announce-line contract carried forward
grep -q 'NO WIKI WRITE IN THE FOREGROUND' "${LOADER}" || fail "missing iron law: foreground"
grep -q 'announce' "${LOADER}" || fail "missing announce-line contract"

# Trigger taxonomy
grep -q 'TRIGGER' "${LOADER}" || fail "missing trigger taxonomy"

# Body length sanity (not a 500-line monster — this is the loader)
lines=$(wc -l < "${LOADER}")
if [[ "${lines}" -gt 200 ]]; then
  fail "loader is ${lines} lines; should be ≤ 200 (this is the loader, not the full body)"
fi

echo "PASS: using-karpathy-wiki loader structure"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/unit/test-using-karpathy-wiki-loader.sh`
Expected: FAIL with "loader file missing: .../skills/using-karpathy-wiki/SKILL.md"

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test-using-karpathy-wiki-loader.sh
git commit -m "test(unit): add failing test for using-karpathy-wiki loader structure"
```

---

### Task 3: Implement `using-karpathy-wiki/SKILL.md`

**Files:**
- Create: `skills/using-karpathy-wiki/SKILL.md`

- [ ] **Step 1: Write the loader skill**

This is the skill that the SessionStart hook will force-load. Mirrors `superpowers:using-superpowers` shape. Keep ≤ 200 lines.

```markdown
---
name: using-karpathy-wiki
description: |
  Auto-loaded into every conversation by the karpathy-wiki SessionStart hook. This is the loader — it tells the agent WHEN to capture and points at the full operational skills (`karpathy-wiki-capture` for authoring, `karpathy-wiki-ingest` for the spawned ingester). Read this preamble; load the on-demand skills only when their moment arrives.
---

<SUBAGENT-STOP>
If you were dispatched as a subagent for a task unrelated to wiki capture or ingest, skip this skill. The wiki rules apply to the main agent in the conversation; subagents doing isolated work (Explore, code-reviewer, codex:rescue, etc.) do not need to capture.
</SUBAGENT-STOP>

# karpathy-wiki — loader (read once per session, applies for the whole session)

You are operating in a project that uses the karpathy-wiki plugin. Durable knowledge surfaced in this conversation must be captured to a wiki so future sessions can find it.

## Announce when you act

When you write a capture, run an ingest, or answer from the wiki, prefix your reply with one line:

> **Using the karpathy-wiki skill to [capture this / ingest pending captures / answer from wiki].**

This is the ONLY wiki-mechanics text the user sees. Do not narrate orientation, capture authoring, spawn mechanics, or state-machine progress. Do all the wiki work silently after the announce line.

## Iron laws

```
NO WIKI WRITE IN THE FOREGROUND
NO PAGE EDIT WITHOUT READING THE PAGE FIRST
NO SKIPPING A CAPTURE BECAUSE "IT DOESN'T LOOK WIKI-SHAPED"
```

Captures go to `<wiki>/.wiki-pending/<timestamp>-<slug>.md`. A detached `claude -p` ingester reads the capture and writes the wiki page in the background.

## TRIGGER — when to capture

Write a capture when ANY of these fire (immediate-capture triggers):

- A research subagent or research agent completes or returns a file with durable findings.
- New factual information is found (web search, doc fetch, external fact surfaced in conversation).
- Session resolves a confusion — something neither of you knew before.
- A gotcha, quirk, or non-obvious behavior in a tool is discovered.
- A pattern is validated (approaches compared, one picked, with reasons).
- An architectural decision is made with explicit rationale.
- User pastes a URL or document for study.
- `<wiki>/inbox/` or `<wiki>/raw/` has unprocessed files.
- User says "add to wiki" / "remember this" / "wiki it" / "save this".
- Two claims contradict each other.

Also TRIGGER (orientation + citation): the user asks "what do we know about X" / "how do we handle Y" / "what did we decide about Z" / "have we seen this before" — or any question the wiki might cover.

## SKIP — when not to capture

- Routine file edits, syntax lookups, one-off debugging with trivial root causes.
- Time-sensitive data that must be fetched fresh.
- Questions clearly outside any wiki's scope.

Do NOT skip based on tone or shape. "This looks like casual chat", "there's no code here", "this isn't a wiki context" are forbidden rationalizations. If new factual information appeared, capture. Tone is not the trigger.

## What to do when a trigger fires

For chat-driven captures (the conversation IS the source, or you have a file alongside the conversation): load `karpathy-wiki-capture/SKILL.md` and follow it. The capture is written via `bin/wiki capture` (a subcommand of the existing `bin/wiki` CLI).

For research subagent reports (a file is the source): the agent's job is one command, NOT a hand-written capture body:

```bash
mv <subagent-report-path> <wiki>/inbox/<basename>
wiki ingest-now <wiki>          # or wait for next SessionStart
```

For "what does the wiki know about X" questions: load `karpathy-wiki-capture/SKILL.md` and read its orientation section. Do NOT load `karpathy-wiki-ingest/SKILL.md` (that's for the spawned ingester only).

## Mode change

If the user asks to change the wiki mode for this directory (phrases like "use project wiki here," "main only," "switch to both," "fork to main"), run:

```bash
wiki use project|main|both
```

Confirm the change in one line; do not over-narrate.

## What's NOT in this loader

The full operational details — capture format, body-size floors, spawn mechanics, ingester orientation, page format, manifest protocol, commit conventions — live in the on-demand skills:

- `skills/karpathy-wiki-capture/SKILL.md` — load when you are about to write a capture.
- `skills/karpathy-wiki-ingest/SKILL.md` — loaded by the spawned ingester via its prompt; the main agent never reads this.

If you do not know what to do at a particular step, load the on-demand skill — do not invent.
```

- [ ] **Step 2: Run test to verify it passes**

Run: `bash tests/unit/test-using-karpathy-wiki-loader.sh`
Expected: PASS

- [ ] **Step 3: Commit**

```bash
git add skills/using-karpathy-wiki/SKILL.md
git commit -m "feat(skills): add using-karpathy-wiki loader skill"
```

---

### Task 4: Failing test — `karpathy-wiki-capture/SKILL.md` exists with required content

**Files:**
- Create: `tests/unit/test-capture-skill.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/bin/bash
# Verify karpathy-wiki-capture skill structure.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SKILL="${REPO_ROOT}/skills/karpathy-wiki-capture/SKILL.md"
SCHEMA_REF="${REPO_ROOT}/skills/karpathy-wiki-capture/references/capture-schema.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "${SKILL}" ]] || fail "skill file missing: ${SKILL}"
[[ -f "${SCHEMA_REF}" ]] || fail "reference file missing: ${SCHEMA_REF}"

# Frontmatter
head -10 "${SKILL}" | grep -q '^name: karpathy-wiki-capture' || fail "frontmatter missing name"
head -10 "${SKILL}" | grep -q '^description:' || fail "frontmatter missing description"

# Required sections
grep -q '^## Trigger' "${SKILL}" || fail "missing 'Trigger' section"
grep -q '^## Capture file format' "${SKILL}" || fail "missing 'Capture file format' section"
grep -q '^## Body sufficiency' "${SKILL}" || fail "missing 'Body sufficiency' section"
grep -q 'bin/wiki capture' "${SKILL}" || fail "no reference to bin/wiki capture (canonical entry point)"

# Subagent-report workflow guidance
grep -qi 'subagent report' "${SKILL}" || fail "missing subagent-report workflow"
grep -q 'wiki ingest-now' "${SKILL}" || fail "no reference to wiki ingest-now"

# Pointer to schema reference
grep -q 'capture-schema.md' "${SKILL}" || fail "no pointer to references/capture-schema.md"

# capture-schema.md content
grep -q 'capture_kind' "${SCHEMA_REF}" || fail "schema ref missing capture_kind enum"
grep -q 'raw-direct' "${SCHEMA_REF}" || fail "schema ref missing raw-direct kind"
grep -q 'chat-attached' "${SCHEMA_REF}" || fail "schema ref missing chat-attached kind"
grep -q 'chat-only' "${SCHEMA_REF}" || fail "schema ref missing chat-only kind"

# Iron laws not duplicated here (single source of truth is the loader)
if grep -q 'NO WIKI WRITE IN THE FOREGROUND' "${SKILL}"; then
  fail "iron law duplicated in capture skill (single source: using-karpathy-wiki/SKILL.md)"
fi

echo "PASS: karpathy-wiki-capture skill structure"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/unit/test-capture-skill.sh`
Expected: FAIL with "skill file missing"

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test-capture-skill.sh
git commit -m "test(unit): add failing test for karpathy-wiki-capture skill"
```

---

### Task 5: Implement `karpathy-wiki-capture/SKILL.md` and its `references/capture-schema.md`

**Files:**
- Create: `skills/karpathy-wiki-capture/SKILL.md`
- Create: `skills/karpathy-wiki-capture/references/capture-schema.md`

- [ ] **Step 1: Write the schema reference first (other tasks will cite it)**

Create `skills/karpathy-wiki-capture/references/capture-schema.md`:

````markdown
# Capture frontmatter schema (canonical)

This is the single source of truth for capture file format. Both the
`karpathy-wiki-capture` skill (main agent) and the
`karpathy-wiki-ingest` skill (spawned ingester) reference this file.
Do not duplicate the contents in the skill bodies.

## File location

Captures live at `<wiki>/.wiki-pending/<timestamp>-<slug>.md` where
`<timestamp>` is `YYYY-MM-DDTHH-MM-SSZ` (UTC, hyphens not colons in
the time portion to keep the filename POSIX-friendly).

## Frontmatter fields

```yaml
---
title: "<one-line title>"
evidence: "<absolute path OR the literal string conversation>"
evidence_type: "file" | "mixed" | "conversation"
capture_kind: "raw-direct" | "chat-attached" | "chat-only"
suggested_action: "create" | "update" | "augment" | "auto"
suggested_pages:
  - concepts/<slug>.md
captured_at: "<ISO-8601 UTC timestamp>"
captured_by: "<source identifier>"
propagated_from: null  # absolute path to project wiki root, or null
---
```

## `capture_kind` enum (canonical)

| `capture_kind` | `evidence_type` | Body floor | Body source |
|---|---|---|---|
| `raw-direct` | `file` | none | hook-generated boilerplate |
| `chat-attached` | `mixed` | 1000 b | main agent writes (the conversation-delta) |
| `chat-only` | `conversation` | 1500 b | main agent writes (the conversation IS the evidence) |

Body bytes are measured AFTER the closing `---` of frontmatter. Captures
under their floor are rejected by the ingester with `needs-more-detail: true`.

## Backward-compat for legacy captures (no `capture_kind` field)

Pre-v2.4 captures that lack `capture_kind` are mapped at ingest-time, in
priority order:

1. **Legacy drift override.** If `captured_by == "session-start-drift"` OR
   the title starts with `Drift:` → `capture_kind = raw-direct`. These
   are existing v2.x drift captures; they always meant raw-direct
   semantically.
2. **Path evidence.** If rule 1 doesn't match AND `evidence` is a
   filesystem path (starts with `/` or `~`) → `capture_kind = chat-attached`.
3. **Conversation evidence.** If `evidence == "conversation"` →
   `capture_kind = chat-only`.

The validator enforces `capture_kind` presence on new captures written
by v2.4-and-later code; legacy captures pass through these rules.

## `evidence` field

- For `capture_kind: raw-direct` and `chat-attached` → absolute path to
  the file on disk. NEVER the string `"file"`, `"mixed"`, or a
  wiki-relative path.
- For `capture_kind: chat-only` → the literal string `conversation`.

## `propagated_from`

- `null` for original captures.
- Absolute path to the originating wiki root if the capture was
  propagated from another wiki (post-v2.4 cross-wiki workflow; not used
  in v2.4 itself but reserved).

## Filename slug

Slug is lowercased title with non-alphanumerics replaced by `-`,
collapsed, and trimmed. Generated by `scripts/wiki-lib.sh`'s `slugify`
function. Capture base length capped at 200 chars before adding `.md`.
````

- [ ] **Step 2: Write the capture skill body**

Create `skills/karpathy-wiki-capture/SKILL.md`:

````markdown
---
name: karpathy-wiki-capture
description: |
  Capture-authoring protocol for the main agent. Read on demand when a TRIGGER fires (per `using-karpathy-wiki/SKILL.md`). Defines how to format a capture, how to invoke `bin/wiki capture`, body-size floors, and the subagent-report workflow.
---

# karpathy-wiki capture

You loaded this skill because a TRIGGER fired (per the loader). Your job
is to write a capture file (or move a file into `inbox/` for raw-direct
ingest), then return to the user's task.

## Single capture entry point

All chat-driven captures go through ONE command:

```bash
echo "$BODY" | bin/wiki capture \
  --title "<one-line title>" \
  --kind chat-only|chat-attached \
  --suggested-action create|update|augment
```

Or for long bodies:

```bash
bin/wiki capture \
  --title "<one-line title>" \
  --kind chat-only \
  --suggested-action create \
  --body-file /tmp/body.md
```

`bin/wiki capture` handles wiki resolution (which wiki the capture goes
to), prompts the user for setup if needed, writes the capture file,
and spawns the detached ingester. You do NOT write to
`.wiki-pending/` directly. You do NOT call `wiki-spawn-ingester.sh`
directly.

## Trigger

Triggers are listed in the loader (`using-karpathy-wiki/SKILL.md`).
This skill assumes a trigger has fired and you're now writing.

## Capture file format

See `references/capture-schema.md` for the canonical frontmatter
schema. Key fields you set when invoking `bin/wiki capture`:

- `--title`: one-line title (becomes filename slug + capture title).
- `--kind`: `chat-only` (no file evidence) | `chat-attached` (file +
  conversation delta) | `raw-direct` (you do NOT write this; it's for
  drop-zone ingestion).
- `--suggested-action`: `create` (new page) | `update` (replace
  existing) | `augment` (add to existing).

The body is read from stdin OR `--body-file <path>`.

## Body sufficiency

Per `references/capture-schema.md`:

| Kind | Floor | What goes in the body |
|---|---|---|
| `chat-only` | 1500 b | Every durable claim, exact details (URLs, version numbers, error messages), every decision-with-rationale, every gotcha, sources cited. |
| `chat-attached` | 1000 b | The conversation-delta — what the conversation added that the file doesn't cover. The file is the bulk; you owe the delta in full. |
| `raw-direct` | none | You don't write raw-direct bodies. The SessionStart hook or `wiki ingest-now` auto-generates them when a file appears in `inbox/`. |

If the ingester rejects your capture (`needs-more-detail: true`),
expand the body in place and re-spawn. Do NOT ignore the rejection.

## Subagent reports — DO NOT write a capture body

When a research subagent returns a file with durable findings, the
report IS the capture. Move the file to `<wiki>/inbox/`:

```bash
mv <subagent-report-path> <wiki>/inbox/<basename>
wiki ingest-now <wiki>          # or wait for next SessionStart
```

`wiki ingest-now` triggers the same drift-scan + drain that
SessionStart runs, but on demand. Use this when the user is still in
the active session and wants the report ingested before they close
the terminal.

Subagent-report bodies frequently exceed several KB; rewriting them
as a `chat-only` capture body wastes tokens AND produces an inferior
wiki page (the body summarizes what the file already says).

## Body sufficiency — what to put in `chat-only` captures

A `chat-only` capture body must clear the 1500-byte floor with content,
not filler. Required:

- Every durable CLAIM — fact, number, version, commit, percentage, decision.
- Every CONCRETE DETAIL the ingester cannot guess — exact URLs, package names, error messages, command snippets, code examples (5-15 lines), numeric thresholds, version ranges.
- Every DECISION made WITH its rationale — *"we chose X because Y failed on Z"* is a complete unit. *"we chose X"* alone is not.
- Every CONTRADICTION, GOTCHA, OR CAVEAT observed.
- SOURCES — doc URLs, arxiv IDs, GitHub repos with star counts as-of the session.

NOT in the body:
- Pleasantries, meta-commentary, "let me check", "good question".
- Process over output: wrong turns, reasoning trail, "I thought X but then Y". Keep the resolution; drop the detour.
- The user's questions verbatim — they're context, not content. Capture the ANSWER, not the question.

## Mode change

If the user asks to change the wiki mode for this directory:

```bash
wiki use project    # captures go to ./wiki/ only
wiki use main       # captures go to ~/wiki/ only
wiki use both       # captures fork to ./wiki/ AND ~/wiki/
```

Confirm in one line. The mode is persisted in `<cwd>/.wiki-config`
(project or both) or `<cwd>/.wiki-mode` (main-only). See
`references/capture-schema.md` and the v2.4 spec for details.

## Order matters: reply first, then capture

Reply to the user FIRST. The user is waiting; capture mechanics are
not. After your reply emits, write any captures whose triggers fired
(via `bin/wiki capture`), then run a turn-closure check.

## Turn closure — before you stop

Before emitting your final assistant message, check:

```bash
ls "<wiki_root>/.wiki-pending/" 2>/dev/null | grep -v '^archive$\|^schema-proposals$' | head -20
```

If the output lists any `.md` file OR any `.md.processing` file older
than 10 minutes, the turn is NOT done. Handle the pending captures
first (rejection-handling, stalled-recovery, missed-capture from
earlier turns), then re-check, then close the turn.

This is a self-discipline rule until a Stop-hook gate is wired.

## What's NOT in this skill

- The ingester's behavior (orientation, page format, manifest
  protocol). That lives in `karpathy-wiki-ingest/SKILL.md` and is
  loaded by the spawned ingester only. The main agent never reads it.
- Iron laws and announce-line contract. Those live in the loader
  (`using-karpathy-wiki/SKILL.md`) — single source of truth.
````

- [ ] **Step 3: Run tests to verify they pass**

Run: `bash tests/unit/test-capture-skill.sh`
Expected: PASS

Run: `bash tests/unit/test-using-karpathy-wiki-loader.sh`
Expected: still PASS (Task 3 result holds)

- [ ] **Step 4: Commit**

```bash
git add skills/karpathy-wiki-capture/SKILL.md skills/karpathy-wiki-capture/references/capture-schema.md
git commit -m "feat(skills): add karpathy-wiki-capture skill + capture-schema reference"
```

---

### Task 6: Failing test — `karpathy-wiki-ingest/SKILL.md` exists with required content

**Files:**
- Create: `tests/unit/test-ingest-skill.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/bin/bash
# Verify karpathy-wiki-ingest skill structure.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SKILL="${REPO_ROOT}/skills/karpathy-wiki-ingest/SKILL.md"
PAGE_REF="${REPO_ROOT}/skills/karpathy-wiki-ingest/references/page-conventions.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "${SKILL}" ]] || fail "skill file missing: ${SKILL}"
[[ -f "${PAGE_REF}" ]] || fail "page-conventions file missing: ${PAGE_REF}"

head -10 "${SKILL}" | grep -q '^name: karpathy-wiki-ingest' || fail "frontmatter missing name"
head -10 "${SKILL}" | grep -q '^description:' || fail "frontmatter missing description"

# Required sections — orientation, page format, manifest, commit
grep -q -i '^## Orientation' "${SKILL}" || fail "missing Orientation section"
grep -q -i 'manifest' "${SKILL}" || fail "missing manifest section"
grep -q -i 'commit' "${SKILL}" || fail "missing commit section"

# Role guardrail (project / main lens)
grep -q -i 'role' "${SKILL}" || fail "missing role guardrail"
grep -qi 'project\|main' "${SKILL}" || fail "missing project/main lens guidance"

# Pointer to capture-schema (shared contract)
grep -q 'capture-schema.md' "${SKILL}" || fail "no pointer to capture-schema.md"

# page-conventions.md content
grep -q -i 'cross-link' "${PAGE_REF}" || fail "page-conventions missing cross-link convention"
grep -q -i 'frontmatter' "${PAGE_REF}" || fail "page-conventions missing frontmatter section"

# No iron-law duplication
if grep -q 'NO WIKI WRITE IN THE FOREGROUND' "${SKILL}"; then
  fail "iron law duplicated in ingest skill (single source: using-karpathy-wiki/SKILL.md)"
fi

# No announce-line duplication
if grep -q -i 'announce' "${SKILL}"; then
  fail "announce-line contract duplicated in ingest skill (single source: using-karpathy-wiki/SKILL.md)"
fi

echo "PASS: karpathy-wiki-ingest skill structure"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/unit/test-ingest-skill.sh`
Expected: FAIL with "skill file missing"

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test-ingest-skill.sh
git commit -m "test(unit): add failing test for karpathy-wiki-ingest skill"
```

---

### Task 7: Implement `karpathy-wiki-ingest/SKILL.md` and `references/page-conventions.md`

**Files:**
- Create: `skills/karpathy-wiki-ingest/SKILL.md`
- Create: `skills/karpathy-wiki-ingest/references/page-conventions.md`

The body of `karpathy-wiki-ingest/SKILL.md` is the operational ingester body — the bulk of what's in today's `skills/karpathy-wiki/SKILL.md` (lines ~275-470). For Leg 1 we extract it as-is; Leg 4 (deep orientation + issue reporting) modifies it further.

- [ ] **Step 1: Write `references/page-conventions.md`**

Create `skills/karpathy-wiki-ingest/references/page-conventions.md`:

````markdown
# Wiki page conventions (canonical)

Single source of truth for page format. The ingester writes pages following these conventions; the validator (`scripts/wiki-validate-page.py`) enforces them.

## Frontmatter

```yaml
---
title: "<page title>"
type: <category>           # plural form: concepts, entities, queries, ideas, projects, ...
tags: [tag1, tag2, ...]
sources:
  - raw/<basename>         # OR the literal string "conversation"
related:
  - /concepts/<slug>.md    # leading-slash, wiki-root-relative
created: "<ISO-8601 UTC>"
updated: "<ISO-8601 UTC>"
quality:
  accuracy: 1-5
  completeness: 1-5
  signal: 1-5
  interlinking: 1-5
  overall: <average>
  rated_at: "<ISO-8601 UTC>"
  rated_by: ingester       # OR "human" — human is sticky, ingester must not overwrite
---
```

## Cross-link convention

All cross-links in the page body and the `related:` frontmatter use
**wiki-root-relative paths with a leading `/`**:

- ✅ `[Auth flow](/concepts/auth-flow.md)`
- ✅ `related: [/concepts/auth-flow.md]`
- ❌ `[Auth flow](concepts/auth-flow.md)` (relative; breaks when read from a nested page)
- ❌ `[Auth flow](../concepts/auth-flow.md)` (relative; breaks when page moves)

## Quality block — never overwrite human ratings

If `rated_by: human`, the ingester MUST NOT change any quality field.
Human ratings are sticky. The ingester may add OTHER fields (sources,
related, etc.) but the quality block stays untouched.

If `rated_by: ingester` (or absent), the ingester re-rates on every
re-ingest.

## Page size threshold

Split a page when:
- It crosses 200 lines, OR
- It accumulates 2+ raw sources covering distinct subtopics.

The ingester decides; the title-scope check (see ingest skill) catches
the case where new evidence is broader than the existing page's slug.

## Category directory

`type:` MUST equal `path.parts[0]` (the top-level directory name,
plural form). Validated by `wiki-discover.py` against the actual
directory tree.
````

- [ ] **Step 2: Extract the ingest body from the existing `karpathy-wiki/SKILL.md`**

Read the current `skills/karpathy-wiki/SKILL.md` lines ~275 onwards (Ingest section through end). That's the canonical ingester body. Copy it into `skills/karpathy-wiki-ingest/SKILL.md` with the new frontmatter wrapper:

```markdown
---
name: karpathy-wiki-ingest
description: |
  For the spawned `claude -p` ingester only. The main agent never loads this. Defines orientation protocol, page format, role guardrail, validator contract, manifest protocol, commit protocol. Loaded via the spawn prompt by `wiki-spawn-ingester.sh`.
---

# karpathy-wiki ingest (for spawned ingester only)

You are a detached `claude -p` ingester invoked by
`wiki-spawn-ingester.sh`. Your job: process one already-claimed
capture into wiki pages and commit. The main agent does NOT read this
skill — it's loaded by your spawn prompt.

## Orientation

Before any wiki write, read these in order:

1. `<wiki>/schema.md` — current categories, taxonomy, thresholds.
2. `<wiki>/index.md` (or `<wiki>/<category>/_index.md` per category) — what pages exist.
3. Last ~10 entries of `<wiki>/log.md` — recent activity.

Only then decide what to do. Without orientation you will duplicate
existing pages, miss relevant cross-references, or violate the schema.

(Leg 4 of v2.4 extends this with deep orientation: read 0-7 candidate
pages in full before deciding what to write. The basic three-step
orientation above is the minimum.)

## Role guardrail

Read `<wiki>/.wiki-config` to determine the wiki's role:

- `role: project` or `role: project-pointer` → you are writing for a
  PROJECT wiki. Document specifics: how this app handles X, where
  bug Y lived, what we decided for this codebase. Do NOT generalize.
- `role: main` → you are writing for the MAIN wiki. Extract general
  patterns reusable across projects. Do NOT name specific apps or
  instances.

If the index pulls strongly toward instance-style or pattern-style
writing (you read 5+ existing pages of one shape), trust the pull.
The role hint is a backup tripwire — *"if you find yourself
generalizing in a project wiki / specifying in a main wiki, stop."*

## Capture format

See `<plugin>/skills/karpathy-wiki-capture/references/capture-schema.md`
for the canonical capture frontmatter contract — `capture_kind` enum,
body floors, evidence rules, legacy backward-compat. Do not duplicate
that schema here.

## Page format

See `references/page-conventions.md` for the canonical page
frontmatter and cross-link conventions.

## Body-sufficiency check (first thing — reject if too thin)

Before any other work, measure the capture body size in bytes (content
AFTER the closing `---` of frontmatter). Apply the per-`capture_kind`
floor:

- `raw-direct` → no floor (body is auto-generated boilerplate).
- `chat-attached` → 1000 bytes.
- `chat-only` → 1500 bytes.

Legacy captures (no `capture_kind`): apply backward-compat per
`<plugin>/skills/karpathy-wiki-capture/references/capture-schema.md`.

If body is BELOW its floor:

1. Add `needs_more_detail: true` to the capture's frontmatter.
2. Add `needs_more_detail_reason: "body is <N> bytes; floor for capture_kind=<K> is <F> bytes"`.
3. Rename `.md.processing` → `.md` so the next session-start drain
   re-presents it after the main agent expands.
4. Append to `log.md`: `## [<timestamp>] reject | <capture-basename> — body <N>b below <F>b floor`.
5. Exit 0. Do NOT write pages. Do NOT commit.

A thin-capture rejection is a feature, not a failure.

## Ingester steps (full)

(The remainder of this section is extracted from the v2.3
`karpathy-wiki/SKILL.md` lines 275-470, covering steps 2-10:
orientation, capture body read, evidence copy + manifest, target
page decision, page write, validator, commit, archive. Copy that
content here verbatim during Task 7's implementation step.)

[Extraction step — do this in Step 3 below: copy the content of
`skills/karpathy-wiki/SKILL.md` from the line `## Ingest — what
the headless ingester does` (currently line 275) through the end
of the ingester section. Paste it here, replacing this placeholder
block. Do NOT edit the extracted content in this leg; Leg 4 modifies
the orientation step to add deep orientation + issue reporting.]
````

- [ ] **Step 3: Actually do the extraction**

Run:

```bash
# Find the line range in the current SKILL.md for the ingest section
grep -n '^## Ingest' /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md
# Should print something like "275:## Ingest — what the headless ingester does"

# Manually inspect the file from that line onwards and copy the
# Ingester section through to the end of the file (or to the next
# top-level section that's not ingest-related).
```

Use the Read tool to load the relevant lines of `skills/karpathy-wiki/SKILL.md` starting at the `## Ingest` heading, copy the content through to the end of the ingester section (typically through "Stop. Do not summarize."), and paste it into `skills/karpathy-wiki-ingest/SKILL.md` replacing the `[NOTE TO IMPLEMENTER: ...]` block.

- [ ] **Step 4: Run tests to verify they pass**

Run: `bash tests/unit/test-ingest-skill.sh`
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add skills/karpathy-wiki-ingest/SKILL.md skills/karpathy-wiki-ingest/references/page-conventions.md
git commit -m "feat(skills): add karpathy-wiki-ingest skill + page-conventions reference"
```

---

### Task 8: Failing test — skill split has no rule duplication

**Files:**
- Create: `tests/unit/test-skill-split-no-overlap.sh`

- [ ] **Step 1: Write the failing test**

This test enforces the spec's "skill rule ownership" contract: each rule has exactly one canonical home.

```bash
#!/bin/bash
# Verify capture and ingest skills don't duplicate rules.
# Specifically: no >80 contiguous-word substring overlap between them
# (excluding files under references/, which are explicitly shared).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CAPTURE="${REPO_ROOT}/skills/karpathy-wiki-capture/SKILL.md"
INGEST="${REPO_ROOT}/skills/karpathy-wiki-ingest/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "${CAPTURE}" ]] || fail "capture skill missing"
[[ -f "${INGEST}" ]] || fail "ingest skill missing"

# Use python to find any contiguous 80-word substring that appears in both files.
python3 - "${CAPTURE}" "${INGEST}" <<'PYEOF'
import sys, re

def words(path):
    with open(path) as f:
        text = f.read()
    # Strip code blocks (the canonical schema reference may legitimately appear in both as a fenced ref)
    text = re.sub(r'```.*?```', '', text, flags=re.DOTALL)
    return re.findall(r'\S+', text)

WIN = 80
a = words(sys.argv[1])
b_text = ' '.join(words(sys.argv[2]))

# For every 80-word window in a, check if it appears in b
overlap = None
for i in range(len(a) - WIN + 1):
    window = ' '.join(a[i:i + WIN])
    if window in b_text:
        overlap = window
        break

if overlap:
    print(f"FAIL: 80-word overlap between capture and ingest skills:")
    print(f"  ...{overlap[:200]}...")
    sys.exit(1)
else:
    print("PASS: no >80-word substring overlap")
PYEOF
```

- [ ] **Step 2: Run test to verify it passes (or surfaces real overlap)**

Run: `bash tests/unit/test-skill-split-no-overlap.sh`
Expected: PASS — if the skill split is clean. If it FAILs and reports a real overlap, that's an actionable signal: the duplicated text needs to be moved into one canonical home (loader OR a `references/` file).

- [ ] **Step 3: If the test fails, fix the duplication**

Move the duplicated rule into either:
- `skills/using-karpathy-wiki/SKILL.md` (if it's a rule that applies to BOTH capture and ingest contexts — e.g., iron laws, announce contract).
- `skills/karpathy-wiki-capture/references/capture-schema.md` or `skills/karpathy-wiki-ingest/references/page-conventions.md` (if it's a shared schema/contract).

Then delete the duplicate from one of the skill bodies. Re-run the test until PASS.

- [ ] **Step 4: Commit**

```bash
git add tests/unit/test-skill-split-no-overlap.sh
# If you fixed any duplication:
git add skills/
git commit -m "test(unit): enforce no rule duplication between capture and ingest skills"
```

---

### Task 9: Failing test — SessionStart hook injects loader

**Files:**
- Create: `tests/unit/test-session-start-loader-injection.sh`

- [ ] **Step 1: Write the failing test**

```bash
#!/bin/bash
# Verify the SessionStart hook injects the using-karpathy-wiki loader
# in normal contexts and skips it in subagent/ingester contexts.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${REPO_ROOT}/hooks/session-start"
LOADER="${REPO_ROOT}/skills/using-karpathy-wiki/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "${HOOK}" ]] || fail "hook missing"
[[ -f "${LOADER}" ]] || fail "loader missing"

# Make a temp wiki so the drift-scan portion has something to look at
TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT
cd "${TESTDIR}"
bash "${REPO_ROOT}/scripts/wiki-init.sh" main "${TESTDIR}/wiki" >/dev/null

# Case 1: normal session — loader should be in additionalContext
output_normal=$(env -u WIKI_CAPTURE -u CLAUDE_AGENT_PARENT bash "${HOOK}" 2>/dev/null || true)
echo "${output_normal}" | grep -q 'additionalContext' \
  || fail "normal session: hook did not emit additionalContext"
echo "${output_normal}" | grep -q 'EXTREMELY_IMPORTANT' \
  || fail "normal session: additionalContext missing <EXTREMELY_IMPORTANT> wrapper"
echo "${output_normal}" | grep -q 'using-karpathy-wiki' \
  || fail "normal session: additionalContext missing loader name"

# Case 2: WIKI_CAPTURE set (we are inside an ingester) — no additionalContext
output_capture=$(WIKI_CAPTURE=1 bash "${HOOK}" 2>/dev/null || true)
if echo "${output_capture}" | grep -q 'additionalContext'; then
  fail "ingester context: hook leaked additionalContext"
fi

# Case 3: CLAUDE_AGENT_PARENT set (we are a subagent) — no additionalContext
output_subagent=$(env -u WIKI_CAPTURE CLAUDE_AGENT_PARENT=1 bash "${HOOK}" 2>/dev/null || true)
if echo "${output_subagent}" | grep -q 'additionalContext'; then
  fail "subagent context: hook leaked additionalContext"
fi

# Case 4: no wiki at cwd AND not under one — loader STILL injected
NOWIKI="$(mktemp -d)"
trap 'rm -rf "${NOWIKI}"; rm -rf "${TESTDIR}"' EXIT
cd "${NOWIKI}"
output_nowiki=$(env -u WIKI_CAPTURE -u CLAUDE_AGENT_PARENT bash "${HOOK}" 2>/dev/null || true)
echo "${output_nowiki}" | grep -q 'additionalContext' \
  || fail "no-wiki cwd: hook did not emit additionalContext (loader must inject regardless of wiki presence)"

echo "PASS: SessionStart loader injection across all four contexts"
```

- [ ] **Step 2: Run test to verify it fails**

Run: `bash tests/unit/test-session-start-loader-injection.sh`
Expected: FAIL — current hook does not emit `additionalContext` at all.

- [ ] **Step 3: Commit**

```bash
git add tests/unit/test-session-start-loader-injection.sh
git commit -m "test(unit): add failing test for SessionStart loader injection"
```

---

### Task 10: Implement loader injection in `hooks/session-start`

**Files:**
- Modify: `hooks/session-start`

- [ ] **Step 1: Read the current hook**

Read `hooks/session-start` end-to-end. The current structure is:

1. `WIKI_CAPTURE` fork-bomb guard (lines 21-23) — exit 0 if set.
2. Resolve wiki via `wiki_root_from_cwd` (line 31) — exit 0 if not found.
3. `_drift_scan` function — finds new/modified files in `raw/`, creates drift captures.
4. `_drain_pending` function — spawns ingesters for pending captures.
5. `_reclaim_stale` function — renames `.md.processing` files >10min old back to `.md`.
6. Exit 0.

Today's hook does NOT emit any stdout or `additionalContext`. Step 2 of the v2.4 hook execution order needs to be added BEFORE the existing wiki-resolution logic.

- [ ] **Step 2: Add `CLAUDE_AGENT_PARENT` to the early-exit guard**

In `hooks/session-start`, find the existing fork-bomb guard:

```bash
if [[ -n "${WIKI_CAPTURE:-}" ]]; then
  exit 0
fi
```

Change it to:

```bash
# v2.4 step 1: subagent / ingester fork-bomb guard.
# Skip the entire hook (no loader, no drift-scan, no drain) when:
#   - WIKI_CAPTURE is set (we are inside a spawned ingester)
#   - CLAUDE_AGENT_PARENT is set (we are a subagent dispatched by another agent)
if [[ -n "${WIKI_CAPTURE:-}" || -n "${CLAUDE_AGENT_PARENT:-}" ]]; then
  exit 0
fi
```

- [ ] **Step 3: Add loader-injection step BEFORE wiki resolution**

Locate the line that resolves the wiki:

```bash
wiki="$(wiki_root_from_cwd 2>/dev/null || echo "")"
[[ -n "${wiki}" ]] || exit 0  # No wiki; nothing to do.
```

Insert the loader-injection step immediately BEFORE that block (and after the env-var guard). Use the same pattern as `superpowers:using-superpowers`'s SessionStart hook — read the loader file, escape for JSON, emit a JSON object with `hookSpecificOutput.additionalContext`.

```bash
# v2.4 step 2: loader injection (always runs, regardless of wiki presence).
# Reads skills/using-karpathy-wiki/SKILL.md and emits its body wrapped in
# <EXTREMELY_IMPORTANT> tags as hookSpecificOutput.additionalContext, so
# the agent sees the karpathy-wiki rules in every conversation.
LOADER_PATH="${REPO_ROOT}/skills/using-karpathy-wiki/SKILL.md"
if [[ -f "${LOADER_PATH}" ]]; then
  loader_content="$(cat "${LOADER_PATH}")"

  # Escape the loader content for JSON embedding.
  # Each ${s//old/new} is a single C-level pass — fast for large strings.
  escape_for_json() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
  }

  loader_escaped="$(escape_for_json "${loader_content}")"
  context="<EXTREMELY_IMPORTANT>\nYou have karpathy-wiki rules.\n\n**Below is the full content of the using-karpathy-wiki loader skill — auto-loaded into every conversation. For all other karpathy-wiki skills (capture, ingest), use the Skill tool when their moment arrives:**\n\n${loader_escaped}\n</EXTREMELY_IMPORTANT>"

  # Claude Code expects hookSpecificOutput.additionalContext (nested).
  printf '{"hookSpecificOutput":{"additionalContext":"%s"}}' "${context}"
fi

# v2.4 step 3: wiki resolution (existing walk-up behavior).
# Steps 4-6 (drift-scan, drain, reclaim) only run if a wiki is found.
```

Then leave the existing wiki resolution + drift/drain/reclaim logic as-is. Today's `[[ -n "${wiki}" ]] || exit 0` becomes the natural step-3 termination point: if no wiki, the loader has already been emitted and the hook exits cleanly without running steps 4-6.

- [ ] **Step 4: Run the failing test from Task 9 to verify it now passes**

Run: `bash tests/unit/test-session-start-loader-injection.sh`
Expected: PASS

- [ ] **Step 5: Run the existing SessionStart integration test to verify no regression**

Run: `bash tests/integration/test-session-start.sh`
Expected: PASS (the existing drift-scan + drain behavior is preserved).

If it fails, the most likely cause is the existing test asserts empty hook stdout (which v2.4 violates by design). Update the existing test to allow `additionalContext` JSON in normal contexts; it should still assert empty stdout for `WIKI_CAPTURE`/`CLAUDE_AGENT_PARENT` contexts.

- [ ] **Step 6: Commit**

```bash
git add hooks/session-start
# If you updated the existing integration test:
git add tests/integration/test-session-start.sh
git commit -m "feat(hooks): inject using-karpathy-wiki loader via SessionStart additionalContext"
```

---

### Task 11: Update old `skills/karpathy-wiki/SKILL.md` description (transition)

**Files:**
- Modify: `skills/karpathy-wiki/SKILL.md`

The old skill stays in place during the v2.4 transition (per the spec's migration section). Only its description changes — to redirect users invoking it by name.

- [ ] **Step 1: Update the frontmatter description**

In `skills/karpathy-wiki/SKILL.md`, replace the `description:` block (the YAML frontmatter at the top, between the two `---` markers) with a redirect note. Keep `name:` unchanged, keep `metadata:` unchanged, keep the BODY unchanged.

The new description:

```yaml
description: |
  DEPRECATED in v2.4 — split into three focused skills:
  - `using-karpathy-wiki` (auto-loaded by SessionStart hook; loader)
  - `karpathy-wiki-capture` (main agent, on-demand)
  - `karpathy-wiki-ingest` (spawned ingester only)

  This skill's body is preserved for the v2.4 transition. The body content has been migrated to the three new skills above; new agents should not invoke this skill directly. Removal is scheduled for a separate cleanup commit after v2.4 ships and the new skills are verified working in the wild.

  TRIGGER (legacy redirect): Same triggers as `using-karpathy-wiki`. If you are reading this skill, follow `using-karpathy-wiki/SKILL.md` instead.
```

- [ ] **Step 2: Verify the body is unchanged**

Run: `git diff skills/karpathy-wiki/SKILL.md`
Expected: ONLY the description block changed. The body (everything after the second `---`) is identical to before.

- [ ] **Step 3: Verify existing tests still pass**

Run: `bash tests/run-all.sh`
Expected: all tests pass. The old skill body still loads, drift-scan + drain still work, etc.

- [ ] **Step 4: Commit**

```bash
git add skills/karpathy-wiki/SKILL.md
git commit -m "docs(skills): mark karpathy-wiki skill deprecated in v2.4 (transition)"
```

---

### Task 12: Integration test — Leg 1 end-to-end

**Files:**
- Create: `tests/integration/test-leg1-end-to-end.sh`

- [ ] **Step 1: Write the integration test**

```bash
#!/bin/bash
# Integration test for v2.4 Leg 1: loader injected, skills split correctly,
# old skill still loads, hook behavior consistent across contexts.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${REPO_ROOT}/hooks/session-start"

fail() { echo "FAIL: $*" >&2; exit 1; }

# 1. All four skill files exist
for f in \
  skills/using-karpathy-wiki/SKILL.md \
  skills/karpathy-wiki-capture/SKILL.md \
  skills/karpathy-wiki-capture/references/capture-schema.md \
  skills/karpathy-wiki-ingest/SKILL.md \
  skills/karpathy-wiki-ingest/references/page-conventions.md \
  skills/karpathy-wiki/SKILL.md
do
  [[ -f "${REPO_ROOT}/${f}" ]] || fail "missing: ${f}"
done

# 2. Old skill description marks itself deprecated
grep -q 'DEPRECATED in v2.4' "${REPO_ROOT}/skills/karpathy-wiki/SKILL.md" \
  || fail "old skill description not updated"

# 3. Hook execution order: env-guard → loader → wiki-resolution
# Check by inspecting hook source (no need to mock the runtime — the
# unit tests already cover the runtime behavior end-to-end).
hook_src="$(cat "${HOOK}")"
guard_line=$(echo "${hook_src}" | grep -n 'WIKI_CAPTURE.*CLAUDE_AGENT_PARENT' | head -1 | cut -d: -f1)
loader_line=$(echo "${hook_src}" | grep -n 'EXTREMELY_IMPORTANT' | head -1 | cut -d: -f1)
resolve_line=$(echo "${hook_src}" | grep -n 'wiki_root_from_cwd' | head -1 | cut -d: -f1)
[[ -n "${guard_line}" && -n "${loader_line}" && -n "${resolve_line}" ]] \
  || fail "hook missing one of: env guard, loader injection, wiki resolution"
[[ "${guard_line}" -lt "${loader_line}" ]] \
  || fail "hook ordering: env guard ($guard_line) must come before loader ($loader_line)"
[[ "${loader_line}" -lt "${resolve_line}" ]] \
  || fail "hook ordering: loader injection ($loader_line) must come before wiki resolution ($resolve_line)"

# 4. Smoke-run the existing unit + integration tests still pass
bash "${REPO_ROOT}/tests/unit/test-using-karpathy-wiki-loader.sh" >/dev/null \
  || fail "loader unit test"
bash "${REPO_ROOT}/tests/unit/test-capture-skill.sh" >/dev/null \
  || fail "capture skill unit test"
bash "${REPO_ROOT}/tests/unit/test-ingest-skill.sh" >/dev/null \
  || fail "ingest skill unit test"
bash "${REPO_ROOT}/tests/unit/test-skill-split-no-overlap.sh" >/dev/null \
  || fail "skill-split overlap test"
bash "${REPO_ROOT}/tests/unit/test-session-start-loader-injection.sh" >/dev/null \
  || fail "loader injection test"

echo "PASS: Leg 1 end-to-end integration"
```

- [ ] **Step 2: Run the integration test**

Run: `bash tests/integration/test-leg1-end-to-end.sh`
Expected: PASS

- [ ] **Step 3: Run the full test suite**

Run: `bash tests/run-all.sh`
Expected: all tests pass. Verify the existing test suite is not regressed.

- [ ] **Step 4: Commit**

```bash
git add tests/integration/test-leg1-end-to-end.sh
git commit -m "test(integration): Leg 1 end-to-end (loader + skill split + hook ordering)"
```

---

## Self-review checklist

Before declaring Leg 1 done, verify:

- [ ] Loader skill (`using-karpathy-wiki/SKILL.md`) is ≤ 200 lines and contains: frontmatter (name, description), `<SUBAGENT-STOP>` block at top of body, iron laws, announce-line contract, trigger taxonomy, pointers to capture and ingest skills.
- [ ] Capture skill cites `references/capture-schema.md`; does NOT duplicate iron laws or announce contract.
- [ ] Ingest skill cites `references/page-conventions.md` AND `karpathy-wiki-capture/references/capture-schema.md`; does NOT duplicate iron laws or announce contract.
- [ ] `tests/unit/test-skill-split-no-overlap.sh` PASSES (no >80-word verbatim overlap between capture and ingest skills outside their `references/` files).
- [ ] SessionStart hook execution order: subagent/ingester guard → loader injection → wiki resolution → drift/drain/reclaim.
- [ ] Hook injects `additionalContext` in normal contexts (verified by `tests/unit/test-session-start-loader-injection.sh`).
- [ ] Hook injects NO `additionalContext` when `WIKI_CAPTURE` OR `CLAUDE_AGENT_PARENT` is set.
- [ ] Hook injects loader EVEN when no wiki at cwd (no-wiki case is the loader's purpose).
- [ ] Old `skills/karpathy-wiki/SKILL.md` description updated to redirect; body unchanged.
- [ ] `bash tests/run-all.sh` passes (no regressions in existing tests).
- [ ] RED scenario (`tests/red/RED-leg1-no-loader.md`) committed before any skill change.

## Verification gate

After Leg 1 ships, the following must hold (this is the spec's exit criterion for Leg 1):

- Fresh agent session in any directory shows the `using-karpathy-wiki` body inside `<EXTREMELY_IMPORTANT>` tags in conversation context.
- Spawned ingester (`WIKI_CAPTURE` set) does not see the loader.
- Subagent dispatch (`CLAUDE_AGENT_PARENT` set) does not see the loader.

Verified mechanically by the unit + integration tests above.

## Next leg

Leg 2 plan: `docs/superpowers/plans/2026-05-06-karpathy-wiki-v2.4-leg2-resolver.md` — adds `bin/wiki capture` subcommand, `wiki-resolve.sh`, project-pointer config layout, headless fallback, `wiki use` CLI. Depends on Leg 1's loader being in place (the loader instructs the agent to invoke `bin/wiki capture`).
