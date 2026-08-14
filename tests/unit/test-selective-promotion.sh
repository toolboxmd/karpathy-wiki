#!/bin/bash
# Deterministic project-to-main publication, provenance, and retry recovery.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PROMOTE="${REPO_ROOT}/scripts/wiki-promote-capture.py"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

file_mode() {
  local path="$1"
  if stat -f '%Lp' "${path}" >/dev/null 2>&1; then
    stat -f '%Lp' "${path}"
  else
    stat -c '%a' "${path}"
  fi
}

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT
export WIKI_POINTER_FILE="${TESTDIR}/.wiki-pointer"
export XDG_CONFIG_HOME="${TESTDIR}/config-home"

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
  local capture body promoted pin
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
  ! grep -q '^promotion_main_wiki:' "${capture}" \
    || fail "source capture leaked an absolute main path"
  find "${XDG_CONFIG_HOME}/karpathy-wiki/promotions" -type f -name 'prom-*.json' \
    -exec grep -l '"canonical_main_wiki"' {} + | grep -q . \
    || fail "trusted external promotion pin missing"
  pin="$(find "${XDG_CONFIG_HOME}/karpathy-wiki/promotions" -type f -name 'prom-*.json' -exec grep -l 'cap-reusable' {} +)"
  [[ "$(file_mode "${pin}")" == "600" && "$(file_mode "$(dirname "${pin}")")" == "700" ]] \
    || fail "trusted promotion pin is not owner-only"
  python3 - "${pin}" "${PROJECT}" "${MAIN}" <<'PY' || fail "trusted promotion pin bindings are incomplete"
import json, sys
import os
pin = json.load(open(sys.argv[1], encoding="utf-8"))
expected_project_wiki = os.path.realpath(sys.argv[2])
expected_main_wiki = os.path.realpath(sys.argv[3])
assert pin["schema_version"] == 1
assert pin["source_capture_id"] == "cap-reusable"
assert pin["promotion_id"].startswith("prom-")
assert pin["canonical_project_wiki"] == expected_project_wiki
assert pin["canonical_workspace"]
assert pin["canonical_main_wiki"] == expected_main_wiki
assert pin["target_name"].endswith(f'-{pin["promotion_id"]}.md')
assert pin["created_at"]
PY
  [[ "$(find "${PROJECT}/.locks/promotions" -maxdepth 1 -type f -name 'prom-*.json' | wc -l | tr -d ' ')" -eq 1 ]] \
    || fail "durable local promotion receipt missing"
  run_promote "${capture}" verify || fail "published decision did not verify"
}

