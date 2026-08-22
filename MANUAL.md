# karpathy-wiki user manual (v0.3.2)

A short reference for karpathy-wiki v0.3.2. It covers setup, the common scenarios, and what the plugin handles automatically versus per-machine configuration.

For installation, see [README.md](README.md). For open work, see
[TODO.md](TODO.md), [ISSUES.md](ISSUES.md), and [IDEAS.md](IDEAS.md). For
shipped history, see [CHANGELOG.md](CHANGELOG.md). For contributing, see
[AGENTS.md](AGENTS.md).

## Current Grok recommendation (2026-08-21)

- New general mixed-media Grok configurations use `grok-4.6` with Medium
  reasoning effort and keep the stable profile name `grok_medium`.
- Grok image evidence is sent with the normal ingester instructions in one
  request as native ACP image content blocks. Supported formats are JPEG and
  PNG, detected from file signatures.
- `read_file` and path mentions are not qualified visual-evidence transports.
  A declared image that cannot be encoded natively fails before Grok starts.
- Existing runtime files remain unchanged until the operator runs an explicit
  profile update. No fallback profile is added automatically.

This updates the general mixed-media recommendation without erasing the earlier
text-ingest result. The [2026-08-20 matched text benchmark](docs/benchmarks/2026-08-20-grok-4.5-vs-4.6-medium.md)
scored Grok 4.5 Medium at 95/100 and Grok 4.6 Medium at 94/100, so 4.5 was the
correct recommendation for that tested workload. The later
[multimodal transport benchmark](docs/benchmarks/2026-08-21-grok-4.6-native-acp-image-qualification.md)
qualified only Grok 4.6 Medium with native ACP image transport. It did not test
Grok 4.5 with native images, so it does not prove that 4.6 is universally
superior or isolate every model-by-transport interaction.

## What changed in 0.3.2

- New Grok configurations recommend `grok-4.6` with Medium reasoning effort
  while retaining the stable `grok_medium` profile name. Explicit Grok 4.5
  pins remain valid, and no fallback profile is added automatically.
- Explicitly declared JPEG and PNG evidence is delivered to Grok with the
  normal ingester text in one `--prompt-json` request using native ACP image
  content blocks. MIME types come from file signatures, and multiple images
  retain capture order.
- Missing, unreadable, unsupported, escaped, or oversized declared images fail
  before provider launch. A file path or `read_file` result is not treated as
  proof that Grok received visual evidence. Text-only Grok ingestion continues
  to use the existing prompt-file transport.
- Existing user runtime configurations are not rewritten. Opt a named profile
  into the new recommendation explicitly with:

```bash
wiki config update-runtime <wiki> \
  --profile grok_medium --model grok-4.6 --reasoning-effort medium
```

## What changed in 0.3.1

- Replaced per-wiki LaunchAgents with one machine-wide macOS scheduler.
- Preserved independent per-wiki activation: `session_start` or `scheduled`.
- Enforced fixed concurrency limits across every launch source: 10 workers machine-wide and one worker per wiki.
- Added `wiki scheduler enable|disable|tick-all` and compatibility aliases for the v0.3.0 `install <wiki>` / `uninstall <wiki>` commands.

## What changed in 0.3.0

- Added native Codex plugin packaging and qualified Codex as the primary interactive development host.
- Added the bounded provider-aware dispatcher with explicit Claude, Codex, and Grok profiles, retries, heartbeats, cooldowns, and process limits.
- Moved provider settings and trust decisions into private per-machine runtime files instead of tracked repository configuration.
- Replaced competing routing and consent markers with one authoritative `project | main | both` workspace mode.
- Made `both` project-first: the original capture stays in the project wiki and only reusable knowledge is selectively promoted to the configured main wiki.
- Added pinned, retry-safe selective promotion plus a shared strict frontmatter parser for capture, completion, promotion, and status paths.
- Corrected headless Grok automation to use one non-interactive permission mode, avoiding 30-second `permission_cancelled` failures caused by combining `--always-approve` with `--permission-mode auto` in Grok CLI 1.0.5.
- Requalified Grok ingestion after the adapter fix. At the time, the matched
  text benchmark correctly kept Grok 4.5 Medium as the recommended profile; see
  [the dated benchmark report](docs/benchmarks/2026-08-20-grok-4.5-vs-4.6-medium.md).

## Current dispatcher changes

- Ingest is bounded by the global slot pool; no SessionStart, capture, manual tick, scheduled tick, promotion, or worker-completion refill can exceed 10 machine-wide workers or one worker per wiki.
- Claude Code, Codex, and Grok are supported as detached ingest providers. Every profile names an exact model and reasoning effort.
- `.wiki-config` is tracked structural identity only. Provider settings and local trust live under `.../wikis/<hash>/runtime.toml`; the one authoritative per-workspace `project|main|both` choice lives separately under `.../workspaces/<hash>/runtime.toml`.
- Automatic activation is mutually exclusive per wiki: `session_start` or `scheduled` (the macOS LaunchAgent adapter).
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
recorded in [ISSUES.md](ISSUES.md) and requires its own implementation and
tests.

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

