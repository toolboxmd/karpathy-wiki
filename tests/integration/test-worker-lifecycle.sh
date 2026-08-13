#!/bin/bash
# Provider exit + deterministic completion + retry/failure lifecycle.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DISPATCH="${REPO_ROOT}/scripts/wiki_dispatch.py"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

make_wiki() {
  local root="$1"
  local attempts="${2:-4}"
  mkdir -p "${root}/.wiki-pending"
  printf '# Schema\n' > "${root}/schema.md"
  printf '# Index\n' > "${root}/index.md"
  printf 'role = "project"\n' > "${root}/.wiki-config"
  printf '{}\n' > "${root}/.manifest.json"
  cat > "${root}/.wiki-config.local" <<EOF
[ingest]
dispatch_mode = "scheduled"
max_processes = 1
default_profile = "p"
heartbeat_seconds = 5
stale_after_seconds = 30
usage_monitor = "off"
max_attempts = ${attempts}
[ingest.profiles.p]
provider = "codex"
model = "test"
reasoning_effort = "low"
[settings]
auto_commit = false
EOF
}

wait_for() {
  local expression="$1"
  local i
  # Detached workers can take several seconds to start on a loaded Cloud host.
  # Poll up to 20 seconds while still returning immediately on completion.
  for i in $(seq 1 1000); do
    if eval "${expression}"; then return 0; fi
    sleep 0.02
  done
  return 1
}

run_tick() {
  local wiki="$1"
  local mode="$2"
  shift 2
  env WIKI_DISPATCH_TEST_MODE=1 WIKI_DISPATCH_TEST_PROVIDER_MODE="${mode}" "$@" \
    python3 "${DISPATCH}" tick --wiki "${wiki}" --source manual
}

test_zero_exit_without_completion_is_transient() {
  local wiki="${TESTDIR}/missing-completion"
  make_wiki "${wiki}"
  printf 'capture\n' > "${wiki}/.wiki-pending/x.md"
  run_tick "${wiki}" success_no_complete WIKI_DISPATCH_TEST_NO_REFILL=1
  wait_for "[[ -f '${wiki}/.wiki-pending/x.md' && ! -e '${wiki}/.locks/ingest-slots/1.lock' ]]" \
    || fail "incomplete provider result was not requeued/released"
  python3 - "${wiki}/.ingest-runs.jsonl" <<'PY' || fail "missing transient event"
import json, sys
events = [json.loads(x) for x in open(sys.argv[1]) if x.strip()]
assert [e["status"] for e in events] == ["started", "transient_failure"]
assert events[-1]["attempt"] == 1
PY
  echo "PASS: test_zero_exit_without_completion_is_transient"
}

test_completion_archives_and_closes_once() {
  local wiki="${TESTDIR}/completed"
  make_wiki "${wiki}"
  printf '%s\n' '---' 'title: "Completed"' '---' > "${wiki}/.wiki-pending/x.md"
  run_tick "${wiki}" complete_success WIKI_DISPATCH_TEST_NO_REFILL=1
  wait_for "find '${wiki}/.wiki-pending/archive' -type f -name x.md 2>/dev/null | grep -q ." \
    || fail "successful completion was not archived"
  wait_for "[[ ! -e '${wiki}/.locks/ingest-slots/1.lock' ]]" || fail "successful worker kept lease"
  python3 - "${wiki}/.ingest-runs.jsonl" <<'PY' || fail "completion event contract failed"
import json, sys
events = [json.loads(x) for x in open(sys.argv[1]) if x.strip()]
assert sum(e["status"] == "completed" for e in events) == 1
PY
  echo "PASS: test_completion_archives_and_closes_once"
}

test_retry_limit_moves_capture_to_failed() {
  local wiki="${TESTDIR}/failed"
  make_wiki "${wiki}" 2
  printf 'capture\n' > "${wiki}/.wiki-pending/x.md"
  run_tick "${wiki}" transient_failure
  wait_for "[[ -f '${wiki}/.wiki-pending/failed/x.md' ]]" || fail "retry limit did not fail capture"
  wait_for "[[ ! -e '${wiki}/.locks/ingest-slots/1.lock' ]]" || fail "failed worker kept lease"
  python3 - "${wiki}/.ingest-runs.jsonl" <<'PY' || fail "retry attempt history incorrect"
import json, sys
events = [json.loads(x) for x in open(sys.argv[1]) if x.strip()]
transient = [e for e in events if e["status"] == "transient_failure"]
assert [e["attempt"] for e in transient] == [1, 2], transient
assert sum(e["status"] == "failed" for e in events) == 1
PY
  echo "PASS: test_retry_limit_moves_capture_to_failed"
}

