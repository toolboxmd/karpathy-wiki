# Codex Spark medium dispatcher acceptance — 2026-08-11

## Scope

This acceptance used a disposable project wiki whose path and evidence path
both contained spaces. It did not discover, inspect, migrate, or mutate an
existing wiki. CodexBar was deliberately unavailable.

Requested profile:

- provider: `codex`
- model: `gpt-5.3-codex-spark`
- reasoning effort: `medium`
- maximum active ingests: `1`

## Result

| Case | Duration | Lifecycle | Content result |
|---|---:|---|---|
| Cold ingest | 116.009 s | one `started`, one `completed`, one archive | created one Relay policy page |
| Exact duplicate | 39.405 s | one `started`, one `completed`, one archive | byte-identical page snapshot; no duplicate page |
| Related augmentation | 184.017 s | one `started`, one `completed`, one archive | added deterministic jitter and retry-window cap |

All three retained `invocation.json` files identify the requested provider,
model, and effort exactly. The command-event audit found no nested Claude,
Grok, or Codex invocation. Final state had no pending capture, processing file,
or ingest-slot lease.

The first preflight exposed that the operator's Codex config supplied an
unsupported `reasoning.summary` option to Spark. The adapter was corrected to
use Codex `--ignore-user-config`; authentication remains available, while the
selected profile no longer inherits unrelated model options. A clean rerun
then passed.

The augmentation also exposed a skill-level timestamp defect: local
Europe/Warsaw wall time was labeled with `Z`. The provider-neutral ingest skill
and canonical page convention now require timestamps generated from a UTC
clock (`date -u`); the regression is recorded in
`tests/red/RED-utc-frontmatter-timestamps.md`.

Raw provider output and local paths are retained only under the Git-ignored
`raw/2026-08-11T15-21-54Z/` directory.

This result qualifies the Codex adapter and deterministic lifecycle. It does
not place Spark in a production author or fallback chain; semantic model
selection remains governed by the separate blind ingestion benchmark.
