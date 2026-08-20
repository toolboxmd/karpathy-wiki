#!/bin/bash
set -e
export WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME=1

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
  cat > "${WIKI}/.wiki-config.local" <<'EOF'
[ingest]
dispatch_mode = "session_start"
max_processes = 1
default_profile = "test"
heartbeat_seconds = 5
stale_after_seconds = 30
usage_monitor = "off"

[ingest.profiles.test]
provider = "codex"
model = "test"
reasoning_effort = "low"

[settings]
auto_commit = false
EOF
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

test_embedded_wiki_commit_does_not_stage_parent_repo_changes() {
  TESTDIR="$(mktemp -d)"
  local app="${TESTDIR}/app"
  WIKI="${app}/wiki"
  mkdir -p "${app}"
  (
    cd "${app}"
    git init -q
    git config user.email test@example.com
    git config user.name test
    printf 'app v1\n' > app.txt
    git add app.txt
    git commit -q -m "chore: init app"
  )
  bash "${REPO_ROOT}/scripts/wiki-init.sh" main "${WIKI}" >/dev/null
  (
    cd "${app}"
    git add wiki
    git commit -q -m "chore: init embedded wiki"
  )

  printf 'app v2\n' > "${app}/app.txt"
  printf '\n# Changed inside wiki\n' >> "${WIKI}/index.md"
  bash "${COMMIT}" "${WIKI}" "ingest: embedded wiki only"

  local last changed status
  last="$(cd "${app}" && git log -1 --format=%s)"
  [[ "${last}" == "ingest: embedded wiki only" ]] || {
    echo "FAIL: embedded wiki commit message. got '${last}'"; teardown; exit 1
  }
  changed="$(cd "${app}" && git show --name-only --format= HEAD | sed '/^$/d')"
  grep -Fxq "wiki/index.md" <<< "${changed}" || {
    echo "FAIL: embedded wiki change was not committed"; teardown; exit 1
  }
  if grep -Fxq "app.txt" <<< "${changed}"; then
    echo "FAIL: parent repo file was captured by wiki commit"; teardown; exit 1
  fi
  status="$(cd "${app}" && git status --short)"
  grep -Fxq " M app.txt" <<< "${status}" || {
    echo "FAIL: parent repo change should remain unstaged in working tree; status=${status}"; teardown; exit 1
  }
  echo "PASS: test_embedded_wiki_commit_does_not_stage_parent_repo_changes"
  teardown
}

test_commit_nothing_if_no_changes
test_commit_creates_commit_with_message
test_commit_respects_auto_commit_false
test_embedded_wiki_commit_does_not_stage_parent_repo_changes
echo "ALL PASS"
