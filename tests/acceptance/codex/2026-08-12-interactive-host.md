# Codex Interactive Host Acceptance

**Date:** 2026-08-12
**Repository revision before candidate changes:** `9bffbc08734fa6728c5087bdc5084e05ba65b47f`
**Plugin:** `karpathy-wiki@karpathy-wiki-local`, version `0.2.8`
**Primary qualified CLI:** Codex CLI `0.147.0`
**Fixture:** disposable main wiki under `/private/tmp`, with no pointer to an
existing user wiki and `auto_commit = false`
**Result:** PASS with two retained deviations described below

**Post-acceptance packaging note:** the retained transcript below correctly
records the marketplace ID used during the run, `karpathy-wiki-local`. After
the run, the Codex marketplace was renamed to the publisher-scoped ID
`toolboxmd`, with display name `toolbox.md`. Current installs therefore use
`karpathy-wiki@toolboxmd`. The obsolete Homebrew-prefix npm Codex noted in the
deviations was subsequently uninstalled; the NVM CLI remains the active shell
runtime. The historical evidence is intentionally unchanged.

## Scope and safety

This run qualified Codex as the interactive host that receives the plugin
loader, reads from a wiki, publishes a capture, and observes the bounded ingest
lifecycle. It did not inspect or mutate an existing user wiki, Naturbiss data,
or production model configuration.

Computer Use could not control the Codex application because that application
is blocked by the Computer Use safety policy. The acceptance therefore used a
real Codex CLI TUI in a PTY. Filesystem and lifecycle assertions were checked
separately from the model's own success messages.

## Installation and update procedure

The repository is registered as a local marketplace and installed as one
plugin. Do not install duplicate copies of the same skills under
`~/.agents/skills` or `~/.codex/skills`.

Initial install:

```bash
CODEX_BIN=/Users/lukaszmaj/.nvm/versions/node/v22.23.1/bin/codex
REPO=/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki

"$CODEX_BIN" plugin marketplace add "$REPO" --json
"$CODEX_BIN" plugin add karpathy-wiki@toolboxmd --json
"$CODEX_BIN" plugin list --json
```

Codex CLI 0.147.0 has no `plugin update` command. Refresh a local snapshot by
removing and adding the plugin, then start a new session:

```bash
"$CODEX_BIN" plugin remove karpathy-wiki@toolboxmd --json
"$CODEX_BIN" plugin add karpathy-wiki@toolboxmd --json
"$CODEX_BIN" plugin list --json
```

After a hook definition changes, open `/hooks` in a new Codex session, inspect
the command and matcher, and trust the revised hook intentionally.

The current installed cache path is:

```text
~/.codex/plugins/cache/toolboxmd/karpathy-wiki/0.2.8
```

The local remove and add refresh procedure was executed successfully during
this acceptance run.

## Hook inspection

Codex presented two hooks from `karpathy-wiki@karpathy-wiki-local` for review.
Both commands resolved inside the installed plugin cache:

| Hook | Matcher | Command | Result |
|---|---|---|---|
| SessionStart | `startup|clear|compact` | `<plugin-cache>/hooks/session-start` | trusted |
| Stop | all events | `<plugin-cache>/hooks/stop` | trusted |

No standalone Karpathy Wiki skill with the same name was present in the user
skill directories.

## Scenario results

| Scenario | Result | Retained evidence |
|---|---|---|
| Loader and announce line | PASS | Clean sessions emitted `Using the karpathy-wiki skill to answer from wiki.` before the answer. Session IDs `019ff5ee-4287-7642-980b-92d54495a3f8` and `019ff5fe-a04c-78d1-8974-0e64d98ca016`. |
| Retrieval | PASS | Codex returned fixture-only beacon `cobalt-finch-7319` and 47 seconds from `concepts/codex-host-acceptance-beacon.md`. |
| Capture | PASS with deviation | Codex published and ingested `amber-heron-4826`. The first page omitted required sections, so the host detected the incomplete result and published one augmentation capture. The final page retained scope, rationale, invariants, evidence preservation, success criteria, and failure criteria. |
| Dispatch and ingest | PASS | Runs recorded exact provider `codex`, model `gpt-5.3-codex-spark`, profile `codex_medium`, one active worker, terminal `completed` events, archives, raw evidence, and manifest references. |
| Failure recovery | PASS | Deterministic `transient_failure` returned `controlled-recovery.md` unchanged with attempt 1 and no lease. The explicit attempt 2 produced one archive and one terminal completion. |
| Mode isolation | PASS | In `scheduled` mode, SessionStart emitted loader context but run count stayed 6, the capture remained unclaimed, and its checksum was unchanged. |

