# Test Strategy Rightsizing - Read-Only Portfolio Audit

**Status:** Phase 1 audit complete. Recommendation only. No test, runtime, skill, or contributor-policy change is applied by this document.
**Date:** 2026-08-12
**Audited commit:** `9bffbc08734fa6728c5087bdc5084e05ba65b47f`
**Branch:** `main`, equal to `origin/main` before this report was created
**Required handoff:** `docs/planning/2026-08-12-test-strategy-rightsizing-handoff.md`

## Executive recommendation

Keep strict RED-GREEN-REFACTOR for bug fixes and non-trivial deterministic behavior, especially capture durability, concurrency, lifecycle, provider invocation, migration, and validation. Stop treating that discipline as a universal requirement for editorial changes, thin wrappers, documentation-only work, and every local edit.

Adopt the proposed four-tier verification model. The default inner loop should select the affected subsystem and complete in under 20 seconds. Keep the complete deterministic suite as a final integration gate, not as an edit-by-edit gate. Move real provider, real session, real scheduler, and semantic model qualification outside the default deterministic suite.

Do not mass-delete coverage. Consolidate related shell files into contract suites while preserving named assertions and failure localization. One current test is a supported removal candidate: `test-skill-split-no-overlap.sh`. It detects an arbitrary 80-word overlap, not behavior, and a prior adversarial review already recorded that it can pass while the skills are semantically broken. Its meaningful single-source assertions survive in the loader, capture, and ingest contract checks.

For Codex, package the project as a Codex plugin rather than installing only copies under `~/.agents/skills`. Standalone skills give Codex the instructions, but not the lifecycle hook distribution the project depends on. A plugin can bundle both skills and `SessionStart` hooks. Keep a standalone or symlinked skill install only as a development fallback, and do not enable both copies at once because Codex does not merge duplicate skill names.

## Audit method and current evidence

The audit:

1. verified the branch, status, and exact commit before writing this report;
2. enumerated all scripts discovered by `tests/run-all.sh`;
3. read every test body and the runtime or skill surface it exercises;
4. traced explicit bug reports, RED comments, and introducing commits;
5. ran every discovered script separately under `/usr/bin/time -p` with output isolated under `/tmp`;
6. compared the repository policy with the current Superpowers methodology and current official Codex documentation.

Fresh results at `9bffbc0`:

| Measure | Result |
|---|---:|
| Unit scripts | 76 |
| Integration scripts | 14 |
| Scripts run | 90 |
| Passing | 90 |
| Failing | 0 |
| Sum of isolated per-script wall times | 79.36 s |
| Unit time | 49.78 s |
| Integration time | 29.58 s |
| Unit and integration test lines | 9,238 |
| Runtime lines in `scripts/`, `bin/`, and `hooks/` | 8,289 |
| Test/runtime line ratio | 1.11 |

The measured sum is not a new post-rightsizing benchmark. It is the current portfolio cost when each script is run once in isolation. `/usr/bin/time -p` has 0.01-second display precision on this machine.

The dispatcher commit `877e659` changed 59 files under `tests/` and added 3,810 test/acceptance lines. It changed 18 runtime files under `scripts/`, `bin/`, and `hooks/` and added 3,714 runtime lines. That is evidence of navigation and maintenance cost, not evidence that the dispatcher contracts are unnecessary.

Eleven current scripts contain an explicit RED, bug, or regression narrative in their body. Other tests have credible implementation-risk evidence even when they were added with the feature rather than in a separately visible RED commit. The most consequential earlier regressions were evidence-path loss, cross-project routing leakage, raw recovery duplication, validator bypass, incorrect status counts, and invalid Claude hook output. These are not speculative.

## Runtime concentration

| Test | Time | Main cost observed |
|---|---:|---|
| `integration/test-end-to-end-plumbing.sh` | 8.00 s | Three fixed one-second sleeps plus detached hook/worker cleanup |
| `unit/test-mtime-defer.sh` | 6.32 s | Deliberate six-second sleep to cross a five-second boundary |
| `unit/test-status.sh` | 5.07 s | Eleven isolated wiki fixtures and repeated command startup |
| `integration/test-session-start.sh` | 4.77 s | Repeated setup plus detached tick completion/cleanup |
| `integration/test-concurrent-ingest.sh` | 2.59 s | Real process concurrency and lock exercises |
| `unit/test-capture-evidence-path.sh` | 2.51 s | Two one-second sleeps used only for filename separation |
| `integration/test-provider-fallback.sh` | 2.16 s | Multi-worker fallback and cooldown lifecycle |

