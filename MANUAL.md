# karpathy-wiki user manual (v0.2.7)

A short reference for the karpathy-wiki plugin as it ships in v0.2.7. Covers setup, the five common scenarios, and what the plugin handles automatically vs requires explicit config.

For installation, see [README.md](README.md). For deferred work, see [TODO.md](TODO.md). For contributing, see [CLAUDE.md](CLAUDE.md).

## What changed in 0.2.7

- **Iron Rule 4** in the loader: `NO ANSWERING ANY USER QUESTION WITHOUT ORIENTING FIRST`. Restored after the v2.4 split silently dropped it.
- **New `karpathy-wiki-read` skill** with a deterministic 6-step ladder. No agent judgement at branch points.
- **Threshold 5/6** for inline-read vs Explore-subagent dispatch (≤5 candidates → inline; 6+ → subagent).
- **Three-platform JSON output** in `hooks/session-start`: `additional_context` for Cursor, `hookSpecificOutput.additionalContext` for Claude Code (unchanged), `additionalContext` for Copilot CLI / SDK-standard. Mirrors `obra/superpowers` v5.1.0.
- **Silent bootstrap of `~/.wiki-pointer`** from `$HOME/wiki/` when the resolver returns exit 10 AND `$HOME/wiki/.wiki-config` has `role = "main"` AND structural files exist. Pre-existing wiki users no longer hit a prompt or orphan on first capture after upgrade.
- **Legacy `skills/karpathy-wiki/SKILL.md`** (DEPRECATED in v2.4, 549 lines) deleted.
- **Capture skill body-sufficiency dedup** — the section was duplicated across two scrolls pre-0.2.7.

Tests: 58/58 pass.

## One-time setup per machine

Two things must exist before captures work cleanly:

1. **`~/.wiki-pointer`** — single line of text. Either an absolute path (e.g. `/Users/you/wiki`) or the literal word `none` (means "no main wiki configured; project wikis only"). Created by:
   - `wiki init-main` (interactive prompt: "point at existing", "create at ~/wiki/", or "none").
   - The 0.2.7 silent bootstrap (auto-fires on first capture if `~/wiki/` is structurally a valid main wiki).
   - Manual `echo "<path>" > ~/.wiki-pointer` (functionally identical to the bootstrap).

2. **A main wiki at the path the pointer references.** Structurally requires `.wiki-config` (with `role = "main"`), `schema.md`, `index.md`, and `.wiki-pending/` directory. Created by `wiki-init.sh main <path>`. Default path is `~/wiki/`.

If neither exists when you run `wiki capture`, the resolver returns exit 10. `bin/wiki` either prompts (interactive) or saves your body to `~/.wiki-orphans/` (headless).

## Per-directory config (optional)

Run `wiki use <mode>` once per directory you want a non-default capture flow in:

- `wiki use project` — writes `.wiki-config` with `role = "project"` to cwd. Initializes `./wiki/` if missing. Captures from this dir flow to `./wiki/.wiki-pending/`. The project wiki's ingester decides per-capture whether to propagate general-interest content to the main wiki.
- `wiki use main` — writes `.wiki-mode` with literal string `main-only` to cwd. Captures flow only to `~/wiki/`.
- `wiki use both` — writes `.wiki-config` with fork mode. Captures fork: same content goes to BOTH `./wiki/` AND `~/wiki/`.

Without `wiki use`, headless captures auto-select `main-only` the first time and silently write `.wiki-mode`. Interactive captures prompt with the three options.

## What "automatic" means

Per-session, no setup needed:

- SessionStart hook injects the loader skill (`using-karpathy-wiki/SKILL.md`) as `additionalContext`. The agent has Iron Rules 1-4, the trigger taxonomy, and the resist-table loaded in every conversation.
- Pending captures in `<wiki>/.wiki-pending/` are drained on every SessionStart — one detached `claude -p` ingester per capture.
- Files in `<wiki>/inbox/` are picked up and turned into `capture_kind: raw-direct` captures (no fabricated wrapper body needed).
- Files in `<wiki>/raw/` that are not in the manifest are recovered to `<wiki>/inbox/` under the manifest lock (raw-recovery rule).
- `.processing` files older than 10 minutes are reclaimed (renamed back to `.md`) so the next ingester can pick them up.
- The fork-bomb guard short-circuits the hook when `WIKI_CAPTURE` or `CLAUDE_AGENT_PARENT` is set — keeps spawned ingesters and dispatched subagents from re-firing the SessionStart machinery.
- Iron Rule 4 fires for every user question. Agent loads `karpathy-wiki-read` and runs the 6-step ladder to orient before answering.

## The 6-step read ladder

Every step is deterministic. No agent judgement at branch points.

- **Step A — Orient.** Read `<wiki>/schema.md` + the relevant `<wiki>/<category>/_index.md`. Once per session; subsequent questions reuse the cached content (marginal cost near-zero).
- **Step B — Count signal-matching candidates** in `_index.md`. Branch on count: `0 → Step F`, `1-5 → Step C`, `6+ → Step E`.
- **Step C — Inline read** all 1-5 candidates. Sufficient to answer the question? `YES → cite + answer (done)`. `NO → Step D`.
- **Step D — Gap-fill via web search** for the specific claim the wiki did not cover. Cite both wiki and web. ALWAYS write a capture noting the gap (the wiki should grow toward questions it failed to answer fully).
- **Step E — Spawn an Explore subagent** for breadth questions (6+ candidates). Subagent runs the orient procedure inside its own context (no page-count cap). Returns synthesis with citations. Main agent uses the synthesis as the answer's basis. No word cap on the synthesis; target shape is "terse but complete."
- **Step F — Cold result** (zero candidates). Web search + always capture so the next session is not cold for this topic.

