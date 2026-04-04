---
name: karpathy-project-wiki
description: "Build and maintain a persistent Karpathy Project Wiki — an auto-updating knowledge base for your codebase based on Andrej Karpathy's LLM Wiki pattern. TRIGGER when: user modifies project files (code, configs, docs), adds new modules, refactors architecture, merges PRs, asks about project architecture ('how does auth work', 'what's the data flow', 'where is X implemented', 'explain this module', 'what patterns does this project use'), or requests a documentation health check ('is the wiki up to date', 'check the docs', 'find undocumented code'). Also triggers when git shows changes since last wiki update. DO NOT TRIGGER when: user wants a general research wiki on external topics (use karpathy-wiki instead), asks to read a single specific file, or asks general programming questions unrelated to this project."
---

# Karpathy Project Wiki

Auto-maintain a living knowledge base for your codebase. Based on Karpathy's LLM Wiki pattern adapted for source code: the LLM reads your project, builds interlinked markdown documentation, and keeps it current as the code evolves. You never write the docs — the LLM does.

## Decision tree

```
Does wiki/ exist in the project?
├─ No → User says "init project wiki" or "document this project" → Run INIT
├─ Yes →
│   ├─ Code changed since last log.md entry? → Run INGEST
│   ├─ User asks about architecture, patterns, modules? → Run QUERY
│   ├─ User says "lint docs", "check wiki", "find gaps"? → Run LINT
│   └─ Major refactor or new module added? → Run INGEST (structural)
```

## How this differs from karpathy-wiki

- **No raw/ directory** — the codebase IS the source material
- **Entity pages** = services, modules, APIs, database models, config files
- **Concept pages** = patterns, auth flow, error handling, deployment, testing strategy
- **Drift detection** via git diff, not file scanning
- **Architecture diagrams** as mermaid in markdown

## Wiki structure

```
wiki/
├── index.md            # Content catalog — every page with link + summary
├── log.md              # Append-only chronological record of all operations
├── schema.md           # Wiki conventions, co-evolved with user
├── overview.md         # Architecture overview, tech stack, key decisions
├── concepts/           # Pattern pages (e.g., concepts/auth-flow.md)
├── entities/           # Component pages (e.g., entities/user-service.md)
└── queries/            # Filed query results worth keeping
```

## Operations

### INIT
1. Scan codebase structure — identify languages, frameworks, key directories
2. Read existing docs (README, CLAUDE.md, doc comments, config files)
3. Read git log for recent history and key contributors
4. Write `overview.md` — architecture, tech stack, directory layout, key decisions
5. Create entity pages for major components (services, modules, APIs)
6. Create concept pages for architectural patterns (auth, error handling, data flow)
7. Generate mermaid diagrams for key flows
8. Create `index.md`, `log.md`, `schema.md`
9. Add to project CLAUDE.md: "This project has a wiki at wiki/. Consult wiki/index.md for architecture questions. Keep wiki updated after code changes."

### INGEST (on code changes)
1. Detect what changed — `git diff` or files modified in current session
2. Read changed files, understand the nature of changes
3. Classify: structural (new module, renamed API, changed architecture) vs trivial (formatting, comments, minor fixes)
4. For structural changes: update relevant entity/concept pages
5. Update `overview.md` if architecture shifted
6. Update cross-references and mermaid diagrams
7. Update `index.md`, append to `log.md`
8. Skip trivial changes — don't pollute the wiki with noise

### QUERY
1. Read `index.md` to find relevant pages
2. Read wiki pages + source code for additional context if needed
3. Synthesize answer citing both wiki pages and source files (`file:line`)
4. If answer produces valuable synthesis, file in `queries/`
5. Update `index.md` if new page created, append to `log.md`

### LINT
1. Compare wiki against actual codebase state
2. Check: are all major modules documented? Do entity pages reference files that still exist? Are architecture descriptions current? Are there new modules without wiki pages?
3. Fix what's stale, flag what needs human judgment
4. Suggest documentation gaps and questions to investigate
5. Append to `log.md`

## Page conventions

Every wiki page has YAML frontmatter:
```yaml
---
title: Page Title
type: concept | entity | query | overview
tags: [tag1, tag2]
created: YYYY-MM-DD
updated: YYYY-MM-DD
related_files: [src/path/file.ts, src/other/file.ts]
---
```

- Use `[[wikilinks]]` for cross-references between wiki pages
- Reference source code as `src/path/file.ts:42` (file:line format)
- Use mermaid code blocks for architecture and flow diagrams
- Start every page with a 1-2 sentence summary

## Key rules

- The LLM writes and maintains the wiki. The user writes code.
- Source code is the source of truth — wiki documents it, never contradicts it.
- Focus on structural/architectural changes. Skip trivial edits.
- Every operation updates `index.md` and appends to `log.md`.
- When code and wiki disagree, the code wins — update the wiki.

See [references/operations.md](references/operations.md) for detailed workflows.
