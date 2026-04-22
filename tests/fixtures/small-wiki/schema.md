# Wiki Schema

## Role
main

## Categories
- `concepts/` — ideas, patterns, principles
- `entities/` — specific tools, services, APIs
- `sources/` — one summary page per ingested source
- `queries/` — filed Q&A worth keeping

## Tag Taxonomy (bounded)
- `#api` — API-related
- `#rate-limit` — rate limit / throttling
- `#browser` — browser automation
- `#research` — research findings
- `#pattern` — reusable patterns
- `#workaround` — known workarounds

## Numeric Thresholds
- Split a concept page: 2+ sources or 200+ lines
- Archive a raw source: referenced by 5+ wiki pages
- Restructure top-level category: 500+ pages within it

## Update Policy
- Keep existing claims; append new findings with dates
- Use `contradictions:` frontmatter field when pages disagree
- Never delete pages during ingest; mark `archived: true` in frontmatter
