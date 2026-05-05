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
| Project resolver | every `wiki capture` invocation | cwd has `.wiki-config` / `.wiki-mode` / neither; `~/.wiki-pointer` exists / not | use existing wiki, OR signal "user prompt needed" via exit code, OR initialize |
| Raw-direct | session start AND on-demand `wiki ingest-now` | files in `<wiki>/Clippings/` (drop zone); manifest sha vs sha for files in `raw/` | create raw-direct capture per file; ingester moves Clippings → raw on commit |

### Component map

New files:

```
skills/using-karpathy-wiki/SKILL.md             # thin loader, force-loaded
skills/karpathy-wiki-capture/SKILL.md           # for the main agent (read on demand)
skills/karpathy-wiki-ingest/SKILL.md            # for the spawned ingester only
skills/karpathy-wiki-capture/references/capture-schema.md  # canonical frontmatter contract
bin/wiki                                        # extended: capture, ingest-now, use, issues subcommands
scripts/wiki-resolve.sh                         # decides which wiki(s) a capture targets; non-interactive
scripts/wiki-capture.sh                         # SINGLE entry point for capture writes (calls resolver, writes captures, spawns ingesters)
scripts/wiki-init-main.sh                       # interactive main-wiki bootstrap (run by `wiki capture` only when user channel is available)
scripts/wiki-use.sh                             # change per-cwd mode
scripts/wiki-ingest-now.sh                      # on-demand drift-scan + drain (same logic as SessionStart hook)
scripts/wiki-manifest-lock.sh                   # flock-based wrapper around manifest mutations
scripts/wiki-issues.sh                          # render .ingest-issues.jsonl as markdown
scripts/wiki-issue-log.sh                       # ingester helper to append a JSON line (uses flock)
hooks/session-start                             # extended: inject loader + scan Clippings/ + scan raw/ for drift
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

Each cwd is in exactly one of these states:

1. **Inside a wiki** — `cwd/.wiki-config` exists. Use that wiki. (See
   "Marker layout" for the canonical location.)
2. **Configured external use** — `cwd/.wiki-mode` exists with value
   `main-only` or `both`.
3. **Unconfigured** — neither file exists.

### Marker layout (canonical)

The previous `wiki_root_from_cwd` checked **two** paths per directory:
`<dir>/.wiki-config` AND `<dir>/wiki/.wiki-config`. v2.4 picks **one
canonical layout**: `<cwd>/.wiki-config` ONLY.

When the user picks "project" mode at the per-cwd prompt, `wiki-init.sh
project` is invoked with target `<cwd>/wiki/` — but the resolver does
NOT walk into `<cwd>/wiki/` to discover it. Instead, the resolver
checks `<cwd>/.wiki-config`, and the install step writes a small
**pointer config** at `<cwd>/.wiki-config` that contains:

```toml
role = "project-pointer"
wiki = "./wiki"
created = "2026-05-05"
```

The resolver, on finding `role = "project-pointer"`, reads `wiki` and
returns `<cwd>/<wiki>` as the project-wiki root. The full project wiki
itself (with its own `.wiki-config`, `concepts/`, etc.) lives at
`<cwd>/wiki/`.

Why this layout: it gives one canonical detection path
(`<cwd>/.wiki-config`) regardless of whether the wiki dir is `./wiki/`,
`./.wiki/`, or something else; future installers can write the same
pointer with different `wiki` values. It also avoids the existing
sibling-match bug where being in `~/dev/myapp/` accidentally claims
`~/wiki/` as the wiki root.

A user who places the wiki AT cwd (rare; happens when the user runs the
agent inside the wiki itself) gets a real `<cwd>/.wiki-config` with
`role = "main"` or `role = "project"` — handled by the same resolver
without any pointer indirection.

### `wiki-resolve.sh` (non-interactive)

A new script called by `wiki-capture.sh` at the start of every capture.
**`wiki-resolve.sh` is non-interactive: it never prompts.** It either
returns a list of wikis on stdout (one absolute path per line) and
exits 0, OR exits with one of these specific non-zero codes that
signal "I need user input":

- `10` — `~/.wiki-pointer` missing (need to run main-bootstrap prompt).
- `11` — cwd unconfigured (need to run per-cwd prompt).
- `12` — `.wiki-mode` says `main-only` or `both` but `~/.wiki-pointer`
  is `none`. Configuration error, recoverable only by user action.
- `13` — `.wiki-config` AND `.wiki-mode` both present at cwd (conflict
  state; see "Conflict precedence" below).

The non-interactive contract means tests, hooks, and headless contexts
can call the resolver without stalling. Prompting is the main agent's
job.

Pseudocode:

```
# Read main wiki pointer.
read $HOME/.wiki-pointer:
  - missing                 → exit 10 (need main-bootstrap prompt)
  - contains "none"         → main_wiki = "" (no main configured; OK)
  - contains <path>         → main_wiki = <path>
                              (verify path exists & has .wiki-config;
                               if missing, treat as if pointer were
                               missing → exit 10 with detail)

# Resolve cwd.
read cwd/.wiki-config:
  - present, role = "main" or "project"   → wiki_root = cwd
  - present, role = "project-pointer"     → wiki_root = cwd/<wiki> from config
  - absent                                → wiki_root = (none)

read cwd/.wiki-mode:
  - present, contains "main-only"  → mode = main-only
  - present, contains "both"       → mode = both
  - absent                         → mode = (none)

# Conflict precedence.
if wiki_root and mode:
  # Both files present in cwd. Two scenarios:
  if wiki_root == cwd  (cwd IS a wiki) AND mode == "both":
    # User chose "both" while standing inside their main or project
    # wiki itself. Honor it: this wiki + main_wiki (if main_wiki is
    # the wiki we're standing in, dedupe; just return [wiki_root]).
    if main_wiki and main_wiki != wiki_root:
      return [wiki_root, main_wiki]
    else:
      return [wiki_root]
  else:
    # Conflicting state. Exit 13; main agent must reconcile.
    exit 13

# Single source of truth.
if wiki_root:
  return [wiki_root]

if mode == "main-only":
  if main_wiki: return [main_wiki]
  else:         exit 12
if mode == "both":
  if main_wiki: return [<must-have-project-target>, main_wiki]
                # Mode = "both" without a project wiki at cwd is an
                # error: `wiki use both` always co-creates the project
                # wiki at write time, so reaching here means the user
                # deleted ./wiki/ manually. Exit 13 (conflict).
  else:         exit 12

