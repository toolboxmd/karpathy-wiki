#!/bin/bash
# Stale dead leases recover; stale live providers are never duplicated.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DISPATCH="${REPO_ROOT}/scripts/wiki_dispatch.py"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
cleanup() {
  local lease pid
  while IFS= read -r lease; do
    [[ -n "${lease}" ]] || continue
    pid="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("wrapper_pid", ""))' "${lease}" 2>/dev/null || true)"
    if [[ "${pid}" =~ ^[0-9]+$ && "${pid}" -ne "$$" ]]; then kill "${pid}" 2>/dev/null || true; fi
  done < <(find "${TESTDIR}" -type f -path '*/.locks/ingest-slots/*.lock' 2>/dev/null || true)
  rm -rf "${TESTDIR}"
}
trap cleanup EXIT

make_wiki() {
  local root="$1"
  mkdir -p "${root}/.wiki-pending" "${root}/.locks/ingest-slots"
  printf '# Schema\n' > "${root}/schema.md"
  printf '# Index\n' > "${root}/index.md"
  printf 'role = "project"\n' > "${root}/.wiki-config"
  cat > "${root}/.wiki-config.local" <<'EOF'
[ingest]
dispatch_mode = "scheduled"
max_processes = 1
default_profile = "p"
heartbeat_seconds = 5
stale_after_seconds = 15
usage_monitor = "off"
[ingest.profiles.p]
provider = "codex"
model = "test"
reasoning_effort = "low"
[settings]
auto_commit = false
EOF
}

write_lease() {
  local root="$1"
  local run_id="$2"
  local wrapper_pid="$3"
  local provider_pid="$4"
  cat > "${root}/.locks/ingest-slots/1.lock" <<EOF
{"attempt":1,"capture":"x.md.processing","expected_archive":".wiki-pending/archive/2026-08/x.md","profile":"p","provider":"codex","provider_pid":${provider_pid},"run_id":"${run_id}","slot":1,"started_at":"2026-08-11T00:00:00Z","wrapper_pid":${wrapper_pid}}
EOF
}

make_stale() {
  python3 -c 'import os,sys,time; old=time.time()-60; os.utime(sys.argv[1], (old, old))' "$1"
}

test_dead_stale_lease_is_reclaimed_once() {
  local wiki="${TESTDIR}/dead"
  make_wiki "${wiki}"
  printf 'capture\n' > "${wiki}/.wiki-pending/x.md.processing"
  make_stale "${wiki}/.wiki-pending/x.md.processing"
  write_lease "${wiki}" dead-run 999991 999992

  WIKI_DISPATCH_TEST_MODE=1 WIKI_DISPATCH_TEST_PROVIDER_MODE=hold \
  WIKI_DISPATCH_TEST_PROVIDER_SECONDS=10 WIKI_DISPATCH_TEST_NO_REFILL=1 \
    python3 "${DISPATCH}" tick --wiki "${wiki}" --source manual

  [[ -f "${wiki}/.wiki-pending/x.md.processing" ]] || fail "recovered capture was not reclaimed"
  [[ "$(find "${wiki}/.locks/ingest-slots" -type f -name '*.lock' | wc -l | tr -d ' ')" -eq 1 ]] \
    || fail "dead reconciliation produced duplicate leases"
  if grep -q 'dead-run' "${wiki}/.locks/ingest-slots/1.lock"; then
    fail "dead lease was not replaced"
  fi
  echo "PASS: test_dead_stale_lease_is_reclaimed_once"
}

test_live_stale_lease_is_preserved_and_flagged() {
  local wiki="${TESTDIR}/live"
  make_wiki "${wiki}"
  printf 'capture\n' > "${wiki}/.wiki-pending/x.md.processing"
  make_stale "${wiki}/.wiki-pending/x.md.processing"
  write_lease "${wiki}" live-run $$ $$

  WIKI_DISPATCH_TEST_MODE=1 \
    python3 "${DISPATCH}" tick --wiki "${wiki}" --source manual
  grep -q 'live-run' "${wiki}/.locks/ingest-slots/1.lock" || fail "live stale lease was replaced"
  [[ "$(find "${wiki}/.wiki-pending" -maxdepth 1 -type f | wc -l | tr -d ' ')" -eq 1 ]] \
    || fail "live stale capture was duplicated"
  python3 - "${wiki}/.ingest-runs.jsonl" <<'PY' || fail "heartbeat stall event missing"
import json, sys
events = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
assert len(events) == 1
assert events[0]["run_id"] == "live-run"
assert events[0]["status"] == "heartbeat_stalled"
PY
  rm -f "${wiki}/.locks/ingest-slots/1.lock"
  echo "PASS: test_live_stale_lease_is_preserved_and_flagged"
}

test_dead_stale_lease_is_reclaimed_once
test_live_stale_lease_is_preserved_and_flagged
echo "ALL PASS"
