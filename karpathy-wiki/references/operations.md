# Wiki Operations — Detailed Reference

## Ingest Workflow

When a new source is added to `raw/`:

1. **Read the source** — full content, note format (article, paper, dataset, image)
2. **Extract key information:**
   - Main claims, findings, or arguments
   - Named entities (people, orgs, tools, products)
   - Concepts and themes
   - Data points, statistics, quotes worth preserving
   - Contradictions with existing wiki content
3. **Discuss with user** (if interactive) — share 3-5 key takeaways, ask what to emphasize
4. **Write source summary** — `sources/<slugified-title>.md` with frontmatter:
   ```yaml
   ---
   title: "Article Title"
   type: source
   tags: [topic1, topic2]
   created: 2026-04-04
   updated: 2026-04-04
   original: raw/filename.md
   word_count: ~N
   ---
   ```
   Body: structured summary (not a copy), key quotes, main arguments, relevance to existing wiki topics.

5. **Create or update concept pages** — for each significant concept in the source:
   - If `concepts/<concept>.md` exists: add new information, update synthesis, note if source confirms or contradicts existing claims
   - If new concept: create page with definition, context, connections to other concepts
   - Add wikilinks to related concepts and entities

6. **Create or update entity pages** — for each significant entity:
   - If `entities/<entity>.md` exists: add new data points, update timeline
   - If new entity: create page with description, role, connections
   - Add wikilinks to related entities and concepts

7. **Update cross-references** — ensure all new pages link to relevant existing pages and vice versa. Check for:
   - Concepts mentioned in the source that have existing pages
   - Entities that appear across multiple sources
   - Themes that connect previously unrelated pages

8. **Update overview.md** — if the new source shifts the big picture, update the synthesis. Note new themes, strengthened arguments, or emerging contradictions.

9. **Update index.md** — add entries for all new pages, update summaries for modified pages.

10. **Append to log.md:**
    ```markdown
    ## [2026-04-04] ingest | Article Title
    - Source: raw/filename.md
    - Pages created: concepts/new-concept.md, entities/new-entity.md
    - Pages updated: concepts/existing.md, overview.md
    - Total pages touched: 12
    ```

## Query Workflow

When the user asks a question:

1. **Read index.md** — scan for relevant pages by topic, tags, summaries
2. **Read relevant pages** — follow wikilinks to gather connected information
3. **Synthesize answer:**
   - Cite wiki pages: `According to [Concept X](concepts/x.md)...`
   - Note confidence level — well-supported (multiple sources) vs. single-source claims
   - Flag contradictions if sources disagree
   - Identify gaps — what the wiki doesn't cover that would help answer fully
4. **Decide whether to file the answer:**
   - Does it synthesize across multiple pages in a new way? → File in `queries/`
   - Is it a simple lookup? → Don't file
   - Did it reveal a new connection? → File and add cross-references
5. **If filing:** write `queries/<question-slug>.md` with frontmatter, update index.md
6. **Append to log.md:**
   ```markdown
   ## [2026-04-04] query | How does X relate to Y?
   - Pages consulted: concepts/x.md, concepts/y.md, entities/z.md
   - Answer filed: queries/x-relates-to-y.md (or: not filed — simple lookup)
   ```

## Lint Workflow

Periodic health check:

1. **Read all pages** — build a mental map of the wiki's state
2. **Check for issues:**

   | Check | What to look for |
   |---|---|
   | Contradictions | Two pages making conflicting claims about the same thing |
   | Stale claims | Older pages superseded by newer sources |
   | Orphan pages | Pages with no inbound wikilinks |
   | Missing concepts | Terms mentioned frequently but lacking their own page |
   | Broken links | Wikilinks pointing to non-existent pages |
   | Data gaps | Topics partially covered — need more sources |
   | Thin pages | Pages with very little content that could be expanded |

3. **Fix what you can** — update stale claims, add missing cross-references, create pages for frequently-mentioned concepts
4. **Report what needs user input** — suggest sources to find, questions to investigate, contradictions that need human judgment
5. **Append to log.md:**
   ```markdown
   ## [2026-04-04] lint | Periodic health check
   - Issues found: 3 orphan pages, 2 contradictions, 5 missing concepts
   - Fixed: added cross-references to orphan pages, created 2 concept stubs
   - Needs attention: contradiction between sources/a.md and sources/b.md on topic Z
   - Suggested sources: [list of topics to research]
   ```

## Index.md Conventions

```markdown
# Wiki Index

## Overview
- [Overview](overview.md) — High-level synthesis (updated 2026-04-04)

## Concepts
- [Attention Mechanisms](concepts/attention.md) — Self-attention, cross-attention, and variants (3 sources, 2026-04-03)
- [Transformer Architecture](concepts/transformers.md) — Encoder-decoder, decoder-only, key innovations (5 sources, 2026-04-04)

## Entities
- [GPT-4](entities/gpt-4.md) — OpenAI's multimodal model, capabilities and limitations (2 sources, 2026-04-02)

## Sources
- [Attention Is All You Need](sources/attention-is-all-you-need.md) — Original transformer paper (2026-04-01)

## Queries
- [How does attention scale?](queries/attention-scaling.md) — Comparison of attention variants by compute cost (2026-04-03)
```

## Log.md Conventions

```markdown
# Wiki Log

## [2026-04-04] ingest | New Research Paper
- Source: raw/new-paper.pdf
- Pages created: concepts/new-idea.md
- Pages updated: overview.md, concepts/related.md, entities/author.md
- Total pages touched: 8

## [2026-04-03] query | How does X compare to Y?
- Pages consulted: concepts/x.md, concepts/y.md
- Answer filed: queries/x-vs-y.md

## [2026-04-02] lint | Weekly health check
- Issues found: 2 orphan pages, 1 broken link
- Fixed: all resolved
```

Entries are parseable: `grep "^## \[" wiki/log.md | tail -5` shows last 5 operations.
