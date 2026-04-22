# Plan Review: karpathy-wiki-v2 Implementation Plan
Date: 2026-04-22
Reviewer: senior code reviewer (pre-execution gate)
Plan under review: `/Users/lukaszmaj/dev/bigbrain/plans/2026-04-22-karpathy-wiki-v2.md` (3,901 lines, 28 tasks, 4 phases)

## Summary
- Overall verdict: **approve-with-fixes** (the plan is well-structured and covers 90% of the design; a handful of real bugs in bash snippets and a SKILL.md that mis-declares length will bite during execution).
- Critical issues: 6
- Important issues: 10
- Minor issues: 8

The plan is in strong shape overall — the RED/GREEN/REFACTOR discipline is clean, the task slicing is near-optimal for subagent dispatch, all function names are consistent across tasks, and the architecture from the design doc is mostly faithfully encoded. The problems fall in three buckets: (1) bash bugs that will make tests fail when they run (`local` outside a function, parsing of CLEAN/NEW output, `mv -n` semantics), (2) missing architecture pieces that are in the design doc but have no task (cross-platform detection, `~/.wiki-config` home-level main-wiki record, SessionStart matcher, `hooks.json` file for Claude Code, transcript sweep), and (3) a SKILL.md whose `description` field still mildly narrates workflow and whose tasks do not preserve the "under 500 lines" invariant in any enforceable way.

## Critical issues
(these will cause execution to fail outright, produce wrong behavior, or fail the design intent)

### C1. `local` keyword used outside a function body in `hooks/session-start` (Task 15)

In the drift loop (lines 2424–2453) and again in the stale-processing-reclaim loop (lines 2479–2488):

```bash
while IFS= read -r line; do
  case "${line}" in
    NEW:*|MODIFIED:*)
      local_path="$(echo "${line}" | awk '{print $2}')"   # OK — a var name, not a keyword
      local capture_name                                    # BUG — `local` outside function
      capture_name="..."
      local capture_path                                    # BUG
```

`local` is only valid inside a function. The top-level script body will fail with `local: can only be used in a function`. Same bug at line 2480 (`local mtime now age` inside `while read`). This means the SessionStart hook will NOT work on any real session. The integration test may hide this because `set -e` gives up early; the ingester-spawn path will still silently abort.

