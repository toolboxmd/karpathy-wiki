# Karpathy Wiki v2 — Design Document

**Status:** Design, not yet implemented
**Date:** 2026-04-22
**Supersedes:** the existing `~/.claude/skills/{wiki,project-wiki}` skills (built 2026-04-04)
**Companion docs:**
- `/Users/lukaszmaj/dev/bigbrain/research/karpathy_wiki_ecosystem.md` — research on what the community built on top of Karpathy's original pattern
- `/Users/lukaszmaj/.claude/skills/wiki/SKILL.md` — current (v1) skill, to be refactored into v2
- `/Users/lukaszmaj/.claude/skills/project-wiki/SKILL.md` — current (v1) project variant, to be merged into v2

This document captures everything we discussed so the design can be recreated even if this session is lost.

---

## Part 1 — The idea, in plain terms

### What we're building

A skill that keeps a living knowledge base up to date automatically. The user works normally — code, research, conversation — and anything worth remembering gets captured and added to a wiki in the background. No commands to remember. No ceremony. It just works.

### Why we're building it

Right now, knowledge is scattered. Research files live in `bigbrain/`, `/dev/research/`, and various project folders. Insights from conversations vanish when the session ends. Next week you re-learn the same thing. Next month you can't find what you already know.

A wiki solves this, but only if it stays current without effort. If updating the wiki is a manual task, it won't happen. Karpathy's original pattern assumed the user would drop files into a `raw/` folder and trigger ingestion — that works for deliberate research but misses the insights that emerge during normal work.

This skill closes that gap by making capture automatic.

### How it works, at a glance

- There is one **main wiki** at `~/wiki/`. It's broad-scoped: research, ideas, practices, code snippets, concepts, entities.
- Every project can have its own **project wiki** at `<project>/wiki/`. It's narrow-scoped to that project.
- The main wiki and project wikis are the same kind of thing with different scopes. They both ingest, query, lint. They link to each other.
- As you work, the agent notices wiki-worthy moments and writes small capture notes. Each note triggers an immediate background ingester that writes the actual wiki pages. This happens while you continue working, never blocks you.
- You ask questions naturally. The LLM figures out to check the wiki.
- Two user commands exist: `wiki doctor` (deep cleanup) and `wiki status` (health check). Everything else is automatic.
- The wiki is git-backed, visible in the project, Obsidian-compatible, and made of plain markdown files you can read in any editor.

### Core design decisions, and why each one

**One main wiki plus project wikis with bidirectional linking**
Some knowledge is project-specific (how this codebase handles auth). Some is universal (how JWT works). Separating scopes lets each wiki stay coherent; linking them lets context flow naturally between them.

**Capture and ingest are separate steps**
Capture is cheap (write a small file). Ingest is expensive (synthesize pages). Separating them means capture never slows the user down, and ingest can happen at its own pace.

**Ingest happens immediately in the background, not at next session start**
If the user has a long session and never reopens it, "next session" never comes. Captures must be ingested while the main session is still running, just not on its thread.

**The background ingester prefers cheap models and escalates when needed**
Most ingestion work is mechanical. Using a smart model for all of it is wasteful. When the ingester finds ambiguity or contradiction, it escalates to a smarter model or the user.

**Captures are markdown files in a visible folder**
Not JSONL, not a database. If anything goes wrong the user can read, edit, or delete captures directly.

**Regular markdown links, not Obsidian `[[wikilinks]]`**
LLMs, GitHub, and most tools handle full-path links better than wikilink syntax. Obsidian works fine with regular links too.

**Git-backed from day one**
Syncs across devices, gives full history, guards against loss.

**Always-on Obsidian compatibility, no detection**
Cost nothing, solves a real compatibility problem if the user later installs Obsidian. No branching logic.

**Wiki pages are not hash-tracked**
The ingester always reads a page before editing it, so manual user edits are preserved naturally. Tracking hashes on wiki pages solves a problem that doesn't exist.

**Raw source files ARE hash-tracked**
When a source file changes, we want to re-synthesize pages based on it. Hash drift on `raw/` triggers a re-ingest.

**Zero-setup install**
The first time anything triggers the skill, the wiki is created with sensible defaults. Nothing to configure.

