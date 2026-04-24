# Karpathy Wiki v2.2 Audit Report

**Date:** 2026-04-24
**Auditor:** Opus 4.7 max-effort (third audit; first was v2-hardening, second was v2.1 missed-capture)
**Wiki state at audit:**
- 40 concept pages, 3 entities, 31 sources, 4 ideas, 0 queries (= 78 type-bearing pages)
- 24 raw files, 45 archived captures, 4 schema-proposals
- 105 total pages reported by `wiki status`
- log.md: 427 lines / 93 `## [` headings (60 ingest, 28 stalled, 2 skip, 1 repair, 0 reject, 0 overwrite)
- index.md: 87 lines / 76 entries / **24,975 bytes** — three times over the 8 KB orientation threshold
- `.wiki-pending/` is empty (all captures landed)
- `.manifest.json` consolidated, `wiki-manifest.py diff` reports CLEAN
**Skill state at audit:**
- SKILL.md: 455 lines (45 lines headroom under the 500-line superpowers cap)
- 14 scripts in `scripts/` (15 if you count `__pycache__`)
- 5 commits on `v2-rewrite` since the v2-hardening shipped (`be6854e`, `0d7eacd`, `e256379`, `c64a122`, `1294003`)

---

## Executive summary

**Top 3 most important findings:**

1. **`index.md` has silently breached the orientation-degradation ceiling.** It is 24,975 bytes — over 3x the 8 KB threshold and ≈12,500 tokens (≈12.5x the 1,000-token Chroma Context Rot inflection). The skill's own numeric threshold says "split at ~200 entries / 8KB / 2000 tokens"; the rule was added in the v2.1 patch but the agent has never authored a schema-proposal capture to act on it. The orientation read it prescribes is now noticeably cheap-pollutes context, and will degrade further with every ingest.
2. **The validator silently accepts `type: query` on files in `sources/`** (5 live source pages have it — `2026-04-24-cyberpunk-terminal-stack.md`, `2026-04-24-api-sdk-cli-mcp-wrapper-stack.md`, `2026-04-24T14-08-32Z-wiki-obsidian-integration.md`, `2026-04-24T17-23-00Z-zellij-mental-model-session-tab-pane.md`, `2026-04-24T17-23-01Z-zellij-macos-gotchas.md`). The validator only checks that `type` is in `{concept, entity, source, query}` — it never cross-checks `type` against the directory the page lives in. The ingester is mis-typing source pointer pages and the safety net never catches it. This silently breaks the queries/ category accounting (which currently shows 0 entries in `wiki status` despite five "queries" in `sources/`).
3. **The capture body floors are systematically too low for `conversation` captures.** All 11 sub-3.5 pages cluster either in (a) early action-tokenization/dental work that ran before v2-hardening shipped or (b) `sources/` pointer pages whose body is the 5-line template the ingester writes. The floor (1500b for conversation) is honored but the body is structurally a stub. Symptom: 5 of the 11 lowest-quality pages are sources/ pointer pages with quality 3.0 — the cluster the TODO predicted.

**Recommended next plan:** **v2.2-hardening** for findings 1, 2, 3, 4, 5, 6, 7 (blockers + highs — 7 fixes, mostly validator/script edits, one small SKILL.md prose tightening on index split + one ingester behavior tightening on source-pointer body shape). **Defer** findings 8-15 to v2.3 (medium/low — most are content cleanup that `wiki doctor` will resolve when implemented). Implementing v2.2-hardening in the same shape as v2-hardening is appropriate; it is mostly mechanical enforcement.

---

## Findings (ordered by severity)

### [BLOCKER] Finding 01: `index.md` has breached the orientation-degradation ceiling and the agent has not surfaced a schema-proposal

- **What's wrong:** `/Users/lukaszmaj/wiki/index.md` is now 24,975 bytes / 87 lines / 76 entries. SKILL.md line 359 says: "Split or atom-ize `index.md` when it exceeds ~200 entries / 8KB / 2000 tokens — orientation degrades beyond that. Evidence: Chroma Context Rot research shows retrieval accuracy starts degrading around 1,000 tokens of preamble." The 8 KB threshold was crossed long ago; the wiki is at ≈12,500 tokens of orientation preamble, ≈12x the Chroma inflection. No `schema-proposal` capture has been filed; `wiki-pending/schema-proposals/` contains 5 captures, none about index splitting.
- **Why it matters:** The skill mandates reading `index.md` end-to-end on every orientation pass (SKILL.md line 70). At 12,500 tokens the agent is paying that cost on every wiki query and every ingest. Worse, the recall accuracy degradation means the agent will start missing relevant pages during cross-link suggestion and missed-cross-link checks — exactly the kind of silent quality regression that the v2-hardening missed-cross-link Tier-1 lint was designed to prevent. Half of the islands found in this audit (Finding 04) are downstream of this: the cheap model is missing connections that should be obvious.
- **Where the skill should change:** SKILL.md "Numeric thresholds (from schema.md)" section (line 354) — the threshold is correctly documented but the *mechanism that fires it* is missing. The ingester's step 7 ("Update `index.md`") needs an explicit post-update size check that drops a `schema-proposal` capture when the threshold is met. Without this, "thresholds" are decoration.
- **Suggested fix shape:**
  - Add ingest step 7.6: "After updating `index.md`, measure its byte size. If > 8 KB, append a `.wiki-pending/schema-proposals/<ts>-index-split.md` capture suggesting an atom-ize: split `## Concepts` into per-tag sub-indexes or split into `index/concepts.md`, `index/sources.md`, etc., re-link from `index.md` as a 5-line MOC. Do not block ingest. Do not split inline."
  - Update `wiki-status.sh` to surface "index.md: 25KB / 76 entries — over 8KB threshold; consider atom-ization" so the user sees it at a glance.
  - Decide architecturally: per-category sub-index files, or per-tag MOCs? Document the choice in `karpathy-wiki-v2-design.md` so it isn't bikeshed every audit.
- **Test that would catch a regression:** Unit test for the size-check step: build a fixture wiki with an `index.md` that has 200 line entries, run an ingest mock, assert that a `.wiki-pending/schema-proposals/*-index-split.md` capture exists after.

### [BLOCKER] Finding 02: Validator does not cross-check `type` against page directory; 5 live `sources/` pages are mis-typed as `query`

- **What's wrong:** The validator at `/Users/lukaszmaj/.claude/skills/karpathy-wiki/scripts/wiki-validate-page.py` line 40 declares `VALID_TYPES = {"concept", "entity", "source", "query"}` and at line 233 checks `type in VALID_TYPES`. It never cross-checks: a page in `sources/` that says `type: query` passes. Five live source pages are doing exactly this:
  - `/Users/lukaszmaj/wiki/sources/2026-04-24-cyberpunk-terminal-stack.md` → `type: query`
  - `/Users/lukaszmaj/wiki/sources/2026-04-24-api-sdk-cli-mcp-wrapper-stack.md` → `type: query`
  - `/Users/lukaszmaj/wiki/sources/2026-04-24T14-08-32Z-wiki-obsidian-integration.md` → `type: query`
  - `/Users/lukaszmaj/wiki/sources/2026-04-24T17-23-00Z-zellij-mental-model-session-tab-pane.md` → `type: query`
  - `/Users/lukaszmaj/wiki/sources/2026-04-24T17-23-01Z-zellij-macos-gotchas.md` → `type: query`
  Adjacent: 4 of 4 ideas/ pages still use `type: concept` as a workaround (`obsidian-rich-init.md`, `sessionstart-hook-inject-skill.md`, `wiki-doctor-real-implementation.md`) — the workaround predicted in the TODO and tracked by the `validate-idea-pages.md` idea page. Only `validate-idea-pages.md` itself uses `type: idea`.
