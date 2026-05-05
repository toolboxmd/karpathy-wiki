---
title: "karpathy-wiki v2.4 — Executable Protocol"
status: design
created: 2026-05-05
authors: [lukemaj]
supersedes: []
---

# karpathy-wiki v2.4 — Executable Protocol

## Problem

Three pieces of behavior described in `SKILL.md` today are **prose, not
script**: the agent is told *what should happen*, but no code enforces it.
In practice, agents skip these steps — silently and consistently — because
the rules live in a document the agent may or may not read.

1. **Skill auto-load.** `SKILL.md` says *"load this skill on every
   conversation; entry is non-negotiable."* In reality the agent loads it
   most of the time and ignores it some of the time. There is no hook that
   forces the rules into the conversation.

2. **Project-wiki resolution.** `SKILL.md` describes a 3-case algorithm for
   deciding which wiki a capture belongs to (cwd-local project wiki vs
   `$HOME/wiki`). No script runs that algorithm. Captures default to
   `$HOME/wiki/` regardless of cwd; project wikis are dead code.

3. **Raw-direct ingest.** `SKILL.md` lists "user adds a file to `raw/`" as
   a capture trigger, but the only mechanism is for the agent to write a
   *fabricated wrapper capture* around the file — a thin "please process
   this" note that fails the body-floor sufficiency rule and produces a
   low-information wiki page.

All three share the same diagnosis (prose-not-script) and the same fix
shape (replace prose with a script or hook that fires unconditionally).
v2.4 ships them together.

## Goals

- Skill rules are present in every conversation, regardless of agent
  judgment.
- The wiki the capture lands in is decided by the user (one-time per
  cwd), not silently defaulted.
- Files dropped into a wiki's drop zones (`Clippings/`, `raw/`) are
  ingested directly from their content, with no fabricated wrapper.
- Each ingester's view of the world is shaped by the wiki it reads —
  index, schema, log, **and the pages it's about to link to** — so the
  difference between "project lens" and "main lens" emerges from the
  index gravity instead of a prompt-level role hint.
- Issues the ingester observes during reading (broken links,
  contradictions, schema drift, stale claims) are reported to a
  durable, queryable log instead of evaporating.

## Non-goals

- Cross-wiki back-references (project pages linking to main pages and
  vice versa). Each ingester sees its own wiki only. A future
  `wiki link-instances` command can connect pattern pages to instance
  pages post-hoc; not in v2.4.
- `wiki doctor` real implementation. Stays stubbed; v2.4 produces a
  richer issue feed for it to consume later.
- Migrating `.ingest.log` to JSONL. Carved out to v2.5; see "Deferred to
  v2.5" below.
- Filesystem watchers or daemons for raw-direct ingest. SessionStart
  scan only.
- Per-capture fork decisions by the agent. The user's per-cwd choice
  decides; the agent does not assess fork-worthiness per capture.

---

## Architecture

### Three legs, one theme

The unifying pattern across all three legs:

> **A small script runs at a defined moment, reads explicit signals, and
> takes an action that previously lived in `SKILL.md` prose.**

Concretely:

| Leg | Moment | Signal read | Action |
|---|---|---|---|
| Auto-load | session start | `skills/using-karpathy-wiki/SKILL.md` exists | inject loader as `additionalContext` |
| Project resolver | first capture in cwd | cwd has `.wiki-config` / `.wiki-mode` / neither; `~/.wiki-pointer` exists / not | use existing wiki, OR prompt user, OR initialize one |
| Raw-direct | session start | manifest.json vs files in `raw/` and `Clippings/` | create raw-direct ingest job per new file |

### Component map

New files:

```
skills/using-karpathy-wiki/SKILL.md       # thin loader, force-loaded
skills/karpathy-wiki-capture/SKILL.md     # for the main agent (read on demand)
skills/karpathy-wiki-ingest/SKILL.md      # for the spawned ingester only
scripts/wiki-resolve.sh                   # decides which wiki a capture goes to
scripts/wiki-init-main.sh                 # interactive main-wiki bootstrap
scripts/wiki-use.sh                       # change per-cwd mode
scripts/wiki-issues.sh                    # render .ingest-issues.jsonl as markdown
scripts/wiki-issue-log.sh                 # ingester helper to append a JSON line
hooks/session-start                       # extended to inject loader + scan drop zones
```

