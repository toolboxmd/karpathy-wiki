# Test Strategy Rightsizing — Codex Handoff

**Status:** Ready for a new Codex session. Audit first; do not remove, merge, or rewrite tests before human review.
**Date:** 2026-08-12
**Repository:** `toolboxmd/karpathy-wiki`
**Baseline before this handoff:** `bee7938`
**Dispatcher implementation:** `877e659`

## Why this handoff exists

The bounded provider-aware ingest dispatcher is shipped and verified. The next
question is whether the repository now applies more TDD and verification rigor
than the actual risks justify.

The user explicitly wants critical judgment, not automatic defense of the
current process. The preliminary conclusion is:

- strict tests remain justified for data durability, concurrency, process
  lifecycle, migration, and provider invocation;
- the repository-wide testing doctrine appears too absolute for editorial
  skill changes, thin wrappers, documentation-only changes, and everyday
  development loops;
- the next step is evidence-based rightsizing, not mass deletion.

## Verified current evidence

At commit `bee7938`:

- `tests/run-all.sh` discovers 76 unit scripts and 14 integration scripts;
- all 90 scripts pass;
- a measured full run on 2026-08-11 took about 86 seconds;
- unit plus integration test code is about 9.2K lines;
- runtime code under `scripts/`, `bin/`, and `hooks/` is about 9.3K lines;
- the dispatcher ship added 59 files under `tests/` and about 3.8K test lines,
  compared with about 3.7K runtime lines;
- the semantic Spark benchmark and real provider/session/scheduler acceptance
  are separate from the normal 90-script suite.

These numbers show a real maintenance and navigation cost. They do not, by
themselves, prove that individual tests are redundant.

## What must remain protected

Treat these as high-risk contracts unless the audit finds stronger equivalent
coverage:

- atomic capture publication and claiming;
- hard global and per-profile concurrency ceilings;
- no duplicate live worker after stale-heartbeat reconciliation;
- one durable terminal outcome per run;
- validation before archive and recoverable post-archive failure;
- bounded retries, rate-limit cooldowns, and immediate fallback behavior;
- provider process-group termination after orchestration failure;
- provider/model/effort attribution and argv boundary safety;
- secret redaction in retained diagnostics;
- explicit deferral of `needs_more_detail` without a hot loop;
- atomic, backed-up, dry-runnable config migration;
- mutual exclusion of SessionStart and scheduled automatic activation;
- clean scheduler install, run, and uninstall lifecycle;
- source hashes, manifest integrity, and exact-duplicate idempotence.

## Suspected over-rigidity to investigate

Do not accept these as conclusions until the audit maps actual coverage:

1. Multiple small tests grep overlapping phrases in the same `SKILL.md`.
2. Every script is expected to have its own unit test even when a thin wrapper
   contains no independent logic and is already exercised integrationally.
3. Every `SKILL.md` edit requires a new pressure scenario, including editorial,
   link, or provider-neutral wording changes that do not change judgment.
4. The full suite is often run after documentation-only edits, rather than once
   at the final integration boundary.
5. Real-provider and scheduler acceptance may be treated as routine regression
   tests even though they are expensive environment qualification.
6. Semantic model benchmarks may be rerun for runtime-only changes that do not
   alter source interpretation, page selection, attribution, or synthesis.
7. One-test-file-per-contract has increased file count and discovery cost where
   a subsystem contract suite might be clearer.

## Required first task: read-only test portfolio audit

Do not edit tests, runtime code, skills, or contributor policy in the first
phase. Produce a review document under `docs/planning/` with one row per test
script or coherent test group.

For each item record:

| Field | Meaning |
|---|---|
| Test or group | File path(s) |
| Contract protected | The user-visible or durability failure it catches |
| Evidence | Incident, RED scenario, implementation risk, or only speculative coverage |
| Risk | Critical, high, medium, or low |
| Unique coverage | What fails here that no other test would catch |
| Overlap | Other tests covering the same contract |
| Cost | Runtime, setup complexity, flake/environment risk, maintenance burden |
| Recommendation | Keep, merge, demote to acceptance, or remove |
| Confidence | High, medium, or low |

