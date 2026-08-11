#!/bin/bash
# Verify the ingest skill assigns run-history mechanics to the wrapper.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SKILL="${REPO_ROOT}/skills/karpathy-wiki-ingest/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

grep -q -i 'Run record' "${SKILL}" || fail "missing 'Run record' section"
grep -q '.ingest-runs.jsonl' "${SKILL}" || fail "missing .ingest-runs.jsonl filename"
grep -q 'WIKI_RUN_ID' "${SKILL}" || fail "missing runtime-provided run ID"
grep -qi 'runtime wrapper owns' "${SKILL}" || fail "wrapper ownership is not explicit"
grep -q 'wiki-complete-ingest.sh' "${SKILL}" || fail "completion helper missing"
if grep -q 'ingest-runs.lock\|RUN_ID="in-' "${SKILL}"; then
  fail "model-authored run-history implementation remains"
fi

echo "PASS: ingest skill delegates run-record protocol to runtime"
