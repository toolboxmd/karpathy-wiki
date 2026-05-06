#!/bin/bash
# Verify the ingest skill documents .ingest-runs.jsonl protocol.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SKILL="${REPO_ROOT}/skills/karpathy-wiki-ingest/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

grep -q -i 'Run record' "${SKILL}" || fail "missing 'Run record' section"
grep -q '.ingest-runs.jsonl' "${SKILL}" || fail "missing .ingest-runs.jsonl filename"
grep -q '"status":"spawned"' "${SKILL}" || fail "missing spawned status"
grep -q 'completed\|failed' "${SKILL}" || fail "missing closing status values"
grep -q 'flock' "${SKILL}" || fail "missing flock guidance"

echo "PASS: ingest skill documents run-record protocol"
