# Hermes Agent `llm-wiki` Skill — Study for Karpathy Wiki v2

**Date:** 2026-04-22
**Subject of study:** `skills/research/llm-wiki/SKILL.md` as shipped in Hermes Agent.
**Purpose:** Inform the Karpathy Wiki v2 design (`/Users/lukaszmaj/dev/bigbrain/plans/karpathy-wiki-v2-design.md`) by extracting patterns worth copying, patterns to avoid, and Hermes-specific metadata that's safe for us to include.
**Companion research:** `karpathy_wiki_ecosystem.md`, `agentic-cli-skills-comparison.md`, `agentic-cli-headless-subagents.md`.

---

## Section 1 — Location and structure

**Primary copy (in-tree, the package distribution):**

```
/Users/lukaszmaj/dev/research/hermes-agent/skills/research/llm-wiki/
└── SKILL.md          # 460 lines, 17,298 bytes, ~2,543 words
```

**Deployed copies (seeded from the in-tree copy at install time):**

```
/Users/lukaszmaj/.hermes/skills/research/llm-wiki/SKILL.md
/Users/lukaszmaj/.hermes/hermes-agent/skills/research/llm-wiki/SKILL.md
```

The three files are byte-identical (`diff` exit 0) — Hermes simply copies the in-tree file on install.

**Hermes's `llm-wiki` is a single-file skill.** No `references/`, no `scripts/`, no `assets/`, no `hooks.json`, no Hermes plugin sidecar. Everything lives in the SKILL.md body as prose plus embedded code snippets. Strong signal that, for a wiki skill, the SKILL.md body alone can carry the full operational contract.

**Category placement:** `skills/research/` — deliberate framing as tooling for *investigating a domain*, not general note organization. The sibling `skills/note-taking/obsidian/` handles generic vaults.

---

## Section 2 — Full content summary of the SKILL.md

### Frontmatter (verbatim)

```yaml
---
name: llm-wiki
description: "Karpathy's LLM Wiki — build and maintain a persistent, interlinked markdown knowledge base. Ingest sources, query compiled knowledge, and lint for consistency."
version: 2.0.0
author: Hermes Agent
license: MIT
metadata:
  hermes:
    tags: [wiki, knowledge-base, research, notes, markdown, rag-alternative]
    category: research
    related_skills: [obsidian, arxiv, agentic-research-ideas]
    config:
      - key: wiki.path
        description: Path to the LLM Wiki knowledge base directory
        default: "~/wiki"
        prompt: Wiki directory path
---
```

Notes:

- **`description` is only 179 chars** — strikingly short vs. our v1 (~830 chars packed with triggers). Hermes relies on `metadata.hermes.tags` for keywords and on the body's "When This Skill Activates" section for trigger rules.
- **`metadata.hermes.config[]`** is the notable Hermes extension — declaring `wiki.path` as a user-promptable key with a default. The body references it as `${wiki_path}` / `skills.config.wiki.path`. Harmless to other CLIs.

### Body structure (460 lines of markdown)

12 top-level sections for a linear agent read:

1. Intro — wiki as RAG alternative; "division of labor" between human (curates sources, directs) and agent (summarizes, cross-refs, files).
2. **When This Skill Activates** — 5-bullet trigger list in prose (the full DO-TRIGGER rulebook lives here, not in frontmatter).
3. Wiki Location — documents `skills.config.wiki.path` with `~/wiki` fallback.
4. **Architecture: Three Layers** — `raw/`, Layer 2 wiki (`entities/`, `concepts/`, `comparisons/`, `queries/`), Layer 3 `SCHEMA.md`.
5. **Resuming an Existing Wiki (CRITICAL — do this every session)** — 3-step orientation protocol.
6. Initializing a New Wiki — 7 steps, including "ask the user what domain the wiki covers — be specific."
7. **SCHEMA.md Template** — ~70 lines: conventions, frontmatter spec, tag taxonomy, page thresholds, page shapes, Update Policy for contradictions.
8. index.md Template — sectioned by type; scaling rule: split sections at 50 entries, add `_meta/topic-map.md` at 200.
9. log.md Template — action log, rotated at 500 entries (`log-YYYY.md`).
10. **Core Operations**: Ingest (6 steps), Query (6 steps, "file valuable answers back"), Lint (11 steps including an embedded Python sketch for orphan detection).
11. Working with the Wiki — search patterns, bulk-ingest batching, archiving, Obsidian integration (+ 40-line `obsidian-headless` + systemd runbook).
12. Pitfalls — 10 "don't do this" bullets.

