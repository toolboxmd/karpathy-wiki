---
name: karpathy-wiki-ingest
description: |
  For a detached wiki ingester only. The main agent never loads this. Defines orientation protocol, page format, role guardrail, validator contract, manifest protocol, and deterministic completion contract. Loaded by the provider-aware runtime worker.
---

# karpathy-wiki ingest (for detached runtime ingester only)

You are a detached wiki ingester invoked by the provider-aware runtime
worker. Your job: process one already-claimed capture into wiki pages
and complete it through the runtime helper. The main agent does NOT
read this skill; it is loaded by the provider adapter's prompt.

Perform this ingest yourself. You must not launch or delegate the work
to another model or agentic CLI. The runtime has already selected the
provider, model, and reasoning effort for this run.

## Deep orientation

Before any wiki write, run this 9-step orientation protocol. The goal:
your view of the wiki is shaped by the actual page content, not by
titles alone.

### Steps 1-3: read the wiki's current state

1. Read `<wiki>/schema.md` — current categories, taxonomy, thresholds.
2. Read `<wiki>/index.md` (or `<wiki>/<category>/_index.md` per category) — what pages exist with one-line summaries.
3. Read the last ~10 entries of `<wiki>/log.md` — recent activity.

### Steps 4-7: pick and read 0-7 candidate pages

4. **Extract candidate signals from the capture.** From the body and
   frontmatter, gather:
   - Words and phrases from the capture title (lowercase, split on
     non-alphanumerics).
   - Frontmatter `tags:` list (if any).
   - For `chat-only` and `chat-attached` captures: meaningful nouns and
     proper-noun phrases from the body. Use judgment — you're an LLM,
     not a regex; pick names, identifiers, technical terms, version
     numbers.
   - For `raw-direct` captures: filename basename + the file's first
     200 lines.

5. **Score candidates against the index.** A page is a candidate if ANY
   extracted signal:
   - Substring-matches its title (case-insensitive), OR
   - Matches a tag (exact, case-insensitive), OR
   - Appears in its `_index.md` one-line summary.

   This is a deterministic substring + tag match — no embeddings, no
   semantic similarity. See "Why no embeddings / vector search" below
   for the rationale.

6. **Pick up to 7 candidates** ordered by:
   - Signal-match count (descending — more matches = stronger candidate).
   - Title length (ascending — shorter titles rank higher for the same
     match count; they tend to be more general / canonical).
   - Tie-break: alphabetical by title.

7. **Read all picked candidates in full.** Zero is a valid count for a
   small or fresh wiki — see "Cold start" below.

### Steps 8-9: decide and report observations

