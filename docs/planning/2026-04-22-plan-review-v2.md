# Plan Review v2: karpathy-wiki-v2 Implementation Plan (post-fix)
Date: 2026-04-22
Reviewer: senior code reviewer (second pass)
Plan under review: `/Users/lukaszmaj/dev/bigbrain/plans/2026-04-22-karpathy-wiki-v2.md` (4,307 lines, 29 tasks, 4 phases)
Prior review: `/Users/lukaszmaj/dev/bigbrain/research/2026-04-22-plan-review.md`

## Summary
- **Overall verdict: approve** — ready for autonomous execution.
- Critical issues (remaining or new): 0
- Important issues (remaining or new): 0
- Minor issues (new, cosmetic): 3
- Fixes landed cleanly: 16 of 16

All 6 critical and all 10 important issues from the prior review have been addressed correctly. Three small cosmetic issues appeared in the delta (stale expected-output text from renamed tests, README markdown fence nesting, orphan file-tree entries for scripts that are never created). None block execution — an executing subagent will notice the mismatches when a test runs or a file is read and either silently self-correct or surface the discrepancy. The plan is in strong shape to ship.

---

## Fix-by-fix verification

### C1. `local` outside function — STATUS: landed
The session-start hook (Task 15, lines 2471-2587) now wraps every use of `local` inside named helper functions (`_drift_scan`, `_drain_pending`, `_reclaim_stale`), each called on its own line with a non-fatal `|| log_warn`. A grep for `local ` inside the Task 15 block confirms all occurrences are nested two levels deep (inside `_drift_scan() {...}` etc.), never at top level. Line 2503 has the explicit note: *"Wrapped in a function so we can use `local` for variables."* Evidence is at lines 2504 (`_drift_scan() {`), 2545 (`_drain_pending() {`), 2569 (`_reclaim_stale() {`).

### C2. `mv -n` atomicity — STATUS: landed
`wiki_capture_claim` (Task 11, lines 1553-1583) now uses the exclusive-hard-link pattern: `ln "${f}" "${claimed}"` followed by `unlink "${f}"`. The comment at 1559-1562 explicitly calls out *"This is stricter than `mv -n` which on macOS BSD silently no-ops on collision."* A new test `test_claim_is_atomic_concurrent` (lines 1487-1526) spawns 5 background subshells racing on one capture and asserts exactly one winner. This is a proper concurrency test, matching what C2 requested.

**Minor follow-on:** the Task 11 Step 5 expected-output block at line 1627 still says `PASS: test_claim_is_atomic` but the renamed tests emit `PASS: test_claim_is_atomic_sequential` and `PASS: test_claim_is_atomic_concurrent`. An executor running the test will see the output doesn't match the plan's expectation text, but the test itself will pass — so this is cosmetic. Flagged as M-new-1 below.

### C3. Python repr() — STATUS: landed
`wiki-config-read.py` (Task 9, lines 1104-1132) now emits `json.dumps(current)` for dicts/lists (line 1130). The comment at 1121-1123 is explicit: *"For tables/arrays emit JSON so callers can parse reliably (repr() produces Python-specific syntax)."* Scalar handling is preserved. Bool is emitted as `"true"`/`"false"` (correct — matches the test at Task 17 which greps `"auto_commit = true"` and later parses it as a string).

### C4. Missing `hooks/hooks.json` — STATUS: landed
New Task 16b (lines 2690-2748) creates `hooks/hooks.json` with both `SessionStart` and `Stop` entries pointing at `${CLAUDE_PLUGIN_ROOT}/hooks/session-start` and `.../stop`. JSON schema is validated via `python3 -c "... json.load(open(...))"` in Step 2. The matcher notes section (lines 2727-2730) explains why the narrowing and the `Stop` `.*` are both correct. The file is present in the file-tree list (line 87) so it's consistent with the overview.

### C5. Matcher narrowing — STATUS: landed
`hooks/hooks.json` at line 2704 contains `"matcher": "startup|clear|compact"`. The in-plan narrative at 2692 and 2728 connects this to superpowers issue #1220. The self-review invariant at 4224 greps for exactly that pattern. The self-review script at 4264 actually runs the grep.

