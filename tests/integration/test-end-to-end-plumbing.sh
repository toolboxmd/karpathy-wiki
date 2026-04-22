#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

setup() {
  TESTDIR="$(mktemp -d)"
  WIKI="${TESTDIR}/wiki"
  bash "${REPO_ROOT}/scripts/wiki-init.sh" main "${WIKI}" >/dev/null
  # Use echo as a stand-in for claude -p.
  sed -i.bak 's|claude -p|echo stub-ingester|' "${WIKI}/.wiki-config"
  rm -f "${WIKI}/.wiki-config.bak"
}

teardown() { rm -rf "${TESTDIR}"; }

test_capture_drop_plus_hook_plus_spawn() {
  setup

  # Drop a capture
  cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
     "${WIKI}/.wiki-pending/2026-04-22T14-30-test.md"

  # Run session-start hook
  (cd "${WIKI}" && bash "${REPO_ROOT}/hooks/session-start") >/dev/null

  # Wait briefly for spawned workers
  sleep 2

  # Verify: capture either processing or gone
  if [[ -f "${WIKI}/.wiki-pending/2026-04-22T14-30-test.md" ]]; then
    echo "FAIL: capture never claimed"
    ls -la "${WIKI}/.wiki-pending/"
    teardown; exit 1
  fi

  # Verify: ingest log has entries
  grep -q "spawned ingester" "${WIKI}/.ingest.log" || {
    echo "FAIL: spawn not logged"
    cat "${WIKI}/.ingest.log"
    teardown; exit 1
  }

  echo "PASS: test_capture_drop_plus_hook_plus_spawn"
  teardown
}

test_capture_drop_plus_hook_plus_spawn
echo "ALL PASS"
