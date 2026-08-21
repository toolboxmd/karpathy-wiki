# Bounded, Provider-Aware Wiki Ingest Dispatcher — Design Specification

**Status:** Approved architectural specification; implementation and verification are tracked in the companion implementation plan.
**Date:** 2026-08-11
**Scope:** Ingest scheduling, concurrency, provider routing, rate-limit recovery, and worker liveness.
**Out of scope:** Changes to the semantic knowledge-writing rubric, corpus batching strategy, vector search, UI, notifications, and per-ingest model review.

> Historical configuration note, 2026-08-21: this specification records the
> earlier Grok 4.5 text-workload decision. New general mixed-media Grok
> configurations recommend Grok 4.6 Medium with native ACP image transport.
> The dated evidence and limitation are in the
> [multimodal benchmark follow-up](../benchmarks/2026-08-21-grok-4.6-native-acp-image-qualification.md).

## Document role and delivery sequence

This document fixes the architectural contract. It is not the executable implementation plan.

Delivery follows this sequence:

1. audit the current config, hook, spawn, and queue contracts;
2. approve this design specification;
3. write a separate file-level implementation plan with real RED tests, exact files, scoped diffs, migration steps, and verification commands;
4. execute that plan;
5. run the lifecycle and semantic benchmarks;
6. write a post-ship case study from actual commits and failures.

No existing user wiki configuration changes occur as part of this plugin implementation.

## Goal

Replace the current unbounded `SessionStart` fan-out with a small, deterministic dispatcher that:

- never exceeds the configured process limit;
- supports a benchmark-qualified default model and fallback model;
- offers two mutually exclusive activation modes: `session_start` and `scheduled`;
- keeps the existing file-based pending/processing/archive lifecycle;
- uses heartbeats to distinguish a long-running worker from a dead worker;
- uses CodexBar when available, but remains fully functional without it;
- reacts safely to provider rate limits and resumes work without retry storms.

## Evidence for the change

### Unbounded fan-out exists today

`hooks/session-start` currently scans every pending capture and starts one detached ingester for each file. A backlog of 500 captures can therefore attempt to start 500 processes.

### The stale-worker heuristic can reclaim live jobs

The current hook reclaims a `.md.processing` file when its modification time is more than ten minutes old. The frozen v0.2.8 benchmark included completed configurations lasting 766 seconds, 860 seconds, and 1,312 seconds. A valid ingest can therefore outlive the current stale threshold.

### Provider selection is opaque

`.wiki-config` currently contains one shell string under `platform.headless_command`. The dispatcher cannot reliably identify the provider, model, reasoning effort, fallback order, or matching CodexBar provider from that opaque string.

### Operational configuration is currently committed

The actual wiki-root `.wiki-config` is currently tracked by the wiki's Git repository and is not ignored by the generated `.gitignore`. An observed existing wiki contains a machine-specific absolute plugin path and Claude command. This mixes shared wiki identity with per-user execution settings.

The project-root `.wiki-config` may be only a local pointer to the real wiki, but it is a different file from the tracked config inside the wiki root. The new contract must preserve that distinction.

### Content quality and lifecycle completion are separate concerns

The v0.2.8 benchmark selected Grok 4.5 / medium as the best content result at 99/100, but its run left one already-ingested source in `inbox/`. Claude Sonnet / low scored 95/100 and finished cleanly. This plan therefore uses benchmark qualification for semantic quality and deterministic runtime checks for lifecycle completion. It does not add a second model that reviews every production ingest.

Benchmark evidence is external to this general-purpose plugin repository and
is not a runtime input. Only the resulting model-selection decision and the
reproducible dispatcher acceptance cases belong here.

## Approved decisions

| Area | Decision |
|---|---|
| Default author | User-selected benchmark-qualified profile; the plugin has no repository-wide model default |
| Fallback author | Optional user-selected profile; the plugin has no repository-wide fallback |
| Development test ingester | Codex Spark (`gpt-5.3-codex-spark`), medium reasoning; test-only and never an automatic production fallback |
| Concurrency | Configurable hard ceiling per wiki on the current machine; examples use 10 |
| Activation | Exactly one configured mode: `session_start` or `scheduled` |
| Scheduled implementation | Portable `wiki tick` core; the first scheduler adapter is a macOS LaunchAgent |
| SessionStart in scheduled mode | Loader only; no source scan, stale reclaim, or dispatch |
| Config ownership | Tracked `.wiki-config` keeps shared structural identity; ignored `.wiki-config.local` contains per-user execution settings |
| Legacy config | Explicit migration with backup and dry-run; no silent legacy fallback |
| Job state | Existing `.md`, `.md.processing`, archive, and failed directories |
| Liveness | Heartbeat updates the `.processing` modification time |
| Retry history | Existing `.ingest-runs.jsonl`; no per-job database or JSON state file |
| Usage monitoring | CodexBar is optional and defaults to auto-detection |
| No CodexBar | Reactive rate-limit handling from provider CLI results |
| Semantic review | Benchmark before production; no model review after each ingest |

