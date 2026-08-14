#!/bin/bash
# Deterministic project-to-main publication, provenance, and retry recovery.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROMOTE="${REPO_ROOT}/scripts/wiki-promote-capture.py"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT
export WIKI_POINTER_FILE="${TESTDIR}/.wiki-pointer"

MAIN="${TESTDIR}/main"
SECOND_MAIN="${TESTDIR}/second-main"
PROJECT="${TESTDIR}/project"
bash "${INIT}" main "${MAIN}" >/dev/null
bash "${INIT}" main "${SECOND_MAIN}" >/dev/null
bash "${INIT}" project "${PROJECT}" "${MAIN}" >/dev/null
echo "${MAIN}" > "${WIKI_POINTER_FILE}"

make_source() {
  local name="$1"
  local policy="${2:-selective}"
  local capture="${PROJECT}/.wiki-pending/${name}.md.processing"
  cat > "${capture}" <<EOF
---
title: "${name}"
evidence: "conversation"
evidence_type: "conversation"
capture_kind: "chat-only"
suggested_action: "create"
suggested_pages: []
captured_at: "2026-08-12T12-00-00Z"
captured_by: "in-session-agent"
capture_id: "cap-${name}"
promotion_policy: "${policy}"
promotion_decision: null
promotion_id: null
propagated_from: null
---

Project source body for ${name}.
EOF
  echo "${capture}"
}

make_body() {
  local path="$1"
  printf 'Reusable generalized knowledge with enough detail for main ingestion.\n%.0s' {1..35} > "${path}"
}

run_promote() {
  local capture="$1"
  shift
  WIKI_ROOT="${PROJECT}" WIKI_CAPTURE="${capture}" WIKI_RUN_ID="test-run" \
    WIKI_PLUGIN_ROOT="${REPO_ROOT}" python3 "${PROMOTE}" "$@"
}

test_publish_once_with_portable_provenance() {
  local capture body promoted
  capture="$(make_source reusable)"
  body="${TESTDIR}/reusable-body.md"
  make_body "${body}"

  run_promote "${capture}" publish --title "Reusable routing pattern" --body-file "${body}"
  promoted="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' -print -quit)"
  [[ -n "${promoted}" ]] || fail "publish created no derived main capture"
  [[ "$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')" -eq 1 ]] \
    || fail "publish created more than one main capture"
  grep -q '^capture_id: "prom-' "${promoted}" || fail "derived capture lacks promotion identity"
  grep -q '^propagated_from: "cap-reusable"' "${promoted}" \
    || fail "derived capture lacks portable source capture provenance"
  ! grep -q "${PROJECT}" "${promoted}" || fail "derived capture leaked an absolute project path"
  grep -q '^promotion_decision: "promoted"' "${capture}" \
    || fail "source capture was not marked promoted"
  grep -q '^promotion_id: "prom-' "${capture}" || fail "source capture lacks promotion id"
  [[ "$(find "${PROJECT}/.locks/promotions" -maxdepth 1 -type f -name 'prom-*.json' | wc -l | tr -d ' ')" -eq 1 ]] \
    || fail "durable local promotion receipt missing"
  run_promote "${capture}" verify || fail "published decision did not verify"
}

test_body_floor_uses_normalized_emitted_body() {
  local capture body before after state_before state_after
  capture="$(make_source whitespace-floor)"
  body="${TESTDIR}/whitespace-floor-body.md"
  printf 'x%1500s' '' > "${body}"
  before="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')"
  state_before="$(find "${PROJECT}/.locks/promotions" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"

  run_promote "${capture}" publish --title "Whitespace is not detail" --body-file "${body}" >/dev/null 2>&1 \
    && fail "trailing whitespace satisfied the normalized promotion body floor"
  after="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')"
  state_after="$(find "${PROJECT}/.locks/promotions" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d ' ')"
  [[ "${after}" -eq "${before}" ]] || fail "short normalized body changed the main queue"
  grep -q '^promotion_decision: null' "${capture}" \
    || fail "short normalized body changed the source decision"
  [[ "${state_after}" -eq "${state_before}" ]] \
    || fail "short normalized body created promotion intent or receipt state"
}

