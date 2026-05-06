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
- Files dropped into a wiki's drop zones (`inbox/`, `raw/`) are
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
| Raw-direct | session start AND on-demand `wiki ingest-now` | files in `<wiki>/inbox/` (drop zone); manifest sha vs sha for files in `raw/` | create raw-direct capture per file; ingester moves inbox → raw on commit |

### Component map

New files:

```
skills/using-karpathy-wiki/SKILL.md             # thin loader, force-loaded
skills/karpathy-wiki-capture/SKILL.md           # for the main agent (read on demand)
skills/karpathy-wiki-ingest/SKILL.md            # for the spawned ingester only
skills/karpathy-wiki-capture/references/capture-schema.md  # canonical frontmatter contract
skills/karpathy-wiki-ingest/references/page-conventions.md  # cross-link conventions (leading `/`)
bin/wiki                                        # EXTENDED with new subcommands: capture, ingest-now, use, issues, init-main. `wiki capture` is the SINGLE entry point for capture writes (calls resolver, writes captures, spawns ingesters). Note: this is the existing CLI in bin/wiki, NOT a new script. The existing scripts/wiki-capture.sh sourced library is unchanged.
scripts/wiki-resolve.sh                         # decides which wiki(s) a capture targets; non-interactive
scripts/wiki-init-main.sh                       # interactive main-wiki bootstrap (run by `wiki capture` only when user channel is available)
scripts/wiki-use.sh                             # change per-cwd mode (called by `wiki use`)
scripts/wiki-ingest-now.sh                      # on-demand drift-scan + drain (same logic as SessionStart hook; called by `wiki ingest-now`)
scripts/wiki-manifest-lock.sh                   # flock-based wrapper around manifest mutations
scripts/wiki-issues.sh                          # render .ingest-issues.jsonl as markdown (called by `wiki issues`)
scripts/wiki-issue-log.sh                       # ingester helper to append a JSON line (uses flock)
hooks/session-start                             # extended: inject loader + scan inbox/ + scan raw/ for drift
```

Removed / split:

```
skills/karpathy-wiki/SKILL.md             # split into the three above
```

New per-wiki state file:

```
<wiki>/.ingest-issues.jsonl               # append-only, machine-readable
```

New per-cwd marker file (created only when user picks main-only):

```
<cwd>/.wiki-mode                          # contents: "main-only" (only legal value in v2.4)
```

Note: forking to main is encoded as `fork_to_main = true` on
`.wiki-config`, NOT as a `.wiki-mode = both` value. There is no
`.wiki-mode = both`. See "Three-state model" and "Marker layout"
below.

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

#### Hook execution order (canonical)

The hook body runs steps in this order:

1. **Subagent / ingester fork-bomb guard.** If `WIKI_CAPTURE` OR
   `CLAUDE_AGENT_PARENT` is set, exit 0 immediately. Subagent and
   spawned-ingester contexts skip the hook entirely.
2. **Loader injection.** Emit
   `hookSpecificOutput.additionalContext` containing the loader's
   body wrapped in `<EXTREMELY_IMPORTANT>` tags. This step runs
   regardless of whether a wiki exists at cwd — the loader covers
   both "wiki here" and "no wiki here" cases (the loader's prose
   tells the agent what to do in either state).
3. **Wiki resolution (walk-up).** Call `wiki_root_from_cwd`
   (existing behavior, walks up from cwd). If no wiki found, the
   hook is done — return without running steps 4-6.
4. **Drift scan** of `<wiki>/inbox/` and `<wiki>/raw/` (extended
   from existing behavior).
5. **Drain** pending captures.
6. **Reclaim** stale `.processing` files.

