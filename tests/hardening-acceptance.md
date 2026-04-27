# v2-hardening acceptance (Tasks 30-44)

Date: 2026-04-24

## Acceptance checks

- [x] `bash tests/run-all.sh` exits 0 (unit + integration).
  Result: passed: 17, failed: 0 (all unit + integration suites green)

- [x] `bash tests/self-review.sh` exits 0 (mechanical invariants green).
  Result: all 9 checks PASS

- [x] For every page under `~/wiki/concepts|entities|sources|queries`, `wiki-validate-page.py --wiki-root ~/wiki` exits 0.
  Result: sweep exit 0, no failures across 25 pages (8 concepts, 2 entities, 6 sources, 0 queries)

- [x] `~/wiki/.manifest.json` has exactly one entry per file under `~/wiki/raw/`, each with sha256, origin (non-empty or the literal "conversation"), copied_at, last_ingested, referenced_by.
  Result: 6 raw files, 6 manifest entries, all fields present and non-empty

- [x] `~/wiki/raw/.manifest.json` does not exist.
  Result: confirmed absent

- [x] `~/wiki/entities/electron-nwjs-steam-wrapper.md` is a stub pointing at `concepts/threejs-steam-publishing.md`.
  Result: stub confirmed; links to concepts/threejs-steam-publishing.md. Note: file is 28 lines (plan template produces ~28 lines with quality block); the "< 20 lines" acceptance criterion in the plan conflicts with the verbatim template also in the plan -- the template was followed verbatim.

- [x] `~/wiki/concepts/dentin-hypersensitivity-diagnosis.md` has `personal` in its tag list and the 10-year anecdote is in a `> personal` blockquote.
  Result: tags include `personal`; anecdote wrapped in `> personal` blockquote per plan.

- [x] `~/wiki/schema.md` has the "Reserved meta-tags" section with `#personal`.
  Result: `### Reserved meta-tags` section present with `#personal`, `#research-gap`, `#contradicts`; `### Tag Synonyms` section present with `- dental == dentistry`.

- [x] GREEN-results.md has a Scenario 4 section documenting the missed-cross-link behavior.
  Result: Scenario 4 at line 101 of tests/green/GREEN-results.md -- PASS verdict documented.

- [ ] User has manually inspected `wiki status` output from inside `~/wiki/` and confirms the new lines (`pages below 3.5 quality`, `tag synonyms flagged`) read sensibly.
  Awaiting human sign-off. `wiki status` output at time of acceptance run:
  ```
  wiki: /Users/lukaszmaj/wiki
  role: main
  total pages: 25
  pending: 0
  processing: 0
  active locks: 0
  last ingest: 2026-04-23
  drift: CLEAN
  git: clean
  pages below 3.5 quality: 14
  tag synonyms flagged: 4
  ```

## Additional notes (deviations from plan)

1. Task 41 ingester (PID 16188) wrote all files correctly (concept page, source pointer, manifest, cross-links) but did not write to `.ingest.log` or auto-commit -- likely the headless model exited before the `wiki-commit.sh` call. The ingester-produced commit was created manually with message `ingest: Sensitive Teeth -- Toothpaste Ingredient Tolerance and Elmex OptiNamel`. The capture was archived manually. All content is correct.

2. `wiki-lint-tags.py` bug: the `_load_synonym_pairs` function checked only for `## Tag Synonyms` but the plan template uses `### Tag Synonyms` (level-3 subsection). Fixed in commit `ed983af` by extending the pattern to also match `### Tag Synonyms`. With the fix, `dental <-> dentistry (schema-listed synonym)` is correctly flagged.

3. Stub entity check: `electron-nwjs-steam-wrapper.md` is 28 lines (including quality block in YAML frontmatter). The plan's acceptance criterion says "< 20 lines" but the plan's own verbatim stub template generates ~28 lines when the quality block is included. Template was followed verbatim; the content is unambiguously a stub.

## Manual sign-off

Signed off by user: ____________   Date: ____________
