# karpathy-wiki v2.3 : Flexible Categories + Auto-Discovered Schema

**Status:** design notes only; brainstorm-and-plan happens in a fresh session.
**Date drafted:** 2026-04-25
**Source:** in-session conversation that surfaced the architectural debt; this file captures the discussion verbatim enough that a fresh session can brainstorm against it without needing the conversation history.
**Branch when implemented:** `v2-rewrite` (continues; same branch as v2 + v2-hardening + v2.1 + v2.2 lineage)

---

## The problem this design addresses

The wiki is supposed to be a flexible knowledge cache that the user (and any agent) can restructure freely as the knowledge grows. In practice, two architectural decisions made in v2-hardening lock the structure:

1. **Closed type whitelist.** `wiki-validate-page.py` line 39: `VALID_TYPES = {"concept", "entity", "query"}` (plus `idea` for `ideas/`). Any page whose `type:` frontmatter is outside this set fails validation. The whitelist is hard-coded; adding a new category requires editing the validator, shipping a new skill version, and reinstalling.

2. **No directory-tree-as-source-of-truth.** Categories are documented in `schema.md` as prose. The validator checks the type field but does not check the directory the file lives in (the v2.2 audit Finding 02 proposed this cross-check; it was deferred to a future ship). Result: directory and `type:` are two parallel sources of truth that can diverge silently.

