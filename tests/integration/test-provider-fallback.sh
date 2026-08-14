#!/bin/bash
# Reactive cooldown and optional CodexBar preflight select fallback deterministically.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DISPATCH="${REPO_ROOT}/scripts/wiki_dispatch.py"
PYTHON_BIN="$(command -v python3)"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

PROVIDER_EXEC="${TESTDIR}/fake provider"
cat > "${PROVIDER_EXEC}" <<'EOF'
#!/bin/bash
printf '<%s>\n' "$@" > "${WIKI_ROOT}/provider-argv.txt"
cat >/dev/null || true
bash "${WIKI_PLUGIN_ROOT}/scripts/wiki-complete-ingest.sh"
EOF
chmod +x "${PROVIDER_EXEC}"

make_wiki() {
  local root="$1"
  local monitor="${2:-off}"
  local primary_exec="${3:-${PROVIDER_EXEC}}"
  local fallback_exec="${4:-${PROVIDER_EXEC}}"
  mkdir -p "${root}/.wiki-pending"
  printf '# Schema\n' > "${root}/schema.md"
  printf '# Index\n' > "${root}/index.md"
  printf 'role = "project"\n' > "${root}/.wiki-config"
  printf '{}\n' > "${root}/.manifest.json"
  cat > "${root}/.wiki-config.local" <<EOF
[ingest]
dispatch_mode = "scheduled"
max_processes = 1
default_profile = "primary"
fallback_profile = "fallback"
heartbeat_seconds = 5
stale_after_seconds = 30
usage_monitor = "${monitor}"
usage_monitor_timeout_seconds = 1
rate_limit_retry_seconds = 900
[ingest.profiles.primary]
provider = "grok"
executable = "${primary_exec}"
model = "primary-model"
reasoning_effort = "medium"
usage_provider = "grok"
[ingest.profiles.fallback]
provider = "claude"
executable = "${fallback_exec}"
model = "fallback-model"
reasoning_effort = "low"
usage_provider = "claude"
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

wait_for_test_processes() {
  local pid
  for _ in $(seq 1 300); do
    pid="$(pgrep -f -- "${TESTDIR}" | head -n 1 || true)"
    [[ -z "${pid}" ]] && return 0
    sleep 0.02
  done
  ps -ef | grep -F -- "${TESTDIR}" | grep -v grep >&2 || true
  return 1
}

future="2099-01-01T00:00:00Z"
past="2020-01-01T00:00:00Z"

seed_rate_limit() {
  local wiki="$1" profile="$2" provider="$3" model="$4" retry="$5"
  printf '{"run_id":"seed-%s","capture":"seed.md","status":"provider_rate_limited","profile":"%s","provider":"%s","model":"%s","retry_after":"%s","at":"2026-08-11T00:00:00Z"}\n' \
    "${profile}" "${profile}" "${provider}" "${model}" "${retry}" >> "${wiki}/.ingest-runs.jsonl"
}

test_reactive_cooldown_uses_fallback() {
  local wiki="${TESTDIR}/reactive fallback"
  make_wiki "${wiki}" off
  seed_rate_limit "${wiki}" primary grok primary-model "${future}"
  printf '%s\n' '---' 'title: "Fallback"' '---' > "${wiki}/.wiki-pending/x.md"
  python3 "${DISPATCH}" tick --wiki "${wiki}" --source manual
  wait_for "find '${wiki}/.wiki-pending/archive' -type f -name x.md 2>/dev/null | grep -q ." || fail "fallback did not complete"
  grep -q '"profile":"fallback"' "${wiki}/.ingest-runs.jsonl" || fail "fallback profile was not selected"
  grep -Fxq '<fallback-model>' "${wiki}/provider-argv.txt" || fail "fallback model was not passed"
  echo "PASS: test_reactive_cooldown_uses_fallback"
}

test_concurrent_completion_does_not_clear_cooldown() {
  local wiki="${TESTDIR}/concurrent completion"
  make_wiki "${wiki}" off
  seed_rate_limit "${wiki}" primary grok primary-model "${future}"
  printf '%s\n' '{"run_id":"older-live-run","capture":"older.md","status":"completed","profile":"primary","provider":"grok","model":"primary-model","at":"2026-08-11T00:00:01Z"}' \
    >> "${wiki}/.ingest-runs.jsonl"
  printf '%s\n' '---' 'title: "Concurrent"' '---' > "${wiki}/.wiki-pending/x.md"
  python3 "${DISPATCH}" tick --wiki "${wiki}" --source manual
  wait_for "find '${wiki}/.wiki-pending/archive' -type f -name x.md 2>/dev/null | grep -q ." \
    || fail "fallback did not complete after a concurrent completion"
  grep -q '"profile":"fallback"' "${wiki}/.ingest-runs.jsonl" \
    || fail "concurrent completion incorrectly cleared primary cooldown"
  echo "PASS: test_concurrent_completion_does_not_clear_cooldown"
}

test_all_profiles_cooling_keeps_capture_pending() {
  local wiki="${TESTDIR}/all cooling"
  make_wiki "${wiki}" off
  seed_rate_limit "${wiki}" primary grok primary-model "${future}"
  seed_rate_limit "${wiki}" fallback claude fallback-model "${future}"
  printf 'capture\n' > "${wiki}/.wiki-pending/x.md"
  python3 "${DISPATCH}" tick --wiki "${wiki}" --source manual
  [[ -f "${wiki}/.wiki-pending/x.md" ]] || fail "all-cooling tick claimed capture"
  [[ ! -d "${wiki}/.locks/ingest-slots" ]] || fail "all-cooling tick reserved a slot"
  echo "PASS: test_all_profiles_cooling_keeps_capture_pending"
}

test_expired_or_changed_profile_is_available() {
  local expired="${TESTDIR}/expired"
  make_wiki "${expired}" off
  seed_rate_limit "${expired}" primary grok primary-model "${past}"
  printf '%s\n' '---' 'title: "Expired"' '---' > "${expired}/.wiki-pending/x.md"
  python3 "${DISPATCH}" tick --wiki "${expired}" --source manual
  wait_for "grep -q '\"profile\":\"primary\"' '${expired}/.ingest-runs.jsonl'" || fail "expired cooldown still blocked primary"

  local changed="${TESTDIR}/changed"
  make_wiki "${changed}" off
  seed_rate_limit "${changed}" primary grok old-model "${future}"
  printf '%s\n' '---' 'title: "Changed"' '---' > "${changed}/.wiki-pending/x.md"
  python3 "${DISPATCH}" tick --wiki "${changed}" --source manual
  wait_for "grep -q '\"status\":\"started\"' '${changed}/.ingest-runs.jsonl'" || fail "changed model inherited stale cooldown"
  grep -q '"profile":"primary"' "${changed}/.ingest-runs.jsonl" || fail "changed profile did not run as primary"
  echo "PASS: test_expired_or_changed_profile_is_available"
}

CODEXBAR_DIR="${TESTDIR}/codexbar-bin"
mkdir -p "${CODEXBAR_DIR}"
cat > "${CODEXBAR_DIR}/codexbar" <<'EOF'
#!/bin/bash
provider=""
while [[ $# -gt 0 ]]; do
  if [[ "$1" == "--provider" ]]; then provider="$2"; shift 2; else shift; fi
done
if [[ "${provider}" == "grok" ]]; then
  printf '%s\n' '[{"provider":"grok","usage":{"primary":{"usedPercent":100,"resetsAt":"2099-01-01T00:00:00Z"}}}]'
else
  printf '%s\n' '[{"provider":"claude","usage":{"primary":{"usedPercent":20,"resetsAt":"2099-01-01T00:00:00Z"}}}]'
fi
EOF
chmod +x "${CODEXBAR_DIR}/codexbar"

test_codexbar_exhaustion_uses_fallback() {
  local wiki="${TESTDIR}/codexbar fallback"
  make_wiki "${wiki}" auto
  printf '%s\n' '---' 'title: "CodexBar"' '---' > "${wiki}/.wiki-pending/x.md"
  PATH="${CODEXBAR_DIR}:${PATH}" "${PYTHON_BIN}" "${DISPATCH}" tick --wiki "${wiki}" --source manual
  if ! wait_for "find '${wiki}/.wiki-pending/archive' -type f -name x.md 2>/dev/null | grep -q ."; then
    [[ -f "${wiki}/.ingest.log" ]] && sed -n '1,160p' "${wiki}/.ingest.log" >&2
    [[ -f "${wiki}/.ingest-runs.jsonl" ]] && sed -n '1,160p' "${wiki}/.ingest-runs.jsonl" >&2
    while IFS= read -r diagnostic; do
      echo "--- ${diagnostic}" >&2
      sed -n '1,160p' "${diagnostic}" >&2
    done < <(find "${wiki}/.locks/ingest-runs" -type f 2>/dev/null | sort)
    fail "CodexBar fallback did not complete"
  fi
  grep -q '"profile":"fallback"' "${wiki}/.ingest-runs.jsonl" || fail "CodexBar did not select fallback"
  echo "PASS: test_codexbar_exhaustion_uses_fallback"
}

RATE_LIMIT_EXEC="${TESTDIR}/fake provider rate limit"
cat > "${RATE_LIMIT_EXEC}" <<'EOF'
#!/bin/bash
cat >/dev/null || true
printf '%s\n' '{"type":"error","error":{"code":"rate_limit","message":"usage limit reached"}}'
exit 1
EOF
chmod +x "${RATE_LIMIT_EXEC}"

AUTH_EXEC="${TESTDIR}/fake provider auth failure"
cat > "${AUTH_EXEC}" <<'EOF'
#!/bin/bash
cat >/dev/null || true
printf '%s\n' '{"type":"error","error":{"code":"unauthorized","message":"login required"}}'
exit 1
EOF
chmod +x "${AUTH_EXEC}"

test_live_provider_failure_refills_with_fallback() {
  local failure_kind primary_exec wiki
  for failure_kind in rate-limit auth; do
    if [[ "${failure_kind}" == "rate-limit" ]]; then
      primary_exec="${RATE_LIMIT_EXEC}"
    else
      primary_exec="${AUTH_EXEC}"
    fi
    wiki="${TESTDIR}/live-${failure_kind}"
    make_wiki "${wiki}" off "${primary_exec}" "${PROVIDER_EXEC}"
    printf '%s\n' '---' "title: \"${failure_kind}\"" '---' > "${wiki}/.wiki-pending/x.md"
    python3 "${DISPATCH}" tick --wiki "${wiki}" --source manual
    wait_for "find '${wiki}/.wiki-pending/archive' -type f -name x.md 2>/dev/null | grep -q ." \
      || fail "${failure_kind} did not immediately refill with fallback"
    grep -q '"profile":"fallback"' "${wiki}/.ingest-runs.jsonl" \
      || fail "${failure_kind} did not select fallback without another tick"
  done
  echo "PASS: test_live_provider_failure_refills_with_fallback"
}

test_reactive_cooldown_uses_fallback
test_concurrent_completion_does_not_clear_cooldown
test_all_profiles_cooling_keeps_capture_pending
test_expired_or_changed_profile_is_available
test_codexbar_exhaustion_uses_fallback
test_live_provider_failure_refills_with_fallback
wait_for_test_processes || fail "detached provider workers did not exit before cleanup"
echo "ALL PASS"