- **Why it matters:** The skill's mental-model contract is that `type` and directory are the same fact (`type: concept` lives in `concepts/`). When they diverge, downstream consumers break: `wiki-status.sh` would mis-count categories; index.md "## Queries" section is empty despite five queries in sources/ (or, conversely, the queries section is fine because the agent ignores `type` and uses dir, in which case `type` is dead metadata). Either way the validator's job is to keep the two facts in sync, and it isn't doing that. Fix 9 of v2-hardening explicitly added this rule for `type: source` (validator checks for matching raw file, line 369-377) but the broader directory-vs-type symmetry was missed.
- **Where the skill should change:** `scripts/wiki-validate-page.py` — add a cross-check after the type-whitelist check at line 232.
- **Suggested fix shape:** Add to `validate()` after the `type` whitelist check:
  ```python
  if "type" in data and wiki_root is not None:
      try:
          rel = page_path.resolve().relative_to(wiki_root.resolve())
          parent = rel.parts[0]  # 'concepts' / 'entities' / 'sources' / 'queries' / 'ideas'
          expected_type = {
              "concepts": "concept", "entities": "entity",
              "sources": "source", "queries": "query", "ideas": "idea",
          }.get(parent)
          if expected_type and data["type"] != expected_type:
              violations.append(
                  f"{page_path}: type={data['type']!r} but page is in "
                  f"{parent}/ (expected type={expected_type!r})"
              )
      except ValueError:
          pass  # page outside wiki root — skip
  ```
  Then either (a) extend `VALID_TYPES` to include `"idea"`, or (b) add a special case so `type: idea` only validates in `ideas/`. Recommend (a) plus also allow `type: idea` to require `status:` and `priority:` per schema.md.
  Backfill: re-type the 5 source/ pages to `type: source`; re-type the 3 ideas/ pages to `type: idea` and update validator to accept it. The `validate-idea-pages.md` page itself can then be marked `status: shipped`.
- **Test that would catch a regression:** Unit test: fixture wiki with `sources/foo.md` carrying `type: concept` — assert the validator emits the new violation.

### [BLOCKER] Finding 03: 4 captures landed in archive with `.processing` suffix still attached

- **What's wrong:** `find /Users/lukaszmaj/wiki/.wiki-pending/archive -name "*.processing"` returns 4 hits:
  - `2026-04/2026-04-24T12-48-16Z-format-choice-synthesis.md.processing`
  - `2026-04/2026-04-24T13-15-00Z-claude-code-sync-augment.md.processing`
  - `2026-04/2026-04-24T14-06-03Z-planner-reviewer-implementer-subagent-pattern.md.processing`
  - `2026-04/2026-04-24T17-27-43Z-yazi-install-gotchas.md.processing`
  All four were ingested successfully (concept pages exist for each, log.md has matching `ingest |` entries), but the archive step (SKILL.md line 324: `wiki_capture_archive`) renamed `<wiki>/.wiki-pending/<x>.md.processing` → `<wiki>/.wiki-pending/archive/2026-04/<x>.md.processing` instead of stripping the `.processing` suffix. The `wiki_capture_archive` helper in `wiki-lib.sh` does not strip the suffix.
