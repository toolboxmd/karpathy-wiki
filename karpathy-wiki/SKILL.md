---
name: karpathy-wiki
description: "Build and maintain a persistent Karpathy Wiki — a compounding knowledge base of interlinked markdown files based on Andrej Karpathy's LLM Wiki pattern. TRIGGER when: user adds sources to raw/ (articles, papers, notes, images), pastes content to ingest, says 'add to wiki' or 'ingest this', asks synthesis questions ('what do we know about X', 'compare A and B', 'summarize research on Y', 'how does X relate to Y'), or requests a health check ('lint the wiki', 'check for inconsistencies', 'find gaps'). Also triggers when raw/ has unprocessed files. DO NOT TRIGGER when: user asks about project source code or architecture (use karpathy-project-wiki instead), wants simple file operations, or asks general questions unrelated to a wiki."
---

# Karpathy Wiki

Build and maintain a persistent, compounding knowledge base as interlinked markdown. Based on Karpathy's LLM Wiki pattern: raw sources are ingested once, compiled into a wiki, and kept current — not re-derived on every query.

## Decision tree

```
Does wiki/ exist in the project?
├─ No → User says "init wiki" or "start a wiki" → Run INIT
├─ Yes →
│   ├─ New files in raw/ not yet in log.md? → Run INGEST
│   ├─ User asks a question about the wiki's domain? → Run QUERY
│   ├─ User says "lint", "health check", "find gaps"? → Run LINT
│   └─ User pastes content or a URL to add? → Save to raw/, then INGEST
```

## Wiki structure

```
raw/                    # Immutable source documents (user curates)
wiki/
├── index.md            # Content catalog — every page with link + summary
├── log.md              # Append-only chronological record of all operations
├── schema.md           # Wiki conventions, co-evolved with user
├── overview.md         # High-level synthesis across all sources
├── concepts/           # Concept pages (e.g., concepts/attention.md)
├── entities/           # Entity pages (e.g., entities/gpt-4.md)
├── sources/            # One summary per ingested source
└── queries/            # Filed query results worth keeping
```

## Operations

### INIT
1. Create `wiki/` directory structure and `raw/` if missing
2. Write `schema.md` with default conventions (can be customized later)
3. Create empty `index.md` and `log.md`
4. Write `overview.md` placeholder
5. If `raw/` already has files, immediately run INGEST on all of them
6. Add `## Wiki` section to project CLAUDE.md: "This project has an LLM wiki at wiki/. Consult wiki/index.md for questions. Keep the wiki updated."

### INGEST
1. Read the new source in `raw/`
2. Discuss key takeaways with user (if interactive)
3. Write summary page in `sources/`
4. Create or update concept pages in `concepts/`
5. Create or update entity pages in `entities/`
6. Update cross-references (wikilinks) across touched pages
7. Update `overview.md` if the source shifts the big picture
8. Update `index.md` with new/changed pages
9. Append to `log.md`: `## [YYYY-MM-DD] ingest | Source Title`
10. One source should touch 10-15 wiki pages

### QUERY
1. Read `index.md` to find relevant pages
2. Read those pages + any related cross-references
3. Synthesize answer with citations to wiki pages
4. If the answer produces valuable synthesis, file it in `queries/`
5. Update `index.md` if a new page was created
6. Append to `log.md`: `## [YYYY-MM-DD] query | Question summary`

### LINT
1. Scan all wiki pages
2. Check for: contradictions between pages, stale claims, orphan pages (no inbound links), important concepts mentioned but lacking their own page, broken wikilinks, data gaps
3. Fix issues directly or report them to user
4. Suggest new sources to investigate and new questions to explore
5. Append to `log.md`: `## [YYYY-MM-DD] lint | Summary of findings`

## Page conventions

Every wiki page has YAML frontmatter:
```yaml
---
title: Page Title
type: concept | entity | source | query | overview
tags: [tag1, tag2]
created: YYYY-MM-DD
updated: YYYY-MM-DD
sources: [raw/filename.md]
---
```

- Use `[[wikilinks]]` for cross-references between pages
- Start every page with a 1-2 sentence summary
- Cite sources with `[source](../sources/name.md)`

## Index.md format

Organized by category. Each entry: `- [Page Title](path.md) — one-line summary (N sources, YYYY-MM-DD)`

## Log.md format

Append-only. Each entry: `## [YYYY-MM-DD] operation | Title`. Parseable with `grep "^## \[" wiki/log.md`.

## Key rules

- The LLM writes and maintains the wiki. The user curates sources and asks questions.
- Never modify files in `raw/` — they are immutable source of truth.
- Every operation updates `index.md` and appends to `log.md`.
- Good query answers get filed back into the wiki — explorations compound.
- When in doubt about which operation to run, read `log.md` tail and `index.md` to understand current state.

See [references/operations.md](references/operations.md) for detailed workflows.
