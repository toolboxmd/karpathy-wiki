# RED scenario — captures default to $HOME/wiki/ because resolver lives in prose

**Date:** 2026-05-06
**Skill change this justifies:** v2.4 Leg 2 — `bin/wiki capture` is the single capture entry point; `wiki-resolve.sh` enforces the project-wiki branching the v2.x SKILL.md prose only describes.

## The scenario

User runs the agent in `~/dev/myapp/` (a git repo with no wiki).
A trigger fires: research subagent returns a 4 KB findings file.
Agent writes a capture body and runs `bash scripts/wiki-spawn-ingester.sh` directly (per pre-v2.4 SKILL.md prose).
`wiki_root_from_cwd` walks up looking for `.wiki-config`. It does not find one in `~/dev/myapp/` or `~/dev/`. It walks to `~/`, where there is no `.wiki-config`. But there IS one at `~/wiki/.wiki-config` — the v2.x lib had a sibling-check that matched this. Result: capture lands in `~/wiki/.wiki-pending/`.

The user expected the capture to land in either:
- A new project wiki at `~/dev/myapp/wiki/`, or
- The main wiki, with a clear "this is general-knowledge" framing,

depending on a one-time per-cwd decision. The spec describes this branching in prose (3-case algorithm) but no script enforces it. Every project session this user has ever run captured to `~/wiki/`.

## Why prose alone doesn't fix this

The current `skills/karpathy-wiki/SKILL.md` lines 74-93 describe the auto-init algorithm:
> 1. If cwd (or a parent) has a `.wiki-config` → use that wiki.
> 2. Otherwise, if `$HOME/wiki/.wiki-config` exists → cwd is outside a wiki; create a project wiki at `./wiki/` linked to `$HOME/wiki/`.
> 3. Otherwise → create the main wiki at `$HOME/wiki/`.

Steps 2 and 3 describe wiki creation that no script automates. The agent doesn't run this branching at every capture; it relies on `wiki_root_from_cwd` (walk-up). The walk-up's sibling-match silently selects `~/wiki/` whenever cwd is anywhere under `$HOME`.

The fix is structural:
- Add `bin/wiki capture` as the canonical entry point. Loader instructs agents to use it.
- `bin/wiki capture` calls `wiki-resolve.sh` (cwd-only; no walk-up).
- If `wiki-resolve.sh` exits 11 (cwd unconfigured), the wrapper prompts the user once, persists the choice in `.wiki-config` (project + optional `fork_to_main`) or `.wiki-mode` (main-only).
- Future sessions read the persisted choice; no re-prompt.

## Pass criterion

After Leg 2 ships:
- `bin/wiki capture --kind chat-only --title T <<< "$BODY"` in `~/dev/myapp/` (no `.wiki-config`, pointer valid) prompts the user for project / main / both. The chosen mode is persisted. Subsequent captures in the same cwd do NOT re-prompt.
- The walk-up sibling-match bug cannot fire from `bin/wiki capture` because the resolver is cwd-only.