## Configuration contract

The term "semantic configuration" is intentionally avoided. The new configuration is a structured set of profiles and scheduler settings.

### Shared structural config

The existing wiki-root `.wiki-config` remains the tracked marker used to identify and resolve the wiki. It retains only structural fields required by the existing topology contract, for example:

```toml
role = "project"
created = "2026-08-09"
```

Existing topology fields are preserved or migrated separately when required by the resolver. Provider commands, model choices, process limits, scheduler mode, usage monitoring, and machine-specific absolute paths must not remain in the tracked file.

### Per-user execution config

`.wiki-config.local` is created separately for every user or machine and is added to the wiki's generated `.gitignore`.

Illustrative `.wiki-config.local` using benchmark-qualified profiles:

```toml
[ingest]
dispatch_mode = "scheduled"
schedule_interval_seconds = 60
max_processes = 10
default_profile = "grok_medium"
fallback_profile = "sonnet_low"
max_attempts = 4
heartbeat_seconds = 30
stale_after_seconds = 600
usage_monitor = "auto"
rate_limit_retry_seconds = 900

[ingest.profiles.grok_medium]
provider = "grok"
model = "grok-4.5"
reasoning_effort = "medium"
max_processes = 10

[ingest.profiles.sonnet_low]
provider = "claude"
model = "sonnet"
reasoning_effort = "low"
max_processes = 2

[settings]
auto_commit = true
```

### Configuration rules

1. `.wiki-config` is the tracked structural marker; `.wiki-config.local` is the ignored per-user execution config.
2. Every user configures their own provider profiles, model choices, scheduler mode, and concurrency limits. Pulling the wiki repository must not import another user's execution settings.
3. `dispatch_mode` accepts only `session_start` or `scheduled`.
4. `max_processes` is the hard ceiling for this wiki on the current machine. A separate cross-wiki machine-wide ceiling is deferred until multiple concurrently scheduled wikis create evidence for it.
5. A profile-level `max_processes` is an optional provider-specific ceiling. Effective availability is bounded by both ceilings.
6. `default_profile` and `fallback_profile` must reference declared profiles.
7. The runtime builds provider commands as argument arrays from structured profile fields. It must not use `eval`, raw shell word splitting, or arbitrary command strings as the source of truth.
8. `usage_monitor = "auto"` uses CodexBar when its CLI is installed and returns usable data; otherwise it falls back to reactive mode without failing the wiki.
9. `usage_monitor = "off"` skips CodexBar entirely.
10. Rate-limit events do not consume `max_attempts`; provider exhaustion is not a capture failure.
11. Missing or invalid `.wiki-config.local` produces an actionable error with the exact initialization or migration command. It must not silently reuse `platform.headless_command`.

### Legacy migration

The public CLI adds:

```text
wiki config migrate <wiki> --dry-run
wiki config migrate <wiki>
wiki config init-local <wiki>
```

Migration behavior:

1. validate the legacy TOML before changing anything;
2. show the proposed structural and local config split in `--dry-run` mode;
3. create a timestamped backup before the real migration;
4. preserve the structural wiki identity in `.wiki-config`;
5. write provider, model, command, scheduler, and concurrency settings to `.wiki-config.local`;
6. ensure `.wiki-config.local` is ignored by Git;
7. remove the legacy operational fields only after the local file validates;
8. make `wiki status` report an explicit migration-required error while a legacy operational config remains unmigrated.

There is no silent compatibility fallback. A fresh checkout by another user runs `wiki config init-local <wiki>` and configures its own providers.

## Three-question framework audit

### Who invokes?

- The user explicitly invokes `wiki scheduler install`, `wiki scheduler uninstall`, configuration migration, and manual `wiki tick` commands.
- A harness adapter may invoke `wiki tick` on a supported lifecycle event.
- An installed scheduler adapter may invoke `wiki tick` periodically.
- The skill describes capture and ingest judgment. It does not implement concurrency, scheduling, or provider routing in prose.

