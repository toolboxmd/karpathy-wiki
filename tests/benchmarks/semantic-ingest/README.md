# Semantic Ingest Benchmark

This directory defines a source-based benchmark for semantic wiki ingest.
It is intentionally not part of `tests/run-all.sh` yet.

The benchmark tests whether an ingester turns raw sources into the right
knowledge objects instead of collapsing named tools, lookup answers, ideas,
projects, and low-evidence notes into `concepts/`.

The first ten fixtures are a development set, not a held-out leaderboard. They
were originally synthetic and later de-instructed after audit feedback removed
source text that directly told the model which category to choose. Provider
runs also use neutral case-only capture and evidence paths so fixture slugs do
not leak category answers through filenames. Use this set to harden the scorer
and detect known regressions. Add a separate frozen challenge pack before
making broad model leaderboard claims.

## Fixture Shape

Each fixture is a directory:

```text
fixtures/<case-id>-<slug>/
  source.md
  context.yaml
  expected.yaml
  wiki_seed/        # optional
```

- `source.md` is the only source text the ingester should learn from.
- `context.yaml` contains capture metadata and any intentionally misleading
  hints such as `suggested_pages`.
- `expected.yaml` describes expected knowledge objects, not exact output files.
- `wiki_seed/` is copied into a temporary wiki before the source is ingested.

Gold labels must be written from `source.md` plus `context.yaml`, not from a
live wiki page that the current ingester already produced.
Do not put category-routing answers in `source.md`, such as "this is an
entity", "create a query", "comparison concept", "project record", or "do not
file this under concepts". The expected object belongs in `expected.yaml`; the
source should contain domain evidence.

## MVP Cases

| Case | Purpose |
| --- | --- |
| `0001-entity-tool-floor` | Named tool should become an entity, not a concept. |
| `0002-concept-mechanism-floor` | Mechanism should become a concept despite product mentions. |
| `0003-query-lookup-floor` | Reusable operator answer should become a query. |
| `0004-idea-proposal-floor` | Proposal should become an idea, not current docs. |
| `0005-bounded-project-floor` | Bounded migration should become a project when seeded. |
| `0006-mixed-multi-object-note` | One source should split into two entities, one concept, and one idea. |
| `0007-adversarial-suggested-pages` | `suggested_pages: concepts/...` should not override source evidence. |
| `0008-low-evidence-hold` | Rumor and non-repro evidence should stay held/raw. |
| `0009-merge-magnet-seeded` | Existing broad concept should not absorb a named entity. |
| `0010-faithfulness-trap` | Title bait must not create unsupported platform claims. |

## Primary Metrics

The future runner should report per-fixture results plus:

- required-object recall by kind;
- forbidden concept or dump rate;
- named-thing-in-concepts rate;
- under-split rate on multi-object fixtures;
- faithfulness violations;
- low-evidence hold quality.

Validation, index building, and source traceability are gates or diagnostics.
They are not averaged into a single semantic score.

## Runner

Validate fixture metadata and record the frozen current skill hash:

```bash
tests/benchmarks/semantic-ingest/run_baseline.py \
  --output-dir /tmp/semantic-ingest-baseline-validate
```

Run scorer negative controls:

```bash
tests/benchmarks/semantic-ingest/run_baseline.py --self-test
```

Run real detached ingesters only when paid/provider execution is intentional:

```bash
tests/benchmarks/semantic-ingest/run_baseline.py \
  --run-provider \
  --provider grok \
  --model grok-4.6 \
  --effort medium \
  --executable /Users/lukaszmaj/.grok/bin/grok \
  --output-dir tests/benchmarks/semantic-ingest/runs/baseline-grok-4.6-medium
```

Rescore existing wiki snapshots without calling a provider:

```bash
tests/benchmarks/semantic-ingest/run_baseline.py \
  --score-snapshots-dir tests/benchmarks/semantic-ingest/runs/baseline-grok-4.6-medium \
  --output-dir tests/benchmarks/semantic-ingest/runs/baseline-grok-4.6-medium-rescore
```

Use the same model and effort as the production ingester for the frozen
baseline. Higher efforts such as `xhigh` belong in separate oracle or challenge
runs, not in the production baseline.

Provider mode creates one temporary wiki per selected fixture, writes a
raw-direct capture, runs the existing dispatcher path, waits for terminal ingest
events, and writes `baseline.json` plus `baseline.md`. Per-case provider
diagnostics are copied to neutral `cases/<case-id>/provider-runs/` directories
before the disposable wiki is removed. Provider mode runs from an isolated
plugin root containing only `bin`, `scripts`, and `skills`, so the provider
does not receive the benchmark spec or gold labels through the normal prompt
path. Scoring is heuristic and gate-backed. It checks object matches plus
deterministic gates for terminal status, page validation, manifest validation,
index rebuild, current `raw/source.md` citation on touched pages, raw source
SHA and manifest SHA integrity, raw manifest references for touched pages,
`type`/path consistency, idea metadata, fixture-specific category control,
malformed frontmatter, and unassigned extra content pages.
Use the result to expose routing failures and candidates for human review, not
as a final model leaderboard.

Snapshot scoring exists because scorer changes are cheaper than provider
reruns. Use it after manual review exposes scoring artifacts such as negative
guardrail text (`does not exist`, `not implemented`) being mistaken for
positive unsupported claims.

## Source Policy

Fixtures in this MVP are synthetic and public-safe. Existing local `wiki/raw`
files may inform future fixtures only after copying, sanitizing, and usually
rewriting. Do not symlink live raw files into this benchmark. Do not include
private account data, campaign data, ASINs, spend, health details, legal or
family material, private handles, private vendor quotes, images of people, or
company-identifying file paths.