Most scripts are cheap. Sixty-four of the 90 scripts completed in under one second. The largest immediate gain therefore comes from change-aware selection, removing fixed sleeps, and eliminating nested reruns, not from weakening high-risk assertions.

## Portfolio recommendations

Costs below are fresh sums for the listed scripts. `Lines` is current shell test code. A recommendation of `Merge` means preserve the meaningful assertions inside a smaller subsystem suite with named test functions and per-contract failure messages.

| Test or coherent group | Contract protected | Evidence | Risk | Unique coverage | Overlap | Cost | Recommendation | Confidence |
|---|---|---|---|---|---|---|---|---|
| Capture queue: `test-capture-atomic-publish.sh`, `test-capture.sh`, `test-archive-strips-processing.sh` | Complete atomic publication, one winning claim, clean archive name | Concurrency/data-loss risk; archive regression Finding 03 | Critical | Concurrent same-title publication and one-winner claim | Archive state also appears in completion and worker tests | 3 scripts, 208 lines, 0.68 s | Keep | High |
| Capture CLI: `test-capture-evidence-path.sh`, `test-capture-headless-unconfigured-cwd-aborts.sh`, `test-wiki-capture-cli.sh`, `test-wiki-capture-silent-bootstrap.sh` | Evidence provenance, no silent misrouting, orphan preservation, safe bootstrap | Explicit field bugs and RED commits `c52b467`, `c458e14`, `5cf5db8` | Critical | Canonical evidence path and lossless abort behavior | Shared CLI/bootstrap setup and routing branches | 4 scripts, 394 lines, 4.00 s | Merge into two CLI contract suites | High |
| Source scan and recovery: `test-inbox-drift-scan.sh`, `test-mtime-defer.sh`, `test-raw-recovery-no-duplicate-captures.sh`, `test-raw-recovery.sh`, `test-raw-staging-no-race.sh` | No partial-file ingest, no duplicate recovery, durable raw/inbox handoff | Real race found by review; RED commit `90c798e`; partial-write risk | Critical | Lock-window ordering, staging exclusion, collision handling | Repeated init, backdating, and scanner setup | 5 scripts, 363 lines, 9.29 s | Merge into scan and recovery suites; replace wall-clock sleep with a deterministic time boundary | High |
| Lock and concurrent ingest: `test-locks.sh`, `test-wiki-manifest-lock.sh`, `integration/test-concurrent-ingest.sh` | Page/manifest serialization, stale reclaim, no data loss or deadlock | Direct concurrency implementation risk | Critical | Shared-page ingest and ancestor lock ordering | Some capture claim and index assertions exist elsewhere | 3 scripts, 303 lines, 3.08 s | Keep | High |
| Initialization: `test-init.sh`, `test-init-creates-schema-proposals-dir.sh`, `test-wiki-init-main.sh`, `test-wiki-init-rerun-idempotent.sh`, `test-wiki-init-standalone-project.sh` | Complete non-destructive setup, role identity, pointer behavior | Schema-proposal omission had RED `1a30004`; rerun clobber risk | High | Python guard, pointer selection, user-content preservation | Structure and idempotence repeated across five fixtures | 5 scripts, 304 lines, 4.81 s | Merge into main/project initialization suites | High |
| Resolution and routing: `test-lib.sh`, `test-resolver-no-cross-project-leak.sh`, `test-resolver-walks-up.sh`, `test-wiki-resolve.sh`, `test-wiki-use.sh`, `integration/test-leg2-end-to-end.sh` | Correct project/main/both target with no cross-project leak | Two explicit bugs in commit pair `50acfa8`/`f9929eb` | Critical | Fifteen-state exit matrix and real capture routing | The two focused regression files are cases of the larger resolver matrix; Leg 2 repeats `wiki use` paths | 6 scripts, 546 lines, 4.22 s | Merge focused regressions into resolver matrix; retain one routing integration suite | High |
| Manual ingest: `test-wiki-ingest-now.sh`, `integration/test-leg3-end-to-end.sh` | Explicit and cwd-resolved scan, raw evidence path, subagent-report handoff | User-facing CLI contract; fabricated-wrapper RED scenario | High | Subagent report remains a file reference instead of rewritten prose | Both test explicit scan and drift capture creation | 2 scripts, 187 lines, 2.78 s | Merge into one ingest-now integration suite | High |
| Manifest: `test-manifest.sh`, `test-manifest-validate.sh` | Hash integrity, drift, origin, references, manifest migration | Source attribution and idempotence are durability requirements | High | SHA-256 and invalid-origin validation | Same implementation and fixture lifecycle | 2 scripts, 281 lines, 0.60 s | Keep coverage, merge file | High |
| Page validation and YAML: `test-validate-page.sh`, `test-validate-code-block-skip.sh`, `test-validate-deleted-categories.sh`, `test-yaml-helper.sh` | Prevent invalid pages while accepting valid links/frontmatter | URL parser and code-span regressions; validator gates completion | High | Parser oracle, bad-type matrix, code-span exceptions | Three validator files share parser fixtures | 4 scripts, 524 lines, 1.71 s | Merge validator cases; keep YAML helper separate | High |
| Migrations and frontmatter: `test-backfill-quality.sh`, `test-fix-frontmatter.sh`, `test-normalize-frontmatter.sh`, `test-relink.sh`, `test-reserved-set-update.sh`, `test-migrate-v2-hardening.sh`, `test-migrate-v2.2.sh`, `test-migrate-v2.3.sh` | Atomic, backed-up, idempotent migration without body loss | Existing-wiki corruption risk; rollback and dry-run requirements | Critical | Version-specific upgrade paths and rollback | Shared parsing assertions, but different shipped migration entrypoints | 8 scripts, 1,109 lines, 4.30 s | Keep, run in migration/release tier | High |
| Discovery and indexes: `test-build-index.sh`, `test-discover.sh`, `test-index-threshold-fires.sh`, `test-lint-tags.sh` | Correct content inventory, indexes, depth, tag and schema signals | Retrieval/navigation quality and prior v2.3 changes | Medium | Recursive index and threshold/debounce behavior | Discovery output is consumed by multiple scripts | 4 scripts, 520 lines, 2.31 s | Keep | Medium |
| Status: `test-status.sh`, `test-status-last-ingest.sh`, `test-status-filters-content-set.sh`, `test-wiki-status-issues.sh` | Accurate operator health output | Incorrect count had RED `677614d`; stale test-clock incident in dispatcher baseline | Medium | Manifest last-ingest source and exact content-set filtering | All are `wiki-status.sh` fixtures; issue summary also appears in Leg 4 | 4 scripts, 501 lines, 6.91 s | Merge into one status contract suite with named cases | High |
| Issues: `test-wiki-issue-log.sh`, `test-wiki-issues-render.sh`, `integration/test-leg4-end-to-end.sh` | Valid concurrent JSONL issue log and readable grouping | Ingest review workflow; concurrency corruption risk | Medium | Enum/size escaping and renderer corrupt-line resilience | Leg 4 repeats concurrent append, render, and status checks | 3 scripts, 230 lines, 1.87 s | Merge public CLI checks into the two focused suites; retire redundant Leg 4 body | High |
| Commit and deterministic completion: `test-commit-blocks-on-validator-fail.sh`, `test-commit.sh`, `test-complete-ingest.sh` | Validate before commit, rollback after archive failure, one durable success | Explicit validator-bypass bug plus dispatcher lifecycle | Critical | Recoverable post-archive failure and completion idempotence | Worker lifecycle verifies the wrapper outcome from outside | 3 scripts, 223 lines, 1.49 s | Keep | High |
| Runtime configuration: `test-config-read.sh`, `test-runtime-config.sh`, `test-runtime-config-migrate.sh` | Structured, scoped, atomic configuration and migration | Provider/model safety and local path leakage risk | High | Transaction restore, exact profile identity, scope isolation | Some status and scheduler assertions consume the same config | 3 scripts, 594 lines, 2.26 s | Keep | High |
| Dispatcher core: `test-dispatch-scan-routing.sh`, `test-dispatcher-slots.sh`, `test-ingest-run-events.sh`, `test-no-direct-spawn-path.sh`, `test-worker-heartbeat.sh`, `test-worker-reconciliation.sh` | Bounded slots, source ownership, durable run history, stale recovery | Direct implementation risk from 1,218-line orchestrator | Critical | Atomic slot limits, live-vs-dead reconciliation, one launch path | Integration concurrency and lifecycle test the same subsystem at a higher boundary | 6 scripts, 530 lines, 2.43 s | Keep | High |
| Provider and worker lifecycle: `test-provider-adapters.sh`, `test-provider-classification.sh`, `test-usage-monitor.sh`, `integration/test-provider-fallback.sh`, `integration/test-provider-worker.sh`, `integration/test-worker-lifecycle.sh` | Exact argv/model/effort, redaction, bounded retry/fallback, process cleanup | Real Spark run exposed inherited-config defect; security and retry-storm risk | Critical | Shell boundary safety, error-channel classification, process-group termination, `needs_more_detail` deferral | Some fallback state appears in status tests | 6 scripts, 777 lines, 5.64 s | Keep | High |
| Dispatcher concurrency: `integration/test-dispatcher-concurrency.sh`, `integration/test-dispatcher-refill.sh` | Global ceiling under concurrent ticks and bounded refill | Central dispatcher guarantee | Critical | Ten-tick race and multi-wave refill | Slot unit tests cover single-tick arithmetic only | 2 scripts, 174 lines, 0.99 s | Keep | High |
| Scheduler: `test-scheduler-plist.sh`, `integration/test-scheduler-lifecycle.sh` | Path-safe plist and transactional install/reinstall/uninstall | Real LaunchAgent acceptance exists; wrong target can persist processes | High | Failure rollback and exact-wiki uninstall | Plist shape is embedded in lifecycle, but the pure builder test localizes it | 2 scripts, 213 lines, 1.71 s | Keep deterministic tests; real LaunchAgent stays acceptance-only | High |
| SessionStart and plumbing: `test-session-start-claude-code-hookeventname.sh`, `test-session-start-loader-injection.sh`, `integration/test-session-start.sh`, `integration/test-end-to-end-plumbing.sh` | Valid hook output, no nested fan-out, correct mode isolation, source capture | Clean-session schema failure and prior fork-bomb/drift regressions | Critical | Harness JSON shape, scheduled loader-only behavior, no nested dispatch | Loader/guard cases repeat; plumbing repeats scanner cases and uses three fixed sleeps | 4 scripts, 509 lines, 16.10 s | Merge into hook contract and hook lifecycle suites; move scanner regressions to scanner suite | High |
| Skill mechanical structure: `test-capture-skill.sh`, `test-ingest-skill.sh`, `test-using-karpathy-wiki-loader.sh` | Files/frontmatter/references and explicit single-source boundaries exist | Packaging and progressive-disclosure mechanics | Medium | Missing files, required pointers, loader size/placement basics | Many phrase checks can share one parser/fixture | 3 scripts, 127 lines, 0.08 s | Merge into one mechanical skill-contract suite | High |
| Skill semantic grep checks: `test-deep-orientation-cold-start.sh`, `test-ingest-runs-record.sh`, `test-ingest-skill-provider-neutral.sh`, `test-loader-has-capture-resist-table.sh`, `test-session-start-payload-budget.sh` | Intended orientation, lifecycle ownership, provider neutrality, capture resistance, context budget | Some rules came from observed agent failures; current checks only prove words exist | High for behavior, low for exact wording | Payload ceiling and banned legacy/provider phrases are mechanically unique | Exact phrases overlap the structural tests and do not prove agent compliance | 5 scripts, 154 lines, 0.10 s | Merge mechanical invariants; use focused opt-in pressure scenarios only when semantic behavior changes | Medium |
| `test-skill-split-no-overlap.sh` | No arbitrary 80-word duplicate window | Speculative heuristic; prior review says it can pass with semantic breakage | Low | None with a meaningful user failure story | Explicit single-source checks survive in capture, ingest, and loader contract tests | 1 script, 48 lines, 0.03 s | Remove after approval | High |
| `integration/test-leg1-end-to-end.sh` | Four-skill layout and hook source ordering | Historical migration leg | Medium | Hook source-order assertion | Directly reruns five other test scripts; no real harness | 1 script, 58 lines, 1.97 s | Merge order assertion into hook contract; remove nested smoke reruns | High |
| `integration/test-codex-spark-ingest.sh` | Real Codex adapter and semantic ingest through dispatcher | Three real runs found inherited-config and UTC defects | High | Actual provider, duplicate no-op, augmentation, attribution and no nested delegation | Deterministic adapter/lifecycle tests cover non-provider mechanics | 1 script, 361 lines, 0.00 s when skipped; recorded real cases totaled 339.43 s | Demote to acceptance location and run only on Codex adapter/semantic changes or release | High |

