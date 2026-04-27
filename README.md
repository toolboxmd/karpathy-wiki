# Karpathy Wiki

A Claude Code skill for auto-maintained LLM wikis — based on [Andrej Karpathy's LLM Wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f).

Instead of re-deriving answers from raw documents every time (RAG), the LLM incrementally builds and maintains a wiki — a structured, interlinked collection of markdown files. The wiki compounds with every source you add and every question you ask.

## What it does

As you work with Claude Code, any durable knowledge — research findings, resolved confusions, validated patterns, gotchas, architectural decisions — gets written as a small capture file and processed by a detached background worker into a persistent wiki. The wiki is git-versioned. Your flow is never interrupted.

User commands:

- `wiki status` — health report (categories, page counts, depth-violation count, soft-ceiling indicator, quality rollup, last ingest, drift). **Implemented.**
- `wiki doctor` — deep lint + smartest-model re-rate of quality blocks. **Not yet implemented (stub returns "not implemented" exit 1).** Deferred to a future ship; tracked in `TODO.md`.

Everything else is automatic. One skill handles both a main knowledge base (`~/wiki/`) and per-project wikis (`<project>/wiki/`), with the same conventions. Note: per-project wiki auto-resolution is not fully wired — captures from project sessions currently flow into the main `~/wiki/` even when a project-local `./wiki/` would be more appropriate. This is a known v2.4 gap; see `TODO.md`.

## Install

```bash
git clone https://github.com/toolboxmd/karpathy-wiki ~/dev/karpathy-wiki
ln -s ~/dev/karpathy-wiki ~/.claude/plugins/karpathy-wiki
ln -s ~/dev/karpathy-wiki/skills/karpathy-wiki ~/.claude/skills/karpathy-wiki
ln -s ~/dev/karpathy-wiki/bin/wiki ~/.local/bin/wiki   # or anywhere on PATH
```

That's it. Hooks are auto-discovered from `hooks/hooks.json` inside the plugin — no manual `settings.json` surgery required.

## How it works

A single skill (`skills/karpathy-wiki/SKILL.md`) defines triggers, orientation protocol, and iron laws. Two hooks live at repo level:

- `hooks/session-start` — drains pending captures on session start (drift detection in `raw/`, stale-lock reclaim, detached ingester spawn)
- `hooks/stop` — session-end stub (transcript sweep is post-MVP)

Captures land as tiny markdown files in `<wiki>/.wiki-pending/`. The spawner atomically claims each capture (exclusive hard-link rename) and launches a detached `claude -p` ingester that reads the capture, does the orientation protocol, edits wiki pages under per-page locks, and auto-commits.

Design doc: [`docs/planning/karpathy-wiki-v2-design.md`](docs/planning/karpathy-wiki-v2-design.md). Implementation plan: [`docs/planning/2026-04-22-karpathy-wiki-v2.md`](docs/planning/2026-04-22-karpathy-wiki-v2.md).

## Status

**v0.2.3 — work in progress.** Claude Code only. Active development on a single-user wiki; not yet packaged for general consumption.

**What works today (v2.3):**
- Auto-capture + detached background ingest into a git-versioned wiki.
- Discovery-driven categories: any top-level `mkdir <name>/` at the wiki root creates a category. No code changes required.
- Per-directory `_index.md` tree (recursive); root `index.md` is a small MOC.
- Validator enforces `type: <plural-category>` matching `path.parts[0]` and rejects pages at depth ≥5.
- `wiki status` health report.
- Tier-1 lint at every ingest: required frontmatter fields, link resolution, source existence, quality block ranges, type/path consistency.

**What's deferred (v2.4 candidates, see `TODO.md`):**
- `wiki doctor` real implementation (smartest-model re-rate, orphan repair, tag-synonym consolidation).
- Project-wiki auto-resolution at capture time — currently SKILL.md describes the algorithm but no script enforces it; project captures default to `~/wiki/`.
- Raw-direct ingest path — Obsidian Web Clipper / file-as-source content currently requires a wrapping capture.
- SessionStart hook injecting SKILL.md content (the `using-superpowers` autoload pattern).
- Stop-hook gate for turn-closure enforcement.
- Cross-platform support (Codex, OpenCode, Cursor, Hermes, Gemini).

The shipped surface is enough for daily personal use; rough edges remain. PRs welcome once the repo opens for external contributions.

## Tests

```bash
bash tests/run-all.sh
bash tests/self-review.sh
```

## Credits

Based on Andrej Karpathy's [LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) concept and [original tweet](https://x.com/karpathy/status/2039805659525644595).

The v2 SKILL.md is written in the style of, and uses techniques from, [obra/superpowers-skills](https://github.com/obra/superpowers-skills) (the `writing-skills`, `test-driven-development`, and `subagent-driven-development` skills in particular).

Built by [toolbox.md](https://toolbox.md).

## License

MIT