**Two user commands total: `wiki doctor` and `wiki status`**
Everything else is automatic or natural language. Smaller surface = less to remember and maintain.

### What we deliberately don't build

- **Nightly lint cron job** — opinionated, needs setup, unnecessary if ingest is immediate.
- **Hot.md session-continuity cache** — valuable idea but unrelated to the wiki. Belongs in a separate memory/continuity skill if built at all.
- **Vector search or embeddings** — premature until the wiki is very large.
- **A dedicated UI** — plain markdown in any editor is the UI.
- **Project-vs-knowledge mode detection** — the wiki works the same regardless of whether a project has source code. No branching needed.
- **`wiki ingest`, `wiki query`, `wiki flush`, `wiki init`, `wiki promote` commands** — all replaced by natural language or automatic behavior.

### Known risks and how we handle them

**Error baking**: if the ingester misreads a source once, the error propagates across 10+ pages because future queries read the synthesis, not the source. We mitigate by keeping inline source-back-links for every claim, archiving the original source so we can re-ingest, and having the doctor verify sampled claims against sources.

**Scaling past 200 pages**: the index file becomes too large for an LLM to read in one pass. We handle this automatically — when the index exceeds a size threshold, lint splits it into per-category subindexes. The user doesn't think about it.

**Concurrent ingesters conflicting**: two background ingesters might try to edit the same page. We use a lockfile — one ingester holds the lock, others wait and re-read once released. Stale locks (ingester died) are reclaimed after a timeout.

**Cross-platform compatibility**: not every agentic CLI supports headless mode. Where it's available (Claude Code's `claude -p`, Codex's `codex exec`, OpenCode's `opencode run`, etc.) we use it. Where it isn't, the skill falls back to a parallel subagent in the same session — still non-blocking for the user.

---

## Part 2 — Technical details, in depth

### Wiki roles and topology

There are exactly two roles a wiki can have:

- **Main** — the top-level knowledge wiki. Lives at `~/wiki/` by default. One per user per machine. Identified by `.wiki-config` containing `{ role: "main" }`.
- **Project** — a wiki scoped to a single project. Lives at `<project-root>/wiki/`. Identified by `.wiki-config` containing `{ role: "project", main: "/absolute/path/to/main" }`.

Both roles run the same operations (ingest, query, lint, doctor). They differ only in:
- Scope of captures (project wikis capture project-specific knowledge; main wiki captures everything)
- Propagation direction (project wikis can propagate general-interest captures upward to main)

The location of the main wiki is recorded in:
- `$WIKI_MAIN` environment variable (if set by user — optional override)
- `~/.wiki-config` (written by the skill at first init — the default source of truth)
- Each project wiki's own `.wiki-config` file, which records where its main wiki is

Any disagreement between these is resolved in favor of `$WIKI_MAIN` when explicitly set; otherwise `~/.wiki-config`.

### Auto-init (no user ceremony)

The skill has no `wiki init` command. The first invocation that needs a wiki creates one:

1. Skill triggers (any operation — capture, ingest, query via natural language, hook firing).
2. Skill looks for a wiki:
   - Is there a `wiki/` directory in the current working directory with a `.wiki-config`? Use it.
   - Is there a `wiki/` directory without `.wiki-config`? Adopt it — write `.wiki-config` based on whether it's at the `$WIKI_MAIN` path.
   - No `wiki/` in cwd? Check if main wiki exists at `$WIKI_MAIN` or `~/wiki/`.
     - If so and cwd is inside a project (has a `.git` or similar), silently create a project wiki at `./wiki/`.
     - If not, create the main wiki at `~/wiki/` and continue.
3. Every auto-created wiki gets: `index.md`, `log.md`, `schema.md`, `raw/`, `.wiki-config`, `.wiki-pending/`, `.manifest.json`, `.gitignore`, `.obsidian/app.json` (ignored-folders config), and `git init` runs.
4. Skill logs the action. One-line notification to the user. No prompts. No choices.

The only exposed knob is `$WIKI_MAIN` for power users who want their main wiki somewhere other than `~/wiki/`.

### Directory layout

