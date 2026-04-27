# Karpathy Wiki v2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the existing `~/.claude/skills/{wiki,project-wiki}` v1 skills with a single unified Claude Code skill that auto-captures wiki-worthy moments during work and ingests them into a persistent, git-versioned knowledge base via detached background workers.

**Architecture:** One skill (`karpathy-wiki`) handling two wiki roles (main at `~/wiki/`, project at `<project>/wiki/`) via role discrimination in a per-wiki TOML config file. Captures are markdown files in `<wiki>/.wiki-pending/`. Immediate detached headless ingestion via `claude -p &` subprocess (platform-extensible later). Two-level locking: atomic rename for capture claim, file lock for page edits. Git-backed with auto-init + auto-commit. Single SessionStart hook + single Stop hook at repo-level (`hooks/`), shell-only, emit zero model-visible context. Auto-init writes wiki structure on first invocation — no user commands for setup. Two user-facing commands: `wiki doctor` and `wiki status`.

**Tech Stack:**
- Claude Code plugin (packaged as `.claude-plugin/plugin.json`)
- Shell (bash) for hooks, locks, manifest ops; polyglot `.cmd` wrapper for Windows
- Python (stdlib only) for TOML parsing and complex capture operations
- Git for versioning
- SKILL.md per agentskills.io v1.0 spec
- Target v1 for Claude Code, forward-compatible with Codex/OpenCode/Cursor/Hermes via manifest additions

**Repo location (during development):** `/Users/lukaszmaj/dev/karpathy-wiki/` (to be created)

**Deploy-to location:** Symlink `~/.claude/plugins/karpathy-wiki → /Users/lukaszmaj/dev/karpathy-wiki` after testing passes

## Deliberate v1 scope cuts from the design doc

The design doc describes several mechanisms that v1 deliberately drops. These are not gaps — they are cuts. Future maintainers should not re-introduce them without explicit scope expansion.

- **`~/.wiki-config` home-level main-wiki pointer** — dropped. Main wiki location is hardcoded to `$HOME/wiki/` in v1. No override mechanism.
- **`$WIKI_MAIN` environment variable** — dropped. Config file is the sole source of truth; no env var fallback.
- **Cross-platform `agent_cli` / `headless_command` detection** — dropped. v1 hardcodes `claude` and `claude -p`. Post-MVP will add detection when we target Codex, OpenCode, Cursor, Hermes.
- **Stop-hook transcript sweep** — dropped. v1 ships Stop as a stub that only logs session-end. Transcript sweep was a backstop for captures the in-session agent missed; we rely on in-session capture alone for v1. Post-MVP adds the cheap-model sweep.
- **Tier-2 opportunistic lint** — dropped. v1 ships Tier-1 only (inline at ingest). Tier-3 (`wiki doctor`) is also a stub in v1.
- **`wiki doctor` implementation** — stub in v1 (`exit 1` with "not implemented" message). Post-MVP adds the deep-lint pass with smartest-model escalation.
- **Gemini CLI support** — post-MVP. Gemini needs a separate `GEMINI.md` sidecar per packaging research; not in MVP.
- **Cross-wiki propagation test coverage** — v1 ships the propagation logic in SKILL.md but without an automated test. Trust but verify manually during smoke test.

These cuts are why v1 is shippable in ~28 tasks. Post-MVP will incrementally fill them back in.

---

## Context — read these before starting

These files must be read end-to-end before starting implementation. They are the design source of truth.

1. `/Users/lukaszmaj/dev/bigbrain/plans/karpathy-wiki-v2-design.md` — full design doc
2. `/Users/lukaszmaj/dev/bigbrain/research/superpowers-skill-style-guide.md` — style rules for SKILL.md
3. `/Users/lukaszmaj/dev/bigbrain/research/superpowers-packaging-study.md` — repo structure conventions
4. `/Users/lukaszmaj/dev/bigbrain/research/agentic-cli-skills-comparison.md` — cross-platform skill spec
5. `/Users/lukaszmaj/dev/bigbrain/research/agentic-cli-headless-subagents.md` — headless/subagent invocation
6. `/Users/lukaszmaj/dev/bigbrain/research/hermes-llm-wiki-study.md` — reference implementation patterns
7. `/Users/lukaszmaj/dev/bigbrain/research/karpathy_wiki_ecosystem.md` — ecosystem survey

**v1 skill files to reference (but not modify during implementation):**
- `/Users/lukaszmaj/.claude/skills/wiki/` — current v1 general wiki skill
- `/Users/lukaszmaj/.claude/skills/project-wiki/` — current v1 project variant

**Superpowers reference files (already-proven patterns to study):**
- `/Users/lukaszmaj/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.6/hooks/run-hook.cmd` — polyglot hook wrapper
- `/Users/lukaszmaj/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.6/hooks/session-start` — SessionStart example
- `/Users/lukaszmaj/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.6/.claude-plugin/plugin.json` — plugin manifest
- `/Users/lukaszmaj/.claude/plugins/cache/claude-plugins-official/superpowers/5.0.6/.gitattributes` — LF enforcement

---

## File Structure

Before implementation, here is the complete file tree we will produce, with one-line responsibilities.

```
/Users/lukaszmaj/dev/karpathy-wiki/          (repo root)
├── .claude-plugin/
│   └── plugin.json                           Claude Code plugin manifest
├── .gitattributes                            Force LF on all text files (polyglot wrapper needs it)
├── .gitignore                                Standard Node/Python ignores + transcripts
├── AGENTS.md -> CLAUDE.md                    Git symlink (agentskills.io cross-vendor convention)
├── CLAUDE.md                                 Contributor guidelines for AI agents submitting PRs
├── GEMINI.md                                 Post-MVP: Gemini CLI always-on context
├── README.md                                 User-facing install + usage
├── RELEASE-NOTES.md                          Per-version changelog
├── package.json                              NPM metadata (plugin discovery, scripts)
├── .version-bump.json                        Files kept in lockstep for version sync
├── skills/
│   └── karpathy-wiki/                        Named after the project brand (the `toolboxmd/karpathy-wiki`
│       │                                     repo already has 63 stars under that name). Trade-off: a more
│       │                                     generic name like `wiki` would be a shorter invocation target
│       │                                     but would collide with any user-authored `skills/wiki/`.
│       │                                     The branded name is the deliberate choice for v1.
│       └── SKILL.md                          The skill itself (single-file, <500 lines)
├── hooks/
│   ├── hooks.json                            Claude Code plugin hook manifest (matcher + commands)
│   ├── session-start                         Extensionless bash: drift + drain
│   └── stop                                  Extensionless bash: session-end stub
├── scripts/
│   ├── wiki-init.sh                          Auto-init main or project wiki (idempotent)
│   ├── wiki-spawn-ingester.sh                Spawn detached headless ingester
│   ├── wiki-capture.sh                       Capture claim + archive (sourced)
│   ├── wiki-lock.sh                          Page-level locks (sourced)
│   ├── wiki-manifest.py                      Hash manifest for raw/ (build / diff)
│   ├── wiki-status.sh                        Read-only health report
│   ├── wiki-commit.sh                        Background git commit after ingest
│   ├── wiki-config-read.py                   Parse TOML config (stdlib tomllib)
│   └── wiki-lib.sh                           Shared bash helpers (logging, paths, config-get)
│
│ (Note: drift + drain are inlined inside hooks/session-start — no separate
│  wiki-drift-check.sh or wiki-drain-pending.sh scripts. wiki-doctor.sh is
│  stubbed inside bin/wiki — no separate script file. Both planned for
│  post-MVP extraction once behavior stabilizes.)
├── bin/
│   └── wiki                                  User-facing command dispatcher (doctor/status)
└── tests/
    ├── fixtures/
    │   ├── empty-wiki/                       Baseline empty wiki state
    │   ├── small-wiki/                       10-page wiki with realistic content
    │   └── sample-captures/                  Sample capture files
    ├── unit/
    │   ├── test-lib.sh                       wiki-lib.sh helpers (logging, slugify, roots)
    │   ├── test-config-read.sh               wiki-config-read.py tests
    │   ├── test-locks.sh                     Page-level lock tests
    │   ├── test-capture.sh                   Capture claim + archive tests (incl. concurrent)
    │   ├── test-manifest.sh                  Hash manifest build + diff tests
    │   ├── test-init.sh                      Auto-init idempotence tests
    │   ├── test-spawn-ingester.sh            Detached spawn fast-exit tests
    │   ├── test-commit.sh                    Auto-commit respects auto_commit flag
    │   └── test-status.sh                    Status report counts correctly
    ├── integration/
    │   ├── test-session-start.sh             SessionStart hook emits empty context, spawns
    │   ├── test-concurrent-ingest.sh         Two parallel ingesters on shared page
    │   ├── test-end-to-end-plumbing.sh       Full capture → hook → spawn chain
    │   └── self-review.sh                    Mechanical invariant verification
    ├── baseline/
    │   ├── RED-scenario-1-capture.md         No-skill baseline: does agent capture?
    │   ├── RED-scenario-2-research.md        No-skill baseline: research subagent handoff
    │   ├── RED-scenario-3-query.md           No-skill baseline: does agent check existing wiki?
    │   └── RED-results.md                    Documented rationalizations from RED runs
    ├── green/
    │   ├── GREEN-scenario-1-capture.md       Same scenarios with skill installed
    │   ├── GREEN-scenario-2-research.md
    │   ├── GREEN-scenario-3-query.md
    │   └── GREEN-results.md                  Compliance evidence + REFACTOR rounds
    ├── manual-smoke-results.md               Final real-session smoke test log
    └── run-all.sh                            Unit + integration test aggregator
```

### Files that must NOT exist in v2 (deliberately removed)

- `~/.claude/skills/wiki/` (v1 general skill — to be removed after v2 is symlinked and passes testing)
- `~/.claude/skills/project-wiki/` (v1 project skill — same)
- Any `hooks.json` inside a skill directory (hooks live at repo-level, not per-skill, per packaging research)
- Any `~/.wiki-main` env export (config file is sole source of truth, no env var)

---

## Implementation Phases

This plan is divided into **four phases**, each producing working testable software on its own.

- **Phase 1 — Scaffold + baseline tests (RED):** Create repo structure, write baseline pressure scenarios, run them against subagents WITHOUT the skill, document rationalizations. Exit criterion: RED-results.md has documented rationalization patterns.
- **Phase 2 — Core mechanics:** Config, locks, captures, ingester spawn, hooks. Unit-tested. Exit criterion: integration tests pass on small-wiki fixture.
- **Phase 3 — SKILL.md + operations:** Write the skill prose targeting the rationalizations found in Phase 1. Verify compliance (GREEN). Refactor for bulletproof (REFACTOR).
- **Phase 4 — Packaging + deploy:** Plugin manifest, install instructions, README. Symlink into `~/.claude/plugins/`. Manual smoke test.

Each phase has commit checkpoints; work is committed task-by-task.

---

# PHASE 1 — Scaffold + baseline tests (RED)

## Task 1: Create repo and init git

**Files:**
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/` (directory)
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/.gitignore`
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/README.md`
- Modify (shell): init git repo

- [ ] **Step 1: Create repo directory**

Run:
```bash
mkdir -p /Users/lukaszmaj/dev/karpathy-wiki
cd /Users/lukaszmaj/dev/karpathy-wiki
```

- [ ] **Step 2: Write .gitignore**

Create `/Users/lukaszmaj/dev/karpathy-wiki/.gitignore`:
```
# Test artifacts
tests/tmp/
tests/*.log
tests/*/*.actual

# Editor
.DS_Store
*.swp
.vscode/
.idea/

# Python cache
__pycache__/
*.pyc

# Node
node_modules/
npm-debug.log

# Wiki runtime state (never ship)
.wiki-pending/
.locks/
.ingest.log
```

- [ ] **Step 3: Write minimal README placeholder**

Create `/Users/lukaszmaj/dev/karpathy-wiki/README.md`:
```markdown
# karpathy-wiki

A Claude Code skill for auto-maintained LLM wikis following Andrej Karpathy's LLM Wiki pattern.

Status: in development (v2, 2026-04-22).

Full docs coming post-MVP.
```

- [ ] **Step 4: Init git**

Run:
```bash
cd /Users/lukaszmaj/dev/karpathy-wiki
git init
git add .gitignore README.md
git commit -m "chore: initial repo scaffold"
```

Expected output: `[main (root-commit) <hash>] chore: initial repo scaffold`

---

## Task 2: Adopt superpowers-style .gitattributes

**Files:**
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/.gitattributes`

- [ ] **Step 1: Create .gitattributes**

Create `/Users/lukaszmaj/dev/karpathy-wiki/.gitattributes`:
```
# Force LF on all text files. Matches superpowers convention. Keeps shell
# scripts portable across macOS/Linux and prevents CRLF from being introduced
# on any Windows contributor checkout (post-MVP polyglot wrapper will require LF).
* text=auto eol=lf

# Binary files (keep platform native)
*.png binary
*.jpg binary
*.gif binary
*.ico binary
*.svg binary
```

- [ ] **Step 2: Commit**

Run:
```bash
git add .gitattributes
git commit -m "chore: enforce LF for polyglot hook wrapper compatibility"
```

---

## Task 3: Write RED baseline scenario 1 — capture during research

**Files:**
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/baseline/RED-scenario-1-capture.md`
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/baseline/.gitkeep` (for empty dir tracking, will be deleted)

- [ ] **Step 1: Create directories**

Run:
```bash
mkdir -p /Users/lukaszmaj/dev/karpathy-wiki/tests/baseline
mkdir -p /Users/lukaszmaj/dev/karpathy-wiki/tests/green
mkdir -p /Users/lukaszmaj/dev/karpathy-wiki/tests/unit
mkdir -p /Users/lukaszmaj/dev/karpathy-wiki/tests/integration
mkdir -p /Users/lukaszmaj/dev/karpathy-wiki/tests/fixtures/empty-wiki
mkdir -p /Users/lukaszmaj/dev/karpathy-wiki/tests/fixtures/small-wiki
mkdir -p /Users/lukaszmaj/dev/karpathy-wiki/tests/fixtures/sample-captures
```

- [ ] **Step 2: Write RED scenario 1 (research + capture)**

Create `/Users/lukaszmaj/dev/karpathy-wiki/tests/baseline/RED-scenario-1-capture.md`:
```markdown
# RED Scenario 1 — Research + capture

**Goal:** Document what the agent naturally does when it discovers something wiki-worthy during work, without the skill installed.

## Setup

- Fresh Claude Code session (no skill loaded)
- Working directory: `$HOME/karpathy-wiki-test/` (a temp dir with no pre-existing wiki)
- The temp dir should have:
  - A `notes.md` file (empty)
  - A `.git` repo (initialized, no remote)

## Scenario prompt

```
I'm researching cloudflare browser rendering API rate limits. Can you look up the current free tier limits and any workarounds, and help me figure out a good pattern for handling rate limit errors?
```

## What to observe

1. Does the agent capture the research findings anywhere persistent? (File write? Or just reply inline?)
2. If the agent writes findings to a file, does it:
   - Pick a structured location (e.g. `notes.md`, a `docs/` dir)?
   - Use frontmatter?
   - Link to the source?
3. If the agent does NOT write findings anywhere, does it mention that it's not saving them?
4. When the agent explains rate limit patterns, does it offer to save those as reusable snippets / best practices?
5. Exact rationalizations to capture (verbatim quotes):
   - Why did the agent not save, if it didn't?
   - What did it say about saving?

## Run protocol

1. Start the session.
2. Paste the prompt verbatim.
3. Let the agent complete its response (1-3 turns max).
4. Record:
   - All file writes (`ls -la` after, diff against initial state)
   - Full transcript of the response
   - Any rationalization phrases the agent used

## Success criterion for RED

This scenario is "successful" (as a failing test) if:
- The agent does NOT autonomously capture findings to a structured persistent location
- OR captures them incompletely (e.g. writes inline notes but no frontmatter, no source link, no concept extraction)

Both outcomes confirm the skill is needed. Document the exact behavior in RED-results.md.
```

- [ ] **Step 3: Commit**

Run:
```bash
git add tests/baseline/RED-scenario-1-capture.md tests/
git commit -m "test: RED scenario 1 (research + capture baseline)"
```

---

## Task 4: Write RED scenario 2 — research subagent handoff

**Files:**
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/baseline/RED-scenario-2-research.md`

- [ ] **Step 1: Write RED scenario 2**

Create `/Users/lukaszmaj/dev/karpathy-wiki/tests/baseline/RED-scenario-2-research.md`:
```markdown
# RED Scenario 2 — Research subagent handoff

**Goal:** Document what the main agent does when a research subagent returns a research file.

## Setup

- Fresh Claude Code session (no skill loaded)
- Working directory: `$HOME/karpathy-wiki-test/`
- Pre-created file: `$HOME/karpathy-wiki-test/research/2026-04-22-jina-reader-limits.md` with ~500 words of real research content about Jina Reader API (rate limits, workarounds, code example). Use a real plausible research report.
- A `notes.md` in root (empty)

## Scenario prompt

```
A research subagent just finished and wrote its findings to research/2026-04-22-jina-reader-limits.md. I want to make sure this knowledge is available to future me. What should we do with it?
```

## What to observe

1. Does the agent propose a filing system beyond "keep the file where it is"?
2. Does the agent propose extracting concepts (e.g. creating a concepts/ dir)?
3. Does the agent propose an index to find this later?
4. Does the agent recognize that this is wiki-territory without being told?
5. If the agent does nothing beyond "the file is there," record that verbatim — it's the key rationalization.

## Run protocol

Same as RED-1.

## Success criterion for RED

Scenario "succeeds" (as a failing test) if:
- The agent doesn't propose building any structured knowledge base
- OR proposes one but doesn't execute it autonomously

