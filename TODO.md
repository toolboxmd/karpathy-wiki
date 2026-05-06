---
title: karpathy-wiki — TODO / backlog
status: living-document
last_reviewed: 2026-05-06  # post-0.2.7 read-protocol restoration; next audit due after 5-10 more real-session reads + ingests
convention:
  "One ## section per issue. Each section has its own YAML frontmatter block at
  the top."
---

# karpathy-wiki — TODO / backlog

Deferred items for the plugin itself (NOT for the content the plugin produces —
that lives in the wiki). This file serves as a lightweight stand-in for GitHub
Issues while the project is pre-merge to `main`. When ready, these migrate to
GitHub Issues on `toolboxmd/karpathy-wiki` with matching labels. Until then,
edit this file: add items at the top, move shipped items to the "Shipped"
section at the bottom, delete rejected items (their rationale lives in the
commit history of this file).

**How to add an item:** append a new `##` section with the YAML block below,
fill every field, link into the referencing plan/commit/concept page.

**Frontmatter field contract:**

- `status` — `open | deferred | blocked | rejected | shipped`. `open` = fair
  game; `deferred` = has revisit criteria; `blocked` = waiting on upstream;
  `rejected` = decided against (leave in place as "don't re-propose" record);
  `shipped` = closed, moved to Shipped section below.
- `priority` — `p0 | p1 | p2 | p3`. Loose ordering. p0 = blocks next plan; p3 =
  nice-to-have.
- `effort` — `low | medium | high`. Rough T-shirt sizing.
- `labels` — free-form tags for cross-cutting categorization (e.g. `post-mvp`,
  `defers-to-anthropic`, `ux`, `test-infra`).
- `revisit_when` — short sentence naming the concrete condition under which this
  becomes priority-bumped. Required for `status: deferred | blocked`.
- `refs` — backlinks to plan docs, commits, wiki pages, GitHub issues.

---

## 0.2.9: in-repo project-wiki — prompt user for tracking choice

```yaml
status: open
priority: p1
effort: low
labels: [0.2.9, auto-init, ux, real-session-finding]
refs:
  - scripts/wiki-init.sh:173-177  # nested-git auto-prevention
  - skills/using-karpathy-wiki/SKILL.md  # auto-init "no prompts" rule
  - tmp/skill-v1-6ce0c77.md:42-57  # original auto-init cascade
```

When auto-init branch 2 fires (cwd is inside an existing git-tracked
repo, `$HOME/wiki/.wiki-config` exists, agent is about to create
`./wiki/` linked to the main wiki), the agent should prompt the user
for the tracking choice. Currently the spec says "no prompts, no
confirmations" — fine for the bare-cwd case, but inside an active
repo this silently dumps `./wiki/` (9 files: index.md, schema.md,
log.md, .wiki-config, .gitignore, .manifest.json, plus dirs and
.obsidian/app.json) into the parent repo's working tree.

`scripts/wiki-init.sh:173-177` already prevents the nested-git case
(skips `git init` if cwd is already in a work tree). That's correct
— don't change it. But the user should still be asked: track
the wiki under the parent repo, gitignore it, or some other choice.

Real-session evidence: 2026-05-06, `building-agentskills/` repo.
A user typing `wiki init` had the wrong skill route (separate bug —
see entry below), and the surrounding investigation surfaced the
in-repo silent-init concern.

Spec patch (target file: `skills/using-karpathy-wiki/SKILL.md`,
auto-init section):

> When branch 2 fires AND the cwd is inside a git work tree that
> is NOT the wiki itself, ask the user before creating `./wiki/`:
> tracked by the parent repo, gitignored, or alternative location.
> Document that `wiki-init.sh` already prevents the nested-git
> failure mode so the user knows what's at stake.

Out of scope here: changing the bare-cwd / first-wiki-worthy-moment
path. Auto-init must stay invisible there. This entry only adds a
prompt for the in-active-repo branch.

---

## 0.2.9: investigate — does explicit user-typed `wiki init` need a spec rule?

```yaml
status: needs-decision
priority: p3
effort: low
labels: [0.2.9, investigation, real-session-finding, deliberate-test]
refs:
  - skills/using-karpathy-wiki/SKILL.md  # implicit auto-init only
  - tmp/skill-v1-6ce0c77.md:174-181  # v1 forbidden-command list
```

Real-session test (2026-05-06, `building-agentskills/`): user typed
`wiki init` as a deliberate probe. The agent pattern-matched on the
word "wiki" and ran the wiki-status skill instead. Investigation
surfaced two related questions:

1. Should `using-karpathy-wiki/SKILL.md` document what to do when
   the user types a forbidden command name as natural language?
