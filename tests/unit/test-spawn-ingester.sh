#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SPAWN="${REPO_ROOT}/scripts/wiki-spawn-ingester.sh"

# Override headless_command to a no-op for testing: we only verify
# that the spawner builds the right command and detaches.

setup() {
  TESTDIR="$(mktemp -d)"
  WIKI="${TESTDIR}/wiki"
  mkdir -p "${WIKI}/.wiki-pending"
  cat > "${WIKI}/.wiki-config" <<EOF
role = "main"
[platform]
headless_command = "echo"
[settings]
auto_commit = false
EOF
  cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
     "${WIKI}/.wiki-pending/2026-04-22T14-30-test.md"
}

teardown() { rm -rf "${TESTDIR}"; }

test_spawner_detaches_and_exits_immediately() {
  setup
  local start_ts end_ts elapsed
  start_ts="$(date +%s)"
  bash "${SPAWN}" "${WIKI}" "${WIKI}/.wiki-pending/2026-04-22T14-30-test.md"
  end_ts="$(date +%s)"
  elapsed=$((end_ts - start_ts))
  [[ "${elapsed}" -le 2 ]] || {
    echo "FAIL: spawner took ${elapsed}s, should be near-instant"
    teardown; exit 1
  }
  echo "PASS: test_spawner_detaches_and_exits_immediately"
  teardown
}

test_spawner_exits_0_on_missing_capture() {
  setup
  if bash "${SPAWN}" "${WIKI}" "${WIKI}/.wiki-pending/does-not-exist.md"; then
    echo "PASS: test_spawner_exits_0_on_missing_capture (graceful)"
  else
    echo "FAIL: missing capture should not be fatal"
    teardown; exit 1
  fi
  teardown
}

test_spawner_detaches_and_exits_immediately
test_spawner_exits_0_on_missing_capture
echo "ALL PASS"
