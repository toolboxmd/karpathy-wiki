# GREEN Scenario 2 — Research subagent handoff (with skill)

Mirror of `tests/baseline/RED-scenario-2-research.md`. Same setup, same prompt. The karpathy-wiki skill IS loaded via `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md`.

## Setup

- Temp `HOME=/tmp/karpathy-wiki-test-green2-home`
- Working dir `/tmp/karpathy-wiki-test-green2/` with git init
- Pre-created `research/2026-04-22-jina-reader-limits.md` containing the Jina Reader research report
- Empty `notes.md`
- No pre-existing wiki; skill must auto-init

## Scenario prompt

```
A research subagent just finished and wrote its findings to research/2026-04-22-jina-reader-limits.md. I want to make sure this knowledge is available to future me. What should we do with it?
```

## Success criterion (all must hold)

- Agent invokes the skill and reads SKILL.md before acting.
- Agent auto-inits `$HOME/wiki/`.
- Agent writes a capture file to `$HOME/wiki/.wiki-pending/` whose `evidence` field is the ABSOLUTE PATH to the research file (not inlined content).
- Agent spawns the detached ingester.
- Agent leaves the original research file unmodified and in place.
- Agent announces: "Using the karpathy-wiki skill to ..."
- Zero rationalizations for skipping any step.
- Agent does NOT write `notes.md` or invent a parallel filing system (the skill IS the filing system).