# Unconfigured.
exit 11  (need per-cwd prompt)
```

The `wiki-capture.sh` wrapper interprets the exit code and runs the
appropriate prompt (or fails out cleanly in headless mode; see
"Headless contexts" below).

### Conflict precedence

The resolver's exit-13 cases handle the contradictions Codex and Opus
flagged:

- `.wiki-config` (project) + `.wiki-mode = both`: legal only when cwd
  is the wiki root itself AND user explicitly chose "both" to fan out
  to main; otherwise treated as conflict. The conflict-resolution path
  in `wiki-capture.sh` re-runs the per-cwd prompt with explicit
  language: *"You have a project wiki here AND a `both` mode marker.
  Pick: keep project-only / fork to main / abort and clean up
  manually."*
- `.wiki-mode = both` without a project wiki at cwd: should not happen
  via `wiki use both` (which always co-creates the project wiki); if
  it does, the user manually deleted `./wiki/`. Exit 13, prompt for
  recovery.

### `wiki use both` inside an existing wiki

`wiki use both` invoked inside an existing wiki (cwd has
`.wiki-config`) writes `.wiki-mode = both` at cwd. Captures from cwd
fork to the wiki at cwd AND `~/.wiki-pointer`'s main. This is the
"main-instance + main-pattern" workflow when the user's "project" wiki
happens to be the main wiki itself (rare but legal).

### `wiki use main` inside an existing wiki

Forbidden. The user is standing inside a wiki; demoting it to
"main-only" makes no sense. `wiki use main` errors with: *"Cwd is a
wiki (`role = X`). `main-only` mode would orphan it. To stop using
this wiki, `cd` out of it first."*

### cwd-only resolution

The resolver checks **only cwd**, not parents. Rationale unchanged from
prior version of this spec: walk-up has a known false-positive
(sibling wiki under `$HOME` claimed by every cwd under `$HOME`); cwd-
only avoids any boundary rule; mirrors `git init` / `npm init`. Per-
exact-cwd granularity is the user's responsibility — captures fired in
`~/proj/subdir/` do not honor `~/proj/.wiki-mode`.

### First-time main-wiki bootstrap (`wiki-init-main.sh`)

`wiki-capture.sh` runs this when `wiki-resolve.sh` exits 10. Two
prompts; the bootstrap is **interactive only when the main agent has a
user channel** (see "Headless contexts" below).

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

### Migration safety (revised)

Silent migration of pre-v2.4 setups happens only when **all** of these
hold:

1. `~/.wiki-pointer` is missing.
2. Exactly one directory at depth ≤ 2 within `$HOME` has a
   `.wiki-config` AND that config has `role = "main"`.
3. That directory's path matches the v2.4 expected layout (no symlink
   indirection that points outside `$HOME`).

If those hold, write `~/.wiki-pointer` with the discovered path; no
prompt. If two or more candidates exist (e.g., `~/wiki/` AND
`~/work-wiki/` both with `role = "main"`), or the discovered config has
`role = "project"` (someone made a project wiki their de-facto main),
fall through to the interactive bootstrap with a hint:

```
Found existing main wiki(s) at:
  - ~/wiki/
  - ~/work-wiki/
Which one should be the main wiki for v2.4 going forward?
  1) ~/wiki/
  2) ~/work-wiki/
  3) other (enter a path)
  4) none — project wikis only
```

`~/.wiki-pointer` is written with the chosen path (or `none`). The
non-chosen wiki(s) keep working as standalone projects (their own
`.wiki-config` is unchanged).

A symlink at `~/.wiki-pointer` that resolves outside `$HOME` is
honored if the target has a valid `.wiki-config`; if the target
doesn't exist, the resolver exits 10 (treats pointer as missing). The
bootstrap is offered fresh.

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

**Invalid input handling.** If the user replies with anything other than
the offered options, re-prompt up to 3 times with a brief reminder of
valid choices. After 3 invalid attempts, abort the capture, print *"Run
`wiki use project|main|both` to configure this directory and try
again,"* and leave the capture file in `.wiki-pending/` of the previous
session's last-resolved wiki (or, if none, in a new
`$HOME/.wiki-orphans/<timestamp>-<slug>.md` so the body isn't lost).

### Headless contexts

When the agent has no user channel (subagent dispatch, `claude -p`, CI
runner, anything where stdin is closed or `CLAUDE_HEADLESS=1`), the
resolver and bootstrap MUST NOT prompt. `wiki-capture.sh` checks for a
user channel before prompting. Detection rules (any one means
"headless"):

- `WIKI_CAPTURE` env var is set (we are inside a spawned ingester —
  treat as headless; capture-write is forbidden anyway).
- `CLAUDE_HEADLESS=1` env var is set.
- `stdin` is not a TTY AND no `CLAUDE_AGENT_INTERACTIVE=1` env.
- The agent's spawn context indicates subagent (we read
  `CLAUDE_AGENT_PARENT` if set; presence means subagent).

Headless fallback rules, picked to be safe-by-default:

- Resolver exit 10 (pointer missing) → write `~/.wiki-pointer` with
  `none`, log warning to `.ingest.log` of `$HOME/.wiki-orphans/`,
  proceed without a main wiki.
- Resolver exit 11 (cwd unconfigured) AND `~/.wiki-pointer` valid →
  use main-only as default; write `<cwd>/.wiki-mode = main-only`. Log
  warning *"headless mode auto-selected main-only for cwd; user can
  override with `wiki use project|both`."*
- Resolver exit 11 AND `~/.wiki-pointer = none` → abort the capture
  with explicit error; the capture body is preserved at
  `$HOME/.wiki-orphans/<timestamp>-<slug>.md`.
- Resolver exit 12 / 13 (configuration errors) → abort with explicit
  error and orphan-preservation. These cases require user judgment;
  no safe default.

The orphan preservation step is what prevents capture loss in
headless contexts: the body is never thrown away, only set aside for
the user to reconcile.

### `.wiki-mode` marker file

A small file in cwd containing one of two strings on its first line:

- `main-only`
- `both`

No other contents. Optional second line: `# created YYYY-MM-DD by wiki use`.

The "project" choice does not write `.wiki-mode` — it writes
`<cwd>/.wiki-config` with `role = "project-pointer"` and the project
wiki itself at `<cwd>/wiki/`. The resolver detects project mode via
the pointer config.

### `wiki use` CLI

Three subcommands:

- `wiki use project` — if `<cwd>/wiki/` doesn't exist, run
  `wiki-init.sh project <cwd>/wiki <main_or_none>`. Write
  `<cwd>/.wiki-config` with `role = "project-pointer"`. Remove
  `.wiki-mode` if present.
- `wiki use main` — refuse if cwd has `.wiki-config`. Otherwise write
  `.wiki-mode` containing `main-only`. Print warning if `<cwd>/wiki/`
  exists from a prior project mode ("local wiki kept; captures will no
  longer go there; `rm -rf <cwd>/wiki` to remove it").
- `wiki use both` — if `<cwd>/wiki/` doesn't exist, init it (and write
  pointer config). Write `.wiki-mode` containing `both`. Refuse if
  `~/.wiki-pointer` is `none` (no main wiki to fork to).

Idempotent: re-running with the current mode is a no-op.