### C6. Dead polyglot wrapper — STATUS: landed
`run-hook.cmd` is no longer written in Task 15. Line 2605 has the explicit cut: *"the superpowers-style polyglot `run-hook.cmd` (bash+cmd single-file) is deferred to post-MVP. v1 targets macOS/Linux only."* The self-review script at line 4281 has a check `[[ ! -e '${REPO}/hooks/run-hook.cmd' ]]` which will fail the build if anyone restores the file. The only remaining mentions of `run-hook.cmd` in the plan are (a) the reference to superpowers' copy at line 55 (source material, not ours), and (b) the two self-review lines enforcing absence. Clean.

### I1. SKILL.md description triggers — STATUS: landed
The description at line 3424 now includes:
- Question-shaped triggers: *"when the user asks 'what do we know about X', 'how do we handle Y', 'what did we decide about Z', 'have we seen this before'"*
- Phrasal triggers: *"when the user says 'add to wiki' / 'remember this' / 'wiki it' / 'save this'"*
- Plus the original object-trigger set (research subagent return, URL paste, `raw/` unprocessed files, etc.)

The description is longer than before (~800 chars vs 580 prior) but still reasonable for the LLM's trigger-detection context. The "Do NOT use" tail is preserved.

### I2. Announce at start — STATUS: landed
Line 3437: `**Announce at start:** "Using the karpathy-wiki skill to [capture this / ingest pending captures / answer from wiki]."` — exact style-guide phrasing, placed immediately after the one-line overview and before the Iron Laws. Correct position.

### I3. Iron law formatting — STATUS: landed
Lines 3439-3447 now show the iron law in triple-fenced blocks, *and* split into two:
```
NO WIKI WRITE IN THE FOREGROUND
```
```
NO PAGE EDIT WITHOUT READING THE PAGE FIRST
```
Matches style guide section 2 pattern exactly. The split into two iron laws is what the prior review's I3 note recommended.

### I4. `~/.wiki-config` cut note — STATUS: landed
Lines 21-34 contain a dedicated "Deliberate v1 scope cuts from the design doc" section. Line 25: *"`~/.wiki-config` home-level main-wiki pointer — dropped. Main wiki location is hardcoded to `$HOME/wiki/` in v1. No override mechanism."* Line 26: *"`$WIKI_MAIN` environment variable — dropped."* Both explicitly called out. The file tree's "Files that must NOT exist in v2" at line 131 reinforces with *"Any `~/.wiki-main` env export (config file is sole source of truth, no env var)."*

### I5. Hardcoded `claude` CLI — STATUS: landed
Line 27: *"Cross-platform `agent_cli` / `headless_command` detection — dropped. v1 hardcodes `claude` and `claude -p`. Post-MVP will add detection when we target Codex, OpenCode, Cursor, Hermes."* Clear and explicit.

### I6. Stop hook / transcript sweep — STATUS: landed
Line 28: *"Stop-hook transcript sweep — dropped. v1 ships Stop as a stub that only logs session-end. Transcript sweep was a backstop for captures the in-session agent missed; we rely on in-session capture alone for v1. Post-MVP adds the cheap-model sweep."* Task 16 itself at lines 2632-2653 is consistent with this cut, and the script's comments (2633-2637) even note that `$CLAUDE_TRANSCRIPT` may vary by version and recommend resolving it empirically when implementing.

### I7. RED subagent-pretend caveat — STATUS: landed
Task 7 preamble (lines 643-645): *"Methodology caveat: this is a lightweight RED using Task-tool subagents that 'pretend to have no skill loaded.' It is not fully equivalent to a rigorous isolated-session test... The subagent pretense is contaminated — the subagent has seen its own system prompt, but has NOT seen the karpathy-wiki skill content. For v1, this compromise is acceptable..."* Exactly what prior review asked for.

