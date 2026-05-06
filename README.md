# Karpathy Wiki

A Claude Code skill for auto-maintained LLM wikis — based on [Andrej Karpathy's LLM Wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f).

Instead of re-deriving answers from raw documents every time (RAG), the LLM incrementally builds and maintains a wiki — a structured, interlinked collection of markdown files. The wiki compounds with every source you add and every question you ask.

For day-to-day usage and the workflow walkthrough, see [MANUAL.md](MANUAL.md).

## What it does

As you work with Claude Code, any durable knowledge — research findings, resolved confusions, validated patterns, gotchas, architectural decisions — gets written as a small capture file and processed by a detached background worker into a persistent wiki. The wiki is git-versioned. Your flow is never interrupted.

User commands:

- `wiki status` — health report (categories, page counts, depth-violation count, soft-ceiling indicator, quality rollup, last ingest, drift, recent ingester-reported issues, fork-asymmetry). **Implemented.**
- `wiki capture` — write a chat-driven capture (the agent's canonical entry point; supports `--kind chat-only|chat-attached`, body via stdin or `--body-file`).
- `wiki ingest-now` — drift-scan + drain `inbox/` on demand.
- `wiki issues` — show recent ingester-reported issues, grouped and severity-ordered.
- `wiki use project|main|both` — change per-cwd wiki mode.
- `wiki init-main` — bootstrap `~/.wiki-pointer` (interactive).
- `wiki doctor` — deep lint + smartest-model re-rate of quality blocks. **Not yet implemented (stub returns "not implemented" exit 1).** Deferred to a future ship; tracked in `TODO.md`.

Everything else is automatic. The plugin handles both a main knowledge base (`~/wiki/`) and per-project wikis (`<project>/wiki/`) via the `wiki-resolve.sh` resolver: every capture call resolves the right wiki for the cwd before writing. Drop a file into a wiki's `inbox/` and the next session-start ingests it directly — no fabricated wrapper capture required.

## Install

Clone the repo and the user CLI symlink:

```bash
git clone https://github.com/toolboxmd/karpathy-wiki ~/dev/karpathy-wiki
ln -s ~/dev/karpathy-wiki/bin/wiki ~/.local/bin/wiki   # or anywhere on PATH
```

Then register the plugin with Claude Code by adding two entries to `~/.claude/settings.json` — the marketplace pointer and the enabled-plugins flag:

```json
{
  "extraKnownMarketplaces": {
    "karpathy-wiki-local": {
      "source": {
        "source": "directory",
        "path": "/Users/<you>/dev/karpathy-wiki"
      }
    }
  },
  "enabledPlugins": {
    "karpathy-wiki@karpathy-wiki-local": true
  }
}
```

Replace `/Users/<you>/dev/karpathy-wiki` with your actual repo path. Then run `/reload-plugins` in any Claude Code session. Hooks, commands, and the SKILL are auto-discovered from the plugin manifest — no manual hook wiring required.

> **Note on local install:** Claude Code's plugin system requires plugins to come from a registered marketplace, even for local-directory sources. The `extraKnownMarketplaces` entry above declares this repo IS a (single-plugin) marketplace; `marketplace.json` at the repo root makes that real. A bare `~/.claude/plugins/karpathy-wiki` symlink is NOT enough — Claude Code won't load slash commands from it.

## How it works

The skill is split into four focused parts, each loaded only when its moment arrives:

- `skills/using-karpathy-wiki/SKILL.md` — loader, auto-injected into every session by the SessionStart hook (via `hookSpecificOutput.additionalContext` for Claude Code; `additional_context` for Cursor; `additionalContext` for Copilot CLI / SDK-standard). Defines iron laws, triggers, and points at the other three.
- `skills/karpathy-wiki-capture/SKILL.md` — main agent, on-demand. Capture-authoring protocol: format, body floor, `bin/wiki capture` invocation.
- `skills/karpathy-wiki-read/SKILL.md` — main agent, on-demand. Deterministic 6-step orientation ladder for finding wiki coverage of a user question (orient → count candidates → inline-read OR Explore subagent OR web search → cite). Loaded for any user question, per Iron Rule 4.
- `skills/karpathy-wiki-ingest/SKILL.md` — spawned `claude -p` ingester only. Deep orientation protocol, page format, validator contract, manifest protocol, commit protocol.

Two hooks live at repo level:

- `hooks/session-start` — runs in this order: (1) subagent / ingester fork-bomb guard, (2) loader injection of the `using-karpathy-wiki` skill, (3) wiki resolution from cwd, (4) `inbox/` scan with 5-second mtime defer (rsync/unzip protection) → emits `capture_kind: raw-direct` captures, (5) `raw/` drift detection + raw-recovery (accidentally-dropped files in `raw/` move back to `inbox/` under the manifest lock), (6) drain pending captures via detached ingester spawn, (7) reclaim stale `.processing` files (>10 min).
- `hooks/stop` — session-end stub (transcript sweep is post-MVP).

Captures land as tiny markdown files in `<wiki>/.wiki-pending/`. Two flows feed it:

- **Chat-driven capture.** The main agent calls `bin/wiki capture` with a body that encodes durable knowledge from the conversation. The resolver chooses the right wiki for the cwd (project vs main), and the file is written into that wiki's `.wiki-pending/`.
- **Raw-direct ingest.** A file dropped into `<wiki>/inbox/` is picked up by the next SessionStart, which writes a `capture_kind: raw-direct` capture pointing at the file's absolute path. The ingester reads the file directly — no fabricated wrapper.

Either way, `wiki-spawn-ingester.sh` atomically claims each capture (exclusive hard-link rename) and launches a detached `claude -p` ingester that does deep orientation (steps 1-9), edits wiki pages under per-page locks, runs the validator, and auto-commits. Issues encountered during ingest are logged to `.ingest-issues.jsonl`; `wiki status` and `wiki issues` surface them.

Design doc: [`docs/planning/karpathy-wiki-v2-design.md`](docs/planning/karpathy-wiki-v2-design.md). Implementation plan: [`docs/planning/2026-04-22-karpathy-wiki-v2.md`](docs/planning/2026-04-22-karpathy-wiki-v2.md).

## Status

**v0.2.7 — work in progress.** Claude Code primary; multi-platform JSON shapes emitted defensively but untested on Cursor / Copilot CLI / Codex / OpenCode / Gemini. Active development on a single-user wiki; not yet packaged for general consumption.

**What works today (v2.4 + 0.2.7 read-protocol restoration):**
- Auto-capture + detached background ingest into a git-versioned wiki.
- Discovery-driven categories: any top-level `mkdir <name>/` at the wiki root creates a category. No code changes required.
- Per-directory `_index.md` tree (recursive); root `index.md` is a small MOC.
- Validator enforces `type: <plural-category>` matching `path.parts[0]` and rejects pages at depth ≥5.
- **Read-from-wiki protocol** (restored in 0.2.7 after v2.4 split silently dropped it). Iron Rule 4 forbids answering any user question without orientation; new `karpathy-wiki-read` skill defines a deterministic 6-step ladder (orient → candidate count → inline-read for ≤5 candidates / Explore subagent for 6+ / web search + capture-the-gap for cold results) with a hard cite contract on every wiki-grounded answer.
- Four-skill split with auto-loaded `using-karpathy-wiki` loader. Multi-platform SessionStart hook output: `hookSpecificOutput.additionalContext` for Claude Code, `additional_context` for Cursor, `additionalContext` for Copilot CLI / SDK-standard. Subagents and spawned ingesters get only the surface they need.
- Project-wiki auto-resolution at capture time via `wiki-resolve.sh` (5 exit codes). `wiki use project|main|both` lets the user override; `wiki init-main` bootstraps `~/.wiki-pointer`.
- Raw-direct ingest: drop a file into `<wiki>/inbox/` and the next SessionStart ingests it directly (no fabricated wrapper). Files accidentally dropped in `raw/` are recovered to `inbox/` under the manifest lock.
- Deep orientation (steps 1-9) in the ingester; issues surfaced to `.ingest-issues.jsonl` and the `wiki issues` / `wiki status` commands.
- Per-wiki `.ingest-runs.jsonl` for run history; status check detects fork-asymmetry between main and project wikis.
- `wiki status` health report; `wiki capture` / `wiki ingest-now` / `wiki issues` / `wiki use` / `wiki init-main` CLI.
- Tier-1 lint at every ingest: required frontmatter fields, link resolution, source existence, quality block ranges, type/path consistency.

**What's deferred (see `TODO.md`):**
- `bin/wiki orient` CLI shortcut for the read protocol's Step A (deferred to 0.2.8 — observe whether prose-only fix produces reliable behavior first).
- `allowed-tools` scoping on the four skills (deferred to 0.2.8 — orthogonal to read-protocol restoration).
- `wiki doctor` real implementation (smartest-model re-rate, orphan repair, tag-synonym consolidation).
- Stop-hook gate for turn-closure enforcement (`hooks/stop` is currently a stub).
- `.ingest.log` → `.ingest.jsonl` migration (dual-artifact pattern, scheduled for v2.5).
- Test coverage for non-Claude-Code platforms (Cursor / Copilot CLI / Codex / OpenCode / Gemini).

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
