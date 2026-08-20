# karpathy-wiki user manual (v0.3.0)

A short reference for karpathy-wiki v0.3.0. It covers setup, the common scenarios, and what the plugin handles automatically versus per-machine configuration.

For installation, see [README.md](README.md). For deferred work, see [TODO.md](TODO.md). For contributing, see [CLAUDE.md](CLAUDE.md).

## What changed in 0.3.0

- Added native Codex plugin packaging and qualified Codex as the primary interactive development host.
- Added the bounded provider-aware dispatcher with explicit Claude, Codex, and Grok profiles, retries, heartbeats, cooldowns, and per-wiki process limits.
- Moved provider settings and trust decisions into private per-machine runtime files instead of tracked repository configuration.
- Replaced competing routing and consent markers with one authoritative `project | main | both` workspace mode.
- Made `both` project-first: the original capture stays in the project wiki and only reusable knowledge is selectively promoted to the configured main wiki.
- Added pinned, retry-safe selective promotion plus a shared strict frontmatter parser for capture, completion, promotion, and status paths.
- Corrected headless Grok automation to use one non-interactive permission mode, avoiding 30-second `permission_cancelled` failures caused by combining `--always-approve` with `--permission-mode auto` in Grok CLI 1.0.5.
- Requalified Grok ingestion after the adapter fix. The matched semantic benchmark keeps Grok 4.5 Medium as the recommended Grok profile; see [the benchmark report](docs/benchmarks/2026-08-20-grok-4.5-vs-4.6-medium.md).

## Current dispatcher changes

- Ingest is bounded by `max_processes`; no SessionStart fan-out can exceed the per-wiki or per-profile ceiling.
- Claude Code, Codex, and Grok are supported as detached ingest providers. Every profile names an exact model and reasoning effort.
- `.wiki-config` is tracked structural identity only. Provider settings and local trust live under `.../wikis/<hash>/runtime.toml`; the one authoritative per-workspace `project|main|both` choice lives separately under `.../workspaces/<hash>/runtime.toml`.
- Automatic activation is mutually exclusive: `session_start` or `scheduled` (the macOS LaunchAgent adapter).
- Live work has a heartbeat. Technical failures retry deterministically, rate limits wait without consuming attempts, and exhausted captures move to `.wiki-pending/failed/`.
- CodexBar is optional advisory preflight. Without it, ingestion remains fully functional in reactive mode.

### Security boundary in v0.3.0

The detached ingester is trusted local automation. It is not isolated well
enough to process hostile or collaborator-controlled prompts unattended.

The Grok profile intentionally uses `--always-approve` because Grok CLI 1.0.5
otherwise cannot complete this headless workflow reliably. The dispatcher also
inherits the launcher's complete environment, and the ingest protocol currently
uses general shell commands for orientation, locking, validation, manifest
updates, Git operations, and completion. Treat every capture and referenced
source as trusted input.

A canary confirmed that one project `.grok/sandbox.toml` profile can resolve
the current working directory dynamically, allow the selected wiki plus a
trusted helper, and deny an unrelated test file. The same mechanism is portable
between arbitrary project wikis and the main wiki because each worker starts in
the selected wiki root. It is not sufficient as the only patch:

- denying `~/.grok/auth.json` prevents Grok from signing in;
- allowing only one helper breaks the current semantic ingest protocol, which
  still relies on multiple shell operations;
- Grok documents child-process network restriction as unavailable on macOS;
- path isolation alone does not remove secrets already present in the inherited
  environment.

For v0.3.0, keep unattended ingest limited to trusted personal wikis. If a
capture or evidence file may contain untrusted instructions, inspect it first
or leave automatic dispatch disabled. The provider-neutral containment work is
recorded in [TODO.md](TODO.md) and requires its own implementation and tests.

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
- **Historical note:** 0.2.7 could silently bootstrap `~/.wiki-pointer` from `$HOME/wiki/`. The current single-authority flow no longer changes pointer or routing state during capture; `wiki init-main` and `wiki use` own those choices explicitly.
- **Legacy `skills/karpathy-wiki/SKILL.md`** (DEPRECATED in v2.4, 549 lines) deleted.
- **Capture skill body-sufficiency dedup** — the section was duplicated across two scrolls pre-0.2.7.

