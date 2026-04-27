# Resume Instructions for karpathy-wiki v2 Implementation

**Date:** 2026-04-22
**Context:** this note exists so the next Claude Code session can pick up where the previous one left off, without needing the prior conversation.

## Where we are

The user `lukaszmaj` and Claude (prior session) finished the planning phase for v2 of the `karpathy-wiki` skill. Implementation has not started. Everything from design through two code-review rounds is committed and pushed to the `v2-rewrite` branch of `https://github.com/toolboxmd/karpathy-wiki`.

Current local state:
- Working directory: `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/`
- Current branch: `v2-rewrite` (pushed to `origin/v2-rewrite`)
- Base: `main` contains the v1 skills (unchanged, do not touch)
- Latest commit on `v2-rewrite`: a docs-only commit adding `docs/planning/` artifacts

The skill itself has NOT been implemented yet. Only the planning documents exist.

## What to do next

**Read these files, in order:**

1. `docs/planning/2026-04-22-karpathy-wiki-v2.md` — the **implementation plan**. This is the executable artifact. 29 tasks across 4 phases, TDD-structured with complete code in every step. Start at Phase 1 Task 1.
2. `docs/planning/karpathy-wiki-v2-design.md` — the design doc. Read this to understand the "why" behind architectural decisions.
3. `docs/planning/2026-04-22-plan-review-v2.md` — the latest code review. Confirms the plan is approved for execution. Read the "Summary" section only unless you hit something ambiguous.

**Optional background reading (read only if needed):**
- `docs/planning/karpathy_wiki_ecosystem.md` — community implementations of the Karpathy LLM Wiki pattern
- `docs/planning/superpowers-skill-style-guide.md` — how SKILL.md should be written
- `docs/planning/superpowers-packaging-study.md` — how the plugin should be packaged
- `docs/planning/agentic-cli-skills-comparison.md` — cross-platform skill-loading details
- `docs/planning/agentic-cli-headless-subagents.md` — headless/subagent invocation patterns
- `docs/planning/hermes-llm-wiki-study.md` — Hermes's own llm-wiki skill as reference
- `docs/planning/2026-04-22-plan-review.md` — first code review (already addressed, mostly historical)

## How to execute

Use the `superpowers:subagent-driven-development` skill. The plan's execution handoff explicitly names this as the recommended approach. Fresh subagent per task, two-stage review (spec compliance, then code quality), commit task-by-task.

Model selection per the skill:
- Mechanical tasks (single-file bash or Python with clear spec) -> cheap model
- Integration tasks (multi-file coordination) -> standard model
- Design/review tasks -> most capable available

## Autonomy bounds (user-approved)

The user explicitly granted autonomous execution with these stopping conditions. Do not surface to user unless one hits.

**Proceed autonomously through:**
- Phase 1 (RED baselines)
- Phase 2 (core mechanics, ~11 tasks of bash + Python TDD)
- Phase 3 (SKILL.md draft + GREEN scenarios + REFACTOR rounds)
- Phase 4 (packaging, plugin manifest, README)

**Stop and surface to user when:**
- REFACTOR converges (3 consecutive rounds with zero new rationalizations AND zero regressions)
- Budget hits (10 REFACTOR rounds consumed)
- Architectural change needed (not just prose edits)
- Ambiguity you genuinely cannot judge
- Consistent regression (same rationalization reopens for 2 rounds)

**Never do autonomously:**
- `git push` (every push is the user's call)
- Install the skill into real `~/.claude/skills/` for actual use
- Run the plan against the user's real research corpus
- Touch `main` branch
- Delete or modify files outside the cloned repo (especially do not touch `/Users/lukaszmaj/dev/bigbrain/` or `~/.claude/skills/{wiki,project-wiki}/`)

## Scope cuts already decided (do not re-litigate)

The plan deliberately drops these from v1; do not add them during execution:

- No `$WIKI_MAIN` env var
- No `~/.wiki-config` home-level pointer (the per-wiki `.wiki-config` is sufficient)
- No cross-platform CLI detection (hardcoded `claude` + `claude -p`)
- No Stop-hook transcript sweep (Stop is a stub in v1)
- No `wiki doctor` implementation (stubbed with "not implemented" exit)
- No Gemini `GEMINI.md` sidecar
- No polyglot `run-hook.cmd` Windows wrapper
- No auto-star-on-first-run (user deferred this)
- No Tier-2 opportunistic lint (v1 has Tier-1 inline only)

All of these are enumerated in the plan's "Deliberate v1 scope cuts" section.

## Testing caveat (already agreed with user)

The user will run the final end-to-end smoke test (Task 28) in a real Claude Code session, observing the filesystem state. Everything before Task 28 can be validated via unit tests, integration tests, and Task-tool subagent GREEN scenarios. The user said they accept this arrangement; do not block waiting for user testing except at Task 28.

## First action when resuming

1. `cd /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki`
2. `git status` -> confirm on `v2-rewrite`, clean tree
3. `git log --oneline -3` -> confirm latest is the `docs:` commit
4. Read `docs/planning/2026-04-22-karpathy-wiki-v2.md` end-to-end before dispatching any subagents
5. Create TodoWrite entries for all 29 tasks
6. Announce to user: "Resuming karpathy-wiki v2 implementation. Starting Phase 1 Task 1 now. I will surface when REFACTOR converges, budget hits, or something architectural comes up."
7. Dispatch the first implementer subagent for Task 1 using `superpowers:subagent-driven-development` templates

## Where original plans came from (already archived in this repo)

Everything under `docs/planning/` was copied from `/Users/lukaszmaj/dev/bigbrain/` during the planning phase. Originals remain there for reference. The conversation transcript from the planning session is at `docs/planning/transcripts/2026-04-22-design-session.jsonl` locally but is gitignored (not on GitHub).

## If something feels off

If the plan and reality disagree (e.g. a referenced script path is wrong, a test assumption breaks on this machine, a command behaves differently), stop and surface to the user rather than improvising. Improvisation during a large multi-task run compounds.

---

## v2.3 backups (Phase A.2, 2026-04-27)

- `~/wiki-backup-pre-v2.3-phase-a-20260427T074509Z.tar.gz` (2.6 MB) — outermost rollback for the live frontmatter migration. Pre-migration HEAD: `06db5d3` on `~/wiki/main`. Restore command: `tar xzf ~/wiki-backup-pre-v2.3-phase-a-20260427T074509Z.tar.gz -C ~`.
- `~/wiki-backup-pre-v2.3-phase-d-20260427T081358Z.tar.gz` (2.8 MB) — outermost rollback for Phase D page moves (4 pages from `concepts/` to `projects/toolboxmd/<project>/`). Restore command: `tar xzf ~/wiki-backup-pre-v2.3-phase-d-20260427T081358Z.tar.gz -C ~`.