## What stays non-negotiable

The audit found no basis to weaken these contracts:

- atomic capture publication and one-winner claiming;
- no data loss on any abort, recovery, archive, or commit failure;
- global and per-profile concurrency ceilings;
- no duplicate live worker after stale reconciliation;
- one durable terminal outcome per run;
- validator-before-archive/commit and rollback after post-archive failure;
- bounded retry, cooldown, immediate fallback, and no hot loop for `needs_more_detail`;
- provider process-group termination after orchestration failure;
- exact provider/model/effort attribution and argv boundaries;
- secret redaction in retained diagnostics;
- atomic, backed-up, dry-runnable configuration migration;
- SessionStart/scheduled mutual exclusion;
- scheduler install/run/uninstall targeting;
- source hash, manifest integrity, provenance, and exact-duplicate idempotence.

These are the parts where a failure can be silent, destructive, security-sensitive, or expensive to reconstruct later. The user's ability to notice ordinary workflow defects does not reliably detect a capture that never existed, a provenance path that was silently replaced, or two workers that overwrote the same page.

## Proposed verification matrix

Measured times are derived from the current groups, before any consolidation optimization.

| Change surface | Inner loop | Current measured selection | Final gate |
|---|---|---:|---|
| Documentation, links, examples, comments | Markdown/link/static check only | Under 1 s expected | No runtime suite unless the document defines executable behavior |
| Behavior-preserving `SKILL.md` wording | Mechanical skill contract | 0.21 s for all current skill static scripts | No pressure scenario |
| Skill trigger, decision, sequence, capture threshold, orientation, attribution, or synthesis change | Focused failing pressure scenario plus mechanical contract | Model-dependent, opt-in | Rerun the same scenario after change; clean harness only when loader/hook is involved |
| Capture and scanner | Capture queue + CLI + source scan | 13.97 s | Relevant routing/hook integration, then full suite at merge |
| Dispatcher/provider/completion | Dispatcher core + concurrency + provider + completion | 10.55 s | Real provider acceptance only if adapter or provider-dependent behavior changed |
| Config/scheduler/status | Runtime config + scheduler + status | 10.88 s | Real LaunchAgent only for scheduler adapter/release |
| Schema/index/migration | Manifest + validator + discovery/index + migration | 8.92 s | Full deterministic suite for migration or cross-cutting schema change |
| Cross-cutting runtime or release | Affected groups during work | Under 20 s target per slice | Full deterministic suite once |

