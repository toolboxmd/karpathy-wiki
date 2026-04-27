#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/wiki-lib.sh"
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/wiki-capture.sh"

setup() {
  TESTDIR="$(mktemp -d)"
  WIKI="${TESTDIR}/wiki"
  mkdir -p "${WIKI}/.wiki-pending"
  touch "${WIKI}/.wiki-config"
}

teardown() {
  rm -rf "${TESTDIR}"
}

test_claim_succeeds() {
  setup
  cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
     "${WIKI}/.wiki-pending/2026-04-22T14-30-example.md"
  local claimed
  claimed="$(wiki_capture_claim "${WIKI}")"
  if [[ -f "${claimed}" ]] && [[ "${claimed}" == *.processing ]]; then
    echo "PASS: test_claim_succeeds (claimed: $(basename "${claimed}"))"
  else
    echo "FAIL: expected a .processing file, got: ${claimed}"
    teardown; exit 1
  fi
  teardown
}

test_claim_returns_empty_when_no_pending() {
  setup
  local claimed
  claimed="$(wiki_capture_claim "${WIKI}" || echo "NONE")"
  [[ "${claimed}" == "NONE" ]] || {
    echo "FAIL: expected NONE, got '${claimed}'"; teardown; exit 1
  }
  echo "PASS: test_claim_returns_empty_when_no_pending"
  teardown
}

test_claim_is_atomic_sequential() {
  # Basic smoke: two claims in sequence should give claim+NONE.
  setup
  cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
     "${WIKI}/.wiki-pending/2026-04-22T14-30-example.md"
  local a b
  a="$(wiki_capture_claim "${WIKI}" 2>/dev/null)"
  b="$(wiki_capture_claim "${WIKI}" 2>/dev/null || echo "NONE")"
  if [[ -n "${a}" ]] && [[ "${b}" == "NONE" ]]; then
    echo "PASS: test_claim_is_atomic_sequential"
  else
    echo "FAIL: sequential claim. a=${a} b=${b}"; teardown; exit 1
  fi
  teardown
}

test_claim_is_atomic_concurrent() {
  # Real concurrency: start N background claims racing on ONE capture.
  # Exactly one should report a claimed path; the rest NONE.
  setup
  cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
     "${WIKI}/.wiki-pending/2026-04-22T14-30-example.md"

  local outdir
  outdir="$(mktemp -d)"
  local N=5 i
  for i in $(seq 1 "${N}"); do
    (
      # shellcheck source=/dev/null
      source "${REPO_ROOT}/scripts/wiki-lib.sh"
      # shellcheck source=/dev/null
      source "${REPO_ROOT}/scripts/wiki-capture.sh"
      result="$(wiki_capture_claim "${WIKI}" 2>/dev/null || echo "NONE")"
      echo "${result}" > "${outdir}/claim-${i}.out"
    ) &
  done
  wait

  # Count how many got a non-NONE result.
  local winners=0
  for i in $(seq 1 "${N}"); do
    local out
    out="$(cat "${outdir}/claim-${i}.out")"
    [[ "${out}" == "NONE" ]] && continue
    [[ -n "${out}" ]] && winners=$((winners + 1))
  done

  rm -rf "${outdir}"
  if [[ "${winners}" -eq 1 ]]; then
    echo "PASS: test_claim_is_atomic_concurrent (1 winner out of ${N})"
  else
    echo "FAIL: expected exactly 1 winner, got ${winners}"
    teardown; exit 1
  fi
  teardown
}

test_claim_succeeds
test_claim_returns_empty_when_no_pending
test_claim_is_atomic_sequential
test_claim_is_atomic_concurrent
echo "ALL PASS"