Record rationalizations in RED-results.md.
```

- [ ] **Step 2: Commit**

Run:
```bash
git add tests/baseline/RED-scenario-2-research.md
git commit -m "test: RED scenario 2 (subagent handoff baseline)"
```

---

## Task 5: Write RED scenario 3 — query existing wiki

**Files:**
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/baseline/RED-scenario-3-query.md`

- [ ] **Step 1: Write RED scenario 3**

Create `/Users/lukaszmaj/dev/karpathy-wiki/tests/baseline/RED-scenario-3-query.md`:
```markdown
# RED Scenario 3 — Query a wiki that already exists

**Goal:** Document whether the agent thinks to consult an existing wiki when answering a question, without the skill telling it to.

## Setup

- Fresh Claude Code session (no skill loaded)
- Working directory: `$HOME/karpathy-wiki-test/`
- Pre-created wiki at `$HOME/karpathy-wiki-test/wiki/`:
  - `wiki/index.md` with 10 concept entries
  - `wiki/concepts/jina-reader.md` covering Jina Reader rate limits (from a prior session)
  - `wiki/log.md` with 5 prior ingests logged
  - `wiki/schema.md` describing the structure
- The wiki content is germane to the question being asked.

## Scenario prompt

```
What do we know about Jina Reader's rate limits and common workarounds?
```

## What to observe

1. Does the agent naturally check `wiki/` first, or go straight to training data / web?
2. If the agent does check a file, which one? (index.md? concepts/?)
3. Does the agent cite wiki pages in its answer, or answer from general knowledge?
4. If it answers from general knowledge only, record the exact response. Rationalization candidate: "I'll just answer from what I know."

## Run protocol

Same as RED-1.

## Success criterion for RED

Scenario "succeeds" (as a failing test) if:
- The agent ignores the wiki/ directory entirely
- OR glances at `wiki/index.md` but answers from training data rather than citing wiki pages

Record in RED-results.md.
```

- [ ] **Step 2: Commit**

Run:
```bash
git add tests/baseline/RED-scenario-3-query.md
git commit -m "test: RED scenario 3 (existing-wiki query baseline)"
```

---

## Task 6: Create small-wiki fixture for Scenario 3 and later integration tests

**Files:**
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/fixtures/small-wiki/schema.md`
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/fixtures/small-wiki/index.md`
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/fixtures/small-wiki/log.md`
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/fixtures/small-wiki/concepts/jina-reader.md`
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/fixtures/small-wiki/concepts/cloudflare-browser-rendering.md`
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/fixtures/small-wiki/concepts/rate-limiting.md`

- [ ] **Step 1: Write schema.md**

Create `/Users/lukaszmaj/dev/karpathy-wiki/tests/fixtures/small-wiki/schema.md`:
```markdown
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
```

- [ ] **Step 2: Write index.md**

Create `/Users/lukaszmaj/dev/karpathy-wiki/tests/fixtures/small-wiki/index.md`:
```markdown
# Wiki Index

## Concepts
- [Jina Reader](concepts/jina-reader.md) — Free-tier rate limits, usage patterns
- [Cloudflare Browser Rendering](concepts/cloudflare-browser-rendering.md) — Scraping JS-heavy sites via API
- [Rate Limiting](concepts/rate-limiting.md) — Patterns: exponential backoff, token bucket, request queue

## Entities
(empty)

## Sources
(empty)

## Queries
(empty)
```

- [ ] **Step 3: Write log.md**

Create `/Users/lukaszmaj/dev/karpathy-wiki/tests/fixtures/small-wiki/log.md`:
```markdown
# Wiki Log

## [2026-04-18] ingest | Jina Reader research
- Source: raw/2026-04-18-jina-reader.md
- Pages created: concepts/jina-reader.md
- Pages touched: index.md
- Capture ID: 2026-04-18T10-00-jina-reader

## [2026-04-19] ingest | Cloudflare Browser Rendering research
- Source: raw/2026-04-19-cloudflare-br.md
- Pages created: concepts/cloudflare-browser-rendering.md
- Pages touched: index.md
- Capture ID: 2026-04-19T14-30-cloudflare-br

## [2026-04-20] ingest | Rate limiting patterns
- Source: raw/2026-04-20-rate-limits.md
- Pages created: concepts/rate-limiting.md
- Pages touched: concepts/jina-reader.md, concepts/cloudflare-browser-rendering.md, index.md
- Capture ID: 2026-04-20T09-15-rate-limits
```

- [ ] **Step 4: Write concepts/jina-reader.md**

Create `/Users/lukaszmaj/dev/karpathy-wiki/tests/fixtures/small-wiki/concepts/jina-reader.md`:
```markdown
---
title: Jina Reader
type: concept
tags: [api, rate-limit]
created: 2026-04-18
updated: 2026-04-20
sources: [raw/2026-04-18-jina-reader.md]
---

Jina Reader is a URL-to-markdown conversion API useful for agents that need clean page content.

## Rate Limits (Free Tier)
- 20 requests per minute
- Documented in error response header `X-RateLimit-Remaining`
- See [Rate Limiting](rate-limiting.md) for general patterns

## Workarounds
- Exponential backoff (preferred — see [Rate Limiting](rate-limiting.md))
- Paid tier at $0.0002/request removes the limit

## See also
- [Cloudflare Browser Rendering](cloudflare-browser-rendering.md) — alternative when Jina can't handle JS-heavy sites
```

- [ ] **Step 5: Write concepts/cloudflare-browser-rendering.md**

Create `/Users/lukaszmaj/dev/karpathy-wiki/tests/fixtures/small-wiki/concepts/cloudflare-browser-rendering.md`:
```markdown
---
title: Cloudflare Browser Rendering
type: concept
tags: [api, browser]
created: 2026-04-19
updated: 2026-04-20
sources: [raw/2026-04-19-cloudflare-br.md]
---

Cloudflare Browser Rendering API runs a headless Chrome in Cloudflare Workers and returns rendered HTML/markdown. Good for JS-heavy sites that Jina can't parse.

## Rate Limits
- Free tier: 10 req/min, 5 concurrent
- See [Rate Limiting](rate-limiting.md) for backoff patterns

## Usage
- Endpoint: `/browser-rendering/markdown`
- Auth via Cloudflare account ID + API token (see `.env`)

## See also
- [Jina Reader](jina-reader.md) — faster alternative when JS rendering isn't needed
```

- [ ] **Step 6: Write concepts/rate-limiting.md**

Create `/Users/lukaszmaj/dev/karpathy-wiki/tests/fixtures/small-wiki/concepts/rate-limiting.md`:
```markdown
---
title: Rate Limiting
type: concept
tags: [pattern, api]
created: 2026-04-20
updated: 2026-04-20
sources: [raw/2026-04-20-rate-limits.md]
---

Patterns for handling API rate limits gracefully.

## Exponential Backoff
Simplest and most compatible. Retry after `2^attempt` seconds, cap at 60s.

## Token Bucket
Use when you need sustained throughput. Refills at a known rate.

## Request Queue
Use when rate limit is low and you need order preservation.

## Applied in
- [Jina Reader](jina-reader.md)
- [Cloudflare Browser Rendering](cloudflare-browser-rendering.md)
```

- [ ] **Step 7: Commit**

Run:
```bash
git add tests/fixtures/small-wiki/
git commit -m "test: small-wiki fixture for scenario 3 + integration tests"
```

---

## Task 7: Execute RED phase — run baseline subagent tests

**Files:**
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/baseline/RED-results.md`

**Methodology caveat:** this is a lightweight RED using Task-tool subagents that "pretend to have no skill loaded." It is not fully equivalent to a rigorous isolated-session test (a rigorous version would use `claude -p` in an isolated `$HOME` with no skills installed, per superpowers' `tests/claude-code/` pattern). The subagent pretense is contaminated — the subagent has seen its own system prompt, but has NOT seen the karpathy-wiki skill content.

For v1, this compromise is acceptable: we are measuring rationalization patterns, not rigorously A/B-testing behavior. If specific rationalizations feel implausibly absent, upgrade this task to isolated-session testing (post-MVP).

- [ ] **Step 1: Spawn subagent for RED scenario 1 (in-foreground, not background, so we can observe)**

In the current Claude Code session, use the Task tool to spawn a general-purpose agent with this prompt (copy verbatim):

```
Execute the scenario documented at /Users/lukaszmaj/dev/karpathy-wiki/tests/baseline/RED-scenario-1-capture.md.

Setup:
- Create a temp dir at /tmp/karpathy-wiki-test-red1/
- Create /tmp/karpathy-wiki-test-red1/notes.md (empty)
- Run `git init` inside it

Then, pretend you are a Claude Code session with NO skills loaded. Execute the scenario prompt as if you received it from the user:

"I'm researching cloudflare browser rendering API rate limits. Can you look up the current free tier limits and any workarounds, and help me figure out a good pattern for handling rate limit errors?"

Respond to the user's request as you normally would WITHOUT considering any wiki skill. Do the research (you can use web knowledge from training data, don't need to actually fetch). Give your answer.