test_worker_completion_refills_free_slot() {
  local wiki="${TESTDIR}/refill"
  make_wiki "${wiki}"
  printf '%s\n' '---' 'title: "One"' '---' > "${wiki}/.wiki-pending/a.md"
  printf '%s\n' '---' 'title: "Two"' '---' > "${wiki}/.wiki-pending/b.md"
  run_tick "${wiki}" complete_success
  wait_for "[[ \$(find '${wiki}/.wiki-pending/archive' -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ') -eq 2 ]]" \
    || fail "worker completion did not refill the free slot"
  echo "PASS: test_worker_completion_refills_free_slot"
}

test_rate_limit_does_not_consume_attempt() {
  local wiki="${TESTDIR}/rate-limit"
  make_wiki "${wiki}" 3
  printf 'capture\n' > "${wiki}/.wiki-pending/x.md"
  run_tick "${wiki}" rate_limited WIKI_DISPATCH_TEST_NO_REFILL=1
  wait_for "[[ -f '${wiki}/.wiki-pending/x.md' && ! -e '${wiki}/.locks/ingest-slots/1.lock' ]]" \
    || fail "rate-limited capture was not safely requeued"
  # A deliberate model change bypasses the old model's cooldown. The next
  # technical failure must still be attempt 1 because rate limits do not count.
  sed -i.bak 's/model = "test"/model = "test-2"/' "${wiki}/.wiki-config.local"
  rm -f "${wiki}/.wiki-config.local.bak"
  run_tick "${wiki}" transient_failure WIKI_DISPATCH_TEST_NO_REFILL=1
  wait_for "[[ -f '${wiki}/.wiki-pending/x.md' && ! -e '${wiki}/.locks/ingest-slots/1.lock' ]]" \
    || fail "post-rate-limit transient did not finish"
  python3 - "${wiki}/.ingest-runs.jsonl" <<'PY' || fail "rate limit consumed an attempt"
import json, sys
events = [json.loads(x) for x in open(sys.argv[1]) if x.strip()]
rate = [e for e in events if e["status"] == "provider_rate_limited"]
transient = [e for e in events if e["status"] == "transient_failure"]
assert len(rate) == 1
assert [e["attempt"] for e in transient] == [1], transient
PY
  echo "PASS: test_rate_limit_does_not_consume_attempt"
}

test_orchestrator_failure_terminates_provider_group() {
  local wiki="${TESTDIR}/provider-cleanup"
  local pid_file="${TESTDIR}/provider.pid"
  make_wiki "${wiki}"
  printf 'capture\n' > "${wiki}/.wiki-pending/x.md"
  run_tick "${wiki}" hold \
    WIKI_DISPATCH_TEST_PROVIDER_SECONDS=30 \
    WIKI_DISPATCH_TEST_HEARTBEAT_SECONDS=0.05 \
    WIKI_DISPATCH_TEST_PROVIDER_PID_FILE="${pid_file}" \
    WIKI_DISPATCH_TEST_FAIL_HEARTBEAT=1 \
    WIKI_DISPATCH_TEST_NO_REFILL=1
  wait_for "[[ -s '${pid_file}' && -f '${wiki}/.wiki-pending/x.md' && ! -e '${wiki}/.locks/ingest-slots/1.lock' ]]" \
    || fail "orchestrator failure did not clean queue state"
  local provider_pid
  provider_pid="$(cat "${pid_file}")"
  if kill -0 "${provider_pid}" 2>/dev/null; then
    fail "provider process survived orchestrator cleanup"
  fi
  echo "PASS: test_orchestrator_failure_terminates_provider_group"
}

test_needs_more_detail_is_deferred_without_retry() {
  local wiki="${TESTDIR}/needs-more-detail"
  make_wiki "${wiki}" 2
  printf 'thin capture\n' > "${wiki}/.wiki-pending/x.md"
  run_tick "${wiki}" needs_more_detail
  wait_for "[[ -f '${wiki}/.wiki-pending/x.md' && ! -e '${wiki}/.locks/ingest-slots/1.lock' ]]" \
    || fail "needs-more-detail capture was not preserved and released"
  grep -q '^needs_more_detail: true$' "${wiki}/.wiki-pending/x.md" \
    || fail "needs-more-detail marker missing from deferred capture"
  run_tick "${wiki}" needs_more_detail
  python3 - "${wiki}/.ingest-runs.jsonl" <<'PY' \
    || fail "needs-more-detail deferral consumed or repeated an attempt"
import json
import sys

events = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
assert [event["status"] for event in events] == ["started", "needs_more_detail"]
assert not any(event["status"] in {"transient_failure", "failed"} for event in events)
PY
  echo "PASS: test_needs_more_detail_is_deferred_without_retry"
}

test_zero_exit_without_completion_is_transient
test_completion_archives_and_closes_once
test_retry_limit_moves_capture_to_failed
test_worker_completion_refills_free_slot
test_rate_limit_does_not_consume_attempt
test_orchestrator_failure_terminates_provider_group
test_needs_more_detail_is_deferred_without_retry
echo "ALL PASS"