### What fires on the rules?

| Invariant | Mechanism |
|---|---|
| Exactly one activation mode owns automatic queue work | Config validator plus invocation-source guard in `wiki tick` |
| No more than `max_processes` ingests run | Wiki-wide dispatcher lock, atomic claims, active-worker accounting, and concurrency tests |
| A live long-running ingest is not reclaimed | Worker heartbeat plus stale-reclaim predicate |
| Every spawn path respects the limit | One public dispatcher entrypoint and regression checks for bypass calls |
| Provider exhaustion does not create a retry storm | Provider-level cooldown reducer and circuit breaker |
| CodexBar is optional | Adapter availability check plus tested reactive fallback |
| Successful exit is not mistaken for completed lifecycle | Deterministic completion gate |
| Legacy command strings are not silently executed | Config migration gate and actionable status error |

### What is the token budget?

The dispatcher adds no queue or provider instructions to the SessionStart loader. The current loader baseline is 127 lines and 8,853 bytes. The detailed implementation plan records the before/after injected byte and token estimate and requires no growth attributable to dispatcher mechanics.

Whether SessionStart injection remains justified for the loader itself is a separate benchmarkable design question and is not bundled into this dispatcher change.

## Activation modes

Both modes call the same portable `wiki tick` implementation. They differ only in what starts a drain cycle.

### Portable core and adapters

- **Portable core:** config validation, queue scan, heartbeat recovery, slot calculation, provider selection, circuit breakers, claims, and worker launch.
- **Claude adapter:** SessionStart invokes `wiki tick --source session_start` only when the local mode is `session_start`; loader injection remains a separate responsibility.
- **macOS adapter:** LaunchAgent invokes `wiki tick --source scheduled` at the configured interval.
- **Manual adapter:** the user invokes `wiki tick --source manual` for diagnosis or recovery.

Future systemd, cron, or other harness adapters may invoke the same core without changing queue semantics.

### `session_start`

- Claude Code's `SessionStart` hook calls `wiki tick` on `startup`, `clear`, or `compact`.
- The mode requires no local scheduler installation.
- Once a drain cycle starts, worker completion can invoke another tick to refill freed slots.
- If all providers are rate-limited, automatic recovery waits for the next session start or a manual tick.

### `scheduled`

- A local LaunchAgent invokes `wiki tick` at the configured interval.
- `SessionStart` only injects the loader instructions. It must not scan sources, reclaim stale work, or dispatch workers.
- Provider reset and machine restart recovery do not depend on opening Claude Code.
- The scheduled command is short-lived; it checks state, fills slots, and exits. There is no permanently idle model process.

### Scheduler lifecycle commands

The public CLI should expose:

```text
wiki scheduler install <wiki>
wiki scheduler uninstall <wiki>
wiki scheduler status <wiki>
wiki tick <wiki>
```

- `install` creates or updates the local LaunchAgent and sets `dispatch_mode = "scheduled"` in `.wiki-config.local`.
- `uninstall` removes the LaunchAgent and sets `dispatch_mode = "session_start"` in `.wiki-config.local`.
- `status` compares the configured mode with actual scheduler state and reports mismatches.
- `tick` is the shared one-shot implementation and remains available for manual recovery.

Setting `dispatch_mode = "scheduled"` without an installed scheduler must be visible as an actionable warning in `wiki status`.

## Minimal file-based state model

No database or per-job state document is introduced.

```text
.wiki-pending/<capture>.md              pending
.wiki-pending/<capture>.md.processing   running
.wiki-pending/archive/YYYY-MM/...       completed
.wiki-pending/failed/...                exhausted technical retries
```

### Heartbeat

The worker wrapper updates the `.md.processing` modification time every `heartbeat_seconds` while the provider process is alive.

A processing capture is reclaimable only when:

1. its modification time is older than `stale_after_seconds`; and
2. no current worker has refreshed it during that interval.

Reclaim renames `.md.processing` back to `.md`. The next tick can claim it again.

### Run history

`.ingest-runs.jsonl` remains the durable execution history. Extend events with:

```json
{"capture":"example.md","status":"started","profile":"grok_medium","attempt":1}
{"capture":"example.md","status":"provider_rate_limited","provider":"grok","retry_after":"2026-08-11T14:15:00Z","source":"cli_error"}
{"capture":"example.md","status":"started","profile":"sonnet_low","attempt":1}
{"capture":"example.md","status":"completed","profile":"sonnet_low","attempt":1}
```

