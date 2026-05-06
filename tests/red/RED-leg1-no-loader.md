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
