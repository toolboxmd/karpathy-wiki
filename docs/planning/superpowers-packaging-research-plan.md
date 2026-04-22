# Superpowers Packaging Layer Research Plan

## Goal
Audit the packaging and distribution layer of obra/superpowers (NOT the skills themselves) to inform the packaging strategy for our karpathy-wiki-v2 Claude Code skill with planned cross-platform expansion.

## Output
Single markdown report: `/Users/lukaszmaj/dev/bigbrain/research/superpowers-packaging-study.md` (2000-3500 words, heavy direct quotes).

## Phases

### Phase 1: Context reads (in order)
1. karpathy-wiki-v2-design.md
2. karpathy_wiki_ecosystem.md
3. agentic-cli-skills-comparison.md
4. agentic-cli-headless-subagents.md
5. superpowers-skill-style-guide.md
6. hermes-llm-wiki-study.md

### Phase 2: Gitingest bundle audit (targeted)
Search the 22k-line gitingest bundle for:
- Table of contents / directory listing at top
- Files: AGENTS.md, CLAUDE.md, GEMINI.md, package.json, gemini-extension.json
- Dirs: .claude-plugin/, .codex/, .cursor-plugin/, .opencode/, hooks/, commands/, scripts/, agents/, tests/, .github/
- Meta: .version-bump.json, RELEASE-NOTES.md, .gitattributes
- README install/uninstall sections

### Phase 3: Live GitHub repo
- `gh repo view obra/superpowers`
- `gh release list -R obra/superpowers`
- `gh release view v5.0.7 -R obra/superpowers`
- Fetch files missing from gitingest via `gh api repos/obra/superpowers/contents/...`
- Fetch README via gh or WebFetch

### Phase 4: Answer research questions A-G, write report

## Report structure
1. File-by-file audit at repo root
2. AGENTS.md + vendor-wrapper pattern (quoted)
3. Plugin manifest formats per platform (quoted)
4. Install/uninstall/bootstrap flow
5. Where hooks actually live (corrections)
6. Testing and release infrastructure
7. Recommended repo structure for karpathy-wiki (MVP through full cross-platform), concrete tree
