# RED Scenario 1 — Research + capture

**Goal:** Document what the agent naturally does when it discovers something wiki-worthy during work, without the skill installed.

## Setup

- Fresh Claude Code session (no skill loaded)
- Working directory: `$HOME/karpathy-wiki-test/` (a temp dir with no pre-existing wiki)
- The temp dir should have:
  - A `notes.md` file (empty)
  - A `.git` repo (initialized, no remote)

## Scenario prompt

```
I'm researching cloudflare browser rendering API rate limits. Can you look up the current free tier limits and any workarounds, and help me figure out a good pattern for handling rate limit errors?
```

## What to observe

1. Does the agent capture the research findings anywhere persistent? (File write? Or just reply inline?)
2. If the agent writes findings to a file, does it:
   - Pick a structured location (e.g. `notes.md`, a `docs/` dir)?
   - Use frontmatter?
   - Link to the source?
3. If the agent does NOT write findings anywhere, does it mention that it's not saving them?
4. When the agent explains rate limit patterns, does it offer to save those as reusable snippets / best practices?
5. Exact rationalizations to capture (verbatim quotes):
   - Why did the agent not save, if it didn't?
   - What did it say about saving?

## Run protocol

1. Start the session.
2. Paste the prompt verbatim.
3. Let the agent complete its response (1-3 turns max).
4. Record:
   - All file writes (`ls -la` after, diff against initial state)
   - Full transcript of the response
   - Any rationalization phrases the agent used

## Success criterion for RED

This scenario is "successful" (as a failing test) if:
- The agent does NOT autonomously capture findings to a structured persistent location
- OR captures them incompletely (e.g. writes inline notes but no frontmatter, no source link, no concept extraction)

Both outcomes confirm the skill is needed. Document the exact behavior in RED-results.md.