Removed / split:

```
skills/karpathy-wiki/SKILL.md             # split into the three above
```

New per-wiki state file:

```
<wiki>/.ingest-issues.jsonl               # append-only, machine-readable
```

New per-cwd marker file (created when user picks main-only or both):

```
<cwd>/.wiki-mode                          # contents: "main-only" or "both"
```

New per-user pointer file:

```
~/.wiki-pointer                           # contents: "<absolute path to main wiki>" or "none"
```

### Iron rules preserved

- No wiki write in the foreground.
- No page edit without reading the page first.
- No skipping a capture because "it doesn't look wiki-shaped."
- Captures still ship via `.wiki-pending/`; spawn flow unchanged.
- Each ingester sees only its own wiki.

---

## Leg 1 — Skill auto-load via session-start injection

### Pattern

Mirror `superpowers:using-superpowers`. A thin meta-skill is force-loaded
at session start; full operational skills are read on demand when the
agent decides to act.

### `using-karpathy-wiki/SKILL.md`

A short loader (~40-80 lines), force-loaded into every conversation by
the SessionStart hook:

- The skill name and the announce-line contract.
- The iron laws (3 lines).
- The trigger taxonomy (when to capture, when to skip).
- A pointer: *"For the full capture protocol, read
  `skills/karpathy-wiki-capture/SKILL.md`. For ingest behavior, that lives
  in `skills/karpathy-wiki-ingest/SKILL.md` and is loaded by the spawned
  ingester only."*
- A `<SUBAGENT-STOP>` block at the top: *"If you were dispatched as a
  subagent for a task unrelated to wiki capture or ingest, skip this
  skill."*

### SessionStart hook extension

`hooks/session-start` adds one step to its existing work: emit
`hookSpecificOutput.additionalContext` containing the loader's body
wrapped in `<EXTREMELY_IMPORTANT>` tags.

The loader-injection step runs **before** the existing drift-scan and
drain steps. The `WIKI_CAPTURE` fork-bomb guard already at the top of
the hook (skips the hook entirely when running inside a spawned
ingester) handles subagent re-entry.

### Skill split

The current `skills/karpathy-wiki/SKILL.md` (~500 lines) becomes three
documents:

| File | Reader | When loaded | Content |
|---|---|---|---|
| `using-karpathy-wiki/SKILL.md` | main agent | session start (auto) | loader: triggers, iron laws, announce contract, pointers |
| `karpathy-wiki-capture/SKILL.md` | main agent | on demand (when capturing) | trigger detection, capture file format, body-size floors, spawn command, mode-change CLI |
| `karpathy-wiki-ingest/SKILL.md` | spawned `claude -p` | spawn-time prompt | orientation (now "deep orientation"), page format, role guardrail, validator, manifest, commit, issue reporting |

A small `references/shared.md` covers fields that genuinely span both
readers (capture frontmatter contract, evidence-path conventions). Both
skills point at it.

### Why this beats injecting the full SKILL.md

- The current 500-line body is mostly ingest detail the main agent
  never uses. Force-loading it bloats every conversation's context
  with operational text.
- The split makes role responsibilities legible. A reader of
  `karpathy-wiki-capture` is not distracted by manifest commit
  protocols; a reader of `karpathy-wiki-ingest` is not distracted by
  the announce-line contract.

### Test surface

- Fresh session in a directory with a wiki, no prior captures: agent
  receives loader. Verified by reading `<EXTREMELY_IMPORTANT>` tag
  presence in the first turn's context (manual inspection per RED-GREEN
  discipline).
- Subagent dispatch (e.g., `Explore` agent): receives `<SUBAGENT-STOP>`
  block, skips skill load.
- Ingester (spawned `claude -p` with `WIKI_CAPTURE` set): SessionStart
  hook short-circuits; loader is NOT injected; ingester loads
  `karpathy-wiki-ingest` via its spawn prompt.

---

## Leg 2 — Project-wiki resolver

### Three-state model

Each cwd is in exactly one of three states:

1. **Inside a wiki** — `cwd/.wiki-config` exists. Use that wiki.
2. **Configured to use main only or to fork** — `cwd/.wiki-mode` exists.
   Mode dictates target(s).
3. **Unconfigured** — neither file exists. First capture triggers a
   prompt to the user.

### `wiki-resolve.sh`

A new script called at the start of every capture flow (replaces the
implicit reliance on `wiki_root_from_cwd`). Pseudocode:

```
read $HOME/.wiki-pointer:
  - missing                 → run wiki-init-main.sh, retry
  - contains "none"         → main_wiki = (no main wiki configured)
  - contains <path>         → main_wiki = <path>

check cwd/.wiki-config:
  - exists                  → return [cwd] (use this wiki only)

check cwd/.wiki-mode:
  - contains "main-only"    → return [main_wiki]
                              (or fail with "configured main-only but no main wiki")
  - contains "both"         → return [cwd, main_wiki]
                              (or fail with "configured both but no main wiki")

# Unconfigured cwd: prompt user.
prompt user (project | main | both):
  - project    → run wiki-init.sh project ./wiki <main_wiki>
                 (if main_wiki is "none", run wiki-init.sh project ./wiki
                  with no main; the project wiki stands alone)
                 return [./wiki]
  - main       → require main_wiki to be set; write .wiki-mode "main-only"
                 return [main_wiki]
  - both       → require main_wiki to be set; run wiki-init.sh project ./wiki <main_wiki>
                 write .wiki-mode "both"
                 return [./wiki, main_wiki]

If main_wiki is "none", options "main" and "both" are not offered in
the prompt — only "project" is shown, and the prompt collapses to a
yes/no confirmation.
```

### cwd-only resolution

The resolver checks **only cwd**, not parents. The user is responsible
for `cd`-ing to the right directory before starting the agent. Rationale:

- Walk-up resolution has a known false-positive (sibling wiki under
  `$HOME` claimed by every cwd under `$HOME`). The current
  `wiki_root_from_cwd` exhibits this bug today.
- Walk-up's correct behavior would require an arbitrary stopping rule
  (`$HOME` boundary). Cwd-only needs no rule.
- Mirrors `git init`, `npm init`, `cargo init` — all operate on cwd.
- A user who runs the agent from a subdirectory of an already-configured
  project gets a second wiki at the deeper level. That is their choice;
  the design treats it as the user's responsibility, not a bug to
  prevent.

### First-time main-wiki bootstrap (`wiki-init-main.sh`)

When `~/.wiki-pointer` is missing, the resolver runs an interactive
bootstrap:

```
You don't have a main (global) wiki yet.
A main wiki collects general patterns reusable across projects.
You can have project-only wikis without one.

  1) yes — create a main wiki (you'll be asked where)
  2) no  — project wikis only

Reply with 1 or 2.
```

If `1`:

```
Where should the main wiki live?
  Default: ~/wiki/
  (Reply "default" or a path; the wiki will be created there.)
```

The script then runs `wiki-init.sh main <path>` and writes
`~/.wiki-pointer` with the path. If `2`, writes `~/.wiki-pointer` with
the literal `none`.

If a wiki already exists at `~/wiki/` (pre-v2.4 user upgrading) but
`~/.wiki-pointer` is missing, the bootstrap **does not prompt** —
detects the existing wiki and writes `~/.wiki-pointer` pointing to it.
Silent migration.

### Per-cwd prompt

```
This directory isn't configured for the wiki yet. How should captures here flow?

  1) project — create a project wiki at ./wiki/, captures stay local.
              Documents specifics: how this app handles X, where bug Y
              lived, what we decided for this codebase.

  2) main    — captures go to <main_wiki> (the default).
              Documents general patterns reusable across projects.

  3) both    — fork: write the same capture into both wikis.
              Two ingesters run, each with its own lens.
              Project ingester documents the specifics; main ingester
              extracts the general pattern. Two pages emerge from one
              event.

Reply with 1, 2, or 3.

You can change this later with `wiki use project|main|both` or just ask me.
```

If `~/.wiki-pointer` contains `none`, options 2 and 3 are hidden — the
prompt collapses to a confirmation that the user wants a project wiki
here.

### `.wiki-mode` marker file