2. v1 had an explicit forbidden-command list (*"There is no `wiki
   init`, no `wiki ingest`, no `wiki query`, no `wiki flush`, no
   `wiki promote`"*) — the current split skills dropped it.

The user (project owner) decision: **stay invisible**. Auto-init
should not be triggered by user-typed verbs. The agent's job on
`wiki init` (free text) is to recognize it isn't a slash command,
ask what the user actually wants, and not silently route to a
nearby skill.

This entry's purpose: track the open question of whether the loader
needs a clarifying note ("if the user types something that looks
like a wiki command but isn't, just ask"), or whether leaving the
spec silent on this is correct (auto-init invisibility takes
precedence; agent-side pattern-matching bugs aren't a spec issue).

Resolve by either:
- Adding a one-liner to `using-karpathy-wiki/SKILL.md` ("user-typed
  verbs that look like wiki commands but aren't slash commands: ask,
  don't route"), OR
- Closing as "spec stays silent; agent pattern-matching is a model
  issue, not a skill issue."

Decide before the next loader edit; do not bundle with the in-repo
prompt entry above.

---

## 0.2.8: `bin/wiki orient` CLI shortcut for the read-protocol Step A

```yaml
status: deferred
priority: p2
effort: low
labels: [0.2.8, read-protocol, follow-up]
revisit_when:
  "0.2.7 has been in the wild for a release cycle and we have evidence
  about whether the prose-only read protocol produces reliable behavior.
  If agents reliably orient via the prose ladder, ship the conservative
  flavor of `bin/wiki orient` to make orientation cheaper. If agents
  drift on the prose, the CLI shortcut alone won't fix it — first
  sharpen the loader's resist-table."
refs:
  - skills/karpathy-wiki-read/SKILL.md (Step A — orient)
  - skills/using-karpathy-wiki/SKILL.md (Iron Rule 4 + resist-table)
```

The 0.2.7 read protocol restores orientation as a prose procedure: the
agent reads `<wiki>/schema.md` and the relevant `<wiki>/<category>/_index.md`
itself. Two file reads per first-orient. Once-per-session amortization
makes this cheap, but it relies on the agent following the prose.

`bin/wiki orient` would automate the orient step. Two flavors:

- **Conservative**: `bin/wiki orient` (no args) prints schema +
  category indexes + recent log entries. Agent still reads candidate
  pages itself. Collapses two file reads into one CLI call. Lower
  drift surface than the aggressive version because the agent still
  reads the candidates.
- **Aggressive**: `bin/wiki orient "<query>"` does the substring/tag
  match server-side and prints the top candidate paths + summaries.
  Agent jumps straight to Step C. Higher drift risk: the agent might
  skip the index reading and over-trust the server-side match.

Ship conservative first. Promote to aggressive only if real-session
evidence shows the conservative version produces reliable orientation
without the agent skipping it.

---

## 0.2.8: `allowed-tools` scoping on the four skills

```yaml
status: deferred
priority: p2
effort: medium
labels: [0.2.8, security, blast-radius]
revisit_when:
  "0.2.8 planning starts. Orthogonal to read-protocol restoration; was
  deliberately not folded into 0.2.7 to keep the read-protocol commits
  independently revertable from security-scoping commits. Should ship
  alongside `bin/wiki orient` — the new CLI gives the read skill a
  cleaner `allowed-tools` entry."
refs:
  - skills/using-karpathy-wiki/SKILL.md (loader — no scoping; remains permissive)
  - skills/karpathy-wiki-capture/SKILL.md (capture — scope `bin/wiki capture` + `mv` to `inbox/`)
  - skills/karpathy-wiki-read/SKILL.md (read — scope `bin/wiki orient` + Read/Grep/Glob/WebFetch/WebSearch/Task)
  - skills/karpathy-wiki-ingest/SKILL.md (ingest — scope `scripts/wiki-*` + python3 + git)
```

Today no `karpathy-wiki-*` skill declares `allowed-tools`, so each
skill runs with full tool access when active. The blast radius is
correct in practice (each skill only invokes what it needs) but not
harness-enforced. `allowed-tools` makes the scope explicit and
enforced by Claude Code at call time.

Per-skill draft:

| Skill | `allowed-tools` |
|---|---|
| `using-karpathy-wiki` | none — loader, not actor; per upstream pattern, loaders don't restrict |
| `karpathy-wiki-capture` | `Bash(bin/wiki capture:*)`, `Bash(mv * <wiki>/inbox/*)`, `Read`, `Write(/tmp/*)` |
| `karpathy-wiki-read` | `Bash(bin/wiki orient:*)`, `Read`, `Grep`, `Glob`, `WebFetch`, `WebSearch`, `Task` |
| `karpathy-wiki-ingest` | `Bash(scripts/wiki-*:*)`, `Bash(python3 scripts/wiki-*.py:*)`, `Read`, `Edit`, `Write`, `Bash(git ...)`, `Bash(flock ...)` |

The ingester's broad write permissions are scoped to its own spawned
`claude -p` process — main-agent permissions are unaffected.

---

## 0.2.8: cold-no-wiki question path — Iron Rule 4 + no resolvable wiki

```yaml
status: open
priority: p2
effort: low
labels: [0.2.8, read-protocol, cold-start, ux]
revisit_when:
  "Surfaces in real sessions where a user asks a question in a directory
  with no wiki AND no ~/.wiki-pointer (so the read protocol's Step A has
  nothing to orient against). Currently the read skill degrades to
  Step F (web search) with the gap-capture skipped because there's
  nowhere to capture to. Acceptable but ungraceful — the user gets the
  answer but the wiki gains nothing from the cold result."
refs:
  - skills/karpathy-wiki-read/SKILL.md (Step F — cold result)
  - skills/using-karpathy-wiki/SKILL.md (Iron Rule 4)
  - scripts/wiki-init-main.sh (interactive bootstrap; prompts on first run)
  - bin/wiki (silent-bootstrap branch added in 0.2.7 for the capture path)
```

**The gap.** When a user asks a question and:

1. cwd has no `.wiki-config` / `.wiki-mode` (walk-up finds nothing), AND
2. `~/.wiki-pointer` is missing OR points to `none`, AND
3. `~/wiki/` doesn't exist (so 0.2.7's silent bootstrap can't fire)

…the read skill's Step A has no wiki to orient against. Step F runs (web search + cite), but the gap-capture (the bit that grows the wiki toward questions it failed to answer) is skipped because there is no capture target.

The capture path handles this case via the interactive `wiki-init-main.sh` prompt on exit 10. The READ path has no equivalent — Iron Rule 4 fires, the read skill loads, and the protocol degrades silently.

**Proposed fix.** When the read skill's Step A finds no resolvable wiki, the agent should — in the same announce line as the answer — surface a one-line note suggesting `wiki init-main`, so the user is prompted to set up a main wiki the first time the cold-no-wiki path fires. After the user runs it, subsequent questions get the full read protocol with capture-the-gap working.

Two flavors to consider during the 0.2.8 brainstorm:

- **Prose-only:** karpathy-wiki-read/SKILL.md adds a Step A.0 that says "if no wiki resolvable, the answer should include a one-line nudge: *'(No wiki configured here — run `wiki init-main` to start capturing.)'*" Cheap. Relies on the agent following the prose.
- **Structural:** add a `bin/wiki ensure-main` (or similar) that the read skill calls at Step A. The CLI either resolves a wiki path (success) OR prints the nudge text + exits non-zero. The agent uses the exit code to decide whether to include the nudge.

Lean prose-only — same reasoning as `bin/wiki orient` deferral. Ship the prose first; promote to a CLI gate only if real-session evidence shows the prose nudge gets skipped.

Surfaced 2026-05-06 in conversation about how the wiki behaves in fresh
directories — same conversation that shipped 0.2.7's silent pointer
bootstrap (which closed the equivalent gap on the capture path).

---

## v2.5: migrate `.ingest.log` to `.ingest.jsonl` (dual-artifact pattern)

```yaml
status: deferred
priority: p2
effort: medium
labels: [v2.5, format-alignment, follow-up]
revisit_when:
  "v2.5 planning starts, OR `.ingest.log` becomes painful (grep failures
  due to prose-bleed, tooling that needs jq queries against ops history,
  or test fixtures that depend on the current text format)."
refs:
  - docs/superpowers/specs/2026-05-05-karpathy-wiki-v2.4-executable-protocol-design.md (Deferred to v2.5 section)
  - scripts/wiki-lib.sh (`_wiki_log` writes timestamp-prefixed text today)
  - ~/wiki/concepts/agent-vs-machine-file-formats.md (canonical format-choice doctrine)
```

`.ingest.log` is currently a hybrid: the structured `_wiki_log` helper
writes timestamp-prefixed text, AND ingester stdout bleeds into the same
file as free-form prose ("Ingest complete..."). Per the wiki's own
`concepts/agent-vs-machine-file-formats.md`, machine-write/agent-read
event logs should be **JSONL canonical + markdown rendered on demand** —
the same dual-artifact pattern v2.4 adopts for `.ingest-issues.jsonl`.

v2.5 work:

- Convert `_wiki_log` to emit JSON Lines instead of prefixed text.
- Route the free-form ingester stdout away from `.ingest.log`. Most of
  it is already captured into `log.md` (the agent-facing log); the
  current `.ingest.log` bleed is accidental, not load-bearing.
- Add `wiki ops` CLI to render `.ingest.jsonl` to markdown on demand.
- Update test fixtures and any debug scripts that grep `.ingest.log`.

Carved out of v2.4 to ship the JSONL-issue-stream pattern in isolation.
Once v2.4's `.ingest-issues.jsonl` has lived in the wild for a release
cycle, v2.5 applies the same pattern to the ops log with confidence
(and reuses the same render-on-demand machinery).

---

## `wiki-migrate-v2.2.sh`: regex misses inline-list `sources:` frontmatter

```yaml
status: open
priority: p3
effort: low
labels: [post-mvp, migration-script, known-imperfection]
revisit_when:
  "Any future v2.2-style migration is planned, OR a wiki-doctor pass needs
  to rewrite frontmatter sources entries en masse."
refs:
  - scripts/wiki-migrate-v2.2.sh (`migrate_rewrite_frontmatter_sources`,
    line ~67, regex `^(  - )sources/`)
  - docs/superpowers/plans/2026-04-24-karpathy-wiki-v2.2.md (Task 60)
```

The migration script's frontmatter regex `^(  - )sources/` only matches the
block-list form (each item on its own line with `  - ` prefix), not the
inline-list form (`sources: ["sources/x"]` on one line). During Task 61's
live run against `~/wiki/`, the script silently missed
`concepts/micro-editor-over-nano.md` because that page used inline-list
form; the implementer manually rewrote it after the page validator caught
the dangling reference. No data loss, but the script is incomplete. Sharpen
to handle both forms (probably by switching from grep+sed to a YAML-aware
Python rewrite) before any v2.2-style migration reruns.

---

## Subagent reformatting hazard: TODO.md autoformatted on Task 62 commit

```yaml
status: open
priority: p3
effort: low
labels: [process, subagent-discipline, known-imperfection]
revisit_when:
  "If subagent commits keep accumulating off-scope reformatting noise, OR a
  pre-commit hook is added that enforces wrap-width."
refs:
  - commit a832fa5 (Task 62 -- 230-line diff for what should have been a
    section move + 2 frontmatter edits)
  - docs/superpowers/plans/2026-04-24-karpathy-wiki-v2.2.md (Task 62 spec)
```

The Task 62 implementer subagent reflowed the entire TODO.md to ~80-char
wrap as part of its section-move commit (171 insertions, 59 deletions for
substantively a 1-section move + 2 frontmatter line edits). The task brief
said "do not touch any other file"; technically respected (only TODO.md
changed) but spiritually violated (reformatted untouched lines). The reflow
is harmless and arguably an improvement to file readability, but creates
diff noise that obscures real changes in `git log -p`.

Two paths to address: (a) `git revert a832fa5 && redo` for a minimal-diff
version, or (b) accept the reformat and add an explicit "do not reformat
unrelated lines" clause to future implementer prompts. Recommend (b) plus
a shared subagent prompt template that includes the no-reformat clause.

---

## Stop-hook gate for turn-closure enforcement

```yaml
status: deferred
priority: p1
effort: medium
labels: [post-mvp, architecture]
revisit_when:
  "Fresh-session tests show main agent still skipping captures despite the v2.1
  prose gate, OR 3+ real-session misses where the `ls .wiki-pending/`
  pre-stop-turn check didn't fire."
refs:
  - docs/planning/2026-04-24-karpathy-wiki-v2.1-missed-capture-patch.md#deferred-to-later
  - skills/karpathy-wiki/SKILL.md (turn-closure prose at "Turn closure — before
    you stop")
```

Wire a `hooks/stop.sh` that runs `ls .wiki-pending/ | grep -v archive` and
refuses the Stop matcher if the output is non-empty, so turn-closure becomes
mechanically enforced rather than self-disciplined. Requires schema changes in
`hooks/hooks.json`. The prose in v2.1 is the contract that hook must satisfy.
This is the "real gate" the v2.1 plan reviewer called out as the ultimate fix
for the missed-capture failure mode.

---

## Real `wiki doctor` implementation (not a stub)

```yaml
status: deferred
priority: p1
effort: high
labels: [post-mvp, quality]
revisit_when:
  "After 5-10 real-session ingests accumulate with ingester-stubbed quality
  ratings, so there's meaningful signal for the smart-model re-rate to work on.
  Also triggered if `wiki status` starts reporting a persistent cluster of pages
  below 3.5 quality."
refs:
  - bin/wiki (currently exits 1 with "not implemented")
  - skills/karpathy-wiki/SKILL.md "Quality ratings" section (defines the
    contract doctor must satisfy)
  - docs/planning/2026-04-22-karpathy-wiki-v2.md (scope-cut to stub in v1)
```

`wiki doctor` is stubbed in v2 (`bin/wiki doctor` exits 1 with "not
implemented"). Real implementation re-rates every page's `quality:` block with
the smartest available model, fixes broken cross-references, consolidates
tag-drift synonyms, and auto-archives raw sources that are referenced by 5+ wiki
pages. Must NEVER clobber `rated_by: human` blocks. Should emit a summary of
changes made for user review.

---

## `--max-turns` / `--max-budget-usd` on spawned ingester

```yaml
status: rejected
priority: p3
effort: low
labels: [defers-to-user-policy]
revisit_when:
  "N/A — user explicitly rejected in v2.1 planning. Budget and turn caps are
  user-account concerns, not skill concerns. Revisit ONLY if the skill gets used
  in constrained contexts (e.g., GitHub Actions CI) where a runaway ingester
  would block the pipeline."
refs:
  - docs/planning/2026-04-24-karpathy-wiki-v2.1-missed-capture-patch.md#deliberate-scope-cuts
```

Kept in this file with `status: rejected` specifically so future-us doesn't
re-propose the same thing without seeing the prior reasoning. The underlying
concern (runaway ingester) is handled by the stalled-capture recovery mechanism
shipped in v2.1.

---

## `--bare` + explicit `--allowedTools` on the spawned ingester

```yaml
status: blocked
priority: p2
effort: medium
labels: [defers-to-anthropic]
revisit_when:
  "Anthropic ships the announced `--bare`-as-default-for-`-p` change (documented
  but undated as of 2026-04-24). When that lands, the `--bare` flag becomes
  default and the karpathy-wiki ingester should explicitly opt IN to loading the
  karpathy-wiki skill via `--append-system-prompt` to avoid breaking."
refs:
  - ~/wiki/concepts/claude-code-headless-subagents.md (flag documentation)
  - docs/planning/2026-04-24-karpathy-wiki-v2.1-missed-capture-patch.md#deliberate-scope-cuts
```

Token savings and CI reproducibility. The ingester currently relies on skill
discovery to know how to act (its prompt says "Follow the karpathy-wiki skill's
INGEST operation exactly"). `--bare` skips skill discovery, so this change
requires either passing the skill path via `--append-system-prompt` or
documenting the tradeoff explicitly.

---

## `--json-schema` structured ingester output

```yaml
status: deferred
priority: p3
effort: high
labels: [post-mvp, reliability]
revisit_when:
  "Ingester starts producing malformed output in the wild — e.g. missing quality
  blocks, wrong date format, or the existing Tier-1 lint (read back every page
  link) starts failing regularly. Currently no pain point."
refs:
  - ~/wiki/concepts/claude-code-headless-subagents.md (--json-schema
    documentation)
  - scripts/wiki-validate-page.py (the current pain-point surface if malformed
    output lands)
```

Cleaner success signal than parsing `.ingest.log`. Let the ingester emit a
structured summary object (pages created, pages updated, manifest entries
written, validator result) that the parent can parse to decide whether to retry
or surface an error.

---

## Real test coverage for SKILL.md prose rules

```yaml
status: deferred
priority: p2
effort: high
labels: [test-infra, post-mvp]
revisit_when:
  "Any SKILL.md regression where a prose rule stops being followed. Currently
  the rules are validated manually via real-session observation; no automated
  check."
refs:
  - tests/green/GREEN-results.md (current manual RED-GREEN-REFACTOR evidence)
  - docs/planning/2026-04-24-karpathy-wiki-v2.1-missed-capture-patch.md#deliberate-scope-cuts
```

Agent-facing rules (turn closure, body floor, orientation protocol,
missed-cross-link check) are not unit-testable without a harness that spawns
`claude -p` against a fixture transcript and inspects the resulting capture file
/ wiki pages. Build one post-MVP when the rules start regressing enough to hurt.

---

## Obsidian: pre-enable core plugins in wiki init script

```yaml
status: open
priority: p2
effort: low
labels: [ux, init-script]
revisit_when: N/A
refs:
  - ~/wiki/concepts/wiki-obsidian-integration.md (full spec — when that capture
    lands)
  - scripts/wiki-init.sh (target of the change)
```

The init script writes a minimal `.obsidian/app.json` with just filters. Extend
it to also write `.obsidian/core-plugins.json` enabling Backlinks, Outgoing
Links, Graph View, Tags Pane, Page Preview, Properties View — all built-in
Obsidian core plugins that make the wiki's cross-referenced structure actually
usable. Without this, every new user has to open Settings → Core plugins and
toggle each manually. Takes ~5 minutes to add to the init script; saves every
future user ~5 minutes and a lot of "wait why doesn't Obsidian show backlinks."

---

## Consider migration: TODO.md → GitHub Issues when repo goes public

```yaml
status: open
priority: p3
effort: low
labels: [process]
revisit_when:
  "Repo gets pushed to `toolboxmd/karpathy-wiki` and made public. GitHub Issues
  is the natural home once there are external contributors / visibility."
refs:
  - TODO.md (this file; one-shot migration via `gh issue create` per entry)
```

Once the v2-rewrite branch merges to `main` and the repo goes public, migrate
each open / deferred item in this file to a GitHub Issue with matching labels.
Preserve the YAML frontmatter fields as issue labels/milestones where possible.
`status: rejected` items stay in this file as historical record (don't migrate —
issues don't want to be "closed as rejected" with full rationale; that belongs
in the repo's history). Close this `TODO.md` file once migration is complete (or
leave it as a pointer to the Issues tracker).

---

# Shipped

Items closed here rather than deleted, so the commit history of this file
captures "what was once on the list." When a TODO item ships:

1. Move its `##` section here.
2. Change `status: shipped`.
3. Add `shipped_in:` field pointing at the closing commit SHA.
4. Keep the original body paragraph for posterity.

## 0.2.7: read-from-wiki protocol restored (post-v2.4 regression fix)

```yaml
status: shipped
priority: p0
effort: medium
labels: [0.2.7, read-protocol, regression-fix]
shipped_in: TBD  # filled in by the closing commit
refs:
  - skills/using-karpathy-wiki/SKILL.md (Iron Rule 4 + resist-table)
  - skills/karpathy-wiki-read/SKILL.md (new on-demand skill)
  - skills/karpathy-wiki-capture/SKILL.md (body-sufficiency dedup)
  - hooks/session-start (multi-platform JSON output)
```

The v2.4 split (`using-karpathy-wiki` + `karpathy-wiki-capture` +
`karpathy-wiki-ingest`) silently dropped the read-from-wiki protocol.
The legacy v2.3 skill had Iron Rule 6 ("Never answer a wiki-eligible
question from training data without running orientation first") plus
the orientation procedure ("read schema.md, index.md, last 10 entries
of log.md"). Capture-authoring moved to one skill, ingest-orientation
moved to another, and read-orientation was lost.

User caught the regression: agents stopped checking the wiki before
answering. 0.2.7 restores it, but BETTER than the legacy:

- New Iron Rule 4 in the loader: "NO ANSWERING ANY USER QUESTION
  WITHOUT ORIENTING FIRST." Orient-once-per-session amortization
  framing makes the cost honest (two file reads on the first
  question, near-zero on subsequent).
- New `karpathy-wiki-read` skill with a deterministic 6-step
  ladder (A-F). No agent judgement at branch points: candidate
  count thresholds (0 → cold/web; 1-5 → inline; 6+ → Explore
  subagent).
- Resist-table covers the "trivial / general knowledge / pure
  syntax" rationalizations that produced the v2.4 silent drop.
- Subagent dispatch (Step E) for breadth questions; main-agent
  inline read for targeted ones. Maps to the user's
  `~/.claude/CLAUDE.md` Task Delegation rule.
- Cite contract: every wiki-grounded answer cites the page paths
  it drew from. Uncited claims must be flagged "(from training
  data)."
- Web search + capture-the-gap (Step D and Step F) replaces the
  legacy "answer from training data with caveat" — the wiki grows
  toward questions it failed to answer.

Also shipped in 0.2.7 (orthogonal but bundled):

- Multi-platform SessionStart hook output (Cursor / Claude Code
  / Copilot CLI / SDK-standard). Mirrors obra/superpowers v5.1.0.
- Body-sufficiency section dedup in `karpathy-wiki-capture`.
- Legacy `skills/karpathy-wiki/SKILL.md` deleted (deprecated in v2.4,
  removed now per upstream pattern of "split → delete in same release").
- `CLAUDE.md` "If you are an AI agent" section (mirrors upstream's
  contributor guidelines for AI-slop PR prevention).

## Re-run the Opus auditor after real-session usage accumulates

```yaml
status: shipped
priority: p1
effort: low
labels: [quality, validation]
shipped_in: 5a1d209
refs:
  - docs/planning/2026-04-24-karpathy-wiki-v2-hardening.md#deferred-to-later
    (enumerated targets)
  - tests/green/GREEN-results.md (convergence baseline)
```

Likely future audit targets (not commitments):

- Whether `quality.overall < 3.5` pages cluster in any particular category or
  tag — signal the ingester is chronically over-cautious in a domain.
- Whether tag-drift repeats despite `wiki-lint-tags.py` — heuristics may need
  tuning.
- Whether `sources/` pointer pages degenerate into dead formality (only 1-2
  lines each) and should merge into `raw/` metadata.
- Whether the `quality:` block should carry a per-dimension rationale field
  (currently only overall `notes`).
- Whether `wiki doctor` should actually be implemented now that there is a
  rating surface to rate against.

Audit shipped 2026-04-24 (`docs/planning/2026-04-24-karpathy-wiki-v2.2-audit.md`); v2.2-hardening plan executed Tasks 50-62 closing 6 of the 16 findings (architectural cut + 5 mechanical fixes). The remaining 10 findings remain on TODO.md or defer to v2.3 / `wiki doctor`.

## `ideas/` category in the wiki schema

```yaml
status: shipped
priority: p3
effort: medium
labels: [wiki-schema]
shipped_in: 2b91706
refs:
  - ~/wiki/concepts/wiki-ideas-category-convention.md (the convention page)
  - ~/wiki/schema.md (now contains "## Ideas Category Extension" section per v2.3)
  - scripts/wiki-validate-page.py (validates type: ideas via discovery; no special-case needed)
```

The `ideas/` category was already a wiki-level convention pre-v2.3 (with required `status:` and `priority:` frontmatter fields). v2.3 cemented it into the auto-discovery contract: `ideas/` is one of the four seed categories `wiki-init.sh` creates, validator accepts `type: ideas` because discovery returns it from the directory tree, `wiki-status.sh` counts it, `wiki-backfill-quality.py` walks it. The decision "keep or drop" is settled — the wiki has 5 idea pages today (action-tokenization-v0-build, obsidian-rich-init, sessionstart-hook-inject-skill, validate-idea-pages, wiki-doctor-real-implementation), all earning their keep as durable forward-looking items distinct from this plugin's TODO backlog. Different scopes: TODO.md = plugin-development backlog (in-repo). `ideas/` = wiki-knowledge forward-looking items (in the wiki itself, surfaced to agents via index/discovery).

## v2.3: flexible auto-discovered categories + recursive _index.md tree

```yaml
status: shipped
priority: p1
effort: high
labels: [v2.3, architecture, schema]
shipped_in: 2b91706
refs:
  - docs/planning/2026-04-25-karpathy-wiki-v2.3-flexible-categories-design.md
  - docs/planning/2026-04-25-karpathy-wiki-v2.3-spec.md
  - docs/planning/2026-04-25-karpathy-wiki-v2.3-plan.md
  - docs/planning/transcripts/2026-04-26-auto-discovered-categories.md
  - docs/planning/transcripts/2026-04-26-category-discipline-ceiling.md
  - docs/planning/transcripts/2026-04-26-reply-first-ordering.md
```

v2.3 deletes the validator's hardcoded `VALID_TYPES` whitelist and makes the directory tree the single source of truth for categories. A user/agent can `mkdir <wiki-root>/<name>/` to create a category — discovery picks it up on the next ingest, schema.md regenerates, sub-indexes auto-build. `type:` frontmatter equals `path.parts[0]` (plural form); validator enforces this as a hard violation.

Other shipped pieces:
- Recursive per-directory `_index.md` files replace the legacy 25 KB monolithic `index.md`. Root MOC ~10 lines.
- Wiki-root-relative cross-link convention (`/concepts/foo.md`) for nested pages.
- Three category-discipline rules (≥3 pages per category, depth ≤4 hard cap, ≥8 categories soft ceiling).
- Reply-first turn ordering rule documented in SKILL.md (was implicit in line 444 of the resist-table; now prescriptive).
- Live wiki migrated: 60 pages got `type:` rewritten plural; 4 named pages moved from `concepts/` to `projects/toolboxmd/<project>/`; outbound + inbound cross-links rewritten to leading-`/` form; 8 new `_index.md` files generated.
- Pre-existing bugs cleaned up alongside: `wiki-init.sh` no longer seeds deleted `sources/` and now seeds `ideas/`; `wiki-status.sh` and `wiki-backfill-quality.py` rewired from hardcoded category lists to discovery-driven walks.
- Bundle directory is a symlink to `/scripts/` (verified, structurally drift-proof). Symlink-guard test in `test-bundle-sync.sh`.

Plan executed via subagent-driven-development (~30 commits across phases A.1, A.2, B, C, D, E). Both reviewer passes (spec-compliance + code-quality) caught real bugs: parser drift in Task 0 (4 silent divergences from the existing validator parser, fixed via oracle test), reserved-dir descendant leak in Task 11's index builder (would have inflated subdirectory counts), and root-dir double-write in single-directory mode. Phase D's atomic moves+relinks contract held — validator passed clean between every commit. Two tarballs preserved at `~/wiki-backup-pre-v2.3-phase-{a,d}-*.tar.gz` as outermost rollbacks.

## v2.4 deferrals (out of scope from v2.3)

```yaml
status: open
priority: p2
effort: medium
labels: [v2.4, follow-up]
refs:
  - docs/planning/2026-04-25-karpathy-wiki-v2.3-spec.md (out-of-scope section)
```

Items deferred from v2.3:

- **Automated retroactive global link migration** — v2.3 only rewrote inbound links to the 4 moved pages; ~50+ other relative links throughout the wiki stayed in their existing form. A bulk migration script that converts every `../foo.md` to `/category/foo.md` would polish the wiki but is non-urgent.
- **Skill-bundling sync mechanism** — currently `/skills/karpathy-wiki/scripts/` is a symlink to `../../scripts/`, which works for development but breaks if the plugin is installed via `claude plugin install` (which resolves the symlink to a real copy). A proper sync mechanism (build step, symlink-aware install, single canonical location) would be cleaner. v2.3 ships hand-copy + symlink + CI guard; v2.4 picks the right machinery.
- **`wiki create-category <name>` CLI** — v2.3 contract is `mkdir`. If friction surfaces from heavy use, a small CLI wrapper that does `mkdir + name validation + initial _index.md skeleton` is straightforward.
- **Cosmetic reorg of historical migration scripts to `scripts/historical/`** — `wiki-migrate-v2-hardening.sh`, `wiki-migrate-v2.2.sh`, `wiki-migrate-v2.3.sh` accumulate. Moving them to `scripts/historical/` (or similar) keeps the active scripts dir clean.
- **`wiki doctor` real implementation** — still a stub. Now with the recursive `_index.md` tree, the smartest-model re-rate path is unblocked; orphan repair and tag-synonym consolidation also become cleaner.
- **Per-`_index.md` schema-proposal firing** — the SKILL.md ingester step 7.6 has prose for this but it's not exercised by an actual ingester run yet (would happen during an organic ingest after v2.3 ships).
- **Singular `type:` orphan recovery** — if anyone hand-writes a page with singular `type:` post-v2.3, the validator hard-rejects. A friendlier `wiki fix-type` CLI that runs `wiki-fix-frontmatter.py` on the offending page would smooth this.

Each of these is a candidate for a future ship; none block v2.3.

## Project-wiki auto-resolution at capture time (architectural — surfaced 2026-04-27 post-v2.3 ship)

```yaml
status: shipped
priority: p1
effort: medium
labels: [v2.4, architecture, ingest, project-wiki]
shipped_in: c82677b  # bin/wiki capture/use/init-main subcommands; wiki-resolve.sh in 7377a28; wiki-init-main.sh in a34be9d; wiki-use.sh in 1cce0cf
refs:
  - scripts/wiki-resolve.sh (non-interactive resolver, 5 exit codes)
  - scripts/wiki-init-main.sh (silent migration + bootstrap prompts)
  - scripts/wiki-use.sh (per-cwd mode switch: project|main|both)
  - bin/wiki capture (calls resolver before writing to .wiki-pending/)
  - skills/karpathy-wiki/SKILL.md (lines 74-91: "When no wiki exists" auto-init algorithm — now executable)
  - scripts/wiki-lib.sh (lines 47-65: wiki_root_from_cwd walks up looking for .wiki-config)
  - scripts/wiki-init.sh (supports project mode: `wiki-init.sh project ./wiki ~/wiki`)
```

**SHIPPED in v2.4 Leg 2 (2026-05-06).** The "executable protocol" theme: SKILL.md prose is now backed by `wiki-resolve.sh` which fires at capture time. `bin/wiki capture` invokes the resolver; `wiki use project|main|both` lets the user override; `wiki init-main` bootstraps the main pointer. Original gap analysis preserved below.

---

**Bug surfaced post-v2.3-ship.** The architecture supports project-wiki-in-cwd + main-wiki-in-`$HOME` (SKILL.md describes the three-case algorithm; `wiki-init.sh project` mode exists; `wiki_root_from_cwd` walks up looking for `.wiki-config`). But in practice agents always write captures to `$HOME/wiki/` even when in a project directory.

**Why:** the auto-init algorithm is PROSE in SKILL.md, not a SCRIPT that fires at capture time. Concretely:

- `wiki_root_from_cwd` (in `wiki-lib.sh`) walks up from cwd. If no parent has `.wiki-config`, it returns nothing.
- SKILL.md says "if `$HOME/wiki/.wiki-config` exists AND cwd is outside a wiki, CREATE a project wiki at `./wiki/` linked to `$HOME/wiki/`."
- But no script automates that creation. Captures default to `$HOME/wiki/` because that's where the manually-initialized main wiki is.
- The agent doesn't run the auto-init branching at every capture — it assumes wiki-resolution already happened.

**Symptom in v2.x usage:** every project session this user has ever run has captured to `$HOME/wiki/`, not to a project-local `./wiki/`. The project-wiki branch of the algorithm is dead code in practice.

**Downstream effect:** the propagation mechanism (SKILL.md line 385 — project wiki decides whether each capture is general-interest or project-specific, propagates to main wiki when general) is unused. Without project wikis existing, there's nothing to propagate.

**The cleaner v2.4 architecture:**

Add a `wiki-resolve.sh` (or extend `wiki-spawn-ingester.sh`'s entry point) that runs at the start of every capture flow:

1. If `wiki_root_from_cwd` finds a `.wiki-config`, use it.
2. Else if `$HOME/wiki/.wiki-config` exists AND cwd is in a git repo (or has another "this is a project" signal), AUTO-CREATE `./wiki/` linked to `$HOME/wiki/` via `wiki-init.sh project ./wiki $HOME/wiki`.
3. Else fall back to `$HOME/wiki/`.

Capture and spawn-ingester scripts call this resolver instead of hardcoding `$HOME/wiki/`.

**Open design questions for the v2.4 brainstorm:**

- **Auto-create vs prompt.** Should step 2 silently create `./wiki/` (zero-friction; user might be surprised by a new directory in their repo) or prompt the user (interrupts the agent flow with a Y/N) or require an explicit opt-in (`wiki use-local`)?
- **What counts as "project context"?** Presence of `.git/`? Presence of any specific marker file (`package.json`, `pyproject.toml`, etc.)? Fall through to "ask user once per cwd"?
- **Backfill: should existing captures in `$HOME/wiki/` get reclassified?** Probably no — they were captured during sessions where the user thought they were going to main wiki. Don't move them retroactively.

**Why this didn't ship in v2.3:** v2.3 was about category-flexibility within a single wiki. The cross-wiki-resolution gap is orthogonal. Surfaced in conversation post-ship when the user noticed that not a single agent had ever created a project-wiki for them, despite working in projects regularly.

**Combines with the raw-direct ingest gap above:** both are "the SKILL.md describes a flow but no SCRIPT enforces it" failure mode. v2.4 should address them together as the "executable-protocol" theme: SKILL.md prose backed by hooks/scripts that actually fire.

---

## Raw-direct ingest path (architectural — surfaced 2026-04-27 post-v2.3 ship)

```yaml
status: shipped
priority: p1
effort: medium
labels: [v2.4, architecture, ingest]
shipped_in: 7faeeed  # SessionStart inbox/ scan + raw-direct capture + raw-recovery; manifest lock in d23a53b; reserved-set update in 715925c; ingest-now in ff91b06
refs:
  - hooks/session-start (inbox/ scan, raw-direct capture emission, raw-recovery)
  - scripts/wiki-manifest-lock.sh (cross-platform lock + atomic manifest rename)
  - scripts/wiki-ingest-now.sh (on-demand drift+drain)
  - bin/wiki ingest-now (CLI entry point)
  - skills/karpathy-wiki/SKILL.md (line 121: "user adds a file to raw/" trigger)
  - skills/karpathy-wiki/SKILL.md (line 502: Iron Rule 5 "Never modify files in raw/")
```

**SHIPPED in v2.4 Leg 3 (2026-05-06).** Files dropped into `inbox/` (the new unified drop zone, replacing reserved `Clippings/`) are auto-ingested without a fabricated wrapper capture: the SessionStart hook emits a `capture_kind: raw-direct` capture pointing at the absolute file path; the ingester reads the file directly and generates a wiki page. Files accidentally dropped in `raw/` are recovered to `inbox/` under the manifest lock. Original gap analysis preserved below.

---

**Bug surfaced post-v2.3-ship.** The capture-driven ingest architecture conflates two distinct semantic flows:

1. **Capture-driven ingest** (conversation IS the source): A conversation surfaced durable knowledge → agent writes a capture → ingester reads capture body → generates wiki page. The capture is the canonical encoding of what the conversation produced; the file (if any) is supporting evidence.

2. **Raw-direct ingest** (file IS the source): A file appears on disk (Obsidian Clippings, manual download, research-tool export). The file IS the durable content. There is no conversation context to encode.

Today's design only supports flow 1. SKILL.md line 121 lists "user adds a file to raw/" as a capture trigger — but that's misleading: the actual mechanism requires the agent to write a capture WRAPPING the raw file (`evidence: <abs-path>`, `evidence_type: file`), which is a fabrication step for material with no conversation behind it. The capture body becomes meta-text like "this is a Clippings file, please process it," failing the body-floor sufficiency rule and producing low-information wiki pages.

**The cleaner architecture (v2.4 work):**

Add a `wiki-ingest-raw.py` mode (or `--from-file` flag on the existing ingester) that:
- Copies file to `raw/<basename>` with manifest entry (`origin: <original-path>`).
- Reads the file directly (no capture middleman).
- Generates a wiki page from file content; `sources:` points at `raw/<basename>`.
- Logs `raw-ingest |` (new verb distinct from `ingest |` for capture-driven runs).

Open design questions to settle in the v2.4 brainstorm:

- **Trigger mechanism:** SessionStart hook scanning `Clippings/`? CLI command (`wiki ingest-raw <file>`)? Filesystem watcher?
- **Agent involvement:** pure auto-ingest, or the raw-direct path produces a draft for next-session agent review (categorization, cross-link enrichment, quality rating)?
- **What about Clippings/?** Currently reserved (validator skips, discovery skips). Either keep reserved + require explicit move to a "queue" dir, OR auto-process Clippings/ via the raw-direct path on session start.

**Why this matters for the wiki use case:** Obsidian Web Clipper users will drop external content (articles, X posts, technical docs) into Clippings/ regularly. Without raw-direct, every clipping requires the user to invoke an agent + write a thin capture + spawn ingester. With raw-direct, drop-and-go works.

**Why this didn't ship in v2.3:** the bug surfaced AFTER v2.3 shipped, in conversation about Obsidian Clipper behavior. The architectural fix is non-trivial (new ingest path, new tests, new log verb, design choices about agent involvement). Shipping it would have been scope creep.

**What v2.3 ships in the meantime:** the misleading "user adds a file to raw/" trigger remains in SKILL.md. Pragmatically the agent can still read a Clippings file and write a thin capture, but it's a workaround, not the right architecture. v2.4 fixes properly.

---

## SessionStart hook injects SKILL.md content (using-superpowers pattern)

```yaml
status: shipped
priority: p2
effort: low
labels: [post-mvp, architecture, v2.4]
shipped_in: cca22c5  # plus skill split: d72fa75 (using-karpathy-wiki loader), f349439 (capture skill), 58284a0 (ingest skill), c0757db (deprecate legacy skill)
refs:
  - hooks/session-start (step 2: loader injection via hookSpecificOutput.additionalContext)
  - skills/using-karpathy-wiki/SKILL.md (the loader body that gets injected)
  - skills/karpathy-wiki-capture/SKILL.md (main agent on-demand)
  - skills/karpathy-wiki-ingest/SKILL.md (spawned ingester only)
  - skills/karpathy-wiki/SKILL.md (legacy, marked DEPRECATED in v2.4)
  - ~/wiki/concepts/claude-code-skill-autoload-mechanisms.md (revisit criteria + implementation sketch)
```

**SHIPPED in v2.4 Leg 1 (2026-05-06).** The session-start hook reads `skills/using-karpathy-wiki/SKILL.md` and emits its body wrapped in `<EXTREMELY_IMPORTANT>` tags as `hookSpecificOutput.additionalContext`, so the agent reads the wiki rules in every conversation regardless of whether it chooses to invoke. The legacy `skills/karpathy-wiki/SKILL.md` was split into three focused skills (`using-karpathy-wiki` loader, `karpathy-wiki-capture` for the main agent, `karpathy-wiki-ingest` for the spawned ingester) so subagents and ingesters get only the surface they need. Subagent fork-bomb guard already in place from 0.2.4 prevents the loader from re-firing inside dispatched subagents.