After responding, stop and report:
1. The full text of your response
2. Any files you wrote, and their exact contents
3. Any files you didn't write but considered writing — state what and why you decided against
4. The exact words you used when explaining how this knowledge would be preserved (or why it wouldn't)

Do NOT use any wiki-related tools or invoke any skills. Pretend they don't exist.

Return your findings as a single markdown report.
```

- [ ] **Step 2: Record RED-1 results**

Append the scenario 1 findings to `/Users/lukaszmaj/dev/karpathy-wiki/tests/baseline/RED-results.md` under a `## Scenario 1` section.

- [ ] **Step 3: Spawn subagent for RED scenario 2 — same process, different scenario**

Use Task tool with this prompt:

```
Execute the scenario at /Users/lukaszmaj/dev/karpathy-wiki/tests/baseline/RED-scenario-2-research.md.

Setup:
- Create /tmp/karpathy-wiki-test-red2/research/ directory
- Write /tmp/karpathy-wiki-test-red2/research/2026-04-22-jina-reader-limits.md with this content (copy verbatim):

---
# Jina Reader API — Rate Limits Research

## Findings

Jina Reader free tier limits:
- 20 requests per minute
- 100,000 requests per month
- No concurrent-request limit explicitly documented
- Hitting limit returns HTTP 429 with X-RateLimit-Remaining: 0

## Workarounds observed
1. Exponential backoff — simplest, no additional infra
2. Paid tier at $0.0002/req removes limit
3. Self-host the open-source version (available on GitHub)

## Code pattern

```python
import time
import requests

def fetch_with_backoff(url, max_retries=5):
    for attempt in range(max_retries):
        resp = requests.get(f"https://r.jina.ai/{url}")
        if resp.status_code != 429:
            return resp
        time.sleep(2 ** attempt)
    raise Exception("Rate limit exceeded")
```
---

- Create /tmp/karpathy-wiki-test-red2/notes.md (empty)
- Run `git init` in /tmp/karpathy-wiki-test-red2/

Now, pretend you are a Claude Code session with NO wiki skill loaded. Execute this prompt as if the user sent it:

"A research subagent just finished and wrote its findings to research/2026-04-22-jina-reader-limits.md. I want to make sure this knowledge is available to future me. What should we do with it?"

Respond naturally. Take whatever action you would normally take.

After responding, report:
1. Full text of your response
2. Any files created or modified
3. Exact rationalizations about how knowledge is preserved

Do NOT invoke any wiki-related tools. Pretend they don't exist.
```

- [ ] **Step 4: Record RED-2 results**

Append scenario 2 findings to `RED-results.md` under `## Scenario 2`.

- [ ] **Step 5: Spawn subagent for RED scenario 3**

Use Task tool with this prompt:

```
Execute the scenario at /Users/lukaszmaj/dev/karpathy-wiki/tests/baseline/RED-scenario-3-query.md.

Setup:
- Create /tmp/karpathy-wiki-test-red3/
- Copy the entire contents of /Users/lukaszmaj/dev/karpathy-wiki/tests/fixtures/small-wiki/ to /tmp/karpathy-wiki-test-red3/wiki/
- Verify: ls /tmp/karpathy-wiki-test-red3/wiki/ should show: schema.md, index.md, log.md, concepts/

cd to /tmp/karpathy-wiki-test-red3/

Pretend you are a Claude Code session with NO wiki skill loaded. Execute this prompt as if sent by user:

"What do we know about Jina Reader's rate limits and common workarounds?"

Respond naturally.

After responding, report:
1. Full text of response
2. Which files you read (if any) — exact paths
3. Whether you noticed the wiki/ directory and how you reasoned about it
4. Whether your answer cited wiki pages or came from training data
5. Exact rationalizations

Do NOT invoke any wiki skills.
```

- [ ] **Step 6: Record RED-3 results**

Append scenario 3 findings to `RED-results.md` under `## Scenario 3`.

- [ ] **Step 7: Synthesize RED findings**

Add a final `## Synthesized rationalization patterns` section to `RED-results.md` that lists:
- The 3-5 most common rationalization phrases across all scenarios
- The top 3 places the agent chose NOT to take an action that the skill would want
- Patterns to target when writing the skill's TRIGGER rules

- [ ] **Step 8: Commit RED results**

Run:
```bash
cd /Users/lukaszmaj/dev/karpathy-wiki
git add tests/baseline/RED-results.md
git commit -m "test(RED): baseline subagent behavior without skill documented"
```

**Exit criterion for Phase 1:** `RED-results.md` exists with documented rationalizations. Do NOT proceed to Phase 2 without this — you'll be writing the skill in the dark.

---

# PHASE 2 — Core mechanics

Core mechanics are the small shell/Python pieces that the skill orchestrates. Each is independently testable. We build them bottom-up so the skill has reliable primitives to call.

## Task 8: wiki-lib.sh — shared bash helpers

**Files:**
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-lib.sh`
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-lib.sh`

- [ ] **Step 1: Write failing test for log_info**

Create `/Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-lib.sh`:
```bash
#!/bin/bash
# Test wiki-lib.sh helpers.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LIB="${REPO_ROOT}/scripts/wiki-lib.sh"

# shellcheck source=/dev/null
source "${LIB}"

test_log_info() {
  local tmpfile
  tmpfile="$(mktemp)"
  WIKI_INGEST_LOG="${tmpfile}" log_info "hello"
  grep -q "INFO  hello" "${tmpfile}" || {
    echo "FAIL: test_log_info — expected 'INFO  hello' in log, got:"
    cat "${tmpfile}"
    exit 1
  }
  rm -f "${tmpfile}"
  echo "PASS: test_log_info"
}

test_slugify() {
  local result
  result="$(slugify "Hello World! My Title")"
  [[ "${result}" == "hello-world-my-title" ]] || {
    echo "FAIL: test_slugify — expected 'hello-world-my-title', got '${result}'"
    exit 1
  }
  echo "PASS: test_slugify"
}

test_wiki_root_from_cwd_with_wiki_dir() {
  local tmp
  tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki"
  touch "${tmp}/wiki/.wiki-config"

  local result
  result="$(cd "${tmp}" && wiki_root_from_cwd)"
  [[ "${result}" == "${tmp}/wiki" ]] || {
    echo "FAIL: test_wiki_root_from_cwd — expected '${tmp}/wiki', got '${result}'"
    rm -rf "${tmp}"
    exit 1
  }
  rm -rf "${tmp}"
  echo "PASS: test_wiki_root_from_cwd_with_wiki_dir"
}

test_log_info
test_slugify
test_wiki_root_from_cwd_with_wiki_dir
echo "ALL PASS"
```

- [ ] **Step 2: Run test to see it fail**

Run:
```bash
cd /Users/lukaszmaj/dev/karpathy-wiki
chmod +x tests/unit/test-lib.sh
bash tests/unit/test-lib.sh
```

Expected: `FAIL` or `source: no such file or directory: scripts/wiki-lib.sh` (because wiki-lib.sh doesn't exist yet).

- [ ] **Step 3: Write minimal wiki-lib.sh**

Create `/Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-lib.sh`:
```bash
#!/bin/bash
# Shared helpers for karpathy-wiki scripts.
# Source this file; don't execute.

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------
# Writes structured log lines to $WIKI_INGEST_LOG (default: .ingest.log in wiki root).
# Format: ISO8601 LEVEL message

_wiki_log() {
  local level="$1"
  shift
  local ts
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  local logfile="${WIKI_INGEST_LOG:-}"
  if [[ -z "${logfile}" ]]; then
    local root
    root="$(wiki_root_from_cwd 2>/dev/null || echo "")"
    if [[ -n "${root}" ]]; then
      logfile="${root}/.ingest.log"
    else
      logfile="/dev/null"
    fi
  fi
  printf '%s %-5s %s\n' "${ts}" "${level}" "$*" >> "${logfile}"
}

log_info()  { _wiki_log "INFO"  "$@"; }
log_warn()  { _wiki_log "WARN"  "$@"; }
log_error() { _wiki_log "ERROR" "$@"; }

# ---------------------------------------------------------------------------
# Slug / path helpers
# ---------------------------------------------------------------------------

slugify() {
  # Lowercase, replace non-alphanumerics with -, collapse repeats, trim edges.
  local input="$1"
  echo "${input}" \
    | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g' \
    | sed 's/--*/-/g' \
    | sed 's/^-//;s/-$//'
}

wiki_root_from_cwd() {
  # Walks up from cwd looking for a dir containing .wiki-config.
  # Prints absolute path or exits 1.
  local dir
  dir="$(pwd)"
  while [[ "${dir}" != "/" ]]; do
    if [[ -f "${dir}/.wiki-config" ]]; then
      echo "${dir}"
      return 0
    fi
    # Also check if cwd has a wiki/ subdir with .wiki-config
    if [[ -f "${dir}/wiki/.wiki-config" ]]; then
      echo "${dir}/wiki"
      return 0
    fi
    dir="$(dirname "${dir}")"
  done
  return 1
}

# ---------------------------------------------------------------------------
# Config read
# ---------------------------------------------------------------------------

wiki_config_get() {
  # wiki_config_get <wiki_root> <key.subkey>
  # Invokes wiki-config-read.py. Requires python3.
  local root="$1"
  local key="$2"
  local script
  script="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/wiki-config-read.py"
  python3 "${script}" "${root}/.wiki-config" "${key}"
}
```

- [ ] **Step 4: Make executable and run test**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-lib.sh
bash /Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-lib.sh
```

Expected output:
```
PASS: test_log_info
PASS: test_slugify
PASS: test_wiki_root_from_cwd_with_wiki_dir
ALL PASS
```

- [ ] **Step 5: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/karpathy-wiki
git add scripts/wiki-lib.sh tests/unit/test-lib.sh
git commit -m "feat: wiki-lib.sh with logging, slugify, root discovery"
```

---

## Task 9: wiki-config-read.py — TOML config parser

**Files:**
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-config-read.py`
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-config-read.sh`

- [ ] **Step 1: Write failing test**

Create `/Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-config-read.sh`:
```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
READER="${REPO_ROOT}/scripts/wiki-config-read.py"

# Fixture config
TMPCFG="$(mktemp)"
cat > "${TMPCFG}" <<'EOF'
role = "main"
created = "2026-04-22"

[platform]
agent_cli = "claude"
headless_command = "claude -p"

[settings]
auto_commit = true
EOF

test_read_top_level() {
  local result
  result="$(python3 "${READER}" "${TMPCFG}" role)"
  [[ "${result}" == "main" ]] || { echo "FAIL: role. got '${result}'"; exit 1; }
  echo "PASS: test_read_top_level"
}

test_read_nested() {
  local result
  result="$(python3 "${READER}" "${TMPCFG}" platform.agent_cli)"
  [[ "${result}" == "claude" ]] || { echo "FAIL: platform.agent_cli. got '${result}'"; exit 1; }
  echo "PASS: test_read_nested"
}

test_read_missing_key_exits_nonzero() {
  if python3 "${READER}" "${TMPCFG}" missing.key 2>/dev/null; then
    echo "FAIL: missing key should exit nonzero"
    exit 1
  fi
  echo "PASS: test_read_missing_key_exits_nonzero"
}

test_read_missing_file_exits_nonzero() {
  if python3 "${READER}" /tmp/does-not-exist-$$ role 2>/dev/null; then
    echo "FAIL: missing file should exit nonzero"
    exit 1
  fi
  echo "PASS: test_read_missing_file_exits_nonzero"
}

test_read_top_level
test_read_nested
test_read_missing_key_exits_nonzero
test_read_missing_file_exits_nonzero
rm -f "${TMPCFG}"
echo "ALL PASS"
```

- [ ] **Step 2: Run test to see failure**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-config-read.sh
bash /Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-config-read.sh
```

Expected: FAIL — script doesn't exist.

- [ ] **Step 3: Write wiki-config-read.py**

Create `/Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-config-read.py`:
```python
#!/usr/bin/env python3
"""Read a TOML config value by dotted key.

Usage:
    wiki-config-read.py <path-to-.wiki-config> <dotted.key>

Exits 0 on success (prints value to stdout).
Exits 1 on missing file, missing key, or malformed TOML.
"""

import sys


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: wiki-config-read.py <path> <dotted.key>", file=sys.stderr)
        return 1

    path = sys.argv[1]
    key = sys.argv[2]

    try:
        # tomllib is stdlib in Python 3.11+
        import tomllib
    except ImportError:
        print("python3.11+ required (tomllib not available)", file=sys.stderr)
        return 1

    try:
        with open(path, "rb") as f:
            data = tomllib.load(f)
    except FileNotFoundError:
        print(f"config not found: {path}", file=sys.stderr)
        return 1
    except tomllib.TOMLDecodeError as e:
        print(f"malformed TOML: {e}", file=sys.stderr)
        return 1

    # Walk the dotted key path.
    current = data
    for part in key.split("."):
        if not isinstance(current, dict) or part not in current:
            print(f"key not found: {key}", file=sys.stderr)
            return 1
        current = current[part]

    # Print scalar values cleanly. For tables/arrays emit JSON so callers
    # can parse reliably (repr() produces Python-specific syntax).
    import json as _json
    if isinstance(current, bool):
        print("true" if current else "false")
    elif isinstance(current, (int, float, str)):
        print(current)
    elif isinstance(current, (dict, list)):
        print(_json.dumps(current))
    else:
        print(str(current))
    return 0


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Make executable, run test**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-config-read.py
bash /Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-config-read.sh
```

Expected output:
```
PASS: test_read_top_level
PASS: test_read_nested
PASS: test_read_missing_key_exits_nonzero
PASS: test_read_missing_file_exits_nonzero
ALL PASS
```

- [ ] **Step 5: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/karpathy-wiki
git add scripts/wiki-config-read.py tests/unit/test-config-read.sh
git commit -m "feat: wiki-config-read.py (stdlib TOML reader)"
```

---

## Task 10: Page-level locks (acquire, release, stale reclaim)

**Files:**
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-lock.sh`
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-locks.sh`

- [ ] **Step 1: Write failing test**

Create `/Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-locks.sh`:
```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/wiki-lib.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/wiki-lock.sh"

setup() {
  TESTDIR="$(mktemp -d)"
  WIKI="${TESTDIR}/wiki"
  mkdir -p "${WIKI}/.locks"
  mkdir -p "${WIKI}/concepts"
  touch "${WIKI}/.wiki-config"
  touch "${WIKI}/concepts/foo.md"
}

teardown() {
  rm -rf "${TESTDIR}"
}

test_acquire_succeeds_on_free_page() {
  setup
  if wiki_lock_acquire "${WIKI}" "concepts/foo.md" "cap-1"; then
    echo "PASS: test_acquire_succeeds_on_free_page"
  else
    echo "FAIL: should have acquired"; teardown; exit 1
  fi
  teardown
}

test_acquire_fails_when_held() {
  setup
  wiki_lock_acquire "${WIKI}" "concepts/foo.md" "cap-1"
  if wiki_lock_acquire "${WIKI}" "concepts/foo.md" "cap-2" 2>/dev/null; then
    echo "FAIL: second acquire should have failed"; teardown; exit 1
  fi
  echo "PASS: test_acquire_fails_when_held"
  teardown
}

test_release_allows_reacquisition() {
  setup
  wiki_lock_acquire "${WIKI}" "concepts/foo.md" "cap-1"
  wiki_lock_release "${WIKI}" "concepts/foo.md"
  if wiki_lock_acquire "${WIKI}" "concepts/foo.md" "cap-2"; then
    echo "PASS: test_release_allows_reacquisition"
  else
    echo "FAIL: reacquire after release should have succeeded"; teardown; exit 1
  fi
  teardown
}

test_stale_lock_reclaim() {
  setup
  # Create a stale lock (fake old timestamp)
  local lockfile
  lockfile="${WIKI}/.locks/concepts-foo-md.lock"
  echo '{"pid":99999,"started_at":"1970-01-01T00:00:00Z","capture_id":"stale"}' > "${lockfile}"
  # Set mtime to 1 hour ago
  touch -t 202601010000 "${lockfile}"
  # Should now succeed because lock is stale
  if wiki_lock_acquire "${WIKI}" "concepts/foo.md" "cap-1"; then
    echo "PASS: test_stale_lock_reclaim"
  else
    echo "FAIL: stale lock should have been reclaimed"; teardown; exit 1
  fi
  teardown
}

test_acquire_succeeds_on_free_page
test_acquire_fails_when_held
test_release_allows_reacquisition
test_stale_lock_reclaim
echo "ALL PASS"
```

- [ ] **Step 2: Run to see failure**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-locks.sh
bash /Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-locks.sh
```

Expected: FAIL — wiki-lock.sh missing.

- [ ] **Step 3: Write wiki-lock.sh**

Create `/Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-lock.sh`:
```bash
#!/bin/bash
# Page-level locking for wiki ingesters.
# Source this file; don't execute.

# Stale-lock age in seconds. Matches superpowers' short-timeout finding
# (see superpowers-skill-style-guide.md, issue #1237 lesson).
WIKI_LOCK_STALE_SECONDS="${WIKI_LOCK_STALE_SECONDS:-300}"  # 5 minutes

_wiki_lock_path() {
  # _wiki_lock_path <wiki_root> <page-relative-path>
  # Returns absolute path of the lockfile for that page.
  local root="$1"
  local page="$2"
  local slug
  slug="$(echo "${page}" | tr '/' '-' | tr '.' '-')"
  echo "${root}/.locks/${slug}.lock"
}

_wiki_lock_is_stale() {
  # _wiki_lock_is_stale <lockfile-path>
  # Exits 0 if file mtime is older than WIKI_LOCK_STALE_SECONDS.
  local lockfile="$1"
  [[ -f "${lockfile}" ]] || return 1
  local mtime now age
  mtime="$(stat -f %m "${lockfile}" 2>/dev/null || stat -c %Y "${lockfile}" 2>/dev/null)"
  now="$(date +%s)"
  age=$((now - mtime))
  [[ "${age}" -gt "${WIKI_LOCK_STALE_SECONDS}" ]]
}

wiki_lock_acquire() {
  # wiki_lock_acquire <wiki_root> <page-relative-path> <capture_id>
  # Returns 0 on success, 1 on held-by-another.
  # Reclaims stale locks before acquiring.
  local root="$1"
  local page="$2"
  local capture_id="$3"

  mkdir -p "${root}/.locks"
  local lockfile
  lockfile="$(_wiki_lock_path "${root}" "${page}")"

  # Reclaim stale lock if present.
  if _wiki_lock_is_stale "${lockfile}"; then
    log_warn "reclaiming stale lock: ${lockfile}"
    rm -f "${lockfile}"
  fi

  # Atomic create-exclusive. `set -o noclobber` makes `>` refuse to overwrite
  # an existing file — that is the exclusivity guarantee. Brace groups do NOT
  # scope shell options, so noclobber persists after this block; that is
  # intentional (we want subsequent plain `>` in this function to honor it).
  # The write below uses `>|` which is bash's explicit "force-override
  # noclobber for this one redirect" — required because the lockfile now
  # exists (we just created it) and plain `>` would be refused.
  if { set -o noclobber; > "${lockfile}"; } 2>/dev/null; then
    local pid="$$"
    local ts
    ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf '{"pid":%d,"started_at":"%s","capture_id":"%s"}\n' \
      "${pid}" "${ts}" "${capture_id}" >| "${lockfile}"
    log_info "acquired lock: ${page} (capture=${capture_id})"
    return 0
  fi
  return 1
}

wiki_lock_release() {
  # wiki_lock_release <wiki_root> <page-relative-path>
  local root="$1"
  local page="$2"
  local lockfile
  lockfile="$(_wiki_lock_path "${root}" "${page}")"
  rm -f "${lockfile}"
  log_info "released lock: ${page}"
}

wiki_lock_wait_and_acquire() {
  # wiki_lock_wait_and_acquire <wiki_root> <page-relative-path> <capture_id> [timeout_seconds]
  # Polls until free or timeout. Default timeout 30 seconds.
  local root="$1"
  local page="$2"
  local capture_id="$3"
  local timeout="${4:-30}"
  local elapsed=0
  local poll=1  # seconds between checks

  while ! wiki_lock_acquire "${root}" "${page}" "${capture_id}" 2>/dev/null; do
    sleep "${poll}"
    elapsed=$((elapsed + poll))
    if [[ "${elapsed}" -ge "${timeout}" ]]; then
      log_error "lock acquire timeout: ${page}"
      return 1
    fi
  done
  return 0
}
```

- [ ] **Step 4: Run test**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-lock.sh
bash /Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-locks.sh
```

Expected output:
```
PASS: test_acquire_succeeds_on_free_page
PASS: test_acquire_fails_when_held
PASS: test_release_allows_reacquisition
PASS: test_stale_lock_reclaim
ALL PASS
```

- [ ] **Step 5: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/karpathy-wiki
git add scripts/wiki-lock.sh tests/unit/test-locks.sh
git commit -m "feat: page-level locks with stale reclaim"
```

---

## Task 11: Capture format + atomic claim (rename-based)

**Files:**
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-capture.sh`
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/fixtures/sample-captures/example.md`
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-capture.sh`

- [ ] **Step 1: Write sample capture fixture**

Create `/Users/lukaszmaj/dev/karpathy-wiki/tests/fixtures/sample-captures/example.md`:
```markdown
---
title: "Jina Reader rate limits"
evidence: "/tmp/fake-research/jina-limits.md"
evidence_type: "file"
suggested_action: "update"
suggested_pages:
  - concepts/jina-reader.md
  - concepts/rate-limiting.md
captured_at: "2026-04-22T14:30:00Z"
captured_by: "in-session-agent"
origin: null
---

Jina Reader free tier allows 20 req/min. Confirmed via 429 response.
Workaround: exponential backoff.
```

- [ ] **Step 2: Write failing test**

Create `/Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-capture.sh`:
```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/wiki-lib.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/wiki-capture.sh"

setup() {
  TESTDIR="$(mktemp -d)"
  WIKI="${TESTDIR}/wiki"
  mkdir -p "${WIKI}/.wiki-pending"
  touch "${WIKI}/.wiki-config"
}

teardown() {
  rm -rf "${TESTDIR}"
}

test_claim_succeeds() {
  setup
  cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
     "${WIKI}/.wiki-pending/2026-04-22T14-30-example.md"
  local claimed
  claimed="$(wiki_capture_claim "${WIKI}")"
  if [[ -f "${claimed}" ]] && [[ "${claimed}" == *.processing ]]; then
    echo "PASS: test_claim_succeeds (claimed: $(basename "${claimed}"))"
  else
    echo "FAIL: expected a .processing file, got: ${claimed}"
    teardown; exit 1
  fi
  teardown
}

test_claim_returns_empty_when_no_pending() {
  setup
  local claimed
  claimed="$(wiki_capture_claim "${WIKI}" || echo "NONE")"
  [[ "${claimed}" == "NONE" ]] || {
    echo "FAIL: expected NONE, got '${claimed}'"; teardown; exit 1
  }
  echo "PASS: test_claim_returns_empty_when_no_pending"
  teardown
}

test_claim_is_atomic_sequential() {
  # Basic smoke: two claims in sequence should give claim+NONE.
  setup
  cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
     "${WIKI}/.wiki-pending/2026-04-22T14-30-example.md"
  local a b
  a="$(wiki_capture_claim "${WIKI}" 2>/dev/null)"
  b="$(wiki_capture_claim "${WIKI}" 2>/dev/null || echo "NONE")"
  if [[ -n "${a}" ]] && [[ "${b}" == "NONE" ]]; then
    echo "PASS: test_claim_is_atomic_sequential"
  else
    echo "FAIL: sequential claim. a=${a} b=${b}"; teardown; exit 1
  fi
  teardown
}

test_claim_is_atomic_concurrent() {
  # Real concurrency: start N background claims racing on ONE capture.
  # Exactly one should report a claimed path; the rest NONE.
  setup
  cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
     "${WIKI}/.wiki-pending/2026-04-22T14-30-example.md"

  local outdir
  outdir="$(mktemp -d)"
  local N=5 i
  for i in $(seq 1 "${N}"); do
    (
      # shellcheck source=/dev/null
      source "${REPO_ROOT}/scripts/wiki-lib.sh"
      # shellcheck source=/dev/null
      source "${REPO_ROOT}/scripts/wiki-capture.sh"
      result="$(wiki_capture_claim "${WIKI}" 2>/dev/null || echo "NONE")"
      echo "${result}" > "${outdir}/claim-${i}.out"
    ) &
  done
  wait

  # Count how many got a non-NONE result.
  local winners=0
  for i in $(seq 1 "${N}"); do
    local out
    out="$(cat "${outdir}/claim-${i}.out")"
    [[ "${out}" == "NONE" ]] && continue
    [[ -n "${out}" ]] && winners=$((winners + 1))
  done

  rm -rf "${outdir}"
  if [[ "${winners}" -eq 1 ]]; then
    echo "PASS: test_claim_is_atomic_concurrent (1 winner out of ${N})"
  else
    echo "FAIL: expected exactly 1 winner, got ${winners}"
    teardown; exit 1
  fi
  teardown
}

test_claim_succeeds
test_claim_returns_empty_when_no_pending
test_claim_is_atomic_sequential
test_claim_is_atomic_concurrent
echo "ALL PASS"
```

- [ ] **Step 3: Run to see failure**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-capture.sh
bash /Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-capture.sh
```

Expected: FAIL — wiki-capture.sh missing.

- [ ] **Step 4: Write wiki-capture.sh**

Create `/Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-capture.sh`:
```bash
#!/bin/bash
# Capture lifecycle: claim, archive, list.
# Source this file.

wiki_capture_claim() {
  # wiki_capture_claim <wiki_root>
  # Atomically claims a pending capture by renaming to .processing.
  # Prints the claimed path on success.
  # Exits 1 if no pending captures or another claimant won.
  #
  # Atomicity approach: `ln` creates a hard link exclusively (fails if target
  # exists). Then `unlink` removes the original. If two racers call ln+unlink,
  # only one ln succeeds; the loser sees "File exists" and retries the scan.
  # This is stricter than `mv -n` which on macOS BSD silently no-ops on collision.
  local root="$1"
  local pending="${root}/.wiki-pending"
  [[ -d "${pending}" ]] || return 1

  local f claimed
  for f in "${pending}"/*.md; do
    [[ -f "${f}" ]] || continue
    [[ "${f}" == *.processing ]] && continue
    claimed="${f}.processing"
    # Exclusive hard link. Fails if claimed already exists.
    if ln "${f}" "${claimed}" 2>/dev/null; then
      # We own it. Remove the original. If the unlink fails (another racer
      # already unlinked), that's still OK — we have the .processing handle.
      unlink "${f}" 2>/dev/null || true
      echo "${claimed}"
      return 0
    fi
    # Someone else claimed this one; try the next file.
  done
  return 1
}

wiki_capture_archive() {
  # wiki_capture_archive <wiki_root> <processing-file-path>
  # Moves a successfully-processed capture to .wiki-pending/archive/YYYY-MM/
  local root="$1"
  local processing="$2"
  local date_dir
  date_dir="$(date +%Y-%m)"
  local archive="${root}/.wiki-pending/archive/${date_dir}"
  mkdir -p "${archive}"
  local base
  base="$(basename "${processing}" .processing)"
  mv "${processing}" "${archive}/${base}"
  log_info "archived capture: ${base}"
}

wiki_capture_count_pending() {
  # wiki_capture_count_pending <wiki_root>
  local root="$1"
  local pending="${root}/.wiki-pending"
  [[ -d "${pending}" ]] || { echo 0; return; }
  local count=0
  for f in "${pending}"/*.md; do
    [[ -f "${f}" ]] || continue
    [[ "${f}" == *.processing ]] && continue
    count=$((count + 1))
  done
  echo "${count}"
}
```

- [ ] **Step 5: Run test**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-capture.sh
bash /Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-capture.sh
```

Expected output:
```
PASS: test_claim_succeeds (claimed: 2026-04-22T14-30-example.md.processing)
PASS: test_claim_returns_empty_when_no_pending
PASS: test_claim_is_atomic_sequential
PASS: test_claim_is_atomic_concurrent (1 winner out of 5)
ALL PASS
```

- [ ] **Step 6: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/karpathy-wiki
git add scripts/wiki-capture.sh tests/unit/test-capture.sh tests/fixtures/sample-captures/
git commit -m "feat: capture claim + archive (atomic via ln+unlink)"
```

---

## Task 12: Hash manifest for raw/ drift

**Files:**
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-manifest.py`
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-manifest.sh`

- [ ] **Step 1: Write failing test**

Create `/Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-manifest.sh`:
```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TOOL="${REPO_ROOT}/scripts/wiki-manifest.py"

setup() {
  TESTDIR="$(mktemp -d)"
  WIKI="${TESTDIR}/wiki"
  mkdir -p "${WIKI}/raw"
  echo "alpha" > "${WIKI}/raw/a.md"
  echo "beta"  > "${WIKI}/raw/b.md"
}

teardown() { rm -rf "${TESTDIR}"; }

test_build_manifest_fresh() {
  setup
  python3 "${TOOL}" build "${WIKI}"
  [[ -f "${WIKI}/.manifest.json" ]] || { echo "FAIL: manifest not created"; teardown; exit 1; }
  # Should contain both files
  grep -q 'raw/a.md' "${WIKI}/.manifest.json" || { echo "FAIL: a.md missing"; teardown; exit 1; }
  grep -q 'raw/b.md' "${WIKI}/.manifest.json" || { echo "FAIL: b.md missing"; teardown; exit 1; }
  echo "PASS: test_build_manifest_fresh"
  teardown
}

test_diff_clean() {
  setup
  python3 "${TOOL}" build "${WIKI}"
  local result
  result="$(python3 "${TOOL}" diff "${WIKI}")"
  [[ "${result}" == "CLEAN" ]] || { echo "FAIL: expected CLEAN, got '${result}'"; teardown; exit 1; }
  echo "PASS: test_diff_clean"
  teardown
}

test_diff_detects_new_file() {
  setup
  python3 "${TOOL}" build "${WIKI}"
  echo "gamma" > "${WIKI}/raw/c.md"
  local result
  result="$(python3 "${TOOL}" diff "${WIKI}")"
  echo "${result}" | grep -q "NEW: raw/c.md" || {
    echo "FAIL: expected NEW detection, got: ${result}"; teardown; exit 1
  }
  echo "PASS: test_diff_detects_new_file"
  teardown
}

test_diff_detects_modified_file() {
  setup
  python3 "${TOOL}" build "${WIKI}"
  echo "ALPHA CHANGED" > "${WIKI}/raw/a.md"
  local result
  result="$(python3 "${TOOL}" diff "${WIKI}")"
  echo "${result}" | grep -q "MODIFIED: raw/a.md" || {
    echo "FAIL: expected MODIFIED detection, got: ${result}"; teardown; exit 1
  }
  echo "PASS: test_diff_detects_modified_file"
  teardown
}

test_build_manifest_fresh
test_diff_clean
test_diff_detects_new_file
test_diff_detects_modified_file
echo "ALL PASS"
```

- [ ] **Step 2: Run to see failure**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-manifest.sh
bash /Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-manifest.sh
```

Expected: FAIL — tool missing.

- [ ] **Step 3: Write wiki-manifest.py**

Create `/Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-manifest.py`:
```python
#!/usr/bin/env python3
"""Hash manifest for raw/ files.

Usage:
    wiki-manifest.py build <wiki_root>
    wiki-manifest.py diff <wiki_root>

build: writes .manifest.json mapping raw/ paths to sha256.
diff: compares live raw/ against manifest; prints CLEAN or a list of
      NEW: / MODIFIED: / DELETED: lines to stdout.
"""

import hashlib
import json
import sys
from pathlib import Path


def _hash_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _scan_raw(wiki_root: Path) -> dict[str, str]:
    """Return {relative-path-from-wiki-root: sha256} for each file in raw/."""
    result: dict[str, str] = {}
    raw = wiki_root / "raw"
    if not raw.exists():
        return result
    for p in raw.rglob("*"):
        if p.is_file() and not p.name.startswith("."):
            rel = str(p.relative_to(wiki_root))
            result[rel] = _hash_file(p)
    return result


def _load_manifest(wiki_root: Path) -> dict:
    path = wiki_root / ".manifest.json"
    if not path.exists():
        return {}
    with path.open("r") as f:
        return json.load(f)


def cmd_build(wiki_root: Path) -> int:
    from datetime import datetime, timezone

    hashes = _scan_raw(wiki_root)
    existing = _load_manifest(wiki_root)
    now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    out = {}
    for rel, sha in hashes.items():
        prev = existing.get(rel, {})
        out[rel] = {
            "sha256": sha,
            "last_ingested": prev.get("last_ingested", now),
        }
    (wiki_root / ".manifest.json").write_text(
        json.dumps(out, indent=2, sort_keys=True) + "\n"
    )
    return 0


def cmd_diff(wiki_root: Path) -> int:
    manifest = _load_manifest(wiki_root)
    live = _scan_raw(wiki_root)

    lines: list[str] = []

    for rel, sha in live.items():
        if rel not in manifest:
            lines.append(f"NEW: {rel}")
        elif manifest[rel].get("sha256") != sha:
            lines.append(f"MODIFIED: {rel}")

    for rel in manifest:
        if rel not in live:
            lines.append(f"DELETED: {rel}")

    if not lines:
        print("CLEAN")
    else:
        print("\n".join(lines))
    return 0


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: wiki-manifest.py {build|diff} <wiki_root>", file=sys.stderr)
        return 1

    cmd = sys.argv[1]
    wiki_root = Path(sys.argv[2]).resolve()
    if not wiki_root.is_dir():
        print(f"not a directory: {wiki_root}", file=sys.stderr)
        return 1

    if cmd == "build":
        return cmd_build(wiki_root)
    if cmd == "diff":
        return cmd_diff(wiki_root)
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
```

- [ ] **Step 4: Make executable, run tests**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-manifest.py
bash /Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-manifest.sh
```

Expected output:
```
PASS: test_build_manifest_fresh
PASS: test_diff_clean
PASS: test_diff_detects_new_file
PASS: test_diff_detects_modified_file
ALL PASS
```

- [ ] **Step 5: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/karpathy-wiki
git add scripts/wiki-manifest.py tests/unit/test-manifest.sh
git commit -m "feat: hash manifest for raw/ drift detection"
```

---

## Task 13: Auto-init — create wiki structure idempotently

**Files:**
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-init.sh`
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-init.sh`

- [ ] **Step 1: Write failing test**

Create `/Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-init.sh`:
```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/wiki-lib.sh"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

setup() {
  TESTDIR="$(mktemp -d)"
}

teardown() { rm -rf "${TESTDIR}"; }

test_init_main_creates_structure() {
  setup
  bash "${INIT}" main "${TESTDIR}/wiki" >/dev/null
  for f in index.md log.md schema.md .wiki-config .manifest.json .gitignore; do
    [[ -e "${TESTDIR}/wiki/${f}" ]] || { echo "FAIL: missing ${f}"; teardown; exit 1; }
  done
  for d in concepts entities sources queries raw .wiki-pending .locks; do
    [[ -d "${TESTDIR}/wiki/${d}" ]] || { echo "FAIL: missing dir ${d}"; teardown; exit 1; }
  done
  echo "PASS: test_init_main_creates_structure"
  teardown
}

test_init_main_writes_correct_role() {
  setup
  bash "${INIT}" main "${TESTDIR}/wiki" >/dev/null
  grep -q '^role = "main"' "${TESTDIR}/wiki/.wiki-config" || {
    echo "FAIL: role != main"; teardown; exit 1
  }
  echo "PASS: test_init_main_writes_correct_role"
  teardown
}

test_init_project_links_to_main() {
  setup
  bash "${INIT}" main "${TESTDIR}/main-wiki" >/dev/null
  bash "${INIT}" project "${TESTDIR}/proj/wiki" "${TESTDIR}/main-wiki" >/dev/null
  grep -q '^role = "project"' "${TESTDIR}/proj/wiki/.wiki-config" || {
    echo "FAIL: role != project"; teardown; exit 1
  }
  grep -q "main = \"${TESTDIR}/main-wiki\"" "${TESTDIR}/proj/wiki/.wiki-config" || {
    echo "FAIL: main path not recorded"; teardown; exit 1
  }
  echo "PASS: test_init_project_links_to_main"
  teardown
}

test_init_idempotent() {
  setup
  bash "${INIT}" main "${TESTDIR}/wiki" >/dev/null
  echo "CUSTOM INDEX" > "${TESTDIR}/wiki/index.md"
  bash "${INIT}" main "${TESTDIR}/wiki" >/dev/null
  grep -q "CUSTOM INDEX" "${TESTDIR}/wiki/index.md" || {
    echo "FAIL: re-init clobbered existing index.md"; teardown; exit 1
  }
  echo "PASS: test_init_idempotent"
  teardown
}

test_init_creates_git_repo_if_git_installed() {
  setup
  if ! command -v git >/dev/null 2>&1; then
    echo "SKIP: test_init_creates_git_repo (git not installed)"
    teardown; return
  fi
  bash "${INIT}" main "${TESTDIR}/wiki" >/dev/null
  [[ -d "${TESTDIR}/wiki/.git" ]] || { echo "FAIL: .git not created"; teardown; exit 1; }
  echo "PASS: test_init_creates_git_repo_if_git_installed"
  teardown
}

test_init_main_creates_structure
test_init_main_writes_correct_role
test_init_project_links_to_main
test_init_idempotent
test_init_creates_git_repo_if_git_installed
echo "ALL PASS"
```

- [ ] **Step 2: Run to see failure**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-init.sh
bash /Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-init.sh
```

Expected: FAIL — wiki-init.sh missing.

- [ ] **Step 3: Write wiki-init.sh**

Create `/Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-init.sh`:
```bash
#!/bin/bash
# Initialize a wiki directory (main or project).
# Idempotent: never overwrites existing files.
#
# Usage:
#   wiki-init.sh main <wiki_path>
#   wiki-init.sh project <wiki_path> <main_wiki_path>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"

usage() {
  cat >&2 <<EOF
usage:
  wiki-init.sh main <wiki_path>
  wiki-init.sh project <wiki_path> <main_wiki_path>
EOF
  exit 1
}

[[ $# -ge 2 ]] || usage
role="$1"
wiki="$2"
main_path="${3:-}"

case "${role}" in
  main)
    [[ -z "${main_path}" ]] || { echo >&2 "main role takes no main_path arg"; usage; }
    ;;
  project)
    [[ -n "${main_path}" ]] || { echo >&2 "project role requires main_path"; usage; }
    ;;
  *) usage ;;
esac

# Python 3.11+ required for tomllib. Fail fast with a clear error if missing.
if ! command -v python3 >/dev/null 2>&1; then
  echo >&2 "ERROR: python3 not found on PATH; karpathy-wiki requires Python 3.11+"
  exit 1
fi
if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)'; then
  echo >&2 "ERROR: Python 3.11+ required (tomllib is stdlib from 3.11). Detected: $(python3 --version 2>&1)"
  exit 1
fi

mkdir -p "${wiki}"

# Directories (always ensure present)
for d in concepts entities sources queries raw .wiki-pending .locks .obsidian; do
  mkdir -p "${wiki}/${d}"
done

# Files — create only if missing.
today="$(date +%Y-%m-%d)"

if [[ ! -f "${wiki}/.wiki-config" ]]; then
  if [[ "${role}" == "main" ]]; then
    cat > "${wiki}/.wiki-config" <<EOF
role = "main"
created = "${today}"

[platform]
agent_cli = "claude"
headless_command = "claude -p"

[settings]
auto_commit = true
EOF
  else
    cat > "${wiki}/.wiki-config" <<EOF
role = "project"
main = "${main_path}"
created = "${today}"

[platform]
agent_cli = "claude"
headless_command = "claude -p"

[settings]
auto_commit = true
EOF
  fi
fi

if [[ ! -f "${wiki}/index.md" ]]; then
  cat > "${wiki}/index.md" <<'EOF'
# Wiki Index

## Concepts
(empty)

## Entities
(empty)

## Sources
(empty)

## Queries
(empty)
EOF
fi

if [[ ! -f "${wiki}/log.md" ]]; then
  cat > "${wiki}/log.md" <<EOF
# Wiki Log

## [${today}] init | wiki created
EOF
fi

if [[ ! -f "${wiki}/schema.md" ]]; then
  cat > "${wiki}/schema.md" <<EOF
# Wiki Schema

## Role
${role}

## Categories
- \`concepts/\` — ideas, patterns, principles
- \`entities/\` — specific tools, services, APIs
- \`sources/\` — one summary page per ingested source
- \`queries/\` — filed Q&A worth keeping

## Tag Taxonomy (bounded)
Tags are evolved by the ingester; propose changes via schema edits, not ad-hoc.

## Numeric Thresholds
- Split a concept page: 2+ sources or 200+ lines
- Archive a raw source: referenced by 5+ wiki pages
- Restructure top-level category: 500+ pages within it
EOF
fi

if [[ ! -f "${wiki}/.manifest.json" ]]; then
  echo '{}' > "${wiki}/.manifest.json"
fi

if [[ ! -f "${wiki}/.gitignore" ]]; then
  cat > "${wiki}/.gitignore" <<'EOF'
# Runtime state (per-machine, never commit)
.locks/
.ingest.log
EOF
fi

# .obsidian/app.json — for Obsidian users; harmless if never opened
if [[ ! -f "${wiki}/.obsidian/app.json" ]]; then
  cat > "${wiki}/.obsidian/app.json" <<'EOF'
{
  "userIgnoreFilters": [
    ".wiki-pending/",
    ".locks/",
    ".ingest.log",
    ".manifest.json"
  ]
}
EOF
fi

# Git init — only if git available and wiki isn't already in a git repo
if command -v git >/dev/null 2>&1; then
  if ! (cd "${wiki}" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
    (cd "${wiki}" && git init >/dev/null && git add . && git commit -m "chore: init wiki" >/dev/null 2>&1 || true)
  fi
fi

echo "initialized: ${wiki} (${role})"
```

- [ ] **Step 4: Make executable, run tests**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-init.sh
bash /Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-init.sh
```

Expected output:
```
PASS: test_init_main_creates_structure
PASS: test_init_main_writes_correct_role
PASS: test_init_project_links_to_main
PASS: test_init_idempotent
PASS: test_init_creates_git_repo_if_git_installed
ALL PASS
```

- [ ] **Step 5: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/karpathy-wiki
git add scripts/wiki-init.sh tests/unit/test-init.sh
git commit -m "feat: auto-init wiki structure (idempotent, git-aware)"
```

---

## Task 14: Spawn detached headless ingester (stub)

The ingester itself is a Claude Code session that ingests a single capture. At this point, we only build the **spawn helper** — the actual ingester behavior is defined by the skill prose (Phase 3). The spawn script hands off a capture file path + env vars and detaches.

**Files:**
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-spawn-ingester.sh`
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-spawn-ingester.sh`

- [ ] **Step 1: Write failing test**

Create `/Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-spawn-ingester.sh`:
```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SPAWN="${REPO_ROOT}/scripts/wiki-spawn-ingester.sh"

# Override headless_command to a no-op for testing: we only verify
# that the spawner builds the right command and detaches.

setup() {
  TESTDIR="$(mktemp -d)"
  WIKI="${TESTDIR}/wiki"
  mkdir -p "${WIKI}/.wiki-pending"
  cat > "${WIKI}/.wiki-config" <<EOF
role = "main"
[platform]
headless_command = "echo"
[settings]
auto_commit = false
EOF
  cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
     "${WIKI}/.wiki-pending/2026-04-22T14-30-test.md"
}

teardown() { rm -rf "${TESTDIR}"; }

test_spawner_detaches_and_exits_immediately() {
  setup
  local start_ts end_ts elapsed
  start_ts="$(date +%s)"
  bash "${SPAWN}" "${WIKI}" "${WIKI}/.wiki-pending/2026-04-22T14-30-test.md"
  end_ts="$(date +%s)"
  elapsed=$((end_ts - start_ts))
  [[ "${elapsed}" -le 2 ]] || {
    echo "FAIL: spawner took ${elapsed}s, should be near-instant"
    teardown; exit 1
  }
  echo "PASS: test_spawner_detaches_and_exits_immediately"
  teardown
}

test_spawner_exits_0_on_missing_capture() {
  setup
  if bash "${SPAWN}" "${WIKI}" "${WIKI}/.wiki-pending/does-not-exist.md"; then
    echo "PASS: test_spawner_exits_0_on_missing_capture (graceful)"
  else
    echo "FAIL: missing capture should not be fatal"
    teardown; exit 1
  fi
  teardown
}

test_spawner_detaches_and_exits_immediately
test_spawner_exits_0_on_missing_capture
echo "ALL PASS"
```

- [ ] **Step 2: Run to see failure**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-spawn-ingester.sh
bash /Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-spawn-ingester.sh
```

Expected: FAIL — spawner missing.

- [ ] **Step 3: Write wiki-spawn-ingester.sh**

Create `/Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-spawn-ingester.sh`:
```bash
#!/bin/bash
# Spawn a detached headless ingester for a single capture.
#
# Usage:
#   wiki-spawn-ingester.sh <wiki_root> <capture_path>
#
# This script exits within milliseconds. The ingester runs in the background
# (child of init via setsid), surviving the parent session.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"

wiki="$1"
capture="$2"

[[ -n "${wiki}" ]] || { echo >&2 "missing wiki_root"; exit 1; }
[[ -n "${capture}" ]] || { echo >&2 "missing capture_path"; exit 1; }

# Graceful no-op if capture doesn't exist.
if [[ ! -f "${capture}" ]]; then
  log_warn "spawn: capture missing, skipping: ${capture}"
  exit 0
fi

# Read platform.headless_command from config.
headless_cmd="$(wiki_config_get "${wiki}" platform.headless_command 2>/dev/null || echo "")"
if [[ -z "${headless_cmd}" ]]; then
  log_error "spawn: no headless_command configured"
  exit 1
fi

# Build the ingest prompt.
# The skill prose defines what this prompt means operationally.
prompt="Ingest this capture into the wiki. Wiki root: ${wiki}. Capture file: ${capture}. Follow the karpathy-wiki skill's INGEST operation exactly."

# Explicit env passthrough (Anthropic API keys, etc.).
# Headless workers don't inherit interactive-session env by default on some platforms.
env_passthrough=(
  "HOME=${HOME}"
  "PATH=${PATH}"
  "ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY:-}"
  "WIKI_ROOT=${wiki}"
  "WIKI_CAPTURE=${capture}"
)

# Detach via setsid (Linux) or nohup (macOS/BSD fallback).
# Output goes to .ingest.log.
logfile="${wiki}/.ingest.log"

if command -v setsid >/dev/null 2>&1; then
  setsid env "${env_passthrough[@]}" \
    ${headless_cmd} "${prompt}" \
    >> "${logfile}" 2>&1 < /dev/null &
else
  nohup env "${env_passthrough[@]}" \
    ${headless_cmd} "${prompt}" \
    >> "${logfile}" 2>&1 < /dev/null &
fi

log_info "spawned ingester: capture=$(basename "${capture}") pid=$!"
# Disown so the spawner can exit cleanly.
disown 2>/dev/null || true
exit 0
```

- [ ] **Step 4: Make executable, run test**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-spawn-ingester.sh
bash /Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-spawn-ingester.sh
```

Expected:
```
PASS: test_spawner_detaches_and_exits_immediately
PASS: test_spawner_exits_0_on_missing_capture (graceful)
ALL PASS
```

- [ ] **Step 5: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/karpathy-wiki
git add scripts/wiki-spawn-ingester.sh tests/unit/test-spawn-ingester.sh
git commit -m "feat: detached ingester spawner (setsid/nohup)"
```

---

## Task 15: SessionStart hook — drift + drain

**Files:**
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/hooks/session-start`
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/integration/test-session-start.sh`

- [ ] **Step 1: Write failing integration test**

Create `/Users/lukaszmaj/dev/karpathy-wiki/tests/integration/test-session-start.sh`:
```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${REPO_ROOT}/hooks/session-start"

setup() {
  TESTDIR="$(mktemp -d)"
  export HOME="${TESTDIR}"
  WIKI="${TESTDIR}/wiki"
  bash "${REPO_ROOT}/scripts/wiki-init.sh" main "${WIKI}" >/dev/null
  export WIKI_TEST_ROOT="${WIKI}"
  # Override headless_command so ingester doesn't actually try to run claude
  sed -i.bak 's|claude -p|echo|' "${WIKI}/.wiki-config"
  rm -f "${WIKI}/.wiki-config.bak"
}

teardown() { rm -rf "${TESTDIR}"; }

test_hook_emits_empty_context_on_clean_wiki() {
  setup
  local output
  output="$(cd "${WIKI}" && bash "${HOOK}")"
  # Per superpowers-style-guide, hooks must emit zero model-visible context.
  # Empty output or just {} is acceptable; anything else is a regression.
  if [[ -z "${output}" ]] || [[ "${output}" == "{}" ]]; then
    echo "PASS: test_hook_emits_empty_context_on_clean_wiki"
  else
    echo "FAIL: hook emitted context on clean wiki: '${output}'"
    teardown; exit 1
  fi
  teardown
}

test_hook_spawns_ingester_for_pending() {
  setup
  # Drop a pending capture
  cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
     "${WIKI}/.wiki-pending/2026-04-22T14-30-pending.md"
  (cd "${WIKI}" && bash "${HOOK}") >/dev/null
  # Give spawner a moment
  sleep 1
  # Capture should be claimed (renamed to .processing) or archived
  local has_pending has_processing
  has_pending=0
  has_processing=0
  for f in "${WIKI}/.wiki-pending"/*.md; do
    [[ -f "${f}" ]] || continue
    [[ "${f}" == *.processing ]] && has_processing=1 && continue
    has_pending=1
  done
  # Expect processing or fully consumed.
  # With echo-as-headless, the ingester does nothing, so capture stays as .processing.
  if [[ "${has_processing}" -eq 1 ]] || [[ "${has_pending}" -eq 0 ]]; then
    echo "PASS: test_hook_spawns_ingester_for_pending"
  else
    echo "FAIL: capture not claimed"
    ls "${WIKI}/.wiki-pending/"
    teardown; exit 1
  fi
  teardown
}

test_hook_exits_fast() {
  setup
  local start end elapsed
  start="$(date +%s)"
  (cd "${WIKI}" && bash "${HOOK}") >/dev/null
  end="$(date +%s)"
  elapsed=$((end - start))
  [[ "${elapsed}" -le 3 ]] || {
    echo "FAIL: hook took ${elapsed}s, should be <=3"; teardown; exit 1
  }
  echo "PASS: test_hook_exits_fast (${elapsed}s)"
  teardown
}

test_hook_emits_empty_context_on_clean_wiki
test_hook_spawns_ingester_for_pending
test_hook_exits_fast
echo "ALL PASS"
```

- [ ] **Step 2: Run to see failure**

Run:
```bash
mkdir -p /Users/lukaszmaj/dev/karpathy-wiki/hooks
chmod +x /Users/lukaszmaj/dev/karpathy-wiki/tests/integration/test-session-start.sh
bash /Users/lukaszmaj/dev/karpathy-wiki/tests/integration/test-session-start.sh
```

Expected: FAIL — hook missing.

- [ ] **Step 3: Write session-start hook**

Create `/Users/lukaszmaj/dev/karpathy-wiki/hooks/session-start`:
```bash
#!/bin/bash
# SessionStart hook for karpathy-wiki.
#
# Responsibilities:
#   1. Detect if cwd (or a parent) contains a wiki; exit 0 silently if not.
#   2. Run drift check on raw/ — if new/modified sources, create captures.
#   3. Drain pending captures: spawn one detached ingester per capture.
#   4. Reclaim stale .processing files.
#   5. Emit ZERO model-visible context (stdout stays empty or '{}').
#
# Per superpowers-style-guide.md, we write to files (.ingest.log), never echo.

# NOTE: no `set -e` — we want best-effort execution; a failing drift-check
# should not prevent drain. Use `set -uo pipefail` for safer var handling.
set -uo pipefail

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HOOK_DIR}/.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/wiki-lib.sh"

# Locate wiki from cwd.
wiki="$(wiki_root_from_cwd 2>/dev/null || echo "")"
[[ -n "${wiki}" ]] || exit 0  # No wiki; nothing to do.

log_info "session-start: wiki=${wiki}"

# ---------------------------------------------------------------------------
# Drift check — detect new/modified files in raw/ and create drift captures.
# ---------------------------------------------------------------------------
# Wrapped in a function so we can use `local` for variables.
_drift_scan() {
  local drift_out
  drift_out="$(python3 "${REPO_ROOT}/scripts/wiki-manifest.py" diff "${wiki}" 2>/dev/null || echo "CLEAN")"
  [[ "${drift_out}" == "CLEAN" ]] && return 0

  log_info "session-start: drift detected"
  local line src capture_name capture_path
  while IFS= read -r line; do
    case "${line}" in
      NEW:*|MODIFIED:*)
        src="$(echo "${line}" | awk '{print $2}')"
        capture_name="$(date +%Y-%m-%dT%H-%M)-drift-$(slugify "${src}").md"
        capture_path="${wiki}/.wiki-pending/${capture_name}"
        # Idempotency: skip if a drift capture for this src already exists.
        if [[ -f "${capture_path}" ]]; then
          continue
        fi
        cat > "${capture_path}" <<EOF
---
title: "Drift: ${src}"
evidence: "${wiki}/${src}"
evidence_type: "file"
suggested_action: "update"
suggested_pages: []
captured_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
captured_by: "session-start-drift"
origin: null
---

Raw source \`${src}\` changed since last manifest. Treat as new source.
EOF
        log_info "session-start: drift capture created: ${capture_name}"
        ;;
    esac
  done <<< "${drift_out}"
}
_drift_scan || log_warn "session-start: drift scan failed (non-fatal)"

# ---------------------------------------------------------------------------
# Drain pending captures — spawn a detached ingester per capture.
# ---------------------------------------------------------------------------
_drain_pending() {
  local count=0
  local f
  for f in "${wiki}/.wiki-pending"/*.md; do
    [[ -f "${f}" ]] || continue
    [[ "${f}" == *.processing ]] && continue
    count=$((count + 1))
  done
  [[ "${count}" -eq 0 ]] && return 0

  log_info "session-start: draining ${count} pending captures"
  for f in "${wiki}/.wiki-pending"/*.md; do
    [[ -f "${f}" ]] || continue
    [[ "${f}" == *.processing ]] && continue
    bash "${REPO_ROOT}/scripts/wiki-spawn-ingester.sh" "${wiki}" "${f}" &
    disown 2>/dev/null || true
  done
}
_drain_pending || log_warn "session-start: drain failed (non-fatal)"

# ---------------------------------------------------------------------------
# Reclaim stale .processing files (> 10 min): rename back to .md so next
# opportunity can pick them up.
# ---------------------------------------------------------------------------
_reclaim_stale() {
  local proc mtime now age
  while IFS= read -r proc; do
    [[ -z "${proc}" ]] && continue
    mtime="$(stat -f %m "${proc}" 2>/dev/null || stat -c %Y "${proc}" 2>/dev/null || echo 0)"
    now="$(date +%s)"
    age=$((now - mtime))
    if [[ "${age}" -gt 600 ]]; then
      log_warn "session-start: reclaiming stale processing: $(basename "${proc}")"
      mv "${proc}" "${proc%.processing}" || true
    fi
  done < <(find "${wiki}/.wiki-pending" -maxdepth 1 -name "*.md.processing" -type f 2>/dev/null)
}
_reclaim_stale || log_warn "session-start: stale reclaim failed (non-fatal)"

# Emit empty context per superpowers style guide (issue #1220 cost lesson).
# Exit 0. Do NOT echo anything.
exit 0
```

- [ ] **Step 4: Make executable, run tests**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/karpathy-wiki/hooks/session-start
bash /Users/lukaszmaj/dev/karpathy-wiki/tests/integration/test-session-start.sh
```

Expected:
```
PASS: test_hook_emits_empty_context_on_clean_wiki
PASS: test_hook_spawns_ingester_for_pending
PASS: test_hook_exits_fast (0s)
ALL PASS
```

**Note on cross-platform wrapper:** the superpowers-style polyglot `run-hook.cmd` (bash+cmd single-file) is deferred to post-MVP. v1 targets macOS/Linux only. Windows support comes when we expand to Windows-using platforms.

- [ ] **Step 5: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/karpathy-wiki
git add hooks/session-start tests/integration/test-session-start.sh
git commit -m "feat: SessionStart hook (drift + drain + empty context)"
```

---

## Task 16: Stop hook — transcript sweep stub

**Files:**
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/hooks/stop`

The Stop hook's full behavior (spawn a cheap model to scan transcript) depends on the skill prose + a cheap-model subagent. At this stage we ship the stub that just logs the event. The sweep gets wired up in Phase 3 when the skill prose defines it.

- [ ] **Step 1: Write stop hook stub**

Create `/Users/lukaszmaj/dev/karpathy-wiki/hooks/stop`:
```bash
#!/bin/bash
# Stop hook for karpathy-wiki.
#
# v1: stub — just log that session stopped, don't do sweep yet.
# Post-MVP: spawn cheap-model subagent to scan the session transcript for
# missed captures. The exact transcript-file env var name varies by Claude
# Code version (could be CLAUDE_TRANSCRIPT, CLAUDE_SESSION_TRANSCRIPT, etc.);
# resolve at implementation time by reading Claude Code docs / running a
# `env | grep CLAUDE` check inside a live hook invocation.

set -uo pipefail  # not -e — stop must never abort with a partial log

HOOK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${HOOK_DIR}/.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/wiki-lib.sh"

wiki="$(wiki_root_from_cwd 2>/dev/null || echo "")"
[[ -n "${wiki}" ]] || exit 0

log_info "stop: session ended, wiki=${wiki}"

# Post-MVP: spawn cheap-model sweep of "${CLAUDE_TRANSCRIPT:-}" if set.
# For v1, we rely on in-session capture only.

exit 0
```

- [ ] **Step 2: Make executable**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/karpathy-wiki/hooks/stop
```

- [ ] **Step 3: Add a smoke test for stop hook**

Run and verify manually:
```bash
cd /tmp
mkdir -p /tmp/stop-smoke/wiki
bash /Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-init.sh main /tmp/stop-smoke/wiki >/dev/null
cd /tmp/stop-smoke
bash /Users/lukaszmaj/dev/karpathy-wiki/hooks/stop
grep -q "stop: session ended" /tmp/stop-smoke/wiki/.ingest.log && echo "SMOKE PASS" || echo "SMOKE FAIL"
rm -rf /tmp/stop-smoke
```

Expected: `SMOKE PASS`

- [ ] **Step 4: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/karpathy-wiki
git add hooks/stop
git commit -m "feat: Stop hook stub (post-MVP: transcript sweep)"
```

---

## Task 16b: hooks/hooks.json — Claude Code plugin hook manifest

Without this file, Claude Code's plugin loader does not discover our hooks. This is the file Claude Code auto-reads when it sees a plugin; it must declare the `matcher` narrowing explicitly (matches superpowers' issue #1220 lesson: narrow fire-set to `startup|clear|compact`, never `.*`).

**Files:**
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/hooks/hooks.json`

- [ ] **Step 1: Write hooks.json**

Create `/Users/lukaszmaj/dev/karpathy-wiki/hooks/hooks.json`:
```json
{
  "SessionStart": [
    {
      "matcher": "startup|clear|compact",
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/hooks/session-start"
        }
      ]
    }
  ],
  "Stop": [
    {
      "matcher": ".*",
      "hooks": [
        {
          "type": "command",
          "command": "${CLAUDE_PLUGIN_ROOT}/hooks/stop"
        }
      ]
    }
  ]
}
```

**Matcher notes:**
- `SessionStart` matcher `startup|clear|compact` deliberately excludes `resume` (per superpowers issue #1220 — `resume` fires too often and burns tokens; also the skill's state is already in sync on resume).
- `Stop` matcher `.*` is fine because Stop is cheap in v1 (it's a stub that logs and exits).
- `type: command` invokes the extensionless hook script directly. No prompt-type hook anywhere in v1.

- [ ] **Step 2: Verify schema**

Run:
```bash
python3 -c "import json, sys; json.load(open('/Users/lukaszmaj/dev/karpathy-wiki/hooks/hooks.json')); print('OK')"
```

Expected: `OK`

- [ ] **Step 3: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/karpathy-wiki
git add hooks/hooks.json
git commit -m "feat: Claude Code plugin hook manifest (narrowed matcher)"
```

---

## Task 17: Background auto-commit after successful ingest

**Files:**
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-commit.sh`
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-commit.sh`

- [ ] **Step 1: Write failing test**

Create `/Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-commit.sh`:
```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMMIT="${REPO_ROOT}/scripts/wiki-commit.sh"

setup() {
  TESTDIR="$(mktemp -d)"
  WIKI="${TESTDIR}/wiki"
  bash "${REPO_ROOT}/scripts/wiki-init.sh" main "${WIKI}" >/dev/null
}

teardown() { rm -rf "${TESTDIR}"; }

test_commit_nothing_if_no_changes() {
  setup
  # initial commit was made by init. With no subsequent changes, commit should be a no-op.
  bash "${COMMIT}" "${WIKI}" "Nothing to commit"
  # Count commits
  local count
  count="$(cd "${WIKI}" && git rev-list --count HEAD)"
  # Should still be 1 (init commit), not 2
  [[ "${count}" -eq 1 ]] || { echo "FAIL: expected 1 commit, got ${count}"; teardown; exit 1; }
  echo "PASS: test_commit_nothing_if_no_changes"
  teardown
}

test_commit_creates_commit_with_message() {
  setup
  echo "# Changed" >> "${WIKI}/index.md"
  bash "${COMMIT}" "${WIKI}" "ingest: test title"
  local last
  last="$(cd "${WIKI}" && git log -1 --format=%s)"
  [[ "${last}" == "ingest: test title" ]] || {
    echo "FAIL: commit message. got '${last}'"; teardown; exit 1
  }
  echo "PASS: test_commit_creates_commit_with_message"
  teardown
}

test_commit_respects_auto_commit_false() {
  setup
  sed -i.bak 's/auto_commit = true/auto_commit = false/' "${WIKI}/.wiki-config"
  rm -f "${WIKI}/.wiki-config.bak"
  echo "# Changed" >> "${WIKI}/index.md"
  bash "${COMMIT}" "${WIKI}" "ingest: should not commit"
  local last
  last="$(cd "${WIKI}" && git log -1 --format=%s)"
  # Should still be the init commit, not the new one
  [[ "${last}" != "ingest: should not commit" ]] || {
    echo "FAIL: commit created despite auto_commit=false"; teardown; exit 1
  }
  echo "PASS: test_commit_respects_auto_commit_false"
  teardown
}

test_commit_nothing_if_no_changes
test_commit_creates_commit_with_message
test_commit_respects_auto_commit_false
echo "ALL PASS"
```

- [ ] **Step 2: Run to see failure**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-commit.sh
bash /Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-commit.sh
```

Expected: FAIL — wiki-commit.sh missing.

- [ ] **Step 3: Write wiki-commit.sh**

Create `/Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-commit.sh`:
```bash
#!/bin/bash
# Commit wiki changes with a structured message. Idempotent.
#
# Usage:
#   wiki-commit.sh <wiki_root> <message>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"

wiki="$1"
msg="$2"

[[ -n "${wiki}" ]] || { echo >&2 "missing wiki_root"; exit 1; }
[[ -n "${msg}" ]]  || { echo >&2 "missing message"; exit 1; }

# Respect auto_commit setting.
auto_commit="$(wiki_config_get "${wiki}" settings.auto_commit 2>/dev/null || echo "true")"
if [[ "${auto_commit}" != "true" ]]; then
  log_info "commit: auto_commit disabled, skipping"
  exit 0
fi

# Git must be available and wiki must be a git repo.
command -v git >/dev/null 2>&1 || { log_warn "commit: git not installed"; exit 0; }
if ! (cd "${wiki}" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
  log_warn "commit: wiki is not a git repo"
  exit 0
fi

cd "${wiki}"
git add -A

# If nothing staged, silently exit.
if git diff --cached --quiet; then
  log_info "commit: nothing to commit"
  exit 0
fi

git commit -m "${msg}" >/dev/null 2>&1 || {
  log_error "commit: git commit failed"
  exit 1
}
log_info "commit: ${msg}"
exit 0
```

- [ ] **Step 4: Make executable, run test**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-commit.sh
bash /Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-commit.sh
```

Expected:
```
PASS: test_commit_nothing_if_no_changes
PASS: test_commit_creates_commit_with_message
PASS: test_commit_respects_auto_commit_false
ALL PASS
```

- [ ] **Step 5: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/karpathy-wiki
git add scripts/wiki-commit.sh tests/unit/test-commit.sh
git commit -m "feat: auto-commit after ingest (respects settings.auto_commit)"
```

---

## Task 18: wiki status — read-only health report

**Files:**
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-status.sh`
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-status.sh`

- [ ] **Step 1: Write failing test**

Create `/Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-status.sh`:
```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STATUS="${REPO_ROOT}/scripts/wiki-status.sh"

setup() {
  TESTDIR="$(mktemp -d)"
  WIKI="${TESTDIR}/wiki"
  bash "${REPO_ROOT}/scripts/wiki-init.sh" main "${WIKI}" >/dev/null
}

teardown() { rm -rf "${TESTDIR}"; }

test_status_on_empty_wiki() {
  setup
  local output
  output="$(bash "${STATUS}" "${WIKI}")"
  echo "${output}" | grep -q "role: main" || { echo "FAIL: role missing"; teardown; exit 1; }
  echo "${output}" | grep -q "pending: 0" || { echo "FAIL: pending missing"; teardown; exit 1; }
  echo "${output}" | grep -q "total pages:" || { echo "FAIL: total pages missing"; teardown; exit 1; }
  echo "PASS: test_status_on_empty_wiki"
  teardown
}

test_status_counts_pending() {
  setup
  cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
     "${WIKI}/.wiki-pending/c1.md"
  cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
     "${WIKI}/.wiki-pending/c2.md"
  local output
  output="$(bash "${STATUS}" "${WIKI}")"
  echo "${output}" | grep -q "pending: 2" || {
    echo "FAIL: expected 'pending: 2', got:"
    echo "${output}"
    teardown; exit 1
  }
  echo "PASS: test_status_counts_pending"
  teardown
}

test_status_on_empty_wiki
test_status_counts_pending
echo "ALL PASS"
```

- [ ] **Step 2: Run to see failure**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-status.sh
bash /Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-status.sh
```

Expected: FAIL — wiki-status.sh missing.

- [ ] **Step 3: Write wiki-status.sh**

Create `/Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-status.sh`:
```bash
#!/bin/bash
# Read-only wiki health report.
#
# Usage: wiki-status.sh <wiki_root>

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-lib.sh"
# shellcheck source=/dev/null
source "${SCRIPT_DIR}/wiki-capture.sh"

wiki="$1"
[[ -n "${wiki}" ]] || { echo >&2 "usage: wiki-status.sh <wiki_root>"; exit 1; }
[[ -d "${wiki}" ]] || { echo >&2 "not a directory: ${wiki}"; exit 1; }
[[ -f "${wiki}/.wiki-config" ]] || { echo >&2 "not a wiki: ${wiki}"; exit 1; }

role="$(wiki_config_get "${wiki}" role)"
pending="$(wiki_capture_count_pending "${wiki}")"
processing="$(find "${wiki}/.wiki-pending" -maxdepth 1 -name "*.processing" 2>/dev/null | wc -l | tr -d ' ')"
locks="$(find "${wiki}/.locks" -maxdepth 1 -name "*.lock" 2>/dev/null | wc -l | tr -d ' ')"
total_pages="$(find "${wiki}" -type f -name "*.md" -not -path "*/.wiki-pending/*" 2>/dev/null | wc -l | tr -d ' ')"

last_ingest="never"
if [[ -f "${wiki}/log.md" ]]; then
  last_ingest="$(grep -oE '^## \[[0-9]{4}-[0-9]{2}-[0-9]{2}\]' "${wiki}/log.md" | tail -1 | tr -d '[]# ')"
fi

# Drift
drift="$(python3 "${SCRIPT_DIR}/wiki-manifest.py" diff "${wiki}" 2>/dev/null | head -1)"

# Git state
git_status="n/a"
if command -v git >/dev/null 2>&1 && (cd "${wiki}" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
  if (cd "${wiki}" && git diff --quiet && git diff --cached --quiet); then
    git_status="clean"
  else
    git_status="dirty"
  fi
fi

cat <<EOF
wiki: ${wiki}
role: ${role}
total pages: ${total_pages}
pending: ${pending}
processing: ${processing}
active locks: ${locks}
last ingest: ${last_ingest}
drift: ${drift}
git: ${git_status}
EOF
```

- [ ] **Step 4: Make executable, run test**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-status.sh
bash /Users/lukaszmaj/dev/karpathy-wiki/tests/unit/test-status.sh
```

Expected:
```
PASS: test_status_on_empty_wiki
PASS: test_status_counts_pending
ALL PASS
```

- [ ] **Step 5: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/karpathy-wiki
git add scripts/wiki-status.sh tests/unit/test-status.sh
git commit -m "feat: wiki-status (read-only health report)"
```

---

## Task 19: User-facing `wiki` dispatcher

**Files:**
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/bin/wiki`

- [ ] **Step 1: Write dispatcher**

Create `/Users/lukaszmaj/dev/karpathy-wiki/bin/wiki`:
```bash
#!/bin/bash
# karpathy-wiki user CLI.
#
# Subcommands:
#   wiki status         — health report
#   wiki doctor         — deep lint (post-MVP placeholder)
#
# All other interactions are via natural language to the agent.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/wiki-lib.sh"

sub="${1:-help}"
shift || true

wiki_root() {
  local w
  w="$(wiki_root_from_cwd 2>/dev/null || echo "")"
  [[ -n "${w}" ]] || { echo >&2 "no wiki found in cwd or parents"; exit 1; }
  echo "${w}"
}

case "${sub}" in
  status)
    bash "${REPO_ROOT}/scripts/wiki-status.sh" "$(wiki_root)"
    ;;
  doctor)
    echo "wiki doctor: not implemented in MVP. For now, ask the agent to run a deep lint of the wiki."
    exit 1
    ;;
  help|--help|-h)
    cat <<EOF
usage: wiki <subcommand>

subcommands:
  status     Read-only health report
  doctor     Deep lint + fix (post-MVP)
  help       This message

Everything else — capture, ingest, query — is automatic or via natural
language to the agent. No wiki init / wiki ingest / wiki query commands.
EOF
    ;;
  *)
    echo >&2 "unknown subcommand: ${sub}"
    echo >&2 "try: wiki help"
    exit 1
    ;;
esac
```

- [ ] **Step 2: Make executable**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/karpathy-wiki/bin/wiki
```

- [ ] **Step 3: Smoke test**

Run:
```bash
cd /tmp
mkdir -p /tmp/wiki-cli-smoke/wiki
bash /Users/lukaszmaj/dev/karpathy-wiki/scripts/wiki-init.sh main /tmp/wiki-cli-smoke/wiki >/dev/null
cd /tmp/wiki-cli-smoke
/Users/lukaszmaj/dev/karpathy-wiki/bin/wiki status
```

Expected output contains: `role: main`, `pending: 0`

Run:
```bash
/Users/lukaszmaj/dev/karpathy-wiki/bin/wiki help
```

Expected: the usage message.

Cleanup:
```bash
rm -rf /tmp/wiki-cli-smoke
```

- [ ] **Step 4: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/karpathy-wiki
git add bin/wiki
git commit -m "feat: user-facing wiki CLI (status only in MVP)"
```

---

## Task 20: End-to-end integration test — capture to committed page

This ties everything together: start with empty wiki, drop a capture, run hook, verify capture was claimed + detached worker spawned + log updated. We use `echo` as the stand-in for `claude -p`, so the ingester doesn't actually produce a wiki page; that's Phase 3. This test verifies the **plumbing**.

**Files:**
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/integration/test-end-to-end-plumbing.sh`

- [ ] **Step 1: Write integration test**

Create `/Users/lukaszmaj/dev/karpathy-wiki/tests/integration/test-end-to-end-plumbing.sh`:
```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

setup() {
  TESTDIR="$(mktemp -d)"
  WIKI="${TESTDIR}/wiki"
  bash "${REPO_ROOT}/scripts/wiki-init.sh" main "${WIKI}" >/dev/null
  # Use echo as a stand-in for claude -p.
  sed -i.bak 's|claude -p|echo stub-ingester|' "${WIKI}/.wiki-config"
  rm -f "${WIKI}/.wiki-config.bak"
}

teardown() { rm -rf "${TESTDIR}"; }

test_capture_drop_plus_hook_plus_spawn() {
  setup

  # Drop a capture
  cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
     "${WIKI}/.wiki-pending/2026-04-22T14-30-test.md"

  # Run session-start hook
  (cd "${WIKI}" && bash "${REPO_ROOT}/hooks/session-start") >/dev/null

  # Wait briefly for spawned workers
  sleep 2

  # Verify: capture either processing or gone
  if [[ -f "${WIKI}/.wiki-pending/2026-04-22T14-30-test.md" ]]; then
    echo "FAIL: capture never claimed"
    ls -la "${WIKI}/.wiki-pending/"
    teardown; exit 1
  fi

  # Verify: ingest log has entries
  grep -q "spawned ingester" "${WIKI}/.ingest.log" || {
    echo "FAIL: spawn not logged"
    cat "${WIKI}/.ingest.log"
    teardown; exit 1
  }

  echo "PASS: test_capture_drop_plus_hook_plus_spawn"
  teardown
}

test_capture_drop_plus_hook_plus_spawn
echo "ALL PASS"
```

- [ ] **Step 2: Run test**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/karpathy-wiki/tests/integration/test-end-to-end-plumbing.sh
bash /Users/lukaszmaj/dev/karpathy-wiki/tests/integration/test-end-to-end-plumbing.sh
```

Expected:
```
PASS: test_capture_drop_plus_hook_plus_spawn
ALL PASS
```

- [ ] **Step 3: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/karpathy-wiki
git add tests/integration/test-end-to-end-plumbing.sh
git commit -m "test: end-to-end plumbing (capture → hook → spawn)"
```

**Exit criterion for Phase 2:** all unit tests pass, end-to-end plumbing test passes, concurrent-ingest test passes. At this point, the machinery works. What's missing is the ingester's actual behavior — that's defined by the skill prose in Phase 3.

---

## Task 20b: Concurrent ingest integration test

Design doc names this risk: two ingesters racing on the same page. The plan's lock primitive (`wiki_lock_acquire`) is unit-tested in isolation but never stressed end-to-end. This task verifies the full capture→claim→lock→edit pipeline under concurrency.

**Files:**
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/integration/test-concurrent-ingest.sh`

- [ ] **Step 1: Write failing test**

Create `/Users/lukaszmaj/dev/karpathy-wiki/tests/integration/test-concurrent-ingest.sh`:
```bash
#!/bin/bash
# Concurrency smoke test: two ingesters race on ONE shared page.
# We simulate the ingester's minimal work (claim + lock + append + release).
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/wiki-lib.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/wiki-lock.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/wiki-capture.sh"

setup() {
  TESTDIR="$(mktemp -d)"
  WIKI="${TESTDIR}/wiki"
  bash "${REPO_ROOT}/scripts/wiki-init.sh" main "${WIKI}" >/dev/null
  # Two captures, both targeting the same page.
  cat > "${WIKI}/.wiki-pending/c1.md" <<'EOF'
---
title: "from capture 1"
suggested_pages: [concepts/shared.md]
---
content-from-c1
EOF
  cat > "${WIKI}/.wiki-pending/c2.md" <<'EOF'
---
title: "from capture 2"
suggested_pages: [concepts/shared.md]
---
content-from-c2
EOF
  # Pre-create the shared page.
  mkdir -p "${WIKI}/concepts"
  echo "# Shared Page" > "${WIKI}/concepts/shared.md"
}

teardown() { rm -rf "${TESTDIR}"; }

# Simulated ingester: claim a capture, lock the target page, append its title,
# release, archive the capture. Uses wait-and-acquire to exercise the polling path.
fake_ingester() {
  local wiki="$1"
  local claimed
  claimed="$(wiki_capture_claim "${wiki}" 2>/dev/null)" || return 0  # nothing to claim
  local title
  title="$(grep -oE '^title:.*' "${claimed}" | head -1 | sed 's/title: *//; s/"//g')"
  # Acquire the shared page lock (wait if held).
  wiki_lock_wait_and_acquire "${wiki}" "concepts/shared.md" "$(basename "${claimed}")" 10 || return 1
  # Append (mimics read-before-write: append preserves existing content).
  printf "\n- ingest entry from: %s\n" "${title}" >> "${wiki}/concepts/shared.md"
  # Simulate minimal work time so races are real.
  sleep 0.1
  wiki_lock_release "${wiki}" "concepts/shared.md"
  # Archive.
  wiki_capture_archive "${wiki}" "${claimed}"
}

test_two_ingesters_no_data_loss() {
  setup
  # Start both in parallel. They should both complete successfully.
  (fake_ingester "${WIKI}") &
  local pid1=$!
  (fake_ingester "${WIKI}") &
  local pid2=$!
  wait "${pid1}"
  wait "${pid2}"

  # Both entries must be present in the page.
  local c1_present c2_present
  c1_present=$(grep -c "from capture 1" "${WIKI}/concepts/shared.md" || echo 0)
  c2_present=$(grep -c "from capture 2" "${WIKI}/concepts/shared.md" || echo 0)

  if [[ "${c1_present}" -eq 1 ]] && [[ "${c2_present}" -eq 1 ]]; then
    echo "PASS: test_two_ingesters_no_data_loss"
  else
    echo "FAIL: data loss. c1=${c1_present} c2=${c2_present}"
    cat "${WIKI}/concepts/shared.md"
    teardown; exit 1
  fi

  # Both captures must be archived (neither pending nor processing).
  local pending_n processing_n
  pending_n=$(find "${WIKI}/.wiki-pending" -maxdepth 1 -name "*.md" -type f 2>/dev/null | wc -l | tr -d ' ')
  processing_n=$(find "${WIKI}/.wiki-pending" -maxdepth 1 -name "*.processing" -type f 2>/dev/null | wc -l | tr -d ' ')
  if [[ "${pending_n}" -eq 0 ]] && [[ "${processing_n}" -eq 0 ]]; then
    echo "PASS: test_both_captures_archived"
  else
    echo "FAIL: leftover state. pending=${pending_n} processing=${processing_n}"
    teardown; exit 1
  fi

  # No stale locks.
  local locks_n
  locks_n=$(find "${WIKI}/.locks" -maxdepth 1 -name "*.lock" -type f 2>/dev/null | wc -l | tr -d ' ')
  [[ "${locks_n}" -eq 0 ]] || {
    echo "FAIL: stale locks remaining (${locks_n})"
    teardown; exit 1
  }
  echo "PASS: no_stale_locks"

  teardown
}

test_two_ingesters_no_data_loss
echo "ALL PASS"
```

- [ ] **Step 2: Run test to see it fail (if it does)**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/karpathy-wiki/tests/integration/test-concurrent-ingest.sh
bash /Users/lukaszmaj/dev/karpathy-wiki/tests/integration/test-concurrent-ingest.sh
```

Expected outcomes:
- If `wiki_capture_claim` and `wiki_lock_*` are correct: `ALL PASS`.
- If the lock protocol has a race: one or both captures fail to show in `concepts/shared.md`, test reports `FAIL: data loss`.

If FAIL: investigate `wiki-lock.sh` and `wiki-capture.sh`. Most likely culprits: `ln` not truly atomic on the filesystem (rare on macOS/Linux), or the poll-and-retry loop in `wiki_lock_wait_and_acquire` missing the unlock signal.

- [ ] **Step 3: Commit once passing**

Run:
```bash
cd /Users/lukaszmaj/dev/karpathy-wiki
git add tests/integration/test-concurrent-ingest.sh
git commit -m "test: concurrent-ingest smoke — two ingesters, shared page"
```

---

# PHASE 3 — SKILL.md and operations

## Task 21: Draft SKILL.md v1 (GREEN phase start)

**Files:**
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/skills/karpathy-wiki/SKILL.md`

- [ ] **Step 1: Write SKILL.md**

Create `/Users/lukaszmaj/dev/karpathy-wiki/skills/karpathy-wiki/SKILL.md`:

````markdown
---
name: karpathy-wiki
description: Use when a session produces durable knowledge a future-you would search for — a research finding, resolved confusion, validated pattern, gotcha, or documented decision; when a research subagent returns a file; when the user pastes a URL or document to study; when `raw/` has unprocessed files; when the user says "add to wiki" / "remember this" / "wiki it" / "save this"; when the user asks "what do we know about X", "how do we handle Y", "what did we decide about Z", "have we seen this before". Do NOT use for routine lookups, obvious code edits, questions clearly outside the wiki's scope, or time-sensitive data that should be fetched fresh.
metadata:
  hermes:
    config:
      - key: wiki.path
        description: Path to main wiki directory
        default: ~/wiki
---

# Karpathy Wiki

Auto-capture and auto-ingest durable knowledge into a git-versioned LLM wiki. Based on Andrej Karpathy's LLM Wiki pattern.

**Announce at start:** "Using the karpathy-wiki skill to [capture this / ingest pending captures / answer from wiki]."

## Iron laws

```
NO WIKI WRITE IN THE FOREGROUND
```

```
NO PAGE EDIT WITHOUT READING THE PAGE FIRST
```

Every wiki-worthy moment becomes a small capture file. Each capture spawns a detached headless ingester that writes pages and commits. The user continues working — ingest never blocks.

## When a wiki exists (orientation protocol)

Before any wiki operation, read these three files in order:

1. `schema.md` — current categories, taxonomy, thresholds
2. `index.md` — what pages exist
3. Last ~10 entries of `log.md` — recent activity

Only then decide what to do. Without this orientation, you will duplicate existing pages, miss relevant cross-references, or violate the schema.

## When no wiki exists (auto-init)

On the first wiki-worthy moment in any directory:

1. If cwd (or a parent) has a `.wiki-config` → use that wiki.
2. Otherwise, if `$HOME/wiki/.wiki-config` exists → cwd is outside a wiki; create a project wiki at `./wiki/` linked to `$HOME/wiki/`.
3. Otherwise → create the main wiki at `$HOME/wiki/`.

Run the init script (script paths below resolve via `$CLAUDE_PLUGIN_ROOT`, which Claude Code sets to the plugin's root directory):

```bash
# For main wiki:
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wiki-init.sh" main "$HOME/wiki"
# For project wiki:
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wiki-init.sh" project "./wiki" "$HOME/wiki"
```

No prompts. No confirmations. Initialization is automatic and idempotent.

## Capture — what, when, how

A **capture** is a tiny markdown file noting that something happened which the wiki should absorb.

### What counts as wiki-worthy (trigger criteria)

Write a capture when any of these fire:

- A research subagent returned a file with durable findings
- You and the user resolved a confusion — something neither of you knew before
- You discovered a gotcha, quirk, or non-obvious behavior in a tool
- You validated a pattern (compared approaches, picked one, with reasons)
- An architectural decision was made with explicit rationale
- External knowledge was found that updates an existing wiki page
- Two claims contradict each other
- The user adds a file to `raw/`

### What is NOT wiki-worthy

Do NOT capture:

- Routine file operations, syntax lookups, boilerplate
- One-off debugging with trivial root causes
- Questions already well-covered by the wiki (orientation protocol tells you)
- Temporary session state, current-task TODOs
- Personal preferences that don't generalize
- Speculation without evidence

### Capture file format

Append a file to `<wiki>/.wiki-pending/` named `<ISO-timestamp>-<slug>.md`:

```markdown
---
title: "<one-line title>"
evidence: "<absolute path to evidence file, OR 'conversation'>"
evidence_type: "file"  # or "conversation" or "mixed"
suggested_action: "create"  # or "update" or "augment"
suggested_pages:
  - concepts/<slug>.md   # paths relative to wiki root
captured_at: "<ISO-8601 UTC timestamp>"
captured_by: "in-session-agent"
origin: null  # set to wiki path if propagated from satellite
---

<one paragraph summary. if evidence_type=conversation, include enough
detail for the ingester to write a page without re-reading the transcript>
```

### After writing a capture

Immediately spawn a detached ingester:

```bash
bash "${CLAUDE_PLUGIN_ROOT}/scripts/wiki-spawn-ingester.sh" "<wiki_root>" "<capture_path>"
```

This returns in milliseconds. The ingester runs in a separate process. You continue the user's task.

**Never wait for the ingester. Never read the capture back. Move on.**

## Ingest — what the headless ingester does

When spawned, the ingester has a single job: process one capture into wiki pages.

### Ingester steps

1. **Claim the capture** by renaming it to `<name>.md.processing` (atomic rename).
   Call: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/wiki-capture.sh"` → `wiki_capture_claim "${WIKI}"`
2. **Read the orientation files**: schema.md, index.md, last 10 entries of log.md.
3. **Read the capture.**
4. **If evidence_type=file**, copy the evidence into `<wiki>/raw/` preserving basename. Update `.manifest.json`.
5. **Decide target pages**: `suggested_pages` is a hint; orientation may change it.
6. **For each target page**:
   a. Acquire a page lock.
   b. Read current page content (read-before-write).
   c. Merge new material. Do NOT replace existing claims — add dated findings, use `contradictions:` frontmatter if they disagree.
   d. Release lock.
7. **Update `index.md`** (locked).
8. **Append to `log.md`**.
9. **If this wiki is a project wiki** and the capture is general-interest:
   write a new capture in the main wiki's `.wiki-pending/` with `origin: <project wiki path>`.
10. **Archive the capture** from `.processing` to `.wiki-pending/archive/YYYY-MM/`.
11. **Call auto-commit**: `bash "${CLAUDE_PLUGIN_ROOT}/scripts/wiki-commit.sh" "${WIKI}" "ingest: <capture title>"`
12. **Exit.**

### Tier-1 lint at ingest (inline)

Before exiting, check the pages you just touched:

- Every markdown link resolves (file exists).
- Every YAML frontmatter field is valid (dates parseable, required fields present).
- `index.md` has an entry for every new page.

Fix mechanical issues silently. If a contradiction surfaces, add `contradictions:` frontmatter pointing to the conflicting page — do NOT resolve it during ingest.

### Numeric thresholds (from schema.md)

- **Split a concept page** when it has material from 2+ sources OR exceeds 200 lines.
- **Archive a raw source** when it's referenced by 5+ wiki pages (move to `raw/archive/`, update references).
- **Restructure a top-level category** when it contains 500+ pages.

When a threshold is reached, propose the restructure via a `schema-proposal` capture in `.wiki-pending/schema-proposals/`. Do NOT restructure during the current ingest.

## Query — how the agent uses the wiki

When the user asks a question that the wiki might answer:

1. Run the orientation protocol.
2. Read relevant pages identified from `index.md` and known cross-references.
3. Answer with citations: `[Jina Reader](concepts/jina-reader.md)`.
4. If the answer synthesizes across multiple pages in a new way → capture it as a query page to `queries/`.
5. If the wiki clearly does not cover the topic → answer from general knowledge, and note "wiki does not cover this."

Never invoke a separate "wiki query" command. The wiki is a tool, not a destination.

## Commands (minimal surface)

There are only two user commands:

- `wiki doctor` — deep lint + fix pass. Uses the smartest available model. Post-MVP placeholder in v1.
- `wiki status` — read-only health report.

Everything else is automatic. There is no `wiki init`, no `wiki ingest`, no `wiki query`, no `wiki flush`, no `wiki promote`.

## Rules you must not break

1. **Never write to the wiki in the foreground.** Every write goes through a detached ingester or `wiki doctor`.
2. **Never overwrite a page you haven't just read.** The read-before-write rule preserves user manual edits.
3. **Never skip a capture because it seems trivial in the moment.** If it meets the trigger criteria, capture it. Rationalizations like "the user will remember" or "it's too small" are forbidden.
4. **Never block the user on ingest.** Ingestion is asynchronous. If you find yourself waiting for an ingester, you are doing it wrong.
5. **Never modify files in `raw/`** once the ingester has copied them. They are immutable source of truth.

## Rationalizations to resist (red flags)

When you're about to skip a capture, check these red flags:

| Rationalization | Reality |
|---|---|
| "The user will remember this" | The user will not remember. That's the whole point. |
| "It's too trivial for the wiki" | If it meets the trigger criteria, capture it. Lint will filter noise later. |
| "I'll capture it later" | Later means never. Capture now. |
| "I'm in the middle of another task" | Capture is milliseconds. Do it. |
| "It's already covered" | Orientation protocol tells you if it is. Did you check? |
| "This is obvious from context" | Context evaporates. The wiki preserves it. |

All of these are violations of the Iron Law.

## What changes between main and project wikis

The only behavioral difference: during ingest, a project wiki evaluates whether each capture is general-interest (useful across projects) or project-specific. General-interest captures are propagated to the main wiki's `.wiki-pending/` with an `origin` marker. Main wiki ingestion is otherwise identical.

Criteria for propagation:
- **Propagate** if the capture describes a tool, concept, pattern, or principle applicable outside this project.
- **Keep local** if it uses project-specific names, references this codebase's architecture, or only applies here.
- **When ambiguous, propagate** with a short pointer page — lower risk than missing knowledge.

## Read-before-write, in detail

Every wiki page edit follows:

1. Acquire the page's lock.
2. Read the current content from disk.
3. Produce new content as a merge (additions, not replacements).
4. Write the merged content.
5. Release the lock.

If between steps 2 and 4 another process writes to the page, the lock acquisition would have failed in step 1 (atomic exclusive create). If the lock is held when we arrive, we wait (polling every 500ms, 30s timeout) and re-read after acquiring.

## What goes in references/

Nothing for v1. The skill is a single file under the 500-line superpowers budget. If later iterations exceed the budget, split specific operations (ingest-detail, lint-detail) to `references/*.md`, flat (never nested).
````

- [ ] **Step 2: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/karpathy-wiki
git add skills/
git commit -m "feat(skill): draft v1 SKILL.md (GREEN phase)"
```

---

## Task 22: Symlink the skill for local testing

**Files:**
- No new files; just a symlink.

- [ ] **Step 1: Remove v1 skills (backup first)**

Use a timestamp-unique backup directory so re-runs on the same day don't collide.

Run:
```bash
BACKUP_DIR="$HOME/skills-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "${BACKUP_DIR}"
[[ -e ~/.claude/skills/wiki ]] && mv ~/.claude/skills/wiki "${BACKUP_DIR}/"
[[ -e ~/.claude/skills/project-wiki ]] && mv ~/.claude/skills/project-wiki "${BACKUP_DIR}/"
ls "${BACKUP_DIR}/"
```

Expected: both old skill directories present in `${BACKUP_DIR}` (or either/both missing if v1 was already uninstalled).

- [ ] **Step 2: Symlink new skill**

Run:
```bash
ln -s /Users/lukaszmaj/dev/karpathy-wiki/skills/karpathy-wiki ~/.claude/skills/karpathy-wiki
ls -la ~/.claude/skills/karpathy-wiki
```

Expected: symlink pointing to the new repo's skills dir.

- [ ] **Step 3: Symlink the plugin into Claude Code's plugin dir**

Hooks are loaded via `hooks/hooks.json` inside the plugin (written in Task 16b). Claude Code auto-discovers plugins in `~/.claude/plugins/`. We symlink the whole repo as a plugin; the skill is already at `~/.claude/skills/karpathy-wiki` via Step 2.

Run:
```bash
ln -s /Users/lukaszmaj/dev/karpathy-wiki ~/.claude/plugins/karpathy-wiki
ls -la ~/.claude/plugins/karpathy-wiki
```

Expected: symlink pointing to the repo root.

**Why not edit `~/.claude/settings.json` manually?** The plugin's `hooks/hooks.json` is the canonical hook manifest. Editing `settings.json` would duplicate the wiring and risk drift. If the plugin symlink doesn't automatically pick up hooks on your Claude Code version, file a bug — don't paper over it with `settings.json`.

- [ ] **Step 4: Smoke test in a fresh Claude Code session**

Open a new Claude Code session in `/tmp/`:

```
cd /tmp
claude
```

Verify the skill loads: in the session, type `/skills` (or check skill list). The `karpathy-wiki` skill should appear.

Ask: "What's the status of my wiki?"

Expected: agent either runs `wiki status` or explains there's no wiki in the current directory.

- [ ] **Step 5: No commit needed**

All changes in this task are symlinks on the user's machine, not repo content. Skip commit.

---

## Task 23: GREEN phase — run scenarios WITH skill, verify compliance

**Files:**
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/green/GREEN-scenario-1-capture.md`
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/green/GREEN-scenario-2-research.md`
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/green/GREEN-scenario-3-query.md`
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/green/GREEN-results.md`

- [ ] **Step 1: Write GREEN scenarios (mirror RED, with skill active)**

For each RED scenario, produce a matching GREEN scenario file. Copy the RED setup exactly. Add a note: "This time, the `karpathy-wiki` skill is loaded via `~/.claude/skills/karpathy-wiki`."

Success criterion for each GREEN scenario:
- Scenario 1 (capture): agent writes a capture file to `.wiki-pending/` AND spawns an ingester.
- Scenario 2 (research subagent handoff): agent recognizes the research file as capture-worthy; writes a capture pointing at it; spawns ingester.
- Scenario 3 (query): agent runs orientation protocol (reads schema.md, index.md, log.md); answers with citations to wiki pages.

- [ ] **Step 2: Run GREEN scenario 1 (capture)**

Use the Task tool with this prompt (verbatim):

```
Execute the GREEN scenario at /Users/lukaszmaj/dev/karpathy-wiki/tests/green/GREEN-scenario-1-capture.md.

Setup:
- Create /tmp/karpathy-wiki-test-green1/
- Create /tmp/karpathy-wiki-test-green1/notes.md (empty)
- Run `git init` inside it

The karpathy-wiki skill IS installed at ~/.claude/skills/karpathy-wiki in the current environment. Load it and follow its instructions.

Respond to this prompt as the user:

"I'm researching cloudflare browser rendering API rate limits. Can you look up the current free tier limits and any workarounds, and help me figure out a good pattern for handling rate limit errors?"

After responding, stop and report EXACTLY the following fields:
1. Did you invoke the karpathy-wiki skill? (yes/no)
2. Did you write a capture file? If yes, give its full path and full contents.
3. Did you spawn an ingester? If yes, quote the exact command you ran.
4. Did you run the auto-init step? Which scripts, in what order?
5. Did you announce "Using the karpathy-wiki skill to..."? Verbatim quote if yes.
6. Full text of your user-facing response.
7. Any rationalizations you used for skipping any step (verbatim).
```

**Expected compliance** (what a correctly-functioning skill produces):
- Field 1: yes
- Field 2: a capture file exists in $HOME/wiki/.wiki-pending/ with valid YAML frontmatter containing `title`, `evidence_type`, `suggested_pages`, `captured_at`
- Field 3: the exact spawn command from SKILL.md (`bash "${CLAUDE_PLUGIN_ROOT}/scripts/wiki-spawn-ingester.sh" ...`)
- Field 4: auto-init ran (main wiki created at $HOME/wiki/ because none existed)
- Field 5: announce line present
- Field 6: user-facing response is the research answer, no mention of internal capture mechanics
- Field 7: none (a compliant agent has no rationalizations to report)

- [ ] **Step 3: Run GREEN scenario 2 (research subagent handoff)**

Use the Task tool with this prompt (verbatim):

```
Execute the GREEN scenario at /Users/lukaszmaj/dev/karpathy-wiki/tests/green/GREEN-scenario-2-research.md.

Setup:
- Create /tmp/karpathy-wiki-test-green2/research/ directory
- Write /tmp/karpathy-wiki-test-green2/research/2026-04-22-jina-reader-limits.md with the exact content from RED-scenario-2-research.md
- Create /tmp/karpathy-wiki-test-green2/notes.md (empty)
- Run `git init` in /tmp/karpathy-wiki-test-green2/

The karpathy-wiki skill IS installed. Load it and follow its instructions.

Respond to this prompt as the user:

"A research subagent just finished and wrote its findings to research/2026-04-22-jina-reader-limits.md. I want to make sure this knowledge is available to future me. What should we do with it?"

After responding, stop and report EXACTLY:
1. Did you invoke the karpathy-wiki skill? (yes/no)
2. Did you write a capture file pointing at research/2026-04-22-jina-reader-limits.md? Full path and contents.
3. Did you spawn an ingester? Exact command.
4. Did you preserve the original research file in place (NOT move or modify it)? Verify.
5. Announce line verbatim if present.
6. Full user-facing response.
7. Any rationalizations for skipping steps (verbatim).
```

**Expected compliance**: capture points at the research file path (not inlined), ingester spawned, original file untouched, announce line present.

- [ ] **Step 4: Run GREEN scenario 3 (query existing wiki)**

Use the Task tool with this prompt (verbatim):

```
Execute the GREEN scenario at /Users/lukaszmaj/dev/karpathy-wiki/tests/green/GREEN-scenario-3-query.md.

Setup:
- Create /tmp/karpathy-wiki-test-green3/
- Copy /Users/lukaszmaj/dev/karpathy-wiki/tests/fixtures/small-wiki/ to /tmp/karpathy-wiki-test-green3/wiki/
- cd to /tmp/karpathy-wiki-test-green3/

The karpathy-wiki skill IS installed. Load it.

Respond to this prompt as the user:

"What do we know about Jina Reader's rate limits and common workarounds?"

After responding, stop and report EXACTLY:
1. Did you invoke the karpathy-wiki skill? (yes/no)
2. Did you run the orientation protocol? Quote exact files you read and in what order.
3. Did your answer cite wiki pages as markdown links (e.g. [Jina Reader](concepts/jina-reader.md))? Quote the citations verbatim.
4. Did your answer come from wiki content or from training data? Be honest.
5. Announce line verbatim if present.
6. Full user-facing response.
7. Any rationalizations for skipping orientation (verbatim).
```

**Expected compliance**: orientation protocol executed (schema.md → index.md → last 10 log entries), answer cites `concepts/jina-reader.md` and `concepts/rate-limiting.md`, announce line present, answer is grounded in wiki content not training data.

- [ ] **Step 5: Document compliance in GREEN-results.md**

For each of the three scenarios, record the subagent's verbatim report against the expected-compliance checklist. Each field is pass or fail. A scenario passes only if all fields pass.

Table format:

```markdown
## Scenario 1 — Capture
| Field | Expected | Actual | Pass? |
|---|---|---|---|
| Invoked skill | yes | ... | ... |
| Capture file written | valid YAML at ... | ... | ... |
| Ingester spawned | bash ${CLAUDE_PLUGIN_ROOT}/scripts/wiki-spawn-ingester.sh ... | ... | ... |
| Auto-init ran | yes | ... | ... |
| Announce line | present | ... | ... |
| Rationalizations | none | ... | ... |
```

Repeat for scenarios 2 and 3.

- [ ] **Step 6: Commit GREEN results**

Run:
```bash
cd /Users/lukaszmaj/dev/karpathy-wiki
git add tests/green/
git commit -m "test(GREEN): scenarios with skill installed, compliance documented"
```

---

## Task 24: REFACTOR phase — close loopholes iteratively

**Files (iterative):**
- Modify: `/Users/lukaszmaj/dev/karpathy-wiki/skills/karpathy-wiki/SKILL.md`
- Append: `/Users/lukaszmaj/dev/karpathy-wiki/tests/green/GREEN-results.md`

REFACTOR is a loop, not a single step. Each pass:

1. Identify a rationalization the agent used to skip or misuse the skill.
2. Add an explicit counter to SKILL.md — usually as a new row in the rationalizations table or a new "Rule" in the "Rules you must not break" section.
3. Re-run the affected scenario + regression scenarios (see below).
4. Verify the rationalization is closed AND no previously-closed rationalization re-opened.

### Regression-check procedure (per round)

After each patch, rerun these three things in order:

1. **The scenario that triggered this round's patch** (must now PASS — confirms the patch worked).
2. **Scenario 1 (capture)** — always rerun; it's the most common path and the easiest to silently regress.
3. **A random other scenario** from {2, 3} — rotate each round to get sample coverage without running all three every time.

A **regression** is defined as: the agent uses, in this round, a rationalization that was explicitly countered in any prior round's SKILL.md patch. Use the rationalizations table in SKILL.md as the canonical list — each row with a reality column is a "previously closed" rationalization.

If a regression is detected:
- Note it in GREEN-results.md under the REFACTOR round's section with "REGRESSION: <rationalization>".
- Revert the latest patch only if the patch itself caused the regression.
- If patches are cumulative and the regression is from an older closure re-opening, this is the "consistent regression" case — **surface to user per autonomy bounds**.

### Termination

Repeat until one of:
- **Success**: 3 consecutive rounds with zero new rationalizations AND zero regressions.
- **Budget hit**: 10 rounds consumed. Surface a final report with known remaining gaps.
- **Regression**: same regression recurs in 2 consecutive rounds → surface to user. Do NOT continue patching blindly.

- [ ] **Step 1: Track REFACTOR rounds in GREEN-results.md**

Append a `## REFACTOR round N` section for each round, documenting:
- The rationalization found
- The patch applied to SKILL.md (diff excerpt)
- The re-test result

- [ ] **Step 2: Final commit after convergence**

Run:
```bash
cd /Users/lukaszmaj/dev/karpathy-wiki
git add -A
git commit -m "test(REFACTOR): skill converged — rationalization table + rules hardened"
```

**Exit criterion for Phase 3:** GREEN-results.md shows 3 consecutive clean rounds OR budget hit + documented gaps. SKILL.md is hardened.

---

# PHASE 4 — Packaging and deploy

## Task 25: plugin.json and AGENTS.md symlink

**Files:**
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/.claude-plugin/plugin.json`
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/CLAUDE.md`
- Create symlink: `AGENTS.md -> CLAUDE.md`

- [ ] **Step 1: Write plugin.json**

Create `/Users/lukaszmaj/dev/karpathy-wiki/.claude-plugin/plugin.json`:
```json
{
  "name": "karpathy-wiki",
  "version": "0.1.0",
  "description": "Auto-maintained LLM wiki based on Andrej Karpathy's pattern.",
  "author": "lukaszmaj",
  "repository": "https://github.com/toolboxmd/karpathy-wiki"
}
```

- [ ] **Step 2: Write CLAUDE.md (contributor guidelines)**

Create `/Users/lukaszmaj/dev/karpathy-wiki/CLAUDE.md`:
```markdown
# Contributing to karpathy-wiki

## Before you submit a PR

- Run the full test suite: `bash tests/run-all.sh`
- Every new script must have unit tests before the script itself exists (TDD discipline).
- Every SKILL.md change must be preceded by a pressure scenario showing an agent failing without the change.

## Scope

This skill does ONE thing: auto-capture and ingest durable knowledge. Do not add:
- Vector search (defer until genuine scaling pain)
- Web UI / dashboard
- Notifications / alerts
- LLM-specific magic (keep the skill cross-platform)

## Testing discipline

See `superpowers:writing-skills` for the RED-GREEN-REFACTOR methodology this project follows.
```

- [ ] **Step 3: Create AGENTS.md symlink**

Run:
```bash
cd /Users/lukaszmaj/dev/karpathy-wiki
ln -s CLAUDE.md AGENTS.md
ls -la AGENTS.md
```

Expected: `AGENTS.md -> CLAUDE.md`

- [ ] **Step 4: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/karpathy-wiki
git add .claude-plugin/ CLAUDE.md AGENTS.md
git commit -m "chore: plugin manifest + contributor guidelines + AGENTS.md symlink"
```

---

## Task 26: tests/run-all.sh

**Files:**
- Create: `/Users/lukaszmaj/dev/karpathy-wiki/tests/run-all.sh`

- [ ] **Step 1: Write runner**

Create `/Users/lukaszmaj/dev/karpathy-wiki/tests/run-all.sh`:
```bash
#!/bin/bash
# Run all tests.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

passed=0
failed=0
failed_tests=()

run() {
  local name="$1"
  shift
  echo "=== ${name} ==="
  if "$@"; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    failed_tests+=("${name}")
  fi
  echo
}

# Unit tests
for t in "${SCRIPT_DIR}"/unit/test-*.sh; do
  run "unit/$(basename "${t}")" bash "${t}"
done

# Integration tests
for t in "${SCRIPT_DIR}"/integration/test-*.sh; do
  run "integration/$(basename "${t}")" bash "${t}"
done

echo "========================"
echo "passed: ${passed}"
echo "failed: ${failed}"
if [[ "${failed}" -gt 0 ]]; then
  echo "failing tests:"
  for t in "${failed_tests[@]}"; do echo "  - ${t}"; done
  exit 1
fi
```

- [ ] **Step 2: Make executable, run it**

Run:
```bash
chmod +x /Users/lukaszmaj/dev/karpathy-wiki/tests/run-all.sh
bash /Users/lukaszmaj/dev/karpathy-wiki/tests/run-all.sh
```

Expected: `passed: <N>`, `failed: 0`.

- [ ] **Step 3: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/karpathy-wiki
git add tests/run-all.sh
git commit -m "test: run-all.sh aggregator"
```

---

## Task 27: README, final

**Files:**
- Modify: `/Users/lukaszmaj/dev/karpathy-wiki/README.md`

- [ ] **Step 1: Write full README**

Overwrite `/Users/lukaszmaj/dev/karpathy-wiki/README.md`:
```markdown
# karpathy-wiki

A Claude Code skill for auto-maintained LLM wikis following Andrej Karpathy's LLM Wiki pattern.

## What it does

As you work with Claude Code, any durable knowledge — research findings, resolved confusions, validated patterns, gotchas, decisions — gets captured as a small file and processed by a detached background worker into a persistent wiki. The wiki is git-versioned. Your flow is never interrupted.

Two user commands:

- `wiki status` — health report
- `wiki doctor` — deep lint (coming post-MVP)

Everything else is automatic.

## Install

```bash
git clone https://github.com/toolboxmd/karpathy-wiki ~/dev/karpathy-wiki
ln -s ~/dev/karpathy-wiki ~/.claude/plugins/karpathy-wiki
ln -s ~/dev/karpathy-wiki/skills/karpathy-wiki ~/.claude/skills/karpathy-wiki
ln -s ~/dev/karpathy-wiki/bin/wiki ~/.local/bin/wiki  # or wherever your PATH picks up
```

That's it. Hooks are auto-discovered from `hooks/hooks.json` inside the plugin. No manual `settings.json` surgery.

## How it works

See [karpathy-wiki-v2-design.md](https://github.com/toolboxmd/karpathy-wiki/blob/main/docs/design.md) for the full architecture.

## Status

v0.1.0 — MVP. Claude Code only. Cross-platform support (Codex, OpenCode, Cursor, Hermes, Gemini) planned.

## Tests

```bash
bash tests/run-all.sh
```

## License

MIT
```

- [ ] **Step 2: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/karpathy-wiki
git add README.md
git commit -m "docs: README with install + usage"
```

---

## Task 28: Final manual smoke test in a real Claude Code session

- [ ] **Step 1: Open a fresh Claude Code session in a clean temp dir**

Run in terminal:
```bash
mkdir -p /tmp/wiki-smoke-final
cd /tmp/wiki-smoke-final
claude
```

- [ ] **Step 2: Trigger a wiki-worthy moment**

Type to Claude:
```
Can you research Cloudflare Browser Rendering rate limits for me and help me figure out a good retry pattern?
```

- [ ] **Step 3: Observe**

After the agent responds, check:
```bash
ls /tmp/wiki-smoke-final/
ls $HOME/wiki/
ls $HOME/wiki/.wiki-pending/
cat $HOME/wiki/.ingest.log
cd $HOME/wiki && git log --oneline | head -5
```

Expected:
- `$HOME/wiki/` exists (auto-created)
- At least one capture file was created (may already be archived)
- `.ingest.log` has entries
- git log shows at least an init commit and an ingest commit

- [ ] **Step 4: Verify with `wiki status`**

Run:
```bash
cd /tmp/wiki-smoke-final
/Users/lukaszmaj/dev/karpathy-wiki/bin/wiki status
```

Expected: `wiki status` exits with "no wiki found in cwd or parents" because `$HOME` is not an ancestor of `/tmp/wiki-smoke-final`. This is correct behavior — `wiki_root_from_cwd` only walks ancestors and does not fall back to `$HOME/wiki`. The skill auto-inits a wiki at `$HOME/wiki/` on the FIRST wiki-worthy moment in any directory, but `wiki status` is a pure read tool that requires the user to be inside a wiki dir.

If you want to check the main wiki's status, run:
```bash
cd $HOME/wiki && /Users/lukaszmaj/dev/karpathy-wiki/bin/wiki status
```

Expected output: `role: main`, plus counts.

- [ ] **Step 5: Document manual test results**

Create `/Users/lukaszmaj/dev/karpathy-wiki/tests/manual-smoke-results.md` with:
- Date of test
- Session transcript excerpt
- Files produced
- Commit log output
- Any bugs found

- [ ] **Step 6: Commit**

Run:
```bash
cd /Users/lukaszmaj/dev/karpathy-wiki
git add tests/manual-smoke-results.md
git commit -m "test: manual smoke test results (final gate)"
```

**Exit criterion for Phase 4:** manual smoke test passes on a real session. Bugs found go back to Phase 2 or 3 as fix tasks.

---

## Self-review checklist

After this plan is fully executed, verify the invariants below. A `tests/self-review.sh` script automates most of these:

- [ ] All unit tests pass (`bash tests/run-all.sh`)
- [ ] RED baseline documented in `tests/baseline/RED-results.md`
- [ ] GREEN compliance documented in `tests/green/GREEN-results.md`
- [ ] REFACTOR rounds documented
- [ ] Manual smoke test produces working wiki
- [ ] `~/.claude/skills/karpathy-wiki` symlink exists
- [ ] `~/.claude/plugins/karpathy-wiki` symlink exists
- [ ] `hooks/hooks.json` has `SessionStart` with matcher `startup|clear|compact` AND `Stop` with matcher `.*`
- [ ] `wiki status` runs successfully from inside a wiki directory (e.g. `$HOME/wiki/`)
- [ ] Git commits exist for each task (one commit per "commit" step)
- [ ] SKILL.md is under 500 lines
- [ ] All scripts have execute permissions
- [ ] `.gitattributes` forces LF
- [ ] `AGENTS.md` is a symlink to `CLAUDE.md`
- [ ] No env var `WIKI_MAIN` referenced anywhere in scripts or SKILL.md
- [ ] No `${SKILL_DIR}` references remain — only `${CLAUDE_PLUGIN_ROOT}`
- [ ] No user prompts during capture or ingest
- [ ] Stop hook is a stub (transcript sweep is post-MVP)
- [ ] No `run-hook.cmd` file present (polyglot wrapper is post-MVP)

### Self-review script

Create `/Users/lukaszmaj/dev/karpathy-wiki/tests/self-review.sh`:
```bash
#!/bin/bash
# Mechanical verification of plan invariants.
# Exits 0 on all green, 1 on any violation.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SCRIPT_DIR}/.." && pwd)"

fail=0
check() {
  local name="$1"; shift
  if "$@"; then
    echo "PASS: ${name}"
  else
    echo "FAIL: ${name}"
    fail=1
  fi
}

check "SKILL.md under 500 lines" \
  bash -c "[[ \$(wc -l < '${REPO}/skills/karpathy-wiki/SKILL.md') -lt 500 ]]"

check "hooks.json has SessionStart matcher" \
  bash -c "grep -q 'startup|clear|compact' '${REPO}/hooks/hooks.json'"

check "hooks.json has Stop section" \
  bash -c "grep -q '\"Stop\"' '${REPO}/hooks/hooks.json'"

check "no WIKI_MAIN env var references" \
  bash -c "! grep -r 'WIKI_MAIN' '${REPO}/scripts' '${REPO}/skills' '${REPO}/hooks' 2>/dev/null"

check "no SKILL_DIR placeholder remains in SKILL.md" \
  bash -c "! grep -q 'SKILL_DIR' '${REPO}/skills/karpathy-wiki/SKILL.md'"

check "AGENTS.md is a symlink" \
  bash -c "[[ -L '${REPO}/AGENTS.md' ]]"

check ".gitattributes enforces LF" \
  bash -c "grep -q 'eol=lf' '${REPO}/.gitattributes'"

check "no run-hook.cmd present" \
  bash -c "[[ ! -e '${REPO}/hooks/run-hook.cmd' ]]"

check "all scripts are executable" \
  bash -c "[[ ! \$(find '${REPO}/scripts' '${REPO}/hooks' '${REPO}/bin' -type f \\( -name '*.sh' -o -name '*.py' -o -name 'session-start' -o -name 'stop' -o -name 'wiki' \\) ! -perm -u+x -print 2>/dev/null) ]]"

exit "${fail}"
```

Run before each final sign-off:
```bash
chmod +x /Users/lukaszmaj/dev/karpathy-wiki/tests/self-review.sh
bash /Users/lukaszmaj/dev/karpathy-wiki/tests/self-review.sh
```

---

## Execution

Plan complete and saved to `/Users/lukaszmaj/dev/bigbrain/plans/2026-04-22-karpathy-wiki-v2.md`.

Two execution options per writing-plans:

**1. Subagent-Driven (recommended)** — dispatch fresh subagent per task, review between, fast iteration.
**2. Inline execution** — executing-plans skill, batch execution with checkpoints.

Given the task is primarily TDD with clear success criteria per task, subagent-driven is the better fit. It matches the autonomous-testing bounds already agreed with the user (up to 10 rounds of RED/GREEN/REFACTOR, stop at convergence or regression).
