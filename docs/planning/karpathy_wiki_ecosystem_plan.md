# Plan: Karpathy LLM Wiki Ecosystem Research

## Goal
Map what the community has shipped on top of Karpathy's LLM Wiki pattern (gist + 2 X posts, Apr 2-4, 2026) and honestly compare with our skill at ~/.claude/skills/{wiki,project-wiki}.

## Our skill recap (baseline for comparison)
- Two separate Claude Code skills: `karpathy-wiki` (general) + `karpathy-project-wiki` (code)
- Auto-triggering via: verbose SKILL.md description + Stop hook (prompt-type, LLM decides) + SessionStart hook (bash drift-check)
- Layout: raw/ (immutable) → wiki/ (compiled) + log.md + index.md
- Three ops: ingest, query, lint
- Page types: concept / entity / source / query / overview
- Wikilinks + YAML frontmatter

## Research streams (parallel)

### Stream A — Source material
1. Fetch the Karpathy gist directly — confirm content, patterns, any author revisions
2. Try to fetch both X posts via nitter/xcancel; fall back to cloudflare-browser-rendering if needed
3. Look for HN thread(s) discussing the gist/posts

### Stream B — GitHub ecosystem
1. GitHub code search: "karpathy wiki", "llm wiki", "karpathy knowledge base", "llm-wiki"
2. Gist fork graph — look at forks of 442a6bf555914893e9891c11519de94f
3. Search for repos that cite the gist URL in README
4. Target keywords: "karpathy-wiki", "llm-wiki", "wiki-skill", "knowledge-base-skill", "claude skill wiki"

### Stream C — Platform implementations
1. Claude Code skills directory / plugin marketplaces
2. Cursor rules libraries
3. Obsidian community plugins citing Karpathy
4. MCP servers for wiki building

### Stream D — Commentary & critique
1. HN, Reddit (r/LocalLLaMA, r/ClaudeAI, r/ObsidianMD), dev.to, Substack
2. Search for "karpathy wiki" + "tried", "review", "critique", "problems", "doesn't work"

## Analysis questions to answer
- Hook / cron / manual / stop-hook / session-start — what did others pick?
- Split skills vs monolithic?
- Obsidian vs plain fs vs custom UI?
- General + project wikis, or just one?
- Schema innovations beyond Karpathy's original?

## Output
Single report at /Users/lukaszmaj/dev/bigbrain/research/karpathy_wiki_ecosystem.md
Sections 1-5 per user spec, 800-1500 words.