### Tier 1: fast development checks

Target under 20 seconds. Select by changed files and contract ownership. Run after a coherent local edit, not after each keystroke.

### Tier 2: subsystem integration

Run the relevant multi-process or lifecycle suite after completing a capture, scanner, dispatcher, provider, config, scheduler, status, or skill-behavior slice.

### Tier 3: full deterministic suite

Keep `tests/run-all.sh` as the final pre-merge/pre-release deterministic gate. Also run it for cross-cutting state, schema, or lifecycle changes. Do not require it after documentation-only edits or every intermediate implementation edit.

### Tier 4: acceptance and semantic qualification

Run only when the changed surface justifies it:

- clean Codex/Claude session for hook, loader, plugin packaging, or harness changes;
- real provider for its adapter, CLI capability, authentication boundary, or release qualification;
- real LaunchAgent for scheduler adapter/release work;
- semantic benchmark for model selection or material changes to page selection, attribution, deduplication, cross-linking, orientation, or synthesis.

## Expected savings

### Default script count

A conservative consolidation target is about 60 default deterministic scripts instead of 90:

- consolidate skill checks and remove the overlap heuristic;
- absorb the Leg 1 source-order assertion and stop nested reruns;
- consolidate capture CLI, scanner/recovery, initialization, resolver, manifest, validator, status, issue, and SessionStart cases;
- move real Codex acceptance out of default integration discovery.

