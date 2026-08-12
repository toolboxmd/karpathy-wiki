# karpathy-wiki user manual (current development branch)

A short reference for the v0.2.8 base plus the provider-aware dispatcher now under development. It covers setup, the common scenarios, and what the plugin handles automatically versus per-machine configuration.

For installation, see [README.md](README.md). For deferred work, see [TODO.md](TODO.md). For contributing, see [CLAUDE.md](CLAUDE.md).

## Current dispatcher changes

- Ingest is bounded by `max_processes`; no SessionStart fan-out can exceed the per-wiki or per-profile ceiling.
- Claude Code, Codex, and Grok are supported as detached ingest providers. Every profile names an exact model and reasoning effort.
- `.wiki-config` is tracked structural identity. The local trust record plus providers, models, limits, activation, routing, and auto-commit live outside the checkout under `${XDG_CONFIG_HOME:-~/.config}/karpathy-wiki/`.
- Automatic activation is mutually exclusive: `session_start` or `scheduled` (the macOS LaunchAgent adapter).
- Live work has a heartbeat. Technical failures retry deterministically, rate limits wait without consuming attempts, and exhausted captures move to `.wiki-pending/failed/`.
- CodexBar is optional advisory preflight. Without it, ingestion remains fully functional in reactive mode.

## What changed in 0.2.8

12 hardening items from a 3-reviewer adversarial pass on v0.2.7. See `docs/specs/0.2.8.md` for the per-item RED/GREEN ladder and `docs/reviews/2026-05-06-v0.2.7-synthesis.md` for the decision record.

- **`bin/wiki capture --evidence-path <abs>`** — chat-attached and raw-direct captures now require an absolute path; the value lands verbatim in `evidence:` frontmatter (was hardcoded to the literal `"conversation"` for all kinds).
- **Resolver walk-up + cross-project leak fix** — `wiki-resolve.sh` now walks up from cwd to find the project's `.wiki-config`, while `wiki_root_from_cwd` stops at `$HOME` so a project subdir doesn't accidentally route to `~/wiki/`.
- **Validator gate in `wiki-commit.sh`** — moved the "every touched page must pass the validator" iron rule out of skill prose and into code. Commit refuses if any staged content page fails validation.
- **Capture-side resist-table** — restored to the loader (lost in the v2.4 split). Counters rationalizations like "the user will remember this" / "I'll capture it later" / "the file is already in a good place."
- **Spawn prompt fix** — points spawned ingester at `skills/karpathy-wiki-ingest/SKILL.md` (was ambiguous after the split deleted the legacy monolith).
- **Lock-window fix** in `_raw_recovery` — capture emit now happens inside the manifest lock alongside the raw → inbox move.
- **`wiki status` content-set filter** — `total pages` and below-3.5 quality counts now exclude `_index.md`, root index, raw/, and reserved dirs (was silently inflated by the unfiltered glob).
- **Schema-proposals dir created at init** — `wiki-init.sh` now creates `.wiki-pending/schema-proposals/` so the ingester's threshold-fire path doesn't crash on first use.
- **Doc rot cleanup** — README points at the actual `.claude-plugin/marketplace.json`; ingest skill says `python3` (not `bash`) for `wiki-manifest.py`; TODO.md refs to the deleted legacy skill annotated.

Tests: 58 + 8 RED tests pass.

## What changed in 0.2.7

- **Iron Rule 4** in the loader: `NO ANSWERING ANY USER QUESTION WITHOUT ORIENTING FIRST`. Restored after the v2.4 split silently dropped it.
- **New `karpathy-wiki-read` skill** with a deterministic 6-step ladder. No agent judgement at branch points.
- **Threshold 5/6** for inline-read vs Explore-subagent dispatch (≤5 candidates → inline; 6+ → subagent).
- **Three-platform JSON output** in `hooks/session-start`: `additional_context` for Cursor, `hookSpecificOutput.additionalContext` for Claude Code (unchanged), `additionalContext` for Copilot CLI / SDK-standard. Mirrors `obra/superpowers` v5.1.0.
- **Silent bootstrap of `~/.wiki-pointer`** from `$HOME/wiki/` when the resolver returns exit 10 AND `$HOME/wiki/.wiki-config` has `role = "main"` AND structural files exist. Pre-existing wiki users no longer hit a prompt or orphan on first capture after upgrade.
- **Legacy `skills/karpathy-wiki/SKILL.md`** (DEPRECATED in v2.4, 549 lines) deleted.
- **Capture skill body-sufficiency dedup** — the section was duplicated across two scrolls pre-0.2.7.