The body is pure instructional prose with embedded bash/python/markdown snippets. No flow control, no platform branching, no hook references — it's a guide for an agent, not a program.

---

## Section 3 — How Hermes's `llm-wiki` differs from our v2 design

| Design decision | Our v2 | Hermes `llm-wiki` |
|---|---|---|
| Capture mechanism | Automatic — agent writes `.wiki-pending/<ts>-<slug>.md` whenever wiki-worthy mid-session | **None.** Purely user-initiated. No capture queue. |
| Ingest triggering | Immediate background spawn per capture; detached headless CLI or subagent fallback | **Synchronous, in-session.** Never spawns a background worker. |
| Main vs project wiki | Two roles with propagation project → main | **Single wiki** at `${wiki.path}`. No scope split. |
| Headless/background | Core (`claude -p`, `codex exec`, `hermes chat -q`, `setsid`) | Not mentioned. `obsidian-headless` discussion is about the vault *reader*, not the ingester. |
| Locking / concurrency | Per-page `.locks/<slug>.lock`, stale reclaim at 5min; `.processing` renames at 10min | Not mentioned — the synchronous model sidesteps the class of problems. |
| Lint tiers | Three (inline, opportunistic, `wiki doctor`) | **Single tier**, user-invoked. 11 checks grouped by severity. |
| User commands | `wiki doctor` + `wiki status` | **None.** Natural-language dispatch only. |
| Cross-wiki propagation | Project → main, prompt-based evaluator | Not applicable (one wiki). |
| Drift detection on `raw/` | Hash-based (`.manifest.json` SHA-256) | Not implemented. Drift is whatever the user chooses to re-ingest. |
| Page frontmatter | `type/tags/created/updated/sources/related_files/also_in_main` | `title/created/updated/type/tags/sources` + optional `contradictions:` (worth stealing). |
| Link syntax | Plain markdown links (for LLM/GitHub parity) | **`[[wikilinks]]`** universally. Ecosystem survey agrees with Hermes. |
| SCHEMA file | `schema.md`, ingester reads before writing | `SCHEMA.md` — the most detailed part of the skill. ~70-line template. |
| Orientation protocol | Implicit | **Explicit, protocol-grade:** "Resuming an Existing Wiki (CRITICAL — do this every session)". |
| Page thresholds | Not mentioned | **Numeric:** 2+ sources → create, ~200 lines → split, supersession → archive. |
| Obsidian compatibility | Always-on, auto-written `.obsidian/app.json` | Compatibility assumed; no `.obsidian/` write. 40-line `obsidian-headless` + systemd runbook for servers. |
| Git integration | Every wiki is a git repo, auto-commit per ingest | Not mentioned. |
| Cost/model selection | Cheap for ingest, smart for doctor | Not in the skill (handled at Hermes CLI via `-m`). |

---

## Section 4 — Patterns worth borrowing (verbatim quotes where possible)

### 1. The "CRITICAL" orientation protocol — steal wholesale

> **Resuming an Existing Wiki (CRITICAL — do this every session)**
> ① Read `SCHEMA.md` ② Read `index.md` ③ Scan recent `log.md` (last 20-30 entries).
> Only after orientation should you ingest, query, or lint. This prevents: creating duplicate pages for entities that already exist; missing cross-references; contradicting the schema; repeating logged work.

