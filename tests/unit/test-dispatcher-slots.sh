#!/bin/bash
# Atomic slot, mode, ordering, and failure contracts for the ingest dispatcher.
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
    [[ "${pid}" =~ ^[0-9]+$ ]] && kill "${pid}" 2>/dev/null || true
  done < <(find "${TESTDIR}" -type f -path '*/.locks/ingest-slots/*.lock' 2>/dev/null || true)
  rm -rf "${TESTDIR}"
}
trap cleanup EXIT

make_wiki() {
  local root="$1"
  local mode="${2:-scheduled}"
  local limit="${3:-3}"
  local profile_limit="${4:-${limit}}"
  mkdir -p "${root}/.wiki-pending"
  printf '# Schema\n' > "${root}/schema.md"
  printf '# Index\n' > "${root}/index.md"
  printf 'role = "project"\ncreated = "2026-08-11"\n' > "${root}/.wiki-config"
  cat > "${root}/.wiki-config.local" <<EOF
[ingest]
dispatch_mode = "${mode}"
max_processes = ${limit}
default_profile = "test_profile"
heartbeat_seconds = 5
stale_after_seconds = 30
usage_monitor = "off"

[ingest.profiles.test_profile]
provider = "codex"
model = "test-model"
reasoning_effort = "low"
max_processes = ${profile_limit}

[settings]
auto_commit = false
EOF
}

add_captures() {
  local root="$1"
  local count="$2"
  local i
  for i in $(seq -w 1 "${count}"); do
    printf '%s\n' "capture ${i}" > "${root}/.wiki-pending/${i}.md"
  done
}

tick() {
  local root="$1"
  local source="${2:-manual}"
  WIKI_DISPATCH_TEST_MODE=1 \
  WIKI_DISPATCH_TEST_WORKER_HOLD_SECONDS=10 \
    python3 "${DISPATCH}" tick --wiki "${root}" --source "${source}"
}

count_processing() {
  find "$1/.wiki-pending" -maxdepth 1 -type f -name '*.md.processing' | wc -l | tr -d ' '
}

count_leases() {
  find "$1/.locks/ingest-slots" -maxdepth 1 -type f -name '*.lock' 2>/dev/null | wc -l | tr -d ' '
}

test_one_tick_fills_only_available_slots() {
  local wiki="${TESTDIR}/bounded"
  make_wiki "${wiki}" scheduled 3 3
  add_captures "${wiki}" 20
  tick "${wiki}"
  [[ "$(count_processing "${wiki}")" -eq 3 ]] || fail "expected exactly three processing captures"
  [[ "$(count_leases "${wiki}")" -eq 3 ]] || fail "expected exactly three slot leases"
  echo "PASS: test_one_tick_fills_only_available_slots"
}

test_nonblocking_dispatch_lock_changes_nothing() {
  local wiki="${TESTDIR}/locked"
  local ready="${TESTDIR}/lock-ready"
  make_wiki "${wiki}" scheduled 3 3
  add_captures "${wiki}" 2
  mkdir -p "${wiki}/.locks"
  python3 - "${wiki}/.locks/ingest-dispatch.lock" "${ready}" <<'PY' &
import fcntl, pathlib, sys, time
path = pathlib.Path(sys.argv[1])
with path.open("a+") as handle:
    fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
    pathlib.Path(sys.argv[2]).touch()
    time.sleep(3)
PY
  local holder=$!
  for _ in $(seq 1 50); do [[ -f "${ready}" ]] && break; sleep 0.02; done
  [[ -f "${ready}" ]] || fail "lock holder did not become ready"
  tick "${wiki}" || fail "busy dispatcher lock must be a successful no-op"
  [[ "$(count_processing "${wiki}")" -eq 0 ]] || fail "busy lock changed queue"
  [[ "$(count_leases "${wiki}")" -eq 0 ]] || fail "busy lock created leases"
  kill "${holder}" 2>/dev/null || true
  wait "${holder}" 2>/dev/null || true
  echo "PASS: test_nonblocking_dispatch_lock_changes_nothing"
}

test_profile_limit_and_filename_order() {
  local wiki="${TESTDIR}/profile-limit"
  make_wiki "${wiki}" scheduled 10 2
  printf 'z\n' > "${wiki}/.wiki-pending/z.md"
  printf 'a\n' > "${wiki}/.wiki-pending/a.md"
  printf 'm\n' > "${wiki}/.wiki-pending/m.md"
  tick "${wiki}"
  [[ "$(count_leases "${wiki}")" -eq 2 ]] || fail "profile limit was not enforced"
  [[ -f "${wiki}/.wiki-pending/a.md.processing" ]] || fail "first filename was not claimed"
  [[ -f "${wiki}/.wiki-pending/m.md.processing" ]] || fail "second filename was not claimed"
  [[ -f "${wiki}/.wiki-pending/z.md" ]] || fail "claim order is not deterministic"
  echo "PASS: test_profile_limit_and_filename_order"
}

