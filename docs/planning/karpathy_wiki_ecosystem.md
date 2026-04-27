# Karpathy LLM Wiki Ecosystem — 3 Weeks After Launch

**Research date:** 2026-04-22
**Subject:** community implementations of Karpathy's gist [442a6bf](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f) (pub. Apr 4, 2026; ~5k stars, ~4.9k forks at time of writing) and the two launch tweets.
**Our skill:** `~/.claude/skills/{wiki,project-wiki}` — two skills, Stop-hook + SessionStart-hook + verbose SKILL.md triggering, raw/→wiki/ layout, ingest/query/lint.

---

## 1. Notable implementations

| # | Project | Stars | What it ships | Why it matters |
|---|---|---|---|---|
| 1 | [Astro-Han/karpathy-llm-wiki](https://github.com/Astro-Han/karpathy-llm-wiki) | 575 | Single Agent-Skills-compatible skill (Claude Code / Cursor / Codex / OpenCode). raw/ → wiki/, ingest/query/lint. | Most installed **single-skill** implementation. Explicitly cross-platform via the agentskills.io standard — no hooks, manual invocation. "Production-tested" on a 94-article corpus. |
| 2 | [kfchou/wiki-skills](https://github.com/kfchou/wiki-skills) | 87 | **5 separate skills**: wiki-init, wiki-ingest, wiki-query, wiki-lint, wiki-update. SCHEMA.md + severity-tiered lint reports (red/yellow/blue). | Most split architecture. No hooks — entirely manual. Demonstrates the "one big skill vs. many small skills" tension. |
| 3 | [AgriciDaniel/claude-obsidian](https://github.com/AgriciDaniel/claude-obsidian) | 2.8k | Obsidian-native plugin: `/wiki`, `/save`, `/autoresearch`, `/canvas` slash commands + SessionStart/Stop "hot cache" hooks. Reads/writes vault via Local REST API MCP. | **The breakout hit.** Uses **exactly our hook pattern** (SessionStart + Stop). Introduces `wiki/hot.md` — a short-lived cache file refreshed between sessions. Proves the hook approach can scale. |
| 4 | [skyllwt/OmegaWiki](https://github.com/skyllwt/OmegaWiki) | 358 | 23 skills across research lifecycle (daily-arxiv, ideate, novelty, exp-run, paper-draft…). 9 entity types, 9 typed relationships stored in `graph/edges.jsonl`. GitHub Actions cron. | Furthest from Karpathy's minimalism. Shows **where the pattern goes when pushed**: typed graph layer, cron (not hooks) for ingestion, domain-specific skills rather than generic ingest/query/lint. |
| 5 | [ussumant/llm-wiki-compiler](https://github.com/ussumant/llm-wiki-compiler) | 221 | Single plugin with subcommands (`/wiki-init`, `/wiki-compile`, `/wiki-ingest`…). **Dual mode: knowledge OR codebase.** SessionStart context injection. Coverage tags (`[coverage: high/medium/low]`). | The closest parallel to **our general+project split**, but unified in one plugin with auto-detection. Cites cost numbers ($2.60 first compile, $0.30 incremental). |
| 6 | [coleam00/claude-memory-compiler](https://github.com/coleam00/claude-memory-compiler) | (covered in [Cognition blog](https://www.cognitionus.com/blog/claude-memory-compiler-guide)) | SessionStart/Stop hooks capture transcripts, Agent SDK extracts decisions, LLM compiles into `/architecture`, `/decisions`, `/patterns`, `/glossary`. Separate MCP server so the agent reads its own wiki. | Best example of **session-transcript-as-source** pattern. Codebase-focused; proves hooks are the community's preferred trigger for project wikis. |
| 7 | [stevesolun/ctx](https://github.com/stevesolun/ctx) | (prominent) | Skill/agent recommendation engine built on a Karpathy wiki (1,789 skills, 454k graph edges). **PostToolUse + Stop hooks.** Drift detection + quality scoring. | Shows a **third hook** (PostToolUse) nobody else uses. Treats skills themselves as the wiki's entities. |
| 8 | [Ar9av/obsidian-wiki](https://github.com/Ar9av/obsidian-wiki) | 544 | Symlink-based skill distribution to Claude/Cursor/Windsurf/Codex/Gemini. Delta tracking via `.manifest.json` prevents re-ingest. Optional QMD semantic search. | Best **multi-agent portability**. Manifest-based drift detection is a cleaner pattern than our bash drift-check. |
| 9 | [Pratiyush/llm-wiki](https://github.com/Pratiyush/llm-wiki) (a.k.a. llmwiki) | 143 | Converts `.jsonl` session transcripts from 6 agent CLIs into a wiki + static HTML site. Confidence scoring, lifecycle states (draft/reviewed/verified/stale/archived). | Novel take: the wiki's raw/ is **agent session logs**, not curated docs. Schedule via launchd/systemd. |
| 10 | [Lum1104/Understand-Anything](https://github.com/Lum1104/Understand-Anything) | 8.7k | `/understand-knowledge` points at a Karpathy wiki and produces force-directed knowledge graphs with community clustering. Post-commit hook for incremental graph patching. | Biggest-starred project in the ecosystem. Treats the wiki as **input** to visualization, not the primary artifact. |
| 11 | [toolboxmd/karpathy-wiki](https://github.com/toolboxmd/karpathy-wiki) | 63 | **Literally mirrors our design:** two skills (general + project), Stop hook, SessionStart drift hook, ingest/query/lint. | Proof our architecture is not unique. Smaller footprint than ours but identical approach. |
| 12 | [rohitg00 "LLM Wiki v2"](https://gist.github.com/rohitg00/2067ab416f7bbe447c1977edaaa681e2) | — | Gist proposing: confidence scoring, forgetting curves, BM25+vector+graph hybrid search, typed relationships, SessionStart/Stop/periodic hooks, self-healing lint. | The **reference "next-gen" design doc** everyone is citing. Most concrete critique of what Karpathy left out. |
| 13 | [lucasastorian/llmwiki](https://github.com/lucasastorian/llmwiki) + [cachezero on HN](https://news.ycombinator.com/item?id=47667723) | — | `npm i -g cachezero` — Chrome extension captures bookmarks → Hono server + LanceDB vectors → Quartz static site → Obsidian graph. | The "npm-install-it" entrypoint. Introduces the **vector-layer-beside-the-wiki** pattern. |

---

## 2. Design-pattern convergence

### Where the community agrees

- **File layout:** `raw/` + `wiki/` + `index.md` + `log.md` + schema file is near-universal. Almost nobody deviates from Karpathy's original three-layer split.
- **Operations vocabulary:** ingest / query / lint is the lingua franca. Even OmegaWiki's 23 skills map onto those three primitives at the base layer.
- **Frontmatter:** YAML with `title / type / tags / created / updated / sources` is standard. `type` vocabulary (concept / entity / source / query / overview) matches ours almost exactly.
- **Wikilinks `[[...]]`:** everyone uses them — Obsidian-compatible syntax has won, even in non-Obsidian projects.
- **Schema as first-class file:** the v2 gist and the [Aaron Fulkerson production writeup](https://aaronfulkerson.com/2026/04/12/karpathys-pattern-for-an-llm-wiki-in-production/) both call schema.md the most important file in the system. We have this.

### Where the community is split

| Question | Camp A | Camp B | Verdict |
|---|---|---|---|
| Trigger mechanism | **Manual commands** (Astro-Han, kfchou, llm-wiki-compiler) | **Hooks** (claude-obsidian, claude-memory-compiler, ctx, toolboxmd, us) | **Roughly 50/50.** Hook camp is smaller in repo count but much larger in stars (claude-obsidian 2.8k alone). Hooks are winning on momentum. |
| Skill granularity | One big skill with sub-ops (Astro-Han, llm-wiki-compiler) | Many small skills (kfchou=5, OmegaWiki=23) | **Mild lean toward multi-skill**, but the split is along Unix-vs-monolith lines, not clear winner. |
| UI | **Plain filesystem** (most CLI tools) | **Obsidian-first** (claude-obsidian, ScrapingArt stack, Ar9av) | **Obsidian is the dominant UI layer** by star count. Filesystem-only tools are still widely shipped but seen as "headless backends." |
| Scope | Only one wiki type | Both general + project (us, llm-wiki-compiler with auto-detect, Lum1104) | **Minority supports both.** Most ship one scope. Our split into two skills is rare; llm-wiki-compiler's auto-detect is the preferred unification. |
| Search past ~150 pages | Rely on index.md alone | Add BM25 + vectors (cachezero, ScrapingArt's qmd, Ar9av's QMD) | Everyone who has run >150 pages agrees index.md alone breaks. **Hybrid search is converging as the fix**. |
| Drift detection | Bash script comparing timestamps (us) | Manifest file with content hashes (Ar9av's `.manifest.json`) | Ar9av's pattern is cleaner. Hash-based > time-based. |

### Notable schema innovations

- **`hot.md`** (claude-obsidian): short-lived session context cache refreshed on SessionStop.
- **Coverage tags** (llm-wiki-compiler): `[coverage: high/medium/low]` annotations per section.
- **Lifecycle states** (llmwiki): draft / reviewed / verified / stale / archived.
- **Typed relationships** (OmegaWiki, v2 gist): 9 link types — extends / contradicts / supports / supersedes / etc. — stored as edges alongside markdown.
- **Confidence scoring** (v2 gist): each claim carries a confidence number that decays via Ebbinghaus-style forgetting curve unless reinforced.

---

## 3. Pitfalls and critiques

From HN threads ([47640875](https://news.ycombinator.com/item?id=47640875), [47656181](https://news.ycombinator.com/item?id=47656181), [47667723](https://news.ycombinator.com/item?id=47667723)), [Mehul Gupta's "Bad Idea" piece](https://medium.com/data-science-in-your-pocket/andrej-karpathys-llm-wiki-is-a-bad-idea-8c7e8953c618), and Aaron Fulkerson's production writeup:

- **Scaling wall at 100-200 pages.** Index.md alone becomes too long for single-pass reading. Repeated across HN, the v2 gist, and multiple blog posts. Lint becomes O(n²) past this point.
- **Error baking.** Unlike RAG, which verifies against source each query, an LLM wiki hardcodes LLM summaries. A misread in the first ingest propagates across 10-15 pages. HN top comment: "the compounding will just be rewriting valid information with less terse information."
- **Traceability loss.** Answers blend generated summaries with linked fragments — hard to answer "where did this come from?" once the wiki matures.
- **Synthesis vs. learning.** Multiple commenters note delegating the wiki-writing loses the cognitive benefit of doing it yourself.
- **Drift at the source ↔ wiki boundary.** Lint must catch "source says X, wiki says Y" — Karpathy's original spec is thin here; v2 gist proposes self-healing lint.
- **Production lessons (Fulkerson):** first lint pass on a ~hundreds-of-files vault found 23 orphan files and 11 broken cross-references. Suggests linting needs to run often, not just on demand.
- **"Kicking the can down the road"** (HN): the wiki just shifts RAG's retrieval problem to an ingest-time synthesis problem — without solving it.

---

## 4. How our skill compares

**Verdict: our approach is substantially aligned with community consensus, with one outlier choice that is defensible and two choices that should be revisited.**

Aligned:
- raw/ → wiki/ + log.md + index.md layout — standard.
- ingest / query / lint operations — standard.
- Frontmatter vocabulary (concept/entity/source/query/overview) — standard.
- Wikilinks — standard.
- SessionStart + Stop hook combo — **matches claude-obsidian (2.8k stars), toolboxmd, claude-memory-compiler**. This is the dominant trigger pattern in the "automation" camp.

Outlier but defensible:
- **Two separate skills (general + project) instead of one auto-detecting skill.** We're rare here — llm-wiki-compiler auto-detects in a single plugin (221 stars), which is the more popular unification. Our split is defensible because: (a) SKILL.md triggering descriptions can be more precise when scoped; (b) hooks fire differently for the two scopes (git diff vs. raw/ scan); (c) OmegaWiki's 23 skills prove fine-grained works. But if a user installs both, triggering collisions are possible.

Should revisit:
- **Stop hook using `type: "prompt"` (LLM-decided).** Most stop-hook implementations in the community use `type: "command"` running a deterministic script that writes a marker, and the *next* SessionStart picks it up. Our "let the agent decide at Stop" is fragile: the agent may be out of context, tool-limited, or running concurrently with user intent. claude-obsidian's pattern is: Stop hook → bash script → "hot cache" refresh; no LLM reasoning at Stop time. Our approach adds non-determinism and latency at task-end.
- **Bash drift-check on every SessionStart.** Ar9av's `.manifest.json` with content hashes is strictly better than timestamp/mtime bash scripts: resilient to `touch`, cp, clones, and CI. Our approach will produce false positives.

---

## 5. Top 3 concrete suggestions

1. **Replace the Stop `prompt` hook with a deterministic Stop `command` + next-session-pickup flow.** On Stop, a bash script writes `wiki/.pending-ingest` listing modified raw/ files since the last index.md mtime. On the next SessionStart, the drift script sees this marker and either (a) asks the user to confirm ingest or (b) queues it as the first task. Removes non-deterministic agent-at-Stop calls; matches the dominant community pattern (claude-obsidian, claude-memory-compiler). **This is the highest-leverage change.**

2. **Switch drift detection from timestamps to a content-hash manifest.** Add `wiki/.manifest.json` mapping `raw/*` paths to SHA-256 + last-ingested timestamp. The SessionStart script diffs current hashes vs. manifest. Matches Ar9av/obsidian-wiki; eliminates false positives on file moves, clones, and `touch`. Trivial to implement, big reliability win.

3. **Add a scaling-escape-hatch at ~150 pages.** Before the community's documented wall, build in: (a) auto-sharding index.md into per-category catalog files once it exceeds ~8k tokens; (b) a `wiki query --semantic` path that shells out to qmd / ripgrep for content search when the page count is high; (c) a lint rule that warns when index.md exceeds the threshold. We can ship this as a `wiki/index/` directory that takes over from a single index.md — cheaper than introducing BM25+vectors, and enough to push the limit to ~500 pages per the community's production reports.

Honorable mentions worth considering later: lifecycle states on pages (draft/verified/stale — from llmwiki), coverage tags per section (from llm-wiki-compiler), and a `hot.md` session-context cache refreshed on SessionStop (from claude-obsidian, proven at scale).

---

## Sources

Primary:
- [Karpathy gist (llm-wiki.md)](https://gist.github.com/karpathy/442a6bf555914893e9891c11519de94f)
- [LLM Wiki v2 gist (rohitg00)](https://gist.github.com/rohitg00/2067ab416f7bbe447c1977edaaa681e2)
- [HN: LLM Wiki – idea file](https://news.ycombinator.com/item?id=47640875)
- [HN: Show HN – LLM Wiki open-source impl](https://news.ycombinator.com/item?id=47656181)
- [HN: Show HN – CacheZero](https://news.ycombinator.com/item?id=47667723)

Implementations:
- [Astro-Han/karpathy-llm-wiki](https://github.com/Astro-Han/karpathy-llm-wiki)
- [kfchou/wiki-skills](https://github.com/kfchou/wiki-skills)
- [AgriciDaniel/claude-obsidian](https://github.com/AgriciDaniel/claude-obsidian)
- [skyllwt/OmegaWiki](https://github.com/skyllwt/OmegaWiki)
- [ussumant/llm-wiki-compiler](https://github.com/ussumant/llm-wiki-compiler)
- [coleam00/claude-memory-compiler](https://github.com/coleam00/claude-memory-compiler)
- [stevesolun/ctx](https://github.com/stevesolun/ctx)
- [Ar9av/obsidian-wiki](https://github.com/Ar9av/obsidian-wiki)
- [Pratiyush/llm-wiki](https://github.com/Pratiyush/llm-wiki)
- [Lum1104/Understand-Anything](https://github.com/Lum1104/Understand-Anything)
- [toolboxmd/karpathy-wiki](https://github.com/toolboxmd/karpathy-wiki)
- [ScrapingArt/Karpathy-LLM-Wiki-Stack](https://github.com/ScrapingArt/Karpathy-LLM-Wiki-Stack)
- [ekadetov/llm-wiki](https://github.com/ekadetov/llm-wiki)
- [lucasastorian/llmwiki](https://github.com/lucasastorian/llmwiki)

Commentary & critique:
- ["Andrej Karpathy's LLM Wiki is a Bad Idea" — Mehul Gupta](https://medium.com/data-science-in-your-pocket/andrej-karpathys-llm-wiki-is-a-bad-idea-8c7e8953c618)
- [Karpathy's pattern in production — Aaron Fulkerson](https://aaronfulkerson.com/2026/04/12/karpathys-pattern-for-an-llm-wiki-in-production/)
- [claude-memory-compiler guide — Cognition](https://www.cognitionus.com/blog/claude-memory-compiler-guide)
- [Karpathy's LLM Wiki: Complete Guide — antigravity.codes](https://antigravity.codes/blog/karpathy-llm-wiki-idea-file)
- [LLM Wiki Skill: Build a Second Brain — Alireza Rezvani (Medium)](https://alirezarezvani.medium.com/llm-wiki-skill-build-a-second-brain-with-claude-code-and-obsidian-2282752758c1)