test_normalized_body_floor_boundary_succeeds() {
  local capture body promoted
  capture="$(make_source normalized-boundary)"
  body="${TESTDIR}/normalized-boundary-body.md"
  printf '%1500s' '' | tr ' ' x > "${body}"

  run_promote "${capture}" publish --title "Exact normalized boundary" --body-file "${body}"
  promoted="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' -exec grep -l '^propagated_from: "cap-normalized-boundary"$' {} +)"
  [[ -n "${promoted}" ]] || fail "normalized 1500-byte boundary did not publish"
  grep -q '^promotion_decision: "promoted"' "${capture}" \
    || fail "normalized boundary source was not marked promoted"
}

test_repeat_and_concurrent_retry_are_idempotent() {
  local capture body
  capture="${PROJECT}/.wiki-pending/reusable.md.processing"
  body="${TESTDIR}/reusable-body.md"

  run_promote "${capture}" publish --title "Reusable routing pattern" --body-file "${body}"
  run_promote "${capture}" publish --title "Reusable routing pattern" --body-file "${body}" &
  p1=$!
  run_promote "${capture}" publish --title "Changed retry title" --body-file "${body}" &
  p2=$!
  wait "${p1}"
  wait "${p2}"
  [[ "$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')" -eq 1 ]] \
    || fail "retry or concurrency duplicated the main capture"
}

test_failure_after_intent_is_recoverable() {
  local capture body before after
  capture="$(make_source recoverable)"
  body="${TESTDIR}/recoverable-body.md"
  make_body "${body}"
  before="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')"

  WIKI_PROMOTION_TEST_MODE=1 WIKI_PROMOTION_TEST_FAIL_AFTER_INTENT=1 \
    run_promote "${capture}" publish --title "Recoverable pattern" --body-file "${body}" >/dev/null 2>&1 \
    && fail "injected promotion failure unexpectedly succeeded"
  after="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')"
  [[ "${after}" -eq "${before}" ]] || fail "failure before publication created a main capture"
  grep -q '"status": "intent"' "${PROJECT}/.locks/promotions/prom-"*.json \
    || fail "failure did not preserve promotion intent"

  run_promote "${capture}" publish --title "Recoverable pattern" --body-file "${body}"
  after="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')"
  [[ "${after}" -eq $((before + 1)) ]] || fail "retry did not publish exactly one main capture"
  grep -q '^promotion_decision: "promoted"' "${capture}" || fail "retry did not mark source"
}

test_failure_after_publish_before_mark_is_recoverable() {
  local capture body before after
  capture="$(make_source published-before-mark)"
  body="${TESTDIR}/published-before-mark-body.md"
  make_body "${body}"
  before="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')"

  WIKI_PROMOTION_TEST_MODE=1 WIKI_PROMOTION_TEST_FAIL_AFTER_PUBLISH=1 \
    run_promote "${capture}" publish --title "Published before mark" --body-file "${body}" >/dev/null 2>&1 \
    && fail "post-publication injected failure unexpectedly succeeded"
  after="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')"
  [[ "${after}" -eq $((before + 1)) ]] || fail "injected failure did not stop after publication"
  grep -q '^promotion_decision: null' "${capture}" \
    || fail "injected failure unexpectedly marked source promoted"

  run_promote "${capture}" publish --title "Changed retry title" --body-file "${body}"
  after="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')"
  [[ "${after}" -eq $((before + 1)) ]] || fail "post-publication retry duplicated main capture"
  grep -q '^promotion_decision: "promoted"' "${capture}" \
    || fail "post-publication retry did not mark source"
}

test_missing_receipt_after_publish_recovers_existing_target() {
  local capture body before after
  capture="$(make_source missing-receipt)"
  body="${TESTDIR}/missing-receipt-body.md"
  make_body "${body}"
  before="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')"

  WIKI_PROMOTION_TEST_MODE=1 WIKI_PROMOTION_TEST_FAIL_AFTER_PUBLISH=1 \
    run_promote "${capture}" publish --title "Missing receipt recovery" --body-file "${body}" >/dev/null 2>&1 \
    && fail "post-publication injected failure unexpectedly succeeded"
  rm -f "${PROJECT}/.locks/promotions/prom-"*.json

  run_promote "${capture}" publish --title "Changed retry title" --body-file "${body}"
  after="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')"
  [[ "${after}" -eq $((before + 1)) ]] || fail "missing-receipt retry duplicated main capture"
  grep -q '"status": "published"' "${PROJECT}/.locks/promotions/prom-"*.json \
    || fail "missing-receipt retry did not restore the published receipt"
}

