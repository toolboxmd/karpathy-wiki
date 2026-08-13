# Codex-First Rollout and Focused-Test Workflow Plan

**Status:** Approved for autonomous execution of Stages 1 through 3
**Date:** 2026-08-12
**Decision owner:** User
**Audit:** `docs/planning/2026-08-12-test-strategy-rightsizing-audit.md`
**Handoff:** `docs/planning/2026-08-12-test-strategy-rightsizing-handoff.md`

## Outcome

Qualify Codex as the primary interactive host for Karpathy Wiki, prove the
plugin in a clean disposable session, and establish a fast focused-test workflow
without weakening the critical durability contracts identified in the audit.

This plan preserves the useful parts of the Superpowers methodology: fresh
evidence before completion, a witnessed failure before changing non-trivial
behavior, focused pressure scenarios for agent judgment, and full verification
at the correct integration boundary. It does not apply the same ceremony to
links, formatting, factual corrections, or other behavior-preserving edits.

## Approved scope

The agent may execute Stages 1 through 3 autonomously:

1. create and validate minimal Codex plugin packaging;
2. qualify the plugin in a clean interactive Codex session and disposable wiki;
3. introduce the smallest practical focused-test workflow and verify it.

Stages 4 through 7 are recorded below so the direction is not lost, but they are
not part of the current autonomous goal. They require a review of the Stage 1 to
3 evidence before implementation.

## Non-negotiable boundaries

- Do not inspect, migrate, or mutate an existing user wiki.
- Do not touch Naturbiss data or existing semantic benchmark artifacts.
- Do not change production provider or model choices.
- Do not weaken atomic capture, recovery, concurrency, lifecycle, migration,
  provenance, redaction, or provider-boundary contracts.
- Do not install two simultaneously active copies of the same named skill.
- Preserve all unrelated user changes.
- Keep all repository artifacts and agent instructions in English.
- Do not open a PR without showing the complete diff to the user first.
- Do not claim success from a launched process or injected JSON alone. Verify
  the observable agent behavior and retained filesystem state.

## Execution strategy

Use command-line tools for repeatable installation, configuration inspection,
fixture creation, deterministic tests, logs, and filesystem assertions. Use
Computer Use only for evidence that requires the real Codex application UI,
especially hook trust, a fresh interactive session, and observing whether the
host reads and acts on the injected loader context.

This split keeps the acceptance test realistic without making UI automation the
source of truth for assertions that can be checked deterministically.

## Stage 1: minimal Codex plugin

### Objective

Make the existing project installable as one Codex plugin that bundles its
skills and lifecycle hooks, while retaining the existing Claude Code package.

### Work

1. Inspect current Codex plugin manifests installed on the machine and confirm
   the current official manifest and hook contract.
2. Add a minimal `.codex-plugin/plugin.json` with the least metadata and wiring
   needed for this repository.
3. Reuse `hooks/hooks.json` and the existing hook scripts where their current
   output is already compatible.
4. Add a focused failing packaging test before adding behavior that lacks
   coverage. Avoid changing `SKILL.md` unless the clean-session evidence proves
   an instruction defect.
5. Verify that every plugin-relative path resolves and that the package does not
   depend on the checkout's absolute path.
6. Install or link the local plugin through the supported Codex development
   workflow.
7. Inspect the resulting plugin and hook registration.

### Exit criteria

- Codex recognizes one Karpathy Wiki plugin.
- The plugin exposes the intended skills once, without a duplicate standalone
  installation of the same names.
- The SessionStart and Stop hooks resolve from the plugin root.
- Focused deterministic packaging and hook tests pass.
- Installation and update steps are recorded exactly enough to repeat.

## Stage 2: clean Codex host qualification

### Objective

Prove that a real Codex interactive session notices, reads, and acts on the wiki
instructions. Provider qualification alone is not sufficient.

### Disposable fixture

Create a temporary project and wiki containing:

- one distinctive fact that can only be answered from the wiki;
- one source file with a stable evidence path;
- an empty capture queue and clean ingest state;
- no link to any existing user wiki.

Retain only sanitized acceptance evidence in the repository. Remove the
temporary fixture after evidence capture when removal is safe and recoverable.

### Acceptance scenarios

1. **Loader and announce line**
   Start a genuinely new Codex session in a wiki-eligible project. Verify the
   announce line appears and the agent reads the loader instructions.
