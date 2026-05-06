#!/bin/bash
# Verify karpathy-wiki-ingest/SKILL.md documents deep orientation algorithm
# AND the cold-start fallback (≤7 candidate-eligible pages → role-prompt primary).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SKILL="${REPO_ROOT}/skills/karpathy-wiki-ingest/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "${SKILL}" ]] || fail "ingest skill missing"

# Required deep-orientation language
grep -q -i 'deep orientation' "${SKILL}" || fail "missing 'deep orientation' heading or term"
grep -q -i 'candidate' "${SKILL}" || fail "missing 'candidate' selection language"
grep -q -i 'substring.*tag\|tag.*substring' "${SKILL}" || fail "missing substring + tag match algorithm"
grep -q -i 'top.*7\|max.*7\|up to 7' "${SKILL}" || fail "missing 7-candidate cap"
grep -q -i 'cold.start\|≤.*7\|<=.*7\|fewer than 8' "${SKILL}" || fail "missing cold-start fallback"

# Issue reporting integration
grep -q 'wiki-issue-log.sh' "${SKILL}" || fail "ingest skill should call wiki-issue-log.sh"
grep -q -i '.ingest-issues.jsonl' "${SKILL}" || fail "ingest skill should mention .ingest-issues.jsonl"

# Issue types enumerated
for t in broken-cross-link contradiction schema-drift stale-claim; do
  grep -q "${t}" "${SKILL}" || fail "ingest skill missing issue_type: ${t}"
done

echo "PASS: ingest skill documents deep orientation + issue reporting"
