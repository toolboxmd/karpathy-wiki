#!/bin/bash
# Verify wiki status output contains an Issues section when .ingest-issues.jsonl has lines.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STATUS="${REPO_ROOT}/scripts/wiki-status.sh"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

WIKI="${TESTDIR}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null

# Status without issues log: no Issues section (or empty placeholder)
output=$(bash "${STATUS}" "${WIKI}" 2>/dev/null) || fail "status without issues log failed"
# Should not crash; output may or may not have an Issues section header

# Add issue log with 6 broken links + 2 contradictions
log="${WIKI}/.ingest-issues.jsonl"
{
  for i in {1..6}; do
    echo "{\"reported_at\":\"2026-05-06T10:00:00Z\",\"ingester_run\":\"in-${i}\",\"capture\":\"c.md\",\"page\":\"concepts/p${i}.md\",\"issue_type\":\"broken-cross-link\",\"severity\":\"warn\",\"detail\":\"Link missing\"}"
  done
  for i in {1..2}; do
    echo "{\"reported_at\":\"2026-05-06T10:00:00Z\",\"ingester_run\":\"in-c${i}\",\"capture\":\"c.md\",\"page\":\"concepts/q${i}.md\",\"issue_type\":\"contradiction\",\"severity\":\"error\",\"detail\":\"Conflict\"}"
  done
} > "${log}"

output=$(bash "${STATUS}" "${WIKI}")
echo "${output}" | grep -q -i 'issues' || fail "status output missing Issues section"
echo "${output}" | grep -q '6.*broken' || fail "status output missing broken-link count"
echo "${output}" | grep -q '2.*contradict' || fail "status output missing contradiction count"

echo "PASS: wiki status issues integration"