test_forged_tracked_pin_cannot_redirect_first_publication() {
  local capture body main_before second_before
  capture="$(make_source forged-pin-redirect)"
  body="${TESTDIR}/forged-pin-redirect-body.md"
  make_body "${body}"
  sed -i.bak "/^promotion_id:/a promotion_main_wiki: \"${SECOND_MAIN}\"" "${capture}"
  rm -f "${capture}.bak"
  main_before="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')"
  second_before="$(find "${SECOND_MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')"

  run_promote "${capture}" publish --title "Trusted route wins" --body-file "${body}"
  [[ "$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')" -eq $((main_before + 1)) ]] \
    || fail "forged tracked pin redirected first publication away from trusted main"
  [[ "$(find "${SECOND_MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')" -eq "${second_before}" ]] \
    || fail "forged tracked pin redirected first publication to writable second main"
  ! grep -q '^promotion_main_wiki:' "${capture}" \
    || fail "forged tracked pin remained in the source capture"
}

test_receipt_loss_verification_reconstructs_from_external_pin() {
  local capture body
  capture="$(make_source verify-reconstruct)"
  body="${TESTDIR}/verify-reconstruct-body.md"
  make_body "${body}"
  run_promote "${capture}" publish --title "Verification recovery" --body-file "${body}"
  rm -f "${PROJECT}/.locks/promotions/prom-"*.json

  run_promote "${capture}" verify \
    || fail "receipt-loss verification did not reconstruct from trusted durable state"
  grep -q '"status": "published"' "${PROJECT}/.locks/promotions/prom-"*.json \
    || fail "verification did not reconstruct the transient receipt"
}

test_pin_precedes_receipt_and_publication() {
  local capture body before
  capture="$(make_source pin-first-crash)"
  body="${TESTDIR}/pin-first-crash-body.md"
  make_body "${body}"
  before="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')"

  WIKI_PROMOTION_TEST_MODE=1 WIKI_PROMOTION_TEST_FAIL_AFTER_PIN=1 \
    run_promote "${capture}" publish --title "Pin first" --body-file "${body}" >/dev/null 2>&1 \
    && fail "injected pin-first crash unexpectedly succeeded"
  find "${XDG_CONFIG_HOME}/karpathy-wiki/promotions" -type f -name 'prom-*.json' \
    -exec grep -l 'cap-pin-first-crash' {} + | grep -q . \
    || fail "pin-first crash did not leave the trusted external pin"
  ! find "${PROJECT}/.locks/promotions" -type f -name 'prom-*.json' \
    -exec grep -l 'cap-pin-first-crash' {} + | grep -q . \
    || fail "pin-first crash wrote the receipt before the external pin boundary"
  [[ "$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')" -eq "${before}" ]] \
    || fail "pin-first crash published before the external pin boundary"
  run_promote "${capture}" keep-local >/dev/null 2>&1 \
    && fail "keep-local accepted trusted intent before publication"
  echo "${SECOND_MAIN}" > "${WIKI_POINTER_FILE}"
  run_promote "${capture}" publish --title "Pin first retry" --body-file "${body}"
  [[ "$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')" -eq $((before + 1)) ]] \
    || fail "retry did not publish to the pinned original main"
  echo "${MAIN}" > "${WIKI_POINTER_FILE}"
}

test_pin_mismatch_fails_closed() {
  local capture body pin
  capture="$(make_source pin-mismatch)"
  body="${TESTDIR}/pin-mismatch-body.md"
  make_body "${body}"
  WIKI_PROMOTION_TEST_MODE=1 WIKI_PROMOTION_TEST_FAIL_AFTER_PIN=1 \
    run_promote "${capture}" publish --title "Mismatch" --body-file "${body}" >/dev/null 2>&1 \
    && fail "pin mismatch fixture unexpectedly published"
  pin="$(find "${XDG_CONFIG_HOME}/karpathy-wiki/promotions" -type f -name 'prom-*.json' -exec grep -l 'cap-pin-mismatch' {} +)"
  python3 - "${pin}" <<'PY'
import json, sys
path = sys.argv[1]
value = json.load(open(path, encoding="utf-8"))
value["target_name"] = "forged.md"
with open(path, "w", encoding="utf-8") as handle:
    json.dump(value, handle)
PY
  chmod 600 "${pin}"
  run_promote "${capture}" publish --title "Mismatch retry" --body-file "${body}" >/dev/null 2>&1 \
    && fail "mismatched trusted pin did not fail closed"
  grep -q '^promotion_decision: null' "${capture}" \
    || fail "mismatched pin changed the source decision"
}

test_no_cross_workspace_pin_reuse() {
  local other capture body first_pin_count
  other="${TESTDIR}/other-project"
  bash "${INIT}" project "${other}" "${SECOND_MAIN}" >/dev/null
  capture="${other}/.wiki-pending/cross-workspace.md.processing"
  sed 's/cap-forged-pin-redirect/cap-cross-workspace/' \
    "$(make_source forged-pin-redirect)" > "${capture}"
  body="${TESTDIR}/cross-workspace-body.md"
  make_body "${body}"
  first_pin_count="$(find "${XDG_CONFIG_HOME}/karpathy-wiki/promotions" -type f -name 'prom-*.json' | wc -l | tr -d ' ')"
  echo "${SECOND_MAIN}" > "${WIKI_POINTER_FILE}"
  WIKI_ROOT="${other}" WIKI_CAPTURE="${capture}" WIKI_RUN_ID="test-run" \
    WIKI_PLUGIN_ROOT="${REPO_ROOT}" python3 "${PROMOTE}" publish \
      --title "Separate workspace identity" --body-file "${body}"
  [[ "$(find "${XDG_CONFIG_HOME}/karpathy-wiki/promotions" -type f -name 'prom-*.json' | wc -l | tr -d ' ')" -eq $((first_pin_count + 1)) ]] \
    || fail "another workspace reused an existing promotion pin"
  find "${SECOND_MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' \
    -exec grep -l '^propagated_from: "cap-cross-workspace"$' {} + | grep -q . \
    || fail "another workspace did not publish through its own trusted pin"
  echo "${MAIN}" > "${WIKI_POINTER_FILE}"
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

test_external_pin_lookup_survives_parent_pointer_removal() {
  local workspace nested capture body original_before second_before pin promotion_id other
  workspace="${TESTDIR}/standalone-workspace"
  nested="${workspace}/wiki"
  mkdir -p "${workspace}"
  bash "${INIT}" project "${nested}" "${MAIN}" >/dev/null
  cat > "${workspace}/.wiki-config" <<EOF
role = "project-pointer"
wiki = "${nested}"
fork_to_main = true
EOF
  capture="${nested}/.wiki-pending/stable-root.md.processing"
  sed 's/cap-reusable/cap-stable-root/g; s/title: "reusable"/title: "stable-root"/' \
    "$(make_source reusable)" > "${capture}"
  body="${TESTDIR}/stable-root-body.md"
  make_body "${body}"
  original_before="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')"
  second_before="$(find "${SECOND_MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')"

  WIKI_ROOT="${nested}" WIKI_CAPTURE="${capture}" WIKI_RUN_ID="test-run" \
    WIKI_PLUGIN_ROOT="${REPO_ROOT}" python3 "${PROMOTE}" publish \
      --title "Stable root pin" --body-file "${body}"
  promotion_id="$(sed -n 's/^promotion_id: "\([^"]*\)"$/\1/p' "${capture}")"
  pin="$(find "${XDG_CONFIG_HOME}/karpathy-wiki/promotions" -type f -name "${promotion_id}.json" -exec grep -l 'cap-stable-root' {} +)"
  [[ -n "${pin}" ]] || fail "stable-root fixture did not create an external pin"
  [[ "$(basename "$(dirname "${pin}")")" == "$(python3 -c 'import hashlib, sys; print(hashlib.sha256(sys.argv[1].encode()).hexdigest())' "${nested}")" ]] \
    || fail "external pin directory is not the full canonical project-wiki digest"

  rm -f "${nested}/.locks/promotions/${promotion_id}.json" "${workspace}/.wiki-config"
  echo "${SECOND_MAIN}" > "${WIKI_POINTER_FILE}"
  WIKI_ROOT="${nested}" WIKI_CAPTURE="${capture}" WIKI_RUN_ID="test-run" \
    WIKI_PLUGIN_ROOT="${REPO_ROOT}" python3 "${PROMOTE}" publish \
      --title "Stable root retry" --body-file "${body}"
  [[ "$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name "*-${promotion_id}.md" | wc -l | tr -d ' ')" -eq 1 ]] \
    || fail "parent-pointer removal did not recover exactly one original-main target"
  [[ "$(find "${SECOND_MAIN}/.wiki-pending" -maxdepth 1 -type f -name "*-${promotion_id}.md" | wc -l | tr -d ' ')" -eq 0 ]] \
    || fail "parent-pointer removal redirected retry to the current main"
  [[ "$(find "${XDG_CONFIG_HOME}/karpathy-wiki/promotions" -type f -name "${promotion_id}.json" | wc -l | tr -d ' ')" -eq 1 ]] \
    || fail "parent-pointer removal created a second external pin"
  grep -q '"status": "published"' "${nested}/.locks/promotions/${promotion_id}.json" \
    || fail "parent-pointer removal did not reconstruct the receipt"

  other="${TESTDIR}/isolated-stable-root"
  bash "${INIT}" project "${other}" "${SECOND_MAIN}" >/dev/null
  capture="${other}/.wiki-pending/stable-root.md.processing"
  sed 's/cap-reusable/cap-stable-root/g; s/title: "reusable"/title: "stable-root"/' \
    "$(make_source reusable)" > "${capture}"
  WIKI_ROOT="${other}" WIKI_CAPTURE="${capture}" WIKI_RUN_ID="test-run" \
    WIKI_PLUGIN_ROOT="${REPO_ROOT}" python3 "${PROMOTE}" publish \
      --title "Isolated stable root" --body-file "${body}"
  [[ "$(find "${XDG_CONFIG_HOME}/karpathy-wiki/promotions" -type f -name "${promotion_id}.json" | wc -l | tr -d ' ')" -eq 2 ]] \
    || fail "same capture ID in another project wiki reused the first external pin"
  echo "${MAIN}" > "${WIKI_POINTER_FILE}"
  [[ "$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')" -eq $((original_before + 1)) ]] \
    || fail "stable-root recovery changed unrelated original-main targets"
  [[ "$(find "${SECOND_MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')" -eq $((second_before + 1)) ]] \
    || fail "cross-project isolation did not publish exactly once to its own main"
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

test_inline_comment_policy_is_eligible_for_both_decisions() {
  local local_capture publish_capture body promoted
  local_capture="$(make_source inline-comment-local)"
  sed -i.bak 's/^promotion_policy: "selective"$/promotion_policy: selective # routing note/' "${local_capture}"
  rm -f "${local_capture}.bak"

  run_promote "${local_capture}" keep-local \
    || fail "inline-comment selective policy was not eligible for keep-local"
  grep -q '^promotion_decision: "keep-local"' "${local_capture}" \
    || fail "inline-comment selective policy was not eligible for keep-local"

  publish_capture="$(make_source inline-comment-publish)"
  sed -i.bak 's/^promotion_policy: "selective"$/promotion_policy: selective # routing note/' "${publish_capture}"
  rm -f "${publish_capture}.bak"
  body="${TESTDIR}/inline-comment-publish-body.md"
  make_body "${body}"
  run_promote "${publish_capture}" publish --title "Inline comment policy" --body-file "${body}" \
    || fail "inline-comment selective policy was not eligible for publish"
  promoted="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' \
    -exec grep -l '^propagated_from: "cap-inline-comment-publish"$' {} +)"
  [[ -n "${promoted}" ]] \
    || fail "inline-comment selective policy was not eligible for publish"

  local quoted_capture
  quoted_capture="$(make_source quoted-comment-marker)"
  sed -i.bak 's/^promotion_policy: "selective"$/promotion_policy: "selective # literal"/' "${quoted_capture}"
  rm -f "${quoted_capture}.bak"
  run_promote "${quoted_capture}" keep-local >/dev/null 2>&1 \
    && fail "quoted comment marker was stripped from the policy scalar"
  grep -q '^promotion_decision: null' "${quoted_capture}" \
    || fail "quoted comment-marker rejection changed the source decision"
}

test_keep_local_without_intent_ignores_unavailable_current_main() {
  local scenario capture queue_before queue_after
  for scenario in missing moved incomplete; do
    capture="$(make_source "keep-local-${scenario}")"
    case "${scenario}" in
      missing)
        echo "${TESTDIR}/missing-main" > "${WIKI_POINTER_FILE}"
        ;;
      moved)
        mv "${SECOND_MAIN}" "${SECOND_MAIN}.moved"
        echo "${SECOND_MAIN}" > "${WIKI_POINTER_FILE}"
        ;;
      incomplete)
        echo "${SECOND_MAIN}" > "${WIKI_POINTER_FILE}"
        rm -f "${SECOND_MAIN}/index.md"
        ;;
    esac
    queue_before="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')"
    run_promote "${capture}" keep-local \
      || fail "keep-local rejected an unavailable ${scenario} current main without publication intent"
    queue_after="$(find "${MAIN}/.wiki-pending" -maxdepth 1 -type f -name '*prom-*.md' | wc -l | tr -d ' ')"
    grep -q '^promotion_decision: "keep-local"' "${capture}" \
      || fail "unavailable ${scenario} main did not persist keep-local"
    ! grep -q '^promotion_main_wiki:' "${capture}" \
      || fail "unavailable ${scenario} main created a durable main pin"
    [[ "${queue_after}" -eq "${queue_before}" ]] \
      || fail "unavailable ${scenario} main changed main publication state"
    ! find "${PROJECT}/.locks/promotions" -maxdepth 1 -type f -name 'prom-*.json' \
      -exec grep -l "cap-keep-local-${scenario}" {} + | grep -q . \
      || fail "unavailable ${scenario} main created a promotion receipt"
    case "${scenario}" in
      moved) mv "${SECOND_MAIN}.moved" "${SECOND_MAIN}" ;;
      incomplete) printf '# Index\n' > "${SECOND_MAIN}/index.md" ;;
    esac
  done
  echo "${MAIN}" > "${WIKI_POINTER_FILE}"
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
test_receipt_loss_verification_reconstructs_from_external_pin
test_forged_tracked_pin_cannot_redirect_first_publication
test_pin_precedes_receipt_and_publication
test_pin_mismatch_fails_closed
test_no_cross_workspace_pin_reuse
test_body_floor_uses_normalized_emitted_body
test_normalized_body_floor_boundary_succeeds
test_failure_after_intent_is_recoverable
test_failure_after_publish_before_mark_is_recoverable
test_missing_receipt_after_publish_recovers_existing_target
test_missing_receipt_and_changed_main_recovers_original_target
test_external_pin_lookup_survives_parent_pointer_removal
test_keep_local_rejects_published_target_after_receipt_loss
test_keep_local_and_project_policy_guard
test_inline_comment_policy_is_eligible_for_both_decisions
test_keep_local_without_intent_ignores_unavailable_current_main
test_forged_promoted_decision_is_rejected
echo "PASS: selective promotion"
