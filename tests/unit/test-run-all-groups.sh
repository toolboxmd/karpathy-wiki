#!/bin/bash
# Contract for the focused-group interface in tests/run-all.sh.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
RUNNER="${TESTS_DIR}/run-all.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

list_group() {
  local group="$1"
  python3 - "${RUNNER}" "${group}" <<'PY'
import os
import signal
import subprocess
import sys

runner, group = sys.argv[1:]
process = subprocess.Popen(
    ["bash", runner, "--list", group],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    start_new_session=True,
)
try:
    stdout, stderr = process.communicate(timeout=2)
except subprocess.TimeoutExpired:
    os.killpg(process.pid, signal.SIGTERM)
    process.communicate()
    print(f"runner did not return a list for group {group!r}", file=sys.stderr)
    raise SystemExit(1)
if process.returncode != 0:
    print(stderr, file=sys.stderr, end="")
    raise SystemExit(process.returncode)
sys.stdout.write(stdout)
PY
}

test_lists_non_empty_focused_groups() {
  local group output
  for group in skill capture scanner dispatcher provider config scheduler schema full-only; do
    output="$(list_group "${group}")" || fail "could not list ${group}"
    grep -q "^selected group: ${group}$" <<< "${output}" \
      || fail "${group} output does not identify the selected group"
    grep -Eq '^(unit|integration)/test-.*\.sh$' <<< "${output}" \
      || fail "${group} selected no tests"
  done
  echo "PASS: test_lists_non_empty_focused_groups"
}

test_full_lists_every_discovered_test_once() {
  local expected actual
  expected="$(
    find "${TESTS_DIR}/unit" "${TESTS_DIR}/integration" \
      -maxdepth 1 -type f -name 'test-*.sh' \
      | sed "s#^${TESTS_DIR}/##" \
      | sort
  )"
  actual="$(list_group full | grep -E '^(unit|integration)/test-.*\.sh$' | sort)"
  [[ "${actual}" == "${expected}" ]] \
    || fail "full group does not contain every discovered test exactly once"
  echo "PASS: test_full_lists_every_discovered_test_once"
}

test_unknown_group_fails_clearly() {
  local output status
  set +e
  output="$(bash "${RUNNER}" --list definitely-not-a-group 2>&1)"
  status=$?
  set -e
  [[ "${status}" -ne 0 ]] || fail "unknown group reported success"
  grep -q 'unknown test group: definitely-not-a-group' <<< "${output}" \
    || fail "unknown group error is not actionable"
  echo "PASS: test_unknown_group_fails_clearly"
}

test_lists_non_empty_focused_groups
test_full_lists_every_discovered_test_once
test_unknown_group_fails_clearly
echo "ALL PASS"