The `using-karpathy-wiki` loader includes a one-line directive: *"When
the user asks to change wiki mode for this directory (phrases like 'use
project wiki here,' 'main only,' 'switch to both'), run
`wiki use <mode>` and confirm."*

### Standalone project wikis (no main)

`wiki-init.sh project <path>` is extended to accept a missing main
argument. When invoked without a main, it writes `.wiki-config` with
`role = "project"` but **no `main` field**. The propagation mechanism
(out-of-scope for v2.4) treats absent `main` as "no propagation
target." This makes "project-only" a first-class state, not a
degraded form of "project + main."

The existing `wiki-init.sh` validation in `scripts/wiki-init.sh:33-35`
is changed: project mode no longer requires a main path. A new error
case is added: when the wiki path being initialized already exists
with a `.wiki-config`, the script is a no-op (idempotency preserved).

### Forking on capture

When the resolver returns multiple wikis (mode `both`), `wiki-capture.sh`
writes the **same capture body into each wiki's `.wiki-pending/`**.
Filenames are independent (each wiki generates its own
`<timestamp>-<slug>.md`). Each wiki's ingester claims its own copy and
runs independently. No cross-ingester coordination, no locking
complications.

**Partial-failure semantics.** Each spawn-ingester invocation produces
a per-wiki run record at `<wiki>/.ingest-runs.jsonl`:

```json
{"run_id": "in-1746458591-abc123", "capture": "...", "started_at": "...", "status": "spawned"}
```

When the ingester finishes (or crashes), it appends a closing record:

```json
{"run_id": "in-1746458591-abc123", "status": "completed|failed", "ended_at": "...", "exit_code": 0}
```

`wiki-capture.sh` writes a fork-coordination record at
`$HOME/.wiki-forks.jsonl` when mode `both` is in effect:

```json
{"fork_id": "fk-...", "captured_at": "...", "wikis": ["/Users/.../proj/wiki", "/Users/.../wiki"], "captures": [".wiki-pending/...", ".wiki-pending/..."]}
```

This makes asymmetric outcomes observable: `wiki status` reads
`.ingest-runs.jsonl` and `~/.wiki-forks.jsonl` and reports e.g. *"fork
fk-... — project succeeded, main pending."* No automatic retry in
v2.4; the user can run `wiki ingest-now <wiki>` to retry the failed
side. Stalled-capture recovery (existing v2.1 mechanism) eventually
reclaims the failed capture on the next SessionStart of the failed
wiki's directory.

### Test surface

- Fresh cwd outside any wiki, no `~/.wiki-pointer`: bootstrap fires,
  asks Q1 and Q2, writes pointer, then asks per-cwd prompt.
- Fresh cwd outside any wiki, `~/.wiki-pointer` contains `none`:
  per-cwd prompt collapsed (project only).
- Fresh cwd outside any wiki, `~/.wiki-pointer` valid: full per-cwd
  prompt (1/2/3).
- Cwd has `.wiki-config` (`role = "project-pointer"` pointing at
  `./wiki`): resolver returns the resolved wiki path silently.
- Cwd has `.wiki-mode = both`: resolver returns [project wiki, main
  wiki].
- Cwd has `.wiki-config` AND `.wiki-mode = both`: resolver handles
  per "Conflict precedence."
- `wiki use main` inside an existing wiki: errors with explicit
  message.
- `wiki use both` when `~/.wiki-pointer = none`: errors.
- Headless context (CLAUDE_HEADLESS=1) with unconfigured cwd: capture
  body preserved at orphan path; explicit warning logged.
- User types invalid input at prompt 4 times: capture aborts; body
  preserved at orphan path.
- Two `~/wiki/` and `~/work-wiki/` both with `role = "main"`: silent
  migration declines; bootstrap prompts for choice.
- Symlink `~/.wiki-pointer` → broken target: resolver exit 10;
  bootstrap re-runs.

---

## Leg 3 — Raw-direct ingest (unified Clippings + subagent-report flow)

### Source classes

Three categories of "file is the source" cases all funnel through one
mechanism:

| Source | Where it lands | How it gets there |
|---|---|---|
| Obsidian Web Clipper | `<wiki>/Clippings/` | external app drops file |
| Research subagent report | `<wiki>/Clippings/` | main agent moves the file (single command — see below) |
| Drift in `raw/` | already in `<wiki>/raw/`; manifest sha mismatch | external edit / replacement of an existing raw |

### `Clippings/` is a queue, `raw/` is the archive

`<wiki>/Clippings/` is the **drop zone**: a transient queue. Any file
present in `Clippings/` is by definition unprocessed; once an ingester
runs, the file is moved to `raw/<basename>` and removed from
`Clippings/`. There is no separate "Clippings manifest" — durable
state lives in `raw/.manifest.json` exactly as today.

This is the central simplification:

- **Detection rule:** `ls <wiki>/Clippings/*.md` (and other supported
  extensions). Any file present is queue-pending.
- **Ingest action:** for each queue file, create a raw-direct capture
  in `<wiki>/.wiki-pending/`, spawn an ingester. The ingester reads
  the file from `Clippings/`, copies to `raw/`, registers in
  manifest, removes from `Clippings/`, writes the wiki page,
  archives the capture.
- **Idempotency:** re-running the scan over an empty `Clippings/`
  is a no-op. If a file appears in `Clippings/` while an ingester is
  processing a sibling, it gets handled in the next scan iteration —
  no need to coordinate.

The `raw/` drift-scan path (existing v2.x behavior) handles cases
where a file in `raw/` has been replaced/edited externally. That
remains separate from `Clippings/` queue processing — they share the
ingester but use different detection mechanisms.

### Concurrent SessionStart safety

Two SessionStart hooks firing concurrently (user opens two terminals)
would both see the same `Clippings/foo.md`. The capture filename is
deterministic from the source path:

```
capture_filename = drift-<sha12(absolute_path)>-<slugified-basename>.md
```

This is the existing `_drift_scan` filename convention in
`hooks/session-start:58-62`, extended to `Clippings/`. The atomic
`set -C` create (`hooks/session-start:67`) makes the second hook's
attempt fail silently — exactly the deduplication v2.x already relies
on for `raw/` drift.

The `WIKI_CAPTURE` fork-bomb guard (`hooks/session-start:21-23`)
unchanged: spawned ingesters skip the hook entirely.

### Partial-write race (rsync, unzip, etc.)

A file in `Clippings/` may be in the middle of being written (rsync
hasn't finished, an editor is auto-saving, an unzip is extracting).
The hook adds an mtime check: **skip files whose mtime is within the
last 5 seconds.** They get picked up on the next SessionStart or
`wiki ingest-now` invocation.

5 seconds is an arbitrary safety floor; it covers most user-driven
saves and small file copies. Long-running operations (large rsync,
multi-MB extractions) are user responsibility — they should drop into
a staging directory and `mv` into `Clippings/` when done.

### Subagent-report workflow (main agent's responsibility)

When a research subagent returns a file with durable findings, the
main agent's job is **not** to write a capture body summarizing the
report. The report IS the capture. The main agent runs:

```bash
mv <subagent-report-path> <wiki>/Clippings/<basename>
wiki ingest-now <wiki>          # or wait for next SessionStart
```

`wiki ingest-now` is a CLI wrapper around the same drift-scan + drain
function that SessionStart uses. It's the on-demand path for the case
where the user is still in the active session and wants the report
ingested before they close the terminal.

The capture skill (`karpathy-wiki-capture/SKILL.md`) explicitly
instructs:

> **Subagent reports.** When a research subagent returns a file with
> durable findings, do NOT write a chat-style capture body. Move the
> file into `<wiki>/Clippings/<basename>` and run `wiki ingest-now
> <wiki>`. The ingester reads the file directly. Subagent-report
> bodies frequently exceed several KB; rewriting them as a capture
> body wastes tokens and produces inferior wiki pages.

This is the third specific anti-pattern the spec addresses (alongside
the prose-not-script auto-load gap and the project-wiki resolver gap):
forcing the agent to fabricate a wrapper body when the source already
exists.

### Capture format for raw-direct

The capture is auto-generated by the SessionStart hook (or
`wiki ingest-now`):

```markdown
---
title: "Drop: <basename>"
evidence: "<absolute path to file in Clippings/ OR raw/>"
evidence_type: "file"
capture_kind: "raw-direct"
suggested_action: "auto"
suggested_pages: []
captured_at: "<ISO-8601 UTC>"
captured_by: "session-start-drop"  # or "wiki-ingest-now"
origin: null
---

Auto-ingest of file in <Clippings|raw>/. The raw file at `evidence`
is the canonical source; this body is auto-generated and intentionally
minimal. Action for the ingester: read the raw file, infer category
from content, decide create vs augment, file under appropriate
category. If the raw file looks like an Obsidian Web Clipper export
(has source/created/published frontmatter), preserve those fields.
```

### `capture_kind` enum (canonical)

The `capture_kind` field is canonical and mandatory in v2.4-and-later
captures. Three values:

- `raw-direct` — file is the source. Body is auto-generated. No body
  floor. The ingester reads the file and decides.
- `chat-attached` — chat surfaced material AND there's a supporting
  file. Body must clear 1000-byte floor (the existing
  `evidence_type: mixed` rule). The body documents what the
  conversation added that the file doesn't cover.
- `chat-only` — no file; body IS the evidence. Body must clear
  1500-byte floor (the existing `evidence_type: conversation` rule).

The `evidence_type` field stays for backward compatibility but
becomes derivable from `capture_kind`:

| `capture_kind` | `evidence_type` | Body floor |
|---|---|---|
| `raw-direct` | `file` | none |
| `chat-attached` | `mixed` | 1000 b |
| `chat-only` | `conversation` | 1500 b |

A capture missing `capture_kind` (pre-v2.4 capture file lying around)
is treated as follows: if `evidence` is a path → `chat-attached` (the
old `file`/`mixed` semantic with mandatory 200-byte floor for the
file case is dropped — pre-v2.4 file-type captures already had
auto-generated bodies that were thin); if `evidence` is the literal
`conversation` → `chat-only`.

The validator enforces `capture_kind` presence on new captures
written by v2.4-and-later code; legacy captures pass through with the
backward-compat rule.

### Body sufficiency (consolidated)

| `capture_kind` | Body floor | Body source |
|---|---|---|
| `raw-direct` | none | hook-generated boilerplate |
| `chat-attached` | 1000 b | main agent writes (the conversation-delta) |
| `chat-only` | 1500 b | main agent writes (the conversation IS the evidence) |

Drift captures (existing v2.x mechanism that creates a capture when
`raw/<file>` sha changes) are also `capture_kind: raw-direct`. Their
body has been auto-generated since v2.x; this just labels them
correctly.

### Lens for raw-direct

The wiki's role determines the lens (same as chat-driven captures). A
file dropped into a project wiki's `Clippings/` gets project-lens
ingestion; a file dropped into a main wiki's `Clippings/` gets
main-lens ingestion. **Drops do NOT fork** — the user picked the wiki
by picking the directory. If the user wants the same file in both,
they drop into both manually.

### Failure modes

- File is binary / unreadable: ingester writes an issue
  (`issue_type: other`, severity `warn`, detail `cannot read raw
  file`), archives the capture, does not commit a page. The file
  stays in `Clippings/` so the user can investigate (NOT moved to
  `raw/`).
- File is empty: same.
- File is a duplicate of an existing raw (sha256 already in
  manifest): ingester logs (`raw-ingest | skipped duplicate`),
  removes the file from `Clippings/`, archives the capture.
- File mtime is within the last 5 seconds: hook skips it for this
  scan iteration.
- File contains valid YAML frontmatter that conflicts with v2.4
  schema: ingester writes an issue (`issue_type: schema-drift`),
  proceeds with best-effort parsing.

### Test surface

- Drop a markdown file into `Clippings/`. Next session start:
  capture appears in `.wiki-pending/`; ingester runs; page committed;
  raw is in `raw/`; manifest updated; `Clippings/` is empty.
- `wiki ingest-now` triggers same flow on demand without waiting for
  SessionStart.
- Drop the same file twice (different content, same basename):
  second SessionStart sees a different sha → second raw-direct
  capture; the existing overwrite-detection logic (in current
  ingester) handles the merge.
- Two SessionStarts fire concurrently with the same file in
  `Clippings/`: deterministic capture filename + atomic `set -C`
  ensures one wins, the other no-ops.
- File in `Clippings/` with mtime now: hook skips; next scan picks it
  up.
- Subagent report at `/tmp/foo-report.md` → main agent runs
  `mv ... <wiki>/Clippings/ && wiki ingest-now <wiki>` → page
  committed without main agent writing a capture body.
- Binary file in `Clippings/`: issue logged; file stays in
  `Clippings/`; no page written.

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
4. **From the capture, extract candidate signals:**
   - Words and phrases from the capture title.
   - Frontmatter `tags:` (if any).
   - For `chat-only` and `chat-attached` captures: meaningful nouns
     and proper-noun phrases from the body (the ingester is an LLM;
     it picks them by judgment, not regex).
   - For `raw-direct` captures: filename basename + the file's first
     200 lines.
5. **Score candidates against the index.** A page is a candidate if:
   - Any extracted signal substring-matches its title (case-insensitive),
     OR
   - Any signal matches its tags (exact, case-insensitive),
     OR
   - The signal appears in the page's `_index.md` one-line summary.
6. **Pick up to 7 candidates** ordered by signal-match count
   (descending), title-length (ascending; shorter titles rank higher
   for the same match count — they are more general). Tie-break:
   alphabetical by title.
7. **Read all picked candidates in full** (zero is a valid count for a
   small or fresh wiki — see "Cold start" below).
8. Decide: create new, augment existing, or no-op (existing already
   covers).
9. While reading in step 7, observe issues (broken links,
   contradictions, schema drift, stale claims, tag drift, quality
   concerns, orphans). Append each to `.ingest-issues.jsonl` via
   `wiki-issue-log.sh`. **Don't fix them inline; report only.**

### Cold start

Wikis with fewer than 8 pages don't have enough gravity for the index
to shape the lens. In this case, the candidate list is short or empty,
and the role-guardrail at the prompt tail becomes the primary lens
mechanism, not a backup. The ingest skill explicitly states:

> If the candidate list is empty (fresh or near-fresh wiki), the
> `role` field in `.wiki-config` is your primary lens, not a tripwire.
> A `role: project` ingester writes specifics about THIS codebase /
> instance / situation; a `role: main` ingester writes general
> patterns. Defer cross-linking to a future ingester run.

This makes the lens claim load-bearing in two zones: index-pull when
the wiki has > 8 candidate-eligible pages, role-prompt when it
doesn't. The transition is gradual — the role hint stays in the
prompt at all times; its weight in the agent's behavior naturally
declines as the index gravity grows.

### Why this matters for the lens claim

Steps 6-7 are what make the project/main lens emergent in mature
wikis. Reading 5 pages about "our auth flow" pulls the next page's
writing toward instance-style specificity. Reading 5 pages about "FFI
patterns" pulls toward general abstraction. In small wikis the index
pull is weak and `role` carries the lens. The two mechanisms together
cover both cold and warm states.

### Why not embeddings / vector search

Substring + tag match is deterministic, scriptable, testable, and
cheap. Embedding-based candidate selection (the obvious "smart"
upgrade) would shift this skill into vector-store territory, which
CLAUDE.md explicitly carves out: *"do not add: vector search (defer
until genuine scaling pain)."* The substring/tag approach degrades
gracefully — at large scale it hits more candidates than 7, but the
ranking still produces a usable top-7. When that breaks, vector
search becomes worth its complexity; not before.

### Cost

3-7 extra file reads per ingestion (zero on cold-start wikis). Each
page is typically 5-20 KB. The ingester is already reading the
capture and the schema; this is the same order of magnitude. No
measurable spawn-time impact.

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

The script:

1. Validates the `--type` value against the enum (8 known types).
2. Formats the JSON object using `python3 -c 'import json,sys; ...'`
   to handle escaping correctly (no shell-quoting bugs in `detail`).
3. **Acquires an exclusive `flock` on
   `<wiki>/.locks/ingest-issues.lock`** before appending the line.
4. Appends the line using `printf "%s\n" "$JSON" >> ...`.
5. Releases the lock.

Why `flock` not "POSIX append atomicity": `O_APPEND` on a regular
file is atomic for the *position write*, not for arbitrarily long
content. `PIPE_BUF` applies to pipes, not regular files. With
multiple ingesters appending to the same file, only `flock` (or
`fcntl.lockf`) gives us the actual guarantee.

**Max line length: 4 KB.** The helper truncates `detail` if the
overall JSON line would exceed 4 KB, with `... [truncated]` suffix.
This keeps the per-line write under any plausible OS-level atomic
write boundary and prevents one bad issue from corrupting the log.

### Manifest mutations: `wiki-manifest-lock.sh`

Issue logs are not the only concurrent-write surface. The existing
`.manifest.json` is rewritten wholesale by `wiki-manifest.py` (no
lock today). With v2.4's raw-direct path producing more concurrent
ingestions (especially in `both` mode), two ingesters can clobber
each other's manifest writes.

`wiki-manifest-lock.sh` is a flock wrapper that serializes:

- All `wiki-manifest.py` invocations (build, diff, register).
- All direct manifest reads followed by writes from ingester scripts.

Implementation: a thin script that acquires
`<wiki>/.locks/manifest.lock` via `flock`, runs the wrapped command
as a child, releases on exit. All v2.4 ingester code paths that
touch the manifest go through this wrapper. The Python side
(`wiki-manifest.py`) gets a `--lock` flag that does the same with
`fcntl.flock` for in-process callers.

Write pattern: read manifest → mutate in memory → write to
`.manifest.json.tmp` → atomic `os.rename` to `.manifest.json`. The
rename gives crash-safety on top of the lock's serialization.

Test: spawn two ingesters writing distinct raw files in parallel;
assert final manifest contains both entries with correct
`origin`/`referenced_by`/`last_ingested`.

### `wiki doctor` consumes this later

Out of scope for v2.4 (still stubbed). When implemented, `wiki doctor`
reads `.ingest-issues.jsonl` as its work queue: each issue is a candidate
fix.

---

## Data flow end-to-end

### Single capture entry point: `wiki capture`

All chat-driven captures go through **one CLI**: `wiki capture`. The
agent never writes directly to `.wiki-pending/`; never invokes
`wiki-resolve.sh` directly; never spawns an ingester directly. This
makes the resolver's invocation as guaranteed as the script's
existence, the central architectural fix v2.4 is built around.

`wiki capture` reads a body from stdin and metadata from CLI flags:

```bash
wiki capture \
  --title "USB 3.x version-rename gotcha" \
  --kind chat-only \
  --evidence conversation \
  --suggested-action create \
  <<< "$BODY"
```

What it does internally:

1. Calls `wiki-resolve.sh` (non-interactive) to determine target
   wiki(s).
2. If resolver exits 10/11/12/13, runs the appropriate prompt
   (interactive context) or applies the headless fallback rule
   (headless context).
3. For each target wiki, writes a capture file at
   `<wiki>/.wiki-pending/<timestamp>-<slug>.md` with body + auto-
   generated frontmatter (timestamp, captured_by, resolved
   `capture_kind`, etc.).
4. Spawns one detached ingester per target via
   `wiki-spawn-ingester.sh`.
5. Writes a fork-coordination record to `~/.wiki-forks.jsonl` if
   multiple targets.
6. Returns immediately (no foreground wait).

The capture skill (`karpathy-wiki-capture/SKILL.md`) instructs the
agent: *"to capture, run `wiki capture` with title, kind, and the
body on stdin. Never write to `.wiki-pending/` directly."*

### Capture (chat-driven)

```
user says something wiki-worthy
  ↓
main agent (skill rules force-loaded by SessionStart hook)
  ↓
agent loads karpathy-wiki-capture skill on-demand
  ↓
agent runs `wiki capture --title ... --kind ... <<< "$BODY"`
  ↓
wiki capture calls wiki-resolve.sh
  ↓
resolver exits 0 (returns wikis) OR 10-13 (needs prompt)
  ↓
wiki capture handles prompt OR headless fallback
  ↓
wiki capture writes capture(s) to <wiki>/.wiki-pending/<timestamp>.md
  ↓
wiki capture spawns one ingester per target wiki
  ↓
detached claude -p ingester(s) start (ingester skill loaded via spawn prompt)
  ↓
ingester runs deep orientation (schema + index + log + 0-7 pages)
  ↓
ingester writes / augments / no-ops; appends issues to JSONL
  ↓
ingester commits, archives the capture, writes fork run record
```

### Capture (raw-direct via Clippings drop)

```
user (or external tool) drops file into <wiki>/Clippings/<basename>
  OR main agent moves a subagent report there
  ↓
next SessionStart fires (OR user runs `wiki ingest-now <wiki>`)
  ↓
hook scans <wiki>/Clippings/ and <wiki>/raw/ for unmanifested or sha-mismatched files
  ↓
for each: hook creates raw-direct capture in .wiki-pending/
  (filename = drift-<sha12(absolute_path)>-<slug>.md; atomic via set -C)
  ↓
hook calls wiki-spawn-ingester.sh per capture
  ↓
detached claude -p ingester reads the file in Clippings/ (NOT the capture body)
  ↓
ingester runs deep orientation (lens shaped by wiki role)
  ↓
ingester writes/augments/no-ops; copies Clippings/<basename> → raw/<basename>;
  updates manifest (under flock); removes file from Clippings/
  ↓
ingester commits, archives the capture, appends issues to JSONL
```

### Capture (subagent report)

```
research subagent returns a file at /tmp/foo-report.md
  ↓
main agent: `mv /tmp/foo-report.md <wiki>/Clippings/foo-report.md`
  ↓
main agent: `wiki ingest-now <wiki>`
  ↓
(falls through to "Capture (raw-direct via Clippings drop)" above)
```

---

## Error handling

| Failure | Behavior |
|---|---|
| `~/.wiki-pointer` missing on first capture (interactive) | bootstrap prompt fires (Q1: yes/no main wiki; Q2: where); pointer written; capture proceeds |
| `~/.wiki-pointer` missing (headless) | pointer written with `none`; warning logged to `~/.wiki-orphans/.ingest.log`; capture proceeds with main = none |
| `~/.wiki-pointer` valid but path is broken (symlink to deleted dir) | resolver exits 10; bootstrap re-prompts; user can repoint or set to none |
| Multiple candidate main wikis at depth ≤ 2 in $HOME | silent migration declines; bootstrap prompts user to choose |
| Cwd unconfigured (interactive) | per-cwd prompt fires (1/2/3); marker written; capture proceeds |
| Cwd unconfigured (headless) AND main exists | auto-select main-only; write `.wiki-mode = main-only`; warning logged |
| Cwd unconfigured (headless) AND main = none | abort capture; body preserved at `~/.wiki-orphans/<timestamp>-<slug>.md` |
| `~/.wiki-pointer = none` AND user picks "main" or "both" | re-prompt with "main wiki not configured; pick project or run `wiki-init-main.sh`" |
| `.wiki-config` AND `.wiki-mode = both` (legal: cwd is wiki root, both selected) | resolver returns [cwd, main] |
| `.wiki-config` AND `.wiki-mode = both` (illegal: cwd not wiki root) | resolver exits 13; conflict-resolution prompt |
| `.wiki-mode = both` without project wiki at cwd (user deleted ./wiki/ manually) | resolver exits 13; conflict-resolution prompt |
| `wiki use main` inside an existing wiki (cwd has `.wiki-config`) | refuse with explicit error message |
| `wiki use both` when `~/.wiki-pointer = none` | refuse with explicit error message |
| User types invalid input at per-cwd prompt | re-prompt up to 3 times; on 4th invalid, abort and orphan-preserve |
| Spawn fails (no `claude` binary, etc.) | capture stays in `.wiki-pending/`; existing reclaim logic picks it up next session |
| Spawn succeeds for one wiki in `both` mode but fails for the other | per-wiki run record reflects asymmetric outcome; `wiki status` shows fork mismatch; user can `wiki ingest-now <failed-wiki>` to retry |
| Raw-direct file is binary / empty | issue logged; file stays in Clippings/ for user inspection; no page written |
| Raw-direct file mtime within last 5 seconds | hook skips this scan iteration; next scan picks up |
| Two SessionStarts fire concurrently | deterministic capture filename + atomic `set -C` create dedupe; no double-ingest |
| `.ingest-issues.jsonl` write fails (disk full, permission, etc.) | log to `.ingest.log` and continue (issue tracking is best-effort) |
| `.ingest-issues.jsonl` flock acquisition fails after 30 s | log warning; skip this issue line; continue ingestion |
| Manifest write race | resolved by `wiki-manifest-lock.sh` flock; serializes writers |
| Deep orientation candidate page is malformed YAML | issue logged (`schema-drift`); ingester continues with remaining candidates |
| Cwd / wiki path contains spaces or unicode | every script uses `"$VAR"` quoting consistently; tested with fixture path containing spaces |
| Cwd is read-only (cannot write `.wiki-mode`) | abort capture with error; orphan-preserve body |

---

## Testing

Per `superpowers:writing-skills` RED-GREEN-REFACTOR discipline.

### Unit tests (per-script, table-driven)

- `wiki-resolve.sh` — exit-code table covering all branches:
  - pointer missing → 10
  - pointer = none + cwd has `.wiki-config` → 0, returns cwd wiki
  - pointer = none + cwd unconfigured → 11 (with no main option in subsequent prompt)
  - pointer valid + cwd has `.wiki-config` (`role = "project-pointer"`) → 0, returns resolved path
  - pointer valid + cwd `.wiki-mode = main-only` → 0, returns main
  - pointer valid + cwd `.wiki-mode = both` → 0, returns [project, main]
  - cwd has BOTH `.wiki-config` AND `.wiki-mode = both`, cwd is wiki root → 0, returns [cwd-wiki, main]
  - cwd has BOTH `.wiki-config` AND `.wiki-mode = both`, cwd is NOT wiki root → 13
  - cwd `.wiki-mode = main-only` + pointer = none → 12
  - cwd `.wiki-mode = both` + pointer = none → 12
  - cwd `.wiki-mode = both` + no project wiki at cwd → 13
  - pointer is broken symlink → 10
  - 12+ cases minimum.
- `wiki-init-main.sh` — fresh-state prompt flow, single-candidate silent migration, multi-candidate prompt, "none" path, pointer-already-exists no-op.
- `wiki-use.sh` — 3 subcommands × idempotency × already-configured states × refusal cases (`wiki use main` in existing wiki; `wiki use both` with no main).
- `wiki-init.sh` — new standalone-project mode (no main path argument); existing main and project-with-main paths still pass.
- `wiki-issue-log.sh` — enum validation, JSON formatting (special chars in detail), max-line-length truncation, flock-serialized concurrent appends (spawn 5 parallel writers, assert all 5 lines present and well-formed).
- `wiki-issues.sh` — render correctness, `--filter` and `--since` flags, empty log handling, JSONL with corrupted line (skip + warn).
- `wiki-capture.sh` — happy-path single-wiki write; both-mode produces two captures; headless mode applies fallback; orphan-preserve on abort.
- `wiki-ingest-now.sh` — calls drift-scan + drain; on-demand equivalent of SessionStart drop-zone behavior.
- `wiki-manifest-lock.sh` — concurrent manifest mutations from two writers produce consistent final state.

### Integration tests

- **Chat capture, project mode (interactive):** fresh cwd, simulated user picks "project" → `./wiki/` and `./.wiki-config` (project-pointer) created, capture lands, ingester runs, page committed.
- **Chat capture, both mode (interactive):** fresh cwd, simulated user picks "both" → two captures, two ingesters, two pages, fork-coordination record in `~/.wiki-forks.jsonl`.
- **Chat capture, headless mode, main exists:** auto-select main-only, capture proceeds without prompt, `.wiki-mode = main-only` written.
- **Chat capture, headless mode, no main:** capture aborts; body preserved at `~/.wiki-orphans/<timestamp>-<slug>.md`.
- **Conflict resolution:** create cwd with both `.wiki-config` and `.wiki-mode = both`, where cwd is NOT the wiki root (project-pointer to `./wiki/` AND `.wiki-mode` markers both present). Resolver exits 13; `wiki capture` re-prompts.
- **Both-mode partial failure:** capture in both mode, but main wiki has bad permissions on `.wiki-pending/`. Project ingester runs; main spawn fails. `wiki status` reports asymmetric outcome.
- **Raw-direct, Clippings drop:** drop a markdown file → next SessionStart → page emerges, raw is in `raw/` with manifest, `Clippings/` is empty.
- **Raw-direct, on-demand:** same as above but via `wiki ingest-now <wiki>` instead of waiting for SessionStart.
- **Raw-direct, subagent report:** `mv` a fixture file into `<wiki>/Clippings/` then run `wiki ingest-now`; assert page emerges; assert main agent never wrote a capture body.
- **Concurrent SessionStart:** two SessionStarts fire on the same wiki with the same file in `Clippings/`; assert exactly one capture is created (deterministic filename + atomic create).
- **Partial-write race:** `touch` a file in Clippings/, run SessionStart immediately; hook skips it (mtime within 5s). Sleep 6s, re-run; hook picks it up.
- **Path with spaces/unicode:** fixture wiki path `/tmp/wiki test ünicode/` exercises every script; assert no failures.
- **Symlink wiki path:** `~/.wiki-pointer` → symlink → real wiki directory; resolver follows correctly.
- **Migration: single existing wiki at `~/wiki/`:** silent; pointer written.
- **Migration: two existing wikis under `$HOME`:** prompt fires; user picks one; pointer written; non-chosen wiki untouched.
- **Migration: pre-v2.4 captures with no `capture_kind`:** ingester applies backward-compat rule (file evidence → `chat-attached`; `conversation` → `chat-only`) without rejection.
- **Issue reporting:** ingest a capture against a wiki with a known broken link in a candidate page; verify a JSONL line appears with `issue_type: broken-cross-link`. Verify max-line-length truncation works on a 5 KB detail.
- **Cold-start orientation:** ingest into a fresh wiki with 0-7 pages; verify ingester completes without failing the "candidate count" gate; role-prompt lens visible in commit message rationale.
- **Loader injection:** SessionStart hook output contains `additionalContext` with the loader body wrapped in `<EXTREMELY_IMPORTANT>` (asserted by reading hook stdout in fixture). Subagent context (`WIKI_CAPTURE` set OR `CLAUDE_AGENT_PARENT` set) → no `additionalContext` in output.
- **`wiki issues` rendering:** 5 fixture issues across 3 types → assert grouping, severity ordering, format.

### Pressure tests (skill-rule level)

For each skill prose change, write a "RED scenario" — a transcript
fragment showing an agent failing the rule, demonstrating why the rule
is needed before adding it. Concrete pressure scenarios required for
v2.4:

- **Lens claim under cold start:** A/B fixture — same capture, two
  fresh wikis (one `role: project`, one `role: main`), assert outputs
  diverge in expected ways even with empty index.
- **Lens claim under warm state:** same A/B but with 12+ existing
  pages each, assert index-pull moves the lens further than the role
  hint alone.
- **Skill split duplication:** scan capture/ingest skills for
  substring overlap > 80 words outside `references/`; fail CI.
- **Subagent skill load:** simulate a subagent context, assert
  loader is NOT in additionalContext.

---

## Migration

### From v2.3 to v2.4

Migration is governed by the safe-by-default rules in "Migration
safety (revised)" above. Concretely:

1. **Single existing main wiki at `~/wiki/` (or any unique
   `*/.wiki-config` with `role = "main"` at depth ≤ 2 in `$HOME`):**
   silent migration. Pointer written; no prompt.
2. **Multiple candidate main wikis OR ambiguous setup:** bootstrap
   prompts the user. Non-chosen wikis remain functional standalone.
3. **`skills/karpathy-wiki/SKILL.md` split into three new skills:**
   the old skill remains in place during the transition (does not
   immediately disappear), but its frontmatter description gets
   updated to point at the new skills. The old SKILL.md is removed
   in a separate cleanup commit *after* v2.4 has shipped and the new
   skills are verified working in the wild.
4. **`hooks/hooks.json`** already references the SessionStart hook.
   Only the hook body changes.
5. **`.ingest-issues.jsonl`** is created lazily on first write. No
   schema migration needed.
6. **Existing `.wiki-pending/` captures (pre-v2.4 format)** continue
   to work. Their frontmatter doesn't carry `capture_kind`; the
   ingester applies the backward-compat rule:
   - `evidence: <path>` → treated as `capture_kind: chat-attached`
     (1000-byte body floor).
   - `evidence: conversation` → treated as `capture_kind: chat-only`
     (1500-byte body floor).
   New captures written by v2.4 always include `capture_kind`.
7. **Existing v2.x drift captures** (auto-generated when `raw/<file>`
   sha changes) gain the `capture_kind: raw-direct` label going
   forward. Pre-existing drift captures still in `.wiki-pending/`
   are processed by the backward-compat rule above.
8. **`wiki-init.sh`** is changed to allow project mode without a
   main argument (new `wiki-init.sh project <path>` form). The
   existing `wiki-init.sh project <path> <main>` form continues to
   work. Tests cover both forms.

### Rollback

Each leg is independently revertable:

- Auto-load: revert the SessionStart hook change, revert the
  loader-skill creation, revert the skill-split. The original
  `karpathy-wiki/SKILL.md` is still present (per migration step 3
  above) and continues to work.
- Resolver: revert `wiki-resolve.sh`, `wiki-capture.sh`, `wiki-use.sh`.
  Capture flow falls back to `wiki_root_from_cwd` (with its known
  bugs — but those bugs predate v2.4 and aren't worse than rollback's
  starting state).
- Raw-direct: revert the SessionStart drift-scan extension to
  `Clippings/`. Files in `Clippings/` are silently ignored as
  before. `wiki ingest-now` is a separate CLI; reverting it doesn't
  affect the rest.
- Issue reporting: revert `wiki-issue-log.sh`, `wiki-issues.sh`, and
  the ingest-skill changes that call them. The `.ingest-issues.jsonl`
  file remains on disk but unused; safe to keep or delete.

Per CLAUDE.md ("migrations use multiple commits with verification
gates"), each leg ships in its own commit cluster with tests passing
between commits. Verification gate after each leg:

- After leg 1: fresh-session test — loader present in
  `additionalContext`; subagent dispatch — loader absent.
- After leg 2: per-cwd-prompt test (three interactive modes
  end-to-end); headless fallback test; conflict-resolution test.
- After leg 3: drop-and-go test (Clippings/ → page); on-demand
  `wiki ingest-now`; subagent-report move-and-ingest workflow.
- After deep orientation + issue reporting: candidate-selection
  determinism test; issue-log atomicity test; cold-start lens test.

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

### Rich `wiki issues` rendering

v2.4 ships a basic markdown render (grouped by type, severity-ordered).
v2.5 can add `--filter`, `--since`, `--by-page`, terminal coloring, and
deeper integration with `wiki status`. The basic render is sufficient
for `wiki doctor`'s eventual consumption; richer surface is for human
debuggers.

### `wiki use main --remove-local`

Currently `wiki use main` warns about leftover `<cwd>/wiki/` from a
prior project mode but does not remove it. A `--remove-local` flag is
straightforward to add but defers cleanup to user judgment in v2.4 to
avoid accidental data loss.

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
| Single capture entry point or per-leg integration in agent prose? | Single entry point: `wiki capture` CLI. The agent never writes to `.wiki-pending/` directly. Resolves the prose-not-script concern raised in code review. |
| `Clippings/` separate from `raw/` semantically? | No. `Clippings/` is the queue, `raw/` is the archive. Files transit Clippings → raw on ingest. No separate manifest. |
| Subagent reports get a separate ingest path? | No. Subagent reports use the same Clippings drop-zone path. Main agent's job is `mv` + `wiki ingest-now`, not capture-body authoring. |
| Marker layout (where does `.wiki-config` live for project mode)? | `<cwd>/.wiki-config` is the canonical detection path; for project mode it carries `role = "project-pointer"` with `wiki = "./wiki"`; the actual project wiki is at `<cwd>/wiki/`. Eliminates the sibling-match bug. |
| Should the resolver be interactive? | No. `wiki-resolve.sh` exits 0 with stdout, OR exits 10/11/12/13 to signal "user input needed." Prompting is `wiki-capture.sh`'s job; headless mode applies fallback rules. |
| Index-pull lens vs. role-prompt lens? | Both. Index-pull is primary in mature wikis (>7 candidate-eligible pages). Role-prompt is primary in cold-start (≤7 pages). The role hint stays in the prompt at all times; weight in agent behavior shifts naturally. |
| JSONL atomicity primitive? | `flock` on `<wiki>/.locks/ingest-issues.lock` (and `<wiki>/.locks/manifest.lock` for manifest mutations). The earlier "PIPE_BUF" claim was incorrect for regular files. Max line length 4 KB, with truncation. |
| Migration: silent vs. interactive when multiple candidates exist? | Silent only when exactly one unique main wiki at depth ≤ 2 in `$HOME`. Otherwise prompt. Prevents auto-pointing at the wrong wiki. |
| Old `karpathy-wiki/SKILL.md` removed in v2.4 ship commit? | No. Kept during transition; description updated to point at new skills; removal is a separate cleanup commit after v2.4 ships and new skills are verified working. |

---

## Acceptance criteria

v2.4 ships when:

- [ ] **(Automated)** `hooks/session-start` emits
      `hookSpecificOutput.additionalContext` containing the loader
      body wrapped in `<EXTREMELY_IMPORTANT>` tags when
      `WIKI_CAPTURE` and `CLAUDE_AGENT_PARENT` are unset; emits no
      `additionalContext` when either is set. (Verifiable by
      capturing hook stdout in test fixture.)
- [ ] **(Automated)** `skills/using-karpathy-wiki/SKILL.md` exists,
      contains `<SUBAGENT-STOP>` block at top, contains pointers to
      capture and ingest skills (verifiable by file content scan).
- [ ] **(Automated)** First capture in an unconfigured cwd
      (interactive context) prompts with options 1/2/3; user
      response persisted to `<cwd>/.wiki-config` (project pointer)
      OR `<cwd>/.wiki-mode`; second capture in same cwd does NOT
      prompt.
- [ ] **(Automated)** Headless context with unconfigured cwd applies
      the headless fallback rule; capture either succeeds with
      auto-selected main, OR is preserved at orphan path with
      explicit warning.
- [ ] **(Automated)** `wiki use project|main|both` changes the
      persisted choice idempotently; refusal cases (`wiki use main`
      inside a wiki; `wiki use both` with no main) error explicitly.
- [ ] **(Automated)** First-time use with no main wiki and a single
      candidate at `~/wiki/` with `role = "main"` migrates silently;
      multiple candidates trigger interactive prompt.
- [ ] **(Automated)** Files dropped in `Clippings/` are ingested
      next SessionStart with no manual capture authoring; file is
      moved from `Clippings/` to `raw/` on commit; manifest updated.
- [ ] **(Automated)** Subagent-report move-and-ingest workflow:
      `mv <file> <wiki>/Clippings/ && wiki ingest-now <wiki>` →
      page committed; main agent never wrote a capture body.
- [ ] **(Automated)** Concurrent SessionStart with same Clippings
      file produces exactly one capture (deterministic filename +
      atomic `set -C`).
- [ ] **(Automated)** Ingester deep-orientation candidate selection
      is deterministic given fixture index + capture; algorithm
      output matches expected top-N for ≥3 fixture cases.
- [ ] **(Automated)** Cold-start orientation (≤7 pages in wiki)
      completes without failing the candidate-count gate; ingestion
      succeeds; commit message rationale references role-prompt lens.
- [ ] **(Automated)** Issues observed during orientation are
      appended to `.ingest-issues.jsonl`; `wiki issues` renders
      grouped markdown; `wiki status` shows count summary.
- [ ] **(Automated)** Two ingesters appending to
      `.ingest-issues.jsonl` concurrently produce all written lines
      well-formed (flock test).
- [ ] **(Automated)** `wiki-manifest-lock.sh` serializes two
      concurrent manifest writers; final manifest contains all
      registered entries with consistent fields.
- [ ] **(Automated)** Both-mode partial failure: project succeeds,
      main fails to spawn → `wiki status` reports asymmetric
      outcome; user can `wiki ingest-now <failed-wiki>` to retry.
- [ ] **(Automated)** All new scripts have unit tests written
      before the script (TDD discipline; verified by reviewing
      commit history of leg's commit cluster).
- [ ] **(Automated)** Skill split duplication test: capture and
      ingest skills do not contain >80 contiguous-word substring
      overlap outside `references/`.
- [ ] **(Automated)** `bash tests/run-all.sh` passes.
- [ ] **(Manual review)** Per skill prose change, a RED scenario
      exists in `tests/red/` showing an agent failing the rule
      before the rule was added.

---

## Skill rule ownership

To prevent rule drift across the split skills, each rule has exactly
one canonical home. Other skills cite by file path; they don't
duplicate.

| Rule | Canonical home |
|---|---|
| Trigger taxonomy (when to capture, when to skip) | `using-karpathy-wiki/SKILL.md` |
| Iron laws | `using-karpathy-wiki/SKILL.md` |
| Announce-line contract | `using-karpathy-wiki/SKILL.md` |
| `<SUBAGENT-STOP>` block | `using-karpathy-wiki/SKILL.md` |
| Capture authoring (full body-floor rules, etc.) | `karpathy-wiki-capture/SKILL.md` |
| Subagent-report workflow (move + `wiki ingest-now`) | `karpathy-wiki-capture/SKILL.md` |
| `wiki use` mode-change directive | `karpathy-wiki-capture/SKILL.md` |
| Capture frontmatter schema (incl. `capture_kind` enum) | `references/capture-schema.md` |
| Body-floor sufficiency rules (per `capture_kind`) | `references/capture-schema.md` |
| Evidence-path conventions | `references/capture-schema.md` |
| Orientation protocol (incl. deep orientation) | `karpathy-wiki-ingest/SKILL.md` |
| Page format (frontmatter + body conventions) | `karpathy-wiki-ingest/SKILL.md` |
| Role guardrail / role-as-lens fallback | `karpathy-wiki-ingest/SKILL.md` |
| Manifest protocol (origin, sha, referenced_by) | `karpathy-wiki-ingest/SKILL.md` |
| Commit protocol (message format, what to include) | `karpathy-wiki-ingest/SKILL.md` |
| Issue-reporting trigger types and severity | `karpathy-wiki-ingest/SKILL.md` |
| Cross-link convention (wiki-relative leading `/`) | `references/page-conventions.md` |

The CI duplication test (in Acceptance Criteria above) catches drift:
if any rule appears verbatim (>80 contiguous-word match) in a non-
canonical location, the test fails.