The dispatcher derives technical attempt counts and provider cooldowns from the existing append-only log. It must not create a new job-state store unless later evidence proves the log insufficient.

## `wiki tick` algorithm

1. Resolve the structural `.wiki-config`, then load and validate the per-user `.wiki-config.local`.
2. Acquire one wiki-wide dispatcher lock. If another tick holds it, exit successfully.
3. If the invocation source conflicts with `dispatch_mode`, perform no queue work.
4. Scan `inbox/` and `raw/` for drift and emit captures when this activation mode owns scanning.
5. Reclaim `.processing` captures whose heartbeat is stale.
6. Count fresh `.processing` captures.
7. Compute `available_slots = max_processes - active_processing_count`.
8. Resolve provider availability:
   - consult valid provider cooldown events;
   - consult CodexBar when `usage_monitor = "auto"` and data is available;
   - otherwise allow a reactive provider probe.
9. Select the default profile when available; otherwise select the fallback profile.
10. Atomically rename at most `available_slots` captures from `.md` to `.md.processing`.
11. Start one heartbeat-enabled worker wrapper per claimed capture.
12. Append structured start events to `.ingest-runs.jsonl`.
13. Release the dispatcher lock and exit.

Every path that starts an ingester must go through the dispatcher. `bin/wiki capture`, `SessionStart`, `wiki ingest-now`, and scheduled execution must not call the raw worker spawner in a way that bypasses the concurrency limit.

## Provider and rate-limit behavior

### With CodexBar

CodexBar is advisory preflight data:

- skip a provider known to be exhausted;
- use its exact `resetsAt` when available;
- choose the fallback before wasting a worker start;
- handle missing data per provider rather than failing the whole tick.

CodexBar must not be installed automatically and must not be required by initialization.

### Without CodexBar

The provider adapter classifies the actual CLI result:

1. Start the default profile normally.
2. If the provider reports a rate limit, stop the heartbeat and rename `.processing` back to `.md`.
3. Append a provider-level cooldown event to `.ingest-runs.jsonl`.
4. Use an exact reset time from the CLI response when available; otherwise use `rate_limit_retry_seconds`.
5. Trigger another tick so the fallback can claim the capture.
6. If both profiles are cooling down, start nothing until a later scheduled or manual tick.

The first rate-limit result opens a provider-level circuit breaker. Other pending captures must not each probe the same exhausted provider.

### Failure classification

Runtime classification is technical, not a semantic quality review:

- `completed`: provider exited successfully and deterministic lifecycle postconditions pass;
- `provider_rate_limited`: requeue without consuming a capture attempt;
- `transient_failure`: requeue and consume a technical attempt;
- `configuration_or_auth_failure`: do not create a retry storm; expose through status/logging;
- `failed`: move to `failed/` after `max_attempts` technical failures.

No Codex or other reviewer model runs after each completed ingest.

## Deterministic completion gate

A provider process exiting successfully is necessary but not sufficient. The wrapper must confirm only operational postconditions:

- the capture is no longer left as a live `.processing` file;
- the capture was archived on success;
- its run has a closing event;
- manifest and page validators pass for files touched by the run;
- no duplicate inbox source remains when the ingest contract requires removal.

These checks do not grade prose, knowledge completeness, or reasoning. Semantic quality is established by the benchmark before enabling a model profile for production.

## Implementation phases

These are specification-level delivery phases. Before implementation, they are expanded into a separate file-level plan with exact RED tests, files, diff boundaries, and verification commands. The repository requires tests before scripts; each new behavior starts red and ends green.

### Phase 1: Configuration and dispatcher contract

- [ ] Add regression pins for existing structural `.wiki-config` resolution behavior.
- [ ] Add failing tests for the tracked/local config split, Git ignore rule, migration dry-run, backup, and actionable legacy error.
- [ ] Add failing tests for structured profiles and invalid profile references.
- [ ] Add failing tests for `session_start` versus `scheduled` ownership.
- [ ] Add failing tests proving no more than `max_processes` captures are claimed.
- [ ] Implement config parsing and the one-shot dispatcher.
- [ ] Route every existing spawn path through the dispatcher.

### Phase 2: Heartbeat and recovery

