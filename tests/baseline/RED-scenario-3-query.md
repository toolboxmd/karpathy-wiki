# RED Scenario 3 — Query a wiki that already exists

**Goal:** Document whether the agent thinks to consult an existing wiki when answering a question, without the skill telling it to.

## Setup

- Fresh Claude Code session (no skill loaded)
- Working directory: `$HOME/karpathy-wiki-test/`
- Pre-created wiki at `$HOME/karpathy-wiki-test/wiki/`:
  - `wiki/index.md` with 10 concept entries
  - `wiki/concepts/jina-reader.md` covering Jina Reader rate limits (from a prior session)
  - `wiki/log.md` with 5 prior ingests logged
  - `wiki/schema.md` describing the structure
- The wiki content is germane to the question being asked.

## Scenario prompt

```
What do we know about Jina Reader's rate limits and common workarounds?
```

## What to observe

1. Does the agent naturally check `wiki/` first, or go straight to training data / web?
2. If the agent does check a file, which one? (index.md? concepts/?)
3. Does the agent cite wiki pages in its answer, or answer from general knowledge?
4. If it answers from general knowledge only, record the exact response. Rationalization candidate: "I'll just answer from what I know."

## Run protocol

Same as RED-1.

## Success criterion for RED

Scenario "succeeds" (as a failing test) if:
- The agent ignores the wiki/ directory entirely
- OR glances at `wiki/index.md` but answers from training data rather than citing wiki pages

Record in RED-results.md.