test_missing_receipt_and_changed_main_recovers_original_target() {
  local capture body original_before second_before
  capture="$(make_source changed-main-retry)"
  body="${TESTDIR}/changed-main-retry-body.md"
  make_body "${body}"
  original_before="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')"
  second_before="$(find "${SECOND_MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')"

  WIKI_PROMOTION_TEST_MODE=1 WIKI_PROMOTION_TEST_FAIL_AFTER_PUBLISH=1 \
    run_promote "${capture}" publish --title "Pinned publication" --body-file "${body}" >/dev/null 2>&1 \
    && fail "changed-main fixture did not stop after publication"
  rm -f "${PROJECT}/.locks/promotions/prom-"*.json
  echo "${SECOND_MAIN}" > "${WIKI_POINTER_FILE}"

  run_promote "${capture}" publish --title "Retry after pointer change" --body-file "${body}"
  [[ "$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')" -eq $((original_before + 1)) ]] \
    || fail "changed-main retry did not retain the original published target"
  [[ "$(find "${SECOND_MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')" -eq "${second_before}" ]] \
    || fail "changed-main retry published the promotion identity in a second main queue"
  grep -q '"main_wiki": .*\/main"' "${PROJECT}/.locks/promotions/prom-"*.json \
    || fail "changed-main retry did not restore the original main receipt"
  echo "${MAIN}" > "${WIKI_POINTER_FILE}"
}

test_keep_local_rejects_published_target_after_receipt_loss() {
  local capture body
  capture="$(make_source keep-local-after-publish)"
  body="${TESTDIR}/keep-local-after-publish-body.md"
  make_body "${body}"

  WIKI_PROMOTION_TEST_MODE=1 WIKI_PROMOTION_TEST_FAIL_AFTER_PUBLISH=1 \
    run_promote "${capture}" publish --title "Published before local decision" --body-file "${body}" >/dev/null 2>&1 \
    && fail "post-publication injected failure unexpectedly succeeded"
  rm -f "${PROJECT}/.locks/promotions/prom-"*.json

  run_promote "${capture}" keep-local >/dev/null 2>&1 \
    && fail "keep-local accepted an already-published deterministic target"
  grep -q '^promotion_decision: null' "${capture}" \
    || fail "failed keep-local changed the source decision"
  [[ "$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')" -ge 1 ]] \
    || fail "published target disappeared during keep-local check"
}

test_keep_local_and_project_policy_guard() {
  local selective local_only body before after
  selective="$(make_source local-case)"
  run_promote "${selective}" keep-local
  grep -q '^promotion_decision: "keep-local"' "${selective}" \
    || fail "keep-local decision was not persisted"
  run_promote "${selective}" keep-local || fail "repeated keep-local decision was not idempotent"
  run_promote "${selective}" verify || fail "keep-local decision did not verify"
  body="${TESTDIR}/terminal-decision-body.md"
  make_body "${body}"
  before="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')"
  run_promote "${selective}" publish --title "Must remain local" --body-file "${body}" >/dev/null 2>&1 \
    && fail "keep-local decision was later changed to promoted"
  after="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')"
  [[ "${after}" -eq "${before}" ]] || fail "terminal keep-local decision changed main queue"

  local_only="$(make_source project-only none)"
  body="${TESTDIR}/project-only-body.md"
  make_body "${body}"
  before="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')"
  run_promote "${local_only}" publish --title "Must stay local" --body-file "${body}" >/dev/null 2>&1 \
    && fail "project-only capture unexpectedly promoted"
  after="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')"
  [[ "${after}" -eq "${before}" ]] || fail "project-only refusal changed main queue"
}

test_forged_promoted_decision_is_rejected() {
  local capture
  capture="$(make_source forged)"
  sed -i.bak \
    -e 's/promotion_decision: null/promotion_decision: "promoted"/' \
    -e 's/promotion_id: null/promotion_id: "prom-forged"/' \
    "${capture}"
  rm -f "${capture}.bak"
  if run_promote "${capture}" verify >/dev/null 2>&1; then
    fail "forged promoted decision without receipt unexpectedly verified"
  fi
}

test_publish_once_with_portable_provenance
test_repeat_and_concurrent_retry_are_idempotent
test_body_floor_uses_normalized_emitted_body
test_normalized_body_floor_boundary_succeeds
test_failure_after_intent_is_recoverable
test_failure_after_publish_before_mark_is_recoverable
test_missing_receipt_after_publish_recovers_existing_target
test_missing_receipt_and_changed_main_recovers_original_target
test_keep_local_rejects_published_target_after_receipt_loss
test_keep_local_and_project_policy_guard
test_forged_promoted_decision_is_rejected
echo "PASS: selective promotion"
