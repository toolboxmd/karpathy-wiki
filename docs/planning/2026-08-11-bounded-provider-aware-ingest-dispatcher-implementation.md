# Bounded, Provider-Aware Wiki Ingest Dispatcher — Implementation Plan

**Status:** Shipped and verified in commit [`877e659`](https://github.com/toolboxmd/karpathy-wiki/commit/877e659). No existing user wiki was a migration target or test fixture.
**Date:** 2026-08-11
**Design specification:** `docs/planning/2026-08-11-bounded-provider-aware-ingest-dispatcher-plan.md`
**Repository baseline:** `990cb20`
**Target release:** decide only after the implementation diff is complete; do not bump the plugin version during feature work.

## Goal

Replace every direct ingester spawn with one bounded dispatcher while preserving the existing file lifecycle:

```text
.wiki-pending/<capture>.md
    -> .wiki-pending/<capture>.md.processing
    -> .wiki-pending/archive/YYYY-MM/<capture>.md
    or .wiki-pending/failed/<capture>.md
```

The implementation must:

- enforce a hard per-wiki ceiling on concurrent ingests;
- support a structured default profile and optional fallback profile;
- support `session_start` and `scheduled` activation without running both automatic triggers;
- keep `.wiki-config` structural and tracked, and `.wiki-config.local` operational and ignored;
- keep CodexBar optional;
- maintain a heartbeat on every live `.processing` capture;
- recover technical failures without retry storms;
- use deterministic lifecycle checks, not a second model reviewing every ingest;
- remain usable by a person who does not have CodexBar installed;
- keep all user-facing repository files and generated documentation in English.

An illustrative local configuration, based on the completed benchmark, is:

```text
default profile:  Grok 4.5 / medium
fallback profile: Claude Sonnet / low
max ingests:      10
```

These are examples, not plugin defaults. Every user chooses their own default and optional fallback profiles. Codex Spark is a development and adapter-test ingester and is never added to a user's fallback chain automatically.

## Non-goals

- No database, daemonized model, web UI, notification service, or vector search.
- No semantic reviewer after each ingest.
- No automatic CodexBar installation.
- No migration or mutation of any existing user wiki in this goal.
- No machine-wide cross-wiki concurrency pool in this release.
- No systemd or Windows scheduler adapter in this release.
- No redesign of the content-quality rubric in this change.

## Execution result

The completed working tree now has one provider-aware dispatch path for Claude
Code, Codex, and Grok; split structural/local configuration; bounded global and
per-profile slots; reactive and CodexBar-assisted cooldowns; immediate fallback;
heartbeat and process-group cleanup; deterministic completion; explicit
`needs_more_detail` deferral; SessionStart/scheduled mode isolation; and a
macOS LaunchAgent adapter.

Verification completed on 2026-08-11:

- `bash tests/run-all.sh`: 90 test scripts passed, 0 failed;
- `bash tests/self-review.sh`: all repository checks passed;
- all shell entrypoints passed syntax checks and every Python script compiled;
- `git diff --check` passed;
- a disposable real Codex Spark medium acceptance completed cold, exact-
  duplicate, and augmentation cases;
- clean Claude sessions verified both activation modes, and a temporary real
  LaunchAgent completed and was fully removed;
- no existing wiki was discovered, inspected, migrated, or mutated.

The evidence-backed post-ship retrospective is now published as the
[provider-aware ingest case study](https://github.com/toolboxmd/building-agentskills/blob/a87d457/case-studies/2026-08-11-karpathy-wiki-provider-aware-ingest.md),
with a condensed benchmark evidence manifest in the same repository.

## Current baseline and pre-existing failure

Run before implementation:

```bash
cd /Users/lukaszmaj/dev/toolboxmd/karpathy-wiki
bash tests/run-all.sh
```

Observed on 2026-08-11:

```text
passed: 68
failed: 1
failing tests:
  - unit/test-wiki-status-issues.sh
```

The failure predates this feature. The test writes issue timestamps fixed at `2026-05-06`, while `wiki-status.sh` intentionally shows only the last 30 days. The fixture is now outside that window. Task 0 fixes only the test clock so the dispatcher begins from a green baseline.

## Runtime ownership boundaries

| Concern | Owner |
|---|---|
| What knowledge to write and how to link it | `skills/karpathy-wiki-ingest/SKILL.md` |
| Queue scan, claiming, limits, profile selection, retries | `scripts/wiki_dispatch.py` |
| Provider-specific argument arrays and error parsing | `scripts/wiki_providers.py` |
| Runtime config validation and migration | `scripts/wiki_config.py` |
| Inbox/raw drift detection and capture emission | `scripts/wiki-scan.sh` |
| Heartbeat and provider child lifecycle | `scripts/wiki_dispatch.py worker` |
| Validation, archive, run close, and commit at successful ingest end | `scripts/wiki-complete-ingest.sh` |
| macOS scheduled activation | `scripts/wiki_scheduler.py` |
| Loader injection | `hooks/session-start` |

The skill must not contain provider command construction, retry loops, concurrency arithmetic, or shell snippets for run-history locking. Those are deterministic mechanics and belong in code.

## Final configuration contract

### Tracked wiki identity: `.wiki-config`

For an actual wiki root, the tracked file contains structural identity only:

```toml
role = "project"
created = "2026-08-09"
```

The project-root `role = "project-pointer"` file is a separate routing marker and is not migrated as a wiki runtime config. `wiki config migrate` must reject a project pointer and print the resolved actual wiki path.

### Ignored per-user runtime: `.wiki-config.local`

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
usage_monitor_timeout_seconds = 5
rate_limit_retry_seconds = 900

[ingest.profiles.grok_medium]
provider = "grok"
executable = "grok"
model = "grok-4.5"
reasoning_effort = "medium"
max_processes = 10
usage_provider = "grok"

[ingest.profiles.sonnet_low]
provider = "claude"
executable = "claude"
model = "sonnet"
reasoning_effort = "low"
max_processes = 2
usage_provider = "claude"

[routing]
fork_to_main = false

[settings]
auto_commit = true
```

Rules:

1. `provider` is one of `claude`, `grok`, or `codex` in the first release.
2. `executable` is one executable name or absolute path. It is never parsed as a shell command.
3. The provider adapter creates an argument array. No `eval`, `shell=True`, or unquoted word splitting is allowed.
4. `fallback_profile` may be omitted. If present, it must name a declared profile different from `default_profile`.
5. `max_processes >= 1`; profile limits, when present, must also be positive.
6. `heartbeat_seconds >= 5` and `stale_after_seconds >= 3 * heartbeat_seconds`.
7. `dispatch_mode` is exactly `session_start` or `scheduled`.
8. `usage_monitor` is exactly `auto` or `off`.
9. Missing CodexBar data never makes configuration invalid.
10. Runtime config is validated before queue state changes.

### Stable error messages

Tests pin the actionable prefix and command, not incidental punctuation:

```text
wiki: runtime configuration missing: <wiki>/.wiki-config.local
Run: wiki config init-local <wiki>
```

```text
wiki: legacy ingest configuration detected in <wiki>/.wiki-config
Run: wiki config migrate <wiki> --dry-run
```

```text
wiki: invalid runtime configuration: ingest.max_processes must be an integer >= 1
```

`wiki status` still prints content health when runtime config is missing or legacy. It adds a runtime error section but does not hide the rest of the report.

## Minimal state contract

No durable per-job file is added.

Durable state remains:

- pending / processing / archive / failed capture paths;
- `.ingest-runs.jsonl` for append-only execution events.

Transient concurrency leases live under:

```text
.locks/ingest-slots/<slot-number>.lock
```

Each lease contains only `run_id`, capture basename, profile, wrapper PID, provider PID when known, and start time. It exists solely to make the limit atomic. It is removed when the worker exits and is ignored by Git with the rest of `.locks/`.

`max_processes` means active provider-agent ingests. The short-lived dispatcher and heartbeat loop are not separate ingest slots.

### Run event schema

Keep the existing `status` field so current status/fork readers remain compatible:

```json
{"run_id":"in-...","capture":"x.md","status":"started","profile":"grok_medium","provider":"grok","attempt":1,"at":"..."}
{"run_id":"in-...","capture":"x.md","status":"provider_rate_limited","profile":"grok_medium","provider":"grok","retry_after":"...","at":"..."}
{"run_id":"in-...","capture":"x.md","status":"transient_failure","profile":"grok_medium","attempt":1,"exit_code":1,"at":"..."}
{"run_id":"in-...","capture":"x.md","status":"completed","profile":"sonnet_low","attempt":1,"at":"..."}
```

- Rate-limit events do not consume `max_attempts`.
- Unknown non-zero provider exits are transient technical failures and do consume an attempt.
- A zero provider exit without successful lifecycle completion is a transient technical failure.
- After `max_attempts`, the capture moves to `.wiki-pending/failed/`.
- JSONL parsing skips blank/malformed lines and a partial final line, reports the count, and continues from valid events.

## Tick source policy

| Source | Allowed modes | May scan inbox/raw? | Purpose |
|---|---|---:|---|
| `session_start` | `session_start` only | yes | automatic Claude lifecycle adapter |
| `scheduled` | `scheduled` only | yes | automatic LaunchAgent adapter |
| `manual` | both | only with `--scan` | explicit diagnosis/recovery |
| `capture` | both | no | fill a free slot after a new capture |
| `worker_completion` | both | no | refill a slot after a worker exits |

The automatic sources are mutually exclusive. Manual, capture, and completion sources are safe one-shot events and may run in either mode.

## Provider command contract

The adapters build arrays equivalent to the already exercised benchmark commands. Exact flags are capability-tested against the installed CLI before a real integration run.

### Claude

```text
claude --plugin-dir <plugin-root> --model <model> --effort <effort>
       --permission-mode auto --no-chrome --no-session-persistence
       --output-format json -p <prompt>
```

### Grok

```text
grok --cwd <wiki> --model <model> --reasoning-effort <effort>
     --always-approve --permission-mode auto --max-turns 150
     --no-memory --output-format streaming-json --prompt-file <prompt-file>
```

### Codex

```text
codex --model <model> -c model_reasoning_effort="<effort>"
      --cd <wiki> --sandbox danger-full-access
      exec --ephemeral --ignore-user-config --skip-git-repo-check --json
      --output-last-message <path> -
```

The production implementation must use the currently supported placement of global versus `exec` options, verified by a preflight test. A provider capability failure is reported as configuration/capability failure; it must never silently substitute another model or effort.
`--ignore-user-config` prevents unrelated per-machine model options from making
the selected profile incompatible; Codex authentication remains available.

## CodexBar contract

When `usage_monitor = "auto"`:

1. If `codexbar` is absent, continue in reactive mode.
2. Invoke `codexbar usage --provider <usage_provider> --format json` with the configured short timeout.
3. Treat a provider as preflight-exhausted only when a returned active usage window explicitly reports exhaustion (for example `usedPercent >= 100`) or an explicit exhausted state.
4. Use `resetsAt` when present.
5. Do not block a provider merely because `pace.willLastToReset` predicts future exhaustion.
6. Empty, malformed, partial, unsupported-provider, timeout, or non-zero output means “monitor unavailable,” not “provider unavailable.”
7. The actual provider result remains authoritative and can open the circuit breaker.

The adapter must support usage windows under `primary`, `secondary`, and `tertiary` and ignore identity/account fields.

## Deterministic completion contract

The provider model does the semantic work, then calls one deterministic helper with `WIKI_ROOT`, `WIKI_CAPTURE`, and `WIKI_RUN_ID` already set by the worker.

`scripts/wiki-complete-ingest.sh` performs, in order:

1. verify the run/capture environment and that the capture is still `.processing`;
2. run the manifest validator;
3. archive the capture with `wiki_capture_archive`;
4. run the existing auto-commit helper, whose staged-page gate validates every changed content page;
5. if validation or commit fails after the move, restore the archived capture to its original `.processing` path and exit non-zero;
6. exit zero.

The worker wrapper, not the model or completion helper, appends the final `completed` event after it verifies the archive and provider exit. If the wrapper dies in the narrow interval after a valid archive/commit, the next dispatcher reconciliation uses the slot lease's `run_id` and expected archive path to append one recovered completion event before releasing the dead lease. The append operation is idempotent per `run_id + terminal status`.

The wrapper accepts success only when:

- the provider exits zero;
- the `.processing` file no longer exists;
- the expected archive basename exists;
- the wrapper can append and then re-read a matching `completed` event for `WIKI_RUN_ID`.

It does not grade prose, completeness, usefulness, or reasoning. Those remain benchmark responsibilities.

If the provider exits zero without calling the helper, the wrapper records `transient_failure`, requeues the capture, and consumes one attempt. This converts an ambiguous “clean process exit” into a deterministic lifecycle result without asking another model to review the ingest.

## Task sequence

Each task begins with the named test failing for the intended reason, implements the smallest behavior, runs its focused tests, and then runs the entire suite. Do not start a later task while the full suite has an unexplained new failure.

### Task 0 — Restore a green, time-stable baseline

**Files**

- Modify: `tests/unit/test-wiki-status-issues.sh`
- Do not modify: `scripts/wiki-status.sh`

**RED evidence**

```bash
bash tests/unit/test-wiki-status-issues.sh
# expected before fix: FAIL: status output missing broken-link count
```

**Implementation**

- Replace the fixed `reported_at` value with one UTC timestamp generated at test runtime.
- Keep all counts and assertions unchanged.
- Do not weaken or remove the 30-day production filter.

**GREEN**

```bash
bash tests/unit/test-wiki-status-issues.sh
bash tests/run-all.sh
```

**Expected result:** 69 test scripts pass, zero fail.

**Commit boundary:** test-only. Suggested message: `test: make status issue window time-stable`.

### Task 1 — Add split config reading and validation

**Files**

- Create: `scripts/wiki_config.py`
- Create: `tests/unit/test-runtime-config.sh`
- Modify: `scripts/wiki-lib.sh`
- Modify: `scripts/wiki-commit.sh`
- Modify: `scripts/wiki-init.sh`
- Modify: `tests/unit/test-config-read.sh`
- Modify: `tests/unit/test-init.sh`
- Modify: `tests/unit/test-wiki-init-rerun-idempotent.sh`
- Modify: `tests/unit/test-commit.sh`

**RED cases in `test-runtime-config.sh`**

1. A structural config plus valid local config validates and exposes typed JSON.
2. Missing local config emits the exact init command and exits non-zero for runtime operations.
3. A tracked config containing `[platform]` emits the exact migration command.
4. Invalid dispatch mode, profile reference, process count, heartbeat ratio, provider, and effort each fail with the dotted key in the message.
5. An executable path containing spaces is returned as one string, not split.
6. A local config with no CodexBar installation still validates.
7. A project-pointer marker is classified as `project-pointer`, not as an actual wiki root.
8. A fallback profile may be omitted; if supplied it must resolve and differ from default.

**Implementation**

- `scripts/wiki_config.py` uses Python 3.11 `tomllib` and stdlib only.
- Provide importable functions plus CLI subcommands `show`, `validate`, `init-local`, and `migrate` (migration behavior lands in Task 2).
- Add `wiki_structural_config_get` and `wiki_runtime_config_get` to `wiki-lib.sh`.
- Keep `wiki_config_get` as a structural-reader compatibility alias until all existing call sites migrate; do not let it fall through to the local file.
- Switch `wiki-commit.sh` from tracked `settings.auto_commit` to local `settings.auto_commit`.
- New `wiki-init.sh` output contains structural fields only, ensures `.wiki-config.local` is listed in `.gitignore`, and does not invent a provider profile.
- A newly initialized wiki is content-usable but runtime-unconfigured until `wiki config init-local` is run.
- If `.gitignore` already exists, append exactly one `.wiki-config.local` entry without rewriting unrelated user lines.

**REGRESSION-PIN**

- `wiki_root_from_cwd`, main pointer resolution, nested `wiki/` resolution, and project-pointer behavior remain unchanged in this task.
- Existing `wiki-config-read.py` remains available to old internal readers until the migration is complete.

**GREEN**

```bash
bash tests/unit/test-runtime-config.sh
bash tests/unit/test-config-read.sh
bash tests/unit/test-init.sh
bash tests/unit/test-wiki-init-rerun-idempotent.sh
bash tests/unit/test-commit.sh
bash tests/run-all.sh
```

**Commit boundary:** config split only. Suggested message: `feat: split structural and local wiki config`.

### Task 2 — Add explicit, atomic legacy migration

**Files**

- Modify: `scripts/wiki_config.py`
- Create: `tests/unit/test-runtime-config-migrate.sh`
- Modify: `bin/wiki`
- Modify: `scripts/wiki-resolve.sh`
- Modify: `scripts/wiki-use.sh`
- Modify: `tests/unit/test-wiki-resolve.sh`
- Modify: `tests/unit/test-wiki-use.sh`

**Public commands**

```text
wiki config init-local <wiki> [explicit profile/options]
wiki config migrate <wiki> --dry-run [explicit profile/options]
wiki config migrate <wiki> [explicit profile/options]
```

`init-local` and `migrate` accept structured options, never a raw command string:

```text
--default-provider grok --default-model grok-4.5 --default-effort medium
--fallback-provider claude --fallback-model sonnet --fallback-effort low
--max-processes 10 --dispatch-mode session_start|scheduled
```

With a TTY, `wiki config init-local <wiki>` asks for these values and shows the resulting file before writing it. In headless mode the structured flags are required and the error prints a complete example. It never silently chooses a provider merely because an executable happens to be installed.

**RED cases**

1. `--dry-run` prints both proposed files and mutates nothing.
2. Real migration creates a timestamped backup, validates the local temp file, atomically replaces both configs, and adds one ignore line.
3. A forced validation failure leaves the original config byte-identical and creates no partial local config.
4. Re-running a completed migration is a clear no-op.
5. A project-pointer path is rejected with the resolved nested wiki suggestion.
6. The current legacy Claude command shape is parsed only for migration display; it is never executed.
7. Unknown legacy commands require explicit structured profile options and do not guess.
8. `main = <absolute path>` is not copied into the tracked wiki-root config.
9. Wiki-root `fork_to_main` moves to local `[routing]`; the authoritative main path remains `~/.wiki-pointer`.
10. Project-root `role = "project-pointer"` routing behavior remains unchanged.
11. Malformed TOML, symlink escape, missing wiki markers, or an unwritable target fail before mutation.

**Atomicity**

- Write sibling temporary files.
- `fsync` and parse them.
- Create the timestamped backup.
- Replace with `os.replace`.
- If replacement of the second file fails, restore the first from backup and report the rollback.

**Resolver changes**

- For an actual `role = "project"` wiki root, read local `routing.fork_to_main` when available.
- A missing runtime config does not make the resolver lose the wiki path; it only prevents dispatch later.
- For a `role = "project-pointer"` marker, continue reading its own `wiki` and `fork_to_main` fields exactly as today.
- `wiki use both` on an actual wiki root updates local routing, not the tracked structural file.

**GREEN**

```bash
bash tests/unit/test-runtime-config-migrate.sh
bash tests/unit/test-wiki-resolve.sh
bash tests/unit/test-wiki-use.sh
bash tests/run-all.sh
```

**Commit boundary:** migration and routing only. Suggested message: `feat: add explicit local config migration`.

### Task 3 — Implement atomic dispatcher slots and bounded claims

**Files**

- Create: `scripts/wiki_dispatch.py`
- Create: `tests/unit/test-dispatcher-slots.sh`
- Create: `tests/integration/test-dispatcher-concurrency.sh`
- Modify: `bin/wiki`

**RED cases**

1. With 20 pending captures and `max_processes = 3`, one tick creates exactly three processing captures and three slot leases.
2. Ten concurrent ticks with `max_processes = 3` still create at most three processing captures/leases.
3. A tick that cannot acquire the dispatcher lock exits zero without queue changes.
4. A profile limit of two creates at most two leases for that profile even when the wiki ceiling is ten.
5. Claim ordering is deterministic by filename.
6. A capture disappearing between enumeration and claim is skipped safely.
7. Invalid config creates no lease and renames no capture.
8. A detached-worker spawn failure releases its lease and requeues its capture.
9. `session_start` source is a no-op in scheduled mode; `scheduled` is a no-op in session-start mode.
10. Manual/capture/completion sources work in both modes.
11. No runtime path can invoke a provider directly without a slot.

**Implementation algorithm**

1. Load and validate config.
2. Acquire `.locks/ingest-dispatch.lock` with Python `fcntl.flock`.
3. Enforce the tick-source policy.
4. Reconcile dead leases before counting capacity.
5. Count valid slot leases and per-profile leases.
6. Derive available slots.
7. Select a profile from currently available profiles (basic default/fallback selection now; cooldown intelligence lands in Task 6).
8. Atomically reserve a numbered slot directory/file.
9. Atomically rename one `.md` capture to `.md.processing`.
10. Start `wiki_dispatch.py worker` detached with an argument array.
11. Write worker PID into the lease before releasing the dispatcher lock.
12. Release the lock and exit quickly.

Use no database and no global daemon.

**CLI**

```text
wiki tick [<wiki>] --source session_start|scheduled|manual|capture|worker_completion [--scan]
```

An explicit path must resolve to an actual wiki root. With no path, use the existing resolver.

**GREEN**

```bash
bash tests/unit/test-dispatcher-slots.sh
bash tests/integration/test-dispatcher-concurrency.sh
bash tests/run-all.sh
```

**Commit boundary:** queue cap only; provider fixtures, not real CLIs. Suggested message: `feat: bound wiki ingest dispatch`.

### Task 4 — Add worker heartbeat, run log, retries, and deterministic completion

**Files**

- Modify: `scripts/wiki_dispatch.py`
- Create: `scripts/wiki-complete-ingest.sh`
- Create: `tests/unit/test-worker-heartbeat.sh`
- Create: `tests/unit/test-ingest-run-events.sh`
- Create: `tests/unit/test-complete-ingest.sh`
- Create: `tests/integration/test-worker-lifecycle.sh`
- Create: `tests/red/RED-provider-neutral-ingester.md`
- Modify: `skills/karpathy-wiki-ingest/SKILL.md`
- Modify: `tests/unit/test-ingest-skill.sh`
- Create: `tests/unit/test-ingest-skill-provider-neutral.sh`

**Pressure scenario before the skill edit**

Document the observed frozen-skill failure in which Codex Spark followed the phrase “detached `claude -p` ingester” and launched Claude during an ingest. Preserve the benchmark artifact path and hashes. This is evidence that provider-specific role wording changes agent behavior; it is not a hypothetical compliance rewrite.

**RED cases**

1. A live fake provider keeps `.processing` mtime fresh across more than one stale threshold used by the test clock.
2. A dead wrapper with stale heartbeat and dead provider PID is reclaimed and requeued once.
3. A stale heartbeat whose recorded wrapper/provider PID is still alive is not duplicated; status records `heartbeat_stalled` for manual attention.
4. A successful provider that does not call the completion helper is classified as transient and requeued.
5. The completion helper validates, archives, and commits; the wrapper appends exactly one matching completed event after verifying those effects.
6. Calling the completion helper twice is idempotent: no second archive or closing event.
7. JSONL appends from ten workers remain one valid JSON object per line on macOS and Linux.
8. A malformed historical line or truncated final line does not prevent later valid events from being read.
9. Rate-limit events do not increment attempt count.
10. Transient failures increment count; the configured last attempt moves the capture to `failed/`.
11. Worker exit always releases its slot lease, including signal/non-zero paths.
12. Worker completion triggers one refill tick without scanning sources.

**Worker loop**

- Start the provider with `subprocess.Popen(argv, shell=False)`.
- Store the provider PID in the slot lease.
- Poll at `heartbeat_seconds`; on every poll, call `os.utime(processing)`.
- On exit, classify the result, apply the completion gate, append an event, requeue/fail when required, release the slot, and invoke a one-shot `worker_completion` tick.
- The wrapper, not a model, owns start/failure events and heartbeat.

**Skill change boundary**

- Replace Claude-specific role wording with provider-neutral “detached wiki ingester.”
- Remove the model-authored spawned/closing JSONL shell snippets.
- State that the runtime wrapper owns heartbeat and run history.
- Replace direct archive/commit steps with one call to `scripts/wiki-complete-ingest.sh`.
- Do not change page selection, source attribution, deduplication, linking, quality rubric, or content-writing instructions in this feature.

**GREEN**

```bash
bash tests/unit/test-worker-heartbeat.sh
bash tests/unit/test-ingest-run-events.sh
bash tests/unit/test-complete-ingest.sh
bash tests/unit/test-ingest-skill.sh
bash tests/unit/test-ingest-skill-provider-neutral.sh
bash tests/integration/test-worker-lifecycle.sh
bash tests/run-all.sh
```

**Commit boundary:** lifecycle only. Suggested message: `feat: make ingest lifecycle deterministic`.

### Task 5 — Add safe provider adapters and technical error classification

**Files**

- Create: `scripts/wiki_providers.py`
- Create: `tests/unit/test-provider-adapters.sh`
- Create: `tests/unit/test-provider-classification.sh`
- Create: `tests/fixtures/provider-results/claude/`
- Create: `tests/fixtures/provider-results/grok/`
- Create: `tests/fixtures/provider-results/codex/`
- Modify: `scripts/wiki_dispatch.py`

**RED cases**

1. Claude, Grok, and Codex profiles produce exact argument arrays with model and effort in their supported positions.
2. Wiki/plugin paths containing spaces remain single argv elements.
3. No adapter output contains a shell command string.
4. Unknown provider/model/effort or missing executable returns configuration/capability failure before claim.
5. A requested model or effort is never silently replaced.
6. Sanitized real fixtures classify 429/quota/usage-limit errors as `provider_rate_limited`.
7. Auth/login/key errors classify as `configuration_or_auth_failure`.
8. Unknown non-zero results classify as `transient_failure`.
9. Exit zero plus ordinary source text mentioning “rate limit” is not misclassified.
10. Structured error fields are inspected; ordinary final-answer text is not used as the primary classifier.
11. Prompt and output paths are created under the wiki runtime area and handle spaces safely.

**Implementation**

- Use provider-specific builders returning `list[str]` plus explicit environment additions.
- Preserve `HOME`, `PATH`, and provider auth environment without printing secrets.
- Set `WIKI_ROOT`, `WIKI_CAPTURE`, `WIKI_RUN_ID`, `WIKI_PLUGIN_ROOT`, and the fork-bomb guard.
- Write provider stdout/stderr to run-specific files under `.locks/ingest-runs/<run_id>/`; remove them on clean success, retain them on failure for diagnosis. This directory is transient and Git-ignored.
- Redact obvious token/key values from retained diagnostic snippets.
- Capability preflight uses `--help`/version and a minimal provider invocation only in integration tests, never on every production tick.

**GREEN**

```bash
bash tests/unit/test-provider-adapters.sh
bash tests/unit/test-provider-classification.sh
bash tests/run-all.sh
```

**Commit boundary:** provider adapters only. Suggested message: `feat: add structured ingest provider adapters`.

### Task 6 — Add optional CodexBar preflight and provider circuit breakers

**Files**

- Modify: `scripts/wiki_providers.py`
- Modify: `scripts/wiki_dispatch.py`
- Create: `tests/unit/test-codexbar-optional.sh`
- Create: `tests/unit/test-provider-cooldowns.sh`
- Add sanitized fixtures: `tests/fixtures/codexbar/`

**RED cases**

1. No `codexbar` executable: default provider is attempted reactively.
2. `usage_monitor = off`: CodexBar is never invoked even if installed.
3. Valid Grok `primary.usedPercent = 100` with `resetsAt` skips Grok until reset and selects Sonnet.
4. `usedPercent = 76` plus `pace.willLastToReset = false` does not skip Grok.
5. Exhaustion in any active primary/secondary/tertiary window blocks that provider.
6. Empty Claude usage data degrades to reactive mode.
7. Malformed JSON, timeout, non-zero exit, missing provider, or partial fields degrade to reactive mode.
8. A real provider rate-limit event opens a provider-level breaker visible to every pending capture.
9. The breaker expires at exact `retry_after`; fallback fills the released slot without probing the exhausted provider again.
10. If both profiles are cooling down, no worker starts and pending captures remain unchanged.
11. Rate-limit requeue does not consume a capture attempt.
12. Config/auth failures use a bounded cooldown and appear in status; they do not hot-loop.

**Implementation**

- Run CodexBar outside the dispatcher lock when possible, cache one result for the current tick, then reacquire/validate queue state before claims.
- Bound the command by `usage_monitor_timeout_seconds`.
- Map provider names explicitly (`grok -> grok`, `claude -> claude`, `codex -> codex`) with optional `usage_provider` override.
- Derive breaker state from `.ingest-runs.jsonl`; do not create a second durable state store.
- The latest valid reset/cooldown event wins; expired events require no cleanup rewrite.

**GREEN**

```bash
bash tests/unit/test-codexbar-optional.sh
bash tests/unit/test-provider-cooldowns.sh
bash tests/run-all.sh
```

**Commit boundary:** advisory monitor and breakers only. Suggested message: `feat: add optional provider usage preflight`.

### Task 7 — Extract source scanning and route every entrypoint through `wiki tick`

**Files**

- Create: `scripts/wiki-scan.sh`
- Modify: `hooks/session-start`
- Modify: `bin/wiki`
- Modify: `scripts/wiki-ingest-now.sh`
- Delete: `scripts/wiki-spawn-ingester.sh`
- Modify: `tests/unit/test-inbox-drift-scan.sh`
- Modify: `tests/unit/test-raw-recovery.sh`
- Modify: `tests/unit/test-raw-recovery-no-duplicate-captures.sh`
- Modify: `tests/unit/test-mtime-defer.sh`
- Replace: `tests/unit/test-spawn-ingester.sh` with `tests/unit/test-no-direct-spawn-path.sh`
- Modify: `tests/unit/test-spawn-prompt-references-current-skill.sh`
- Modify: `tests/unit/test-wiki-ingest-now.sh`
- Modify: `tests/unit/test-wiki-capture-cli.sh`
- Modify: `tests/unit/test-wiki-capture-silent-bootstrap.sh`
- Modify: `tests/integration/test-end-to-end-plumbing.sh`
- Modify: `tests/integration/test-session-start.sh`
- Modify: `tests/integration/test-leg2-end-to-end.sh`
- Modify: `tests/integration/test-leg3-end-to-end.sh`

**RED cases**

1. Scan behavior is identical when invoked by `session_start`, scheduled tick, or `ingest-now --scan`.
2. SessionStart in scheduled mode emits the loader but does not scan, reclaim, or dispatch.
3. SessionStart in session-start mode invokes exactly one tick.
4. `wiki ingest-now` calls manual tick with scan and never invokes the SessionStart hook.
5. `wiki capture` writes the capture first, then calls source `capture`; if runtime config is absent, the capture remains and the CLI prints the actionable warning.
6. Worker completion cannot trigger a source scan.
7. Existing concurrent raw-recovery and deterministic drift-filename guarantees remain green.
8. A source filename containing spaces remains safe.
9. Runtime code contains no call to `wiki-spawn-ingester.sh`, `claude -p`, `grok`, or `codex` outside the provider adapter.
10. The deleted spawner has no live skill/runtime references.

**Implementation**

- Move the current drift, inbox, manifest-lock, raw-recovery, and capture-emission functions from the hook to `wiki-scan.sh` with one explicit wiki-root argument.
- Keep the SessionStart loader JSON generation byte-for-byte unchanged.
- The hook checks the local mode; in scheduled mode it stops after loader injection.
- The dispatcher invokes the scanner only for source/mode combinations allowed by the table.
- `wiki ingest-now` becomes a small resolver plus `wiki tick --source manual --scan` adapter.
- Remove direct spawn code rather than retaining a bypassing legacy implementation.

**Loader budget gate**

Record before and after:

```bash
wc -l -c hooks/session-start skills/using-karpathy-wiki/SKILL.md
```

Dispatcher mechanics must add zero bytes to injected loader context.

**GREEN**

```bash
bash tests/unit/test-no-direct-spawn-path.sh
bash tests/unit/test-inbox-drift-scan.sh
bash tests/unit/test-raw-recovery.sh
bash tests/unit/test-raw-recovery-no-duplicate-captures.sh
bash tests/unit/test-mtime-defer.sh
bash tests/unit/test-wiki-ingest-now.sh
bash tests/unit/test-wiki-capture-cli.sh
bash tests/integration/test-end-to-end-plumbing.sh
bash tests/integration/test-session-start.sh
bash tests/run-all.sh
```

**Commit boundary:** entrypoint convergence only. Suggested message: `refactor: route ingest entrypoints through dispatcher`.

### Task 8 — Add the macOS LaunchAgent scheduler adapter

**Files**

- Create: `scripts/wiki_scheduler.py`
- Create: `tests/unit/test-scheduler-plist.sh`
- Create: `tests/integration/test-scheduler-lifecycle.sh`
- Modify: `bin/wiki`

**Public commands**

```text
wiki scheduler install <wiki>
wiki scheduler uninstall <wiki>
wiki scheduler status <wiki>
```

**RED cases**

1. Generated plist contains an absolute `bin/wiki`, real wiki path, `tick`, `--source scheduled`, `--scan`, and configured `StartInterval`.
2. Label is stable and collision-resistant from the canonical wiki path.
3. Paths with spaces are separate plist array values.
4. Install is idempotent and updates a changed interval.
5. Install switches local mode to scheduled only after plist validation and successful bootstrap.
6. Failed bootstrap leaves the prior config mode unchanged.
7. Uninstall bootouts/removes only the exact wiki's LaunchAgent and switches mode to session-start only after success.
8. Missing `launchctl` prints a clear macOS-only adapter error and leaves config unchanged.
9. Status detects configured-scheduled-but-not-installed and installed-but-configured-session-start mismatches.
10. Tests use a fake `launchctl` and temporary `HOME`; they never modify the real user LaunchAgents.

**Implementation**

- Use `plistlib`, not hand-written XML.
- Store at `~/Library/LaunchAgents/com.toolboxmd.karpathy-wiki.<path-hash>.plist`.
- Use current GUI domain `gui/<uid>`.
- Scheduled command is short-lived; no model stays idle in memory.
- Do not add a second SessionStart drain path.
- Users on other systems can invoke the portable `wiki tick --source scheduled --scan` from their scheduler manually; automatic systemd support is deferred.

**GREEN**

```bash
bash tests/unit/test-scheduler-plist.sh
bash tests/integration/test-scheduler-lifecycle.sh
bash tests/run-all.sh
```

**Commit boundary:** scheduler adapter only. Suggested message: `feat: add macOS scheduled ingest adapter`.

### Task 9 — Expose operational state without a dashboard

**Files**

- Modify: `scripts/wiki-status.sh`
- Modify: `tests/unit/test-status.sh`
- Modify: `tests/unit/test-wiki-status-issues.sh`
- Modify: `MANUAL.md`
- Modify: `README.md`
- Modify: `bin/wiki` help

**Status additions**

```text
runtime config: configured | missing | migration required | invalid
dispatch mode: session_start | scheduled
scheduler: installed | not installed | mismatch | n/a
active ingests: N / max_processes
profiles: default=<name>, fallback=<name|none>
provider cooldowns: <profile until timestamp> | none
stalled heartbeat: N
failed captures: N
usage monitor: codexbar | reactive | off
```

**RED cases**

1. Content status still renders when local config is missing.
2. Legacy config shows migration required and the exact command.
3. Scheduled/configured without plist shows an actionable warning.
4. Active slot count and stale heartbeat count are accurate.
5. Malformed JSONL lines are counted but do not crash status.
6. Missing CodexBar displays `reactive`, not an error.
7. Cooldown reset timestamps are visible.
8. Existing content, issue, fork-asymmetry, and quality sections remain unchanged.

**Documentation**

- Explain the two modes in user language.
- Explain that LaunchAgent is the macOS cron-like adapter.
- Show init-local and migration commands.
- State that `.wiki-config.local` is per user/machine and ignored.
- Explain that CodexBar is optional.
- Explain failed captures and safe retry behavior.
- Do not document implementation internals as skill instructions.

**GREEN**

```bash
bash tests/unit/test-status.sh
bash tests/unit/test-wiki-status-issues.sh
bash tests/run-all.sh
```

**Commit boundary:** visibility/docs only. Suggested message: `docs: expose ingest dispatcher operations`.

### Task 10 — Real provider and concurrency acceptance tests with Codex Spark

**Files**

- Create: `tests/integration/test-codex-spark-ingest.sh`
- Create: `tests/integration/test-dispatcher-refill.sh`
- Create: `tests/acceptance/dispatcher/` run artifacts (Git-ignore raw provider output if it can contain local paths or account data; retain sanitized summaries)

**Preflight**

1. Verify `gpt-5.3-codex-spark` is available.
2. Verify each requested reasoning effort explicitly; never substitute.
3. Verify the current Codex CLI global/`exec` option placement.
4. Use a temporary clone of the test wiki and temporary runtime config.
5. Add the neutral benchmark guard: the tested model must perform the ingest itself and must not delegate to another model or agentic CLI.

**Acceptance runs**

- At least three independent Spark ingests through the actual dispatcher and completion helper.
- One successful cold ingest.
- One exact-duplicate ingest.
- One related augmentation.
- One test with a path containing spaces.
- One `max_processes = 2` refill test with more than two pending captures.
- One fake rate-limit/default-to-fallback lifecycle; do not intentionally exhaust a paid provider.
- One no-CodexBar environment.

**Assertions**

- Requested Spark model and effort are present in raw command metadata.
- No nested Claude/Grok/Codex CLI invocation occurs inside the tested ingester.
- Active slots never exceed the configured ceiling.
- Every completed run archives exactly once and has one closing event.
- No processing/slot leaks remain.
- Duplicate input does not create duplicate content pages.
- The full repository test suite remains green afterward.

These tests qualify the Codex adapter lifecycle. They do not promote Spark into the production author chain without the separate semantic benchmark.

**Commit boundary:** acceptance harness only. Suggested message: `test: exercise dispatcher with Codex Spark`.

### Task 11 — Real clean-session transcript and complete diff review

**Required because `hooks/session-start` and the ingest skill change.**

1. Install/use the modified plugin from the working tree in a clean test wiki.
2. Start a genuinely clean Claude Code session in `session_start` mode.
3. Capture the loader announce line and one bounded tick in a transcript.
4. Repeat in `scheduled` mode and prove SessionStart emits the loader but performs no scan/dispatch.
5. Run the LaunchAgent against a temporary wiki and prove it invokes a short-lived scheduled tick.
6. Sanitize secrets and unrelated paths from the transcript.
7. Run:

```bash
bash tests/run-all.sh
git diff --check
git status --short
git diff --stat
git diff
```

8. Show the user the complete diff before any commit, push, or PR.

No commit or PR is authorized merely by this plan.

### Task 12 — Disposable migration acceptance

This goal verifies migration behavior only on temporary fixture wikis. It does not inspect, migrate, or mutate any existing user wiki.

**Acceptance scenarios**

- Clone a legacy fixture into a temporary directory.
- Run migration dry-run and verify it mutates nothing.
- Run real migration against that disposable clone.
- Verify `.wiki-config` contains structural fields only.
- Verify `.wiki-config.local` contains the explicitly supplied provider profiles and is Git-ignored.
- Verify backup and rollback against a forced second-file replacement failure.
- Verify `wiki status`, manual tick, missing-CodexBar behavior, and scheduler generation without installing a real user LaunchAgent.
- Destroy only the exact temporary fixture directory created by the test harness.

Migration of a real wiki, if ever wanted, is a separate future task with its own scope and approval. It is not a deferred step of this goal.

### Task 13 — Semantic gate and post-ship learning capture

The dispatcher is operationally correct only after the runtime acceptance tests. Production author quality remains governed by the frozen wiki-ingestion benchmark.

1. Preserve the current-skill Spark low/medium/high benchmark as a separate baseline, including the invalid nested-Claude attempt and the neutral harness amendment.
2. If Task 4 changes only provider-neutral role/lifecycle mechanics as scoped, run a focused regression benchmark on selected reference profiles plus Spark; do not claim old semantic scores automatically apply to materially changed skill prose.
3. Use the same blind judge, hidden retrieval questions, source-attribution checks, and lifecycle checks.
4. Do not add per-ingest model review as a substitute for benchmark qualification.
5. After implementation commits and failures exist, write a short case study in `/Users/lukaszmaj/dev/toolboxmd/building-agentskills` covering only evidenced lessons:
   - provider-specific role wording can contaminate benchmark attribution;
   - deterministic runtime mechanics belong in code, not agent prose;
   - clean ingest is not the same as useful retrieval;
   - time-relative tests must not hard-code expiring timestamps;
   - optional observability adapters need a tested no-adapter path.
6. Keep that cross-project case study in a separate diff/commit from karpathy-wiki.

## Final acceptance checklist

- [ ] Baseline suite is green before feature code.
- [ ] `.wiki-config.local` is ignored and contains all operational settings.
- [ ] Project-pointer files are not mistaken for wiki runtime configs.
- [ ] Migration has dry-run, backup, atomic replacement, rollback, and readable errors.
- [ ] All entrypoints use one dispatcher.
- [ ] No direct raw provider command path remains outside adapters.
- [ ] Ten concurrent ticks cannot exceed the configured ingest ceiling.
- [ ] Heartbeat protects a valid long ingest from the ten-minute stale heuristic.
- [ ] Dead workers are reclaimed without duplicate live provider processes.
- [ ] Run history remains valid under concurrent writes and malformed legacy lines.
- [ ] Rate limits requeue without consuming attempts and open one provider breaker.
- [ ] User-selected default and optional fallback profiles are honored exactly.
- [ ] CodexBar absence, timeout, malformed output, and missing provider all fall back to reactive behavior.
- [ ] SessionStart does no queue work in scheduled mode.
- [ ] LaunchAgent install/uninstall/status are idempotent and tested without touching the real user agent in unit tests.
- [ ] Successful provider exit without archive/close is not marked completed.
- [ ] No semantic reviewer model runs after each ingest.
- [ ] Spark adapter acceptance runs use the exact requested model/effort and do not delegate.
- [ ] Clean-session transcript exists for both modes.
- [ ] Full diff is shown to the user before commit or PR.
- [ ] No existing user wiki was inspected or migrated by acceptance tests.

## Rollback

- Feature implementation is isolated to the karpathy-wiki repository and disposable test fixtures.
- Reverting a feature diff must not touch external wiki directories.
- Migration rollback tests restore only their temporary fixture backups.
- Rollback never deletes pending, processing, archive, failed, source, or wiki content files inside a fixture; it restores configuration atomically.