Tests: 58/58 pass.

## One-time setup per machine

Wiki identity/routing and ingest execution are configured separately.

1. **`~/.wiki-pointer`** — single line of text. Either an absolute path (e.g. `/Users/you/wiki`) or the literal word `none` (means "no main wiki configured; project wikis only"). Created by:
   - `wiki init-main` (interactive prompt: "point at existing", "create at ~/wiki/", or "none").
   - The 0.2.7 silent bootstrap (auto-fires on first capture if `~/wiki/` is structurally a valid main wiki).
   - Manual `echo "<path>" > ~/.wiki-pointer` (functionally identical to the bootstrap).

2. **A main wiki at the path the pointer references.** Structurally requires `.wiki-config` (with `role = "main"`), `schema.md`, `index.md`, and `.wiki-pending/` directory. Created by `wiki-init.sh main <path>`. Default path is `~/wiki/`.

3. **Trusted external runtime configuration for every wiki this machine ingests.** Create it explicitly; the plugin does not guess a provider or model:

```bash
wiki config init-local <wiki> \
  --trust-workspace <canonical-project-or-wiki-root> \
  --default-provider grok --default-model grok-4.5 --default-effort medium \
  --fallback-provider claude --fallback-model sonnet --fallback-effort low \
  --max-processes 10 --dispatch-mode session_start
```

The example profile choices are illustrative, not defaults. You may choose any supported provider (`grok`, `claude`, or `codex`), arbitrary model ID accepted by that CLI, and supported reasoning effort. Validate or inspect the normalized result with:

```bash
wiki config validate <wiki>
wiki config show <wiki>
```

For an older config that still contains an operational command, first preview and then explicitly apply the split:

```bash
wiki config migrate <wiki> --trust-workspace <canonical-project-or-wiki-root> --dry-run
wiki config migrate <wiki> --trust-workspace <canonical-project-or-wiki-root> \
  [provider/model/effort options if inference is impossible]
```

Configuration migration does not migrate, move, or rewrite wiki content.

If neither exists when you run `wiki capture`, the resolver returns exit 10. `bin/wiki` either prompts (interactive) or saves your body to `~/.wiki-orphans/` (headless).

## Per-directory config (optional)

Run `wiki use <mode>` once per directory you want a non-default capture flow in:

- `wiki use project` — writes a `role = "project-pointer"` marker to cwd and initializes `./wiki/` with `role = "project"` if missing. Captures from this dir flow to `./wiki/.wiki-pending/`.
- `wiki use main` — writes `.wiki-mode` with literal string `main-only` to cwd. Captures flow only to `~/wiki/`.
- `wiki use both` — writes `.wiki-config` with selective promotion enabled. The original capture goes only to `./wiki/`; after local ingest, reusable cross-project knowledge may produce one generalized capture in the main wiki. Project-specific knowledge stays local.

Without `wiki use`, interactive capture prompts for a mode. Headless capture preserves the body as an orphan and asks the user to choose; it never silently writes `.wiki-mode`.

## What "automatic" means

With a valid external trust and runtime record, the selected activation mode is automatic:

- SessionStart hook injects the loader skill (`using-karpathy-wiki/SKILL.md`) as `additionalContext`. The agent has Iron Rules 1-4, the trigger taxonomy, and the resist-table loaded in every conversation.
- In `session_start` mode, the hook starts exactly one short scan/tick. In `scheduled` mode, it is loader-only and never touches the queue.
- The bounded dispatcher fills only free slots. `wiki capture`, worker completion, and `wiki ingest-now` also request safe one-shot ticks through the same dispatcher.
- Files in `<wiki>/inbox/` are picked up by a configured scan and turned into `capture_kind: raw-direct` captures (no fabricated wrapper body needed).
- Files in `<wiki>/raw/` that are not in the manifest are recovered to `<wiki>/inbox/` under the manifest lock (raw-recovery rule).
- A wrapper heartbeat refreshes each live `.processing` capture. Dead stale leases are safely re-queued; a live provider is never duplicated merely because a heartbeat looks old.
- The fork-bomb guard short-circuits the hook when `WIKI_CAPTURE` or `CLAUDE_AGENT_PARENT` is set — detached ingesters and unrelated subagents cannot re-fire SessionStart dispatch.
- Iron Rule 4 fires for every user question. Agent loads `karpathy-wiki-read` and runs the 6-step ladder to orient before answering.

