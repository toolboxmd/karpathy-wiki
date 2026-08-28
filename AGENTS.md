# Contributing to karpathy-wiki

## Active planning handoff

Before changing test policy or removing, merging, or demoting tests, read
[`docs/planning/2026-08-12-test-strategy-rightsizing-handoff.md`](docs/planning/2026-08-12-test-strategy-rightsizing-handoff.md).
The first phase is a read-only portfolio audit and must stop for human review.
Remove this pointer when that workstream is resolved.

## Project ledger files

Use the global project-ledger convention when adding or pruning local
`CHANGELOG.md`, `TODO.md`, `ISSUES.md`, and `IDEAS.md`.

In this repository, `ISSUES.md` means a local known-problems scratchpad. It is
not the `wiki issues` command, not `.ingest-issues.jsonl`, not a GitHub Issues
replacement, and not a work-package manifest.

## Recent Changes

- 2026-08-28: Naturbiss proof restored `9fb75e3a`, ran doctor 0.8.1
  plus shop-surface rewrites; queue stayed paused. Report in
  `docs/proof/2026-08-28-naturbiss-doctor-rewriter.md`.
- 2026-08-28: Entity rewrite jobs turn a catalog entity into a map.
  Identity sources stay; claim sources move onto playbooks that cite
  them. Unique source paths are not dropped except duplicates.
- 2026-08-28: Detached `wiki rewrite` drains one cluster job in the
  shared ingest pool. Two siblings compact onto a playbook; pointer
  files stay off the index. Doctor still does not rewrite bodies.
- 2026-08-28: Doctor complete fails closed unless every 6+ cluster and
  catalog entity has a rewrite job.
- 2026-08-28: Doctor topical-keep helper strips provenance and spray
  tags and must not remove `sources:`.
- 2026-08-28: Category indexes and discovery counts omit pages tagged
  `pointer`; the files stay on disk.
- 2026-08-28: Schema Objects are knowledge-object names only. Schema-patch
  drops function words, pointer-stub language, and corpus-wide tags, and
  prunes tokens that fall under 6 hits. Annotated Page-contract keys are
  not duplicated.


## If you are an AI agent

Before opening a PR against this repo:

1. **Read the PR template** (when one exists) and answer every prompt; do not skip prompts you find redundant.
2. **Search for existing PRs** on the same topic. Duplicates get closed.
3. **Verify a real problem exists.** Cite the failing test, the wrong output, or the user-reported bug. Do NOT fabricate problem descriptions.
4. **Show your human partner the complete diff** before submitting. Walk them through it.

We will not accept:

- Speculative fixes for problems no one is reporting.
- Bulk reformatting / "compliance" rewrites of skill content.
- Bundled unrelated changes in one PR.
- Fabricated test results, fabricated bug reports, fabricated benchmark numbers.

## Before you submit a PR

- Run the full test suite: `bash tests/run-all.sh`
- Every new script must have unit tests before the script itself exists (TDD discipline).
- Every SKILL.md change must be preceded by a pressure scenario showing an agent failing without the change.
- If your change touches `hooks/session-start` or `skills/using-karpathy-wiki/SKILL.md`, include a real session transcript in the PR description showing the announce line firing on a wiki-eligible trigger in a clean session. Tests verify the loader injects; only a transcript verifies the agent reads and acts on it.

## Scope

This skill does ONE thing: auto-capture, read, and ingest durable knowledge. Do not add:

- Vector search (defer until genuine scaling pain)
- Web UI / dashboard
- Notifications / alerts

## Platform support

Codex is the primary interactive development host. Claude Code remains a
supported, fully-tested platform; preserve its existing hook behavior and test
coverage. Codex has qualified interactive-host acceptance evidence, but this
does not imply equivalent automated coverage for every Codex lifecycle path.
As of v0.2.7 the SessionStart hook also emits the harness-correct JSON shape for
Cursor (`additional_context`) and Copilot CLI / SDK-standard harnesses
(`additionalContext`), but those paths are untested and best-effort. PRs adding
test coverage for those best-effort harnesses are welcome.

## Testing discipline

See `superpowers:writing-skills` for the RED-GREEN-REFACTOR methodology this project follows.
