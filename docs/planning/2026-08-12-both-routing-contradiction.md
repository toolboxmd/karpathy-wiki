# Both-Mode Routing Contradiction

**Status:** Resolved on `codex/single-authority-selective-routing`. The original
handoff evidence is retained below for review history.
**Date:** 2026-08-12
**Observed at:** `9bffbc08734fa6728c5087bdc5084e05ba65b47f`
**Resolution branch:** `codex/single-authority-selective-routing`

## Resolution

The fix replaces routing flags with one trusted per-workspace runtime record:

- `wiki use project|main|both` performs one direct selection and atomically
  stores `routing.mode` plus exact targets outside the checkout;
- the resolver reads one snapshot, ignores tracked routing markers and legacy
  `.wiki-mode`, and returns one initial target;
- `both` returns the project as that target with `promotion_policy=selective`;
- new captures carry portable identity, promotion policy, decision, and stable
  promotion identity fields;
- the project ingester makes the semantic keep-local or promote decision;
- `scripts/wiki-promote-capture.py` owns locked, atomic, idempotent derived
  publication and retry receipts;
- deterministic completion refuses to archive a selective capture without a
  durable decision;
- new simultaneous-fork records are no longer written, and status reports
  selective decision counts instead;
- the global pointer is consulted only when selecting `main` or `both`; later
  pointer changes do not silently retarget the workspace;
- tracked project-pointer config no longer stores routing authority or an
  absolute main-wiki path.

The witnessed RED transcript is retained at
`tests/red/RED-selective-both-promotion.md`. The deterministic suite covers
local-first routing, exact-once publication, portable provenance, concurrent
retry, failures before and after publication, project-mode isolation,
main-mode stability, and invalid main-pointer refusal.

## Summary

The repository currently describes and implements two incompatible ways to
move reusable knowledge from a project wiki to the main wiki.

The original project-wiki contract is selective propagation. A project
ingester first processes the capture with the project-specific lens, then
decides whether the result is reusable outside that project. Only reusable
knowledge is propagated to the main wiki. Project-specific knowledge remains
local.

The later `wiki use both` contract is unconditional fan-out. `bin/wiki capture`
writes the same capture into both the project and main queues before either
ingester evaluates it. Two ingest workers then process the copies independently.

These flows cannot safely remain active as one feature. Unconditional fan-out
bypasses the selective propagation decision and can also combine with the
project ingester's propagation instruction to enqueue main-wiki knowledge more
than once.

## Evidence

### Selective propagation remains an active ingester instruction

`skills/karpathy-wiki-ingest/SKILL.md`, step 9, tells a project ingester to:

- propagate tools, concepts, patterns, and principles useful across projects;
- keep project-specific architecture and names local;
- create a derived main-wiki capture with `propagated_from` when propagation is
  selected.

The original design states the same behavior in
`docs/planning/2026-04-22-karpathy-wiki-v2.md`: the behavioral difference
between project and main wikis is the project ingester's general-interest
decision.

### Both mode performs unconditional fan-out

The v2.4 executable-protocol design defines `both` as writing the same capture
to both wikis so two ingesters run with different lenses.

The current implementation follows that later design:

1. `scripts/wiki-resolve.sh` emits the project and main wiki roots when
   `fork_to_main = true`.
2. `bin/wiki` loops over every emitted target and publishes a complete copy of
   the capture into each `.wiki-pending/` directory.
3. `bin/wiki` dispatches every target independently.
4. `tests/integration/test-leg2-end-to-end.sh` requires the same capture to
   exist in both queues and checks that a fork-coordination record was written.

### The selective path is not qualified end to end

No deterministic or acceptance test proves either of these required outcomes:

- project-specific knowledge in `both` mode never reaches the main wiki;
- reusable project knowledge reaches the main wiki exactly once with durable
  provenance.

The project ingester instruction also does not have a complete runtime contract
for locating the selected main wiki. The resolver knows the main target during
capture, but the detached project worker receives `WIKI_ROOT`, `WIKI_CAPTURE`,
`WIKI_RUN_ID`, and `WIKI_PLUGIN_ROOT`. A main-wiki target is not supplied as an
explicit worker input.

## User-visible risks

1. Project-specific implementation details can pollute the global knowledge
   base even though the documented project lens says to keep them local.
2. One event can produce duplicate or competing main-wiki captures.
3. Fork-asymmetry status can report a mechanical mismatch without proving that
   the semantically correct promotion decision occurred.
4. A green routing test can establish that two files were created while saying
   nothing about whether either file belonged in the main wiki.
5. Main-wiki quality becomes dependent on two independent semantic runs for
   every capture, increasing latency and cost for ordinary project work.

## Recommended target contract

Use three modes with non-overlapping meanings:

| Mode | Initial capture target | Project-to-main behavior |
|---|---|---|
| `project` | Project wiki only | Never propagate automatically |
| `main` | Main wiki only | Not applicable |
| `both` | Project wiki first | Selectively create one derived main capture when reusable |

In `both` mode:

1. Publish the original capture only to the project queue.
2. Let the project ingester create the project-specific page or no-op.
3. Require an explicit promote-or-keep-local decision.
4. On promote, publish exactly one derived capture to the selected main wiki.
5. Set `propagated_from` to durable project provenance and preserve the source
   evidence reference.
6. Let the main ingester abstract the reusable pattern without carrying over
   unnecessary project names or architecture.

This preserves the useful two-lens design without paying for a main-wiki ingest
when the project ingester decides that the knowledge is local.

## Required RED scenarios before implementation

The fix changes routing behavior and agent judgment, so it requires witnessed
failures before implementation.

1. **Local-only both capture:** a capture containing repository-specific paths
   and architecture is ingested into the project wiki and creates no main-wiki
   capture or page.
2. **Reusable both capture:** a generalizable tool or pattern creates one
   project result and exactly one derived main capture with `propagated_from`.
3. **No duplicate promotion:** retrying or resuming project ingest cannot
   publish a second equivalent main capture.
4. **Recoverable promotion failure:** failure after the project result but
   before main publication leaves enough durable state to retry once without
   losing or duplicating knowledge.
5. **Project mode isolation:** the same reusable-looking capture in `project`
   mode remains local because automatic promotion is disabled.
6. **Main mode stability:** direct `main` capture behavior remains unchanged.
7. **Missing-main refusal:** selecting `both` without a valid main pointer still
   fails before accepting a capture.

Use disposable project and main wiki fixtures. Do not use an existing user
wiki for these scenarios.

## Implementation questions for the fix branch

Resolve these explicitly in the design before editing runtime code:

1. How the detached project worker receives the selected main-wiki path without
   writing a machine-specific absolute path into tracked project configuration.
2. Which deterministic component owns idempotent publication of the derived
   capture. The model may decide whether to promote, but a helper should own the
   atomic write and duplicate key.
3. How `propagated_from` identifies the originating project capture and result
   rather than only a directory path.
4. How `.wiki-forks.jsonl`, fork-asymmetry status, and run history should be
   redefined for a sequential selective promotion rather than immediate
   two-target fan-out.
5. Whether `fork_to_main` remains the persisted field name or is renamed in a
   migration-safe way to describe selective promotion accurately.

## Scope boundary

Do not fix this contradiction as part of the Codex plugin packaging or focused
test-runner rollout. The current branch should only retain this evidence and
handoff. Runtime, skill, and policy changes belong in the dedicated fix branch
with the RED scenarios above.