Measure per-test runtime without modifying tracked files. Read test bodies and
the implementation they exercise; do not classify solely from filenames.

## Recommendation definitions

- **Keep:** unique coverage for a meaningful failure, especially state loss,
  concurrency, security, migration, or public contract regression.
- **Merge:** useful assertions, but clearer and cheaper as one subsystem
  contract suite. Merging must preserve failure localization.
- **Demote to acceptance:** depends on a real provider, real session, scheduler,
  subscription, platform, or long semantic evaluation. Run on relevant adapter
  changes or release qualification, not in the default local loop.
- **Remove:** duplicates stronger coverage or pins an implementation detail with
  no meaningful failure story. Removal requires showing the surviving test that
  protects the contract.

## Candidate verification tiers — proposal, not yet approved

The audit should evaluate this four-tier shape:

### Tier 1: fast development checks

Target: under 20 seconds. Run tests for the changed subsystem plus cheap static
contracts. This is the default inner loop.

### Tier 2: subsystem integration

Run after completing a dispatcher, provider, config, scheduler, capture, or
skill-behavior slice. Include the relevant multi-process and lifecycle tests.

### Tier 3: full deterministic suite

Run once before merge/release and after cross-cutting contract changes. Keep
`tests/run-all.sh` as the final deterministic gate unless evidence supports a
replacement.

### Tier 4: opt-in acceptance and semantic benchmarks

Run real provider/session/scheduler acceptance when those adapters change or
before release. Run semantic benchmarks only when model selection or semantic
ingest behavior changes materially.

## Candidate policy correction — proposal, not yet approved

The audit should draft exact replacement wording for `AGENTS.md` and
`CLAUDE.md`, guided by these boundaries:

- New non-trivial deterministic logic and bug fixes use a failing test first.
- Thin wrappers may be covered by an existing integration test when they add no
  independent branching or state transition.
- A new pressure scenario is required for changes to skill triggers, decisions,
  sequencing, or semantic behavior—not for links, formatting, factual
  corrections, or wording that preserves behavior.
- During development, run affected tests. Run the full deterministic suite at
  the integration boundary, not after every edit.
- Real-harness acceptance is required when the changed surface depends on that
  harness; it is not a universal documentation gate.
- Semantic benchmarks qualify model/skill quality offline and are not repeated
  for purely deterministic runtime refactors.

Do not apply this wording until the user reviews the portfolio audit and agrees
on the target policy.

## Relevant shipped evidence

- `docs/planning/2026-08-11-bounded-provider-aware-ingest-dispatcher-plan.md`
- `docs/planning/2026-08-11-bounded-provider-aware-ingest-dispatcher-implementation.md`
- `tests/acceptance/dispatcher/2026-08-11-codex-spark-medium.md`
- `tests/acceptance/dispatcher/2026-08-11-clean-session-and-scheduler.md`
- [Provider-aware ingest retrospective](https://github.com/toolboxmd/building-agentskills/blob/a87d457/case-studies/2026-08-11-karpathy-wiki-provider-aware-ingest.md)
- [Provider-neutral runtime guidance](https://github.com/toolboxmd/building-agentskills/blob/a87d457/docs/05-authoring/provider-neutral-runtime.md)
- [Benchmark integrity guidance](https://github.com/toolboxmd/building-agentskills/blob/a87d457/docs/06-testing/benchmark-integrity.md)

## Scope boundaries

- Do not inspect, migrate, or mutate any existing user wiki.
- Do not modify Naturbiss data or benchmark artifacts.
- Do not change production provider/model choices.
- Do not update `building-agentskills` again before this repository produces new
  ship evidence; general doctrine follows proven changes, not proposals.
- Preserve unrelated user changes if the working tree is no longer clean.
- All repository artifacts and agent instructions remain English; the user may
  discuss decisions in Polish.

## Completion gate for the next session

The first session is complete when it has:

1. verified current branch, status, and baseline;
2. produced the read-only portfolio audit with evidence and timings;
3. proposed a smaller verification matrix and exact policy wording;
4. identified expected time/file-count savings without weakening named critical
   contracts;
5. stopped for user review before deleting, merging, or demoting any test.
