# Karpathy Wiki

A provider-aware plugin for auto-maintained LLM wikis — based on [Andrej Karpathy's LLM Wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f).

Instead of re-deriving answers from raw documents every time (RAG), the LLM incrementally builds and maintains a wiki — a structured, interlinked collection of markdown files. The wiki compounds with every source you add and every question you ask.

For day-to-day usage and the workflow walkthrough, see [MANUAL.md](MANUAL.md).

## What it does

As you work with Claude Code, any durable knowledge — research findings, resolved confusions, validated patterns, gotchas, architectural decisions — gets written as a small capture file and processed by a detached background worker into a persistent wiki. The wiki is git-versioned. Your flow is never interrupted.

User commands:

- `wiki status` — content and ingest-runtime health report: queue depth, active slots, profiles, cooldowns, heartbeat stalls, scheduler state, failed/deferred captures, quality, drift, issues, and fork-asymmetry.
- `wiki capture` — write a chat-driven capture (the agent's canonical entry point; supports `--kind chat-only|chat-attached`, body via stdin or `--body-file`).
- `wiki ingest-now` — drift-scan + drain `inbox/` on demand.
- `wiki issues` — show recent ingester-reported issues, grouped and severity-ordered.
- `wiki use project|main|both` — change per-cwd wiki mode.
- `wiki config init-local|migrate|validate|show` — manage ignored, per-machine provider and dispatcher settings.
- `wiki scheduler install|uninstall|status` — manage the macOS cron-like LaunchAgent adapter.
- `wiki tick` — run one short, bounded dispatcher pass (also usable from an external scheduler).
- `wiki init-main` — bootstrap `~/.wiki-pointer` (interactive).
- `wiki doctor` — deep lint + smartest-model re-rate of quality blocks. **Not yet implemented (stub returns "not implemented" exit 1).** Deferred to a future ship; tracked in `TODO.md`.

The plugin handles both a main knowledge base (`~/wiki/`) and per-project wikis (`<project>/wiki/`) via the `wiki-resolve.sh` resolver. Each machine chooses one automatic activation mode: SessionStart, or a local scheduler. Drop a file into a wiki's `inbox/` and the next scan ingests it directly — no fabricated wrapper capture required.

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

> **Note on local install:** Claude Code's plugin system requires plugins to come from a registered marketplace, even for local-directory sources. The `extraKnownMarketplaces` entry above declares this repo IS a (single-plugin) marketplace; `.claude-plugin/marketplace.json` makes that real. A bare `~/.claude/plugins/karpathy-wiki` symlink is NOT enough — Claude Code won't load slash commands from it.

## How it works

The skill is split into four focused parts, each loaded only when its moment arrives:

- `skills/using-karpathy-wiki/SKILL.md` — loader, auto-injected into every session by the SessionStart hook (via `hookSpecificOutput.additionalContext` for Claude Code; `additional_context` for Cursor; `additionalContext` for Copilot CLI / SDK-standard). Defines iron laws, triggers, and points at the other three.
- `skills/karpathy-wiki-capture/SKILL.md` — main agent, on-demand. Capture-authoring protocol: format, body floor, `bin/wiki capture` invocation.
- `skills/karpathy-wiki-read/SKILL.md` — main agent, on-demand. Deterministic 6-step orientation ladder for finding wiki coverage of a user question (orient → count candidates → inline-read OR Explore subagent OR web search → cite). Loaded for any user question, per Iron Rule 4.
- `skills/karpathy-wiki-ingest/SKILL.md` — detached runtime ingester only. Provider-neutral deep orientation, page format, validator contract, manifest protocol, and deterministic completion contract.

Two hooks live at repo level:

- `hooks/session-start` — applies the subagent/ingester guard, injects the loader, resolves the wiki, and starts exactly one short dispatcher tick only when that wiki's local mode is `session_start`. In `scheduled` mode it is loader-only.
- `hooks/stop` — session-end stub (transcript sweep is post-MVP).

Captures land as tiny markdown files in `<wiki>/.wiki-pending/`. Two flows feed it:

- **Chat-driven capture.** The main agent calls `bin/wiki capture` with a body that encodes durable knowledge from the conversation. The resolver chooses the right wiki for the cwd (project vs main), and the file is written into that wiki's `.wiki-pending/`.
- **Raw-direct ingest.** A file dropped into `<wiki>/inbox/` is picked up by the next configured scan (SessionStart, LaunchAgent, or `wiki ingest-now`), which writes a `capture_kind: raw-direct` capture pointing at the file's absolute path. The ingester reads the file directly — no fabricated wrapper.

Either way, one dispatcher atomically claims captures and enforces the configured per-wiki and per-profile ceilings. It can invoke Claude Code, Codex, or Grok with the exact configured model and reasoning effort. A heartbeat keeps live `.processing` work identifiable; technical failures retry up to `max_attempts`, rate limits wait without consuming attempts, and exhausted work moves to `.wiki-pending/failed/`. Semantic ingest is not reviewed by a second model on every run; quality is selected and measured through benchmarks.

## Per-machine ingest configuration

Tracked `.wiki-config` contains only wiki identity. Provider/model choices, concurrency, activation mode, routing, and auto-commit live in `.wiki-config.local`, which is ignored by Git and configured separately by every user or machine.

Example (profile choices are illustrative, not defaults):

```bash
wiki config init-local <wiki> \
  --default-provider grok --default-model grok-4.5 --default-effort medium \
  --fallback-provider claude --fallback-model sonnet --fallback-effort low \
  --max-processes 10 --dispatch-mode session_start
wiki config validate <wiki>
wiki config show <wiki>
```

Supported provider adapters in this release are `grok`, `claude`, and `codex`; model IDs are not hard-coded. `executable` is one executable name or absolute path, never an arbitrary shell command.

For an older tracked operational config, inspect the split before applying it:

```bash
wiki config migrate <wiki> --dry-run
wiki config migrate <wiki> [explicit provider/model/effort options if needed]
```

This only migrates configuration layout. It does not move or rewrite wiki content.

## Activation modes

- `session_start`: no scheduler installation. SessionStart injects the loader and launches one bounded scan/tick.
- `scheduled`: `wiki scheduler install <wiki>` installs a short-lived macOS LaunchAgent and switches the local mode only after successful activation. `wiki scheduler uninstall <wiki>` removes only that wiki's agent and switches back to SessionStart.

The scheduled command does not keep a model resident in memory. On non-macOS systems, use `wiki tick <wiki> --source scheduled --scan` from an external scheduler. CodexBar is optional: when usable it provides advisory preflight quota data; when absent, malformed, or timed out, the dispatcher continues in reactive mode using provider CLI results.

Design doc: [`docs/planning/karpathy-wiki-v2-design.md`](docs/planning/karpathy-wiki-v2-design.md). Implementation plan: [`docs/planning/2026-04-22-karpathy-wiki-v2.md`](docs/planning/2026-04-22-karpathy-wiki-v2.md).

## Status

**Unreleased development branch based on v0.2.8.** Claude Code remains the loader-hook host; detached ingest supports Claude Code, Codex, and Grok. Multi-platform loader JSON shapes are emitted defensively but remain less tested than Claude Code.

**What works today (v2.4 + 0.2.7 read-protocol restoration + 0.2.8 hardening):**
- Auto-capture + detached background ingest into a git-versioned wiki.
- Discovery-driven categories: any top-level `mkdir <name>/` at the wiki root creates a category. No code changes required.
- Per-directory `_index.md` tree (recursive); root `index.md` is a small MOC.
- Validator enforces `type: <plural-category>` matching `path.parts[0]` and rejects pages at depth ≥5.
- **Read-from-wiki protocol** (restored in 0.2.7 after v2.4 split silently dropped it). Iron Rule 4 forbids answering any user question without orientation; new `karpathy-wiki-read` skill defines a deterministic 6-step ladder (orient → candidate count → inline-read for ≤5 candidates / Explore subagent for 6+ / web search + capture-the-gap for cold results) with a hard cite contract on every wiki-grounded answer.
- Four-skill split with auto-loaded `using-karpathy-wiki` loader. Multi-platform SessionStart hook output: `hookSpecificOutput.additionalContext` for Claude Code, `additional_context` for Cursor, `additionalContext` for Copilot CLI / SDK-standard. Subagents and detached ingesters get only the surface they need.
- Project-wiki auto-resolution at capture time via `wiki-resolve.sh` (5 exit codes). `wiki use project|main|both` lets the user override; `wiki init-main` bootstraps `~/.wiki-pointer`.
- Raw-direct ingest: drop a file into `<wiki>/inbox/` and the next configured scan ingests it directly (no fabricated wrapper). Files accidentally dropped in `raw/` are recovered to `inbox/` under the manifest lock.
- Deep orientation (steps 1-9) in the ingester; issues surfaced to `.ingest-issues.jsonl` and the `wiki issues` / `wiki status` commands.
- Per-wiki `.ingest-runs.jsonl` for run history; status check detects fork-asymmetry between main and project wikis.
- Bounded provider-aware dispatcher, optional fallback profile, heartbeat, retries, failed queue, optional CodexBar preflight, and mutually exclusive SessionStart/scheduled activation.
- `wiki status` health report; `wiki capture` / `wiki ingest-now` / `wiki issues` / `wiki use` / `wiki config` / `wiki scheduler` / `wiki tick` / `wiki init-main` CLI.
- Tier-1 lint at every ingest: required frontmatter fields, link resolution, source existence, quality block ranges, type/path consistency.

**What's deferred (see `TODO.md`):**
- `bin/wiki orient` CLI shortcut for the read protocol's Step A (deferred — observe whether prose-only fix produces reliable behavior first).
- `allowed-tools` scoping on the four skills (deferred — orthogonal to read-protocol restoration).
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
