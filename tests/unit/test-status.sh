#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STATUS="${REPO_ROOT}/scripts/wiki-status.sh"

setup() {
  TESTDIR="$(mktemp -d)"
  WIKI="${TESTDIR}/wiki"
  bash "${REPO_ROOT}/scripts/wiki-init.sh" main "${WIKI}" >/dev/null
}

teardown() { rm -rf "${TESTDIR}"; }

test_status_on_empty_wiki() {
  setup
  local output
  output="$(bash "${STATUS}" "${WIKI}")"
  echo "${output}" | grep -q "role: main" || { echo "FAIL: role missing"; teardown; exit 1; }
  echo "${output}" | grep -q "pending: 0" || { echo "FAIL: pending missing"; teardown; exit 1; }
  echo "${output}" | grep -q "total pages:" || { echo "FAIL: total pages missing"; teardown; exit 1; }
  echo "PASS: test_status_on_empty_wiki"
  teardown
}

test_status_counts_pending() {
  setup
  cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
     "${WIKI}/.wiki-pending/c1.md"
  cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
     "${WIKI}/.wiki-pending/c2.md"
  local output
  output="$(bash "${STATUS}" "${WIKI}")"
  echo "${output}" | grep -q "pending: 2" || {
    echo "FAIL: expected 'pending: 2', got:"
    echo "${output}"
    teardown; exit 1
  }
  echo "PASS: test_status_counts_pending"
  teardown
}

test_status_on_empty_wiki
test_status_counts_pending
echo "ALL PASS"
