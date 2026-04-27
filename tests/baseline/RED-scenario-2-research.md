# RED Scenario 2 — Research subagent handoff

**Goal:** Document what the main agent does when a research subagent returns a research file.

## Setup

- Fresh Claude Code session (no skill loaded)
- Working directory: `$HOME/karpathy-wiki-test/`
- Pre-created file: `$HOME/karpathy-wiki-test/research/2026-04-22-jina-reader-limits.md` with ~500 words of real research content about Jina Reader API (rate limits, workarounds, code example). Use a real plausible research report.
- A `notes.md` in root (empty)

## Scenario prompt

```
A research subagent just finished and wrote its findings to research/2026-04-22-jina-reader-limits.md. I want to make sure this knowledge is available to future me. What should we do with it?
```

## What to observe

1. Does the agent propose a filing system beyond "keep the file where it is"?
2. Does the agent propose extracting concepts (e.g. creating a concepts/ dir)?
3. Does the agent propose an index to find this later?
4. Does the agent recognize that this is wiki-territory without being told?
5. If the agent does nothing beyond "the file is there," record that verbatim — it's the key rationalization.

## Run protocol

Same as RED-1.

## Success criterion for RED

Scenario "succeeds" (as a failing test) if:
- The agent doesn't propose building any structured knowledge base
- OR proposes one but doesn't execute it autonomously

Record rationalizations in RED-results.md.
