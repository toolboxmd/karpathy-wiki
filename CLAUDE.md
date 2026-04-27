# Contributing to karpathy-wiki

## Before you submit a PR

- Run the full test suite: `bash tests/run-all.sh`
- Every new script must have unit tests before the script itself exists (TDD discipline).
- Every SKILL.md change must be preceded by a pressure scenario showing an agent failing without the change.

## Scope

This skill does ONE thing: auto-capture and ingest durable knowledge. Do not add:
- Vector search (defer until genuine scaling pain)
- Web UI / dashboard
- Notifications / alerts
- LLM-specific magic (keep the skill cross-platform)

## Testing discipline

See `superpowers:writing-skills` for the RED-GREEN-REFACTOR methodology this project follows.