### Scheduled mode

On macOS, the built-in adapter is a LaunchAgent: a cron-like process that wakes, runs one short tick, and exits. It does not keep a model idle in memory.

```bash
wiki scheduler install <wiki>    # installs/updates and then switches mode
wiki scheduler status <wiki>
wiki scheduler uninstall <wiki>  # removes this wiki's agent and switches back
```

On another operating system, invoke the portable command from your own scheduler:

```bash
wiki tick <wiki> --source scheduled --scan
```

Set `dispatch_mode = scheduled` only when that external scheduler actually exists; `wiki status` reports a mismatch otherwise.

## The 6-step read ladder

Every step is deterministic. No agent judgement at branch points.

- **Step A — Orient.** Read `<wiki>/schema.md` + the relevant `<wiki>/<category>/_index.md`. Once per session; subsequent questions reuse the cached content (marginal cost near-zero).
- **Step B — Count signal-matching candidates** in `_index.md`. Branch on count: `0 → Step F`, `1-5 → Step C`, `6+ → Step E`.
- **Step C — Inline read** all 1-5 candidates. Sufficient to answer the question? `YES → cite + answer (done)`. `NO → Step D`.
- **Step D — Gap-fill via web search** for the specific claim the wiki did not cover. Cite both wiki and web. ALWAYS write a capture noting the gap (the wiki should grow toward questions it failed to answer fully).
- **Step E — Spawn an Explore subagent** for breadth questions (6+ candidates). Subagent runs the orient procedure inside its own context (no page-count cap). Returns synthesis with citations. Main agent uses the synthesis as the answer's basis. No word cap on the synthesis; target shape is "terse but complete."
- **Step F — Cold result** (zero candidates). Web search + always capture so the next session is not cold for this topic.

**Cite contract.** Every wiki-grounded answer cites the page paths it drew from. Uncited claims must be flagged "(from training data; not in wiki)" — the only allowed case for uncited claims.

## The 5 common scenarios

### Scenario 1 — Starting Claude in a fresh directory

The SessionStart hook runs in this order:

1. Subagent / ingester guard (exits if `WIKI_CAPTURE` or `CLAUDE_AGENT_PARENT` set).
2. Loader injection — emits `using-karpathy-wiki/SKILL.md` body as `additionalContext`.
3. Wiki resolution — walks up from cwd looking for `.wiki-config`. Fresh dir has none.
4. If a wiki is found and local mode is `session_start`, launch one bounded scan/tick. In `scheduled` mode, stop after loader injection.

Result: agent has the wiki rules loaded; cwd has no wiki to capture into yet.

### Scenario 2 — Asking a question

Iron Rule 4 fires. Agent loads `karpathy-wiki-read` and runs Steps A-F against the resolved wiki (`~/wiki/` if `~/.wiki-pointer` is set; else falls through to Step F as a "cold-no-wiki" case).

The cold-no-wiki case has a known gap: Step F's gap-capture skips because there's nowhere to capture to. Tracked in [TODO.md](TODO.md) as a 0.2.8 candidate ("0.2.8: cold-no-wiki question path").

### Scenario 3 — `wiki capture` headless from a fresh directory

The resolver checks `~/.wiki-pointer`, then cwd state. Five exit codes:

- `0` — success
- `10` — pointer missing/broken (silent-bootstrap fires if `$HOME/wiki/` valid; else interactive prompt OR headless orphan)
- `11` — cwd unconfigured (interactive prompts; headless preserves an orphan and asks for `wiki use project|main|both`)
- `12` — cwd config requires main but pointer is none/missing (orphan)
- `13` — cwd has BOTH `.wiki-config` AND `.wiki-mode` (conflict, orphan)
- `14` — half-built wiki (orphan)