**Cite contract.** Every wiki-grounded answer cites the page paths it drew from. Uncited claims must be flagged "(from training data; not in wiki)" — the only allowed case for uncited claims.

## The 5 common scenarios

### Scenario 1 — Starting Claude in a fresh directory

The SessionStart hook runs in this order:

1. Subagent / ingester guard (exits if `WIKI_CAPTURE` or `CLAUDE_AGENT_PARENT` set).
2. Loader injection — emits `using-karpathy-wiki/SKILL.md` body as `additionalContext`.
3. Wiki resolution — walks up from cwd looking for `.wiki-config`. Fresh dir has none.
4. (Skipped if no wiki found.) Inbox scan + drift detection + drain + stale reclaim.

Result: agent has the wiki rules loaded; cwd has no wiki to capture into yet.

### Scenario 2 — Asking a question

Iron Rule 4 fires. Agent loads `karpathy-wiki-read` and runs Steps A-F against the resolved wiki (`~/wiki/` if `~/.wiki-pointer` is set; else falls through to Step F as a "cold-no-wiki" case).

The cold-no-wiki case has a known gap: Step F's gap-capture skips because there's nowhere to capture to. Tracked in [TODO.md](TODO.md) as a 0.2.8 candidate ("0.2.8: cold-no-wiki question path").

### Scenario 3 — `wiki capture` headless from a fresh directory

The resolver checks `~/.wiki-pointer`, then cwd state. Five exit codes:

- `0` — success
- `10` — pointer missing/broken (silent-bootstrap fires if `$HOME/wiki/` valid; else interactive prompt OR headless orphan)
- `11` — cwd unconfigured (interactive prompts; headless auto-selects main-only)
- `12` — cwd config requires main but pointer is none/missing (orphan)
- `13` — cwd has BOTH `.wiki-config` AND `.wiki-mode` (conflict, orphan)
- `14` — half-built wiki (orphan)

Orphans land in `${WIKI_ORPHANS_DIR:-$HOME/.wiki-orphans}/<timestamp>-<slug>.md`. Body preserved; manual cleanup later.

### Scenario 4 — Drop a file into `<wiki>/inbox/`

Two firing paths:

- Next SessionStart: hook scans `<wiki>/inbox/` for files older than 5 seconds (rsync/unzip-protection mtime defer) and emits a `capture_kind: raw-direct` capture in `.wiki-pending/` pointing at the absolute file path.
- `wiki ingest-now`: same scan + drain, runs immediately.

The spawned ingester reads the file directly (no wrapper capture body), generates a wiki page, copies the file to `<wiki>/raw/<basename>` with manifest entry, and commits. If the file was accidentally dropped in `<wiki>/raw/` instead, the SessionStart hook recovers it to `<wiki>/inbox/` under the manifest lock.

### Scenario 5 — `wiki use project` in a new directory

Writes `<cwd>/.wiki-config` with `role = "project"`. Initializes `./wiki/` via `wiki-init.sh project ./wiki ~/wiki` if missing. From this point, captures from `<cwd>` (or any subdir) write to `./wiki/.wiki-pending/` instead of `~/wiki/`. The project wiki's ingester evaluates each capture: general-interest content propagates to `~/wiki/.wiki-pending/` with a `propagated_from:` field; project-specific content stays local.

## CLI surface

```
wiki status        # health report
wiki capture       # write a chat-driven capture (agent's canonical entry)
wiki ingest-now    # drift-scan + drain inbox/ on demand
wiki issues        # show recent ingester-reported issues, grouped + severity-ordered
wiki use <mode>    # change per-cwd wiki mode (project|main|both)
wiki init-main     # bootstrap ~/.wiki-pointer (interactive)
wiki doctor        # deep lint + smartest-model re-rate (NOT YET IMPLEMENTED, exits 1)
wiki help          # show usage
```

`wiki status` reports: total pages, pending count, processing count, active locks, last ingest, drift status, git status, pages below 3.5 quality, tag synonyms flagged, `index.md` size, per-category page counts, depth violations, category count vs soft ceiling 8, fork-asymmetry between main and project wikis, recent ingester-reported issues (last 30 days, grouped by type).

## Skill architecture (4 skills)

| Skill | Loaded by | Purpose |
|---|---|---|
| `using-karpathy-wiki` | SessionStart hook (auto, every session) | Loader: iron laws, triggers, resist-table, redirects to others |
| `karpathy-wiki-capture` | Main agent on-demand (when capture trigger fires) | Capture authoring: `wiki capture`, body floors, subagent-report flow |
| `karpathy-wiki-read` | Main agent on-demand (when ANY user question fires per Iron Rule 4) | Read protocol: 6-step ladder, cite contract |
| `karpathy-wiki-ingest` | Spawned `claude -p` ingester only (via spawn prompt) | Page writing: 9-step deep orientation, role guardrail, validator, manifest, commit |

## What's deferred

See [TODO.md](TODO.md). Highlights:

- **0.2.8 candidates**: `wiki orient` CLI shortcut for read-protocol Step A; `allowed-tools` scoping on the four skills; cold-no-wiki question path nudge.
- **`wiki doctor` real implementation**: smartest-model re-rate, orphan repair, tag-synonym consolidation.
- **Stop-hook gate** for turn-closure enforcement (`hooks/stop` is currently a stub).
- **`.ingest.log` → `.ingest.jsonl` migration** (dual-artifact pattern, scheduled for v2.5).
- **Test coverage for non-Claude-Code platforms**: Cursor, Copilot CLI, Codex, OpenCode, Gemini.
