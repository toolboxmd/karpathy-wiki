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

## Instruction priority

If the user's `CLAUDE.md` / `AGENTS.md` or an explicit user instruction conflicts with the rules below, follow the user. The wiki rules override the default system prompt where they conflict, but **never** override the user's direct instructions.

## Iron laws

```
NO WIKI WRITE IN THE FOREGROUND
NO PAGE EDIT WITHOUT READING THE PAGE FIRST
NO SKIPPING A CAPTURE BECAUSE "IT DOESN'T LOOK WIKI-SHAPED"
NO ANSWERING ANY USER QUESTION WITHOUT ORIENTING FIRST
```

Captures go to `<wiki>/.wiki-pending/<timestamp>-<slug>.md`. A detached `claude -p` ingester reads the capture and writes the wiki page in the background.

## Orient before answering — the read protocol

For ANY user message that is asking a QUESTION (vs requesting a code edit, file operation, or pure command), you must orient on the wiki BEFORE drafting the answer. Pre-classifying a question as "general knowledge" or "not wiki-relevant" is the forbidden rationalization Iron Rule 4 was written to forbid.

**Cost framing.** Orientation is a once-per-session investment:

- First wiki-eligible question of the session: read `<wiki>/schema.md` and the relevant `<wiki>/<category>/_index.md` (or root `<wiki>/index.md` for cross-category questions). Two file reads, ~10-30 KB total.
- Subsequent questions in the same session: the schema and index are already in your working memory; the marginal check is a candidate-count scan against the (already-read) `_index.md`. Near-zero cost.

Load `karpathy-wiki-read/SKILL.md` for the deterministic 6-step ladder (orient → count candidates → inline-read OR subagent OR web-search → cite). Do NOT skip the load because "this question seems trivial" — the iron rule is unconditional.

**Resist-table for the read protocol** (see also the capture-side resist-table in `karpathy-wiki-capture/SKILL.md`):

| Rationalization | Reality |
|---|---|
| "This is general knowledge / I know this from training" | Pre-classifying questions as wiki-irrelevant is the forbidden rationalization. The wiki's scope is whatever has been captured. You don't know without checking. Orient. |
| "This question is trivial; reading two files is overkill" | Orientation is once per session. After the first orient, the marginal cost on the next question is near-zero (a re-scan of the already-read `_index.md`). The "trivial question" carve-out is the same drift that dropped the read protocol in v2.4. |
| "Pure syntax question, the wiki won't cover this" | You cannot know without checking. If `_index.md` has zero matches, the read skill's Step F handles it (web search + capture the gap). The orient itself is what proves there are no candidates. |
| "User asked me to fix a bug, not answer a question" | Code-edit requests don't trigger the read protocol; question-shaped requests do. If unsure (e.g. "why isn't this working" — could be a question OR a debug request), orient. |
| "I already oriented earlier this session, I'll skip this time" | Correct! Re-use the schema and index you already have. Run only the candidate-count check on the new question's terms. The protocol's deterministic part (Step B) is the only thing that re-runs per question. |

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

For ANY user question (including "what does the wiki know about X" questions, but also any other question per Iron Rule 4): load `karpathy-wiki-read/SKILL.md` and run the deterministic 6-step ladder. Do NOT load `karpathy-wiki-ingest/SKILL.md` — that's for the spawned ingester only and contains write-side machinery the main agent never needs.

## Mode change

If the user asks to change the wiki mode for this directory (phrases like "use project wiki here," "main only," "switch to both," "fork to main"), run:

```bash
wiki use project|main|both
```

Confirm the change in one line; do not over-narrate.

## What's NOT in this loader

The full operational details — capture format, body-size floors, spawn mechanics, ingester orientation, page format, manifest protocol, commit conventions — live in the on-demand skills:

- `skills/karpathy-wiki-capture/SKILL.md` — load when you are about to write a capture.
- `skills/karpathy-wiki-read/SKILL.md` — load when you are about to answer a user question (Iron Rule 4).
- `skills/karpathy-wiki-ingest/SKILL.md` — loaded by the spawned ingester via its prompt; the main agent never reads this.

If you do not know what to do at a particular step, load the on-demand skill — do not invent.