### I8. GREEN scenario specificity — STATUS: landed
Task 23 (lines 3730-3873) now gives each GREEN scenario a verbatim subagent prompt with 7-field expected-compliance checklist, mirroring Task 7's structure. Each scenario ends with an **Expected compliance** block that lists field-by-field what a correctly-functioning skill produces (e.g. line 3775-3782 for scenario 1). Step 5 (3845-3861) defines the result-capture table format.

### I9. REFACTOR regression check — STATUS: landed
Task 24 now has a dedicated **Regression-check procedure (per round)** section at 3889-3902 with a concrete 3-step protocol: (1) rerun the triggering scenario, (2) always rerun Scenario 1, (3) rerun a rotating random other from {2,3}. Termination rules at 3904-3909 explicitly separate success / budget-hit / regression. The "regression" definition at 3897 — *"the agent uses, in this round, a rationalization that was explicitly countered in any prior round's SKILL.md patch"* — is observable and testable, not a judgement call.

### I10. Concurrent-ingest test — STATUS: landed
New Task 20b (lines 3265-3406) creates `tests/integration/test-concurrent-ingest.sh`. The test sets up two captures targeting the same shared page, spawns two parallel fake ingesters (claim→lock→append→release→archive), and asserts: (a) both content entries present in the shared page, (b) both captures archived, (c) zero stale locks remaining. This fully exercises the two-level lock protocol end-to-end. The "if FAIL" diagnostic at 3395-3397 is a nice touch — tells the executor what to investigate.

### H2. `set -e` → `set -uo pipefail` in hooks — STATUS: landed
- `hooks/session-start` line 2487: `set -uo pipefail`, with explicit comment at 2485-2486 explaining why not `-e`.
- `hooks/stop` line 2639: `set -uo pipefail  # not -e — stop must never abort with a partial log`.
- All three drift/drain/reclaim calls end with `|| log_warn` (best-effort wrappers) at 2540, 2563, 2582.

### H3. `${SKILL_DIR}` → `${CLAUDE_PLUGIN_ROOT}` — STATUS: landed
Zero occurrences of `${SKILL_DIR}` or `SKILL_DIR` remain in SKILL.md (Task 21, lines 3419-3652). All script invocations use `${CLAUDE_PLUGIN_ROOT}/scripts/...` and `${CLAUDE_PLUGIN_ROOT}/hooks/...`. Line 3469 has the expository sentence *"script paths below resolve via `$CLAUDE_PLUGIN_ROOT`, which Claude Code sets to the plugin's root directory"*. The self-review script at line 4273 enforces this with a `! grep -q 'SKILL_DIR' ...` check.

### H4. Python 3.11+ version check — STATUS: landed
Lines 2023-2031 in `wiki-init.sh`:
```bash
if ! command -v python3 >/dev/null 2>&1; then
  echo >&2 "ERROR: python3 not found on PATH; karpathy-wiki requires Python 3.11+"
  exit 1
fi
if ! python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)'; then
  echo >&2 "ERROR: Python 3.11+ required (tomllib is stdlib from 3.11). Detected: $(python3 --version 2>&1)"
  exit 1
fi
```
Clean fail-fast with both `python3 not found` and `python3 < 3.11` cases handled. Additionally, `wiki-config-read.py` at lines 1098-1102 has a defense-in-depth ImportError fallback.

### M4. Backup dir uniqueness — STATUS: landed
Task 22 Step 1 (line 3676): `BACKUP_DIR="$HOME/skills-backup-$(date +%Y%m%d-%H%M%S)"` — seconds-resolution timestamp, so two runs on the same day (even the same minute, if more than 1 second apart) cannot collide.

### M5. Plugin symlink instead of settings.json merge — STATUS: landed
Task 22 Step 3 (lines 3695-3707) replaces the old "manually merge settings.json" instruction with `ln -s /Users/lukaszmaj/dev/karpathy-wiki ~/.claude/plugins/karpathy-wiki`. The explanatory paragraph at 3707 is explicit: *"The plugin's `hooks/hooks.json` is the canonical hook manifest. Editing `settings.json` would duplicate the wiring and risk drift."* Task 27's README install block (lines 4099-4104) uses the same approach with the same symlink chain. Consistent across the plan.