test_disappearing_capture_is_skipped() {
  local wiki="${TESTDIR}/disappearing"
  make_wiki "${wiki}" scheduled 1 1
  printf 'a\n' > "${wiki}/.wiki-pending/a.md"
  printf 'b\n' > "${wiki}/.wiki-pending/b.md"
  WIKI_DISPATCH_TEST_MODE=1 \
  WIKI_DISPATCH_TEST_REMOVE_AFTER_SCAN=a.md \
  WIKI_DISPATCH_TEST_WORKER_HOLD_SECONDS=10 \
    python3 "${DISPATCH}" tick --wiki "${wiki}" --source manual
  [[ ! -e "${wiki}/.wiki-pending/a.md" ]] || fail "test race did not remove first capture"
  [[ -f "${wiki}/.wiki-pending/b.md.processing" ]] || fail "dispatcher did not safely continue after race"
  [[ "$(count_leases "${wiki}")" -eq 1 ]] || fail "race created an incorrect lease count"
  echo "PASS: test_disappearing_capture_is_skipped"
}

test_invalid_config_has_no_queue_side_effects() {
  local wiki="${TESTDIR}/invalid"
  make_wiki "${wiki}" scheduled 2 2
  add_captures "${wiki}" 2
  sed -i.bak 's/max_processes = 2/max_processes = 0/' "${wiki}/.wiki-config.local"
  rm -f "${wiki}/.wiki-config.local.bak"
  if python3 "${DISPATCH}" tick --wiki "${wiki}" --source manual >/dev/null 2>&1; then
    fail "invalid runtime config unexpectedly dispatched"
  fi
  [[ "$(count_processing "${wiki}")" -eq 0 ]] || fail "invalid config renamed a capture"
  [[ "$(count_leases "${wiki}")" -eq 0 ]] || fail "invalid config created a lease"
  echo "PASS: test_invalid_config_has_no_queue_side_effects"
}

test_spawn_failure_requeues_and_releases() {
  local wiki="${TESTDIR}/spawn-failure"
  make_wiki "${wiki}" scheduled 1 1
  add_captures "${wiki}" 1
  WIKI_DISPATCH_TEST_MODE=1 WIKI_DISPATCH_TEST_SPAWN_FAILURE=1 \
    python3 "${DISPATCH}" tick --wiki "${wiki}" --source manual >/dev/null 2>&1 \
    && fail "injected spawn failure unexpectedly succeeded"
  [[ -f "${wiki}/.wiki-pending/1.md" ]] || fail "capture was not requeued after spawn failure"
  [[ "$(count_processing "${wiki}")" -eq 0 ]] || fail "processing file left after spawn failure"
  [[ "$(count_leases "${wiki}")" -eq 0 ]] || fail "lease left after spawn failure"
  echo "PASS: test_spawn_failure_requeues_and_releases"
}

test_tick_source_policy() {
  local scheduled="${TESTDIR}/mode-scheduled"
  local session="${TESTDIR}/mode-session"
  make_wiki "${scheduled}" scheduled 1 1
  make_wiki "${session}" session_start 1 1
  add_captures "${scheduled}" 1
  add_captures "${session}" 1

  tick "${scheduled}" session_start
  tick "${session}" scheduled
  [[ "$(count_processing "${scheduled}")" -eq 0 ]] || fail "session_start ran in scheduled mode"
  [[ "$(count_processing "${session}")" -eq 0 ]] || fail "scheduled ran in session_start mode"

  tick "${scheduled}" capture
  tick "${session}" worker_completion
  [[ "$(count_processing "${scheduled}")" -eq 1 ]] || fail "capture source should work in scheduled mode"
  [[ "$(count_processing "${session}")" -eq 1 ]] || fail "completion source should work in session_start mode"
  echo "PASS: test_tick_source_policy"
}

test_public_tick_wrapper() {
  local wiki="${TESTDIR}/public-wrapper"
  make_wiki "${wiki}" scheduled 1 1
  add_captures "${wiki}" 1
  WIKI_DISPATCH_TEST_MODE=1 WIKI_DISPATCH_TEST_WORKER_HOLD_SECONDS=10 \
    bash "${REPO_ROOT}/bin/wiki" tick "${wiki}" --source manual
  [[ "$(count_processing "${wiki}")" -eq 1 ]] || fail "public wiki tick wrapper did not dispatch"
  echo "PASS: test_public_tick_wrapper"
}

test_one_tick_fills_only_available_slots
test_nonblocking_dispatch_lock_changes_nothing
test_profile_limit_and_filename_order
test_disappearing_capture_is_skipped
test_invalid_config_has_no_queue_side_effects
test_spawn_failure_requeues_and_releases
test_tick_source_policy
test_public_tick_wrapper
echo "ALL PASS"