This is approximately 30 fewer discovered scripts. It does not require dropping a meaningful durability assertion. Named test functions and per-case failure messages preserve localization inside each subsystem suite.

### Runtime

The primary user-visible saving comes immediately from selecting affected groups: current focused selections are 0.21 to 13.97 seconds rather than 79.36 seconds.

For the full deterministic gate, a reasonable unverified target after consolidation is 60 to 65 seconds. The estimate is based on observable current costs:

- 1.97 seconds of nested Leg 1 reruns;
- six seconds in the mtime test that can be modeled deterministically;
- two one-second filename-separation sleeps in the evidence test;
- one one-second mtime-resolution sleep in init-main;
- three one-second sleeps in end-to-end plumbing that can use state polling;
- repeated hook/status/init fixture startup that can be shared without sharing mutable state.

This is a projection, not a benchmark result. It must be measured after an approved implementation.

## Draft policy wording, not applied

Suggested replacement for the absolute testing bullets in both `AGENTS.md` and `CLAUDE.md`:

```markdown
## Testing discipline

- Use RED-GREEN-REFACTOR for bug fixes and for new or changed non-trivial deterministic behavior. Before implementation, run a focused test that fails for the expected reason.
- Thin wrappers may be covered by an existing integration test when they add no independent branch, state transition, parsing rule, or failure recovery.
- For a `SKILL.md` change that alters triggers, decisions, sequencing, thresholds, or semantic behavior, first run a focused pressure scenario that demonstrates the missing behavior, then rerun it after the change. Links, formatting, factual corrections, and behavior-preserving wording need only the relevant static checks.
- During development, run the smallest affected test tier. Run `bash tests/run-all.sh` once at the integration boundary before a PR, merge, or release, and after cross-cutting state, schema, or lifecycle changes.
- Real provider, real session, and real scheduler acceptance is required when the changed surface depends on that adapter or harness, and for release qualification. It is not a universal documentation gate.
- Run semantic benchmarks only when model selection or semantic ingest behavior changes materially, including page selection, attribution, deduplication, cross-linking, orientation, or synthesis.
```

