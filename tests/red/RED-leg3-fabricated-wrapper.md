# RED scenario — fabricated wrapper captures around subagent reports

**Date:** 2026-05-06
**Skill change this justifies:** v2.4 Leg 3 — `inbox/` drop zone + `wiki ingest-now` + raw-direct capture path.

## The scenario

A research subagent returns a 4 KB findings file at `/tmp/research-2026-05-06.md`. The findings include detailed claims, citations, version numbers, code snippets — exactly the kind of content the wiki should preserve.

Pre-v2.4 workflow: the main agent must write a `chat-attached` capture body (≥ 1000 bytes) wrapping a pointer to `/tmp/research-2026-05-06.md`. The body says something like:

> The research subagent at /tmp/research-2026-05-06.md returned findings on X. Please read the file and ingest it into the wiki. The findings cover [a brief summary]. The ingester should categorize this as concepts/ and cross-link to [related pages].

This wrapper body is a fabrication: it summarizes what the file already says (the ingester is going to read the file directly anyway). It wastes tokens AND produces a redundant first-pass on the content. The ingester ends up writing a wiki page that is essentially "what the wrapper body said, cleaned up" — much weaker than what it would write reading the report directly with full context.

Symptom: every research-subagent-returns-file event produces a wiki page that is a summary-of-a-summary. The actual rich content in the report is filtered through the wrapper's compression first.

## Why prose alone doesn't fix this

The pre-v2.4 SKILL.md describes "raw-direct ingest" (line 121: *"the user adds a file to raw/"*) but the actual mechanism still requires the agent to write a wrapper capture pointing at the raw. There is no `wiki ingest-now` and no `inbox/` queue that the ingester drains directly. Drift detection only fires when an EXISTING raw file's sha changes — it doesn't pick up new files dropped from outside.

The fix is structural:
- `<wiki>/inbox/` is a queue scanned by SessionStart and `wiki ingest-now`.
- A file in `inbox/` produces an auto-generated raw-direct capture (frontmatter only; body is hook-generated boilerplate). The ingester reads the FILE, not the capture body.
- Subagent-report workflow becomes: `mv /tmp/research-... <wiki>/inbox/ && wiki ingest-now <wiki>`. One command. No body authoring.

## Pass criterion

After Leg 3 ships:
- A subagent file moved into `<wiki>/inbox/` and processed via `wiki ingest-now` produces a wiki page that is a deep ingest of the FILE content, not a re-summary of an agent-written wrapper.
- The capture skill explicitly directs: "Subagent reports: do NOT write a chat-style capture body. Move the file into `<wiki>/inbox/` and run `wiki ingest-now`."
