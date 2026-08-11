#!/bin/bash
# Deterministic validate -> archive -> commit helper and rollback behavior.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
COMPLETE="${REPO_ROOT}/scripts/wiki-complete-ingest.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

make_wiki() {
  local root="$1"
  mkdir -p "${root}/.wiki-pending" "${root}/.locks"
  printf '{}\n' > "${root}/.manifest.json"
  cat > "${root}/.wiki-config.local" <<'EOF'
[ingest]
dispatch_mode = "scheduled"
max_processes = 1
default_profile = "p"
[ingest.profiles.p]
provider = "codex"
model = "test"
reasoning_effort = "low"
[settings]
auto_commit = false
EOF
}

run_complete() {
  local wiki="$1"
  local capture="$2"
  WIKI_ROOT="${wiki}" WIKI_CAPTURE="${capture}" WIKI_RUN_ID="in-test" \
    bash "${COMPLETE}"
}

test_success_and_idempotence() {
  local wiki="${TESTDIR}/success"
  local capture="${wiki}/.wiki-pending/capture.md.processing"
  make_wiki "${wiki}"
  printf '%s\n' '---' 'title: "Completion test"' '---' > "${capture}"
  run_complete "${wiki}" "${capture}" || fail "completion helper failed"
  local archived
  archived="$(find "${wiki}/.wiki-pending/archive" -type f -name 'capture.md' -print -quit)"
  [[ -n "${archived}" ]] || fail "successful completion did not archive capture"
  [[ ! -e "${capture}" ]] || fail "processing capture remains after completion"
  run_complete "${wiki}" "${capture}" || fail "second completion call should be idempotent"
  [[ "$(find "${wiki}/.wiki-pending/archive" -type f -name 'capture.md' | wc -l | tr -d ' ')" -eq 1 ]] \
    || fail "idempotent completion created another archive"
  echo "PASS: test_success_and_idempotence"
}

test_validation_failure_keeps_processing() {
  local wiki="${TESTDIR}/invalid-manifest"
  local capture="${wiki}/.wiki-pending/capture.md.processing"
  make_wiki "${wiki}"
  printf '%s\n' '{"raw/x.md":{"origin":""}}' > "${wiki}/.manifest.json"
  printf '%s\n' '---' 'title: "Invalid manifest"' '---' > "${capture}"
  run_complete "${wiki}" "${capture}" >/dev/null 2>&1 && fail "invalid manifest unexpectedly completed"
  [[ -f "${capture}" ]] || fail "validation failure lost processing capture"
  [[ ! -d "${wiki}/.wiki-pending/archive" ]] || fail "validation failure archived capture"
  echo "PASS: test_validation_failure_keeps_processing"
}

test_post_archive_failure_rolls_back() {
  local wiki="${TESTDIR}/rollback"
  local capture="${wiki}/.wiki-pending/capture.md.processing"
  make_wiki "${wiki}"
  printf '%s\n' '---' 'title: "Rollback"' '---' > "${capture}"
  WIKI_COMPLETE_TEST_MODE=1 WIKI_COMPLETE_TEST_FAIL_AFTER_ARCHIVE=1 \
  WIKI_ROOT="${wiki}" WIKI_CAPTURE="${capture}" WIKI_RUN_ID="in-rollback" \
    bash "${COMPLETE}" >/dev/null 2>&1 && fail "injected post-archive failure unexpectedly succeeded"
  [[ -f "${capture}" ]] || fail "post-archive failure did not restore processing capture"
  [[ "$(find "${wiki}/.wiki-pending/archive" -type f -name 'capture.md' 2>/dev/null | wc -l | tr -d ' ')" -eq 0 ]] \
    || fail "rollback left archived copy"
  echo "PASS: test_post_archive_failure_rolls_back"
}

test_success_and_idempotence
test_validation_failure_keeps_processing
test_post_archive_failure_rolls_back
echo "ALL PASS"
