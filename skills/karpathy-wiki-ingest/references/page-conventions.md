# Wiki page conventions (canonical)

Single source of truth for page format. The ingester writes pages following these conventions; the validator (`scripts/wiki-validate-page.py`) enforces them.

## Frontmatter

```yaml
---
title: "<page title>"
type: <category>           # plural form: concepts, entities, queries, ideas, projects, ...
tags: [tag1, tag2, ...]
sources:
  - raw/<basename>         # OR the literal string "conversation"
related:
  - /concepts/<slug>.md    # leading-slash, wiki-root-relative
created: "<ISO-8601 UTC>"
updated: "<ISO-8601 UTC>"
quality:
  accuracy: 1-5
  completeness: 1-5
  signal: 1-5
  interlinking: 1-5
  overall: <average>
  rated_at: "<ISO-8601 UTC>"
  rated_by: ingester       # OR "human" — human is sticky, ingester must not overwrite
---
```

## Cross-link convention

All cross-links in the page body and the `related:` frontmatter use
**wiki-root-relative paths with a leading `/`**:

- ✅ `[Auth flow](/concepts/auth-flow.md)`
- ✅ `related: [/concepts/auth-flow.md]`
- ❌ `[Auth flow](concepts/auth-flow.md)` (relative; breaks when read from a nested page)
- ❌ `[Auth flow](../concepts/auth-flow.md)` (relative; breaks when page moves)

## Quality block — never overwrite human ratings

If `rated_by: human`, the ingester MUST NOT change any quality field.
Human ratings are sticky. The ingester may add OTHER fields (sources,
related, etc.) but the quality block stays untouched.

If `rated_by: ingester` (or absent), the ingester re-rates on every
re-ingest.

## Page size threshold

Split a page when:
- It crosses 200 lines, OR
- It accumulates 2+ raw sources covering distinct subtopics.

The ingester decides; the title-scope check (see ingest skill) catches
the case where new evidence is broader than the existing page's slug.

## Category directory

`type:` MUST equal `path.parts[0]` (the top-level directory name,
plural form). Validated by `wiki-discover.py` against the actual
directory tree.
