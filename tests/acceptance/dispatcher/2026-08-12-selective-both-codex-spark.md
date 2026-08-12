# Selective `both` Codex Spark acceptance — 2026-08-12

## Scope

This acceptance exercised the project-first selective-promotion workflow on
commit `7fed32c` using disposable main and project wikis under a temporary
directory. It did not inspect, migrate, or mutate the user's existing main
wiki. The main pointer was also temporary.

Requested profile for every worker:

- provider: `codex`
- model: `gpt-5.3-codex-spark`
- reasoning effort: `medium`
- maximum active ingests per wiki: `1`
- auto-commit: `false`

An exact-model preflight returned `SPARK_SELECTIVE_PREFLIGHT_OK` before the
acceptance captures were submitted.

## Result

| Case | Worker duration | Project decision | Main result |
|---|---:|---|---|
| Clearly repository-specific | 173.280 s | `keep-local` | no receipt, capture, run, or page |
| Clearly reusable | 146.818 s | `promoted` | exactly one derived capture published |
| Derived main ingest | 100.437 s | not applicable | one `started`, one `completed`, one page |

All three real workers recorded provider `codex` and model
`gpt-5.3-codex-spark`. Each had exactly one `started` and one `completed`
event, with three unique run IDs in total. There were no failed, transient,
rate-limited, authentication, or needs-more-detail outcomes.

## Clearly local evidence

The capture described repository-only paths, class names, event names, and a
temporary migration fence, while explicitly stating that it was not reusable
guidance.

- The project worker created `queries/local-relay-router-local-routing.md`.
- The archived source retained `promotion_policy: selective` and recorded
  `promotion_decision: keep-local` with null promotion ID.
- No promotion receipt was created.
- The main wiki contained no capture or page derived from source capture
  `cap-35edfd36cc5540608937b218ea8f9836`.
- Project manifest validation passed, with no processing file or slot lease.

This qualifies the semantic false-positive boundary: clearly local knowledge
remained local even though the capture was eligible for selective promotion.

## Clearly reusable evidence

The capture described the general pattern of separating a semantic decision
from deterministic, atomic, idempotent publication and crash recovery.

- The project worker created
  `concepts/reusable-atomic-publication-pattern.md`.
- The archived source recorded `promotion_decision: promoted`.
- The promotion ID was deterministically derived as
  `prom-9dcc02271d0d7e88a7fb250f` from source capture
  `cap-0bec3df8c11f48b0b6ebeea6705d8b19`.
- Exactly one receipt recorded `status: published`, the pinned disposable
  main wiki, and one target filename.
- Exactly one derived capture existed across main pending, processing, failed,
  and archive states. It was archived after the main worker completed.
- The derived body was 3483 bytes, carried
  `propagated_from: cap-0bec3df8c11f48b0b6ebeea6705d8b19`, and used
  `promotion_policy: none` to prevent recursion.
- The derived capture contained no absolute project path and none of the
  repository-only identifiers from the local scenario.
- The main worker created
  `concepts/reusable-atomic-publication-pattern.md`.
- Project and main manifest validation passed, with no processing file or slot
  lease remaining.

This qualifies the semantic false-negative boundary and the complete
project-to-main lifecycle. The two source scenarios required three provider
calls because the reusable case intentionally included ingestion of the
derived main capture rather than stopping after durable publication.

The disposable fixture was deleted after these assertions passed.
