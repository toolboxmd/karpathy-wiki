#!/bin/bash
# The real adapter path executes argv safely, cleans success, and retains redacted failure.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DISPATCH="${REPO_ROOT}/scripts/wiki_dispatch.py"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

make_wiki() {
  local root="$1"
  local executable="$2"
  mkdir -p "${root}/.wiki-pending"
  printf '# Schema\n' > "${root}/schema.md"
  printf '# Index\n' > "${root}/index.md"
  printf 'role = "project"\n' > "${root}/.wiki-config"
  printf '{}\n' > "${root}/.manifest.json"
  cat > "${root}/.wiki-config.local" <<EOF
[ingest]
dispatch_mode = "scheduled"
max_processes = 1
default_profile = "codex_profile"
heartbeat_seconds = 5
stale_after_seconds = 30
usage_monitor = "off"
max_attempts = 3
[ingest.profiles.codex_profile]
provider = "codex"
executable = "${executable}"
model = "exact-model-id"
reasoning_effort = "medium"
[settings]
auto_commit = false
EOF
}

wait_for() {
  local expression="$1"
  for _ in $(seq 1 300); do
    if eval "${expression}"; then return 0; fi
    sleep 0.02
  done
  return 1
}

SUCCESS_EXEC="${TESTDIR}/fake provider success"
cat > "${SUCCESS_EXEC}" <<'EOF'
#!/bin/bash
printf '<%s>\n' "$@" > "${WIKI_ROOT}/fake-argv.txt"
cat >/dev/null
bash "${WIKI_PLUGIN_ROOT}/scripts/wiki-complete-ingest.sh"
EOF
chmod +x "${SUCCESS_EXEC}"

test_real_adapter_success_path() {
  local wiki="${TESTDIR}/success wiki"
  make_wiki "${wiki}" "${SUCCESS_EXEC}"
  local canonical_wiki
  canonical_wiki="$(cd "${wiki}" && pwd -P)"
  printf '%s\n' '---' 'title: "Adapter success"' '---' > "${wiki}/.wiki-pending/x.md"
  python3 "${DISPATCH}" tick --wiki "${wiki}" --source manual
  wait_for "find '${wiki}/.wiki-pending/archive' -type f -name x.md 2>/dev/null | grep -q ." \
    || fail "real adapter did not complete capture"
  wait_for "[[ ! -e '${wiki}/.locks/ingest-slots/1.lock' ]]" || fail "successful adapter kept its slot"
  grep -Fxq '<exact-model-id>' "${wiki}/fake-argv.txt" || fail "configured model was not preserved"
  grep -Fxq '<model_reasoning_effort="medium">' "${wiki}/fake-argv.txt" || fail "configured effort was not preserved"
  grep -Fxq "<${canonical_wiki}>" "${wiki}/fake-argv.txt" || fail "wiki path with spaces was split"
  [[ ! -d "${wiki}/.locks/ingest-runs" || -z "$(find "${wiki}/.locks/ingest-runs" -mindepth 1 -maxdepth 1 -type d -print -quit)" ]] \
    || fail "clean success retained provider diagnostics"
  echo "PASS: test_real_adapter_success_path"
}

AUTH_EXEC="${TESTDIR}/fake provider auth"
cat > "${AUTH_EXEC}" <<'EOF'
#!/bin/bash
cat >/dev/null
printf '%s\n' '{"type":"error","error":{"code":"unauthorized","message":"API key=TOPSECRET login required"}}'
exit 1
EOF
chmod +x "${AUTH_EXEC}"

test_auth_failure_is_requeued_and_redacted() {
  local wiki="${TESTDIR}/auth wiki"
  make_wiki "${wiki}" "${AUTH_EXEC}"
  printf 'capture\n' > "${wiki}/.wiki-pending/x.md"
  python3 "${DISPATCH}" tick --wiki "${wiki}" --source manual
  wait_for "[[ -f '${wiki}/.wiki-pending/x.md' && ! -e '${wiki}/.locks/ingest-slots/1.lock' ]]" \
    || fail "auth failure was not requeued/released"
  grep -q 'configuration_or_auth_failure' "${wiki}/.ingest-runs.jsonl" || fail "auth failure status missing"
  grep -q '"retry_after"' "${wiki}/.ingest-runs.jsonl" || fail "auth failure did not open a bounded cooldown"
  python3 "${DISPATCH}" tick --wiki "${wiki}" --source manual
  started_count="$(grep -c '"status":"started"' "${wiki}/.ingest-runs.jsonl")"
  [[ "${started_count}" == 1 ]] || fail "auth cooldown allowed an immediate retry storm"
  if rg -q 'TOPSECRET' "${wiki}/.locks/ingest-runs"; then
    fail "retained diagnostics leaked a token"
  fi
  rg -q '\[REDACTED\]' "${wiki}/.locks/ingest-runs" || fail "retained diagnostics were not redacted"
  echo "PASS: test_auth_failure_is_requeued_and_redacted"
}

test_missing_executable_fails_before_claim() {
  local wiki="${TESTDIR}/missing executable"
  make_wiki "${wiki}" "${TESTDIR}/does not exist/provider"
  printf 'capture\n' > "${wiki}/.wiki-pending/x.md"
  python3 "${DISPATCH}" tick --wiki "${wiki}" --source manual >/dev/null 2>&1 \
    && fail "missing provider executable unexpectedly dispatched"
  [[ -f "${wiki}/.wiki-pending/x.md" ]] || fail "missing executable changed queue"
  [[ ! -d "${wiki}/.locks" ]] || fail "missing executable created runtime state before preflight"
  echo "PASS: test_missing_executable_fails_before_claim"
}

test_real_adapter_success_path
test_auth_failure_is_requeued_and_redacted
test_missing_executable_fails_before_claim
echo "ALL PASS"
