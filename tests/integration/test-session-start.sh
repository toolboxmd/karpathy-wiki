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
  cat > "${WIKI}/.wiki-config.local" <<'EOF'
[ingest]
dispatch_mode = "session_start"
max_processes = 1
default_profile = "test"
max_attempts = 1
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
  export WIKI_DISPATCH_TEST_MODE=1
  export WIKI_DISPATCH_TEST_PROVIDER_MODE=success_no_complete
  export WIKI_DISPATCH_TEST_NO_REFILL=1
}

teardown() {
  # SessionStart intentionally detaches its tick. On macOS, rm can observe a
  # last log/runtime write while recursively removing the disposable fixture.
  # Retry the fixture cleanup until that bounded background tick has exited.
  local attempt
  for attempt in $(seq 1 100); do
    rm -rf "${TESTDIR}" 2>/dev/null && return 0
    sleep 0.05
  done
  rm -rf "${TESTDIR}"
}

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

test_hook_emits_installed_cli_path() {
  setup
  local output expected_cli
  expected_cli="${REPO_ROOT}/bin/wiki"
  output="$(cd "${WIKI}" && env -u WIKI_CAPTURE -u CLAUDE_AGENT_PARENT bash "${HOOK}")"

  if echo "${output}" | grep -Fq "${expected_cli}" \
     && echo "${output}" | grep -Fq 'do not rely on a global symlink or PATH entry'; then
    echo "PASS: test_hook_emits_installed_cli_path"
  else
    echo "FAIL: loader context did not expose the plugin-owned wiki CLI: '${output:0:240}...'"
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

test_hook_dispatches_pending_capture() {
  setup
  # Drop a pending capture
  cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
     "${WIKI}/.wiki-pending/2026-04-22T14-30-pending.md"
  (cd "${WIKI}" && bash "${HOOK}") >/dev/null
  # The hook returns immediately; wait for durable terminal evidence so the
  # detached worker has finished before the disposable fixture is removed.
  local deadline=$((SECONDS + 5))
  while [[ "${SECONDS}" -lt "${deadline}" ]]; do
    if [[ -f "${WIKI}/.ingest-runs.jsonl" ]] \
       && grep -Eq '"status":"(completed|failed|transient_failure|rate_limited|auth_failure|config_failure)"' \
         "${WIKI}/.ingest-runs.jsonl"; then
      echo "PASS: test_hook_dispatches_pending_capture"
      teardown
      return
    fi
    sleep 0.05
  done
  echo "FAIL: SessionStart did not produce a dispatcher run"
  [[ -f "${WIKI}/.ingest.log" ]] && tail -30 "${WIKI}/.ingest.log"
  teardown; exit 1
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

test_scheduled_mode_is_loader_only() {
  setup
  python3 "${REPO_ROOT}/scripts/wiki_config.py" update-runtime \
    --wiki "${WIKI}" --dispatch-mode scheduled >/dev/null
  cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
    "${WIKI}/.wiki-pending/scheduled-pending.md"
  printf '%s\n' "scheduled source" > "${WIKI}/inbox/scheduled-source.md"
  touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" \
    "${WIKI}/inbox/scheduled-source.md"

  local output
  output="$(cd "${WIKI}" && bash "${HOOK}")"
  sleep 0.3
  grep -q 'additionalContext' <<< "${output}" \
    || { echo "FAIL: scheduled mode lost loader output"; teardown; exit 1; }
  [[ -f "${WIKI}/.wiki-pending/scheduled-pending.md" ]] \
    || { echo "FAIL: scheduled SessionStart claimed queue work"; teardown; exit 1; }
  if compgen -G "${WIKI}/.wiki-pending/drift-*scheduled-source*" >/dev/null; then
    echo "FAIL: scheduled SessionStart scanned source material"
    teardown; exit 1
  fi
  [[ ! -s "${WIKI}/.ingest-runs.jsonl" ]] \
    || { echo "FAIL: scheduled SessionStart recorded a dispatcher run"; teardown; exit 1; }
  echo "PASS: test_scheduled_mode_is_loader_only"
  teardown
}

test_hook_emits_loader_context_in_normal_session
test_hook_emits_installed_cli_path
test_hook_emits_empty_context_in_subagent_or_ingester
test_hook_dispatches_pending_capture
test_hook_exits_fast
test_scheduled_mode_is_loader_only
echo "ALL PASS"
