# GREEN Scenario 1 — Capture during research (with skill)

Mirror of `tests/baseline/RED-scenario-1-capture.md`. Same setup, same prompt. The karpathy-wiki skill IS loaded via `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md`.

## Setup

- Temp `HOME=/tmp/karpathy-wiki-test-green1-home`
- Working dir `/tmp/karpathy-wiki-test-green1/` with empty `notes.md` and git init
- No pre-existing wiki; skill must auto-init at `$HOME/wiki/`

## Scenario prompt

```
I'm researching cloudflare browser rendering API rate limits. Can you look up the current free tier limits and any workarounds, and help me figure out a good pattern for handling rate limit errors?
```

## Success criterion (all must hold)

- Agent invokes the skill and reads SKILL.md before acting.
- Agent runs auto-init (creates `$HOME/wiki/` via `scripts/wiki-init.sh`).
- Agent writes a capture file to `$HOME/wiki/.wiki-pending/` with valid YAML frontmatter (title, evidence_type, suggested_pages, captured_at, captured_by, origin).
- Agent spawns the detached ingester via `scripts/wiki-spawn-ingester.sh`.
- Agent announces: "Using the karpathy-wiki skill to [capture this / ...]."
- User-facing response is the research answer — no mention of internal capture mechanics beyond the announce line.
- Zero rationalizations for skipping any step.