## Sanitized clean-session transcript

Codex CLI 0.147.0, session
`019ff5fe-a04c-78d1-8974-0e64d98ca016`:

```text
User: What protocol follows three consecutive probe failures, and how long
does it wait before one retry? Answer from the local wiki and cite the page.

Codex: Using the karpathy-wiki skill to answer from wiki.

Codex: The Amber Heron recovery protocol (amber-heron-4826) follows exactly
three consecutive failed health probes for the same ingest worker. It waits
73 seconds, then permits at most one retry using the same provider profile.
If that retry fails, the capture returns to a recoverable pending state.

Source: concepts/amber-heron-recovery-protocol.md:21
```

The turn completed in 38.725 seconds and used 31,306 input and output tokens in
the TUI usage summary, plus 123,648 cached input tokens.

## Capture and ingest evidence

The interactive capture session
`019ff5ee-4287-7642-980b-92d54495a3f8` completed in 438.204 seconds. The TUI
usage summary reported 74,342 input and output tokens, plus 1,367,040 cached
input tokens. This directly supports the user's concern that the current
methodology is reliable but too expensive for ordinary small changes.

Provider lifecycle:

| Capture | Started UTC | Completed UTC | Wall time | Outcome |
|---|---:|---:|---:|---|
| distinctive beacon drift | 12:24:24.606 | 12:25:49.847 | 85.241 s | completed |
| Amber Heron initial capture | 12:29:57.545 | 12:33:08.196 | 190.651 s | completed |
| Amber Heron completeness augmentation | 12:33:48.012 | 12:35:56.587 | 128.575 s | completed |

Final durable state:

- one canonical page: `concepts/amber-heron-recovery-protocol.md`;
- two archived evidence captures because the first semantic ingest was
  incomplete and required an explicit augmentation;
- two raw evidence files, both attributed to `conversation` and both referring
  to the same canonical page;
- page validation passed;
- no Amber Heron capture remained pending or processing;
- auto-commit was disabled, so the fixture was not committed or pushed.

## Controlled failure transcript

```text
PASS mode-isolation loader=true runs-before=6 runs-after=6
     capture=unclaimed checksum=unchanged
PASS transient-recovery statuses=started,transient_failure attempt=1
     capture=requeued checksum=unchanged lease=released
PASS retry-completion statuses=started,transient_failure,started,completed
     attempt=2 archives=1 pending=0 processing=0
```

## Deviations and recommendation

1. The semantic ingest was safe but not right on the first attempt. It omitted
   required content and needed a second provider run. This is not rewritten as
   a clean first-pass success.
2. Two Codex installations exist locally. Login PTY resolution selected
   `/opt/homebrew/bin/codex` version 0.144.1, while the NVM path provides
   version 0.147.0. The final qualification invoked the 0.147.0 binary by its
   absolute path. Unify the local PATH before relying on an unqualified
   `codex` command for release evidence.

Proceed with Codex as the primary interactive host after the local CLI path is
unified. Keep real semantic capture acceptance opt-in. The measured cost is too
high for a default edit loop, while the deterministic lifecycle and focused
contract tests remain appropriate default safeguards.

## Focused deterministic benchmark

The focused runner was integrated after a witnessed RED in
`tests/unit/test-run-all-groups.sh`. No test was removed, merged, demoted, or
made unreachable. The final `full` selection contains all 92 discovered test
files exactly once.

| Group | Test files | Wall time |
|---|---:|---:|
| `skill` | 11 | 2.15 s |
| `capture` | 7 | 4.61 s |
| `scanner` | 5 | 9.36 s |
| `dispatcher` | 10 | 10.78 s |
| `provider` | 7 | 6.34 s |
| `config` | 9 | 7.83 s |
| `scheduler` | 2 | 2.03 s |
| `schema` | 18 | 12.26 s |
| `full-only` | 23 | 35.47 s |
| `full` | 92 | 93.40 s |

All normal focused development groups are below the 20-second target. The
`full-only` ownership bucket is intentionally not an inner-loop group. It holds
cross-cutting and low-frequency operator flows and remains part of `full`.

The exact candidate full gate passed 92 test files with zero failures in 93.40
seconds. The opt-in real Codex Spark acceptance test was discovered and skipped
because `RUN_CODEX_SPARK_ACCEPTANCE=1` was not set. Real provider behavior was
already qualified separately in the disposable fixture described above.