**Fix:** drop the `local` declarations (top-level scripts don't need them) or wrap the relevant loop bodies in a function call.

### C2. `mv -n` is used as if it were atomic-exclusive; on macOS it silently no-ops when target exists (Task 11, wiki_capture_claim)

Lines 1505–1512:

```bash
if mv -n "${candidate}" "${claimed}" 2>/dev/null; then
  if [[ -f "${claimed}" ]] && [[ ! -f "${candidate}" ]]; then
    echo "${claimed}"
    return 0
  fi
fi
return 1
```

`mv -n` returns exit 0 on "did nothing because target exists" on macOS — so when two ingesters race on the same capture both will see `mv` return 0, and the post-hoc `[[ -f ]] && [[ ! -f ]]` check saves you here, but the result is that the **second-arriving ingester silently exits with "no capture" rather than seeing the collision**. That's OK behavior-wise, but the test `test_claim_is_atomic` at lines 1444–1457 runs both claims in the same shell sequentially — it doesn't actually test concurrency at all. Both calls happen with identical pid; the race is not exercised. A real concurrency test requires two backgrounded subshells.

More subtly: `mv` (without `-n`) on macOS BSD is NOT atomic across directories but IS atomic within a directory. That's fine since we're renaming within `.wiki-pending/`. But `mv -n` specifically adds a TOCTOU window on BSD (it `stat`s then `rename`s), which on a fast-enough race loses atomicity.

**Fix:** use `ln` + `unlink` (proper exclusive-create rename pattern) or `mv` without `-n` inside an explicit check loop. Also add a real concurrency test that backgrounds two claim calls.

### C3. Python script `wiki-config-read.py` prints `repr()` of dict/list values — breaks nested table reads (Task 9)

Line 1104:

```python
else:
    # Dict/list — print as repr so callers can parse if needed.
    print(repr(current))
```

Plan claims `wiki_config_get "${wiki}" platform` would be useful, but `print(repr(dict))` emits `{'agent_cli': 'claude', 'headless_command': 'claude -p'}` (single quotes) — not valid JSON, not shell-parseable. No current caller hits this path since the plan only reads scalar keys (`platform.headless_command`, `settings.auto_commit`, `role`), so it's a latent bug not a current one. But the test at line 1015 (`missing.key`) combined with this branch means ambiguous error cases (e.g. `wiki_config_get "${wiki}" platform` which is a table not a missing key) would surprise.

**Fix:** emit JSON (`json.dumps(current)`) for non-scalars, or fail with a clear error ("key is a table, not a value").

### C4. `hooks.json` is missing — the plan never creates the file Claude Code needs to discover hooks (Task 15 + Task 22)

The plan writes `hooks/session-start` and `hooks/stop` scripts, but Claude Code's plugin system **auto-discovers `hooks/hooks.json`** (see superpowers packaging study section 3.1 and 5.1). The plan has no Task that creates `hooks/hooks.json`. Instead, Task 22 Step 3 asks the executor to manually merge settings into `~/.claude/settings.json` — that's a fallback that works for a symlinked skill but defeats the whole point of packaging. When Task 25 writes `plugin.json` the plugin is still hooked-less because there's no `hooks/hooks.json` inside the plugin root.

The design doc (section "Hooks") and the packaging study both prescribe a per-plugin `hooks/hooks.json` with `"matcher": "startup|clear|compact"`. The plan encodes the matcher only inside the `settings.json` instructions in Task 22, not in the plugin manifest.

**Fix:** add a task (before Task 25 or as part of it) to write `hooks/hooks.json` with the same matcher and command structure. Point the command at the polyglot wrapper: `"${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd" session-start`. Do the same for `stop`.

### C5. The `matcher` narrowing and cost-of-reinjection lesson from superpowers issue #1220 is not encoded anywhere

The style guide explicitly calls out issue #1220: SessionStart fires on `startup|clear|compact` and injecting context 13× over a long session cost 17.8k tokens. The plan's session-start hook does emit empty context (good — fixes the cost problem at source), but the plan never specifies the **matcher** anywhere except inside the sample `settings.json` block in Task 22 (line 3438). If a future hands-off executor writes a `hooks.json` from scratch, they'll likely default to `".*"` because that's the obvious shape. The matcher is a deliberate narrowing and needs to be called out as a requirement.

**Fix:** when writing Task 15 Step 4 (polyglot wrapper) or a new task for `hooks.json`, include an explicit comment: `"matcher": "startup|clear|compact"  # narrow fire-set per superpowers issue #1220`.

### C6. Polyglot wrapper `run-hook.cmd` is defined but never USED by any hook wiring (Task 15)

Lines 2497–2533 write `hooks/run-hook.cmd` with the polyglot bash+cmd pattern, but Tasks 15, 16, 22, 25 all invoke hooks directly via `bash hooks/session-start`, never through `run-hook.cmd session-start`. The wrapper is dead weight as written. On Unix this is equivalent; on Windows (where the wrapper is only a Windows concern) the plan's invocation still would go through `bash` rather than `cmd.exe → bash.exe` via the wrapper.

Additionally the polyglot file as written has the bash section put together slightly wrong: `goto :eof` before the `CMDBLOCK` terminator means CMD execution jumps to end-of-file which is fine, but the bash `exec bash "${HOOK_DIR}/${HOOK_NAME}"` should `shift` and pass remaining args (unlike superpowers' version which does `shift; exec bash "$SCRIPT_NAME" "$@"`). Current version sends no args through beyond the script name, which is fine for session-start/stop today but will burn anyone who later invokes `run-hook.cmd some-script arg1 arg2`.

**Fix:** either (a) remove `run-hook.cmd` from MVP if cross-platform isn't a day-one goal, or (b) route `hooks/hooks.json` through it AND fix the bash tail to shift + pass args. Going with (a) is simpler for MVP; the polyglot wrapper is listed as "post-MVP" concern in several places already.

## Important issues
(things that will produce poor quality, skip the plan's own discipline, or violate design intent)

### I1. SKILL.md description still leaks workflow — violates style guide's #1 rule

From Task 21 (line 3159):

> Use when a session produces durable knowledge a future self would search for — a research finding, a resolved confusion, a validated pattern, a gotcha, a contradiction with prior notes, or a documented decision. **Also when a research subagent returns a file, when a user pastes a URL or document to study, or when `raw/` in a wiki directory has unprocessed files.** Do NOT use for routine lookups, obvious code edits, questions the wiki clearly does not cover, or time-sensitive information that should be fetched fresh.

This is 580 chars and mostly good — it describes triggers, not workflow. BUT it misses the query-shaped triggers that the design doc explicitly names ("user asks what we know about X", "how do we handle Y", "what did we decide about Z"). The `description` field is what the LLM sees to decide whether to load the body. If query-shaped triggers aren't in the description, the skill won't fire on natural questions — which is exactly the Hermes/Karpathy gap this is supposed to close.

The description also omits the "the user says 'add to wiki' / 'remember this' / 'wiki it'" phrasal trigger that the design doc calls out. These are short, high-signal phrases that should live in the description.

**Fix:** rewrite to include 3-5 question-shaped triggers and 2-3 phrasal triggers. Keep it under 700 chars. Style guide's derived playbook (section 3.3) is the template.

### I2. SKILL.md lacks "Announce at start" line the style guide names as a bulletproofing pattern

The superpowers pattern is "**Announce at start:** 'I'm using the [name] skill to [purpose].'" — it forces the agent to declare its skill use aloud, reducing silent-skip. The skill body opens with "The iron law" but no announce line. The style guide (section 6.3) gives the exact copy: *"Using the wiki skill to [capture this / ingest pending captures / answer from wiki]."*

**Fix:** add an `**Announce at start:**` line at the top of SKILL.md (above or below the iron-law fence).

### I3. SKILL.md's iron-law section is prose, not a triple-fenced block-quote as style guide prescribes

Line 3174:

```
**Never write to the wiki in the foreground. Never ask the user before ingesting. Capture cheap, ingest detached.**
```

The style-guide template (section 2) says the Iron Law is a **triple-fenced code block** (```NO X WITHOUT Y FIRST```) immediately after the overview. That treatment makes it scan-findable and visually gated. The current prose iron-law reads like a tagline, not an iron law.

Also, the style guide (section 7, pattern 2) suggests separate iron laws: `NO INGEST WITHOUT A CAPTURE FIRST` and `NO PAGE EDIT WITHOUT READING THE PAGE FIRST`. Two-iron-laws may be clearer than one combined one.

**Fix:** wrap the iron-law text in a triple-fenced block. Consider splitting into two block-quoted iron laws.

### I4. Missing tasks for `~/.wiki-config` (home-level main-wiki record) — design doc section "Wiki roles and topology" says this file exists

Design doc lines 110–117 specify a `~/.wiki-config` **at the home directory, not inside a wiki** that records `main_wiki_path`. The plan's wiki-init.sh (Task 13) writes `.wiki-config` inside the wiki directory but never touches `~/.wiki-config`. The skill's SKILL.md auto-init section (lines 3188–3205) checks for `$HOME/wiki/.wiki-config` directly, not the `~/.wiki-config` pointer. So the feature is silently dropped.

Is this a problem? Arguably no — the design-doc's `$WIKI_MAIN` env var and `~/.wiki-config` are described as "optional overrides" for power users who want the main wiki somewhere other than `~/wiki/`. The plan's "no env var, config file is sole truth" note in the File Structure section (line 113) suggests the plan deliberately drops both mechanisms. The self-review checklist (line 3886) confirms: "No env var `WIKI_MAIN` referenced anywhere (config file is sole truth)."

But the plan doesn't note that `~/.wiki-config` was deliberately dropped. Future maintainers will re-introduce it thinking it's a missing feature.

**Fix:** add a line to the plan's Overview or File Structure section: "`~/.wiki-config` and `$WIKI_MAIN` env var are both dropped — main-wiki location is hardcoded to `$HOME/wiki` with no override in v1."

### I5. Cross-platform `agent_cli` and `headless_command` detection is hardcoded, not detected — design says "detected at init"

Design doc (lines 185–189):
> `agent_cli` and `headless_command` are detected at init by checking env vars (`CLAUDE_CODE_*`, `CODEX_*`, etc.) and which CLIs are on `PATH`. Re-detected if detection appears wrong.

The plan's `wiki-init.sh` hardcodes `agent_cli = "claude"` and `headless_command = "claude -p"` (lines 1970, 1983). No detection. This is fine for MVP (the plan explicitly says "Claude Code only"), but the plan should acknowledge this as a deferred feature rather than silently diverging.

**Fix:** note in the plan's "What's deliberately removed in v2" or in Task 13's docstring: "platform detection is hardcoded to claude in v1; post-MVP adds detection".

### I6. The Stop hook is a stub with no post-MVP spec anywhere — cross-platform transcript sweep is hand-waved

Task 16 makes the Stop hook a stub with a comment that post-MVP will add "cheap-model sweep of CLAUDE_TRANSCRIPT". The design doc (section "Hooks") makes transcript-sweep a core part of v2 ("Stop hook: If any captures remain: spawn final drain ingester. Optional transcript sweep."). The plan demotes it to post-MVP without explaining why or how.

If the design intent is that v1 ships WITHOUT transcript sweep, the plan should name that as a deliberate cut. If sweep is supposed to be in v1, Task 16 needs a real implementation: read `$CLAUDE_TRANSCRIPT`, spawn headless `claude -p` with a cheap-model flag and a "find missed captures" prompt, write any discovered captures to `.wiki-pending/`.

**Fix:** pick one. Either document the cut explicitly ("v1 ships without transcript sweep; Stop hook is stub") or add a real transcript-sweep task. Current plan is ambiguous.

### I7. RED test protocol uses subagents that "pretend they have no skill" — this is not equivalent to actual-no-skill baseline

Task 7 (lines 625–748) spawns subagents via Task tool with prompts like "Pretend you are a Claude Code session with NO skill loaded." Superpowers' actual RED testing runs real `claude -p` sessions in isolated `$HOME` with no skills installed (packaging study section 6.1, `tests/claude-code/` pattern: create isolated `$HOME`, no skills dir, run headless). A subagent "pretending" to have no skill has seen the skill's design in system context during its own agent run — the pretense is contaminated.

For this plan, the scope is smaller: we want to measure baseline rationalizations, not rigorously A/B-test. "Pretend no skill" is acceptable for a one-shot measurement. But the plan should call out this compromise explicitly rather than treating the subagent method as equivalent to isolated-session testing.

**Fix:** in Task 7 preamble, note: "This is a lightweight RED — a full isolated-session test would use headless `claude -p` with `--no-skills` flag or an isolated `$HOME`. The subagent pretend pattern is faster for MVP and sufficient to surface rationalization patterns."

### I8. GREEN phase (Task 23) is under-specified — just says "same process, with skill active"

Task 23 Step 2 says "For each GREEN scenario, spawn a fresh agent with the RED prompt's setup + the karpathy-wiki skill available in the session." That's it. No specific prompts, no acceptance criteria beyond "agent writes a capture + spawns ingester". No timeout, no "record exactly these 5 fields". Task 7 gave verbatim prompts for each RED scenario (hundreds of words); Task 23 gives a one-liner.

**Fix:** mirror Task 7's structure. For each GREEN scenario, give a verbatim subagent prompt, a verbatim expected-behavior specification, and a verbatim "record these exact fields" checklist. Without that, the executor will improvise and the GREEN test becomes non-comparable with RED.

### I9. REFACTOR loop (Task 24) has no concrete way to verify "no regression" across rounds

Lines 3538–3549:

> 5. Check that no previously-closed rationalization has re-opened.

How? The plan doesn't define the regression-check procedure. Re-running all scenarios each round is the honest answer (and is what superpowers does), but at 3 scenarios × 10 rounds × subagent-cost that's expensive. More concerning: "re-opened" is judgement-call — the plan doesn't say what that looks like or who decides.

**Fix:** add explicit round protocol: "After each REFACTOR patch, re-run Scenario N (the one that triggered the patch) AND Scenario 1 AND Scenario 3 to catch regressions. A regression is the agent using a rationalization it hadn't used in the previous two rounds."

### I10. Missing integration test for concurrent ingest — design doc calls this out as a risk

Design doc (line 92):
> Concurrent ingesters conflicting: two background ingesters might try to edit the same page. We use a lockfile...

Plan's file structure (line 95) lists `tests/integration/test-concurrent-ingest.sh` — but **no task creates this file**. Task 20 is the only integration test (single capture → single ingester). The plan never stress-tests the lock protocol with two parallel ingesters.

This is load-bearing: the entire two-level locking design (atomic claim + page lock) is the design doc's answer to a named risk, and the plan ships without verifying it. `test_acquire_fails_when_held` (Task 10) tests the lock primitive in isolation, but never in the realistic scenario of two ingesters racing on two captures that both want page X.

**Fix:** add a task (between Task 20 and Task 21) that writes `tests/integration/test-concurrent-ingest.sh` covering: two captures, both targeting `concepts/foo.md`, both spawned concurrently, assert final page content contains both insertions without corruption, assert exactly two `ingest:` log entries.

## Minor issues

### M1. Task 1 README placeholder is replaced in Task 27 — the initial content is throwaway. Fine, but annotate it.

### M2. Task 6 fixture wiki has inline Obsidian-compatible markdown links using relative paths (`[Jina Reader](concepts/jina-reader.md)`). Good — matches design. But the schema.md fixture says `## Role main` rather than a parseable frontmatter/role field. If tests later want to read the role programmatically, they can't.

### M3. Plan claims SKILL.md is "~450 lines" at the bottom (line 3378). In the plan, the SKILL.md content is ~220 lines. The "450" estimate is wrong either direction — it was an aspirational pre-draft guess. Replace with "~220 lines, under 500-line budget" before the skill file ships.

### M4. Task 22 Step 1 moves v1 skills to `~/skills-backup-$(date +%Y%m%d)/`. If the user re-runs the task on the same day, the dir already exists and the move silently collides. Use `-T` or check-and-rename.

### M5. Task 22 Step 3 asks the executor to "manually merge" settings into `~/.claude/settings.json`. This is user-dependent and easily skipped. Provide a small `jq`-based script that does the merge idempotently. The executor should not be doing JSON surgery by hand.

### M6. The self-review checklist (lines 3872–3888) is good but not a "test" — nothing programmatic verifies these. Consider a simple `tests/self-review.sh` that greps for each invariant.

### M7. Plan calls the skill directory `skills/karpathy-wiki/` (line 65). The packaging study argues for `skills/wiki/` (function-name, not lineage-name). Minor naming call; plan's choice is defensible (disambiguates from any user-authored `skills/wiki/` that might exist). Worth calling out the tradeoff explicitly.

### M8. `.gitignore` writes `.locks/` and `.ingest.log` inside `wiki-init.sh` output (Task 13), but the REPO-level `.gitignore` (Task 1) also writes these patterns. Harmless but redundant. Probably fine.

## Strengths

These are the things the plan does well — the executor should preserve them.

1. **Task slicing is near-optimal for subagent dispatch.** 28 tasks, each with 2-6 steps, each step 1-3 minutes. This is the sweet spot for subagent-driven execution.
2. **TDD discipline is cleanly encoded.** Every non-trivial task has "Write failing test → Run to see failure → Write implementation → Run to see pass → Commit" as explicit steps. Expected-output lines are given. This is rare in plans written for agents; treat it as a model.
3. **Function names are consistent across tasks.** `wiki_lock_acquire`, `wiki_capture_claim`, `wiki_config_get`, `wiki_root_from_cwd`, `wiki_capture_archive`, `wiki_capture_count_pending` all appear with the same signatures from their defining task through their later callers. No drift.
4. **Commits are scoped per-task, not per-phase.** `feat: wiki-lib.sh...`, `feat: page-level locks...`, `test: RED scenario 1...` — this matches conventional commits and makes bisecting easy.
5. **Phase exit criteria are explicit.** Each phase ends with "Exit criterion for Phase N: ..." — giving the executor a clear go/no-go without surfacing to user.
6. **Autonomy bounds are named.** The 3-clean-rounds / 10-round-budget / regression-surfacing conditions are stated in Task 24 and the execution footer. This matches the agreed autonomous testing policy.
7. **Hash manifest scoped to raw/ only (not wiki pages).** Task 12 gets this right — just raw files. Design intent preserved. `test_build_manifest_fresh` and `test_diff_detects_*` are surgical.
8. **Orientation protocol is called out in SKILL.md.** Schema → index → log. Matches Hermes's "CRITICAL" protocol (lightly renamed). Good steal.
9. **Stop hook and SessionStart hook both explicitly emit zero model-visible context.** Addresses the superpowers issue #1220 cost lesson at the implementation layer.
10. **AGENTS.md symlink present from Task 25.** Matches superpowers-packaging-study Section 2. Zero-cost for Claude Code today, opens door for Codex/OpenCode later.

## Dimension-by-dimension findings

### A. Completeness

Walking design doc section by section:

| Design section | Plan coverage | Gap |
|---|---|---|
| Wiki roles and topology | Task 13 (wiki-init.sh) | `~/.wiki-config` home-level record dropped silently (I4) |
| Auto-init | Task 13 + SKILL.md | `.wiki-config` adoption path (dir exists but no `.wiki-config`) is not implemented — the design doc says "adopt it — write `.wiki-config` based on ...". The wiki-init.sh creates only when missing, won't adopt. |
| Directory layout | Task 13 creates all dirs | `sources/`, `ideas/`, `practices/`, `snippets/` from design doc not created (plan creates only concepts/entities/sources/queries). Design is fuzzy here; plan's choice is defensible. |
| .wiki-config format | Task 13 | Plan uses TOML; design doc showed JSON examples. Plan rightly uses TOML because tomllib is stdlib; this is a deliberate improvement. Note this in the plan's Overview. |
| Captures format | Task 11 + SKILL.md | Consistent between plan and design. |
| Ingester mechanics | Task 14 (spawn) + SKILL.md (steps) | The ingester "steps" in SKILL.md Task 21 don't map cleanly onto a test. Design calls out "If evidence_type == conversation: use the capture body as seed material; re-consult the current session transcript if more context is needed." — SKILL.md mentions conversation-type but doesn't describe how to "re-consult the transcript" since a detached ingester has no access to the parent session's transcript. This is a spec hole. |
| Spawn mechanism (headless + fallback) | Task 14 | Fallback to "parallel subagent" is mentioned in design, not implemented in plan. That's OK for MVP. |
| Two-level locking | Task 10 (page lock) + Task 11 (capture claim) | Correct |
| Logs (log.md + .ingest.log) | Task 8 (log_info) + Task 13 | Correct |
| Hash manifest on raw/ only | Task 12 | Correct |
| SessionStart hook | Task 15 | hooks.json missing (C4), matcher not encoded (C5), local-keyword bug (C1) |
| Stop hook | Task 16 | Stubbed; transcript sweep deferred without explanation (I6) |
| Propagation (project → main) | SKILL.md only | No test covers propagation. No task creates a propagated capture. Design intent is preserved in SKILL.md prose, but execution is untested. Add at minimum a unit test that verifies: when a project-wiki ingester runs and capture is "general-interest", a new capture appears in `<main>/.wiki-pending/` with `origin` set. |
| Cross-wiki querying | SKILL.md only | Reasonable for MVP. |
| Three-tier lint | SKILL.md calls out Tier 1 | Tier 2 (opportunistic at SessionStart drain) not wired; Tier 3 (wiki doctor) is stubbed to "not implemented in MVP" (line 2989). Cross-tier consistency = design gets Tier 1 only in v1. Fine if called out. |
| User commands (doctor + status) | Task 18 (status) + Task 19 (dispatcher) | `wiki doctor` is stubbed with `exit 1` saying "not implemented". Matches design doc intent that doctor is post-MVP. |
| Natural-language triggering | SKILL.md | Description has trigger leak (I1) |
| Git integration | Task 17 (wiki-commit) + Task 13 (git init) | Correct |
| Obsidian compatibility always-on | Task 13 | Correct (writes `.obsidian/app.json`). No detection branching. Good. |
| Cross-platform support | Hardcoded | I5 |
| AGENTS.md symlink | Task 25 | Correct |

Gaps summary: three outright architectural gaps (C4 hooks.json, I4 home-level config, I5 platform detection), two test gaps (propagation test, concurrent-ingest test I10), one protocol gap (transcript sweep I6).

### B. TDD discipline

Strong overall. Every non-trivial script has a failing test written first:

- Task 8 (wiki-lib.sh): 3 tests written before script. Expected fail: "source: no such file" ✓
- Task 9 (wiki-config-read.py): 4 tests, script written second ✓
- Task 10 (locks): 4 tests, script written second ✓
- Task 11 (capture claim): 3 tests, fixture first, script second ✓
- Task 12 (manifest): 4 tests, script second ✓
- Task 13 (init): 5 tests, script second ✓
- Task 14 (spawn): 2 tests, script second ✓
- Task 15 (session-start): 3 tests, hook second ✓
- Task 17 (commit): 3 tests, script second ✓
- Task 18 (status): 2 tests, script second ✓

Task 16 (stop hook) is the exception — it's a stub with a smoke test rather than a failing-first test. Acceptable for a stub.

Every expected-output block is present and specific. Every "run test to see it fail" step has an explicit expected failure mode ("FAIL — script doesn't exist" or similar).

One weakness: Task 20 (end-to-end integration) has only one test case (`test_capture_drop_plus_hook_plus_spawn`). A real end-to-end would cover: (1) capture with bad YAML frontmatter, (2) concurrent captures, (3) capture for non-existent page, (4) capture with evidence file missing.

### C. Placeholder scan

Searched for `TBD`, `TODO`, `implement later`, `similar to Task N`, `add appropriate`, `handle edge cases`, `fill in details`, `placeholder`.

Hits:
- Line 176: "Write minimal README placeholder" — intentional, replaced in Task 27. OK.
- Line 2962: "wiki doctor — deep lint (post-MVP placeholder)" — documented scope cut. OK.
- Line 3231: "Temporary session state, current-task TODOs" — describes a non-wiki-worthy thing. OK (not a plan placeholder).
- Line 3327: "Post-MVP placeholder in v1" — describes doctor. OK.
- `TODO`: only in the context of "current-task TODOs" as a non-wiki-worthy item. No plan TODOs.

**Verdict:** no placeholder issues. Every code block is complete.

### D. Type and name consistency

Checked key names across tasks:

| Name | First defined | Used in |
|---|---|---|
| `wiki_lock_acquire` | Task 10 | Task 10, SKILL.md |
| `wiki_capture_claim` | Task 11 | Task 11, SKILL.md |
| `wiki_capture_archive` | Task 11 | Task 11 (no later caller — suspicious but not inconsistent) |
| `wiki_config_get` | Task 8 | Tasks 14, 15, 17, 18, 19 — all consistent |
| `wiki_root_from_cwd` | Task 8 | Tasks 15, 16, 19 — all consistent |
| `wiki_capture_count_pending` | Task 11 | Task 18 — consistent |
| `slugify` | Task 8 | Task 15 — consistent |
| `log_info` / `log_warn` / `log_error` | Task 8 | Tasks 10, 11, 14, 15, 16, 17 — all consistent |

Config file keys:

| Key | `wiki-init.sh` writes | SKILL.md references | Scripts read |
|---|---|---|---|
| `role` | ✓ | ✓ | Task 18 (`wiki_config_get "${wiki}" role`) ✓ |
| `platform.agent_cli` | ✓ | not referenced | Task 9 test (`wiki_config_get platform.agent_cli`) ✓ |
| `platform.headless_command` | ✓ | not referenced directly | Task 14 (`wiki_config_get platform.headless_command`) ✓ |
| `settings.auto_commit` | ✓ | not referenced | Task 17 (`wiki_config_get settings.auto_commit`) ✓ |
| `main` (project wiki) | ✓ | SKILL.md ingester step 9 | not read anywhere by scripts — only by SKILL.md prose |

File paths:

| Path | Consistent? |
|---|---|
| `/Users/lukaszmaj/dev/karpathy-wiki/` | ✓ (hardcoded dev location) |
| `~/.claude/skills/karpathy-wiki` | ✓ (symlink target) |
| `<wiki>/.wiki-pending/` | ✓ |
| `<wiki>/.locks/` | ✓ |
| `<wiki>/.manifest.json` | ✓ |
| `<wiki>/.ingest.log` | ✓ |
| `<wiki>/raw/` | ✓ |

**Verdict:** consistency is tight. No drift found.

### E. Task granularity

Each task has 2-6 steps, each step 1-3 minutes of work when happy-path. Some edge cases:

- Task 7 (RED execution) is ~8 steps, each step potentially 10-20 minutes (waiting for subagent return). This is fine — the subagent is doing the work, not the executor.
- Task 13 (wiki-init.sh) is dense — one script with 5 tests and a 100+-line implementation. Could be split into "13a: write tests" + "13b: write script + verify". Marginal.
- Task 15 (session-start) is the largest — 6 steps, including polyglot wrapper and integration test. Could be split but the cohesion is strong enough that splitting adds overhead.
- Task 21 (SKILL.md draft) is one step: "Write SKILL.md". For a 220-line markdown file this is fine.
- Task 23 (GREEN execution) is under-specified — see I8.
- Task 24 (REFACTOR loop) is inherently multi-round. The plan treats it as one task. Acceptable given explicit exit criteria.

**Verdict:** task granularity is appropriate. No splits needed. One task (Task 23) should be fleshed out (I8).

### F. SKILL.md quality (Task 21)

Against each requirement:

- **`description` = triggers only, no workflow summary:** partially (I1). The current description has strong triggers but misses query-shaped and phrasal ones. No workflow leak per se — it doesn't describe ingest/spawn/lock. ✓ on that front.
- **Iron law stated prominently:** weakly (I3). Prose rather than fenced block. Should be upgraded.
- **Closes rationalizations explicitly:** yes — the rationalizations table (lines 3344–3352) has 6 entries, which is good. Compare to superpowers TDD skill's 11-entry table. 6 is enough given v1 hasn't been pressure-tested. REFACTOR will grow this.
- **Under 500 lines:** yes — actually under 220 lines as written. The "~450 lines" claim in Task 21 is wrong (M3) but the budget is kept.
- **Cross-references flat (not nested):** yes — no `references/` subdirectory created; no file-to-file links inside SKILL.md.
- **Follows superpowers style:** mostly. Missing Announce (I2), iron-law formatting (I3), no Pairs-with / Integration section, no "Red Flags — STOP" header (it exists as "Rationalizations to resist" which is functionally equivalent but not style-consistent).
- **Numeric thresholds from Hermes:** yes — lines 3303–3307 include 2+ sources, 200+ lines, 5+ pages, 500+ pages. All four thresholds are from Hermes study section 4.2 and 4.3. ✓
- **Orientation protocol:** yes — lines 3178–3186. Stated as "orientation protocol". Matches Hermes study's CRITICAL protocol.
- **Rationalization table:** yes (but could be denser — see above).
- **Obsidian detection NOT present:** yes — no detection branching. Always-on .obsidian/app.json write in wiki-init.sh. ✓

**Verdict:** SKILL.md is ~75% there. Fixing I1 (description triggers), I2 (Announce), I3 (iron-law format) gets it to 95%. The REFACTOR loop (Task 24) is supposed to harden it further — so the current draft being incomplete is acceptable as a GREEN starting point.

### G. Autonomy bounds

Encoded clearly in two places:

- **Task 24 (REFACTOR loop):** lines 3546-3548:
  > **Success**: 3 consecutive rounds with zero new rationalizations.
  > **Budget hit**: 10 rounds consumed.
  > **Regression**: closing one loophole reopens another consistently → surface to user (out of autonomy).

- **Execution footer (line 3901):** "It matches the autonomous-testing bounds already agreed with the user (up to 10 rounds of RED/GREEN/REFACTOR, stop at convergence or regression)."

Phase exit criteria are stated per phase (lines 770, 3141, 3566, 3864). Each names a concrete observable condition.

Gaps:
- No explicit "surface to user" protocol for cases other than REFACTOR regression. What if a unit test fails repeatedly in Phase 2? The plan implicitly assumes happy-path.
- No "if this, ask" guidance for ambiguous subagent-execution prompts in RED (Task 7) or GREEN (Task 23).
- Budget for the whole plan (not just REFACTOR rounds) isn't given. If the plan takes 8 hours wall-clock, is that within bounds? No time budget is stated.

**Verdict:** autonomy bounds are named but shallow. Adequate for subagent-driven execution; would benefit from a "when to surface" section at the top.

### H. Risks not addressed

1. **macOS-specific `stat` format.** Task 10 uses `stat -f %m` (BSD) with fallback to `stat -c %Y` (GNU). Good. But Task 15's reclaim loop (line 2481) also does this inside `while read` — combined with the `local` bug (C1), this compounds.

2. **`set -e` inside hooks causes silent-abort.** `hooks/session-start` and `hooks/stop` both start with `set -e`. If any command in the script fails (e.g. stale-reclaim finds no matching files and `find` exits nonzero on macOS when no results, which it doesn't — but `mv` on stale file might), the whole hook aborts without finishing downstream work. Use `set -uo pipefail` without `-e` for hooks, or wrap failing commands with `|| true`.

3. **`${SKILL_DIR}` is referenced in SKILL.md but never defined anywhere.** Lines 3200, 3202, 3261, 3275, 3290 all use `${SKILL_DIR}` — but that's prose for the agent. In practice, when a headless ingester spawned by `wiki-spawn-ingester.sh` runs, there's no shell variable named `SKILL_DIR`. The agent reading the skill sees these paths and tries to execute them literally. Either the plan needs to resolve `SKILL_DIR` at skill-load time (via `CLAUDE_PLUGIN_ROOT`), or the SKILL.md prose should use absolute-path equivalents or stable relative paths from the wiki root.

4. **Python 3.11+ required but no version check anywhere.** `wiki-config-read.py` imports `tomllib`, which is 3.11+. If the user's system has Python 3.10 (plausible on macOS), the script fails at runtime. The plan doesn't test for this. Add a version check in `wiki-init.sh` or make `wiki-lib.sh`'s `wiki_config_get` fall back gracefully.

5. **No handling of bad TOML in `.wiki-config`.** If a user edits `.wiki-config` and writes malformed TOML, the script exits with "malformed TOML: ..." — but downstream scripts (`wiki-commit.sh`, `wiki-status.sh`) call `wiki_config_get` and use `|| echo "default"` fallback. The user's bad config is silently hidden. Surface it.

6. **`$CLAUDE_TRANSCRIPT` is referenced in Task 16 comment but may not be a real Claude Code env var.** The comment at line 2580 says "Claude Code sets this" — I can't verify without running Claude Code. If this env var doesn't exist or has a different name, the post-MVP transcript-sweep plan is based on a false assumption.

7. **The `disown` behavior varies by shell.** `disown` in bash works one way, in zsh slightly differently. If the user's login shell is zsh and bash is invoked as `#!/bin/bash` (as all scripts do), it should be fine. But if any script fires from a zsh-interactive parent with inherited settings, `disown` might misbehave. Low probability; worth noting.

8. **Hook invocation works differently when triggered by Claude Code than when invoked manually in tests.** Tests cd into the wiki dir and invoke the hook. Claude Code invokes the hook with `$CLAUDE_PLUGIN_ROOT` and `$PWD` set to the user's session cwd. The plan's tests don't exercise the $CLAUDE_PLUGIN_ROOT path — so any future hook that depends on that env var is untested.

9. **settings.json merge in Task 22 is fragile.** If the user has existing SessionStart or Stop entries in `~/.claude/settings.json`, the "add our entries" operation has no conflict resolution. Plan says "Merge this into existing... carefully" — that's not an executable instruction.

10. **No cleanup on partial-run failures.** If Task 14 (spawn) is executed and the ingester actually runs (because `echo` worked but the script then hung), there's no way to recover. Tests clean up with `teardown()` but in real use, `.processing` files can accumulate. The stale-reclaim logic handles this after 10 min — fine for production, painful during debugging.

## Recommended actions before execution

**Critical (must fix before starting):**
- [ ] Fix C1: remove `local` keyword from top-level script bodies in `hooks/session-start` drift and stale-reclaim loops (Task 15).
- [ ] Fix C2: replace `mv -n` in `wiki_capture_claim` with a truly-atomic rename (e.g. explicit `link + unlink`) and add a real concurrency test backgrounding two claim subshells (Task 11).
- [ ] Fix C3: change `wiki-config-read.py` to emit JSON for tables/lists or fail clearly, not `repr()` (Task 9).
- [ ] Fix C4: add a task that writes `hooks/hooks.json` (Claude Code plugin format, `matcher: "startup|clear|compact"`, `type: command`, pointing at `${CLAUDE_PLUGIN_ROOT}/hooks/run-hook.cmd` or at the extensionless hook script directly) BEFORE Task 25.
- [ ] Fix C5: encode the `matcher` narrowing in every location that wires hooks (plan and settings.json example).
- [ ] Fix C6: either remove `run-hook.cmd` polyglot wrapper for MVP or route `hooks/hooks.json` through it and fix the bash-tail `shift`/arg-passing.

**Important (should fix before starting):**
- [ ] Fix I1: rewrite SKILL.md `description` to include question-shaped triggers and phrasal triggers ("add to wiki", "remember this", "wiki it").
- [ ] Fix I2: add `**Announce at start:**` line to SKILL.md.
- [ ] Fix I3: wrap iron-law in triple-fenced block; consider splitting into two iron laws.
- [ ] Fix I4: add a note about `~/.wiki-config` and `$WIKI_MAIN` being deliberately dropped in v1.
- [ ] Fix I5: note the hardcoded `claude` CLI as a deliberate v1 simplification.
- [ ] Fix I6: pick a position on transcript-sweep — either implement it in Task 16 or document the cut explicitly.
- [ ] Fix I7: add the "subagent pretend" caveat to Task 7.
- [ ] Fix I8: flesh out Task 23 GREEN scenario prompts to mirror Task 7's specificity.
- [ ] Fix I9: add a concrete regression-check procedure to Task 24.
- [ ] Fix I10: add a concurrent-ingest integration test task between Task 20 and Task 21.

**Minor (nice-to-have):**
- [ ] M5: replace "manually merge settings.json" with a jq-based merge helper.
- [ ] M6: add a `tests/self-review.sh` that greps for self-review invariants.
- [ ] H2: change hook scripts from `set -e` to `set -uo pipefail`; add `|| true` to cleanup commands that may miss.
- [ ] H3: resolve `${SKILL_DIR}` → `${CLAUDE_PLUGIN_ROOT}/skills/karpathy-wiki` (or equivalent) where it appears in SKILL.md.
- [ ] H4: add a Python 3.11+ check to `wiki-init.sh` before writing `.wiki-config`.

**Post-execution (punch list):**
- [ ] Validate that Task 22 Step 4 smoke test actually works on a fresh session.
- [ ] Validate that `wiki status` finds wikis via ancestor walk (line 3844 hints at a bug).
- [ ] Document transcript-sweep post-MVP roadmap in RELEASE-NOTES.md.
- [ ] Add cost-tracking hooks (design doc mentions "total cost this month if tracked") — deferred.
