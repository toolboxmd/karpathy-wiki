#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMMIT="${REPO_ROOT}/scripts/wiki-commit.sh"

setup() {
  TESTDIR="$(mktemp -d)"
  WIKI="${TESTDIR}/wiki"
  bash "${REPO_ROOT}/scripts/wiki-init.sh" main "${WIKI}" >/dev/null
}

teardown() { rm -rf "${TESTDIR}"; }

test_commit_nothing_if_no_changes() {
  setup
  # initial commit was made by init. With no subsequent changes, commit should be a no-op.
  bash "${COMMIT}" "${WIKI}" "Nothing to commit"
  # Count commits
  local count
  count="$(cd "${WIKI}" && git rev-list --count HEAD)"
  # Should still be 1 (init commit), not 2
  [[ "${count}" -eq 1 ]] || { echo "FAIL: expected 1 commit, got ${count}"; teardown; exit 1; }
  echo "PASS: test_commit_nothing_if_no_changes"
  teardown
}

test_commit_creates_commit_with_message() {
  setup
  echo "# Changed" >> "${WIKI}/index.md"
  bash "${COMMIT}" "${WIKI}" "ingest: test title"
  local last
  last="$(cd "${WIKI}" && git log -1 --format=%s)"
  [[ "${last}" == "ingest: test title" ]] || {
    echo "FAIL: commit message. got '${last}'"; teardown; exit 1
  }
  echo "PASS: test_commit_creates_commit_with_message"
  teardown
}

test_commit_respects_auto_commit_false() {
  setup
  sed -i.bak 's/auto_commit = true/auto_commit = false/' "${WIKI}/.wiki-config"
  rm -f "${WIKI}/.wiki-config.bak"
  echo "# Changed" >> "${WIKI}/index.md"
  bash "${COMMIT}" "${WIKI}" "ingest: should not commit"
  local last
  last="$(cd "${WIKI}" && git log -1 --format=%s)"
  # Should still be the init commit, not the new one
  [[ "${last}" != "ingest: should not commit" ]] || {
    echo "FAIL: commit created despite auto_commit=false"; teardown; exit 1
  }
  echo "PASS: test_commit_respects_auto_commit_false"
  teardown
}

test_commit_nothing_if_no_changes
test_commit_creates_commit_with_message
test_commit_respects_auto_commit_false
echo "ALL PASS"
