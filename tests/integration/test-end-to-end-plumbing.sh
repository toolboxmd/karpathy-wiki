#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

setup() {
  TESTDIR="$(mktemp -d)"
  WIKI="${TESTDIR}/wiki"
  bash "${REPO_ROOT}/scripts/wiki-init.sh" main "${WIKI}" >/dev/null
  cat > "${WIKI}/.wiki-config.local" <<'EOF'
[ingest]
dispatch_mode = "session_start"
max_processes = 1
default_profile = "test"
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
  export WIKI_DISPATCH_TEST_PROVIDER_MODE=hold
  export WIKI_DISPATCH_TEST_PROVIDER_SECONDS=30
  export WIKI_DISPATCH_TEST_NO_REFILL=1
}

teardown() {
  local lease pid
  for lease in "${WIKI}/.locks/ingest-slots"/*.lock; do
    [[ -f "${lease}" ]] || continue
    while IFS= read -r pid; do
      [[ "${pid}" =~ ^[0-9]+$ ]] && kill "${pid}" 2>/dev/null || true
    done < <(python3 - "${lease}" <<'PY'
import json
import sys
try:
    data = json.load(open(sys.argv[1], encoding="utf-8"))
except Exception:
    data = {}
for key in ("provider_pid", "wrapper_pid"):
    if isinstance(data.get(key), int) and data[key] > 0:
        print(data[key])
PY
)
  done
  sleep 0.1
  rm -rf "${TESTDIR}"
}

test_capture_drop_plus_hook_plus_dispatch() {
  setup

  # Drop a capture
  cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
     "${WIKI}/.wiki-pending/2026-04-22T14-30-test.md"

  # Run session-start hook
  (cd "${WIKI}" && bash "${REPO_ROOT}/hooks/session-start") >/dev/null

  # Wait for durable lifecycle evidence rather than racing a fixed startup
  # budget. The outer bound still fails promptly if dispatch never starts.
  deadline=$((SECONDS + 30))
  while [[ "${SECONDS}" -lt "${deadline}" ]]; do
    if grep -q '"status":"started"' "${WIKI}/.ingest-runs.jsonl" 2>/dev/null; then
      [[ -f "${WIKI}/.wiki-pending/2026-04-22T14-30-test.md.processing" ]] || {
        echo "FAIL: dispatcher recorded started without retaining claimed queue state"
        cat "${WIKI}/.ingest-runs.jsonl"
        [[ -f "${WIKI}/.ingest.log" ]] && cat "${WIKI}/.ingest.log"
        teardown; exit 1
      }
      echo "PASS: test_capture_drop_plus_hook_plus_dispatch"
      teardown
      return
    fi
    sleep 0.05
  done
  echo "FAIL: bounded dispatcher never recorded a started lifecycle event"
  ls -la "${WIKI}/.wiki-pending/"
  [[ -f "${WIKI}/.ingest.log" ]] && cat "${WIKI}/.ingest.log"
  teardown; exit 1
  teardown
}

test_fork_bomb_guard_short_circuits_inside_ingester() {
  # Regression: a SessionStart hook invoked with WIKI_CAPTURE set must do
  # nothing (no drift scan, no drain), because that env var marks the caller
  # as a headless ingester. Without this guard the hook would re-spawn N more
  # ingesters inside every ingester, exploding to thousands of processes.
  setup

  # Drop a pending capture that WOULD be drained on a normal SessionStart.
  cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
     "${WIKI}/.wiki-pending/2026-04-22T14-30-fork-test.md"

  # Run hook with WIKI_CAPTURE set, simulating a spawned ingester.
  ( cd "${WIKI}" && WIKI_CAPTURE="${WIKI}/.wiki-pending/some-other-capture.md" \
      bash "${REPO_ROOT}/hooks/session-start" ) >/dev/null

  # Capture must NOT be claimed and no dispatcher run may be recorded.
  if [[ ! -f "${WIKI}/.wiki-pending/2026-04-22T14-30-fork-test.md" ]]; then
    echo "FAIL: fork-bomb guard did not fire — capture was drained"
    teardown; exit 1
  fi
  if [[ -s "${WIKI}/.ingest-runs.jsonl" ]]; then
    echo "FAIL: fork-bomb guard did not fire — dispatcher run was recorded"
    teardown; exit 1
  fi

  echo "PASS: test_fork_bomb_guard_short_circuits_inside_ingester"
  teardown
}

test_drift_filenames_with_spaces_handled_correctly() {
  # Regression: drift code used `awk '{print $2}'` which truncates filenames
  # at the first space. Two raw files like `Claude Code's Limits...md` and
  # `Post by @PawelHuryn on X.md` got recorded as evidence: raw/Claude and
  # raw/Post (paths that don't exist), causing every SessionStart to re-flag
  # them as NEW (the manifest never updated, drift never settled).
  setup

  # Drop a raw file with spaces in its name (no manifest entry yet).
  echo "test content" > "${WIKI}/raw/File With Spaces In Name.md"
  # v2.4: backdate so the 5-second mtime defer doesn't apply.
  touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" "${WIKI}/raw/File With Spaces In Name.md"

  # Run hook (NOT inside an ingester).
  (cd "${WIKI}" && bash "${REPO_ROOT}/hooks/session-start") >/dev/null
  # SessionStart dispatch is detached. Wait for the worker to claim the drift
  # capture so the filename is stable while the test reads it.
  for _ in $(seq 1 100); do
    compgen -G "${WIKI}/.wiki-pending/*drift*.processing" >/dev/null && break
    sleep 0.1
  done

  # Find the claimed drift capture.
  local found_capture=""
  for f in "${WIKI}/.wiki-pending"/*drift*.processing; do
    [[ -f "${f}" ]] || continue
    found_capture="${f}"
    break
  done

  if [[ -z "${found_capture}" ]]; then
    echo "FAIL: no drift capture created for raw file with spaces"
    teardown; exit 1
  fi

  # Capture's evidence path must point at the actual file, not a truncated one.
  local evidence_path
  evidence_path="$(grep -m1 '^evidence:' "${found_capture}" | sed 's/^evidence: *"//; s/"$//')"
  if [[ ! -f "${evidence_path}" ]]; then
    echo "FAIL: evidence path '${evidence_path}' does not exist (truncated at space?)"
    cat "${found_capture}"
    teardown; exit 1
  fi

  echo "PASS: test_drift_filenames_with_spaces_handled_correctly"
  teardown
}

test_drift_capture_body_clears_200_byte_floor() {
  # Regression: drift captures had 75-byte bodies, well below the
  # evidence_type=file 200-byte floor. Ingesters rejected every drift
  # capture with needs_more_detail, so .wiki-pending/ filled with dust
  # and the underlying raw files never got ingested.
  setup

  echo "drift body content" > "${WIKI}/raw/drift-body-test.md"
  # v2.4: backdate so the 5-second mtime defer doesn't apply.
  touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" "${WIKI}/raw/drift-body-test.md"
  (cd "${WIKI}" && bash "${REPO_ROOT}/hooks/session-start") >/dev/null
  for _ in $(seq 1 100); do
    compgen -G "${WIKI}/.wiki-pending/*drift*drift-body-test*.processing" >/dev/null && break
    sleep 0.1
  done

  # Read only after the worker claim makes the capture name stable.
  local cap=""
  for f in "${WIKI}/.wiki-pending"/*drift*drift-body-test*.processing; do
    [[ -f "${f}" ]] && cap="${f}" && break
  done

  if [[ -z "${cap}" ]]; then
    echo "FAIL: drift capture not created"
    teardown; exit 1
  fi

  # Extract body (everything after the SECOND ---) and measure.
  local body_size
  body_size="$(awk '/^---$/{c++; next} c==2' "${cap}" | wc -c | tr -d ' ')"
  if [[ "${body_size}" -lt 200 ]]; then
    echo "FAIL: drift body is ${body_size} bytes, below 200-byte floor"
    teardown; exit 1
  fi

  echo "PASS: test_drift_capture_body_clears_200_byte_floor (${body_size} bytes)"
  teardown
}

test_drift_idempotent_under_concurrent_session_starts() {
  # Regression: with %H-%M filename granularity and a non-atomic [[ -f ]] check,
  # two SessionStart hooks firing in the same minute could both write the same
  # drift capture filename (race between stat and cat>). Result: 2-3x duplicate
  # captures per minute during the fork bomb.
  setup

  echo "drift-source" > "${WIKI}/raw/concurrent-test.md"
  # v2.4: backdate so the 5-second mtime defer doesn't apply.
  touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" "${WIKI}/raw/concurrent-test.md"

  # Start one detached scan/dispatch lifecycle and wait until its worker owns
  # the capture. Further SessionStarts then scan concurrently with that live
  # processing owner, exercising idempotency across both queue states.
  (cd "${WIKI}" && bash "${REPO_ROOT}/hooks/session-start") >/dev/null
  for _ in $(seq 1 100); do
    compgen -G "${WIKI}/.wiki-pending/*drift*concurrent-test*.processing" >/dev/null && break
    sleep 0.1
  done
  compgen -G "${WIKI}/.wiki-pending/*drift*concurrent-test*.processing" >/dev/null \
    || { echo "FAIL: first SessionStart did not establish a processing owner"; teardown; exit 1; }

  # Fire four more hooks while the held worker still owns the first capture.
  local i
  for i in 1 2 3 4; do
    (cd "${WIKI}" && bash "${REPO_ROOT}/hooks/session-start") >/dev/null &
  done
  wait
  for _ in $(seq 1 200); do
    if compgen -G "${WIKI}/.wiki-pending/*drift*concurrent-test*.md" >/dev/null \
      || grep -q 'scan: raw-direct capture already owned: .*concurrent-test' "${WIKI}/.ingest.log" 2>/dev/null; then
      break
    fi
    sleep 0.1
  done

  # Count drift captures for this source.
  local count
  count="$(find "${WIKI}/.wiki-pending" -maxdepth 1 -name "*drift*concurrent-test*" -type f 2>/dev/null | wc -l | tr -d ' ')"

  if [[ "${count}" -eq 0 ]]; then
    echo "FAIL: concurrent SessionStart did not create a drift capture"
    teardown; exit 1
  fi

  if [[ "${count}" -gt 1 ]]; then
    echo "FAIL: ${count} duplicate drift captures created under concurrent SessionStart"
    ls "${WIKI}/.wiki-pending/" | grep concurrent
    if [[ "${WIKI_TEST_PRESERVE_FAILURES:-0}" == "1" ]]; then
      echo "PRESERVED: ${TESTDIR}"
      return 1
    fi
    teardown; exit 1
  fi

  echo "PASS: test_drift_idempotent_under_concurrent_session_starts (count=${count})"
  teardown
}

test_capture_drop_plus_hook_plus_dispatch
test_fork_bomb_guard_short_circuits_inside_ingester
test_drift_filenames_with_spaces_handled_correctly
test_drift_capture_body_clears_200_byte_floor
test_drift_idempotent_under_concurrent_session_starts
echo "ALL PASS"
