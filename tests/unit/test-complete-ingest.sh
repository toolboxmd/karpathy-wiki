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

test_selective_capture_requires_decision() {
  local wiki="${TESTDIR}/selective"
  local capture="${wiki}/.wiki-pending/selective.md.processing"
  make_wiki "${wiki}"
  printf 'role = "project"\n' > "${wiki}/.wiki-config"
  printf '%s\n' '---' 'title: "Selective"' 'capture_id: "cap-selective"' \
    'promotion_policy: "selective"' 'promotion_decision: null' \
    'promotion_id: null' '---' > "${capture}"
  run_complete "${wiki}" "${capture}" >/dev/null 2>&1 \
    && fail "selective capture without decision unexpectedly completed"
  [[ -f "${capture}" ]] || fail "missing decision lost processing capture"
  WIKI_ROOT="${wiki}" WIKI_CAPTURE="${capture}" WIKI_RUN_ID="in-test" \
    WIKI_PLUGIN_ROOT="${REPO_ROOT}" python3 "${REPO_ROOT}/scripts/wiki-promote-capture.py" keep-local \
    || fail "keep-local helper failed"
  run_complete "${wiki}" "${capture}" || fail "decided selective capture did not complete"
  echo "PASS: test_selective_capture_requires_decision"
}

test_body_promotion_prose_is_not_metadata() {
  local wiki="${TESTDIR}/body-prose"
  local capture="${wiki}/.wiki-pending/body-prose.md.processing"
  make_wiki "${wiki}"
  printf '%s\n' '---' 'title: "Legacy capture documenting promotion"' '---' '' \
    'The supported setting is written as:' 'promotion_policy: selective' > "${capture}"
  run_complete "${wiki}" "${capture}" || fail "body promotion prose was treated as frontmatter"
  [[ -f "${wiki}/.wiki-pending/archive/$(date +%Y-%m)/body-prose.md" ]] \
    || fail "legacy capture with body promotion prose was not archived"
  echo "PASS: test_body_promotion_prose_is_not_metadata"
}

test_explicit_unsupported_policy_fails_closed() {
  local wiki="${TESTDIR}/unsupported-policy"
  local capture="${wiki}/.wiki-pending/unsupported.md.processing"
  make_wiki "${wiki}"
  printf '%s\n' '---' 'title: "Unsupported policy"' \
    'promotion_policy: "always"' '---' > "${capture}"

  run_complete "${wiki}" "${capture}" >/dev/null 2>&1 \
    && fail "explicit unsupported promotion policy unexpectedly completed"
  [[ -f "${capture}" ]] || fail "unsupported policy lost recoverable processing capture"
  [[ ! -d "${wiki}/.wiki-pending/archive" ]] \
    || fail "unsupported policy was archived as legacy"
  echo "PASS: test_explicit_unsupported_policy_fails_closed"
}

test_explicit_malformed_policy_fails_closed() {
  local wiki="${TESTDIR}/malformed-policy"
  local capture="${wiki}/.wiki-pending/malformed.md.processing"
  make_wiki "${wiki}"
  printf '%s\n' '---' 'title: "Malformed policy"' \
    'promotion_policy: "selective" trailing-text' '---' > "${capture}"

  run_complete "${wiki}" "${capture}" >/dev/null 2>&1 \
    && fail "explicit malformed promotion policy unexpectedly completed"
  [[ -f "${capture}" ]] || fail "malformed policy lost recoverable processing capture"
  [[ ! -d "${wiki}/.wiki-pending/archive" ]] \
    || fail "malformed policy was archived as legacy"
  echo "PASS: test_explicit_malformed_policy_fails_closed"
}

test_inline_comment_selective_policy_requires_decision() {
  local wiki="${TESTDIR}/inline-comment-policy"
  local capture="${wiki}/.wiki-pending/inline-comment.md.processing"
  make_wiki "${wiki}"
  printf 'role = "project"\n' > "${wiki}/.wiki-config"
  printf '%s\n' '---' 'title: "Inline comment policy"' \
    'capture_id: "cap-inline-comment"' \
    'promotion_policy: selective # routing note' \
    'promotion_decision: null' 'promotion_id: null' '---' > "${capture}"

  run_complete "${wiki}" "${capture}" >/dev/null 2>&1 \
    && fail "inline-comment selective policy bypassed decision enforcement"
  [[ -f "${capture}" ]] || fail "inline-comment policy lost recoverable processing capture"
  [[ ! -d "${wiki}/.wiki-pending/archive" ]] \
    || fail "inline-comment selective policy was archived as legacy"
  echo "PASS: test_inline_comment_selective_policy_requires_decision"
}

test_crlf_legacy_capture_completes_without_changing_content() {
  local wiki="${TESTDIR}/crlf-legacy"
  local capture="${wiki}/.wiki-pending/crlf-legacy.md.processing"
  local expected="${TESTDIR}/crlf-legacy.expected"
  make_wiki "${wiki}"
  printf '%s\r\n' '---' 'title: "CRLF legacy capture"' '---' '' \
    'Body line preserved with CRLF.' > "${capture}"
  cp "${capture}" "${expected}"

  run_complete "${wiki}" "${capture}" || fail "valid CRLF legacy capture did not complete"
  local archived="${wiki}/.wiki-pending/archive/$(date +%Y-%m)/crlf-legacy.md"
  [[ -f "${archived}" ]] || fail "valid CRLF legacy capture was not archived"
  cmp -s "${expected}" "${archived}" \
    || fail "completion changed CRLF legacy capture content"
  echo "PASS: test_crlf_legacy_capture_completes_without_changing_content"
}

test_crlf_selective_capture_completes() {
  local wiki="${TESTDIR}/crlf-selective"
  local capture="${wiki}/.wiki-pending/crlf-selective.md.processing"
  local expected="${TESTDIR}/crlf-selective.expected"
  make_wiki "${wiki}"
  printf 'role = "project"\n' > "${wiki}/.wiki-config"
  printf '%s\r\n' '---' 'title: "CRLF selective capture"' \
    'capture_id: "cap-crlf-selective"' 'promotion_policy: "selective"' \
    'promotion_decision: "keep-local"' 'promotion_id: null' '---' '' \
    'Selective body preserved with CRLF.' > "${capture}"
  cp "${capture}" "${expected}"

  run_complete "${wiki}" "${capture}" || fail "valid CRLF selective capture did not complete"
  local archived="${wiki}/.wiki-pending/archive/$(date +%Y-%m)/crlf-selective.md"
  [[ -f "${archived}" ]] || fail "valid CRLF selective capture was not archived"
  cmp -s "${expected}" "${archived}" \
    || fail "completion changed CRLF selective capture content"
  echo "PASS: test_crlf_selective_capture_completes"
}

test_success_and_idempotence
test_validation_failure_keeps_processing
test_post_archive_failure_rolls_back
test_selective_capture_requires_decision
test_body_promotion_prose_is_not_metadata
test_inline_comment_selective_policy_requires_decision
test_explicit_unsupported_policy_fails_closed
test_explicit_malformed_policy_fails_closed
test_crlf_legacy_capture_completes_without_changing_content
test_crlf_selective_capture_completes
echo "ALL PASS"