A small file in cwd containing one of two strings on its first line:

- `main-only`
- `both`

No other contents. Optional second line: `# created YYYY-MM-DD by wiki use`.

The "project" choice does not write `.wiki-mode` — it writes
`./wiki/.wiki-config` (via `wiki-init.sh project`), and the resolver
detects project mode via `.wiki-config` presence.

### `wiki use` CLI

Three subcommands:

- `wiki use project` — if `./wiki/` doesn't exist, run
  `wiki-init.sh project ./wiki <main>`. Remove `.wiki-mode` if present.
- `wiki use main` — write `.wiki-mode` containing `main-only`. Print
  warning if `./wiki/` exists ("local wiki kept; captures will no longer
  go there; `rm -rf ./wiki` to remove it").
- `wiki use both` — if `./wiki/` doesn't exist, init it. Write
  `.wiki-mode` containing `both`.

Idempotent: re-running with the current mode is a no-op.

The `using-karpathy-wiki` loader includes a one-line directive: *"When
the user asks to change wiki mode for this directory (phrases like 'use
project wiki here,' 'main only,' 'switch to both'), run
`wiki use <mode>` and confirm."*

### Forking on capture

When the resolver returns multiple wikis (mode `both`), the main agent
writes the **same capture body into each wiki's `.wiki-pending/`**.
Filenames are independent (each wiki generates its own
`<timestamp>-<slug>.md`). Each wiki's ingester claims its own copy and
runs independently. No cross-ingester coordination, no locking
complications.

The ingest skill's deep-orientation step shapes the lens: each ingester
reads its own wiki's index, schema, log, **and the 3-7 pages it
identifies as candidates for cross-linking**. The gravitational pull of
existing pages (specific in project wiki, general in main wiki) shapes
what gets written. The `role` field in `.wiki-config` becomes a tripwire
— *"if you find yourself generalizing in a project wiki / specifying in
a main wiki, stop"* — not the primary lens.

### Test surface

- Fresh cwd outside any wiki, no `~/.wiki-pointer`: bootstrap fires,
  asks Q1 and Q2, writes pointer, then asks per-cwd prompt.
- Fresh cwd outside any wiki, `~/.wiki-pointer` contains `none`:
  per-cwd prompt collapsed (project only).
- Fresh cwd outside any wiki, `~/.wiki-pointer` valid: full per-cwd
  prompt (1/2/3).
- Cwd is under an existing project wiki (cwd has `.wiki-config`):
  resolver returns [cwd's wiki] silently.
- Cwd has `.wiki-mode = both`: resolver returns [project wiki, main
  wiki].
- `wiki use main` after prior `project` choice: warning printed,
  `./wiki/` preserved, `.wiki-mode` written.

---

## Leg 3 — Raw-direct ingest

### Trigger

The existing SessionStart drift-scan extends to also scan `Clippings/`
(in addition to `raw/`). For each new file (not in `.manifest.json`),
the hook creates a **raw-direct capture** in `.wiki-pending/` and
spawns a normal ingester against it.

The capture differs from a chat capture in two ways:

1. `evidence_type: file` and `evidence: <absolute path to the dropped file>`.
2. A new `capture_kind: raw-direct` field in the frontmatter, signaling
   to the ingester that **the body is intentionally minimal** — the file
   IS the evidence; the ingester reads the file directly.

### Body sufficiency for raw-direct

Today's `evidence_type: file` floor is 200 bytes of pointer-with-intent
prose. Raw-direct captures cannot meet that floor honestly — the agent
is the SessionStart hook, not a thinking entity that knows why the user
dropped the file.

The body-floor rule extends:

- `evidence_type: file` AND `capture_kind: raw-direct` → no body floor;
  body is auto-generated boilerplate ("Auto-ingest of file dropped into
  `Clippings/`. Read the file, infer category from content, decide
  create vs augment, file under appropriate category.").
- `evidence_type: file` AND `capture_kind` absent (or `chat-attached`)
  → 200-byte floor unchanged.

The ingester's lens does the work: it reads the file, runs deep
orientation, and decides where the resulting page belongs. No fake
"please process this" wrapper.

### Lens for raw-direct

Same as chat-driven captures: the wiki's role determines the lens. A
file dropped into `<project-wiki>/Clippings/` gets project-lens
ingestion; a file dropped into `<main-wiki>/Clippings/` gets main-lens
ingestion. Drops do **not** fork — the user picked the wiki by picking
the directory.

### Failure modes

- File is binary / unreadable: ingester writes an issue
  (`issue_type: other`, severity `warn`, detail `cannot read raw file`),
  archives the capture, does not commit a page.
- File is empty: same.
- File is a duplicate of an existing raw (sha256 already in manifest):
  ingester logs and archives without writing.

### Test surface

- Drop a markdown file into `Clippings/`. Next session start:
  capture appears in `.wiki-pending/`; ingester runs; page appears in
  the appropriate category; raw is in `raw/` with manifest entry.
- Drop the same file twice: second SessionStart's drift-scan detects
  it as MODIFIED only if the content changed; otherwise no second
  capture.
- Drop a binary file: issue log captures the failure; no page written.

---

## Deep orientation

### Current orientation

Today the ingester reads:
1. `schema.md`
2. `index.md` (or `_index.md` per category in v2.3)
3. Last ~10 lines of `log.md`

Then writes its page.

### The gap

Reading the index reveals what page **titles** exist; it does not reveal
what those pages **say**. The ingester picks `see also` cross-links based
on title similarity, sometimes linking to pages that don't actually
relate. Worse: it sometimes creates a new page when an existing one
already covers the topic, because it didn't read the existing page.

### v2.4 deep orientation

The ingester's orientation step grows a "deep" phase between "list
candidates" and "decide":

1. Read `schema.md` (unchanged).
2. Read `index.md` / `_index.md` (unchanged).
3. Read last ~10 lines of `log.md` (unchanged).
4. **From the capture, identify 3-7 candidate pages by title-tag-keyword
   match against the index.**
5. **Read those candidate pages in full.**
6. Decide: create new, augment existing, or no-op (existing already
   covers).
7. While doing 5, observe issues (broken links, contradictions, schema
   drift, stale claims, tag drift, quality concerns, orphans). Append
   each to `.ingest-issues.jsonl` via `wiki-issue-log.sh`. **Don't fix
   them inline; report only.**

### Why this matters for the lens question

Step 5 is what makes the project/main lens emergent. Reading 5 pages
about "our auth flow" pulls the next page's writing toward instance-style
specificity. Reading 5 pages about "FFI patterns" pulls toward general
abstraction. The role guardrail at the prompt's tail is now a backup
check, not the primary mechanism.

### Cost

3-7 extra file reads per ingestion. Each page is typically 5-20 KB. The
ingester is already reading the capture and the schema; this is the same
order of magnitude. No measurable spawn-time impact.

---

## Issue reporting

### Storage: `.ingest-issues.jsonl`

Append-only JSON Lines. Located at `<wiki>/.ingest-issues.jsonl`. One JSON
object per line:

```json
{
  "reported_at": "2026-05-05T14:23:11Z",
  "ingester_run": "in-1746458591-abc123",
  "capture": ".wiki-pending/2026-05-05-foo.md.processing",
  "page": "concepts/auth-flow.md",
  "issue_type": "broken-cross-link",
  "severity": "warn",
  "detail": "Links to /concepts/legacy-auth.md which does not exist.",
  "suggested_action": "Remove link or create stub page."
}
```

Field contracts:

- `reported_at` — ISO-8601 UTC.
- `ingester_run` — opaque identifier (timestamp + short hash) tying the
  issue to a specific ingest invocation. Already implicit in
  `.ingest.log` today; v2.4 generates it once per ingester and threads
  it through.
- `capture` — wiki-relative path to the capture being processed when
  the issue was observed.
- `page` — wiki-relative path to the page where the issue was observed
  (the page the ingester was reading, not the one it was writing).
- `issue_type` — bounded enum: `broken-cross-link | contradiction |
  schema-drift | stale-claim | tag-drift | quality-concern | orphan |
  other`.
- `severity` — `info | warn | error`. `error` blocks ingestion (rare:
  unreadable schema). `warn` is default. `info` is observational.
- `detail` — free-form prose, what the ingester saw.
- `suggested_action` — optional. The ingester's hint for `wiki doctor`
  to act on later.

### Why JSONL not markdown

Per `concepts/agent-vs-machine-file-formats.md`, JSONL is correct for
**append-only machine-write** surfaces (transcripts, event logs).
Markdown is correct for **agent-read** surfaces. Issue reports are both:
machine appends them, agents (and `wiki doctor`) read them.

The wiki's own canonical pattern is dual-artifact: keep the JSONL as
the canonical store; render markdown on demand for agent reads.

### Read surface: `wiki issues`

A new CLI that reads `.ingest-issues.jsonl` and renders a markdown
summary to stdout:

```markdown
# Wiki issues — 12 open

## Broken cross-links (6)
- `concepts/auth-flow.md` → `/concepts/legacy-auth.md` (target missing)
  - reported 2026-05-05 by ingester run in-1746458591
  - suggested: remove link or create stub

- `concepts/foo.md` → `/entities/bar.md` (target missing)
  ...

## Schema drift (3)
- `concepts/baz.md` has `type: concept` (singular); should be `type: concepts`
  ...

## Contradictions (2)
- `concepts/x.md` claims X; `concepts/y.md` claims not-X
  ...
```

Grouped by `issue_type`, ordered by severity within each group. `--filter
<type>` and `--since <date>` flags for narrower views.

### `wiki status` integration

Existing `wiki status` adds an "Issues" section:

```
Issues reported by ingesters (last 30 days):
  6 broken cross-links
  3 schema drift
  2 contradictions
  1 stale claim
  Run `wiki issues` for details.
```

### Ingester helper: `wiki-issue-log.sh`

A small bash wrapper around appending a JSON line. The ingester calls:

```bash
wiki-issue-log.sh \
  --ingester-run "$INGESTER_RUN_ID" \
  --capture "$CAPTURE_PATH" \
  --page "$PAGE_BEING_READ" \
  --type broken-cross-link \
  --severity warn \
  --detail "Links to /concepts/legacy-auth.md which does not exist." \
  --suggested-action "Remove link or create stub page."
```

The script validates the type enum, formats the JSON, and atomically
appends one line to `<wiki>/.ingest-issues.jsonl`. Append uses `>>` —
atomic for single lines on local filesystems (POSIX guarantees writes ≤
PIPE_BUF are atomic).

### `wiki doctor` consumes this later

Out of scope for v2.4 (still stubbed). When implemented, `wiki doctor`
reads `.ingest-issues.jsonl` as its work queue: each issue is a candidate
fix.

---

## Data flow end-to-end

### Capture (chat-driven)

```
user says something wiki-worthy
  ↓
main agent (skill rules force-loaded by SessionStart)
  ↓
agent loads skills/karpathy-wiki-capture/SKILL.md on-demand
  ↓
agent runs wiki-resolve.sh
  ↓
resolver returns one or two wikis based on cwd config
  ↓ (if first time, prompt user; bootstrap main wiki if needed)
agent writes capture body to each returned wiki's .wiki-pending/
  ↓
agent calls wiki-spawn-ingester.sh per wiki
  ↓
detached claude -p ingester(s) start
  ↓
ingester loads skills/karpathy-wiki-ingest/SKILL.md
  ↓
ingester runs deep orientation (schema + index + log + 3-7 pages)
  ↓
ingester writes / augments / no-ops; appends issues to JSONL
  ↓
ingester commits, archives the capture
```

### Capture (raw-direct)

```
user drops file into <wiki>/Clippings/ or <wiki>/raw/
  ↓
next SessionStart fires
  ↓
hook scans drop zones, finds new file
  ↓
hook creates raw-direct capture in .wiki-pending/
  ↓
hook calls wiki-spawn-ingester.sh
  ↓
detached claude -p ingester starts
  ↓
ingester reads the dropped file (not the capture body)
  ↓
ingester runs deep orientation
  ↓
ingester writes / augments / no-ops; appends issues to JSONL
  ↓
ingester commits, archives the capture, copies file to raw/, updates manifest
```

---

## Error handling

| Failure | Behavior |
|---|---|
| `~/.wiki-pointer` missing on first capture | bootstrap interactive prompt fires; if user aborts, capture aborts with explicit message |
| `~/.wiki-pointer = none` AND user picks "main" or "both" in per-cwd prompt | resolver errors: "no main wiki configured; pick `1` or run `wiki-init-main.sh` first" |
| `cwd/.wiki-config` exists but `.wiki-mode = both` | conflict: project mode (config presence) takes precedence; warn user once, suggest `wiki use both` to reconcile |
| Spawn fails (no `claude` binary, etc.) | capture stays in `.wiki-pending/`; existing reclaim logic picks it up next session |
| Raw-direct file is binary / empty | issue logged, capture archived, no page written |
| `.ingest-issues.jsonl` write fails | log to `.ingest.log` and continue (issue tracking is best-effort, never gates ingestion) |
| Deep orientation candidate page is malformed YAML | issue logged (`schema-drift`); ingester continues with remaining candidates |

---

## Testing

Per `superpowers:writing-skills` RED-GREEN-REFACTOR discipline:

### Unit tests (per-script)

- `wiki-resolve.sh` — table of (cwd state, pointer state) → expected
  return value. ~12 cases covering all branches.
- `wiki-init-main.sh` — fresh-state prompt flow, pre-existing-wiki
  silent-migration path, "none" path.
- `wiki-use.sh` — three subcommands × idempotency × already-configured
  states.
- `wiki-issue-log.sh` — type enum validation, JSON formatting,
  concurrent-append correctness (multiple ingesters writing the same
  file).
- `wiki-issues.sh` — render correctness, filter and since flags, empty
  log handling.

### Integration tests

- **End-to-end chat capture, project mode**: fresh cwd, simulate user
  picks "project" at prompt → `./wiki/` appears, capture lands in
  `./wiki/.wiki-pending/`, ingester runs, page committed.
- **End-to-end chat capture, both mode**: fresh cwd, simulate user
  picks "both" → capture appears in both wikis, two ingesters run,
  two pages exist.
- **End-to-end raw-direct**: drop file in main wiki's `Clippings/`,
  trigger SessionStart, verify page emerges, raw file is in `raw/`,
  manifest updated.
- **Issue reporting**: ingest a capture against a wiki with a known
  broken link in the candidate page set; verify a JSONL line appears
  with `issue_type: broken-cross-link`.
- **`wiki issues` rendering**: write 5 fixture issues; run `wiki
  issues`; assert grouping, ordering, format.

### Pressure tests (skill-rule level)

For each skill prose change, write a "RED scenario" — a transcript
fragment showing an agent failing the rule, demonstrating why the rule
is needed before adding it.

---

## Migration

### From v2.3 to v2.4

1. Existing `~/wiki/.wiki-config` users: silent migration. The first
   v2.4 run notices `~/wiki/` exists, writes `~/.wiki-pointer` pointing
   to it, no prompt.
2. `skills/karpathy-wiki/SKILL.md` is split into three new skills.
   Existing `hooks/hooks.json` already references the SessionStart
   hook; only the hook body changes.
3. `.ingest-issues.jsonl` is created lazily on first write. No schema
   migration needed.
4. Existing `.wiki-pending/` captures continue to work — their
   frontmatter doesn't carry `capture_kind`; absence is treated as
   `chat-attached` (the existing behavior).
5. `wiki-init.sh` already supports both `main` and `project` modes;
   no schema change.

### Rollback

Each leg is independently revertable:

- Auto-load: revert the SessionStart hook change, revert the skill
  split. Existing skill prose still works.
- Resolver: revert `wiki-resolve.sh` and `wiki-use.sh`. Capture flow
  falls back to `wiki_root_from_cwd`.
- Raw-direct: revert the SessionStart drift-scan extension. Files in
  `Clippings/` are silently ignored as before.

Per CLAUDE.md ("migrations use multiple commits with verification
gates"), each leg ships in its own commit (or commit cluster), with
tests passing between commits. Verification gate after each leg:

- After leg 1: fresh-session test — loader visible in conversation
  context.
- After leg 2: per-cwd-prompt test — three modes exercised end-to-end.
- After leg 3: drop-and-go test — file in `Clippings/` becomes a
  page next session.

---

## Deferred to v2.5

Items deliberately carved out of v2.4:

### Migrate `.ingest.log` to `.ingest.jsonl` (dual-artifact pattern)

Today `.ingest.log` is a hybrid of timestamp-prefixed structured lines
and free-form ingester stdout (the "Ingest complete..." prose bleed).
Neither cleanly machine-parseable (no JSONL) nor agent-friendly (mixed
content). Per the wiki's own
`concepts/agent-vs-machine-file-formats.md`, the right shape is JSONL
canonical + markdown rendered on demand — exactly the pattern v2.4
adopts for `.ingest-issues.jsonl`.

The migration is non-trivial because:
- `_wiki_log` in `wiki-lib.sh` needs to emit JSON instead of prefixed
  text.
- The free-form ingester stdout currently caught by `.ingest.log` needs
  a new home (probably `log.md` is already the right place; the bleed
  is accidental).
- Existing tooling that greps `.ingest.log` (test fixtures, debug
  scripts) needs updating.

Carved out so v2.4 ships the issue-stream pattern in isolation. v2.5
applies the same pattern to the ops log with confidence.

### Cross-wiki back-references (`wiki link-instances`)

Connecting project-wiki "instance" pages to main-wiki "pattern" pages
post-hoc. Out of scope: each ingester sees its own wiki only in v2.4.

### `wiki doctor` real implementation

Still stubbed. The richer issue feed v2.4 produces is a prerequisite;
v2.5 or later actually implements doctor.

### Filesystem watcher for raw-direct

SessionStart-only is good enough for v2.4. A daemon process is
over-engineered relative to the use case; revisit if latency complaints
surface.

### `wiki promote <page>` for manual project→main page promotion

Useful if a project page turns out to be more general than initially
captured. Out of scope for v2.4; the fork-at-capture path covers most
cases; this CLI is for the edge.

---

## Open questions resolved during brainstorm

For traceability — questions that came up during design and how they
were settled:

| Question | Resolution |
|---|---|
| Inject full SKILL.md or thin loader? | Thin loader, mirroring `using-superpowers`. |
| Walk up from cwd or cwd-only? | Cwd-only. User is responsible for starting agent in correct directory. |
| Ask at session start or first capture? | First capture. Avoids prompts in shells where the wiki never fires. |
| Always fork, or agent decides per-capture? | User's per-cwd choice decides. Agent does not assess fork-worthiness. |
| Mirror at capture or fork at raw layer? | Fork at the capture: same body in two pending trays, two ingesters claim independently. |
| Single skill or split? | Split into three (loader / capture / ingest). Token cost on main agent drops ~70%. |
| Ingester role hint? | Tripwire only. Real lens is the wiki's own pages read during deep orientation. |
| JSONL or markdown for issues? | JSONL canonical, markdown rendered on demand. Per `agent-vs-machine-file-formats.md`. |
| Should the main ingester silently reject captures with "no general kernel"? | No. An earlier brainstorm draft considered always-fork-and-let-main-reject; the user's per-cwd choice is now the single decision point. If user chose "both," both ingestions always run; the main ingester does not gate on generality. |

---

## Acceptance criteria

v2.4 ships when:

- [ ] `using-karpathy-wiki/SKILL.md` is force-loaded into every fresh
      session in a wiki-bearing directory; subagents skip it.
- [ ] First capture in an unconfigured cwd prompts user with the 1/2/3
      options; answer is persisted; subsequent captures don't re-prompt.
- [ ] `wiki use project|main|both` changes the persisted choice
      idempotently.
- [ ] First-time use with no main wiki bootstraps via `wiki-init-main.sh`
      prompt; "none" is supported.
- [ ] Files dropped in `Clippings/` are ingested next SessionStart with
      no manual capture authoring.
- [ ] Ingester reads 3-7 candidate pages during orientation;
      observable in `.ingest.log`.
- [ ] Issues observed during orientation are appended to
      `.ingest-issues.jsonl`; `wiki issues` renders them as markdown;
      `wiki status` shows the count.
- [ ] All new scripts have unit tests written before the script (TDD
      discipline).
- [ ] All SKILL.md prose changes have RED-scenario evidence.
- [ ] `bash tests/run-all.sh` passes.