### M6. `tests/self-review.sh` — STATUS: landed
Lines 4239-4288 define the script. It runs 8 mechanical invariant checks: SKILL.md length, `hooks.json` SessionStart matcher, `hooks.json` Stop section, absence of `WIKI_MAIN`, absence of `SKILL_DIR`, `AGENTS.md` is a symlink, `.gitattributes` LF, `run-hook.cmd` absent, and executable bits on scripts. Exits nonzero on any FAIL. Matches every major invariant called out in the self-review checklist (4217-4235).

### M7. `skills/karpathy-wiki/` naming tradeoff — STATUS: landed
File tree at lines 79-84 has a 5-line explanation of why `karpathy-wiki/` (not `wiki/`) is the deliberate choice for v1: *"Named after the project brand (the `toolboxmd/karpathy-wiki` repo already has 63 stars under that name). Trade-off: a more generic name like `wiki` would be a shorter invocation target but would collide with any user-authored `skills/wiki/`. The branded name is the deliberate choice for v1."*

---

## New issues (minor, cosmetic)

Three small regressions introduced by the fixes themselves. None block execution.

### M-new-1. Stale expected-output in Task 11 Step 5
Line 1627 says `PASS: test_claim_is_atomic`. After the rename to `test_claim_is_atomic_sequential` + addition of `test_claim_is_atomic_concurrent`, the expected output should read:
```
PASS: test_claim_succeeds (claimed: ...)
PASS: test_claim_returns_empty_when_no_pending
PASS: test_claim_is_atomic_sequential
PASS: test_claim_is_atomic_concurrent
ALL PASS
```
Impact: low. An executing subagent will see the test pass with 4 lines and the expected-output text show 3. It'll notice the mismatch and either self-correct silently or flag it. Fix by updating the expected-output block.

### M-new-2. Task 27 README has an unclosed nested code fence
Inside the outer triple-fence-markdown block (lines 4081-4126) that contains the README content, line 4107 is a stray closing ` ``` ` with no matching opener. The sequence is:
- 4099 opens a `bash` fence
- 4104 closes it
- 4106 plain text
- **4107 orphan closing fence**
- 4109 plain text (`## How it works`)