Three Read calls, front-loaded every session. Directly addresses the error-baking failure mode from our ecosystem survey. Our v2 doesn't name this ritual. We should.

### 2. Numeric page thresholds in SCHEMA.md

> **Create** a page at 2+ source mentions or central-to-one-source. **Add to existing** otherwise. **Don't create** for passing mentions. **Split** at ~200 lines. **Archive** on full supersession (move to `_archive/`, drop from index).

Prevents "page per every proper noun" sprawl. 2-sources is a concrete agent-enforceable filter; 200-line split is a free lint rule.

### 3. Explicit scaling rules inside index.md and log.md

> **Scaling rule:** section > 50 entries → split by first letter/sub-domain. Index > 200 total → create `_meta/topic-map.md` by theme.
> log.md > 500 entries → rotate to `log-YYYY.md`.

The ecosystem's "wall at 100-200 pages" is addressed here with concrete per-file thresholds. Our design mentions auto-sharding but without numbers. Steal Hermes's.

### 4. The `contradictions:` frontmatter field + Update Policy

> 1. Check dates — newer generally supersedes older. 2. If genuinely contradictory, note both positions with dates/sources. 3. Mark in frontmatter: `contradictions: [page-name]`. 4. Flag for user review in the lint report.

Contradiction handling is one of the hard ecosystem critiques. Hermes's answer is a frontmatter list + a lint check. Deterministic, cheap, greppable.

### 5. Tag taxonomy bounded by SCHEMA.md

> Every tag on a page must appear in this taxonomy. If a new tag is needed, add it here first, then use it.

Pitfalls echo: *"freeform tags decay into noise."* Tag equivalent of a page threshold — without it, tags drift.

### 6. Minimum cross-link count per page

> Use `[[wikilinks]]` to link between pages (minimum 2 outbound links per page).
> Every page must link to at least 2 other pages.

Makes orphan detection a structural property — enforced at ingest, not discovered by lint after the fact.

### 7. Bulk ingest batching

> Read all sources first; identify all entities/concepts across all sources; check existing pages in one search pass (not N); create/update in one pass; update index once; single log entry for the batch.

Our background-ingester design spawns per capture — fine for one, wasteful for a 20-capture drain. Adopt this for drain ingests.

### 8. "Ask before mass-updating" guardrail

> If an ingest would touch 10+ existing pages, confirm scope with the user first.

Natural throttle against runaway ingests. Trivial to drop into the ingester prompt.

### 9. The three-layer framing (Raw / Wiki / Schema)

> **Layer 1 — Raw Sources:** Immutable. The agent reads but never modifies these.
> **Layer 2 — The Wiki:** Agent-owned markdown; created/updated/cross-referenced by the agent.
> **Layer 3 — The Schema:** `SCHEMA.md` — structure, conventions, tag taxonomy.

Cleanest mental-model articulation we've seen. Our design has the structure implicitly; Hermes names it.

### 10. Circled numerals (①②③) for Operations steps

Stylistic. Scannable, not parsed as headers by markdown renderers. Worth copying for the 500-line body's readability.

---

## Section 5 — Choices Hermes made that we should NOT copy

### 1. Synchronous, in-session ingest

Hermes's entire Ingest runs while the user waits. No `-p`, no `hermes chat -q --source tool`, no detach. Fine for short pastes; painful for a 30-page PDF. Our v2 explicitly rejects this — capture is cheap, ingest is expensive, and ingest must happen off the user's thread. Keep our background-ingester design.

### 2. Single-wiki scope

Hermes ships one wiki — no project scope, no propagation. Reasonable for a general research tool, but our v2 wants the main+project split (rare in the ecosystem but defensible because triggering and hook fan-out differ between scopes).

### 3. No capture mechanism