8. **Decide**: create new page, augment an existing page, or no-op
   (the capture's content is already covered by an existing page).
   Write your decision rationale into the commit message later.

9. **Issue reporting (during steps 5-7).** While reading the index and
   the candidate pages, observe issues. Append each as one JSONL line
   to `<wiki>/.ingest-issues.jsonl` via
   `bash "${WIKI_PLUGIN_ROOT}/scripts/wiki-issue-log.sh"`.
   Do NOT fix issues inline; report only — `wiki doctor` consumes the
   log later.

   Example invocation:

   ```bash
   bash "${WIKI_PLUGIN_ROOT}/scripts/wiki-issue-log.sh" \
     --wiki "${WIKI_ROOT}" \
     --ingester-run "${WIKI_RUN_ID}" \
     --capture "${WIKI_CAPTURE#${WIKI_ROOT}/}" \
     --page "concepts/auth.md" \
     --type broken-cross-link \
     --severity warn \
     --detail "Links to /concepts/legacy.md which does not exist." \
     --suggested-action "Remove link or create stub"
   ```

   Issue types to watch for (the `--type` enum in `wiki-issue-log.sh`):
   - **broken-cross-link**: page links to `/path/foo.md` but that file
     does not exist.
   - **contradiction**: page makes a claim that contradicts another
     page you're reading or the capture itself.
   - **schema-drift**: page has `type: concept` (singular) but
     directory is `concepts/`; page lacks required frontmatter; page
     uses retired categories.
   - **stale-claim**: page says "as of 2025-12 library X is at version
     Y" and the capture or another source clearly indicates a newer
     version.
   - **tag-drift**: same concept tagged two different ways across
     pages.
   - **quality-concern**: page's `quality.overall < 3.0` was rated by
     ingester (not human).
   - **orphan**: page exists but is not linked from any `_index.md` or
     other page.
   - **other**: anything else worth noting.

   Severity:
   - **error**: blocks ingestion (rare — only if reading the schema or
     a candidate page fails outright).
   - **warn**: default. Issue noted; ingestion proceeds.
   - **info**: observational; usually for tag-drift or quality-concern.

   Each issue gets one JSONL line, ≤ 4096 bytes total. Over-length
   `--detail` is auto-truncated by the helper.

### Cold start: wikis with ≤ 7 pages

When the candidate list from step 6 is empty or near-empty (the index
has fewer than 8 pages total), step 7 reads few or no pages. The role
guardrail in `<wiki>/.wiki-config` becomes the PRIMARY lens, not a
backup tripwire:

- **`role: project` or `role: project-pointer`**: write specifics
  about THIS codebase / instance / situation. Document the symptom,
  the pinpoint, what code path triggered it. Do NOT generalize.
- **`role: main`**: write general patterns reusable across projects.
  Do NOT name specific apps or instances; abstract them.

In the cold-start state the index has insufficient gravity to shape
the page; the role hint carries the lens. Defer cross-linking to a
future ingester run when more pages exist.

### Why no embeddings / vector search

The substring + tag match in step 5 is deterministic, scriptable,
testable, and cheap. Embedding-based candidate selection is the
"smart" upgrade but explicitly out of scope per CLAUDE.md ("do not
add: vector search — defer until genuine scaling pain"). The
substring/tag approach degrades gracefully — at large scale it hits
more candidates than 7, but the ranking still produces a usable
top-7. When that breaks, vector search becomes worth its complexity;
not before.

### Cost

3-7 extra file reads per ingestion (zero on cold-start wikis). Each
page is typically 5-20 KB. The ingester is already reading the
capture and the schema; this is the same order of magnitude. No
measurable spawn-time impact.

## Run record (per ingestion)

`WIKI_RUN_ID` is assigned before you start. Do not generate or replace
it. The runtime wrapper owns the `started`, retry, failure, and
`completed` records in `<wiki>/.ingest-runs.jsonl`; it also owns the
heartbeat on `WIKI_CAPTURE` and the process-slot lease. Do not write
run-history records yourself.

Use `WIKI_RUN_ID` only when another deterministic helper needs to tie
an observation to the current run, such as `wiki-issue-log.sh`. A
successful ingest is closed by the completion helper described in
step 10. The wrapper writes `completed` only after it verifies both the
archive and the provider's zero exit.

## Role guardrail

Read `<wiki>/.wiki-config` to determine the wiki's role:

- `role: project` or `role: project-pointer` → you are writing for a
  PROJECT wiki. Document specifics: how this app handles X, where
  bug Y lived, what we decided for this codebase. Do NOT generalize.
- `role: main` → you are writing for the MAIN wiki. Extract general
  patterns reusable across projects. Do NOT name specific apps or
  instances.

The role field is the primary lens during cold start (≤ 7 pages in
the wiki) and a sanity tripwire in mature wikis (the index pull is
the primary lens once enough pages exist). See "Deep orientation —
Cold start" above.

If the index pulls strongly toward instance-style or pattern-style
writing (you read 5+ existing pages of one shape), trust the pull.
The role hint then becomes a tripwire — *"if you find yourself
generalizing in a project wiki / specifying in a main wiki, stop."*

## Capture format

See `<plugin>/skills/karpathy-wiki-capture/references/capture-schema.md`
for the canonical capture frontmatter contract — `capture_kind` enum,
body floors, evidence rules, legacy backward-compat. Do not duplicate
that schema here.

## Page format

See `references/page-conventions.md` for the canonical page
frontmatter and cross-link conventions.

All generated page metadata timestamps (`created`, `updated`, `rated_at`) must
be real UTC values. In shell, generate them with
`date -u +%Y-%m-%dT%H:%M:%SZ`. Never append `Z` to local wall-clock output.

## Body-sufficiency check (first thing — reject if too thin)

Before any other work, measure the capture body size in bytes (content
AFTER the closing `---` of frontmatter). Apply the per-`capture_kind`
floor:

- `raw-direct` → no floor (body is auto-generated boilerplate).
- `chat-attached` → 1000 bytes.
- `chat-only` → 1500 bytes.

Legacy captures (no `capture_kind`): apply backward-compat per
`<plugin>/skills/karpathy-wiki-capture/references/capture-schema.md`.

If body is BELOW its floor:

1. Add `needs_more_detail: true` to the capture's frontmatter.
2. Add `needs_more_detail_reason: "body is <N> bytes; floor for capture_kind=<K> is <F> bytes"`.
3. Rename `.md.processing` → `.md` so the next session-start drain
   preserves it for the main agent to expand. The dispatcher skips marked
   captures until the main agent removes both deferral fields.
4. Append to `log.md`: `## [<timestamp>] reject | <capture-basename> — body <N>b below <F>b floor`.
5. Exit 0. Do NOT write pages. Do NOT commit.

A thin-capture rejection is a feature, not a failure.

## Ingester steps

1. **The capture is already claimed for you.** Read `${WIKI_CAPTURE}` (it's a `.md.processing` file). If for some reason `${WIKI_CAPTURE}` is unset or missing, call `wiki_capture_claim "${WIKI_ROOT}"` to grab any pending capture as fallback.

2. **Read the orientation files**: schema.md, index.md, last 10 entries of log.md (per the Orientation section above).

3. **Read the capture body.**

4. **Copy evidence with write-staging discipline (v2.4):**

   Atomic write to `raw/` requires the staging dance (skip steps 1–2 and 7
   if `evidence_type` is `conversation` AND the capture has no real path):

   1. Copy the evidence file to `<wiki>/.raw-staging/<basename>` (NOT directly to `raw/`).
   2. Compute the new sha256.
   3. Acquire `<wiki>/.locks/manifest.lock` via
      `bash "${WIKI_PLUGIN_ROOT}/scripts/wiki-manifest-lock.sh" ...` for the
      manifest write + rename block.
   4. Re-read the manifest under the lock. If `raw/<basename>` already exists with the same sha256, this is a duplicate — skip (apply the sha256 short-circuit below).
   5. Update the manifest entry for `raw/<basename>` (origin, sha, copied_at, last_ingested, referenced_by).
   6. Write the manifest atomically (`.manifest.json.tmp` + `os.rename`) — `wiki-manifest.py build` already does this.
   7. Atomically rename `<wiki>/.raw-staging/<basename>` → `<wiki>/raw/<basename>` (POSIX rename is atomic on the same filesystem).
   8. Release the lock.
   9. If the source file is in `<wiki>/inbox/<basename>` (raw-direct via inbox queue), `rm` it.

   Crash recovery: if the ingester crashes between steps 1 and 7, a file
   lingers in `.raw-staging/`. The SessionStart recovery scan SKIPS
   `.raw-staging/` (it's a reserved dot-prefixed directory). Future cleanup
   is `wiki doctor`'s responsibility.

   - In ALL cases (including `chat-only` / legacy `conversation`): write or update the manifest entry for the raw file in `<wiki>/.manifest.json`:
     ```json
     {
       "raw/<basename>": {
         "sha256": "<sha256 of raw file>",
         "origin": "<exact value of capture's `evidence` field>",
         "copied_at": "<iso-8601 utc, preserve if already present>",
         "last_ingested": "<iso-8601 utc, now>",
         "referenced_by": ["<pages added to this list below>"]
       }
     }
     ```
   - Always call `python3 "${WIKI_PLUGIN_ROOT}/scripts/wiki-manifest.py" build "${WIKI_ROOT}"` at the end of ingest to refresh sha256 and `last_ingested`. This is mandatory; the manifest is the drift-detection source of truth.
   - **Iron rule:** `origin` is the capture's `evidence` field value — never the string `"file"`, `"conversation"` (when a real path was available), `"mixed"`, or the `evidence_type`/`capture_kind`. If `capture_kind == "chat-only"` AND the capture has no real path, `origin` is the literal string `"conversation"`. Any other value is a validator failure.
   - **sha256 short-circuit.** If `raw/<basename>` already exists AND `sha256(new) == manifest[raw/<basename>].sha256`, the evidence content is identical — skip content re-ingest of this capture and append `## [<timestamp>] skip | <capture-basename> — sha match, no-op` to `log.md`. You MUST still perform step 9 when `promotion_policy: "selective"`; a duplicate content result does not satisfy a missing promotion decision. Archive the capture normally only after step 9. This prevents re-ingesting the same research file twice without skipping required routing state.
   - **Title-scope check.** Before merging into an existing wiki page in step 6, compare the new evidence's scope to the existing page's slug. Scope is the set of distinct entities (product names, versions, model names, concepts) the evidence covers. If the existing page's slug is NARROWER than the new evidence's scope (example: existing `concepts/gemma4-27b-hardware-requirements.md` vs new evidence covering a 27B+31B comparison), do NOT force-merge the broader content into the narrower-titled page. Instead, either (a) create a sibling concept page with a scope-appropriate slug (e.g. `concepts/gemma4-27b-vs-31b-hardware-comparison.md`) and cross-link both, or (b) rename the existing page's slug AND frontmatter title to cover the new scope, then merge — only if no other wiki page currently links to the old slug (if any do, use option (a) to avoid broken links). Log which option was taken in `log.md`.
   - **Overwrite-detection recovery.** If `raw/<basename>` already exists AND the new sha256 differs from the manifest entry AND the manifest's `last_ingested` is within the last 60 minutes (the evidence file on disk was replaced since the previous ingest), treat this as an overwrite situation: copy the new evidence to `raw/<basename>` AS NORMAL, but also append `## [<timestamp>] overwrite | <capture-basename> — raw sha changed since <previous_ingested_iso>, previous referenced_by: [<list>]` to `log.md`. Proceed with the rest of step 4 and the title-scope check in step 6 as above. The overwrite is not an error — it is the exact scenario from the failure-mode transcript (two research agents both wrote to `2026-04-24-gemma4-hardware.md`), and the title-scope check catches the content-divergence part.

5. **Decide target pages by extracting knowledge objects first.**
   `suggested_pages` is a hint; orientation may change it.

   Canonical wiki pages are knowledge objects, not source summaries. A
   capture can produce zero, one, or several durable objects. Before choosing
   paths, make an internal inventory of candidate objects:

   - named durable things such as tools, services, APIs, people, repos, and
     components usually belong in `entities/`;
   - reusable mechanisms, patterns, principles, and comparisons usually belong
     in `concepts/`;
   - durable lookup answers, audits, readiness checks, comparisons, and
     operational Q&A usually belong in `queries/`;
   - proposed future work and experiments usually belong in `ideas/` and need
     `status` plus `priority`;
   - bounded workstreams with scope, window, deliverables, gates, or rollback
     usually belong in `projects/` when that category exists;
   - thin, rumor-only, non-repro, empty, or low-evidence material should stay
     raw/held or become a no-page log entry.

   Avoid both under-splitting and overproduction. A lookup/procedure source
   should usually create one query page, with supporting terms kept inline or
   linked to existing pages. Create a sibling entity or concept only when the
   source contains enough durable, independently useful claims for that object.
   A named product, flag, status, error class, or internal term mentioned only
   to answer the lookup is not by itself enough to create a product
   encyclopedia or concept essay.

   Do not use `concepts/` as the safe fallback. If the source is about a named
   durable tool or service, prefer `entities/`; if it is a future proposal,
   prefer `ideas/`; if it is a reusable answer, prefer `queries/`; if evidence
   is too thin, hold it.

6. **For each target page**:
   a. Acquire a page lock (`wiki_lock_wait_and_acquire`).
   b. Read current page content (read-before-write).
   c. Merge new material. Do NOT replace existing claims — add dated findings, use `contradictions:` frontmatter if they disagree.
   d. Ensure every page you changed, including an existing page that only got
      a see-also link or timestamp update, includes the current raw evidence
      path in `sources:` and is included in the raw manifest entry's
      `referenced_by` list. The completion helper validates the manifest, so
      do not treat cross-link-only updates as source-free.
   e. Release lock (`wiki_lock_release`).

6.5. **Self-rate every page you just touched.** Use your own judgment as the current ingester; do not launch another model. For each page, score four dimensions (1-5 each), compute `overall` as `round(mean, 2)`, and write the following into the page's frontmatter (creating the `quality:` block if missing, preserving `rated_by: human` if the page already has it):
   ```yaml
   quality:
     accuracy: <1-5>
     completeness: <1-5>
     signal: <1-5>
     interlinking: <1-5>
     overall: <float>
     rated_at: "<ISO-8601 UTC now>"
     rated_by: ingester
   ```
   Rating criteria in one line each:
   - accuracy: does every claim map to evidence in `sources:`?
   - completeness: would a future-you searching for this topic find enough to act?
   - signal: dense knowledge vs restatement?
   - interlinking: does it link to every related page the wiki contains?

   **Never clobber `rated_by: human`.** If the existing page has `quality.rated_by == "human"`, skip this step for that page entirely. See `references/page-conventions.md` for the full quality block contract.

7. **Update indexes via `wiki-build-index.py`.** Do NOT write `index.md` or any `_index.md` directly. Instead, for each unique parent directory of a touched page (deduplicated from `touched_pages`), invoke:

   ```bash
   for dir in "${TOUCHED_DIRS[@]}"; do
     python3 "${WIKI_PLUGIN_ROOT}/scripts/wiki-build-index.py" \
       --wiki-root "${WIKI_ROOT}" "${dir}"
   done
   ```

   The script regenerates `_index.md` in that directory and walks UP to ancestors (path-order locks, leaves first). Root MOC (`index.md`) is rebuilt automatically by the script if a top-level category was added or removed.

   If the script exits non-zero (lock timeout, discovery failure), log the failure to `log.md` and continue. The next ingest catches up because indexes are a function of directory state.

7.5. **Missed-cross-link check.** Using your own judgment as the current ingester, compare the freshly edited page with the relevant `_index.md` (the page's parent directory's index, NOT root `index.md`). Identify existing pages it obviously should link to but currently does not. Do not delegate this check to another model. For every clear match, insert a markdown link at a relevant point in the page (or append to a `## See also` section, creating it if absent), re-acquire the page lock, save, release, and re-validate. Do not propose new pages in this step.

7.6. **Per-`_index.md` size threshold check.** After step 7's invocation, check the size of every `_index.md` the script touched:

   ```bash
   for idx in "${TOUCHED_INDEXES[@]}"; do
     size="$(wc -c < "${idx}" | tr -d ' ')"
     if [[ "${size}" -gt 8192 ]]; then
       slug="$(echo "${idx#${WIKI_ROOT}/}" | tr '/' '-' | tr '.' '-')"
       proposal_pattern="${WIKI_ROOT}/.wiki-pending/schema-proposals/*-${slug}-index-split.md"
       if ! find ${proposal_pattern} -mtime -1 2>/dev/null | grep -q .; then
         ts="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
         cat > "${WIKI_ROOT}/.wiki-pending/schema-proposals/${ts}-${slug}-index-split.md" <<EOF
---
title: "Schema proposal: split ${idx#${WIKI_ROOT}/} (size threshold exceeded)"
captured_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
trigger: "${idx#${WIKI_ROOT}/} size = ${size} bytes (threshold 8192 bytes)"
---

The sub-index file ${idx#${WIKI_ROOT}/} exceeded the 8 KB orientation-degradation threshold. Recommended: split this directory into sub-categories, OR consolidate scope. Root MOC is exempt from this threshold (capped via Rule 3 instead — see Category discipline).
EOF
       fi
     fi
   done
   ```

   The root `index.md` (small MOC built by `_build_root_moc`) is exempt from this 8 KB threshold. The MOC is bounded by Rule 3 (≥8 categories soft ceiling) instead — see Category discipline section.

8. **Append to `log.md`**.

9. **Honor the capture's promotion policy.** Read `promotion_policy` from the
   claimed capture. Missing legacy fields mean `none`.

   - `none`: do not perform cross-wiki publication. This covers main captures,
     project-only captures, and legacy captures.
   - `selective`: make exactly one semantic decision after the local project
     result is complete. The deterministic completion helper rejects a
     selective capture until this decision is persisted.

   For a selective capture:

   - **Keep local** when the knowledge uses project-specific names, repository
     paths, local architecture, or only applies here. Persist the decision with:

     ```bash
     python3 "${WIKI_PLUGIN_ROOT}/scripts/wiki-promote-capture.py" keep-local
     ```

   - **Promote** when the result describes a reusable tool, concept, pattern,
     or principle that is useful across projects. Write a self-contained,
     generalized body of at least 1500 bytes to a temporary file under
     `${WIKI_ROOT}/.locks/`. Remove repository-only names and paths while
     preserving the durable claims, rationale, caveats, and evidence context.
     Then publish only through:

     ```bash
     python3 "${WIKI_PLUGIN_ROOT}/scripts/wiki-promote-capture.py" publish \
       --title "<generalized one-line title>" \
       --body-file "<absolute temporary body path>"
     ```

   - **When ambiguous, promote** a sufficiently detailed generalized account.
     Missing reusable knowledge is costlier than a main-wiki result that the
     main ingester later consolidates.

   Never write directly into another wiki's `.wiki-pending/`. The helper
   revalidates the authoritative workspace mode and exact pinned main target,
   validates the project role, owns portable provenance,
   atomically publishes one derived capture, and treats retry or concurrency
   as an idempotent success. If it exits non-zero, stop and exit non-zero so
   the dispatcher can retry the original project capture.

   Main-wiki ingestion of a derived capture is otherwise identical to direct
   main-wiki ingestion. Its `promotion_policy` is `none`, so promotion cannot
   recurse.

10. **Complete through the deterministic runtime helper:**

    ```bash
    bash "${WIKI_PLUGIN_ROOT}/scripts/wiki-complete-ingest.sh"
    ```

    `WIKI_ROOT`, `WIKI_CAPTURE`, and `WIKI_RUN_ID` are already set. The
    helper validates the promotion decision and manifest, archives the `.processing` capture,
    and applies the configured commit policy. If it exits non-zero,
    stop and exit non-zero; the wrapper owns retry classification.

11. **Exit zero only after the completion helper succeeds.**

## Tier-1 lint at ingest (inline)

Before exiting, run the validator on every page you just touched:

```bash
for page in "${touched_pages[@]}"; do
  python3 "${WIKI_PLUGIN_ROOT}/scripts/wiki-validate-page.py" \
    --wiki-root "${WIKI_ROOT}" "${page}"
done
```

The validator checks:
- Every markdown link in the page resolves to an existing file.
- Required frontmatter fields (`title`, `type`, `tags`, `sources`, `created`, `updated`) present.
- `type` matches the discovered top-level category and the page's first path
  component (plural form such as `concepts`, `entities`, or `queries`).
- Dates are full ISO-8601 UTC (`2026-04-24T13:00:00Z`, not `2026-04-24`).
- `sources:` is a flat list of strings (no nested mappings).
- Every `quality.*` field is present and in range.

If the validator exits non-zero for any page, fix the mechanical issue and re-validate. The commit script enforces this in code (0.2.8 #3): `wiki-commit.sh` runs `wiki-validate-page.py` on every staged content page and refuses to commit if any page fails. If the commit step refuses, fix the failing page and re-attempt the commit — do not bypass by skipping `wiki-commit.sh`.

If a contradiction surfaces, add `contradictions:` frontmatter pointing to the conflicting page — do NOT resolve it during ingest. (Contradictions are a judgement call, not a validator violation.)

Additionally: after running the validator, also run `wiki-lint-tags.py` if it exists in the plugin. If it reports proposed new tags, drop a schema-proposal capture in `.wiki-pending/schema-proposals/` and continue — do NOT rename tags inline.

## Numeric thresholds (from schema.md)

- **Split a concept page** when it has material from 2+ sources OR exceeds 200 lines.
- **Archive a raw source** when it's referenced by 5+ wiki pages (move to `raw/archive/`, update references).
- **Restructure a top-level category** when it contains 500+ pages.
- **Split or atom-ize `index.md`** when it exceeds ~200 entries / 8KB / 2000 tokens — orientation degrades beyond that. Evidence: Chroma Context Rot research shows retrieval accuracy starts degrading around 1,000 tokens of preamble; Obsidian MOC practitioners cap at 25 items per MOC; Starmorph flags 100-200 pages as the scale-out point.

When a threshold is reached, propose the restructure via a `schema-proposal` capture in `.wiki-pending/schema-proposals/`. Do NOT restructure during the current ingest.

## Category discipline (v2.3+)

Three rules govern how categories grow. Each has firing mechanism aimed at the agent during ingest, not at the user via status alarms.

**Rule 1: Don't create a new category to file ONE page.** Before mkdir-ing during ingest step 5 (decide-target-page), the current ingester checks: are there ≥3 pages I can place here, or one page that will grow to ≥3? If neither, place this page in an existing category instead. **Mechanism:** the provider-neutral ingest prompt carries this rule explicitly. Decision-time prevention beats after-the-fact warning.

**Rule 2: Sub-directory depth has a HARD cap of 4.** Validator REJECTS any page placed at depth ≥5 (`category/a/b/c/d/page.md`). The current ingester must place shallower if a deeper position would be required. **Mechanism:** validator exit non-zero. `wiki-status.sh` surfaces "categories exceeding depth 4" (always 0 if validator is doing its job).

**Rule 3: ≥8 categories soft ceiling triggers schema-proposal.** When current category count is already 8 and the current ingester wants to mkdir a 9th, it files a schema-proposal capture in `.wiki-pending/schema-proposals/<timestamp>-9th-category-<name>.md` instead of mkdir-ing. The current capture is filed in the existing-best-fit category for now. User reviews schema-proposal and can `mkdir` themselves to override. **Mechanism:** schema-proposal capture (not a hard reject — flexibility preserved). `wiki-status.sh` surfaces "category count vs soft-ceiling 8."

## What's NOT in this skill

- Iron laws and the agent-facing capture-trigger taxonomy. Those live in the loader (`using-karpathy-wiki/SKILL.md`) — single source of truth.
- Capture authoring (how the main agent writes a capture body, body floors per kind). Lives in `karpathy-wiki-capture/SKILL.md`.
- Cross-link convention, frontmatter standards, quality block format. See `references/page-conventions.md`.
- Capture frontmatter schema. See `<plugin>/skills/karpathy-wiki-capture/references/capture-schema.md`.