- [ ] Add a test where a worker runs longer than the stale threshold while heartbeat remains fresh.
- [ ] Add a test where a dead worker stops heartbeat and its capture is reclaimed exactly once.
- [ ] Add concurrent tick tests proving the dispatcher lock prevents oversubscription.
- [ ] Implement the heartbeat wrapper and stale reclaim changes.

### Phase 3: Provider adapters and optional CodexBar

- [ ] Add fixtures for successful, rate-limited, transient-failure, and auth-failure CLI outputs.
- [ ] Add a missing-CodexBar test proving ingestion still starts.
- [ ] Add a malformed/partial-CodexBar-response test proving per-provider reactive fallback.
- [ ] Add a default-provider limit test proving the configured fallback receives the requeued capture; a Grok-to-Sonnet fixture may be used.
- [ ] Add a both-providers-limited test proving no retry storm occurs.
- [ ] Add a test-only Codex Spark profile using `gpt-5.3-codex-spark` with medium reasoning.
- [ ] Add a capability/entitlement preflight that fails clearly if Spark is unavailable; do not silently substitute another model.
- [ ] Implement provider adapters, auto-detection, cooldowns, and fallback routing.

### Phase 4: Scheduled mode

- [ ] Add tests for scheduler install, uninstall, status, and idempotent reinstall.
- [ ] Add a test proving `SessionStart` performs no queue work in `scheduled` mode.
- [ ] Add a test proving the scheduled tick resumes work after a simulated reset.
- [ ] Implement the macOS LaunchAgent adapter.
- [ ] Keep `session_start` available for machines without scheduler installation.

### Phase 5: Benchmark and production gate

- [ ] Run `bash tests/run-all.sh`.
- [ ] Record the required real clean-session transcript because `hooks/session-start` changes.
- [ ] Rerun the frozen semantic benchmark for any profiles proposed as recommended examples.
- [ ] Add concurrency/lifecycle benchmark cases without changing the frozen semantic fixtures.
- [ ] Run at least three end-to-end ingests with Codex Spark as the development test ingester. These runs validate the Codex adapter and lifecycle contract; they do not qualify Spark as a production fallback.
- [ ] Verify Grok retains full retrieval quality and finishes with a clean terminal state.
- [ ] Verify the configured fallback remains operationally clean.
- [ ] Show the complete diff and benchmark comparison to the user before any cross-project installation.

## Acceptance criteria

- A queue of 100 captures with `max_processes = 10` never has more than ten fresh `.processing` files or worker processes.
- Concurrent tick invocations never exceed the configured ceiling.
- A healthy worker can run beyond ten minutes without being reclaimed.
- A dead worker is reclaimed after its heartbeat expires.
- `scheduled` mode performs zero queue work from `SessionStart`.
- `session_start` mode works without a LaunchAgent.
- Scheduled mode resumes without opening Claude Code.
- The user-selected default and optional fallback profiles are honored without silent model or effort substitution.
- Missing or broken CodexBar data never blocks ingestion.
- The tracked `.wiki-config` contains no provider command, model selection, scheduler mode, concurrency limit, or machine-specific absolute path.
- `.wiki-config.local` is ignored, independently initialized per user, and required for automatic dispatch.
- An unmigrated legacy operational config fails with an exact migration command instead of running silently.
- Codex Spark completes the development E2E ingest cases but is not added to automatic production routing.
- Dispatcher work does not increase the SessionStart loader payload.
- A provider rate limit opens one provider-level cooldown instead of failing every pending capture.
- Rate-limit events do not exhaust capture attempts.
- No per-job database or JSON state file is added.
- No post-ingest semantic reviewer is added.
- The full repository test suite passes.
- The post-change semantic benchmark meets or exceeds the approved baseline for both qualified profiles.

## Explicit non-goals

- Do not build a dashboard, notification system, or remote scheduler.
- Do not add a database for queue state.
- Do not add per-ingest semantic grading.
- Do not add unbenchmarked providers to automatic fallback.
- Do not redesign corpus batching in this change.
- Do not rewrite the full ingest skill as part of dispatcher work.
- Do not keep both `SessionStart` and scheduled queue activation enabled simultaneously.

## Next step

After human review of this specification, write the separate file-level implementation plan. Deterministic dispatcher behavior uses real unit and integration RED tests; pressure scenarios are reserved for any changed SKILL.md judgment behavior. Existing user wikis are outside this implementation goal; migration behavior is verified only against disposable fixtures.