When the executor types this into the actual README file, it will produce a literal ` ``` ` line rendered in the middle of the README. Impact: the README will render oddly between "That's it..." and "How it works" with an orphan code-fence line. Fix: delete line 4107.

### M-new-3. File tree lists 3 scripts and 1 test that no task creates
Lines 93, 94, 95, 115 of the file tree list:
- `scripts/wiki-drift-check.sh` (no task creates)
- `scripts/wiki-drain-pending.sh` (no task creates)
- `scripts/wiki-doctor.sh` (no task creates; Task 19 dispatcher has `doctor` subcommand exit 1 instead)
- `tests/integration/test-doctor.sh` (no task creates)

The session-start hook inlines drift + drain logic; there are no separate scripts for those. The doctor is deferred and explicitly stubbed in the dispatcher. Impact: minor — a careful executor will notice the file tree doesn't match the tasks. Fix: either remove from the file tree, or add an explanatory note like "aspirational; post-MVP extraction from hooks". This isn't a new issue from the fixes — it pre-existed — but since the fixes grew the plan by 400 lines without adjusting the file tree, it's worth flagging.

---

## Regressions (no functional regressions found)

I specifically checked the items the review task asked about:

### Cross-references: Task 22 plugin symlink vs Task 25 plugin.json
**No inconsistency.** Task 25's `plugin.json` (lines 3943-3951) is minimal metadata. Task 22 symlinks the whole repo to `~/.claude/plugins/karpathy-wiki`. Claude Code plugin discovery expects `.claude-plugin/plugin.json` at the plugin root and auto-reads `hooks/hooks.json` from the plugin root. The symlinked repo has both (`.claude-plugin/plugin.json` and `hooks/hooks.json`) at the root, so plugin.json discovery works correctly with the new install method.

### README install vs Task 22 approach
**Consistent.** Both use the 3-symlink pattern (repo→`~/.claude/plugins/karpathy-wiki`, skills subdir→`~/.claude/skills/karpathy-wiki`, `bin/wiki`→PATH). Both explicitly tell the user NOT to touch `settings.json`. The README has the orphan fence issue (M-new-2) but the install instructions themselves are correct.

### Self-review checklist vs new structure
**Consistent.** The self-review checklist at lines 4217-4235 matches the current structure exactly:
- `hooks/hooks.json` exists check → line 4224
- `run-hook.cmd` absent check → line 4235
- No `SKILL_DIR` → line 4232
- `~/.claude/plugins/karpathy-wiki` symlink → line 4223
- `~/.claude/skills/karpathy-wiki` symlink → line 4222
- `AGENTS.md` symlink → line 4230
- Stop hook is a stub → line 4234

All invariants are aligned with the refactored plan.

### Function-name consistency after the `ln`+`unlink` change
**Consistent.** The new `wiki_capture_claim` implementation (lines 1553-1583) preserves its public signature: input `<wiki_root>`, output `<path-to-.processing-file>` on stdout or exit 1 on no pending. Every caller I checked uses this same interface:
- Task 15 session-start: calls via spawn-ingester, which itself doesn't call claim directly (the ingester does)
- Task 20b concurrent-ingest `fake_ingester`: line 3321 uses `wiki_capture_claim "${wiki}"` with the correct signature
- Task 11 tests: all three tests call `wiki_capture_claim "${WIKI}"`
- SKILL.md ingester step 1 (line 3548): correct signature

The internal rename from `mv -n` to `ln`+`unlink` is hidden inside the function. No caller breaks.

### Hook script best-effort wrappers
**Consistent.** The three `_drift_scan`, `_drain_pending`, `_reclaim_stale` functions in the session-start hook each return 0 on normal completion and rely on the outer `|| log_warn "... (non-fatal)"` to absorb failures. This matches the stated H2 intent. Verified: lines 2540, 2563, 2582 have explicit `|| log_warn` wrappers.

---

## Recommendation

**Approve.** Ship it. All 6 critical issues and all 10 important issues have been addressed correctly. The plan now has:

1. Bash bugs that would have aborted hooks silently: fixed (C1 via function-wrapping).
2. A real concurrency test for atomic claim: added (C2 test_claim_is_atomic_concurrent).
3. A JSON-clean config reader: fixed (C3 json.dumps).
4. The missing `hooks/hooks.json` file: added (C4 Task 16b).
5. The `matcher` narrowing encoded: in hooks.json directly (C5).
6. Dead polyglot wrapper removed and fenced off by self-review (C6).
7. A SKILL.md that has question-shaped triggers, phrasal triggers, an Announce line, triple-fenced iron laws, and all known scope cuts documented (I1-I6).
8. Proper test specificity for GREEN/REFACTOR (I7-I9).
9. A concurrent-ingest integration test (I10).
10. Proper `set -uo pipefail` discipline in hooks with best-effort wrappers (H2).
11. No `${SKILL_DIR}` references left (H3).
12. Python 3.11+ fail-fast check (H4).
13. Cleanly-symlinked plugin install (M5) with executable self-review (M6).

The only remaining issues (M-new-1, M-new-2, M-new-3) are cosmetic and will not cause execution failures. An executing subagent will notice them when running a test or reading the README and either self-correct or surface them.

**Direct answer: Yes, this plan is ready for autonomous execution.** The 400-line growth from the first review all went into real hardening, not padding. The RED/GREEN/REFACTOR discipline is intact. The autonomy bounds (10 rounds max, surface on consistent regression) are explicit. Consistency across tasks is tight.

If you want to spot-fix the three cosmetic M-new items before dispatch, they take under 5 minutes. If you don't, the plan will still execute cleanly and the items will surface organically during the run.
