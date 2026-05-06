# Contributing to karpathy-wiki

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

Claude Code is the primary, fully-tested platform. As of v0.2.7 the SessionStart hook also emits the harness-correct JSON shape for Cursor (`additional_context`) and Copilot CLI / SDK-standard harnesses (`additionalContext`), but those paths are untested and best-effort. PRs adding test coverage for non-Claude-Code harnesses are welcome.

## Testing discipline

See `superpowers:writing-skills` for the RED-GREEN-REFACTOR methodology this project follows.
