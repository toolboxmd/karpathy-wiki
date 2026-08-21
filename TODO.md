---
title: karpathy-wiki TODO
status: living-document
last_reviewed: 2026-08-21
---

# TODO

Concrete follow-ups and next actions for the plugin. This file is not shipped
history and is not a known-problems archive.

Use the other project ledgers for different kinds of information:

- `CHANGELOG.md` records shipped changes.
- `ISSUES.md` tracks known bugs, risks, regressions, and technical debt.
- `IDEAS.md` tracks product ideas, experiments, future options, and rejected
  ideas kept only to avoid re-proposal.

Remove TODO entries once shipped, or move their shipped context to
`CHANGELOG.md`. Promote an entry to GitHub Issues only when public,
collaborative, or automated work is actually starting.

## 0.2.9: in-repo project-wiki — prompt user for tracking choice

```yaml
status: partial
priority: p1
effort: low
labels: [0.2.9, auto-init, ux, real-session-finding]
shipped_in_part:
  - 84e77b2  # bin/wiki capture: headless + cwd unconfigured now aborts
             # with orphan + nudge instead of silent main-only auto-select.
             # Covers the capture-time half of the silent-default problem.
             # The init-time half (wiki-init.sh branch 2 inside an
             # existing git tree) is still open below.
refs:
  - scripts/wiki-init.sh:173-177  # nested-git auto-prevention
  - skills/using-karpathy-wiki/SKILL.md  # auto-init "no prompts" rule
  - tmp/skill-v1-6ce0c77.md:42-57  # original auto-init cascade
  - bin/wiki:194-225  # capture-time abort path (shipped 84e77b2)
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
  - skills/karpathy-wiki-ingest/SKILL.md "Quality ratings" section (defines the
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
## Review which local ledger entries should become GitHub Issues

```yaml
status: open
priority: p3
effort: low
labels: [process]
revisit_when:
  "Starting public, collaborative, or automated work on a local TODO or ISSUES
  entry."
refs:
  - TODO.md
  - ISSUES.md
```

The repository is public, but do not migrate local ledgers wholesale. Promote a
local entry to GitHub Issues only when public, collaborative, or automated work
is actually starting. Preserve useful metadata as labels, milestones, or issue
body context. Leave purely local notes in `TODO.md`, `ISSUES.md`, or `IDEAS.md`
according to the ledger convention.
