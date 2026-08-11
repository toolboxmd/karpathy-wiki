#!/bin/bash
# Verify the 5-second mtime defer protects against partial writes.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCAN="${REPO_ROOT}/scripts/wiki-scan.sh"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
cleanup() {
  # SessionStart detaches the test ingester. On macOS, rm can briefly race
  # with that child creating its final processing/log entry and report
  # "Directory not empty" even though the assertion already passed.
  local attempt
  for attempt in {1..20}; do
    rm -rf "${TESTDIR}" 2>/dev/null && return 0
    sleep 0.05
  done
  rm -rf "${TESTDIR}"
}
trap cleanup EXIT

WIKI="${TESTDIR}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null

# Drop a file with mtime = NOW (within 5s)
echo "fresh content" > "${WIKI}/inbox/fresh.md"
touch "${WIKI}/inbox/fresh.md"

# Run scanner — should defer
bash "${SCAN}" "${WIKI}" >/dev/null

# No drift- capture should appear yet (the inbox emit was skipped due to defer).
for f in "${WIKI}/.wiki-pending"/drift-*; do
  [[ -f "${f}" ]] && fail "fresh-mtime file was not deferred: ${f}"
done

# Wait > 5 seconds and re-run
sleep 6
bash "${SCAN}" "${WIKI}" >/dev/null

# Now a capture SHOULD appear
found=""
for f in "${WIKI}/.wiki-pending"/drift-*; do
  [[ -f "${f}" ]] || continue
  found="${f}"; break
done
[[ -n "${found}" ]] || fail "after 6s wait, drift capture should appear"

echo "PASS: 5-second mtime defer"
