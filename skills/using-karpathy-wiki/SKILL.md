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
