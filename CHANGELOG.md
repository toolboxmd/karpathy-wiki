# Changelog

All notable shipped changes for karpathy-wiki.

This file records shipped behavior, architecture, API contracts, operational
changes, migrations, and meaningful bug fixes. Active follow-ups live in
`TODO.md` or `ISSUES.md`; speculative future options live in `IDEAS.md`.

## Unreleased - 2026-08-21

- Hardened the semantic-ingest benchmark after audit feedback. The first ten
  fixtures are now documented as a development set, source text no longer tells
  the model which category to choose, and the scorer has negative-control
  self-tests plus deterministic gates for validation, manifest/source
  traceability, indexes, idea metadata, and category control.
- Updated the detached ingester instructions to inventory knowledge objects
  before choosing pages, avoid overproducing entity/concept pages from lookup
  sources, and cite the current raw source on every touched page including
  see-also-only updates. The hardened development benchmark moved from `8/10`
  before the instruction patch to `10/10` after it on Grok 4.6 Medium.
- Added snapshot rescoring for the semantic-ingest benchmark and tightened its
  heuristic scorer after manual review of Grok 4.6 Medium output. The scorer now
  prefers title/path matches in the expected category, ignores negated forbidden
  claims, strips frontmatter from claim checks, preserves numeric/code tokens,
  and avoids provider reruns when only scoring logic changes.

## 0.3.2 - 2026-08-21

- Added fail-closed native ACP image transport for Grok. File-backed JPEG and
  PNG evidence is detected from signatures and sent in the same request as the
  normal ingester text. Additional capture attachments are explicit,
  canonicalized under the primary evidence directory, and delivered in stable
  capture order. Missing, unreadable, unsupported, escaped, or oversized
  declared images fail before provider launch, with no path-only or `read_file`
  visual fallback. Normal invocation metadata stores hashes and MIME details,
  never image bytes or base64.
- Changed the built-in recommendation for new Grok configurations to Grok 4.6
  Medium while retaining `grok_medium` and explicit Grok 4.5 pins. Existing
  user runtime files remain untouched unless `wiki config update-runtime` is
  invoked for a named profile.
- Preserved the dated Grok 4.5 text-ingest recommendation and added the later
  multimodal qualification as a separate benchmark decision, including the
  untested Grok 4.5 native-image limitation.
- Adopted the project ledger structure: `CHANGELOG.md`, `TODO.md`, `ISSUES.md`,
  and `IDEAS.md` now have separate jobs.
- Made `AGENTS.md` the canonical project instruction file and kept `CLAUDE.md`
  as a compatibility symlink.
- Added the global project-ledger convention to the local agent instructions.

## Historical shipped backlog migrated from TODO.md

The entries below were moved from the old combined `TODO.md` shipped section on
2026-08-21.

### 0.2.7: read-from-wiki protocol restored (post-v2.4 regression fix)

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
### Re-run the Opus auditor after real-session usage accumulates

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
### `ideas/` category in the wiki schema

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
### v2.3: flexible auto-discovered categories + recursive _index.md tree

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
### Project-wiki auto-resolution at capture time (architectural — surfaced 2026-04-27 post-v2.3 ship)

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
  - skills/karpathy-wiki/SKILL.md (lines 74-91: "When no wiki exists" auto-init algorithm — file deleted in v0.2.7; now executable via wiki-resolve.sh)
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
### Raw-direct ingest path (architectural — surfaced 2026-04-27 post-v2.3 ship)

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
  - skills/karpathy-wiki/SKILL.md (line 121: "user adds a file to raw/" trigger — file deleted in v0.2.7; trigger now in skills/using-karpathy-wiki/SKILL.md)
  - skills/karpathy-wiki/SKILL.md (line 502: Iron Rule 5 "Never modify files in raw/" — file deleted in v0.2.7)
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
### SessionStart hook injects SKILL.md content (using-superpowers pattern)

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
  - skills/karpathy-wiki/SKILL.md (legacy, deleted in v0.2.7 after split)
  - ~/wiki/concepts/claude-code-skill-autoload-mechanisms.md (revisit criteria + implementation sketch)
```

**SHIPPED in v2.4 Leg 1 (2026-05-06).** The session-start hook reads `skills/using-karpathy-wiki/SKILL.md` and emits its body wrapped in `<EXTREMELY_IMPORTANT>` tags as `hookSpecificOutput.additionalContext`, so the agent reads the wiki rules in every conversation regardless of whether it chooses to invoke. The legacy `skills/karpathy-wiki/SKILL.md` was split into three focused skills (`using-karpathy-wiki` loader, `karpathy-wiki-capture` for the main agent, `karpathy-wiki-ingest` for the spawned ingester) so subagents and ingesters get only the surface they need. Subagent fork-bomb guard already in place from 0.2.4 prevents the loader from re-firing inside dispatched subagents.

## [0.3.8] - 2026-08-22

### Changed

- Archive the v2.2 migration and retire resolved ledger entries

## [0.3.7] - 2026-08-22

### Changed

- Fix semantic ingest claim polarity matcher

## [0.3.6] - 2026-08-22

### Changed

- Fix semantic ingest benchmark audit blockers

## [0.3.5] - 2026-08-22

### Changed

- Harden semantic ingest benchmark after independent audits

## [0.3.4] - 2026-08-22

### Added

- Adopt repository SemVer before benchmark hardening
