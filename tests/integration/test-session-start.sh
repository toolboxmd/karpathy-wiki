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

test_hook_emits_loader_context_in_normal_session() {
  setup
  local output
  output="$(cd "${WIKI}" && env -u WIKI_CAPTURE -u CLAUDE_AGENT_PARENT bash "${HOOK}")"
  # v2.4: hook emits the using-karpathy-wiki loader as additionalContext in
  # normal sessions. Drift/drain still write to .ingest.log (not stdout).
  if echo "${output}" | grep -q 'additionalContext' \
     && echo "${output}" | grep -q 'EXTREMELY_IMPORTANT' \
     && echo "${output}" | grep -q 'using-karpathy-wiki'; then
    echo "PASS: test_hook_emits_loader_context_in_normal_session"
  else
    echo "FAIL: hook did not emit loader additionalContext: '${output:0:200}...'"
    teardown; exit 1
  fi
  teardown
}

test_hook_emits_empty_context_in_subagent_or_ingester() {
  setup
  local output_capture output_subagent
  output_capture="$(cd "${WIKI}" && WIKI_CAPTURE=1 bash "${HOOK}")"
  output_subagent="$(cd "${WIKI}" && env -u WIKI_CAPTURE CLAUDE_AGENT_PARENT=1 bash "${HOOK}")"
  # In subagent/ingester contexts the hook must emit no model-visible context.
  if [[ -z "${output_capture}" || "${output_capture}" == "{}" ]] \
     && [[ -z "${output_subagent}" || "${output_subagent}" == "{}" ]]; then
    echo "PASS: test_hook_emits_empty_context_in_subagent_or_ingester"
  else
    echo "FAIL: hook leaked context in guarded contexts: capture='${output_capture:0:120}' subagent='${output_subagent:0:120}'"
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

test_hook_emits_loader_context_in_normal_session
test_hook_emits_empty_context_in_subagent_or_ingester
test_hook_spawns_ingester_for_pending
test_hook_exits_fast
echo "ALL PASS"