```
~/wiki/                                  ← main wiki, user's home knowledge base
├── index.md                             visible, committed, top-level catalog
├── log.md                               visible, committed, operation log
├── schema.md                            visible, committed, current structure
├── concepts/                            visible, committed
├── entities/                            visible, committed
├── sources/                             visible, committed, per-source summary pages
├── queries/                             visible, committed, filed Q&A
├── ideas/                               visible, committed (user's taxonomy may vary)
├── practices/                           visible, committed
├── snippets/                            visible, committed
├── raw/                                 visible, committed (or gitignored — user choice)
├── .wiki-config                         hidden, committed
├── .manifest.json                       hidden, committed (raw/ hash manifest)
├── .wiki-pending/                       hidden, committed (capture queue)
├── .locks/                              hidden, gitignored (per-machine)
├── .ingest.log                          hidden, gitignored (per-machine)
├── .obsidian/                           hidden, committed (ignored-folders config)
└── .gitignore                           hidden, committed

<project-root>/wiki/                     ← project wiki, identical structure
```

Top-level categories in the wiki (`concepts/`, `entities/`, etc.) are not hardcoded. They live in `schema.md` and evolve with the user. The ingester reads `schema.md` before writing to know where pages go.

### `.wiki-config` format

Per-wiki configuration file. Minimal. Example for main wiki:

```json
{
  "role": "main",
  "created": "2026-04-22",
  "agent_cli": "claude",
  "headless_command": "claude -p",
  "auto_commit": true
}
```

Example for project wiki:

```json
{
  "role": "project",
  "main": "/Users/lukaszmaj/wiki",
  "created": "2026-04-22",
  "agent_cli": "claude",
  "headless_command": "claude -p",
  "auto_commit": true
}
```

`agent_cli` and `headless_command` are detected at init by checking env vars (`CLAUDE_CODE_*`, `CODEX_*`, etc.) and which CLIs are on `PATH`. Re-detected if detection appears wrong.

`~/.wiki-config` (at the home dir, not inside a wiki) records the location of the main wiki for this user:

```json
{
  "main_wiki_path": "/Users/lukaszmaj/wiki"
}
```

### Captures — what they are and how they flow

A **capture** is a small markdown file representing "something that might belong in the wiki." It lives at `<wiki>/.wiki-pending/<timestamp>-<slug>.md`.

Capture file format:

```markdown
---
title: "Jina Reader rate limits"
evidence: "/Users/lukaszmaj/dev/bigbrain/research/2026-04-22-jina-limits.md"
evidence_type: "file"          # file | conversation | mixed
suggested_action: "update"     # create | update | augment
suggested_pages:
  - concepts/jina-reader.md
  - concepts/rate-limiting.md
captured_at: "2026-04-22T14:30:00Z"
captured_by: "in-session-agent" # in-session-agent | stop-sweep | raw-watcher
origin: null                   # path to originating wiki if cross-propagated
---

Jina Reader free tier allows 20 req/min. Confirmed in error response.
Workaround: batch requests, use exponential backoff.
```

**When captures are created:**

1. **In-session agent** notices a wiki-worthy moment during a conversation. Writes capture.
2. **Research subagent returns a file** and the parent agent recognizes it should go in the wiki. Writes a capture pointing to the research file.
3. **Stop-hook transcript sweep** (if enabled) runs a cheap model over the session transcript at Stop to catch what the in-session agent missed. Writes any additional captures.
4. **Raw watcher** detects new files in `raw/` (dropped by user manually). Writes captures pointing to them.

**What counts as "wiki-worthy":**

The agent evaluates against this list, which goes in the SKILL.md description:

- Resolved confusion (we didn't know how X worked, now we do)
- A research finding with a definitive answer
- A pattern that repeats (snippet candidate)
- A gotcha or quirk in a tool
- A validated practice (tried A vs B, A won for these reasons)
- An architectural decision with context
- External knowledge that slots into an existing page
- A contradiction with existing wiki content (needs resolution)

What's NOT wiki-worthy:
- Routine file operations, syntax lookups, formatting
- One-off debugging for trivial causes
- Questions already well-covered in the wiki
- Temporary task state
- Personal preferences that aren't generalizable

### Ingesters — how captures become wiki pages

As soon as a capture is written, a background ingester is spawned to process it. The ingester is an independent agent subprocess.

**Spawn mechanism (in priority order):**

1. **Headless mode** on the current CLI (`$HEADLESS_COMMAND` from `.wiki-config`). Detached via `&`, `nohup`, or `setsid`. Runs as a separate process entirely. Does not share the user's session context.
2. **Fallback: parallel subagent** (platform's Task/Agent tool). Runs concurrently in the current session. Consumes the user's session context/credits but still doesn't block.

The skill never runs an ingester synchronously in the user's thread.

**Model selection**: the ingester's prompt specifies "use the cheapest model available for this agent CLI." Claude Code picks Haiku, Codex picks its cheapest tier, etc. If the ingester runs into ambiguity it escalates.

**The ingester's job (single capture):**

1. Atomically claim the capture by renaming it: `<file>.md` → `<file>.md.processing`. If rename fails (another ingester already claimed it), exit quietly.
2. Read the capture.
3. If `evidence_type == file`: copy the evidence file into `<wiki>/raw/` (do not move — leave the original intact). Compute hash, update `.manifest.json`.
4. If `evidence_type == conversation`: use the capture body as seed material; re-consult the current session transcript if more context is needed.
5. Read `schema.md` to know the current structure.
6. Read `suggested_pages` (and any other pages the evidence clearly touches).
7. For each touched page:
   - Acquire page-level lock (`<wiki>/.locks/<page-path-slugified>.lock`) via atomic create-exclusive.
   - If lock held by another ingester: poll every 500ms. On release, re-read the page (it may have changed) and re-acquire.
   - Edit the page in place (don't replace — read first, merge changes).
   - Release lock.
   - Append a line to `.ingest.log`.
8. Update `index.md` (also locked).
9. Append operation summary to `log.md`.
10. If this wiki is a project wiki and the capture is general-interest: write a new capture pointing at the newly-created pages into the main wiki's `.wiki-pending/`, with `origin` set to this project wiki's path.
11. Delete the `.processing` file.
12. If `auto_commit` is true: `git add <wiki>/ && git commit -m "ingest: <capture title>"`.
13. Exit.

**Recovery:**

- Orphaned `.processing` files (older than, say, 10 minutes with no `.ingest.log` activity) are reclaimed by the next ingester that runs. It renames them back to `.md` and retries.
- Stale `.lock` files (older than 5 minutes) are reclaimed the same way.

### Page-level locking

Simple file-based locking to prevent two ingesters from writing the same page concurrently.

- Lockfile location: `<wiki>/.locks/<slugified-page-path>.lock`
- Contents: `{ pid, started_at, capture_id }`
- Acquisition: `open(path, O_CREAT | O_EXCL)` — fails if exists. Atomic on all Unix filesystems.
- Release: delete the file.
- Wait-on-locked: poll every ~500ms. On release, re-read the page (state may have changed) and retry acquisition.
- Timeout: 30 seconds of waiting. On timeout, give up, mark the capture as needs-retry, exit. Next opportunity picks it up.
- Stale reclaim: if a lock is older than 5 minutes, next ingester overwrites it and proceeds.

### Logs

Two separate logs:

- **`<wiki>/log.md`** — user-facing operation log. High-level: "ingested X, created Y pages, updated Z." Committed to git. Append-only. Human-readable.
- **`<wiki>/.ingest.log`** — internal trace log. Every lock, unlock, read, write. Per-machine. Gitignored. For debugging.

### The manifest (raw-only hashing)

`<wiki>/.manifest.json` — committed to git — maps each file in `raw/` to its SHA-256 and last-ingested timestamp:

```json
{
  "raw/2026-04-22-jina-limits.md": {
    "sha256": "abc123...",
    "last_ingested": "2026-04-22T14:30:45Z"
  },
  "raw/2026-04-21-context7-research.md": {
    "sha256": "def456...",
    "last_ingested": "2026-04-21T10:00:00Z"
  }
}
```

Uses:
- Drift detection: if a file in `raw/` has a different hash than the manifest, it was updated. Spawn a capture of type "source-updated" and re-ingest.
- Completeness check: lint compares `raw/` against the manifest to find any source that was never ingested.

**No hashing of wiki pages themselves.** They change all the time (every ingest edits them), and the ingester always reads before writing, so user manual edits are naturally preserved.

### Hooks

Two hooks, both shell-only (no LLM in the hook itself):

**SessionStart hook:**
1. If wiki exists in cwd:
   - Run drift check: diff `raw/` against `.manifest.json`. Any new or modified sources? Write captures for them.
   - Check `.wiki-pending/`: any captures still there (leftover from prior sessions)? Spawn a drain ingester in headless mode to process them all.
   - Reclaim stale `.processing` files and `.lock` files if older than thresholds.
   - Exit.

**Stop hook:**
1. If wiki exists in cwd:
   - Quick drift check on `raw/`.
   - If any captures remain in `.wiki-pending/`: spawn final drain ingester.
   - (Optional, opt-in) Transcript sweep: spawn cheap-model subprocess to read session transcript and flag any wiki-worthy moments the in-session agent missed. Appends captures.
   - Exit.

Neither hook blocks the user. Both complete in under a second of shell work.

### Propagation (project wiki → main wiki)

Happens at ingest time, within the ingester:

1. Ingester processes a capture in the project wiki.
2. Ingester evaluates: is this capture general-interest (useful across projects) or project-specific?
3. If general-interest:
   - Write a new capture into the main wiki's `.wiki-pending/`.
   - Capture's `evidence_type: file`, `evidence: <path to the project wiki's just-written page>`, `origin: <project wiki path>`.
   - Main wiki's next ingester picks it up, synthesizes into main.
4. Project wiki's page gets a frontmatter note: `also_in_main: true`.

Evaluation is prompt-based — ingester's instructions list "project-specific indicators" (uses internal naming, refers to this repo's architecture, mentions only this codebase's decisions) and "general-interest indicators" (describes a tool, pattern, concept, or principle that applies outside this project). When ambiguous, default to main wiki with a short pointer page rather than full synthesis (lower risk).

No auto-propagation from main to project. If main has something relevant to a project, the project wiki can link to it during its own ingests. Uni-directional auto-propagation (project → main); queries read both.

### Cross-wiki querying

The skill doesn't search across wikis automatically. When working in a project wiki, queries read the project wiki first. If it references the main wiki (via a frontmatter field or an explicit link), the agent can follow that link and read main wiki pages as needed. Main wiki is the default fallback when a project wiki doesn't have the answer.

For v1 this is purely agent-driven via prompts — no special indexing. If cross-wiki search becomes painful we add it later as a subindex aggregating all wikis' indexes.

### Lint — three tiers

**Tier 1 — inline at ingest (always runs):**
- Scope: only the pages the ingest just touched.
- Checks: broken markdown links, frontmatter validity (dates, required fields), every claim has an inline source-back-link, new pages have at least one inbound link, index is updated.
- Model: whatever the ingester is already using (cheap).
- Cost: near-zero (pages already in context).

**Tier 2 — opportunistic (runs during SessionStart drain or doctor):**
- Scope: pages neighboring recently-ingested ones + random sample.
- Checks: orphan pages, thin pages, missing concepts (terms frequent but no page), stale frontmatter dates.
- Model: cheap.
- Cost: low, bounded by sample size.

**Tier 3 — `wiki doctor` only (user-invoked):**
- Scope: everything in the wiki.
- Checks: all of Tier 1 and 2, plus contradiction detection across pages, source-back-link verification (sample claims, fetch source, verify), index reconciliation (pages in index vs. filesystem), index sharding if oversized, rebuilding broken cross-references.
- Model: smartest available. Doctor is rare, high-stakes, user-asked — cheap model doing cleanup is worse than not doing cleanup.
- Cost: ~$0.50-$1 per run at 250 pages; can be run monthly or as-needed.

### User commands

**`wiki doctor`**
- Full Tier 3 lint + fix pass.
- Auto-fixes mechanical issues (broken links, stale frontmatter, index reconciliation).
- Flags judgment calls (contradictions, ambiguous orphans) to a report file and (optionally) a user prompt.
- Uses smartest model.
- Safe to interrupt (idempotent).

**`wiki status`**
- Read-only.
- Prints: pending capture count, processing (stale?) captures, stale locks, last ingest timestamp, page counts per category, total pages, index size (tokens-ish), orphan count (approximate), git dirty/clean status, total cost this month if tracked.
- Complement to `wiki doctor`: status tells you *if* something is wrong, doctor *fixes* it.

No other commands. Everything else is automatic or natural language.

### Natural-language triggering (how the LLM knows to use the wiki)

The SKILL.md description contains explicit TRIGGER and DO-NOT-TRIGGER rules. The LLM reads them on every interaction and decides whether to invoke the skill's operations.

Triggers include:
- User asks a factual question that might be in the wiki
- User asks about a tool, concept, or entity
- User asks "what we did" / "what did we decide" / "how do we handle X"
- Files are added to `raw/`
- Research subagents return files
- A wiki-worthy moment emerges during the session
- User says "add to wiki" / "remember this" / "wiki it"

Do NOT trigger:
- Time-sensitive questions (fetch fresh data)
- Pure coding/implementation help (unless about decisions documented)
- User explicitly asks to skip the wiki
- Questions clearly outside the wiki's scope

### Git integration

- Every wiki is a git repo (`git init` at auto-init).
- `.gitignore` auto-written: `.locks/`, `.ingest.log`, optionally `raw/` large binaries.
- Commits auto-created after successful ingests (configurable; default on).
- Commit message: `ingest: <capture title>` or `doctor: <summary>` or `manual edit` (for user-made commits).
- User adds a remote manually when they want sync (`git remote add origin ...`).
- No auto-push. Pushing is the user's call.

Multi-device sync: everything in the wiki except `.locks/` and `.ingest.log` is in git. Captures (`.wiki-pending/`) sync across devices. A capture made on laptop gets ingested on desktop if the ingester there fires first.

### Obsidian compatibility

Always-on, no detection.

At init, the skill writes:
- `.obsidian/app.json` with ignored-folders entries for `.wiki-pending/`, `.locks/`, `raw/` (optional), `.ingest.log`.

If the user opens the wiki dir as an Obsidian vault:
- Regular markdown links work (we use them everywhere, not `[[wikilinks]]`).
- Frontmatter works.
- Graph view works.
- Backlinks work.
- Search works.

If the user never installs Obsidian, the `.obsidian/` dir sits there ignored. Harmless.

### Cross-platform support

The skill targets Claude Code, Codex, OpenCode, Cursor, Gemini CLI, Aider, and any agentic CLI with:
- Skills or equivalent (to load SKILL.md)
- Hooks or equivalent (to run SessionStart/Stop shell commands)
- Headless invocation (to spawn background ingesters)

Detected at init; recorded in `.wiki-config`:
- `agent_cli`: which tool is in use
- `headless_command`: the specific invocation (`claude -p`, `codex exec`, etc.)

Fallback if headless isn't available: the in-session agent spawns a parallel subagent for ingestion. Slower because it consumes session context, but still non-blocking.

### What we know is hard and may need later iteration

**In-session "is this wiki-worthy?" decisions**
Relies on the agent's judgment, guided by the SKILL.md description. First version will be noisy or over-cautious. Tune with real usage.

**Propagation scope judgment**
Ingester deciding "is this general or project-specific" is a prompt-engineering problem. Likely over-propagates initially. User can always delete main-wiki pages that shouldn't be there.

**Ingester reliability at high concurrency**
Lock system should work but hasn't been stress-tested. If we see deadlocks or data loss, add metrics and tune timeouts.

**Error baking over long time periods**
Most dangerous failure mode. Mitigations (inline source-back-links, raw/ archival, doctor verification) buy us time. If it becomes a real problem, consider adding confidence scoring (from the v2 gist in the ecosystem report).

**Index scaling beyond ~500 pages**
Auto-sharding handles 500-ish. Past 1000, we probably need a vector or BM25 index alongside the markdown. Defer.

---

## Part 3 — Migration plan (how to actually get here from v1)

### Skill refactor

Starting from the current `~/.claude/skills/{wiki,project-wiki}` setup:

1. **Merge** the two skills into one directory: `~/.claude/skills/wiki/` (keeping the name for the existing 63-star github repo at toolboxmd/karpathy-wiki).
2. **Fix the four bugs in the current v1:**
   - `grep -oP` (PCRE, not on macOS BSD grep by default) → replace with `grep -oE` or awk
   - `git diff --since` is invalid (`--since` is a `git log` flag) → replace with `git log --name-only --since`
   - Stop hook type `prompt` (LLM-decided at Stop) → replace with Stop hook type `command` that writes marker files
   - Timestamp-based drift check → replace with `.manifest.json` SHA-256 hash manifest
3. **Add** all the v2 machinery: captures, `.wiki-pending/`, page locks, auto-init, `wiki doctor` and `wiki status` subcommands, headless-ingester spawning, propagation, schema-driven structure, Obsidian config, git integration.
4. **Remove** the old `project-wiki` skill directory (merged into `wiki`).
5. **Update** the SKILL.md description with the new TRIGGER/DO-NOT-TRIGGER rules, wiki-worthy criteria, and the two-command surface.

### Content migration

The user's existing corpus:
- `/Users/lukaszmaj/dev/bigbrain/` — 17 research/plan `.md` files at root
- `/Users/lukaszmaj/dev/bigbrain/research/` — 55 files
- `/Users/lukaszmaj/dev/bigbrain/plans/` — 4 files
- `/Users/lukaszmaj/dev/research/`, `/Users/lukaszmaj/dev/noir-chrome-research/`, scattered `research-*.md` in other projects

Migration approach (deferred to a separate plan once the skill is hardened):
- Bulk-copy all files into `~/wiki/raw/` preserving original paths as metadata
- Create initial captures for each (or for the top ~20 most valuable, with the rest as background material for later on-demand ingestion)
- Let the ingester build `~/wiki/` organically
- Run `wiki doctor` to catch orphans/broken links after the bulk pass

### Per-project adoption

For each existing project (`amazonads`, `opencanmod`, `naturbiss`, etc.):
- User (or agent) invokes the skill from inside the project once
- Auto-init creates `./wiki/` as a project wiki linked to main
- Captures accumulate naturally as work happens
- No manual ceremony

### Publishing updates

- toolboxmd/karpathy-wiki github repo gets a v2 branch, tested locally first
- Once stable, merge to main and tag `v2.0.0`
- Existing 63 stargazers pull the update when they want

---

## Part 4 — Open questions for the implementation plan

These are things we discussed but didn't finalize, and that the implementation plan will need to pin down:

1. **Exact wiki-worthy criteria** in SKILL.md description — needs careful wording to trigger correctly without over-triggering.
2. **Stop-hook transcript sweep — default on or default off?** Cost is real (~$0.02/session) but it's the backstop that catches missed captures. Current lean: default on, opt-out.
3. **Exact Obsidian ignored-folders JSON schema** — need to verify against current Obsidian plugin API.
4. **How exactly the ingester detects its platform's headless command** — env var inspection? `which` checks? User prompt on first run?
5. **Whether `raw/` should be gitignored by default** or committed** — committing is safer (wiki is self-contained), gitignoring is lighter (wiki stays small). Lean: committed by default, user can change.
6. **Threshold values**: when does index auto-shard (page count or token count)? How long before a `.processing` file is considered stale? How long before a `.lock` is stale?
7. **Cost tracking**: do we embed token/cost tracking from day one, or leave that for later?
8. **Whether the Stop-hook transcript sweep uses the same cheap model or always the cheapest available**.
9. **Whether propagation from project to main should include a diff note** ("this came from project X") or just silently appear in main.
10. **Schema bootstrap**: what's the starter `schema.md` content for a freshly-auto-init'd wiki?

---

## Summary of the state of this discussion

We've converged on a clear design. Two wiki roles (main + project) with the same operations. Immediate background ingestion triggered by captures. Two user commands. Zero-setup install. Git-backed, Obsidian-compatible, cross-platform. Locking for concurrency. Three-tier lint. Hash manifest only on `raw/`, not wiki pages. Natural-language triggering for queries.

Next step: write the implementation plan. That plan will turn this design into concrete refactor tasks, new file contents, and test cases.

This document should be sufficient to recreate the design in a future session. If resuming: re-read this doc, re-read `/Users/lukaszmaj/dev/bigbrain/research/karpathy_wiki_ecosystem.md` for ecosystem context, and look at the current `~/.claude/skills/wiki/` and `~/.claude/skills/project-wiki/` contents to know the v1 starting point.