Hermes requires the user to explicitly say "ingest this" — the agent never writes `.wiki-pending/<ts>.md` autonomously. Misses the insights-that-emerge-during-normal-work case, which is the single biggest reason we're building v2.

### 4. The `obsidian-headless` + systemd section is out of scope for SKILL.md

Hermes spends ~40 lines on server-side Obsidian Sync (npm install, `ob login`, systemd unit file). That's a deployment runbook, not skill content. If we need it, push to `references/deployment.md`.

### 5. No git integration

Hermes skips git entirely. Our v2 makes every wiki a git repo for sync/history/loss-prevention. Don't drop git just because Hermes omitted it.

---

## Section 6 — Hermes-specific metadata conventions safe to include

All of these are ignored by Claude Code, OpenCode, Codex, and Cursor. They help Hermes users discover and configure the skill. Including them has no cost on other platforms.

**Use these verbatim (pattern from Hermes's own skill):**

```yaml
metadata:
  hermes:
    tags: [wiki, knowledge-base, research, notes, markdown, rag-alternative]
    category: research
    related_skills: [obsidian, arxiv]
    config:
      - key: wiki.path
        description: Path to the LLM Wiki knowledge base directory
        default: "~/wiki"
        prompt: Wiki directory path
```

Per-field:

- **`metadata.hermes.tags`** — keyword list. agentskills.io permits arbitrary `metadata` keys. Low-cost, discoverable in Hermes's hub.
- **`metadata.hermes.category`** — determines the install sub-folder (`~/.hermes/skills/research/llm-wiki/`). Without it Hermes flattens.
- **`metadata.hermes.related_skills`** — powers Hermes's "related" suggestions. List obsidian, arxiv, etc.
- **`metadata.hermes.config[]`** — the only piece that actually changes Hermes runtime behavior. `hermes config migrate` walks every skill's `config[]` and prompts the user per key. Declare `wiki.path` (main) and likely `wiki.project_path` so Hermes users get proper setup. Other CLIs ignore it.

**Safe-to-add platform-neutral fields** (already in Hermes's frontmatter): `version`, `license`, `author`.

**Do NOT add** `prerequisites.env_vars`, `prerequisites.commands`, or `platforms:` — these are Hermes-specific gates that don't help other CLIs and can unnecessarily restrict runs. Do runtime checks in scripts instead.

---

## Section 7 — Explicit recommendations for our SKILL.md

### Adopt (Hermes-proven, platform-neutral)

1. **"CRITICAL orientation protocol"** — first operational section; read SCHEMA → index → last-N log entries before any op, including automatic ones.
2. **SCHEMA.md as CAPITALIZED first-class file**, ~70-line template in the body (Hermes's as base, + our propagation/manifest fields).
3. **Numeric page thresholds** (2 sources, 200 lines, archive-on-supersession) baked into the SCHEMA template.
4. **`contradictions:` frontmatter + Update Policy** — greppable, lint-able.
5. **Tag taxonomy bounded by SCHEMA** — add tag before use.
6. **Minimum 2 outbound links per page** — structural, enforced at ingest.
7. **Bulk-ingest batching** for the drain ingester.
8. **"Ask before mass-updating (10+ pages)"** ingester guardrail.
9. **Three-layer framing** (Raw / Wiki / Schema) named in the intro.
10. **Index scaling** (50→split, 200→`_meta/topic-map.md`) + **log rotation** (500→`log-YYYY.md`).
11. **Hermes `metadata.hermes.*` stanza** in frontmatter — free Hermes wiring, ignored elsewhere.

### Do NOT adopt

1. **Synchronous ingest** — keep the background ingester (the core of our value proposition).
2. **Single-wiki scope** — keep main + project.
3. **No capture mechanism** — automatic capture is v2's key differentiator.
4. **`[[wikilinks]]` everywhere** — we chose plain markdown links, but this is worth re-opening as a design question. Ecosystem survey + Hermes both go Obsidian-native; our "LLMs/GitHub handle full-path links better" rationale is not settled.
5. **Embedded `obsidian-headless` + systemd runbook** — push to `references/deployment.md` if we want it.
6. **179-char description** — OpenCode needs trigger verbs in the description for its explicit-invoke matcher. Keep ours closer to v1 length but more structured.

### Translate from Hermes to Claude Code

- `skills.config.wiki.path` injection → Claude Code has no equivalent. Document the fallback chain in prose: *"wiki lives at `$WIKI_MAIN` if set, else `.wiki-config` in cwd for project scope, else `~/wiki`"*.
- `search_files` → genericize (`Grep`/`Glob` on Claude Code). Use prose like *"search recursively for X in *.md"*.
- `read_file offset=<last 30 lines>` → `Read` with `offset`/`limit`. Prose: *"read the last 20-30 lines of log.md"*.

### MVP-specific (Claude Code first)

- Copy the Hermes `metadata.hermes.*` stanza verbatim shape — Claude Code reads `metadata` tolerantly; Hermes users get full wiring free.
- Keep hooks out of SKILL.md (Hermes does the same — hooks live in plugins, not skills). Ship platform adapters separately per our cross-platform research.
- Target 300-500 lines for the body. Hermes's 460 is near the spec's "500 lines / 5k tokens" cap. Push deep ops into `references/` past that.

### One pattern to highlight: the single-file skill

Hermes ships `llm-wiki` as a *single file* — no `references/`, no `scripts/`, no `assets/`. Our v1 `wiki/SKILL.md` already links to `references/operations.md`. Hermes's choice suggests a single-file skill is enough for the first cut — the ingester logic is prose, not code. Worth starting v2 the same way and carving out `references/` only when the body exceeds ~500 lines or a sub-topic needs multi-operation reuse.

---

## Sources

- `/Users/lukaszmaj/dev/research/hermes-agent/skills/research/llm-wiki/SKILL.md` — primary subject (460 lines, 2,543 words)
- `/Users/lukaszmaj/.hermes/skills/research/llm-wiki/SKILL.md` — deployed copy (identical)
- `/Users/lukaszmaj/dev/research/hermes-agent/skills/note-taking/obsidian/SKILL.md` — sample Hermes skill (single-file, minimal frontmatter)
- `/Users/lukaszmaj/dev/research/hermes-agent/skills/productivity/linear/SKILL.md` — sample Hermes skill (with `prerequisites` stanza)
- `/Users/lukaszmaj/dev/research/hermes-agent/skills/research/arxiv/SKILL.md` — sample Hermes skill (with `related_skills`, has `scripts/` subdir)
- `/Users/lukaszmaj/dev/research/hermes-agent/skills/research/blogwatcher/SKILL.md` — sample Hermes skill (with `prerequisites.commands`)
- `/Users/lukaszmaj/dev/research/hermes-agent/plugins/memory/hindsight/plugin.yaml` — confirmation that Hermes hooks live in plugins (not skills)
- `/Users/lukaszmaj/dev/bigbrain/plans/karpathy-wiki-v2-design.md` — our design doc (the target of the comparison)
- `/Users/lukaszmaj/dev/bigbrain/research/karpathy_wiki_ecosystem.md` — ecosystem survey context
- `/Users/lukaszmaj/dev/bigbrain/research/agentic-cli-skills-comparison.md` — Hermes frontmatter field reference
- `/Users/lukaszmaj/dev/bigbrain/research/agentic-cli-headless-subagents.md` — Hermes headless mechanics (`hermes chat -q`, `delegate_task`, `/background`)
- `/Users/lukaszmaj/.claude/skills/wiki/SKILL.md` — our v1 general wiki (to be replaced)
- `/Users/lukaszmaj/.claude/skills/project-wiki/SKILL.md` — our v1 project wiki (to be merged into v2)