This keeps the strongest parts of Superpowers: evidence before claims, a witnessed RED for real behavior changes, minimal implementation, and verification at the right boundary. It rejects the universal application of the same ceremony to changes that cannot affect runtime or agent judgment.

## Superpowers comparison

The current Superpowers main branch inspected on 2026-08-12 was version `6.2.0` at `44c9b2d6e889982ac18c27d05a19fefe335194e1`.

Its current `test-driven-development` skill still says TDD is always used for features, bug fixes, refactoring, and behavior changes, with human-approved exceptions only for throwaway prototypes, generated code, and configuration. Its `writing-skills` skill is stricter: no new or edited skill without a failing pressure scenario, including documentation updates and simple additions. Its `verification-before-completion` principle requires fresh evidence before success claims.

Selective adoption is justified here:

- retain fresh evidence before completion;
- retain focused RED-GREEN-REFACTOR for real logic and bugs;
- retain pressure scenarios for changes to agent judgment;
- retain simplicity/YAGNI and explicit human review;
- do not require a new model-pressure run for a link fix, formatting, or behavior-preserving copy edit;
- do not run every deterministic subsystem after every local edit.

Sources:

- [Superpowers repository](https://github.com/obra/superpowers)
- [Current TDD skill](https://github.com/obra/superpowers/blob/44c9b2d6e889982ac18c27d05a19fefe335194e1/skills/test-driven-development/SKILL.md)
- [Current writing-skills methodology](https://github.com/obra/superpowers/blob/44c9b2d6e889982ac18c27d05a19fefe335194e1/skills/writing-skills/SKILL.md)
- [Current verification-before-completion skill](https://github.com/obra/superpowers/blob/44c9b2d6e889982ac18c27d05a19fefe335194e1/skills/verification-before-completion/SKILL.md)

## Codex-first packaging recommendation

### Finding

The repository is not currently a Codex plugin:

- it has `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`;
- it has no `.codex-plugin/plugin.json`;
- README and contributor policy still call Claude Code the primary loader-hook host;
- current deterministic hook tests assert Claude, Cursor, and SDK/Copilot shapes, not a real Codex session;
- the real dispatcher acceptance qualifies Codex as an ingester, not Codex as the interactive host that notices, reads, and captures knowledge.

The older `docs/planning/superpowers-packaging-study.md` statement that Codex has no SessionStart injection is now stale. Current official Codex documentation supports project, user, and plugin-bundled lifecycle hooks, including `SessionStart`, background command hooks, trust review, and `additionalContext` output.

### Recommendation

Use a Codex plugin as the distribution unit for the interactive host:

1. add a minimal `.codex-plugin/plugin.json` that bundles the current skills and `hooks/hooks.json`;
2. reuse the existing hook script where possible because Codex supports the same SessionStart `hookSpecificOutput.additionalContext` shape and supplies `CLAUDE_PLUGIN_ROOT` as a compatibility variable for plugin hooks;
3. inspect and trust the hook through Codex `/hooks` after each changed hook definition;
4. start a new Codex session after install/update;
5. run a disposable clean-session acceptance proving the announce line, wiki-backed answer, capture creation, bounded dispatch, and scheduled-mode loader-only behavior;
6. keep the real provider ingester qualification separate from the interactive-host qualification.

Do not install the same named skill simultaneously through the plugin and `~/.agents/skills`. Official Codex behavior is to expose both matching names rather than merge them, which creates ambiguity during development.

If Codex IDE extension support is required, plugins are not currently available there. Use standalone repo/user skills plus a trusted repo or user `.codex/hooks.json` for that surface. For Codex in the ChatGPT desktop app and Codex CLI, prefer the plugin.

Official sources:

- [Codex skills and skill locations](https://developers.openai.com/codex/skills/)
- [Codex hooks, trust, SessionStart, and plugin-bundled hooks](https://developers.openai.com/codex/hooks/)
- [Codex plugins and supported surfaces](https://developers.openai.com/codex/plugins/)
- [Codex AGENTS.md discovery](https://developers.openai.com/codex/guides/agents-md/)

## Recommended implementation order after human approval

1. Qualify Codex as the interactive host using a disposable wiki and a minimal plugin package.
2. Add change-to-test ownership metadata or a small selector so Tier 1 is usable before reorganizing files.
3. Remove fixed sleeps and nested reruns, then measure the unchanged assertions.
4. Consolidate low-risk duplicate fixtures and phrase checks while preserving named contract cases.
5. Apply the reviewed policy text to `AGENTS.md` and `CLAUDE.md`.
6. Run the full deterministic suite and the relevant Codex clean-session acceptance.
7. Review the complete diff before any PR, then verify commit and push separately.

No step above is authorized by this audit. The process stops here for human review.

## Appendix A: per-test timings

### Unit

| Test | Seconds | Exit |
|---|---:|---:|
| `test-archive-strips-processing.sh` | 0.03 | 0 |
| `test-backfill-quality.sh` | 0.75 | 0 |
| `test-build-index.sh` | 1.03 | 0 |
| `test-capture-atomic-publish.sh` | 0.55 | 0 |
| `test-capture-evidence-path.sh` | 2.51 | 0 |
| `test-capture-headless-unconfigured-cwd-aborts.sh` | 0.25 | 0 |
| `test-capture-skill.sh` | 0.03 | 0 |
| `test-capture.sh` | 0.10 | 0 |
| `test-commit-blocks-on-validator-fail.sh` | 0.45 | 0 |
| `test-commit.sh` | 0.76 | 0 |
| `test-complete-ingest.sh` | 0.28 | 0 |
| `test-config-read.sh` | 0.10 | 0 |
| `test-deep-orientation-cold-start.sh` | 0.02 | 0 |
| `test-discover.sh` | 0.55 | 0 |
| `test-dispatch-scan-routing.sh` | 0.40 | 0 |
| `test-dispatcher-slots.sh` | 1.05 | 0 |
| `test-fix-frontmatter.sh` | 0.38 | 0 |
| `test-inbox-drift-scan.sh` | 0.92 | 0 |
| `test-index-threshold-fires.sh` | 0.44 | 0 |
| `test-ingest-run-events.sh` | 0.24 | 0 |
| `test-ingest-runs-record.sh` | 0.01 | 0 |
| `test-ingest-skill-provider-neutral.sh` | 0.04 | 0 |
| `test-ingest-skill.sh` | 0.03 | 0 |
| `test-init-creates-schema-proposals-dir.sh` | 0.16 | 0 |
| `test-init.sh` | 1.33 | 0 |
| `test-lib.sh` | 0.03 | 0 |
| `test-lint-tags.sh` | 0.29 | 0 |
| `test-loader-has-capture-resist-table.sh` | 0.02 | 0 |
| `test-locks.sh` | 0.21 | 0 |
| `test-manifest-validate.sh` | 0.09 | 0 |
| `test-manifest.sh` | 0.51 | 0 |
| `test-migrate-v2-hardening.sh` | 0.59 | 0 |
| `test-migrate-v2.2.sh` | 0.26 | 0 |
| `test-migrate-v2.3.sh` | 1.69 | 0 |
| `test-mtime-defer.sh` | 6.32 | 0 |
| `test-no-direct-spawn-path.sh` | 0.02 | 0 |
| `test-normalize-frontmatter.sh` | 0.35 | 0 |
| `test-provider-adapters.sh` | 0.18 | 0 |
| `test-provider-classification.sh` | 0.04 | 0 |
| `test-raw-recovery-no-duplicate-captures.sh` | 0.33 | 0 |
| `test-raw-recovery.sh` | 1.13 | 0 |
| `test-raw-staging-no-race.sh` | 0.59 | 0 |
| `test-relink.sh` | 0.26 | 0 |
| `test-reserved-set-update.sh` | 0.02 | 0 |
| `test-resolver-no-cross-project-leak.sh` | 0.02 | 0 |
| `test-resolver-walks-up.sh` | 0.31 | 0 |
| `test-runtime-config-migrate.sh` | 0.97 | 0 |
| `test-runtime-config.sh` | 1.19 | 0 |
| `test-scheduler-plist.sh` | 0.08 | 0 |
| `test-session-start-claude-code-hookeventname.sh` | 1.58 | 0 |
| `test-session-start-loader-injection.sh` | 1.75 | 0 |
| `test-session-start-payload-budget.sh` | 0.01 | 0 |
| `test-skill-split-no-overlap.sh` | 0.03 | 0 |
| `test-status-filters-content-set.sh` | 0.55 | 0 |
| `test-status-last-ingest.sh` | 0.36 | 0 |
| `test-status.sh` | 5.07 | 0 |
| `test-usage-monitor.sh` | 0.42 | 0 |
| `test-using-karpathy-wiki-loader.sh` | 0.02 | 0 |
| `test-validate-code-block-skip.sh` | 0.07 | 0 |
| `test-validate-deleted-categories.sh` | 0.13 | 0 |
| `test-validate-page.sh` | 1.30 | 0 |
| `test-wiki-capture-cli.sh` | 0.68 | 0 |
| `test-wiki-capture-silent-bootstrap.sh` | 0.56 | 0 |
| `test-wiki-ingest-now.sh` | 0.90 | 0 |
| `test-wiki-init-main.sh` | 1.54 | 0 |
| `test-wiki-init-rerun-idempotent.sh` | 1.43 | 0 |
| `test-wiki-init-standalone-project.sh` | 0.35 | 0 |
| `test-wiki-issue-log.sh` | 0.52 | 0 |
| `test-wiki-issues-render.sh` | 0.23 | 0 |
| `test-wiki-manifest-lock.sh` | 0.28 | 0 |
| `test-wiki-resolve.sh` | 1.08 | 0 |
| `test-wiki-status-issues.sh` | 0.93 | 0 |
| `test-wiki-use.sh` | 1.15 | 0 |
| `test-worker-heartbeat.sh` | 0.50 | 0 |
| `test-worker-reconciliation.sh` | 0.22 | 0 |
| `test-yaml-helper.sh` | 0.21 | 0 |

### Integration

| Test | Seconds | Exit |
|---|---:|---:|
| `test-codex-spark-ingest.sh` | 0.00 | 0, skipped unless explicitly enabled |
| `test-concurrent-ingest.sh` | 2.59 | 0 |
| `test-dispatcher-concurrency.sh` | 0.21 | 0 |
| `test-dispatcher-refill.sh` | 0.78 | 0 |
| `test-end-to-end-plumbing.sh` | 8.00 | 0 |
| `test-leg1-end-to-end.sh` | 1.97 | 0 |
| `test-leg2-end-to-end.sh` | 1.63 | 0 |
| `test-leg3-end-to-end.sh` | 1.88 | 0 |
| `test-leg4-end-to-end.sh` | 1.12 | 0 |
| `test-provider-fallback.sh` | 2.16 | 0 |
| `test-provider-worker.sh` | 0.93 | 0 |
| `test-scheduler-lifecycle.sh` | 1.63 | 0 |
| `test-session-start.sh` | 4.77 | 0 |
| `test-worker-lifecycle.sh` | 1.91 | 0 |
