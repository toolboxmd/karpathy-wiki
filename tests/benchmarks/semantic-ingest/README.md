# Semantic Ingest Benchmark

This directory defines a source-based benchmark for semantic wiki ingest.
It is intentionally not part of `tests/run-all.sh` yet.

The benchmark tests whether an ingester turns raw sources into the right
knowledge objects instead of collapsing named tools, lookup answers, ideas,
projects, and low-evidence notes into `concepts/`.

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

## Source Policy

Fixtures in this MVP are synthetic and public-safe. Existing local `wiki/raw`
files may inform future fixtures only after copying, sanitizing, and usually
rewriting. Do not symlink live raw files into this benchmark. Do not include
private account data, campaign data, ASINs, spend, health details, legal or
family material, private handles, private vendor quotes, images of people, or
company-identifying file paths.
