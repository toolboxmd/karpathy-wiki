#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/wiki-lib.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/wiki-lock.sh"

setup() {
  TESTDIR="$(mktemp -d)"
  WIKI="${TESTDIR}/wiki"
  mkdir -p "${WIKI}/.locks"
  mkdir -p "${WIKI}/concepts"
  touch "${WIKI}/.wiki-config"
  touch "${WIKI}/concepts/foo.md"
}

teardown() {
  rm -rf "${TESTDIR}"
}

test_acquire_succeeds_on_free_page() {
  setup
  if wiki_lock_acquire "${WIKI}" "concepts/foo.md" "cap-1"; then
    echo "PASS: test_acquire_succeeds_on_free_page"
  else
    echo "FAIL: should have acquired"; teardown; exit 1
  fi
  teardown
}

test_acquire_fails_when_held() {
  setup
  wiki_lock_acquire "${WIKI}" "concepts/foo.md" "cap-1"
  if wiki_lock_acquire "${WIKI}" "concepts/foo.md" "cap-2" 2>/dev/null; then
    echo "FAIL: second acquire should have failed"; teardown; exit 1
  fi
  echo "PASS: test_acquire_fails_when_held"
  teardown
}

test_release_allows_reacquisition() {
  setup
  wiki_lock_acquire "${WIKI}" "concepts/foo.md" "cap-1"
  wiki_lock_release "${WIKI}" "concepts/foo.md"
  if wiki_lock_acquire "${WIKI}" "concepts/foo.md" "cap-2"; then
    echo "PASS: test_release_allows_reacquisition"
  else
    echo "FAIL: reacquire after release should have succeeded"; teardown; exit 1
  fi
  teardown
}

test_stale_lock_reclaim() {
  setup
  # Create a stale lock (fake old timestamp)
  local lockfile
  lockfile="${WIKI}/.locks/concepts-foo-md.lock"
  echo '{"pid":99999,"started_at":"1970-01-01T00:00:00Z","capture_id":"stale"}' > "${lockfile}"
  # Set mtime to 1 hour ago
  touch -t 202601010000 "${lockfile}"
  # Should now succeed because lock is stale
  if wiki_lock_acquire "${WIKI}" "concepts/foo.md" "cap-1"; then
    echo "PASS: test_stale_lock_reclaim"
  else
    echo "FAIL: stale lock should have been reclaimed"; teardown; exit 1
  fi
  teardown
}

test_acquire_succeeds_on_free_page
test_acquire_fails_when_held
test_release_allows_reacquisition
test_stale_lock_reclaim
echo "ALL PASS"
