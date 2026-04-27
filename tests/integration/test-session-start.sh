#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${REPO_ROOT}/hooks/session-start"

setup() {
  TESTDIR="$(mktemp -d)"
  export HOME="${TESTDIR}"
  WIKI="${TESTDIR}/wiki"
  bash "${REPO_ROOT}/scripts/wiki-init.sh" main "${WIKI}" >/dev/null
  export WIKI_TEST_ROOT="${WIKI}"
  # Override headless_command so ingester doesn't actually try to run claude
  sed -i.bak 's|claude -p|echo|' "${WIKI}/.wiki-config"
  rm -f "${WIKI}/.wiki-config.bak"
}

teardown() { rm -rf "${TESTDIR}"; }

test_hook_emits_empty_context_on_clean_wiki() {
  setup
  local output
  output="$(cd "${WIKI}" && bash "${HOOK}")"
  # Per superpowers-style-guide, hooks must emit zero model-visible context.
  # Empty output or just {} is acceptable; anything else is a regression.
  if [[ -z "${output}" ]] || [[ "${output}" == "{}" ]]; then
    echo "PASS: test_hook_emits_empty_context_on_clean_wiki"
  else
    echo "FAIL: hook emitted context on clean wiki: '${output}'"
    teardown; exit 1
  fi
  teardown
}

test_hook_spawns_ingester_for_pending() {
  setup
  # Drop a pending capture
  cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
     "${WIKI}/.wiki-pending/2026-04-22T14-30-pending.md"
  (cd "${WIKI}" && bash "${HOOK}") >/dev/null
  # Give spawner a moment
  sleep 1
  # Capture should be claimed (renamed to .processing) or archived
  local has_pending has_processing
  has_pending=0
  has_processing=0
  for f in "${WIKI}/.wiki-pending"/*.md; do
    [[ -f "${f}" ]] || continue
    [[ "${f}" == *.processing ]] && has_processing=1 && continue
    has_pending=1
  done
  # Expect processing or fully consumed.
  # With echo-as-headless, the ingester does nothing, so capture stays as .processing.
  if [[ "${has_processing}" -eq 1 ]] || [[ "${has_pending}" -eq 0 ]]; then
    echo "PASS: test_hook_spawns_ingester_for_pending"
  else
    echo "FAIL: capture not claimed"
    ls "${WIKI}/.wiki-pending/"
    teardown; exit 1
  fi
  teardown
}

test_hook_exits_fast() {
  setup
  local start end elapsed
  start="$(date +%s)"
  (cd "${WIKI}" && bash "${HOOK}") >/dev/null
  end="$(date +%s)"
  elapsed=$((end - start))
  [[ "${elapsed}" -le 3 ]] || {
    echo "FAIL: hook took ${elapsed}s, should be <=3"; teardown; exit 1
  }
  echo "PASS: test_hook_exits_fast (${elapsed}s)"
  teardown
}

test_hook_emits_empty_context_on_clean_wiki
test_hook_spawns_ingester_for_pending
test_hook_exits_fast
echo "ALL PASS"
