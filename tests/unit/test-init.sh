#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/wiki-lib.sh"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

setup() {
  TESTDIR="$(mktemp -d)"
}

teardown() { rm -rf "${TESTDIR}"; }

test_init_main_creates_structure() {
  setup
  bash "${INIT}" main "${TESTDIR}/wiki" >/dev/null
  for f in index.md log.md schema.md .wiki-config .manifest.json .gitignore; do
    [[ -e "${TESTDIR}/wiki/${f}" ]] || { echo "FAIL: missing ${f}"; teardown; exit 1; }
  done
  for d in concepts entities sources queries raw .wiki-pending .locks; do
    [[ -d "${TESTDIR}/wiki/${d}" ]] || { echo "FAIL: missing dir ${d}"; teardown; exit 1; }
  done
  echo "PASS: test_init_main_creates_structure"
  teardown
}

test_init_main_writes_correct_role() {
  setup
  bash "${INIT}" main "${TESTDIR}/wiki" >/dev/null
  grep -q '^role = "main"' "${TESTDIR}/wiki/.wiki-config" || {
    echo "FAIL: role != main"; teardown; exit 1
  }
  echo "PASS: test_init_main_writes_correct_role"
  teardown
}

test_init_project_links_to_main() {
  setup
  bash "${INIT}" main "${TESTDIR}/main-wiki" >/dev/null
  bash "${INIT}" project "${TESTDIR}/proj/wiki" "${TESTDIR}/main-wiki" >/dev/null
  grep -q '^role = "project"' "${TESTDIR}/proj/wiki/.wiki-config" || {
    echo "FAIL: role != project"; teardown; exit 1
  }
  grep -q "main = \"${TESTDIR}/main-wiki\"" "${TESTDIR}/proj/wiki/.wiki-config" || {
    echo "FAIL: main path not recorded"; teardown; exit 1
  }
  echo "PASS: test_init_project_links_to_main"
  teardown
}

test_init_idempotent() {
  setup
  bash "${INIT}" main "${TESTDIR}/wiki" >/dev/null
  echo "CUSTOM INDEX" > "${TESTDIR}/wiki/index.md"
  bash "${INIT}" main "${TESTDIR}/wiki" >/dev/null
  grep -q "CUSTOM INDEX" "${TESTDIR}/wiki/index.md" || {
    echo "FAIL: re-init clobbered existing index.md"; teardown; exit 1
  }
  echo "PASS: test_init_idempotent"
  teardown
}

test_init_creates_git_repo_if_git_installed() {
  setup
  if ! command -v git >/dev/null 2>&1; then
    echo "SKIP: test_init_creates_git_repo (git not installed)"
    teardown; return
  fi
  bash "${INIT}" main "${TESTDIR}/wiki" >/dev/null
  [[ -d "${TESTDIR}/wiki/.git" ]] || { echo "FAIL: .git not created"; teardown; exit 1; }
  echo "PASS: test_init_creates_git_repo_if_git_installed"
  teardown
}

test_init_main_creates_structure
test_init_main_writes_correct_role
test_init_project_links_to_main
test_init_idempotent
test_init_creates_git_repo_if_git_installed
echo "ALL PASS"
