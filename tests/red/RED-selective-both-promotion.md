# RED: selective project-to-main promotion in `both` mode

**Date:** 2026-08-12
**Baseline:** `1eacf8fada4c9922d0747490997163fb6419d8f8`
**Evaluator:** clean read-only agent on the current skill and runtime
**Result:** RED

## Pressure prompt

The evaluator received this project-specific capture:

> In this repository, `bin/wiki` lines 289-365 currently fan out captures to
> both targets; we plan to replace this exact implementation.

Expected behavior in `both` mode:

1. The original capture is queued and ingested in the project wiki only.
2. The project ingester classifies repository paths, exact implementation
   lines, and local architecture as project-specific.
3. The result is kept local, with no main-wiki capture or page.
4. The keep-local outcome is durable and deterministically verifiable.

## Witnessed baseline behavior

The evaluator found that the 132-byte prompt would first be rejected by the
`chat-only` 1500-byte sufficiency floor. After explicitly setting that
independent admission issue aside, the routing behavior still fails:

- `scripts/wiki-resolve.sh` emits the project and main roots when
  `fork_to_main = true`.
- `bin/wiki` publishes the original capture to both queues before either
  ingester can classify it.
- Both copies contain `propagated_from: null`.
- The project ingester's step 9 correctly says repository-specific knowledge
  should remain local, but that decision happens after main publication.
- The worker has no deterministic promotion helper, stable promotion identity,
  or machine-readable keep-local result.
- The current fork record omits the `captures` array which `wiki-status.sh`
  expects, so the old two-sided result cannot be correlated reliably either.

## Verdict

| Expected outcome | Baseline |
|---|---|
| Project result stays local | **FAIL**, original is already queued in main |
| No main capture is published | **FAIL**, publication precedes judgment |
| Outcome is deterministically verifiable | **FAIL**, decision and idempotency state are absent |

The current prose contains the desired semantic judgment, but the executable
runtime contradicts it. This pressure failure justifies changing
`skills/karpathy-wiki-ingest/SKILL.md` only after deterministic routing and
promotion tests are RED.

## Follow-up qualification scenarios

After implementation, a real provider acceptance run must cover all three:

1. Repository-specific paths and architecture under `both` produce an explicit
   keep-local decision and no main capture.
2. A reusable cross-project tool or pattern under `both` produces exactly one
   derived main capture through the deterministic helper, with portable source
   provenance.
3. Reusable-looking material under `project` remains local because policy, not
   semantic confidence alone, controls promotion capability.

## Post-change qualification

The same three cases were evaluated in parallel against the current ingest
skill and against a blind baseline with no repository instructions.

- The current skill produced the exact `keep-local`, `publish`, and no-helper
  actions, including terminal source fields, portable provenance, and retry
  behavior. All three cases passed.
- The blind baseline had to invent an ID algorithm, receipt schema, and meaning
  for `both`; it explicitly reported those contracts as undefined and treated
  a main capture in the repository-specific case as plausible.

This comparison shows that the skill adds the missing semantic routing
contract, while deterministic tests own publication, recovery, and isolation.