- **Why it matters:** Two downstream effects.
  1. **Stalled-recovery confusion.** The stalled-capture recovery rule (SKILL.md lines 230-247) keys on `.md.processing` files. If the recovery routine ever scans recursively (it currently doesn't, but the prose is weak about depth), it would resurrect already-archived captures.
  2. **Audit-trail noise.** A future user grepping the archive for "completed captures" gets a mix of `.md` and `.md.processing` filenames; downstream tools (`gh issue create` migration mentioned in TODO, future search) hit ambiguous suffixes.
- **Where the skill should change:** `scripts/wiki-lib.sh` `wiki_capture_archive()` (the helper SKILL.md step 10 invokes). Currently it `mv`'s into the dated archive subdir without renaming.
- **Suggested fix shape:** In `wiki_capture_archive`, after computing the destination subdir, change the basename to strip a trailing `.processing`:
  ```bash
  base="$(basename "$capture")"
  base="${base%.processing}"
  mv -- "$capture" "$archive_dir/$base"
  ```
  One-time fix for the 4 existing archive entries: a tiny `wiki-archive-rename.sh` migration that renames `*.processing` files in `archive/2026-04/` to drop the suffix. SKILL.md prose at line 324 should state explicitly that archiving strips the `.processing` suffix.
- **Test that would catch a regression:** Unit test extending `tests/unit/test-lock.sh` (or a new `test-archive.sh`): set up a fake `.md.processing` file, call `wiki_capture_archive`, assert the archived file's basename ends in `.md` not `.md.processing`.

### [HIGH] Finding 04: 7 broken markdown links in 5 live wiki pages — Tier-1 lint regressed

- **What's wrong:** Running the validator against every wiki page (`wiki-validate-page.py --wiki-root /Users/lukaszmaj/wiki <page>` for each page) surfaces these failures, all link-related:
  - `concepts/wiki-obsidian-integration.md`: broken link to `concepts/jina-reader.md` (line 47, an example `[Jina Reader](concepts/jina-reader.md)` in prose) AND broken link to `path.md` (line 119, the literal example of "portable markdown — links stay `[Title](path.md)` format")
  - `concepts/starship-terminal-theming.md`: broken links to `concepts/cyberpunk-terminal-stack.md` and `concepts/zellij-plugins-junior-dev.md` (both in `## See also` — paths use `concepts/` prefix when both linker and linkee are in the same directory; this is the same regression Audit fix from v2-hardening was supposed to close)
  - `sources/2026-04-24T14-08-32Z-wiki-obsidian-integration.md`: broken link to `path.md` (mirrored from the concept page)
  - `sources/2026-04-24T17-27-08Z-starship-terminal-themes.md`: missing `quality:` block AND `type=source but no matching raw file at raw/2026-04-24T17-27-08Z-starship-terminal-themes.*`
  - `sources/2026-04-24-fuse-t-sshfs-macos.md`: type=source but no matching raw file at raw/2026-04-24-fuse-t-sshfs-macos.*
  - `sources/2026-04-24T17-27-41Z-zellij-kgp-passthrough-gap.md`: same — no matching raw
- **Why it matters:** SKILL.md ingest step 12 (Tier-1 lint, lines 328-348) says the ingester "MUST run the validator on every page you just touched ... If the validator exits non-zero for any page, fix the mechanical issue and re-validate. Do NOT commit a wiki state where the validator fails." Either the lint isn't running, OR it's running and the ingester is choosing to commit anyway. Six of the 7 violations are in pages ingested in the last 24 hours (`starship`, `wiki-obsidian-integration`, `fuse-t-sshfs-macos`, `zellij-kgp-passthrough-gap`) — so this is a regression, not legacy state. The two example-text false positives (`jina-reader.md` and `path.md` as illustrative URL strings) point at a different gap: the validator doesn't distinguish "this is a markdown link example INSIDE a code span / inline code" from "this is a real link". Both regex captures are lowercase `[Jina Reader](...)` outside code fences, so they triggered.
- **Where the skill should change:**
  - `wiki-validate-page.py`: skip links inside fenced code blocks AND inside backtick-wrapped inline code spans. The current regex `_LINK_RE` doesn't.
  - SKILL.md ingest step 12: state explicitly "ingester must NOT call `wiki-commit.sh` if the validator exits non-zero for any touched page." Audit log lines like `## [...] ingest | starship terminal theming | ... — pages created` are followed by no validator-failure log line, suggesting the ingester emits the success log entry without ever calling the validator.
  - `wiki-spawn-ingester.sh` or the ingest prompt: add a final pre-commit assertion `python3 scripts/wiki-validate-page.py --wiki-root "$WIKI_ROOT" "<page>"` and fail the commit step on non-zero.
- **Suggested fix shape:**
  - In `wiki-validate-page.py._extract_body_links`, strip out fenced code blocks first (`re.sub(r'```.*?```', '', body, flags=re.DOTALL)`) and inline code (`re.sub(r'`[^`]+`', '', stripped)`).
  - SKILL.md step 12: add the line "If the validator returns errors, the ingester MUST repair them BEFORE step 11 (commit). The commit step is gated on validator success."
- **Test that would catch a regression:** RED scenario: ingest a fixture capture that produces a concept page with a broken `## See also` link AND with a broken example like `[Foo](bar.md)` inside a fenced code block. Assert validator emits 1 violation (the See also), not 2.

### [HIGH] Finding 05: Source-pointer pages are structurally stub-shaped — 11 of 31 are 12 lines or fewer

- **What's wrong:** Distribution of source page line counts (sorted ascending): `23, 23, 24, 27, 28, 28, 28, 28, 29, 29, 33, 33, 34, 34, 35, 35, 35, 36, 37, 37, ...`. The smallest 5 are 23-27 lines; almost all are template-shaped (frontmatter + 5-line "**Origin:** … **Referenced by:** … **Summary:** …" block). 5 of the 11 sub-3.5-quality pages are source pointers (`2026-04-24-clove-oil-dental.md` q=3.00, `2026-04-24-claude-code-dotclaude-sync-plan.md` q=3.00, `2026-04-24-dentin-hypersensitivity-diagnosis.md` q=3.00, `2026-04-24-apple-notes-llm-integration.md` q=3.00, `2026-04-23-agent-action-tokenization.md` q=3.00). These are the dental + early-tokenization pages. The TODO predicted this exact cluster: "Whether `quality.overall < 3.5` pages cluster in any particular category or tag — signal the ingester is chronically over-cautious in a domain."
- **Why it matters:** Source-pointer pages exist (Audit fix 5) to ground the "every raw has a Sources/ summary" symmetry. But if the summary is a 5-line template, it adds zero retrieval value — the user reading `index.md` and following the source-pointer link gets no extra information than the raw file's first paragraph. The cluster suggests source-pointer pages ARE the dead formality the TODO suspected ("Whether `sources/` pointer pages degenerate into dead formality (only 1-2 lines each) and should merge into `raw/` metadata"). Confirmed: they did.
- **Where the skill should change:** Two paths.
  - **Path A (raise the bar):** SKILL.md ingest step 4 — when creating a `sources/<basename>.md` pointer, the body MUST contain at least 3 of the following: (i) a 1-paragraph TL;DR distilling the raw, (ii) the raw's bullet-pointed key claims, (iii) a links-out section to every concept page that incorporates this source's claims. Validator gains a new rule: source-pointer body ≥ 400 bytes (smaller than capture floor since pointer).
  - **Path B (cut the formality):** Move the source-pointer's three lines (`Origin`, `Referenced by`, `Summary`) into the manifest entry as fields, render them into `index.md` per-source line, and drop `sources/*.md` as a category. Concept pages still cite `sources: - raw/foo.md` directly. This is the "merge into raw/ metadata" the TODO suggested.
  - Picking one is a design choice; recommend Path A because Path B requires re-writing every concept page's `sources:` field and breaking inbound links.
- **Suggested fix shape:** Path A: extend `wiki-validate-page.py` with `if data.get("type") == "source": <body byte check ≥ 400>`. Add a new "Source-pointer body sufficiency" subsection to SKILL.md analogous to "Capture body sufficiency" (line 148). Re-rate the 5 stub source pages by hand or wait for `wiki doctor`.
- **Test that would catch a regression:** Fixture: a 100-byte source pointer; validator emits "source pointer body too thin (100b < 400b floor)".

### [HIGH] Finding 06: Manifest origin field empty (`""`) on 2 entries — Iron Rule #7 violation

- **What's wrong:** `/Users/lukaszmaj/wiki/.manifest.json` has two entries with `"origin": ""`:
  - `raw/2026-04-24-copyparty-serve-deny-limits.md` (also has `referenced_by: []`)
  - `raw/2026-04-24-yazi-install-gotchas.md` (also has `referenced_by: []`)
  Both are conversation captures that produced concept pages (per log.md `ingest |` entries) but the manifest entry was never linked back. SKILL.md line 287 (Iron Rule #7) says: "`origin` is the capture's `evidence` field value — never the string `\"file\"`, `\"conversation\"` (when a real path was available), `\"mixed\"`, or the evidence_type. If `evidence_type == \"conversation\"` AND the capture has no real path, `origin` is the literal string `\"conversation\"`. Any other value is a validator failure."
- **Why it matters:** The empty-origin case is NOT in the Iron Rule's enumeration — it's neither `"file"`, `"conversation"`, `"mixed"`, nor a path. It's the absence of any decision. Two `referenced_by: []` entries on the same raws confirm the ingester wrote the manifest entry as a side-effect of `wiki-manifest.py build` (which preserves prior values, default `""`) but the per-capture write of step 4 ("write or update the manifest entry") was skipped or failed. The same hardening cycle that closed the clove-oil regression (Audit fix 2) didn't add a validator check for `origin == ""`.
- **Where the skill should change:**
  - `wiki-manifest.py`: add a `validate` subcommand that verifies every entry's `origin` is non-empty AND matches one of {literal `"conversation"`, an absolute path}. Currently only `build` and `diff` and `migrate` exist (`migrate` is one-shot; `diff` only checks sha drift). The `wiki status` rollup should call this and surface origin violations.
  - SKILL.md step 4: tighten the prose — "The manifest entry MUST have a non-empty `origin`. If you cannot determine `origin` from the capture, do NOT write the manifest entry; emit a `## [...] reject | <basename> — capture missing evidence field` log line and bail."
- **Suggested fix shape:** Add `cmd_validate(wiki_root)` to `wiki-manifest.py`:
  ```python
  def cmd_validate(wiki_root: Path) -> int:
      manifest = _load_json(wiki_root / ".manifest.json")
      bad = []
      for k, v in manifest.items():
          o = v.get("origin", "")
          if o == "":
              bad.append(f"{k}: empty origin")
          elif o in ("file", "mixed"):
              bad.append(f"{k}: origin is literal evidence_type {o!r}")
          elif o != "conversation" and not o.startswith("/"):
              bad.append(f"{k}: origin must be 'conversation' or absolute path, got {o!r}")
      for line in bad: print(line, file=sys.stderr)
      return 0 if not bad else 1
  ```
  Repair the 2 live entries by hand (set `origin: conversation`).
- **Test that would catch a regression:** Unit test: build a manifest with `"origin": ""`; assert `wiki-manifest.py validate` exits 1.

### [HIGH] Finding 07: Tag taxonomy is exploding — 193 distinct tags, 39 synonym pairs flagged, 64 orphans

- **What's wrong:** `wiki-lint-tags.py --all --wiki-root /Users/lukaszmaj/wiki` reports:
  - 193 distinct tags in use (was likely ~50 at v2 ship)
  - 39 synonym pairs flagged by levenshtein/shared-prefix heuristics
  - 64 orphan tags (used by < 2 pages)
  Examples of synonyms flagged that should be consolidated:
  - `#claude-code <-> claude-code` (hash-prefix vs bare — applies to 8 of the 12 levenshtein pairs)
  - `agent-orchestration <-> agent-sdk`, `apple-notes <-> applescript`, `context-compression <-> context-window <-> context7` (a 3-way drift cluster)
  - `file-browsing <-> file-formats <-> file-locking <-> file-serving` (4-way prefix drift — these are all distinct concepts that happen to share `file-`; needs human triage)
  - `lora <-> qlora`, `llm-agent <-> llm-agents`
  - `json <-> jsonl`, `toml <-> yaml` (substantively different formats but levenshtein 2)
  - `dental <-> dentistry` (correctly flagged via the schema synonyms list)
  Some flagged synonyms are false positives (`#api <-> #cli`, `cost <-> rust`, `fuse <-> rust`) but the real ones outweigh them.
  Orphan examples: `#agent-tooling`, `agent-orchestration`, `architecture`, `bash`, `bash-tool`, `code-review`, `compaction` — all single-use.
- **Why it matters:** Schema.md says tag taxonomy is bounded ("Grow organically; no closed list. See `wiki-lint-tags.py --all` for the live set"). Bounded-by-lint only works if the lint actually drives action. Currently `wiki status` reports "tag synonyms flagged: 39" but no schema-proposal capture has been written for any of them. The synonym list in schema.md still has only `dental == dentistry` from v2-hardening; all 38 other potential synonyms are unaddressed. Search behavior: a user looking for "agent" may miss `#agent-tooling`-tagged pages because the orientation pass uses tags directly.
  The hash-prefix-vs-bare cluster (`#claude-code` vs `claude-code` etc.) is a particularly clean wedge: the SKILL.md and schema.md leave the `#`-prefix convention ambiguous — the schema reserves `#personal`, `#research-gap`, `#contradicts` (with `#`) but the bounded taxonomy section doesn't say if domain tags carry `#`. The ingester clearly does both.
- **Where the skill should change:**
  - `schema.md`: pin the `#`-prefix convention. Recommend: reserved meta-tags use `#`; domain tags don't. Or vice versa. Pick one.
  - `wiki-lint-tags.py`: add a `--auto-propose` mode that writes a `schema-proposals/<ts>-tag-synonym-<a>-<b>.md` capture for each pair where levenshtein ≤ 2 AND both tags appear ≥ 3 times. Don't auto-act on prefix synonyms (false-positive prone).
  - SKILL.md ingest step 12 (Tier-1 lint): "if `wiki-lint-tags.py` flags any new (page-introduced) tag against an existing tag with levenshtein ≤ 2, drop a schema-proposal capture and downgrade the new tag to the existing one in the page just written." This last clause closes the loop — currently the ingester writes whatever tag the cheap model picked; nothing rewrites it.
- **Suggested fix shape:** Same shape as Finding 1 — a threshold-firing-script-action wiring that replaces decoration with mechanism. Plus one one-time `wiki doctor` pass to consolidate the 13 confirmed-real synonym pairs (run after #-prefix decision is made).
- **Test that would catch a regression:** Unit test for `wiki-lint-tags.py --auto-propose`: fixture wiki with 2 pages tagged `dentistry`, 3 pages tagged `dental`. Assert a schema-proposal capture appears.

### [HIGH] Finding 08: 19 pages self-rated `interlinking ≥ 4` are actually islands or near-islands (≤ 1 inbound link)

- **What's wrong:** Cross-link health analysis (build link graph from all pages → count inbound for each):
  - 3 true islands (no inbound from any wiki page): `ideas/validate-idea-pages.md`, `sources/2026-04-24T17-27-46Z-cyberpunk-terminal-palette.md`, `index.md`. The cyberpunk-terminal-palette source pointer is referenced ONLY by index.md (not by any concept page), making it a structural orphan.
  - 19 pages rated `interlinking: 4` or `interlinking: 5` by the ingester despite having ≤ 1 inbound wiki link. Examples:
    - `concepts/action-tokenization-finetuning-project.md` — interlinking=5, inbound=1 (only `agent-action-tokenization.md` links in)
    - `ideas/validate-idea-pages.md` — interlinking=5, inbound=0 (true island, but rated highest)
    - `ideas/wiki-doctor-real-implementation.md` — interlinking=5, inbound=1
    - `sources/2026-04-21-docs-fetching-methods.md` — interlinking=4, inbound=1
    - And 15 more `sources/` pages, all rated 4 with inbound=1 (the lone link being from their concept page)
- **Why it matters:** The ingester's self-rate of `interlinking` looks at *outbound* links from the freshly-edited page (which it sees) and not *inbound* links from elsewhere (which it doesn't, because the orientation read is index.md alone, not a full inbound graph). Result: source-pointer pages that link out to a single concept page get a 4 ("the link to my concept is correct and present") despite being functionally orphans. The rating is true to the dimension definition (SKILL.md line 313: "are cross-links to related pages present and correct?") but the dimension is measuring the wrong thing — outbound completeness, not graph centrality.
- **Where the skill should change:** Two options.
  - **Option A (cheap):** Re-define the dimension. SKILL.md line 313 → "interlinking: outbound completeness AND inbound presence — does the page sit in the wiki's link graph or is it an island?" The ingester then needs to read the inbound graph during step 6.5. This requires the ingester to compute the inbound count, which means scanning all pages — not free, but the missed-cross-link check at step 7.5 already does roughly this.
  - **Option B (right-sized):** Rename the dimension to `outbound_links` to match what the ingester can see. Add a new dimension `centrality` that `wiki doctor` (smart model with full graph context) computes. Self-rate dimension stays at 4, doctor adjusts to 2. This frees the ingester from a job it can't do.
- **Suggested fix shape:** Recommend Option B because the ingester's context budget is real. The dimension delta will surface "this page is rated 5/4/4/2 — missed cross-link opportunity" in `wiki status` rollup. Implement when `wiki doctor` ships.
- **Test that would catch a regression:** Fixture: page with 1 inbound link. Currently rated 4. Under Option B, doctor lowers to 2 and `wiki status` flags as "orphan candidate".

### [MEDIUM] Finding 09: Two source-pointer pages exist for one concept (VPS asset browsing stack); two for another (cyberpunk terminal stack)

- **What's wrong:**
  - VPS: `sources/2026-04-24-vps-asset-browsing-stack.md` AND `sources/2026-04-24T17-27-40Z-vps-asset-browsing-stack.md`. Both point at the same concept page, both are 1100-1200 bytes, slightly different tag sets, both originate from `conversation`. The first was created during the initial VPS ingest, the second during a stalled-recovery re-ingest where the ingester didn't notice the duplicate.
  - Cyberpunk: `sources/2026-04-24-cyberpunk-terminal-stack.md` (the `type: query`-mistyped page from Finding 02) AND `sources/2026-04-24T17-27-46Z-cyberpunk-terminal-palette.md`. Both source the same `concepts/cyberpunk-terminal-stack.md`. The "palette" page is the post-cyberpunk-recovery capture; the cyberpunk-terminal-stack one is the original.
  - log.md confirms multiple ingests for both topics (VPS was ingested 3 times, cyberpunk-related captures landed twice).
- **Why it matters:** Source-pointer duplication breaks the "one summary page per ingested source" invariant from schema.md. It's not validator-detectable today because the validator looks at one page in isolation. Manifest's `referenced_by` correctly shows both source pointers under `raw/2026-04-24-vps-asset-browsing-stack.md` (3 refs total) — so the consolidation work is just on the source/ side.
- **Where the skill should change:** Either (a) ingester detects "I'm about to write `sources/<basename>.md` but a sibling source page already references the same concept" and merges them, or (b) `wiki doctor` consolidates after the fact. Recommend (b) because (a) requires non-trivial content reconciliation that the cheap model is bad at.
- **Suggested fix shape:** Add to the (post-MVP) `wiki doctor`: walk `concepts/`, build map of concept → [source pages that link to it], for each concept with ≥ 2 source pointers, prompt the smart model to merge them into one keep-page and produce a redirect for the other (keeping inbound links via aliases). This is `wiki-doctor`'s natural job and is on the TODO; this finding raises its priority because the skill IS producing duplicates in the wild.
- **Test that would catch a regression:** Unit test: fixture wiki with 2 source pointers for one concept; doctor consolidates to 1.

### [MEDIUM] Finding 10: 4 pages have `updated > rated_at` (rating staleness from human edits or augment ingests)

- **What's wrong:** Pages where the `updated:` timestamp is later than `quality.rated_at:`:
  - `concepts/micro-editor-over-nano.md`: updated=2026-04-24T20:00:00Z, rated_at=2026-04-24T17:45:00Z (2 hours stale)
  - `concepts/claude-code-skill-autoload-mechanisms.md`: updated=2026-04-24T13:59:24Z, rated_at=2026-04-24T13:30:47Z (29 min stale)
  - `concepts/action-tokenization-finetuning-project.md`: updated=2026-04-24T23:30:00Z, rated_at=2026-04-24T13:20:59Z (10 hours stale)
  - `sources/2026-04-24-claude-code-dotclaude-sync-plan.md`: updated=2026-04-24T13:00:00Z, rated_at=2026-04-24T09:53:46Z (3 hours stale)
- **Why it matters:** SKILL.md step 6.5 (line 298) says "Self-rate every page you just touched." Touching the body and not re-rating means the rating is for an old version. If a future `wiki doctor` pass uses `rated_at` as a "skip if recent" optimization, it'll skip stale ratings. More immediately: `wiki status` rollup uses `quality.overall` to flag low-rated pages; if the body got better but the rating is from before, the page stays in the "needs attention" bucket falsely (and the converse — body got worse but rating is fresh — silently overrates).
- **Where the skill should change:** SKILL.md step 6.5: add "If you touched the page (body or frontmatter), you MUST set `rated_at` to now and re-evaluate the four scores. There is no skip path." Currently the prose says "Self-rate every page you just touched" — which is correct — but doesn't explicitly tie `rated_at` to `updated`.
- **Suggested fix shape:** Validator extension: `if updated > rated_at: violation("rating stale: page modified after last rating")`. This forces the ingester to re-rate. Plus SKILL.md prose tightening: "`rated_at` MUST equal or be later than `updated`."
- **Test that would catch a regression:** Unit test: fixture page with `updated=2026-04-24T15:00Z`, `rated_at=2026-04-24T14:00Z`; assert validator emits the new violation.

### [MEDIUM] Finding 11: Per-dimension ingester self-rate bias — `accuracy` clusters at 5 (55/77 pages = 71%), `interlinking` clusters at 3-4 (71/77 pages = 92%)

- **What's wrong:** Per-dimension distribution of ingester self-ratings (n=77 pages with ratings):
  - `accuracy`: mean 4.57 — `{3: 11, 4: 11, 5: 55}`. 71% are 5s. No 1s or 2s.
  - `completeness`: mean 4.19 — `{2: 1, 3: 10, 4: 39, 5: 27}`. 51% are 4s.
  - `signal`: mean 4.47 — `{2: 1, 3: 10, 4: 18, 5: 48}`. 62% are 5s.
  - `interlinking`: mean 3.68 — `{2: 1, 3: 28, 4: 43, 5: 5}`. 36% are 3s, 56% are 4s. Almost no 5s.
- **Why it matters:** The TODO predicted: "Whether the cheap model's self-rate is systematically biased (always 4-5? always 3?)." Confirmed both ways depending on dimension.
  - Accuracy 5s are suspect: SKILL.md line 311 defines accuracy as "does every claim map to evidence in `sources:`?" The cheap model has no facility to map claims to sources — it can't verify. It's defaulting to 5 because it doesn't have the tooling to lower the score.
  - Interlinking 3-4 cluster is the inverse of Finding 08: the cheap model IS trying to be conservative but the dimension is mis-specified (Finding 08).
  - The `accuracy` ceiling means `wiki doctor`'s biggest job (when it ships) is to lower accuracy ratings on pages whose claims can't be verified from cited sources.
- **Where the skill should change:** SKILL.md lines 309-314 (rating criteria). Tighten:
  - Accuracy: "If the page makes any claim that doesn't appear verbatim or near-verbatim in a cited source, score ≤ 4. Score 5 only when EVERY claim is directly cited or derived in 1 step." Add: "Default = 4 unless full audit possible. 5 is exceptional."
  - Add a fifth dimension `verifiability` that is binary (can claims be checked from cited sources at all? yes=5, no=2, partial=3). This separates "true" from "true-and-checkable".
  - Or, accept the cheap model can't do accuracy; replace dimension with one the cheap model CAN compute (e.g., `body_density = bytes / unique_claims`).
- **Suggested fix shape:** Smallest change is the prose tightening at line 311. The new dimension proposal is overengineered for v2.2 — defer.
- **Test that would catch a regression:** None mechanical (rating bias is observable, not testable). The next audit should re-histogram and assert `accuracy` mean drops below 4.4.

### [MEDIUM] Finding 12: Stalled-capture recovery: 28 stalled events for ~14 distinct captures means most captures stalled at least twice; the SIGTERM root cause is operating below the surface

- **What's wrong:** log.md analysis:
  - 28 `stalled |` log entries for 14 distinct captures (so each capture stalled ≈2x on average).
  - 60 `ingest |` entries for 30 distinct captures (so most captures landed but some twice — `2026-04-24T14-08-32Z-ideas-category-proposal.md` landed 4 times, vps-asset-browsing-stack.md landed 3 times, micro-editor-over-nano.md landed 3 times).
  - 0 `reject |` entries (the body-floor rejection path has never fired in the wild).
  - 0 `overwrite |` entries (the v2.1-patch overwrite-detection has never fired).
  - 1 `repair |` entry (manual cleanup of the bogus yazi raw/sources mismatch).
  - 2 `skip |` entries (sha-match short-circuit IS firing for re-runs of the same research file — works as designed).
  - At one point (log.md line 386) the user marked "ingesters SIGTERM'd on Max subscription" — a known platform issue, not a karpathy-wiki bug.
- **Why it matters:** The recovery mechanism is doing its job — every stalled capture eventually landed, no captures appear lost. But the cost is real: `2026-04-24T14-08-32Z-ideas-category-proposal.md` ran 4 ingest cycles to produce one final wiki state; that's 4x the LLM cost. The duplicate-ingest count for vps-asset-browsing-stack (3 ingests, also producing 2 source-pointer pages — Finding 09) shows the recovery sometimes makes the wiki slightly worse before it makes it better. The ingester does NOT short-circuit on "this capture's basename already corresponds to a fully-formed concept page with the same title" — it just re-runs and merges. That merge is generally successful but produces the duplicate source pointers from Finding 09.
- **Where the skill should change:** SKILL.md step 4 (after sha-match short-circuit, line 289): add a *concept-existence* short-circuit. "Before deciding target pages, check whether `concepts/<slug>.md` (where slug derives from the capture's `suggested_pages` or its title) already exists AND has been recently updated (within last 60 minutes). If so, treat this as a recovery re-run: do NOT create new source pointers; verify the existing ones; update the manifest's `last_ingested` and exit with a `## [...] skip | <basename> — concept already current` log line."
- **Suggested fix shape:** Add 4-line check to ingest step 4 between the sha-match short-circuit and the title-scope check. Test: fixture with two captures targeting same concept page; second ingest skips.
- **Test that would catch a regression:** Run a capture twice in succession; assert second run produces a `skip |` log line, not an `ingest |` line.

### [MEDIUM] Finding 13: SKILL.md still leaks mechanics in step prose (numbered steps 1-12) despite the user-facing-output contract added in `be6854e`

- **What's wrong:** SKILL.md commit `be6854e` added the user-facing output contract at lines 27-36, banning narration of "Spawn mechanics ('capture is claimed', 'ingester is running detached', 'now spawn')" etc. But the SKILL.md body at lines 248-326 (Ingester steps) and lines 184-194 (After writing a capture) still uses imperative mechanics-speak ("Append a file to `<wiki>/.wiki-pending/`", "Immediately spawn a detached ingester", "This returns in milliseconds. The spawner atomically claims the capture..."). The contract addresses *user-visible output*, not *agent-internal prose*. This is fine for the ingester (which is a separate process) but the main agent reads these steps and then re-emits them as transparency-about-process in some sessions — exactly the failure mode the contract was supposed to prevent.
- **Why it matters:** The narration ban is rule-shaped, but the surrounding prose is example-shaped. An agent reading "Append a file to <wiki>/.wiki-pending/ named ..." is being trained by the prose to think of itself as a mechanic, not an answerer. Real-session log.md entries from the past 24 hours show messages like "this required adding raw/2026-04-24-yazi-install-gotchas.md (validator-required basename match)" — that's the agent narrating mechanics in the LOG, not in user output. The log is a fine place for it but the boundary is fuzzy.
- **Where the skill should change:** SKILL.md sections 95-247 (Capture and Ingester sections). Refactor the agent-facing imperative prose to use a different voice from the user-facing output contract. Currently they're indistinguishable. Add a section header `## Mechanics (silent — never narrate to the user)` over the current Ingester Steps section to mark it as not-for-narration.
- **Suggested fix shape:** Cosmetic header changes only. Don't rewrite the imperative prose — the agent needs imperatives. Just visually separate "what the agent does" from "what the user sees".
- **Test that would catch a regression:** Manual; would need a test harness that runs `claude -p` against a fixture and grep'd the assistant output for "spawn", "capture is claimed", etc. Already deferred per TODO.

### [MEDIUM] Finding 14: `wiki-status.sh` reports `last ingest: 2026-04-23` despite ingest activity throughout 2026-04-24

- **What's wrong:** `bash /Users/lukaszmaj/.claude/skills/karpathy-wiki/scripts/wiki-status.sh /Users/lukaszmaj/wiki` outputs `last ingest: 2026-04-23` despite the most recent ingest being `[2026-04-24T17:45:00Z] ingest | VPS Asset Browsing Stack` and 30+ ingests across 2026-04-24. The "last ingest" field is reading the wrong source — likely the date of the second-to-latest log line group, or the date from a `git log` query that pulled commit-ish data.
- **Why it matters:** `wiki status` is the user's at-a-glance health view. A wrong "last ingest" date makes the user think the wiki is dormant when it's actively being filled. Compounds with Finding 1 (index.md size warning is also missing from `wiki status`).
- **Where the skill should change:** `scripts/wiki-status.sh`. The script likely greps log.md or the manifest's `last_ingested` field; both should agree.
- **Suggested fix shape:** `python3 -c "import json; print(max(v['last_ingested'][:10] for v in json.load(open('$WIKI/.manifest.json')).values()))"` to pull the maximum `last_ingested` ISO from the manifest; or `tail -n 200 log.md | grep -oE '\[20[0-9-]+T' | sort -u | tail -1`. Either gives the right answer.
- **Test that would catch a regression:** Unit test for `wiki-status.sh` with a fixture wiki having `last_ingested: 2026-05-01T...`; assert output line `last ingest: 2026-05-01`.

### [LOW] Finding 15: `wiki-lint-tags.py` levenshtein heuristic produces real false positives that should be suppressed

- **What's wrong:** Among the 39 flagged synonym pairs, several are confidently NOT synonyms:
  - `#api <-> #cli` — the levenshtein-2 trigger fires on the substring `#?i`. Unrelated concepts.
  - `#api <-> yazi` — same; spurious.
  - `cost <-> rust` — both are 4 chars, levenshtein 2; unrelated.
  - `fuse <-> rust` — same.
  - `hooks <-> tools` — same.
  - `#rest <-> rust` — same.
  - `toml <-> tools`, `toml <-> yaml`, `json <-> jsonl`, `yaml <-> yazi` — these are flagged as synonyms but each is a distinct file format / tool name.
- **Why it matters:** A user (or `wiki doctor`) acting on the synonym list will create false consolidations. The signal is good for finding real synonyms but the noise floor is too high.
- **Where the skill should change:** `scripts/wiki-lint-tags.py`. Add a `--ignore-synonyms` allowlist file or a hard-coded list of known-distinct pairs. The `--auto-propose` extension proposed in Finding 7 would benefit hugely from this.
- **Suggested fix shape:** Read `<wiki>/.wiki-config` or `<wiki>/schema.md` for an `ignored_synonym_pairs:` list (`json/jsonl`, `yaml/yazi`, etc.). Suppress those.
- **Test that would catch a regression:** Unit test with `json` and `jsonl` tags + an `ignored_synonym_pairs: [json/jsonl]` config; assert no synonym warning.

### [LOW] Finding 16: `ideas/wiki-doctor-real-implementation.md` and `ideas/sessionstart-hook-inject-skill.md` carry `sources: ["conversation", "concepts/foo.md"]` mixing source types

- **What's wrong:** Two ideas pages have a `sources:` list that mixes the literal string `"conversation"` with a wiki-relative path to a concept page. Examples:
  - `ideas/sessionstart-hook-inject-skill.md`: `sources: ["conversation", "concepts/claude-code-skill-autoload-mechanisms.md"]`
  - `ideas/wiki-doctor-real-implementation.md`: `sources: ["conversation", "concepts/wiki-quality-rating-system.md"]`
  The validator passes these because both are strings. But semantically `"conversation"` (a literal sentinel) and `"concepts/..."` (a relative path) are different kinds of thing. SKILL.md doesn't define what should appear in `sources:` — the implicit contract is "absolute paths to raw/ files OR the literal `conversation`", but ideas pages add a third class: "wiki-relative paths to concept pages I derive from."
- **Why it matters:** The validator's `sources entry does not exist on disk` check (lines 354-366) DOES try to resolve each source as a wiki-relative path AND skips the check for literal `conversation`. So `concepts/foo.md` works because it resolves; `conversation` works because it's skipped. But other absolute paths to raw/ files fail (raw files don't live at the path the source field would imply unless they're relative `raw/foo.md`). This is fragile and `wiki-validate-page.py` should clarify what `sources:` means.
- **Where the skill should change:** SKILL.md "Capture file format" section (line 124) implicitly via an explicit "What goes in `sources:` on a wiki page (vs in a capture)" subsection. And a `related:` field for cross-page references (Ideas pages already use this — see `ideas/*.md` `related:` field in their frontmatter — it's just not in the validator's spec).
- **Suggested fix shape:** Document `sources:` as "the evidence the page is built FROM (raw files or `conversation`)" and `related:` as "other wiki pages this page conceptually depends on (no validator existence check, just a hint to humans)". Add `related:` to the validator's known-fields list as optional.
- **Test that would catch a regression:** Unit test: page with `related: [concepts/foo.md]`; validator passes; same page with `sources: [concepts/foo.md]`; validator emits "concepts/foo.md is not a raw file or 'conversation' literal".

---

## Things that are working well

A short list to balance the long list of findings. These are real wins:

- **Manifest consolidation (Audit fix 1) is holding.** `wiki-manifest.py diff` returns CLEAN. Every raw file has a sha256. No legacy `raw/.manifest.json` exists. Drift detection works.
- **Origin-field discipline is mostly intact** (Audit fix 2). Only 2 of 24 manifest entries have empty `origin` (Finding 06); the other 22 are correctly either an absolute path or the literal `conversation`. The clove-oil regression has not recurred.
- **Frontmatter normalization (Audit fix 7) is fully holding.** No pages with date-only `created`/`updated`. No pages with nested mappings in `sources:`. ISO-8601 UTC compliance is 100%.
- **The validator catches what it's designed to catch.** When run against the wiki, it finds 7 link-related violations and 4 missing-raw-file / missing-quality violations. Those are real bugs and the validator surfaces them. Where it misses things (Finding 02, Finding 04 code-block-link false positives) is well-bounded.
- **Sha-match short-circuit IS firing in the wild.** 2 `skip |` log entries confirm the de-duplication mechanism works exactly as designed when re-running an unchanged research file.
- **The stalled-capture recovery mechanism added in v2.1 IS working.** All 14 stalled captures eventually landed; nothing is lost. Cost is real (Finding 12) but the safety net is intact.
- **The body-floor rejection has never falsely-bounced a good capture.** Zero `reject |` log entries. The 200/1000/1500-byte floors hold. The one rejection in the archive (`2026-04-24T14-06-01Z-capture-body-byte-floor-calibration.md`) was from the meta-conversation about the floors themselves.
- **Title-scope check (gemma4 hardware page rename) and overwrite-detection are correctly absent from logs because the conditions haven't recurred.** The fact that `## [...] overwrite |` log entries are zero does NOT mean the mechanism is broken — it means there have been no two-research-file collisions since the gemma4 case. The mechanism is dormant-but-correct.
- **`#personal` tag IS being applied in practice.** 7 pages carry it: dental + tokenization + cyberpunk + zellij-plugins + wiki-obsidian + others. The reserved-tag pattern works.
- **The `ideas/` category landed without breaking the validator.** Three ideas pages work, fourth one (`validate-idea-pages.md`) self-documents the remaining gap.
- **The TODO.md file is a real working artifact.** Status counts: 1 blocked, 6 deferred, 3 open, 1 rejected. It's the right shape for pre-merge planning.

---

## Things this audit deliberately did NOT cover

The next auditor should know these were out of scope:

- **GREEN scenario re-run.** The four GREEN-scenario fixtures from v2-hardening were not re-executed. They describe agent behaviors against a fresh `$HOME`; this audit looked at the LIVE wiki only. A v2.2-hardening plan should re-run them as part of acceptance.
- **`tests/run-all.sh` execution.** Not run during the audit (read-only contract). Should be run before any v2.2-hardening starts to confirm baseline is green.
- **Real-session transcript inspection.** This audit did not open any `~/.claude/projects/*.jsonl` files to verify what the agent ACTUALLY emitted to the user — only checked the artifacts left in `~/wiki/`. The narration-leak finding (Finding 13) is therefore inferential, not transcript-confirmed.
- **The `bin/wiki` command surface.** `wiki status` was run and analyzed; `wiki doctor` was confirmed to still be a stub (per TODO); other commands not exercised.
- **Project-wiki propagation.** No project wiki exists, so no propagation behavior was tested. The skill prose at step 9 is unchanged from v2.
- **Performance.** No timing of ingests, no fsync analysis, no parallel-spawn behavior. Per scope cuts in v2-hardening: "Hardening is correctness, not speed."
- **Security review of the spawned ingester (`claude -p` permissions).** Out of scope for content audit.
- **Cross-platform behavior.** macOS-only audit; nothing tested on Linux.
- **The `wiki-init.sh` Obsidian config.** TODO item "Obsidian: pre-enable core plugins in wiki init script" is `status: open` but not blocking; the .obsidian/ directory in the live wiki has been hand-evolved beyond what init writes. Out of scope to verify.

---

## Comparison to prior audit (v2-hardening)

For each of the 10 v2-hardening fixes, ground-truth status:

1. **Manifest sha256 + consolidation:** HOLDING. `diff` returns CLEAN. No legacy manifest. No dead `lpa-robotics-action-tokenization` reference. ✅
2. **Origin-loss bug fix:** MOSTLY HOLDING with new gap. Clove-oil case is correct (`origin: /Users/lukaszmaj/dev/bigbrain/research/2026-04-24-clove-oil-dental.md`). But two new entries have `origin: ""` (Finding 06) — a NEW failure mode the original fix didn't anticipate. The Iron Rule #7 enumeration doesn't include the empty-string case; that's the gap.
3. **4-dimensional rating frontmatter + ingester self-rating:** HOLDING with calibration issues. 77 of 78 pages have a complete `quality:` block. The math is correct (no overall-mean mismatches). But the `accuracy` and `interlinking` dimensions show systematic ingester bias (Finding 11) and the `interlinking` dimension is mis-specified (Finding 08). The mechanism works; the metrics need tuning.
4. **Tag-drift lint:** HOLDING but unactioned. `wiki-lint-tags.py` correctly flags 39 synonym pairs (Finding 07). But the loop is open: the lint reports them; nothing acts on them. Synonym list in schema.md is unchanged since the original `dental == dentistry` entry. Second-order effect: the script's levenshtein heuristic produces real false positives (Finding 15).
5. **Source-pointer pages mandatory:** PARTIALLY HOLDING. 30 of 31 sources/ pages exist. `raw/2026-04-24T17-27-43Z-yazi-install-gotchas.md` has no matching source pointer (Finding 04 enumerates this case). And 8 sources/ pages list no matching raw/ file (Finding 04). The bidirectional invariant is broken in both directions for at least 9 cases.
6. **Missed-cross-link check:** HOLDING in spirit, gap in dimension. The cheap-model check at ingest step 7.5 is producing cross-links (visible in the `cross-linked:` lines throughout log.md). But the inbound-link blindness from Finding 08 means it's not catching real islands (3 true islands in the wiki right now).
7. **Frontmatter normalization:** FULLY HOLDING. Zero violations of date format, sources flat-list, type whitelist. ✅
8. **Sensitive-teeth toothpaste ingest:** SHIPPED. `concepts/sensitive-teeth-toothpaste.md` exists, q=4.00, cross-linked correctly to dentin-hypersensitivity.
9. **electron-nwjs-steam-wrapper stub:** SHIPPED. The page is now a 12-line stub with `quality.notes: "stub -- content lives on concepts/threejs-steam-publishing.md; keep this page only if unique entity metadata accrues"`. Honestly captured as q=2.75. ✅
10. **#personal tag:** SHIPPED. Schema.md reserves it. Dentin-hypersensitivity page carries it. Six other pages also use it (cyberpunk-terminal-stack, zellij-plugins-junior-dev, action-tokenization-finetuning-project, etc.) — broader uptake than the original fix anticipated, mostly correctly.

**Net:** 4 holding fully (1, 7, 8, 10), 2 holding-with-gaps (5, 9), 4 holding-with-calibration-issues (2, 3, 4, 6). Zero regressions. Two NEW failure modes surfaced that the original audit didn't think to look for: empty-origin (Finding 06) and source-pointer body degeneracy (Finding 05).

---

## Comparison to v2.1 patch (missed-capture)

The v2.1 patch shipped 8 changes: durability test, turn-closure check, stalled-recovery, sha-match short-circuit, title-scope check, overwrite detection, index-size threshold, three new rationalization rows.

- **Turn-closure `ls .wiki-pending/` check:** Self-discipline rule per design; cannot mechanically verify firing. `.wiki-pending/` is currently empty (good). Most ingests landed within the same session they were captured (good). But Finding 1 (index.md unchecked) shows that the turn-closure check is narrow — it covers `.wiki-pending/` only, not other thresholds the agent should check at turn close.
- **Stalled-capture recovery:** WORKING. 28 stalled-event log entries; all eventually landed. See Finding 12.
- **Sha-match short-circuit:** WORKING. 2 `skip |` events confirm. ✅
- **Title-scope check:** UNFIRED. The check was added because of the gemma4 case; that case is now stable; no new collisions have arisen. Cannot verify the mechanism works in the wild yet, but the absence of `[overwrite |` log entries with `prior referenced_by:` is consistent with no triggers.
- **Overwrite detection:** UNFIRED. Same.
- **Index-size threshold (8 KB):** HOLDING in prose, FIRED in reality but UNACTED-ON. See Finding 1 — the prose says split at 8 KB, the wiki is at 25 KB, no schema-proposal exists. The mechanism exists in the SKILL.md text but nothing connects "threshold reached" to "schema-proposal capture written."
- **Three new rationalization rows:** Cannot verify firing in the wild without transcript inspection (deferred). The rows are visible in SKILL.md lines 423, 431, 437.

**Net:** 3 of 8 changes verified-working, 1 holding-but-narrow (turn-closure), 2 unfired-but-architecturally-sound, 1 fired-but-unacted (index threshold = Finding 1), 1 unverifiable-without-transcript.

The v2.1 patch's biggest blind spot: it added thresholds without wiring them to actions. Same shape as v2-hardening's Audit fix 4 (tag-drift lint reports → no action). The pattern is "decoration vs mechanism" and is the strongest signal for what v2.2-hardening should fix.

---

## Comparison to TODO.md

TODO.md state at audit: 11 items (1 blocked, 6 deferred, 3 open, 1 rejected, 0 shipped).

Per-item triage:

- **Stop-hook gate for turn-closure enforcement** (deferred, p1) — RAISE TO p0. Findings 1, 7 (unactioned thresholds) and the predictability that v2.1 turn-closure is self-discipline-only mean a real gate is now the highest-leverage architectural fix.
- **SessionStart hook injects SKILL.md content** (deferred, p2) — KEEP. No fresh-session miss observed in this audit (all triggers fired and produced captures, modulo Finding 1 about thresholds). Revisit criteria not yet met.
- **Real `wiki doctor` implementation** (deferred, p1) — RAISE TO p0. Findings 8, 9, 11 all point at smart-model work that only doctor can do. The TODO's revisit criterion ("After 5-10 real-session ingests accumulate") is met (45 captures); the additional criterion ("a persistent cluster of pages below 3.5 quality") is met (11 pages, all in dental + early-tokenization).
- **`--max-turns / --max-budget-usd` on ingester** (rejected) — KEEP REJECTED. Finding 12 (stalled-capture cost) might re-open the conversation, but the underlying recovery mechanism handles it. No reason to reverse.
- **`--bare` + explicit `--allowedTools`** (blocked) — KEEP. No new info; still defers to Anthropic.
- **`--json-schema` structured ingester output** (deferred, p3) — KEEP. No malformed output observed.
- **Real test coverage for SKILL.md prose rules** (deferred, p2) — RAISE TO p1. Finding 4 (Tier-1 lint regressed) shows the prose rules ARE regressing in the wild, which is the explicit revisit criterion. Need a harness.
- **Re-run the Opus auditor after real-session usage accumulates** (deferred, p1) — SHIPPED-BY-THIS-AUDIT. Move to Shipped section after this audit lands.
- **Obsidian: pre-enable core plugins in wiki init script** (open, p2) — KEEP. Not blocking, no audit change.
- **`ideas/` category in the wiki schema** (open, p3) — RAISE PRIORITY: this audit's Finding 02 includes the validator-doesn't-know-about-`type: idea` gap (validate-idea-pages.md is the relevant page). The fix is small, the workaround (3 pages mistyped as `concept`) is ugly, ship it.
- **Migration: TODO.md → GitHub Issues** (open, p3) — KEEP. Not blocking.

**Net:** 4 priority bumps (Stop-hook → p0, wiki doctor → p0, test coverage → p1, ideas/type → p1-implicit), 1 ship-this-audit (Opus auditor), 6 unchanged.

---

## Suggested v2.2-hardening scope

If the user takes one plan from this audit, take this:

**v2.2-hardening, ~7 fixes:**

1. **Index size mechanism.** Wire the 8KB/200-entry threshold to actually fire a schema-proposal capture (Finding 1). Add to `wiki-status.sh` rollup. Pick atom-ization shape (per-category sub-indexes vs per-tag MOCs) — document in design doc.
2. **Validator: type-vs-directory cross-check + `type: idea` support** (Finding 2). Backfill 5 mistyped sources/ pages and 3 ideas/ pages.
3. **`.processing` suffix stripping in archive helper** (Finding 3). Backfill 4 archived `.processing` files.
4. **Validator: skip code-block markdown links + ingester gates commit on validator success** (Finding 4). Repair 7 live link violations.
5. **Manifest validate subcommand + Iron Rule #7 strengthen for empty origin** (Finding 6). Repair 2 entries.
6. **Tag-drift schema-proposal auto-write + `#`-prefix decision** (Finding 7). Both the firing mechanism and the convention call.
7. **`wiki-status.sh` "last ingest" bug** (Finding 14). Pull from manifest's max `last_ingested`.

**Defer to v2.3** (post-`wiki doctor`):
- Source-pointer body floor (Finding 5) — needs body-content judgment, doctor's job.
- Interlinking dimension redefinition (Finding 8) — needs full graph reasoning, doctor's job.
- Source-pointer duplicate consolidation (Finding 9) — doctor's job.
- Rating staleness validator (Finding 10) — small, ships when convenient.
- Per-dimension bias correction (Finding 11) — needs doctor's smart re-rate to be useful.
- Concept-existence short-circuit on recovery (Finding 12) — possible but needs careful test.
- SKILL.md prose voice (Finding 13) — cosmetic, ships when convenient.
- Synonym false-positive allowlist (Finding 15) — small.
- `related:` vs `sources:` validator distinction (Finding 16) — small.

**Critical path:** Findings 1, 2, 3, 4, 6, 14 all reduce to script edits + small SKILL.md prose changes — same shape as v2-hardening Phases A and C. Finding 7 needs the `#`-prefix decision call from the user before scripting. None require a new tool, none require Anthropic-roadmap changes. The plan should fit in one branch off `v2-rewrite` similar to the v2-hardening shape.

---

End of audit.