Steps 4-6 only run when a wiki was found at step 3. Step 2 always
runs (modulo step 1's guard). The loader is the agent-facing
contract; the drift-scan + drain are wiki-housekeeping that only
makes sense when a wiki exists.

#### Hook resolution scope (carve-out from v2.4 cwd-only rule)

The cwd-only resolver rule (Leg 2) applies to **`bin/wiki capture`
and other user-driven CLI commands**. It does NOT apply to the
SessionStart hook. The hook keeps using `wiki_root_from_cwd` (walk-up
from cwd) for its own resolution, because:

- Users routinely launch the agent from a subdirectory of their wiki
  (e.g. `cd ~/wiki/concepts && claude`). The hook needs to find the
  wiki to drift-scan and drain; cwd-only would silently disable
  drift-scan for these users — a behavior regression with no
  migration aid.
- The hook's job (steps 3-6) is observability, not authoring.
  There's no fork decision to make at session start; the hook scans
  whatever single wiki the walk-up locates.

#### Loader injection guard

The loader is emitted (step 2 above) only when BOTH of these hold:

- `WIKI_CAPTURE` env var is unset (we are NOT inside a spawned
  ingester).
- `CLAUDE_AGENT_PARENT` env var is unset (we are NOT a subagent
  dispatched by another agent).

If either is set, step 1's early exit fires before step 2 runs, so
the hook emits no `additionalContext` at all. Subagent contexts
therefore never see the loader; the `<SUBAGENT-STOP>` block in the
loader body is a defensive backstop for cases where the hook
environment doesn't propagate `CLAUDE_AGENT_PARENT` correctly.

The `WIKI_CAPTURE` env var is set by `wiki-spawn-ingester.sh` on the
headless worker's environment. `CLAUDE_AGENT_PARENT` is the
spec-introduced convention for marking subagent contexts; if Claude
Code doesn't natively set this env var, the plugin's Agent-tool
wrapper sets it on subagent dispatch (out of v2.4 scope, but the env
var remains the contract).

#### No-wiki case (rationale for always-emit-loader)

The loader is emitted at step 2 even when no wiki exists at or
under cwd. This is intentional: a user starting an agent in a fresh
project intending to use the wiki has the loader rules loaded and
knows what to do when a trigger fires. The loader's body explicitly
covers the "no wiki here" case ("if a wiki-worthy moment arises in
this directory, run `bin/wiki capture` to be prompted for setup").
The drift-scan and drain steps (4-6) skip cleanly because there's
no wiki to scan.

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

1. **Inside a wiki** — `cwd/.wiki-config` exists with `role` of
   `main`, `project`, or `project-pointer`. The config alone carries
   all the information needed: target wiki path AND whether to fork
   captures to main.
2. **Configured for main-only external use** — `cwd/.wiki-mode` exists
   with the literal string `main-only`. No project wiki at cwd;
   captures go to `~/.wiki-pointer`'s main.
3. **Unconfigured** — neither file exists.

There is no "both" `.wiki-mode` value. Forking is encoded in
`.wiki-config` as a `fork_to_main = true` field on the project wiki
or its pointer; see "Marker layout" below. This is the structural fix
for the previous design's contradiction (Codex P0): "both" required
TWO marker files at cwd that the resolver could not coherently
combine.

### Marker layout (canonical)

The previous `wiki_root_from_cwd` checked **two** paths per directory:
`<dir>/.wiki-config` AND `<dir>/wiki/.wiki-config`. v2.4 picks **one
canonical layout**: `<cwd>/.wiki-config` ONLY.

When the user picks "project" or "both" mode at the per-cwd prompt,
`wiki-init.sh project` is invoked with target `<cwd>/wiki/` and a
**pointer config** is written at `<cwd>/.wiki-config`:

```toml
# project mode (no fork)
role = "project-pointer"
wiki = "./wiki"
created = "2026-05-06"
fork_to_main = false

# both mode
role = "project-pointer"
wiki = "./wiki"
created = "2026-05-06"
fork_to_main = true
```

The resolver:
- Reads `<cwd>/.wiki-config`.
- If `role = "project-pointer"`: `wiki_root = cwd/<wiki>` from
  config; `fork = fork_to_main` (default false).
- If `role = "project"` or `"main"`: cwd IS a wiki; `wiki_root = cwd`;
  `fork = fork_to_main` (default false; rare to set on the wiki's
  own config).
- If `<cwd>/.wiki-mode = main-only`: `wiki_root = main_wiki` (from
  pointer); `fork = false`.

If `fork = true`, the resolver returns `[wiki_root, main_wiki]`
(deduplicated if `wiki_root == main_wiki`). If `fork = false`, it
returns `[wiki_root]`.

Why this layout:
- One canonical detection path (`<cwd>/.wiki-config`).
- "both" is expressible as a single field, not a marker conflict.
- A user who places the wiki AT cwd and wants to fork can set
  `fork_to_main = true` on the wiki's own `.wiki-config`.
- Avoids the sibling-match bug where being in `~/dev/myapp/`
  accidentally claims `~/wiki/`.

A user who places the wiki AT cwd (rare; happens when the user runs
the agent inside the wiki itself) gets a real `<cwd>/.wiki-config`
with `role = "main"` or `role = "project"` — handled by the same
resolver without pointer indirection.

### `wiki-resolve.sh` (non-interactive)

A new script called by `bin/wiki capture` at the start of every capture.
**`wiki-resolve.sh` is non-interactive: it never prompts.** It either
returns a list of wikis on stdout (one absolute path per line) and
exits 0, OR exits with one of these specific non-zero codes that
signal "I need user input":

- `10` — `~/.wiki-pointer` missing (need to run main-bootstrap prompt).
- `11` — cwd unconfigured (need to run per-cwd prompt).
- `12` — `.wiki-config` requests `fork_to_main = true` but
  `~/.wiki-pointer` is `none`. Configuration error, recoverable only
  by user action.
- `13` — both `.wiki-config` AND `.wiki-mode` exist at cwd (one
  always overrides the other, but having both is a sign the user
  edited by hand or upgraded inconsistently — exit and force
  reconciliation).
- `14` — `.wiki-config` says `role = "main"` or `"project"` but the
  directory it points to is missing required files (`schema.md`,
  `index.md`, `.wiki-pending/`). Half-built wiki; init needed.

The non-interactive contract means tests, hooks, and headless contexts
can call the resolver without stalling. Prompting is `bin/wiki
capture`'s job.

Pseudocode:

```
# Read main wiki pointer.
read $HOME/.wiki-pointer:
  - missing                       → exit 10
  - contains "none"               → main_wiki = ""
  - contains <path>:
    - <path>/.wiki-config missing → exit 10 (broken pointer; re-bootstrap)
    - <path>/.wiki-config role != "main" → exit 10 (pointer target not a main wiki)
    - <path> missing schema.md / index.md / .wiki-pending/ → exit 14
                                  (half-built main wiki at pointer target;
                                   needs `wiki-init.sh main <path>` re-run)
    - else                        → main_wiki = <path>

# Read cwd config(s). Both files present is itself a conflict.
config_present  = exists(cwd/.wiki-config)
mode_present    = exists(cwd/.wiki-mode)

if config_present AND mode_present:
  exit 13  # User edited by hand or upgraded inconsistently.

# Resolve cwd.
if config_present:
  read cwd/.wiki-config:
    role = "main" | "project":
      wiki_root = cwd
      verify wiki_root has schema.md, index.md, .wiki-pending/
      if missing → exit 14
    role = "project-pointer":
      wiki_root = cwd / <wiki> from config
      verify wiki_root has schema.md, index.md, .wiki-pending/
      if missing → exit 14
  fork = config.fork_to_main (default false)
elif mode_present:
  read cwd/.wiki-mode:
    "main-only":
      if not main_wiki  → exit 12
      wiki_root = main_wiki
      fork = false
    other value:
      exit 13  # invalid mode value
else:
  exit 11  # unconfigured, need per-cwd prompt

# Build target list.
if fork:
  if not main_wiki  → exit 12
  if main_wiki == wiki_root: return [wiki_root]
  return [wiki_root, main_wiki]
return [wiki_root]
```

The `bin/wiki capture` wrapper interprets the exit code and runs the
appropriate prompt (or fails out cleanly in headless mode; see
"Headless contexts" below).

### Conflict precedence

The resolver's exit-13 case fires when both `.wiki-config` and
`.wiki-mode` exist at cwd. v2.4's normal write paths never produce
this state — `wiki use main` writes `.wiki-mode` only and refuses if
`.wiki-config` exists; `wiki use project|both` writes `.wiki-config`
only and removes any stale `.wiki-mode`. Exit 13 indicates a hand-
edit or partial migration and forces user reconciliation:

```
This directory has BOTH `.wiki-config` AND `.wiki-mode`. v2.4 expects
one or the other, not both. To fix:
  rm <cwd>/.wiki-mode    # to keep the project wiki
  rm <cwd>/.wiki-config  # to switch to main-only mode
Then re-run your last command.
```

### `fork_to_main` inside an existing wiki

`wiki use both` invoked inside an existing wiki (cwd has
`.wiki-config` with `role = "main"` or `"project"`, not pointer)
sets `fork_to_main = true` in that file. Captures from cwd fork to
the wiki at cwd AND `~/.wiki-pointer`'s main. This handles the
"main-instance + main-pattern" workflow when the user's "project"
wiki happens to be the main wiki itself.

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

`bin/wiki capture` runs this when `wiki-resolve.sh` exits 10. Two
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
resolver and bootstrap MUST NOT prompt. `bin/wiki capture` checks for a
user channel before prompting. Detection rules (any one means
"headless"):

- `WIKI_CAPTURE` env var is set (we are inside a spawned ingester —
  treat as headless; capture-write is forbidden anyway).
- `CLAUDE_HEADLESS=1` env var is set.
- `stdin` is not a TTY AND no `CLAUDE_AGENT_INTERACTIVE=1` env.
- The agent's spawn context indicates subagent (we read
  `CLAUDE_AGENT_PARENT` if set; presence means subagent).

Headless fallback rules, picked to be safe-by-default:

- Resolver exit 10 (pointer missing) AND cwd has `.wiki-config` (cwd
  is itself a configured wiki) → proceed with cwd's wiki only;
  pointer is irrelevant when the local config is sufficient.
- Resolver exit 10 (pointer missing) AND cwd unconfigured → abort
  the capture; preserve body at `$HOME/.wiki-orphans/<timestamp>-<slug>.md`.
  Do NOT silently write `~/.wiki-pointer = none`; that is a user
  decision, not a fallback default.
- Resolver exit 11 (cwd unconfigured) AND `~/.wiki-pointer` valid →
  use main-only as default; write `<cwd>/.wiki-mode = main-only`. Log
  warning *"headless mode auto-selected main-only for cwd; user can
  override with `wiki use project|both`."*
- Resolver exit 12 (cwd requires a main wiki — `.wiki-mode =
  main-only` OR `.wiki-config` with `fork_to_main = true` — but
  `~/.wiki-pointer` is `none` or invalid) → abort with explicit
  error and orphan-preservation. The user's pointer needs setting
  or the per-cwd config needs editing.
- Resolver exit 13 (conflicting markers — both `.wiki-config` AND
  `.wiki-mode` present at cwd) → abort with explicit error and
  orphan-preservation. Requires manual reconciliation (`rm` one of
  the markers).
- Resolver exit 14 (half-built wiki — either cwd or pointer-target
  missing required files) → abort with explicit error naming the
  missing files and the path; orphan-preserve the body. The user's
  wiki directory is not v2.4-shaped and needs `wiki-init.sh` re-run
  on the affected path.

The orphan preservation step is what prevents capture loss in
headless contexts: the body is never thrown away, only set aside for
the user to reconcile.

### `.wiki-mode` marker file

A small file in cwd containing one literal string on the first line:

- `main-only`

No other contents. Optional second line: `# created YYYY-MM-DD by wiki use`.

`.wiki-mode` only encodes "use main only." It does NOT encode "both"
— forking is a property of the cwd's `.wiki-config` (the
`fork_to_main` field), not of `.wiki-mode`. The two files are
mutually exclusive at cwd; presence of both is a configuration
error (resolver exit 13).

### `wiki use` CLI

Three subcommands:

- `wiki use project` — if `<cwd>/wiki/` doesn't exist, run
  `wiki-init.sh project <cwd>/wiki <main_or_none>`. Write
  `<cwd>/.wiki-config` with `role = "project-pointer"`,
  `wiki = "./wiki"`, `fork_to_main = false`. Remove `.wiki-mode` if
  present.
- `wiki use main` — refuse if cwd has `.wiki-config` (cwd is already
  a wiki or a project-pointer). Otherwise write `.wiki-mode`
  containing `main-only`. Print warning if `<cwd>/wiki/` exists from
  a prior project mode ("local wiki kept; captures will no longer go
  there; `rm -rf <cwd>/wiki` to remove it").
- `wiki use both` — refuse if `~/.wiki-pointer = none` (no main wiki
  to fork to). If cwd already has `.wiki-config`:
  - `role = "project-pointer"` → set `fork_to_main = true` in the
    config (in place; preserve other fields).
  - `role = "main"` or `"project"` (cwd IS a wiki) → set
    `fork_to_main = true` in the config (in place).
  Otherwise (cwd unconfigured): if `<cwd>/wiki/` doesn't exist, init
  it via `wiki-init.sh project <cwd>/wiki <main>`. Write
  `<cwd>/.wiki-config` with `role = "project-pointer"`,
  `wiki = "./wiki"`, `fork_to_main = true`. Remove `.wiki-mode` if
  present.

Idempotent: re-running with the current mode/state is a no-op.

The `using-karpathy-wiki` loader includes a one-line directive: *"When
the user asks to change wiki mode for this directory (phrases like 'use
project wiki here,' 'main only,' 'switch to both'), run
`wiki use <mode>` and confirm."*

### Standalone project wikis (no main)

`wiki-init.sh project <path>` is extended to accept a missing main
argument. When invoked without a main, it writes `.wiki-config` with
`role = "project"` but **no `main` field**. The future cross-wiki
propagation mechanism (`wiki link-instances`, deferred to v2.5+)
will treat absent `main` as "no propagation target." This makes
"project-only" a first-class state in v2.4, not a degraded form of
"project + main."

The existing `wiki-init.sh` validation in `scripts/wiki-init.sh:33-35`
is changed: project mode no longer requires a main path. A new error
case is added: when the wiki path being initialized already exists
with a `.wiki-config`, the script is a no-op (idempotency preserved).

### Forking on capture

When the resolver returns multiple wikis (`fork_to_main = true`),
`bin/wiki capture` writes the **same capture body into each wiki's
`.wiki-pending/`**.
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

`bin/wiki capture` writes a fork-coordination record at
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
- Cwd has `.wiki-config` (`role = "project-pointer"`,
  `fork_to_main = false`): resolver returns the resolved wiki path
  silently.
- Cwd has `.wiki-config` (`role = "project-pointer"`,
  `fork_to_main = true`): resolver returns [project wiki, main wiki].
- Cwd has `.wiki-config` (`role = "main"`, `fork_to_main = true`)
  AND main_wiki == cwd: resolver returns [cwd] (deduplicated).
- Cwd has `.wiki-mode = main-only`, pointer valid: resolver returns
  [main_wiki].
- Cwd has BOTH `.wiki-config` AND `.wiki-mode`: resolver exits 13.
- Cwd has `.wiki-config` (`role = "project"`, but `<cwd>/schema.md`
  is missing): resolver exits 14.
- Cwd has `.wiki-config` (`fork_to_main = true`) AND pointer = none:
  resolver exits 12.
- `wiki use main` inside an existing wiki (cwd has `.wiki-config`):
  errors with explicit message.
- `wiki use both` when `~/.wiki-pointer = none`: errors.
- `wiki use both` inside an existing wiki: sets `fork_to_main = true`
  in place; preserves other fields.
- `wiki use project` after prior `wiki use both`: sets
  `fork_to_main = false` in place; idempotent.
- Headless context (CLAUDE_HEADLESS=1) with unconfigured cwd AND no
  pointer: capture aborts; body preserved at orphan path.
- Headless context with unconfigured cwd AND pointer valid:
  auto-selects main-only; warning logged.
- User types invalid input at prompt 4 times: capture aborts; body
  preserved at orphan path.
- Two `~/wiki/` and `~/work-wiki/` both with `role = "main"`: silent
  migration declines; bootstrap prompts for choice.
- Symlink `~/.wiki-pointer` → broken target: resolver exit 10;
  bootstrap re-runs.

---

## Leg 3 — Raw-direct ingest (unified inbox flow)

### Source classes

Three categories of "file is the source" cases all funnel through one
mechanism:

| Source | Where it lands | How it gets there |
|---|---|---|
| Obsidian Web Clipper | `<wiki>/inbox/` | external app drops file |
| Research subagent report | `<wiki>/inbox/` | main agent moves the file (single command — see below) |
| Drift in `raw/` | already in `<wiki>/raw/`; manifest sha mismatch | external edit / replacement of an existing raw |

### `inbox/` is a queue, `raw/` is the archive

`<wiki>/inbox/` is the **drop zone**: a transient queue. Any file
present in `inbox/` is by definition unprocessed; once an ingester
runs, the file is moved to `raw/<basename>` and removed from
`inbox/`. There is no separate inbox manifest — durable
state lives in the wiki-root `.manifest.json` exactly as today
(`scripts/wiki-manifest.py` standardizes on `<wiki>/.manifest.json`,
NOT `<wiki>/raw/.manifest.json`).

This is the central simplification:

- **Detection rule:** `ls <wiki>/inbox/*.md` (and other supported
  extensions). Any file present is queue-pending.
- **Ingest action:** for each queue file, create a raw-direct capture
  in `<wiki>/.wiki-pending/`, spawn an ingester. The ingester reads
  the file from `inbox/`, copies to `raw/`, registers in
  manifest, removes from `inbox/`, writes the wiki page,
  archives the capture.
- **Idempotency:** re-running the scan over an empty `inbox/`
  is a no-op. If a file appears in `inbox/` while an ingester is
  processing a sibling, it gets handled in the next scan iteration —
  no need to coordinate.

The `raw/` drift-scan path (existing v2.x behavior) handles cases
where a file in `raw/` has been **edited or replaced** externally
(sha mismatch against manifest). That remains separate from `inbox/`
queue processing — they share the ingester but use different
detection mechanisms.

### `raw/` is ingester-write-only — write discipline + recovery

#### Write discipline (avoiding the staging-vs-recovery race)

The legitimate ingester writes to `raw/` in TWO steps. The naive
order (cp first, manifest write second) creates a race where
SessionStart's recovery scan can see the cp'd file before the
manifest is updated and incorrectly classify it as "unmanifested
accident." v2.4 prevents this with explicit staging:

1. Ingester copies `<wiki>/inbox/<basename>` to a staging path:
   `<wiki>/.raw-staging/<basename>`. The `.raw-staging/` directory
   is reserved (dotfile, never scanned by recovery or discovery).
2. Ingester acquires `<wiki>/.locks/manifest.lock` via `flock`.
3. Ingester writes the manifest entry for `<basename>` (origin, sha,
   referenced_by, last_ingested) to a temporary
   `.manifest.json.tmp`.
4. Ingester atomically renames `.raw-staging/<basename>` →
   `raw/<basename>`.
5. Ingester atomically renames `.manifest.json.tmp` →
   `.manifest.json`.
6. Ingester releases the manifest lock.
7. Ingester removes `<wiki>/inbox/<basename>`.

The atomic renames ensure that any external observer (the recovery
scan) sees one of two consistent states: file in `raw/` AND in
manifest, OR file not in `raw/` (still in `.raw-staging/`, which
recovery skips).

Crash recovery: a crash between step 1 and step 4 leaves a file in
`.raw-staging/`. On next SessionStart, the recovery scan ignores it
(reserved directory). Cleanup of abandoned staging files (older than
1 hour) is a future `wiki doctor` responsibility, not `wiki status`
(`wiki status` is read-only by design — command/query separation).
Until `wiki doctor` ships, abandoned staging files accumulate
harmlessly; manual `rm` is safe.

#### Recovery rule (user accidents)

`raw/` is the ingester's archive. Every file there has provenance: the
ingester copied it from `inbox/` (or generated it from a chat capture)
AND wrote a manifest entry. The README explicitly tells users not to
put files in `raw/` directly.

If the SessionStart drift-scan finds a file in `raw/` that is **not in
the manifest** (someone put it there by accident, or via a tool that
doesn't know the convention), AND the file's mtime is older than 5
seconds (in-flight protection), the recovery is automatic:

1. Acquire `<wiki>/.locks/manifest.lock` via `flock` (prevents racing
   with a legitimate ingester finishing its write).
2. Re-check manifest membership under the lock; if the file IS now
   in the manifest, abort recovery (the ingester finished writing
   while we were acquiring the lock).
3. Move the file to `<wiki>/inbox/<basename>`. If `<basename>`
   already exists in `inbox/`, append a counter: `<basename>.<n>.md`.
4. Append a WARN line to `.ingest.log`:
   *"raw-recovery | unmanifested file moved raw/ → inbox/: `<basename>`."*
5. Release the manifest lock.
6. Continue normal scan — the moved file gets picked up by the inbox
   queue iteration and ingested through the standard path. The
   ingester's first read produces a fresh manifest entry with proper
   provenance.

This way `raw/` invariants stay intact: every file there is
manifest-tracked. Accidental drops self-heal on the next scan, and
the lock + mtime check eliminate the in-flight-ingest race.

If a file in `raw/` IS in the manifest but its sha differs (the
existing v2.x drift case), that's a different recovery — the existing
overwrite-detection logic in the ingester handles it. The `raw/`
recovery rule above is specifically for **unmanifested** files in
`raw/`.

### Concurrent SessionStart safety

Two SessionStart hooks firing concurrently (user opens two terminals)
would both see the same `inbox/foo.md`. The capture filename is
deterministic from the source path:

```
capture_filename = drift-<sha12(absolute_path)>-<slugified-basename>.md
```

This is the existing `_drift_scan` filename convention in
`hooks/session-start:58-62`, extended to `inbox/`. The atomic
`set -C` create (`hooks/session-start:67`) makes the second hook's
attempt fail silently — exactly the deduplication v2.x already relies
on for `raw/` drift.

The `WIKI_CAPTURE` fork-bomb guard (`hooks/session-start:21-23`)
unchanged: spawned ingesters skip the hook entirely.

### Partial-write race (rsync, unzip, etc.)

A file in `inbox/` may be in the middle of being written (rsync
hasn't finished, an editor is auto-saving, an unzip is extracting).
The hook adds an mtime check: **skip files whose mtime is within the
last 5 seconds.** They get picked up on the next SessionStart or
`wiki ingest-now` invocation.

5 seconds is an arbitrary safety floor; it covers most user-driven
saves and small file copies. Long-running operations (large rsync,
multi-MB extractions) are user responsibility — they should drop into
a staging directory and `mv` into `inbox/` when done.

### Subagent-report workflow (main agent's responsibility)

When a research subagent returns a file with durable findings, the
main agent's job is **not** to write a capture body summarizing the
report. The report IS the capture. The main agent runs:

```bash
mv <subagent-report-path> <wiki>/inbox/<basename>
wiki ingest-now <wiki>          # or wait for next SessionStart
```

`wiki ingest-now` is a CLI wrapper around the same drift-scan + drain
function that SessionStart uses. It's the on-demand path for the case
where the user is still in the active session and wants the report
ingested before they close the terminal.

#### `wiki ingest-now` argument contract

```
wiki ingest-now [<wiki-path>]
```

- **No argument:** uses cwd-resolved wiki via the same resolver
  (`wiki-resolve.sh`) as `wiki capture`. Interactive prompts allowed.
  If the resolver returns multiple wikis (`fork_to_main = true`),
  drift-scan runs against EACH.
  - **Headless context (no body to orphan-preserve):** if the
    resolver exits 10/11/12/13/14 in headless mode, `wiki ingest-now`
    prints the diagnostic and exits non-zero (no body exists to
    preserve, unlike `wiki capture`). The user must reconcile and
    re-run.
- **Explicit `<wiki-path>`:** scans only that wiki, no resolver
  involvement, no prompting. Argument must be an absolute path or
  resolvable to one; the script verifies `<wiki-path>/.wiki-config`
  exists and is non-empty before scanning. If the wiki is half-built
  (missing schema/index/pending), exits non-zero with the same
  diagnostic resolver exit 14 produces.

The two forms cover both ergonomics (no-arg in the user's shell) and
scripting (explicit path for cron jobs, automation, post-fork retry
of a specific wiki).

The capture skill (`karpathy-wiki-capture/SKILL.md`) explicitly
instructs:

> **Subagent reports.** When a research subagent returns a file with
> durable findings, do NOT write a chat-style capture body. Move the
> file into `<wiki>/inbox/<basename>` and run `wiki ingest-now
> <wiki>`. The ingester reads the file directly. Subagent-report
> bodies frequently exceed several KB; rewriting them as a capture
> body wastes tokens and produces inferior wiki pages.

This is the third specific anti-pattern the spec addresses (alongside
the prose-not-script auto-load gap and the project-wiki resolver gap):
forcing the agent to fabricate a wrapper body when the source already
exists.

### Wiki-root README (auto-generated, with upgrade backfill)

`wiki-init.sh` writes a `README.md` at the wiki root explaining the
drop zones and the `raw/` rule. The README is short, agent-friendly
markdown.

**Idempotency rules:**

- `wiki-init.sh main <path>` and `wiki-init.sh project <path> [main]`
  become safely re-runnable on existing wikis. Each step in the init
  script checks "does this artifact exist?" and skips if so.
  Specifically: `.wiki-config`, `index.md`, `log.md`, `schema.md`,
  `.manifest.json`, category directories, `inbox/`, `README.md` — all
  created only if absent.
- The README itself is created only if absent. If the user has hand-
  edited it, the init does NOT overwrite (preserves user content).
- **Upgrade backfill:** users upgrading from v2.3 (no README, no
  `inbox/`) re-run `wiki-init.sh main <path>` once; the script adds
  the missing pieces and leaves everything else alone. The migration
  section documents this as a one-line upgrade hint.

Template:

```markdown
# <wiki-role> wiki — <created-date>

This wiki is auto-managed by the karpathy-wiki plugin. Most of the
time you should not edit files directly — captures, ingestion, and
page writes happen through the plugin's tooling.

## Where to drop files

**`inbox/`** — the universal drop zone for ingestion. Put anything
that should become a wiki page here:

- Obsidian Web Clipper exports (configure your template's "Note
  location" to `inbox` and "Vault" to this wiki — see "Web Clipper
  setup" below).
- Research reports from subagents (the agent typically moves these
  for you).
- Manual file drops: downloaded articles, PDF→markdown exports,
  meeting notes.

After you drop a file, ingestion happens on the next agent session
start (silent), or immediately if you run `wiki ingest-now <this-wiki-path>`.

**Do NOT put files in `raw/`.** That directory is the ingester's
archive — every file there has a manifest entry tracking origin,
sha256, and which wiki pages reference it. If you put a file there
by accident, the next ingest will move it to `inbox/` and process
it normally (a WARN gets logged, but no data is lost).

## Web Clipper setup

In Obsidian Web Clipper settings → Templates → (your template) →
Location:

- **Note name:** `{{title}}` (or whatever filename pattern you prefer)
- **Note location:** `inbox`
- **Vault:** select this wiki's directory

That's it. Clip a page; the file lands in `inbox/`; next agent session
ingests it.

## Other top-level directories

- `concepts/`, `entities/`, `queries/`, `ideas/` — wiki content,
  written by the ingester. Editing pages directly is allowed but the
  ingester will eventually re-rate / re-link them.
- `archive/` — old content the ingester decided to retire.
- `raw/` — the ingester's archive (see above).
- `.wiki-pending/` — pending captures (transient).
- `.locks/` — concurrency primitives (transient).
- `.manifest.json`, `.ingest.log`, `.ingest-issues.jsonl` — machine
  state.

## Schema

See `schema.md` for the live category list, tag taxonomy, and
thresholds.
```

The README is plain prose; users read it on first wiki creation and
when they are confused about where to drop files. The plugin tooling
does not read the README itself.

### Capture format for raw-direct

The capture is auto-generated by the SessionStart hook (or
`wiki ingest-now`):

```markdown
---
title: "Drop: <basename>"
evidence: "<absolute path to file in inbox/ OR raw/>"
evidence_type: "file"
capture_kind: "raw-direct"
suggested_action: "auto"
suggested_pages: []
captured_at: "<ISO-8601 UTC>"
captured_by: "session-start-drop"  # or "wiki-ingest-now"
origin: null
---

Auto-ingest of file in <inbox|raw>/. The raw file at `evidence`
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
is treated as follows, in order:

1. **Legacy drift override.** If `captured_by` is
   `session-start-drift` OR the title starts with `Drift:` →
   `capture_kind = raw-direct` (no body floor). These are existing
   v2.x drift captures that were always file-source with auto-
   generated bodies; they always meant "raw-direct" semantically
   even though the field didn't exist yet.
2. **Path evidence.** If rule 1 doesn't match AND `evidence` is a
   filesystem path → `capture_kind = chat-attached` (1000-byte
   floor). These are pre-v2.4 mixed-evidence captures where the
   agent wrote a body alongside a file pointer.
3. **Conversation evidence.** If `evidence` is the literal string
   `conversation` → `capture_kind = chat-only` (1500-byte floor).

The validator enforces `capture_kind` presence on new captures
written by v2.4-and-later code; legacy captures pass through with
the backward-compat rules above. Captures that fail the resolved
floor under the rules are rejected with `needs-more-detail: true`
exactly as today (no behavior change vs current ingester).

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
file dropped into a project wiki's `inbox/` gets project-lens
ingestion; a file dropped into a main wiki's `inbox/` gets
main-lens ingestion. **Drops do NOT fork** — the user picked the wiki
by picking the directory. If the user wants the same file in both,
they drop into both manually.

### Failure modes

- File is binary / unreadable: ingester writes an issue
  (`issue_type: other`, severity `warn`, detail `cannot read raw
  file`), archives the capture, does not commit a page. The file
  stays in `inbox/` so the user can investigate (NOT moved to
  `raw/`).
- File is empty: same.
- File is a duplicate of an existing raw (sha256 already in
  manifest): ingester logs (`raw-ingest | skipped duplicate`),
  removes the file from `inbox/`, archives the capture.
- File mtime is within the last 5 seconds: hook skips it for this
  scan iteration.
- File contains valid YAML frontmatter that conflicts with v2.4
  schema: ingester writes an issue (`issue_type: schema-drift`),
  proceeds with best-effort parsing.

### Test surface

- Drop a markdown file into `inbox/`. Next session start:
  capture appears in `.wiki-pending/`; ingester runs; page committed;
  raw is in `raw/`; manifest updated; `inbox/` is empty.
- `wiki ingest-now` triggers same flow on demand without waiting for
  SessionStart.
- Drop the same file twice (different content, same basename):
  second SessionStart sees a different sha → second raw-direct
  capture; the existing overwrite-detection logic (in current
  ingester) handles the merge.
- Two SessionStarts fire concurrently with the same file in
  `inbox/`: deterministic capture filename + atomic `set -C`
  ensures one wins, the other no-ops.
- File in `inbox/` with mtime now: hook skips; next scan picks it
  up.
- Subagent report at `/tmp/foo-report.md` → main agent runs
  `mv ... <wiki>/inbox/ && wiki ingest-now <wiki>` → page
  committed without main agent writing a capture body.
- Binary file in `inbox/`: issue logged; file stays in
  `inbox/`; no page written.

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

Grouped by `issue_type`, ordered by severity within each group. v2.4
ships the basic render only (no flags). `--filter <type>` and
`--since <date>` flags for narrower views are deferred to v2.5
(see "Deferred to v2.5").

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

#### Body-input contract

`wiki capture` accepts the body via **exactly one** of:

- `--body-file <path>` — read body from `<path>` (recommended for
  bodies > 16 KB and for any context where stdin may be in use by
  another channel).
- Stdin — read body from stdin until EOF if `--body-file` is not
  provided AND stdin is a pipe/file (not a TTY).

If neither applies (no `--body-file`, stdin is a TTY), `wiki capture`
errors with: *"no body provided. Pass --body-file <path> or pipe body
on stdin."*

The body is read in full into memory before any other action. Limits:

- **Max body size: 256 KB.** Captures larger than this should be
  raw-direct ingestions (drop the file in `inbox/` instead). If the
  caller exceeds the limit, `wiki capture` errors with: *"body
  exceeds 256 KB; use raw-direct ingest instead — `mv <file>
  <wiki>/inbox/ && wiki ingest-now`."*
- Min body size: enforced per `capture_kind` body-floor (see
  "Body sufficiency"). `wiki capture` validates against the floor
  AFTER reading and BEFORE writing the capture file.

#### Prompt channel

When the resolver exits 10/11/12/13 and prompting is required, the
prompt goes to:

1. `/dev/tty` if it's writable (interactive shell context).
2. The agent's tool-use surface if `CLAUDE_AGENT_INTERACTIVE=1` is
   set (the wrapper turns the prompt into an `AskUserQuestion`-
   equivalent call; out of v2.4 scope but the env var is the
   contract).
3. Otherwise the headless fallback rule applies (orphan-preserve
   the body or auto-select main-only per the rules above).

The body channel (stdin or `--body-file`) is independent of the
prompt channel. A body piped into `wiki capture` does NOT prevent
prompting via `/dev/tty`. The headless detector check is for prompt
channel availability, not stdin state.

#### Invocation example

```bash
# Body via stdin (typical agent usage):
echo "$BODY" | wiki capture \
  --title "USB 3.x version-rename gotcha" \
  --kind chat-only \
  --evidence conversation \
  --suggested-action create

# Body via file (large bodies, headless contexts):
wiki capture \
  --title "Long synthesis report" \
  --kind chat-only \
  --evidence conversation \
  --suggested-action create \
  --body-file /tmp/synthesis-body.md
```

#### Internal flow

1. Validates flags + reads body (per body-input contract above).
2. Calls `wiki-resolve.sh` (non-interactive) to determine target
   wiki(s).
3. If resolver exits 10/11/12/13/14, runs the appropriate prompt
   (via prompt-channel rules) or applies the headless fallback rule.
4. Validates body against `capture_kind` floor; aborts and orphan-
   preserves if floor not met.
5. For each target wiki, writes a capture file at
   `<wiki>/.wiki-pending/<timestamp>-<slug>.md` with body + auto-
   generated frontmatter (timestamp, captured_by, resolved
   `capture_kind`, etc.).
6. Spawns one detached ingester per target via
   `wiki-spawn-ingester.sh`.
7. Writes a fork-coordination record to `~/.wiki-forks.jsonl` if
   multiple targets.
8. Returns immediately (no foreground wait).

The capture skill (`karpathy-wiki-capture/SKILL.md`) instructs the
agent: *"to capture, run `wiki capture` with title and kind; pipe
body on stdin or pass via `--body-file`. Never write to
`.wiki-pending/` directly."*

### Capture (chat-driven)

```
user says something wiki-worthy
  ↓
main agent (skill rules force-loaded by SessionStart hook)
  ↓
agent loads karpathy-wiki-capture skill on-demand
  ↓
agent runs `echo "$BODY" | wiki capture --title ... --kind ...`
  ↓
wiki capture validates body against kind's floor
  ↓
wiki capture calls wiki-resolve.sh
  ↓
resolver exits 0 (returns wikis) OR 10-14 (needs prompt or has error)
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

### Capture (raw-direct via inbox drop)

```
user (or external tool) drops file into <wiki>/inbox/<basename>
  OR main agent moves a subagent report there
  ↓
next SessionStart fires (OR user runs `wiki ingest-now <wiki>`)
  ↓
hook scans <wiki>/inbox/ and <wiki>/raw/ for unmanifested or sha-mismatched files
  ↓
for each: hook creates raw-direct capture in .wiki-pending/
  (filename = drift-<sha12(absolute_path)>-<slug>.md; atomic via set -C)
  ↓
hook calls wiki-spawn-ingester.sh per capture
  ↓
detached claude -p ingester reads the file in inbox/ (NOT the capture body)
  ↓
ingester runs deep orientation (lens shaped by wiki role)
  ↓
ingester writes/augments/no-ops; copies inbox/<basename> → raw/<basename>;
  updates manifest (under flock); removes file from inbox/
  ↓
ingester commits, archives the capture, appends issues to JSONL
```

### Capture (subagent report)

```
research subagent returns a file at /tmp/foo-report.md
  ↓
main agent: `mv /tmp/foo-report.md <wiki>/inbox/foo-report.md`
  ↓
main agent: `wiki ingest-now <wiki>`
  ↓
(falls through to "Capture (raw-direct via inbox drop)" above)
```

---

## Error handling

| Failure | Behavior |
|---|---|
| `~/.wiki-pointer` missing on first capture (interactive) | bootstrap prompt fires (Q1: yes/no main wiki; Q2: where); pointer written; capture proceeds |
| `~/.wiki-pointer` missing (headless) AND cwd has `.wiki-config` | proceed with cwd's wiki only; pointer is irrelevant when local config is sufficient |
| `~/.wiki-pointer` missing (headless) AND cwd unconfigured | abort capture; body preserved at `~/.wiki-orphans/<timestamp>-<slug>.md`. Pointer is NOT silently set to `none`; that is a user decision |
| `~/.wiki-pointer` half-built (target exists but missing required files) | resolver exit 14; capture aborts with diagnostic naming the missing files at the main-wiki path |
| `~/.wiki-pointer` valid but path is broken (symlink to deleted dir) | resolver exits 10; bootstrap re-prompts; user can repoint or set to none |
| Multiple candidate main wikis at depth ≤ 2 in $HOME | silent migration declines; bootstrap prompts user to choose |
| Cwd unconfigured (interactive) | per-cwd prompt fires (1/2/3); marker written; capture proceeds |
| Cwd unconfigured (headless) AND main exists | auto-select main-only; write `.wiki-mode = main-only`; warning logged |
| Cwd unconfigured (headless) AND main = none | abort capture; body preserved at `~/.wiki-orphans/<timestamp>-<slug>.md` |
| `~/.wiki-pointer = none` AND user picks "main" or "both" | re-prompt with "main wiki not configured; pick project or run `wiki init-main`" |
| `.wiki-config` (`fork_to_main = true`) AND pointer is valid | resolver returns [cwd-wiki, main_wiki] (deduplicated if equal) |
| `.wiki-config` (`fork_to_main = true`) AND pointer = none | resolver exits 12; user must repoint or set `fork_to_main = false` |
| `.wiki-config` AND `.wiki-mode` both present at cwd (any combination) | resolver exits 13; user must `rm` one of the markers |
| `.wiki-config` references missing `wiki = "..."` directory | resolver exits 14; user must re-init that path |
| `.wiki-config` with `role = "main"` or `"project"` but cwd lacks `schema.md`/`index.md`/`.wiki-pending/` | resolver exits 14; user must re-run `wiki-init.sh` for backfill |
| Crash between staging copy and atomic rename in ingester `raw/` write | file in `<wiki>/.raw-staging/` not in `raw/`; recovery scan ignores (reserved); periodic cleanup prunes after 1 hour |
| Concurrent in-flight ingester write vs. `raw/` recovery scan | recovery acquires manifest lock + re-checks membership; ingester atomic rename happens under same lock; no double-queue |
| `wiki use main` inside an existing wiki (cwd has `.wiki-config`) | refuse with explicit error message |
| `wiki use both` when `~/.wiki-pointer = none` | refuse with explicit error message |
| User types invalid input at per-cwd prompt | re-prompt up to 3 times; on 4th invalid, abort and orphan-preserve |
| Spawn fails (no `claude` binary, etc.) | capture stays in `.wiki-pending/`; existing reclaim logic picks it up next session |
| Spawn succeeds for one wiki in `both` mode but fails for the other | per-wiki run record reflects asymmetric outcome; `wiki status` shows fork mismatch; user can `wiki ingest-now <failed-wiki>` to retry |
| Raw-direct file is binary / empty | issue logged; file stays in inbox/ for user inspection; no page written |
| Raw-direct file mtime within last 5 seconds | hook skips this scan iteration; next scan picks up |
| Unmanifested file in `raw/` (user dropped there by accident) | hook moves to `inbox/<basename>` (with collision suffix), logs WARN, queues normal raw-direct capture |
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
  - pointer = none + cwd has `.wiki-config` (`fork_to_main = false`) → 0, returns cwd wiki
  - pointer = none + cwd has `.wiki-config` (`fork_to_main = true`) → 12 (fork requires main)
  - pointer = none + cwd unconfigured → 11 (with no main option in subsequent prompt)
  - pointer valid + cwd has `.wiki-config` (`role = "project-pointer"`) → 0, returns resolved path
  - pointer valid + cwd `.wiki-mode = main-only` → 0, returns main
  - pointer valid + cwd `.wiki-config` (project-pointer, fork_to_main=false) → 0, returns [resolved project wiki]
  - pointer valid + cwd `.wiki-config` (project-pointer, fork_to_main=true) → 0, returns [resolved project wiki, main]
  - pointer valid + cwd `.wiki-config` (role=main, fork_to_main=true) AND main_wiki == cwd → 0, returns [cwd] (deduplicated)
  - cwd has BOTH `.wiki-config` AND `.wiki-mode` (any combination) → 13
  - cwd `.wiki-mode = main-only` + pointer = none → 12
  - cwd `.wiki-config` (fork_to_main=true) + pointer = none → 12
  - cwd `.wiki-config` (role=main/project) but missing schema.md/index.md/.wiki-pending/ → 14
  - cwd `.wiki-config` (project-pointer) but `wiki` directory missing → 14
  - pointer is broken symlink → 10
  - 12+ cases minimum.
- `wiki-init-main.sh` — fresh-state prompt flow, single-candidate silent migration, multi-candidate prompt, "none" path, pointer-already-exists no-op.
- `wiki-use.sh` — 3 subcommands × idempotency × already-configured states × refusal cases (`wiki use main` in existing wiki; `wiki use both` with no main).
- `wiki-init.sh` — new standalone-project mode (no main path argument); existing main and project-with-main paths still pass.
- `wiki-issue-log.sh` — enum validation, JSON formatting (special chars in detail), max-line-length truncation, flock-serialized concurrent appends (spawn 5 parallel writers, assert all 5 lines present and well-formed).
- `wiki-issues.sh` — basic render correctness, empty log handling, JSONL with corrupted line (skip + warn). No flag tests in v2.4 (deferred to v2.5).
- `bin/wiki capture` — happy-path single-wiki write; both-mode produces two captures; headless mode applies fallback; orphan-preserve on abort.
- `wiki-ingest-now.sh` — calls drift-scan + drain; on-demand equivalent of SessionStart drop-zone behavior.
- `wiki-manifest-lock.sh` — concurrent manifest mutations from two writers produce consistent final state.

### Integration tests

- **Chat capture, project mode (interactive):** fresh cwd, simulated user picks "project" → `./wiki/` and `./.wiki-config` (project-pointer) created, capture lands, ingester runs, page committed.
- **Chat capture, both mode (interactive):** fresh cwd, simulated user picks "both" → two captures, two ingesters, two pages, fork-coordination record in `~/.wiki-forks.jsonl`.
- **Chat capture, headless mode, main exists:** auto-select main-only, capture proceeds without prompt, `.wiki-mode = main-only` written.
- **Chat capture, headless mode, no main:** capture aborts; body preserved at `~/.wiki-orphans/<timestamp>-<slug>.md`.
- **Conflict resolution:** create cwd with both `.wiki-config` (any role) AND `.wiki-mode` (any value); resolver exits 13; `wiki capture` re-prompts with explicit reconciliation instructions.
- **Half-built wiki:** `.wiki-config` at cwd with `role = "project"` but missing `schema.md`; resolver exits 14; `wiki capture` reports missing files and offers re-init.
- **Raw/ recovery during in-flight ingest:** start a legitimate ingester staging a file in `.raw-staging/`; in parallel, fire SessionStart's recovery scan; assert no double-queue, no manifest corruption, recovery skips while file is in `.raw-staging/` (reserved).
- **Both-mode partial failure:** capture in both mode, but main wiki has bad permissions on `.wiki-pending/`. Project ingester runs; main spawn fails. `wiki status` reports asymmetric outcome.
- **Raw-direct, inbox drop:** drop a markdown file → next SessionStart → page emerges, raw is in `raw/` with manifest, `inbox/` is empty.
- **Raw-direct, on-demand:** same as above but via `wiki ingest-now <wiki>` instead of waiting for SessionStart.
- **Raw-direct, subagent report:** `mv` a fixture file into `<wiki>/inbox/` then run `wiki ingest-now`; assert page emerges; assert main agent never wrote a capture body.
- **Concurrent SessionStart:** two SessionStarts fire on the same wiki with the same file in `inbox/`; assert exactly one capture is created (deterministic filename + atomic create).
- **Partial-write race:** `touch` a file in inbox/, run SessionStart immediately; hook skips it (mtime within 5s). Sleep 6s, re-run; hook picks it up.
- **`raw/` recovery:** drop a fixture file directly into `<wiki>/raw/foo.md` (no manifest entry); next SessionStart moves it to `<wiki>/inbox/foo.md`, logs WARN, queues a raw-direct capture; ingester processes normally and writes a fresh manifest entry. Final state: file is in `raw/` with manifest entry, `inbox/` is empty.
- **`raw/` recovery with collision:** repeat the above when `<wiki>/inbox/foo.md` already exists from a different drop; the recovery moves the dropped file to `inbox/foo.1.md`.
- **Wiki-root README created on init:** fresh `wiki-init.sh main <path>` produces a `<path>/README.md` matching the template (idempotency verified by re-running init — README is not overwritten).
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

### Breaking changes (release notes)

> **v2.4 is a breaking change for users of the `Clippings/` directory
> convention.** The `Clippings/` directory is no longer reserved by
> the validator/discovery; v2.4 standardizes on a single `inbox/`
> drop zone. Before upgrading, run:
>
> ```bash
> mv <wiki>/Clippings/* <wiki>/inbox/   # if you have files there
> rmdir <wiki>/Clippings/                # optional cleanup
> ```
>
> No auto-migrator ships in v2.4 (the user base is small enough that
> a manual `mv` is acceptable; an auto-migrator carries its own
> risk surface).
>
> If you don't move the files, they will appear as orphans/category
> pages on next ingest. Either move them or `rm -rf <wiki>/Clippings/`
> to suppress.

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
   to work via the legacy backward-compat rules in "`capture_kind`
   enum (canonical)" — drift captures map to `raw-direct`, path-
   evidence captures to `chat-attached`, conversation captures to
   `chat-only`.
7. **`wiki-init.sh` extended:**
   - Now accepts `project <path>` without a main argument
     (standalone project mode).
   - Now writes `inbox/` directory.
   - Now writes wiki-root `README.md` documenting drop zones and
     the `raw/` rule.
   - Now creates `.raw-staging/` directory (used by ingester
     write-discipline).
   - Re-runnable on existing wikis: each step idempotent (skip if
     present). This is the upgrade backfill path — pre-v2.4 users
     run `wiki-init.sh main <existing-path>` once to add the new
     pieces without disturbing existing content.
8. **Reserved-set update.** `scripts/wiki_yaml.py` (`RESERVED` set
   at line 30) gains `inbox`. `scripts/wiki-relink.py` (line 80)
   gains `inbox`. The legacy `Clippings` entry is retired from
   both (see "Breaking changes" above).
   - `.raw-staging` does NOT need to be added explicitly to
     `wiki-relink.py` — that file's reserved check already auto-
     skips any path component starting with `.`. It DOES need to
     be added to `wiki_yaml.py` if its `RESERVED` set isn't dot-
     aware (verify at implementation time; if dot-aware, this is
     also a no-op).
9. **`bin/wiki` extended** with `capture`, `ingest-now`, `use`,
   `issues`, `init-main` subcommands. `bin/wiki status` and `bin/wiki
   doctor` (existing) unchanged. The existing
   `scripts/wiki-capture.sh` SOURCED LIBRARY (different file from
   the new `wiki capture` subcommand — the library defines
   `wiki_capture_claim`, `wiki_capture_archive`,
   `wiki_capture_count_pending` and is sourced by
   `wiki-spawn-ingester.sh:16`) is unchanged.

### Upgrade procedure (existing v2.3 user)

```bash
# 1. Update plugin to v2.4 (whatever that mechanism is).

# 2. Re-run wiki-init.sh on each existing wiki to backfill the new
#    pieces (inbox/, .raw-staging/, README). Idempotent — won't
#    touch existing files.
bash <plugin>/scripts/wiki-init.sh main ~/wiki
# (repeat for each project wiki: bash ... project <path> ~/wiki)

# 3. Move any files from old Clippings/ into the new inbox/.
#    inbox/ now exists from step 2. Run only if Clippings/ has files.
if compgen -G "~/wiki/Clippings/*" >/dev/null; then
  mv ~/wiki/Clippings/* ~/wiki/inbox/    # NOT silenced — fail loudly
  rmdir ~/wiki/Clippings/                # only if now empty
fi

# 4. First agent session in any cwd will trigger the bootstrap
#    prompt to write ~/.wiki-pointer (silent migration if your main
#    is the unique one under $HOME).
```

Step ordering matters: step 2 (init backfill) MUST run before step 3
(Clippings move) because `inbox/` does not exist on a pre-v2.4 wiki
until init creates it. The `mv` in step 3 is NOT silenced (no
`|| true`) — a failed move means data could be lost, and the user
must see the error and fix it manually.

### Rollback

Legs are revertable in REVERSE order only (i.e., revert leg 3 before
leg 2, leg 2 before leg 1):

- **Leg 3 rollback** (raw-direct + `wiki ingest-now` + README): revert
  the SessionStart drift-scan extension to `inbox/`. Files in
  `inbox/` are silently ignored as before. Revert `wiki ingest-now`
  subcommand and `scripts/wiki-ingest-now.sh`. Leave the auto-
  generated README in place (no harm). Leg 2 stays functional.
- **Leg 2 rollback** (resolver + `wiki capture` + `wiki use`): requires
  leg 3 already reverted (leg 3 calls leg 2's resolver). Revert
  `wiki-resolve.sh`, `bin/wiki capture` subcommand, `bin/wiki use`
  subcommand, `scripts/wiki-use.sh`. Capture flow falls back to
  whatever leg 1 has installed (the loader skill instructs the
  agent to use `wiki capture`; if that subcommand is gone, the
  agent reverts to direct `.wiki-pending/` writes — graceful
  degradation).
- **Leg 1 rollback** (loader injection + skill split): requires
  legs 2 and 3 already reverted. Revert the SessionStart hook
  change, the loader-skill creation, the skill-split. The original
  `karpathy-wiki/SKILL.md` is still present (migration step 3) and
  continues to work.

Inter-leg dependencies (cannot be rolled back independently):

- Leg 2 depends on leg 1's loader skill existing (the loader's
  capture-routing prose points at `wiki capture`).
- Leg 3 depends on leg 2's resolver (no-arg `wiki ingest-now` calls
  the resolver).

Per CLAUDE.md ("migrations use multiple commits with verification
gates"), each leg ships in its own commit cluster with tests passing
between commits. Verification gate after each leg:

- After leg 1: fresh-session test — loader present in
  `additionalContext`; subagent dispatch — loader absent.
- After leg 2: per-cwd-prompt test (three interactive modes
  end-to-end); headless fallback test; conflict-resolution test;
  resolver exit-code coverage (10/11/12/13/14).
- After leg 3: drop-and-go test (inbox/ → page); on-demand
  `wiki ingest-now`; subagent-report move-and-ingest workflow;
  raw/ recovery + write-staging.
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
| `inbox/` separate from `raw/` semantically? | No. `inbox/` is the queue, `raw/` is the archive. Files transit inbox → raw on ingest. No separate manifest. |
| Subagent reports get a separate ingest path? | No. Subagent reports use the same inbox drop-zone path. Main agent's job is `mv` + `wiki ingest-now`, not capture-body authoring. |
| Two drop zones (Clippings and inbox) or one? | One. `inbox/` covers Web Clipper, subagent reports, manual drops. Web Clipper users configure their template's "Note location" to `inbox` (per the screenshot in the design discussion). Reduces directory proliferation; one convention to remember. |
| Is `raw/` ingester-only or can users drop there? | Ingester-write-only. README documents this. Recovery is automatic: the SessionStart hook moves any unmanifested file in `raw/` to `inbox/` and processes through the normal queue, preserving provenance. No data loss; one WARN logged. |
| Wiki-root README auto-generated? | Yes. `wiki-init.sh` writes README.md on first init explaining drop zones, the `raw/` rule, and the Web Clipper template setup. Idempotent — only written if absent. |
| Marker layout (where does `.wiki-config` live for project mode)? | `<cwd>/.wiki-config` is the canonical detection path; for project mode it carries `role = "project-pointer"` with `wiki = "./wiki"`; the actual project wiki is at `<cwd>/wiki/`. Eliminates the sibling-match bug. |
| Should the resolver be interactive? | No. `wiki-resolve.sh` exits 0 with stdout, OR exits 10/11/12/13 to signal "user input needed." Prompting is `bin/wiki capture`'s job; headless mode applies fallback rules. |
| Index-pull lens vs. role-prompt lens? | Both. Index-pull is primary in mature wikis (>7 candidate-eligible pages). Role-prompt is primary in cold-start (≤7 pages). The role hint stays in the prompt at all times; weight in agent behavior shifts naturally. |
| JSONL atomicity primitive? | `flock` on `<wiki>/.locks/ingest-issues.lock` (and `<wiki>/.locks/manifest.lock` for manifest mutations). The earlier "PIPE_BUF" claim was incorrect for regular files. Max line length 4 KB, with truncation. |
| Migration: silent vs. interactive when multiple candidates exist? | Silent only when exactly one unique main wiki at depth ≤ 2 in `$HOME`. Otherwise prompt. Prevents auto-pointing at the wrong wiki. |
| Old `karpathy-wiki/SKILL.md` removed in v2.4 ship commit? | No. Kept during transition; description updated to point at new skills; removal is a separate cleanup commit after v2.4 ships and new skills are verified working. |
| How is `both` mode encoded in the marker layout? | As a `fork_to_main` boolean field on `.wiki-config` (project-pointer or wiki-direct). Earlier draft used `.wiki-mode = both` as a sibling marker; that turned out to be impossible to reconcile with the project-pointer's claim that it owns the cwd → wiki resolution. Single source of truth fixes the contradiction. |
| Backward-compat for v2.x drift captures (no `capture_kind`)? | Three-rule legacy mapping in priority order: (1) `captured_by: session-start-drift` OR title prefix `Drift:` → `raw-direct` (no body floor); (2) path evidence → `chat-attached` (1000 b); (3) `evidence: conversation` → `chat-only` (1500 b). |
| Naming collision with existing `scripts/wiki-capture.sh`? | Resolved: the new "single capture entry point" is `bin/wiki capture` (a SUBCOMMAND, no new script). The existing sourced library at `scripts/wiki-capture.sh` is unchanged and continues to be sourced by `wiki-spawn-ingester.sh`. |
| Does cwd-only resolution apply to the SessionStart hook too? | No. The hook keeps `wiki_root_from_cwd` (walk-up) for its own resolution to avoid breaking users who launch agents from subdirectories of their wiki. Cwd-only applies only to `bin/wiki capture` and other user-driven CLI commands. |
| `wiki capture` body input: stdin only or `--body-file` too? | Both. Stdin (when piped) OR `--body-file <path>`. TTY stdin without `--body-file` errors. Max body 256 KB; larger goes via raw-direct ingest. |
| Prompt channel separate from body channel? | Yes. Body comes via stdin/file; prompts go to `/dev/tty` (interactive) or agent's `AskUserQuestion` (when `CLAUDE_AGENT_INTERACTIVE=1`); else headless fallback. Stdin being a pipe does NOT mean "headless." |
| `wiki ingest-now` argument contract? | Optional positional path. No-arg uses cwd-resolved wiki(s); explicit path bypasses resolver. |
| Race window: `raw/` recovery vs. in-flight ingester write? | Closed by ingester write-staging discipline: ingester writes to `<wiki>/.raw-staging/<basename>` first, then atomically renames to `raw/<basename>` AND `.manifest.json` under the manifest lock. Recovery scan acquires the same lock and re-checks manifest membership before moving — eliminates the race. |
| Half-built wiki at cwd (manual `.wiki-config` without `schema.md` etc.)? | Resolver exit 14 (new code). `bin/wiki capture` reports the missing files explicitly and offers to re-run init. |
| Pre-v2.4 `Clippings/` directory handling? | Breaking change. Manual `mv` before upgrading; release notes carry the instruction. v2.4 user base small enough that auto-migrator is overhead with no benefit. |
| README backfill for pre-v2.4 wikis? | `wiki-init.sh` becomes re-runnable on existing wikis (idempotent: skip if present). Migration section instructs users to re-run init once to backfill the new pieces (README, `inbox/`, `.raw-staging/`). |
| Loader injection guard for subagents? | Hook emits no `additionalContext` at all when `WIKI_CAPTURE` OR `CLAUDE_AGENT_PARENT` is set. The `<SUBAGENT-STOP>` block in the loader body is a defensive backstop for env-var propagation failures. |
| `--filter` / `--since` flags on `wiki issues` in v2.4? | Deferred to v2.5. v2.4 ships basic render only. |

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
- [ ] **(Automated)** Files dropped in `inbox/` are ingested
      next SessionStart with no manual capture authoring; file is
      moved from `inbox/` to `raw/` on commit; manifest updated.
- [ ] **(Automated)** Unmanifested file in `raw/` is moved to
      `inbox/` on next scan with WARN log; collision adds `.<n>`
      suffix; final state has the file in `raw/` with proper
      manifest entry.
- [ ] **(Automated)** `wiki-init.sh main` creates `inbox/`
      directory AND writes wiki-root `README.md` (idempotent on
      re-run).
- [ ] **(Automated)** `scripts/wiki_yaml.py` and
      `scripts/wiki-relink.py` reserved sets contain `inbox` and
      do not contain `Clippings`. `.raw-staging` is reserved (either
      via explicit listing or via the existing dot-prefix auto-skip
      in `wiki-relink.py`).
- [ ] **(Automated)** Subagent-report move-and-ingest workflow:
      `mv <file> <wiki>/inbox/ && wiki ingest-now <wiki>` →
      page committed; main agent never wrote a capture body.
- [ ] **(Automated)** Concurrent SessionStart with same inbox
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
- [ ] **(Automated)** Resolver exits 14 with diagnostic naming the
      missing files when (a) cwd `.wiki-config` references a wiki
      missing schema/index/.wiki-pending OR (b) `~/.wiki-pointer`
      target exists but is similarly half-built. `bin/wiki capture`
      reports the missing files explicitly and orphan-preserves the
      body.
- [ ] **(Automated)** Loader is emitted in `additionalContext` when
      cwd has no wiki AND no parent has a wiki, demonstrating that
      step 2 (loader injection) runs before step 3 (wiki-found
      check) in the SessionStart hook.
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