Tests: 58/58 pass.

## One-time setup per machine

Wiki identity/routing and ingest execution are configured separately.

1. **`~/.wiki-pointer`** — single line of text. Either an absolute path (e.g. `/Users/you/wiki`) or the literal word `none` (means "no main wiki configured; project wikis only"). Created by:
   - `wiki init-main` (interactive prompt: "point at existing", "create at ~/wiki/", or "none").
   - Manual `echo "<path>" > ~/.wiki-pointer`.

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

If this workspace has no routing runtime when you run `wiki capture`, the resolver returns exit 11. `bin/wiki` either prompts once for `project|main|both` (interactive) or saves the body to `~/.wiki-orphans/` with the exact `wiki use` recovery command (headless).

## Per-workspace routing

Run `wiki use <mode>` once per directory you want a non-default capture flow in:

- `wiki use project` — initializes `./wiki/` with `role = "project"` if missing and selects it as the only target.
- `wiki use main` — pins the main wiki currently selected by `~/.wiki-pointer`; it does not create or delete a project wiki.
- `wiki use both` — pins both exact targets. The original capture goes only to `./wiki/`; after local ingest, reusable cross-project knowledge may produce one generalized capture in the main wiki. Project-specific knowledge stays local.

Each command writes one complete private runtime record outside the checkout. There is no consent file or second confirmation step. Tracked `fork_to_main`, tracked main paths, and legacy `.wiki-mode` files are ignored as routing authority and are not rewritten.

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

Iron Rule 4 fires. Agent loads `karpathy-wiki-read` and runs Steps A-F against the primary wiki in the workspace routing runtime. An unconfigured workspace falls through to the cold-no-wiki case.

The cold-no-wiki case has a known gap: Step F's gap-capture skips because there's nowhere to capture to. Tracked in [TODO.md](TODO.md) as a 0.2.8 candidate ("0.2.8: cold-no-wiki question path").

### Scenario 3 — `wiki capture` headless from a fresh directory

The resolver reads one private workspace runtime snapshot. Relevant exit codes:

- `0` — success
- `11` — workspace unconfigured (interactive prompt or headless orphan with `wiki use project|main|both` recovery)
- `13` — malformed or trust-mismatched routing runtime (orphan)
- `14` — a configured exact wiki target is incomplete (orphan)

Orphans land in `${WIKI_ORPHANS_DIR:-$HOME/.wiki-orphans}/<timestamp>-<slug>.md`. Body preserved; manual cleanup later.

### Scenario 4 — Drop a file into `<wiki>/inbox/`

Two firing paths:

- Next configured automatic scan: SessionStart or LaunchAgent scans `<wiki>/inbox/` for files older than 5 seconds (rsync/unzip-protection mtime defer) and emits a `capture_kind: raw-direct` capture in `.wiki-pending/` pointing at the absolute file path.
- `wiki ingest-now`: same scan + drain, runs immediately.

The selected provider/model ingester reads the file directly (no wrapper capture body), generates a wiki page, copies the file to `<wiki>/raw/<basename>` with a manifest entry, validates deterministic completion, and commits when enabled. If the file was accidentally dropped in `<wiki>/raw/`, the shared scanner recovers it to `<wiki>/inbox/` under the manifest lock.

### Scenario 5 — `wiki use project` in a new directory

Initializes `./wiki/` with `role = "project"` if missing, then atomically writes the private workspace routing runtime. It does not edit tracked workspace markers. Captures from `<cwd>` or any subdirectory write to `./wiki/.wiki-pending/`. Run `wiki config init-local ./wiki --trust-workspace "$(pwd)" ...` once on each machine that should ingest this project wiki.

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
