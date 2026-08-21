# Karpathy Wiki

A provider-aware plugin for auto-maintained LLM wikis — based on [Andrej Karpathy's LLM Wiki pattern](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f).

Instead of re-deriving answers from raw documents every time (RAG), the LLM incrementally builds and maintains a wiki — a structured, interlinked collection of markdown files. The wiki compounds with every source you add and every question you ask.

For day-to-day usage and the workflow walkthrough, see [MANUAL.md](MANUAL.md).

## What it does

As you work with Codex or Claude Code, durable knowledge such as research findings, resolved confusions, validated patterns, gotchas, and architectural decisions gets written as a small capture file and processed by a detached background worker into a persistent wiki. The wiki is git-versioned. Your flow is never interrupted.

Agent-facing CLI commands are listed below. In normal plugin use, ask Codex in
natural language and the SessionStart hook supplies the installed CLI path. From
a source checkout, operators can invoke the same commands as `./bin/wiki ...`.
No global `wiki` command is required.

- `wiki status` — content and ingest-runtime health report: queue depth, active slots, profiles, cooldowns, heartbeat stalls, scheduler state, failed/deferred captures, quality, drift, issues, and selective-promotion decisions.
- `wiki capture` — write a chat-driven capture (the agent's canonical entry point; supports `--kind chat-only|chat-attached`, body via stdin or `--body-file`).
- `wiki ingest-now` — drift-scan + drain `inbox/` on demand.
- `wiki issues` — show recent ingester-reported issues, grouped and severity-ordered.
- `wiki use project|main|both` — change per-cwd wiki mode.
- `wiki config init-local|migrate|migrate-local|validate|show` — manage trusted, per-machine provider and dispatcher settings outside the checkout.
- `wiki scheduler install|uninstall|enable|disable|status|tick-all` — manage the one machine-wide macOS LaunchAgent adapter and per-wiki activation.
- `wiki tick` — run one short, bounded dispatcher pass (also usable from an external scheduler).
- `wiki init-main` — bootstrap `~/.wiki-pointer` (interactive).
- `wiki doctor` — deep lint + smartest-model re-rate of quality blocks. **Not yet implemented (stub returns "not implemented" exit 1).** Deferred to a future ship; tracked in `TODO.md`.

The plugin handles both a main knowledge base and per-project wikis via the
`wiki-resolve.sh` resolver. The default main-wiki location is `~/wiki/`, but
the actual path is selected by `wiki init-main` and stored in
`~/.wiki-pointer`. A project wiki lives at `<project>/wiki/`. Each machine
chooses one automatic activation mode: SessionStart, or a local scheduler.
Drop a file into a wiki's `inbox/` and the next scan ingests it directly. No
fabricated wrapper capture is required.

`wiki use both` is project-first. Every original capture enters only the
project wiki. After local ingest, the project worker keeps repository-specific
knowledge local or publishes one generalized, provenance-linked capture to the
main wiki through an atomic idempotent helper. It never copies the original
capture verbatim into both queues.

## Install in Codex

The public repository is a Codex marketplace containing one plugin. Install it
from Codex CLI:

```bash
codex plugin marketplace add toolboxmd/karpathy-wiki --ref main
codex plugin add karpathy-wiki@toolboxmd
```

Then start a new Codex session. Review and trust the plugin's `SessionStart`
and `Stop` hooks through `/hooks`. The installed SessionStart hook tells the
agent the exact plugin-owned CLI path, so no global `wiki` symlink or separate
skill copy is required.

To update a GitHub installation:

1. Run the plugin lifecycle commands in your shell:

```bash
codex plugin marketplace upgrade toolboxmd
codex plugin remove karpathy-wiki@toolboxmd
codex plugin add karpathy-wiki@toolboxmd
```

2. Start a new Codex session, review the new hook hash through `/hooks`, then
   ask Codex to run `wiki scheduler install` with the new plugin-owned Runtime
   CLI path. This refreshes the one machine scheduler.

The reinstall step is required when scheduling is enabled because the
LaunchAgent stores the absolute path to the installed plugin snapshot. v0.3.1
stores that path in one machine scheduler instead of one plist per wiki.

Start a new session after each install or update. If a hook definition changed,
review and trust its new hash through `/hooks`.

For development from a local checkout:

```bash
git clone https://github.com/toolboxmd/karpathy-wiki ~/dev/karpathy-wiki
cd ~/dev/karpathy-wiki
codex plugin marketplace add "$PWD"
codex plugin add karpathy-wiki@toolboxmd
```

Codex installs a snapshot from the marketplace. During local development,
refresh it by removing and adding the snapshot in your shell:

```bash
codex plugin remove karpathy-wiki@toolboxmd
codex plugin add karpathy-wiki@toolboxmd
```

Open a new session and ask Codex to run
`wiki scheduler install` through the new plugin-owned Runtime CLI. Scheduled
wikis keep their per-wiki activation mode across the plugin refresh.

Do not install duplicate copies of these skills under `~/.agents/skills` or
`~/.codex/skills`.

### Where the plugin and wiki data live

- Codex installs the plugin code into its managed plugin cache. The bundled
  `bin/wiki` is the executable, not a wiki-data directory.
- `~/.wiki-pointer` stores the selected main-wiki path. `~/wiki/` is the
  default, not a required location.
- `${XDG_CONFIG_HOME:-~/.config}/karpathy-wiki/wikis/<wiki-hash>/runtime.toml`
  stores the local trust record and provider settings. It is never read from a
  project checkout.
- `${XDG_CONFIG_HOME:-~/.config}/karpathy-wiki/workspaces/<workspace-hash>/runtime.toml`
  stores the one authoritative `project|main|both` selection and exact pinned
  targets. `wiki use` writes it atomically without editing tracked markers.
- Project-specific data lives in `<project>/wiki/` after project mode is
  configured.
- Removing or updating the plugin does not remove `~/.wiki-pointer`, a main
  wiki, or any project wiki.

### Uninstall from Codex

If scheduled activation is enabled, first ask Codex to run
`wiki scheduler uninstall --force` while the plugin is still installed, or run
`wiki scheduler disable <wiki-path>` for each scheduled wiki and then
`wiki scheduler uninstall`. Then remove the plugin:

```bash
codex plugin remove karpathy-wiki@toolboxmd
```

Optionally remove the configured marketplace as well:

```bash
codex plugin marketplace remove toolboxmd
```

These commands remove the Codex plugin bundle and optional marketplace source.
They intentionally preserve all wiki data and `~/.wiki-pointer`.

## Claude Code compatibility

Clone the repository, then register it with Claude Code by adding two entries
to `~/.claude/settings.json`: the marketplace pointer and the enabled-plugin
flag.

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

Replace `/Users/<you>/dev/karpathy-wiki` with the actual checkout path. Then
run `/reload-plugins` in a Claude Code session. Hooks, commands, and skills are
discovered from the plugin manifest. No global CLI symlink or manual hook wiring
is required.

Claude Code requires plugins to come from a registered marketplace, including
local-directory sources. The `extraKnownMarketplaces` entry declares this repo
as a single-plugin marketplace, backed by `.claude-plugin/marketplace.json`.

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

For Grok image ingestion, a JPEG or PNG named by the capture is sent in the
same provider request as the normal ingester instructions using native ACP
image content blocks. The adapter detects MIME type from the file signature,
not the extension, and records only byte count, MIME type, and SHA-256 in
invocation metadata. It never records image bytes or base64. A primary image is
followed by any repeatable `--attachment-path` values in capture order. The
adapter does not scan the wiki for images, and a declared image that is missing,
unsupported, unreadable, outside the primary evidence directory, or too large
for the process argument limit fails before Grok starts. There is no path-only
or `read_file` visual fallback. The ingester still retains every original under
the normal raw-evidence and manifest protocol.

Either way, one dispatcher atomically claims captures and enforces the configured per-wiki and per-profile ceilings. It can invoke Claude Code, Codex, or Grok with the exact configured model and reasoning effort. A heartbeat keeps live `.processing` work identifiable; technical failures retry up to `max_attempts`, rate limits wait without consuming attempts, and exhausted work moves to `.wiki-pending/failed/`. Semantic ingest is not reviewed by a second model on every run; quality is selected and measured through benchmarks.

### Detached-ingester trust boundary

Detached provider workers are trusted local automation in v0.3.0, not a
security boundary for hostile input. In particular, the Grok adapter uses
`--always-approve` so a headless ingest can complete without an interactive
permission prompt, and the dispatcher currently passes the launcher's full
environment to the provider process. A prompt-injected capture can therefore
request commands or reads available to that user account.

Only ingest captures and source files you trust. Do not enable unattended
ingest for collaborator-controlled repositories, downloaded prompt bundles, or
other untrusted content. A project-local Grok sandbox profile can follow the
current working directory and therefore works for either a project wiki or the
main wiki, but that is not a complete one-file fix: Grok must retain access to
its authentication state, the current semantic ingest protocol uses general
shell commands, and Grok's child-process network restriction is not enforced on
macOS. Provider-neutral least-privilege isolation is tracked in
[`ISSUES.md`](ISSUES.md).

## Per-machine ingest configuration

Tracked `.wiki-config` contains only wiki identity. Provider/model choices,
concurrency, activation mode, routing, auto-commit, and the explicit local trust
record live outside the checkout under the user's config home. A checkout cannot
enable its own provider execution by committing configuration files.

For a new general mixed-media wiki, the recommended Grok profile is Grok 4.6
Medium. No fallback profile is created unless the operator supplies one:

```bash
wiki config init-local <wiki> \
  --trust-workspace <canonical-project-or-wiki-root> \
  --default-provider grok --default-model grok-4.6 --default-effort medium \
  --max-processes 10 --dispatch-mode session_start
wiki config validate <wiki>
wiki config show <wiki>
```

Supported provider adapters in this release are `grok`, `claude`, and `codex`;
arbitrary explicit model IDs remain supported. As a convenience,
`--default-provider grok` without model or effort selects the built-in
`grok-4.6` Medium recommendation and keeps the stable `grok_medium` profile
name. An explicit `--default-model grok-4.5 --default-effort medium` pin remains
valid for historical reproduction and intentional text-only comparison.
`executable` is one executable name or absolute path, never an arbitrary shell
command. An executable that resolves inside the trusted project checkout is
rejected, including through a symlink or `PATH`.

Existing runtime files are user-owned and are never rewritten merely because
the plugin is installed, updated, or started. To opt one existing profile into
the new recommendation, run the explicit update command:

```bash
wiki config update-runtime <wiki> \
  --profile grok_medium --model grok-4.6 --reasoning-effort medium
```

The update changes only the named profile fields and preserves routing,
activation, fallback, trust, and every other profile. Inspect the result with
`wiki config show <wiki>` before draining queued work.

The recommendation is workload-specific. The
[2026-08-20 matched text-ingest benchmark](docs/benchmarks/2026-08-20-grok-4.5-vs-4.6-medium.md)
scored Grok 4.5 Medium at 95/100 and Grok 4.6 Medium at 94/100, which correctly
favored 4.5 for that text-oriented workload. The
[2026-08-21 multimodal benchmark](docs/benchmarks/2026-08-21-grok-4.6-native-acp-image-qualification.md)
later found that only Grok 4.6 Medium with native ACP images qualified among
the three tested image configurations. Grok 4.6 through `read_file` produced
one severe hallucination, and Grok 4.5 through `read_file` produced fourteen.
Grok 4.5 with native image input was not tested, so the newer benchmark does
not establish universal model superiority or isolate every model and transport
interaction.

For a chat-attached bundle, record image membership explicitly. The primary
evidence file establishes the allowed directory; additional image paths must
resolve below it and are delivered in the order shown:

```bash
wiki capture --title "Evidence bundle" --kind chat-attached \
  --suggested-action create --evidence-path /absolute/bundle/notes.md \
  --attachment-path /absolute/bundle/page-1.jpg \
  --attachment-path /absolute/bundle/page-2.png < capture-body.md
```

For an older tracked operational config, inspect the split before applying it:

```bash
wiki config migrate <wiki> \
  --trust-workspace <canonical-project-or-wiki-root> --dry-run
wiki config migrate <wiki> \
  --trust-workspace <canonical-project-or-wiki-root> \
  [explicit provider/model/effort options if needed]
```

This only migrates configuration layout. It does not move or rewrite wiki content.

If a previous plugin snapshot already created an ignored
`<wiki>/.wiki-config.local`, import it into the external trust store explicitly:

```bash
wiki config migrate-local <wiki> \
  --trust-workspace <canonical-project-or-wiki-root> --dry-run
wiki config migrate-local <wiki> \
  --trust-workspace <canonical-project-or-wiki-root>
```

The importer refuses a Git-tracked source. After a successful import, the old
checkout file remains as an inactive copy so the operator can inspect and remove
it deliberately.

## Activation modes

- `session_start`: no scheduler installation. SessionStart injects the loader and launches one bounded scan/tick.
- `scheduled`: `wiki scheduler install` installs one short-lived machine LaunchAgent. `wiki scheduler enable <wiki>` switches that trusted wiki to scheduled activation. `wiki scheduler disable <wiki>` switches it back to SessionStart. For compatibility, `wiki scheduler install <wiki>` installs the global scheduler and enables that wiki, while `wiki scheduler uninstall <wiki>` disables only that wiki and leaves the global scheduler installed.

The scheduled command does not keep a model resident in memory. The coordinator wakes, enumerates trusted `wikis/*/runtime.toml` records, offers at most one worker per due wiki, enforces 10 machine-wide workers and one worker per wiki, then exits. On non-macOS systems, use `wiki scheduler tick-all` from an external scheduler. CodexBar is optional: when usable it provides advisory preflight quota data; when absent, malformed, or timed out, the dispatcher continues in reactive mode using provider CLI results.

Design doc: [`docs/planning/karpathy-wiki-v2-design.md`](docs/planning/karpathy-wiki-v2-design.md). Implementation plan: [`docs/planning/2026-04-22-karpathy-wiki-v2.md`](docs/planning/2026-04-22-karpathy-wiki-v2.md).

## Status

**v0.3.1.** Codex is the qualified
primary interactive development host. Claude Code remains supported with its
existing automated hook coverage. Codex qualification includes recorded
interactive-host acceptance evidence; it does not claim equivalent automated
coverage for every Codex lifecycle path. Detached ingest supports Claude Code,
Codex, and Grok. Cursor, Copilot CLI, OpenCode, and Gemini loader paths remain
best-effort.

**What works today (v2.4 + 0.2.7 read protocol + 0.2.8 hardening + 0.3.1 runtime, routing, and provider automation):**
- Auto-capture + detached background ingest into a git-versioned wiki.
- Discovery-driven categories: any top-level `mkdir <name>/` at the wiki root creates a category. No code changes required.
- Per-directory `_index.md` tree (recursive); root `index.md` is a small MOC.
- Validator enforces `type: <plural-category>` matching `path.parts[0]` and rejects pages at depth ≥5.
- **Read-from-wiki protocol** (restored in 0.2.7 after v2.4 split silently dropped it). Iron Rule 4 forbids answering any user question without orientation; new `karpathy-wiki-read` skill defines a deterministic 6-step ladder (orient → candidate count → inline-read for ≤5 candidates / Explore subagent for 6+ / web search + capture-the-gap for cold results) with a hard cite contract on every wiki-grounded answer.
- Four-skill split with auto-loaded `using-karpathy-wiki` loader. Multi-platform SessionStart hook output: `hookSpecificOutput.additionalContext` for Claude Code, `additional_context` for Cursor, `additionalContext` for Copilot CLI / SDK-standard. Subagents and detached ingesters get only the surface they need.
- Single-authority workspace resolution at capture time via `wiki-resolve.sh`. `wiki use project|main|both` writes one private selection; `wiki init-main` establishes the main-wiki pointer used when selecting `main` or `both`.
- Raw-direct ingest: drop a file into `<wiki>/inbox/` and the next configured scan ingests it directly (no fabricated wrapper). Files accidentally dropped in `raw/` are recovered to `inbox/` under the manifest lock.
- Deep orientation (steps 1-9) in the ingester; issues surfaced to `.ingest-issues.jsonl` and the `wiki issues` / `wiki status` commands.
- Per-wiki `.ingest-runs.jsonl` for run history; status reports selective captures awaiting a decision, kept local, or promoted.
- Bounded provider-aware dispatcher, optional fallback profile, heartbeat, retries, failed queue, optional CodexBar preflight, one global scheduled coordinator, and mutually exclusive SessionStart/scheduled activation per wiki.
- Native Grok ACP image delivery for explicitly declared JPEG and PNG evidence, with fail-closed preflight and no `read_file` visual fallback.
- `wiki status` health report; `wiki capture` / `wiki ingest-now` / `wiki issues` / `wiki use` / `wiki config` / `wiki scheduler` / `wiki tick` / `wiki init-main` CLI.
- Tier-1 lint at every ingest: required frontmatter fields, link resolution, source existence, quality block ranges, type/path consistency.

**What's deferred (see `TODO.md`, `ISSUES.md`, and `IDEAS.md`):**
- Provider-neutral least-privilege isolation for detached ingesters: a minimal
  environment, deterministic privileged helpers, per-run path policy, isolated
  provider authentication, and macOS-specific containment tests.
- `bin/wiki orient` CLI shortcut for the read protocol's Step A (deferred — observe whether prose-only fix produces reliable behavior first).
- `allowed-tools` scoping on the four skills (deferred — orthogonal to read-protocol restoration).
- `wiki doctor` real implementation (smartest-model re-rate, orphan repair, tag-synonym consolidation).
- Stop-hook gate for turn-closure enforcement (`hooks/stop` is currently a stub).
- `.ingest.log` → `.ingest.jsonl` migration (dual-artifact pattern, scheduled for v2.5).
- Test coverage for non-Claude-Code platforms other than the qualified Codex
  plugin host (Cursor / Copilot CLI / OpenCode / Gemini).

The shipped surface is enough for daily personal use; rough edges remain. PRs welcome once the repo opens for external contributions.

## Tests

```bash
# Fast inner loop for the affected contract surface
bash tests/run-all.sh skill
bash tests/run-all.sh capture
bash tests/run-all.sh dispatcher

# Inspect a selection without executing it
bash tests/run-all.sh --list provider

# Deterministic final gate
bash tests/run-all.sh
bash tests/self-review.sh
```

Focused groups are `skill`, `capture`, `scanner`, `dispatcher`, `provider`,
`config`, `scheduler`, and `schema`. Tests that span multiple subsystems or
cover low-frequency operator flows are assigned to `full-only` and still run
from the default `full` gate. Use the smallest group that owns the changed
contract during development, then run the full gate once at the integration
boundary.

Real provider and interactive-host acceptance evidence is retained under
`tests/acceptance/` and is not part of the default deterministic loop.

## Credits

Based on Andrej Karpathy's [LLM Wiki](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) concept and [original tweet](https://x.com/karpathy/status/2039805659525644595).

The v2 SKILL.md is written in the style of, and uses techniques from, [obra/superpowers-skills](https://github.com/obra/superpowers-skills) (the `writing-skills`, `test-driven-development`, and `subagent-driven-development` skills in particular).

Built by [toolbox.md](https://toolbox.md).

## License

MIT