2. **Retrieval**
   Ask for the distinctive fact. Verify the answer comes from the disposable
   wiki and cites the correct source or wiki page.
3. **Capture**
   Provide a new durable fact. Verify a complete capture is published with its
   evidence path and without silent routing elsewhere.
4. **Dispatch and ingest**
   Verify staged, processing, and terminal state transitions, bounded worker
   activation, ingest output, and durable run history.
5. **Failure recovery**
   Trigger a controlled non-destructive failure. Verify the source and capture
   remain recoverable and a retry does not create an unsafe duplicate.
6. **Mode isolation**
   Verify SessionStart and scheduled activation do not both dispatch the same
   work.

### Evidence

Record:

- the exact Codex build or version and plugin source revision;
- sanitized hook inspection output;
- a real clean-session transcript containing the announce line;
- commands and relevant filesystem states for each scenario;
- explicit pass, fail, or blocked status per scenario;
- all deviations from the intended behavior, without rewriting them as passes.

### Exit criteria

- All six scenarios pass, or the stage reports a concrete blocker with retained
  evidence and no success claim.
- The test never mutates an existing user wiki.
- The transcript proves behavior, not only loader injection.

## Stage 3: focused-test workflow

### Objective

Make the normal development loop select the affected contracts and target less
than 20 seconds, while keeping `tests/run-all.sh` as the deterministic final
gate.

### Initial groups

- `skill`
- `capture`
- `scanner`
- `dispatcher`
- `provider`
- `config`
- `scheduler`
- `schema`
- `full`

### Work

1. Choose the smallest maintainable interface after inspecting the existing
   runner. Prefer extending a current entrypoint or storing one explicit mapping
   over adding a dispatcher framework for tests.
2. Add a failing runner-contract test before implementing a new script or new
   runner behavior.
3. Map every current deterministic test to at least one group or explicitly to
   `full` only.
4. Ensure an unknown group fails clearly and no empty selection can report
   success silently.
5. Measure each group on the exact implementation commit.
6. Document the change-to-group selection rule for agents and contributors.
7. Run the full deterministic suite once after the runner integration is
   complete.

### Exit criteria

- All current deterministic tests remain reachable from `full`.
- No critical contract identified in the audit disappears.
- Common focused groups complete under 20 seconds, or actual exceptions are
  reported with evidence.
- The selected group and executed test list are visible in output.
- The full suite passes on the exact candidate revision.

## Review gate after Stage 3

Stop and present:

1. the complete diff;
2. the plugin installation and update procedure;
3. clean-session acceptance evidence;
4. focused and full-suite timings;
5. any defects found and how they were resolved;
6. exact Git status, commit status, and push status;
7. a recommendation on whether to proceed to Stage 4.

Do not begin Stage 4 without user review.

One separate routing defect was confirmed during that review. The original
selective project-to-main propagation contract conflicts with the later
unconditional `wiki use both` fan-out. The evidence, target contract, and
required RED scenarios are recorded in
`docs/planning/2026-08-12-both-routing-contradiction.md`. Do not combine that
fix with this rollout branch.

## Deferred Stage 4: remove pure runtime waste

- Replace fixed sleeps with controlled timestamps or state polling.
- Remove nested execution of other test files from Leg 1.
- Re-measure the unchanged portfolio before consolidating coverage.

## Deferred Stage 5: consolidate duplicate suites

Consolidate one subsystem at a time while preserving named cases and failure
localization. Treat removal of `test-skill-split-no-overlap.sh` as an explicit
reviewable decision rather than hiding it in a broad refactor.

## Deferred Stage 6: update TDD and verification policy

Update `AGENTS.md` and `CLAUDE.md` only after the focused workflow has worked in
practice. Preserve focused RED-GREEN-REFACTOR for bugs and non-trivial behavior,
pressure scenarios for agent-judgment changes, and full verification at merge,
release, and cross-cutting boundaries.

## Deferred Stage 7: final qualification and release

Run the full deterministic suite, a fresh Codex host acceptance, relevant real
provider or scheduler acceptance, and final timing comparison. Show the complete
diff before any PR, then verify commit and push as separate outcomes.

## Completion definition for the current goal

The current autonomous goal is complete only when Stages 1 through 3 satisfy
their exit criteria and the Stage 3 review package is ready. Completion does not
authorize Stage 4, a PR, a push, or changes to an existing user wiki.