3. **Trusted external runtime configuration for every wiki this machine ingests.** Choose the provider explicitly. Selecting Grok alone uses the current 4.6 Medium recommendation:

```bash
wiki config init-local <wiki> \
  --trust-workspace <canonical-project-or-wiki-root> \
  --default-provider grok --default-model grok-4.6 --default-effort medium \
  --max-processes 10 --dispatch-mode session_start
```

The shorter `--default-provider grok` form produces the same `grok_medium`
profile. Other providers still require an explicit model and effort. Grok 4.5
can be pinned explicitly for historical reproduction or intentional text-only
comparison. A fallback is optional and is created only when all fallback flags
are supplied. Validate or inspect the normalized result with:

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

Installing or starting a newer plugin also does not rewrite an existing
runtime. Opt into Grok 4.6 Medium for one existing profile explicitly:

```bash
wiki config update-runtime <wiki> \
  --profile grok_medium --model grok-4.6 --reasoning-effort medium
wiki config show <wiki>
```

This is the command to use later for Naturbiss after installing the updated
plugin. Do not run it until that separate repository session is ready for its
own one-image canary.

## Grok image evidence

An image placed directly in `<wiki>/inbox/` becomes the primary `evidence`
path of a raw-direct capture. A chat-attached evidence bundle can record
additional images explicitly:

```bash
wiki capture --title "Evidence bundle" --kind chat-attached \
  --suggested-action create --evidence-path /absolute/bundle/notes.md \
  --attachment-path /absolute/bundle/page-1.jpg \
  --attachment-path /absolute/bundle/page-2.png < capture-body.md
```

The primary image, when present, is delivered first. Additional images follow
the recorded `--attachment-path` order. Every additional path must resolve
inside the canonical directory of the primary evidence file. The adapter does
not search the wiki or attach neighboring files implicitly.

Before provider launch, every declared image is canonicalized, read, checked
for a JPEG or PNG signature, base64-encoded in memory, and placed in an ACP
content block shaped as `{type, data, mimeType}`. Normal invocation metadata
records only model, effort, transport, order, MIME type, byte count, and
SHA-256. It never stores image bytes or base64. Missing, unreadable,
unsupported, escaped, or oversized declared images fail clearly. Text-only
Grok captures continue through the existing prompt-file path.

Native delivery does not replace preservation. The detached ingester still
copies each original into normal raw storage, records manifest provenance, and
completes the normal validation and commit protocol.

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
wiki scheduler install           # installs or refreshes the one machine scheduler
wiki scheduler enable <wiki>     # switches one trusted wiki to scheduled mode
wiki scheduler status
wiki scheduler status <wiki>
wiki scheduler disable <wiki>    # switches one trusted wiki back to SessionStart
wiki scheduler tick-all          # runs one bounded coordinator sweep
```

For compatibility with v0.3.0, `wiki scheduler install <wiki>` installs the
global scheduler and enables that wiki. `wiki scheduler uninstall <wiki>`
disables only that wiki and leaves the global scheduler installed. Removing the
global scheduler while scheduled wikis remain enabled requires disabling them
first or passing the explicit force option.

On another operating system, invoke the portable command from your own scheduler:

```bash
wiki scheduler tick-all
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

Step A.0 sends an unconfigured workspace directly to Step F. After the answer,
the standard capture flow preserves the body and asks once whether routing
should be `project`, `main`, or `both`.

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

The selected provider/model ingester reads the file directly (no wrapper capture body), generates a wiki page, copies the file to `<wiki>/raw/<basename>` with a manifest entry, validates deterministic completion, and commits when enabled. For Grok JPEG or PNG evidence, the adapter also sends the image bytes natively in the same provider request. It does not rely on `read_file` as proof that the model saw the image. If the file was accidentally dropped in `<wiki>/raw/`, the shared scanner recovers it to `<wiki>/inbox/` under the manifest lock.

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
wiki scheduler ... # install, enable, disable, inspect, or tick the global LaunchAgent
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

See [TODO.md](TODO.md), [ISSUES.md](ISSUES.md), and [IDEAS.md](IDEAS.md).
Highlights:

- **Read-protocol follow-ups**: `wiki orient` CLI shortcut for Step A; `allowed-tools` scoping on the four skills.
- **`wiki doctor` real implementation**: smartest-model re-rate, orphan repair, tag-synonym consolidation.
- **`.ingest.log` → `.ingest.jsonl` migration** (dual-artifact pattern, scheduled for v2.5).
- **Loader-hook coverage outside Claude Code**: Cursor, Copilot CLI, OpenCode, and Gemini. Detached Codex/Grok/Claude provider adapters have deterministic coverage.