Orphans land in `${WIKI_ORPHANS_DIR:-$HOME/.wiki-orphans}/<timestamp>-<slug>.md`. Body preserved; manual cleanup later.

### Scenario 4 — Drop a file into `<wiki>/inbox/`

Two firing paths:

- Next configured automatic scan: SessionStart or LaunchAgent scans `<wiki>/inbox/` for files older than 5 seconds (rsync/unzip-protection mtime defer) and emits a `capture_kind: raw-direct` capture in `.wiki-pending/` pointing at the absolute file path.
- `wiki ingest-now`: same scan + drain, runs immediately.

The selected provider/model ingester reads the file directly (no wrapper capture body), generates a wiki page, copies the file to `<wiki>/raw/<basename>` with a manifest entry, validates deterministic completion, and commits when enabled. If the file was accidentally dropped in `<wiki>/raw/`, the shared scanner recovers it to `<wiki>/inbox/` under the manifest lock.

### Scenario 5 — `wiki use project` in a new directory

Writes `<cwd>/.wiki-config` as a project pointer and initializes `./wiki/` with `role = "project"` if missing. From this point, captures from `<cwd>` (or any subdir) write to `./wiki/.wiki-pending/` instead of the main wiki. Run `wiki config init-local ./wiki --trust-workspace "$(pwd)" ...` once on each machine that should ingest this project wiki.

## CLI surface

```
wiki status        # health report
wiki capture       # write a chat-driven capture (agent's canonical entry)
wiki ingest-now    # drift-scan + drain inbox/ on demand
wiki issues        # show recent ingester-reported issues, grouped + severity-ordered
wiki use <mode>    # change per-cwd wiki mode (project|main|both)
wiki config ...    # create, migrate, validate, or show per-machine runtime config
wiki scheduler ... # install, uninstall, or inspect the macOS LaunchAgent
wiki tick ...      # one bounded dispatcher pass
wiki init-main     # bootstrap ~/.wiki-pointer (interactive)
wiki doctor        # deep lint + smartest-model re-rate (NOT YET IMPLEMENTED, exits 1)
wiki help          # show usage
```

`wiki status` keeps all content-health fields and adds runtime config state, dispatch mode, scheduler state, active ingests versus the hard ceiling, default/fallback profiles, provider cooldown reset times, stalled heartbeat count, failed captures, captures waiting for more detail, malformed run-history lines, and `codexbar`/`reactive`/`off` usage-monitor state.

Technical failures consume a bounded attempt. A provider rate limit does not. When `max_attempts` is exhausted, the capture moves to `<wiki>/.wiki-pending/failed/` for explicit inspection instead of hot-looping forever. Fix the source/configuration, move the capture back to `.wiki-pending/`, then run `wiki tick <wiki> --source manual`.

## Skill architecture (4 skills)

| Skill | Loaded by | Purpose |
|---|---|---|
| `using-karpathy-wiki` | SessionStart hook (auto, every session) | Loader: iron laws, triggers, resist-table, redirects to others |
| `karpathy-wiki-capture` | Main agent on-demand (when capture trigger fires) | Capture authoring: `wiki capture`, body floors, subagent-report flow |
| `karpathy-wiki-read` | Main agent on-demand (when ANY user question fires per Iron Rule 4) | Read protocol: 6-step ladder, cite contract |
| `karpathy-wiki-ingest` | Detached provider-neutral runtime ingester only | Page writing: 9-step deep orientation, role guardrail, validator, manifest, deterministic completion |

## What's deferred

See [TODO.md](TODO.md). Highlights:

- **0.2.8 candidates**: `wiki orient` CLI shortcut for read-protocol Step A; `allowed-tools` scoping on the four skills; cold-no-wiki question path nudge.
- **`wiki doctor` real implementation**: smartest-model re-rate, orphan repair, tag-synonym consolidation.
- **Stop-hook gate** for turn-closure enforcement (`hooks/stop` is currently a stub).
- **`.ingest.log` → `.ingest.jsonl` migration** (dual-artifact pattern, scheduled for v2.5).
- **Loader-hook coverage outside Claude Code**: Cursor, Copilot CLI, OpenCode, and Gemini. Detached Codex/Grok/Claude provider adapters have deterministic coverage.