Symptoms observed in the live wiki today (2026-04-25):
- 40+ pages in `concepts/`, 3 in `entities/`, 4 in `ideas/`, 0 in `queries/`. The `concepts/` mega-bucket grows because the cheap model defaults to `type: concept` whenever ambiguous.
- Project-specific knowledge (e.g., `karpathy-wiki-v2.2-architectural-cut.md`, `building-agentskills-repo-decision.md`) sits in `concepts/` next to general principles. No structural way to separate "knowledge about a specific ship of toolboxmd's karpathy-wiki" from "the general decoration-vs-mechanism pattern."
- Adding a `projects/toolboxmd/<project>/` subtree (the obvious user need) currently requires both a code edit (validator's `VALID_TYPES`) and prose update (schema.md). Neither is auto-discovered.

The user's framing: "I wanted the wiki to be fully flexible for the agents to be able to add remove directories isn't that supported rn?" The honest answer was: no, not really; the validator's closed enum makes the directory tree foreign-key-constrained without a foreign-key check. v2.3 fixes this.

---

## The user's refinement (load-bearing for the brainstorm)

The user pushed back on two design choices and the final direction reflects their judgment:

1. **Type stays in frontmatter, but it equals the top-level directory.** Not removed entirely (we don't go full path-derived). The frontmatter field is preserved as a derived-and-validated mirror of the path. Validator enforces `type == path.parts[0]`. Quote: "the type: could be the top level category not the path yes? would it actually be benfisial then?"

2. **Arbitrary depth nesting allowed within each category.** A page can live at `projects/toolboxmd/karpathy-wiki/v2.3/foo.md` if that's where the user wants it. The category (top-level dir) is the only constraint; everything below is free-form. Quote: "we also need to allwos for sub folders, nested as deep as the user wants."

3. **Sub-indexes ship in this v2.3** (Q1=A in the conversation). The atom-ization of `index.md` into per-category sub-indexes is part of v2.3, not a separate ship. Reasoning: nested directories need a rendering story; sub-indexes ARE that story; they also solve the existing `index.md > 8 KB` schema-proposal that was filed in v2.2 Phase D step 9.

---

## Designed shape (the v2.3-B "auto-discovered schema" architecture, sharpened with the user's refinements)

### Core principles

- **Top-level directory IS the category.** `concepts/`, `entities/`, `queries/`, `ideas/`, `projects/` (new), and ANY future top-level dir the user creates is a valid category. No code change needed to add one.
- **`type:` frontmatter equals top-level dir name.** Validator enforces this in ONE direction: path determines type, not the reverse. Auto-corrected by the ingester when files move (or by a small `wiki-fix-frontmatter` script).
- **Arbitrary nesting allowed.** `concepts/foo.md` works. `projects/toolboxmd/karpathy-wiki/v2.3/notes.md` also works. The nesting depth is a user choice per category.
- **Wiki-root-relative links via leading `/`.** Cross-links from nested files use `[X](/concepts/decoration-vs-mechanism.md)` rather than `[X](../../../concepts/decoration-vs-mechanism.md)`. Validator extension resolves leading-slash paths from wiki root. Same convention Mintlify and most renderers follow.
- **Sub-indexes per category.** `index.md` becomes a 5-line MOC pointing at `index/concepts.md`, `index/entities.md`, `index/projects.md`, etc. Each sub-index handles its own category's nesting. Solves both the auto-discovery rendering problem AND the existing index-size schema-proposal in one pass.
- **`schema.md` is partially auto-generated.** Hand-written prose lives outside markers; the categories list lives between `<!-- CATEGORIES:START -->` / `<!-- CATEGORIES:END -->` markers. A `wiki-discover.py` script (or a fold into `wiki-manifest.py`) walks the tree, emits the categories block. Same gitpix marker-injection pattern that v2.2 uses for index split proposals.
- **`wiki-status.sh` reads from auto-discovery**, not from a hard-coded list of 4 dirs.

### Why keep `type:` (the user's refinement, with the supporting argument)

`type:` becomes derived but is still stored in frontmatter, NOT removed. Reasons:

1. **Grep-friendly.** `grep -l "^type: projects" wiki/**/*.md` is faster and more robust than path-walking when a tool wants "all project pages." Used by the ingester, the status report, the future `wiki doctor`.
2. **Backward compatibility.** Every existing page already has `type:`. Removing it is a migration; keeping it derived-but-stored is additive.
3. **Quality-rating system depends on it.** SKILL.md line 364: "Every non-meta page (concept, entity, query) carries a quality block in frontmatter." The rating system uses `type:` to know which pages get rated vs which are meta (logs, schema). Removing `type:` means rewiring that.
4. **Cheap consistency check.** "Is this page in the right place?" becomes a one-line validator check (`type == path.parts[0]`). If they ever diverge (a moved file with un-updated frontmatter), the validator catches it.

### Why NOT make `type:` carry the full path

A richer `type: projects/toolboxmd/karpathy-wiki` was considered. Rejected because:
- It collides with the existing directory tree (now two sources of truth for nesting again).
- Quality rating logic, status counts, and ingester orientation all bucket by category; `projects/toolboxmd/karpathy-wiki` is too granular for those purposes.
- Optional `category_path:` field can carry the nested addressing (e.g., `category_path: toolboxmd/karpathy-wiki`) without polluting `type:`.

So: `type:` is the bucket; `category_path:` is the optional refinement; the actual file path is the source of truth for both.

---

## Concrete shape after v2.3 ships

### Directory tree (representative slice)

```
~/wiki/
├── concepts/                              # type: concept
│   ├── decoration-vs-mechanism.md
│   ├── wiki-quality-rating-system.md
│   └── ...
├── entities/                              # type: entity
│   └── ...
├── queries/                               # type: query
├── ideas/                                 # type: idea
├── projects/                              # type: projects (new top-level)
│   ├── toolboxmd/
│   │   ├── karpathy-wiki/
│   │   │   ├── v2.2-architectural-cut.md     # moved from concepts/
│   │   │   ├── v2.3-flexible-categories.md   # new
│   │   │   └── ...
│   │   ├── building-agentskills/
│   │   │   ├── repo-decision.md              # moved from concepts/
│   │   │   ├── v0-build-pipeline-lessons.md  # moved from concepts/multi-stage-opus-pipeline-lessons.md
│   │   │   └── ...
│   │   ├── gitpix/
│   │   └── landing/
│   └── <future-brand>/
│       └── ...
├── index.md                               # 5-line MOC pointing at sub-indexes
├── index/
│   ├── concepts.md                        # auto-generated from concepts/ tree
│   ├── entities.md
│   ├── queries.md
│   ├── ideas.md
│   └── projects.md                        # auto-generated, handles nesting
├── schema.md                              # hand-written prose + auto-gen categories block
├── log.md
├── raw/
└── .wiki-pending/
```

### Frontmatter shape (example: a project page)

```yaml
---
title: "karpathy-wiki v2.2 : kill sources/, decoration-vs-mechanism pattern"
type: projects                              # MUST equal path.parts[0]
category_path: "toolboxmd/karpathy-wiki"   # optional; nested addressing
tags: [karpathy-wiki, skill-authoring, meta-pattern]
sources:
  - raw/2026-04-24T20-06-48Z-karpathy-wiki-v2.2-architectural-cut.md
created: "2026-04-24T20:06:48Z"
updated: "2026-04-25T16:00:00Z"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 5
  overall: 5.00
  rated_at: "2026-04-25T16:00:00Z"
  rated_by: ingester
---
```

### Cross-link convention (the wiki-root-relative pattern)

A page at `projects/toolboxmd/karpathy-wiki/v2.3.md` linking to `concepts/decoration-vs-mechanism.md`:

```markdown
See [decoration vs mechanism](/concepts/decoration-vs-mechanism.md).
```

NOT:

```markdown
See [decoration vs mechanism](../../../concepts/decoration-vs-mechanism.md).
```

The leading `/` is wiki-root-relative. Validator resolves from wiki root. Mintlify and GitHub markdown renderers respect this convention; for raw `cat`-ing the file in a terminal, the `/` is a minor visual oddity but acceptable trade-off. (Alternative considered: convention-only with no leading slash, validator falls back to wiki-root resolution if relative resolution fails. Rejected because it makes the link's intent ambiguous to a human reader.)

### Schema.md (the auto-generated categories block)

```markdown
# Wiki Schema

## Role
main

<!-- CATEGORIES:START (auto-generated by wiki-discover.py; do not edit between markers) -->
- `concepts/` (43 pages) : type: concept
- `entities/` (3 pages) : type: entity
- `queries/` (0 pages) : type: query
- `ideas/` (4 pages) : type: idea
- `projects/` (8 pages, nested 2 levels) : type: projects
<!-- CATEGORIES:END -->

## When to use which category

(hand-written prose explaining when to put a page in each category : survives auto-regen since it's outside markers)

...
```

The `wiki-discover.py` script runs at the end of every ingest (or on demand) and regenerates the categories block. Adding a new directory = creating it = the next ingest picks it up = next regen reflects it.

---

## What v2.3 delivers (tasks at high level; the brainstorm later refines)

This list is the brainstorm's input, not the final task list. Sized roughly: 12-18 commits across 4 phases, similar shape to v2-hardening or v2.2.

### Phase A : Discovery + soft validator

- A1. New script `scripts/wiki-discover.py`. Walks the wiki root; lists top-level directories (excluding `raw/`, `.wiki-pending/`, `.locks/`, `index/`). Emits a JSON object with categories + per-category counts + nesting depth.
- A2. Extend `wiki-validate-page.py`:
  - Drop hard-coded `VALID_TYPES`. Read from `wiki-discover.py` output instead (cache the discovery, refresh on every validate run).
  - Add the directory-vs-type cross-check (the v2.2 audit Finding 02 fix, now finally implemented in this direction): `type:` MUST equal `path.parts[0]`. Validator emits violation if they differ.
  - Update validator docstring to explain the new contract.
- A3. Add `scripts/wiki-fix-frontmatter.py`. One-shot: reads every page, recomputes `type:` from path, updates frontmatter if mismatched. Used by the migration in Phase D and as a maintenance tool.
- A4. Schema.md gets `<!-- CATEGORIES:START --> ... <!-- CATEGORIES:END -->` markers. `wiki-discover.py` writes the categories block on every ingest's step 7.6 (alongside the existing index-size threshold check). Hand-written prose around the markers stays sacred.
- A5. Unit tests for discovery + validator changes + frontmatter fix-script.

### Phase B : Wiki-root-relative links

- B1. Extend `wiki-validate-page.py` link resolver: links starting with `/` resolve from wiki root, not from the page's directory. All other resolution behavior unchanged.
- B2. Unit tests for the new resolver.
- B3. SKILL.md prose update: document the leading-`/` convention as the recommended cross-link style for nested pages. Existing one-level pages can keep their relative links; they're not broken.
- B4. (Optional, deferred to v2.4 if scope creeps) : automated link migration script that rewrites existing `../foo.md` links to `/category/foo.md` form.

### Phase C : Sub-indexes + `index.md` MOC

- C1. New script `scripts/wiki-build-index.py`. Walks each top-level category, writes `index/<category>.md` listing every page in that category with its quality rating and short description. Handles arbitrary nesting (renders as nested bullet lists or as flat lists with category-path prefix; design choice for the brainstorm).
- C2. New `index.md` is a 5-line MOC: H1 + one-line-per-category links to `index/<category>.md`. Replaces the current 87-line index.md.
- C3. Ingester step 7 updated: instead of writing index.md directly, it invokes `wiki-build-index.py` for the affected category's sub-index. Index.md (the MOC) only changes when categories are added or removed (handled via wiki-discover.py output).
- C4. The pending `index-split.md` schema-proposal capture (filed in v2.2 Phase D step 9) is consumed by this phase and archived. The proposal's recommendations are realized.
- C5. SKILL.md updated to describe the new index structure.
- C6. `wiki-status.sh` updated: reads category counts from `wiki-discover.py` output instead of hard-coding the 4 dirs.

### Phase D : Live wiki migration

- D1. Backup tarball: `tar czf ~/wiki-backup-pre-v2.3-<utc-iso>.tar.gz ~/wiki/`.
- D2. Migration script `scripts/wiki-migrate-v2.3.sh` (single script, named functions, `--dry-run` flag; same pattern as `wiki-migrate-v2.2.sh`):
  - Create `projects/toolboxmd/<project>/` directories.
  - Move project-specific pages from `concepts/` to `projects/toolboxmd/<project>/`. The 3-4 pages today: `karpathy-wiki-v2.2-architectural-cut.md`, `building-agentskills-repo-decision.md`, `multi-stage-opus-pipeline-lessons.md` (the one ingesting now). Maybe also `wiki-obsidian-integration.md` and the `wiki-*` series if they qualify; judgment call per page.
  - Run `wiki-fix-frontmatter.py` on every moved page so `type:` reflects the new path.
  - Update inbound links to moved pages (a `wiki-relink.py` script, or sed if simple enough).
  - Run `wiki-build-index.py` to regenerate sub-indexes.
- D3. Verify: `wiki-validate-page.py --wiki-root ~/wiki` passes on every page; `wiki-manifest.py validate` passes; `wiki-status.sh` reflects the new category set.
- D4. Commit in the wiki repo with the v2.3 migration message.

### Phase E : TODO updates + post-flight

- E1. Update karpathy-wiki repo TODO.md: mark v2.3-related items shipped, add v2.4 deferrals (e.g., automated link migration if not done in B4).
- E2. Optional: write a karpathy-wiki v2.3 ship case study (analog to the v2.2 architectural-cut page) for the building-agentskills repo's case-studies dir.

---

## Out of scope (deliberately deferred)

- **Cross-wiki schema discovery.** If a user has multiple wikis (main + project wikis), each wiki discovers its own categories; no cross-wiki sync. Project-wiki propagation logic in v2 is unchanged.
- **Symlink categories.** Symlinks under wiki root are NOT supported as categories (avoids cycles, ambiguous resolution).
- **Per-category schema enforcement** (e.g., "ideas/ pages MUST have status + priority"). The current `ideas/` extension stays; v2.3 does not add per-category schemas for other categories.
- **Automated link migration to leading-`/` form.** Existing `../foo.md` links keep working; the new convention is recommended but not enforced retroactively. v2.4 if needed.
- **Tag-driven categories.** Categories stay directory-based; tags stay independent. Some other tools (Obsidian, Logseq) conflate the two; we don't.
- **`wiki doctor` integration with v2.3.** Doctor remains the v1 stub. v2.3 ships the structural changes; doctor's smart-model re-rate is still post-MVP.

---

## Risks and mitigations

| Risk | Mitigation |
|---|---|
| Auto-discovery picks up a directory that's not meant to be a category (e.g., `tmp/`, an editor-created folder) | Exclude list in `wiki-discover.py`: `raw/`, `.wiki-pending/`, `.locks/`, `index/`, `.git/`, anything starting with `.`. Document the exclude list in schema.md. |
| Existing pages have `type:` that mismatches the new path-derived rule (e.g., a page literally typed `type: foo` while sitting in `concepts/`) | `wiki-fix-frontmatter.py` runs as part of Phase D migration; auto-corrects all existing pages. Validator then enforces going forward. |
| Wiki-root-relative links break when the wiki is mounted at a non-root URL (Mintlify deployments) | Validator uses filesystem path (always works). Renderers vary: Mintlify resolves leading-`/` from site root; GitHub markdown rendering does too. Confirm with a smoke test in the `building-agentskills` Mintlify deployment before B1. |
| Sub-indexes go stale if `wiki-build-index.py` is not invoked on a category change | Make ingester step 7 invoke `wiki-build-index.py` automatically; never write index.md or sub-indexes by hand from v2.3 forward. |
| Migration of `concepts/` to `projects/` breaks inbound links | Phase D includes the `wiki-relink.py` step; verified post-migration with the validator's link-resolver. Backup tarball is the rollback. |
| Quality-rating logic that uses `type:` breaks when `type:` is now derived | Type is still stored in frontmatter (the user's refinement preserves this); rating logic doesn't notice the change. |
| User wants a category that conflicts with a non-category top-level dir (e.g., wants to call it `raw/`) | Reserved names list in schema.md and discovery: `raw`, `index`, anything starting with `.`. Validator rejects pages whose `type:` is a reserved name. |

---

## Success criteria (the brainstorm's "done" definition)

- Validator no longer hard-codes any category list.
- Adding a new top-level directory (e.g., `mkdir ~/wiki/journal/`) is picked up on the next ingest with no code edits.
- Project-specific pages live under `projects/toolboxmd/<project>/` and link cleanly to general concept pages via `/concepts/...` form.
- `index.md` is a 5-line MOC; per-category sub-indexes hold the actual entries; the v2.2 index-size schema-proposal is consumed and archived.
- All Tier-1 lint passes; manifest validate passes; live `~/wiki/` validates clean.
- A future user (or agent) reading `schema.md` understands the auto-discovery contract from the prose alone.

---

## Open questions for the brainstorm to resolve

These are real design choices the brainstorm should pin before the plan is written. Listed in priority order.

1. **Sub-index nesting render.** Flat list with category-path prefix (`- [v2.3](toolboxmd/karpathy-wiki/v2.3.md)`) vs nested bullets (a tree structure)? Trade-off: flat is grep-friendly, tree is human-readable. My initial lean: flat with prefix, but let the brainstorm's worked-example test which reads better.

2. **`category_path:` frontmatter : required or optional?** If required, every page in nested categories must declare its position. If optional, only pages that want richer addressing carry it. My initial lean: optional (path is canonical anyway; `category_path:` is a query-helper).

3. **What goes in `projects/`?** A clear "when to use projects/ vs concepts/" rule needs to land in schema.md. Initial cut: "projects/ holds knowledge specific to one project's ship/decision/timeline; concepts/ holds general principles applicable across projects." Test against existing pages to see if the line holds.

4. **Migration aggressiveness.** Move only the obviously-project-specific pages (3-4 today) or sweep more aggressively (e.g., the wiki-* series, which is partially about karpathy-wiki the project AND partially about wiki-mechanics-as-concept)? Conservative move: only the obvious 3-4; let the rest accrete in `concepts/` until they earn the move.

5. **Should v2.3 pre-populate `projects/` for the user's other brands?** User mentioned having 2 brands. Currently we only see toolboxmd. Default: just create `projects/toolboxmd/`; the user (or future agent) creates `projects/<other-brand>/` when first content lands.

6. **Index-size threshold for sub-indexes.** With per-category sub-indexes, does the 8 KB threshold from v2.2 still apply? Probably yes per sub-index (each can grow independently). Schema-proposals fire per sub-index.

7. **CLI ergonomics.** Should there be a `wiki create-category <name>` command (or auto on first capture)? Probably not in v2.3 : `mkdir` is the contract. But document the pattern.

---

## How to use this file

1. **Open a fresh Claude session in `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/`.** Tell Claude: "Brainstorm a plan from this design doc: `docs/planning/2026-04-25-karpathy-wiki-v2.3-flexible-categories-design.md`. Use the superpowers:brainstorming skill, then writing-plans. Save the spec to `docs/planning/2026-04-25-karpathy-wiki-v2.3-spec.md` and the plan to `docs/planning/2026-04-25-karpathy-wiki-v2.3-plan.md`."
2. The brainstorm should chase the seven open questions above to resolution before the spec is written.
3. The plan, once written, follows the same shape as v2-hardening / v2.1 / v2.2 plans (file-blocks, content briefs, verbatim git commands per task, verification gates per phase, discipline section).
4. Execute via subagent-driven-development (matches the karpathy-wiki ship cadence) or via a single Opus orchestrator if scope stays under 15 tasks (executing-plans skill, solo execution). Either works; subagent-driven is the safer bet given the test surface here is non-trivial.

End of design notes.
