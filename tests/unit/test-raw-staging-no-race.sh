#!/bin/bash
# Verify the recovery scan and a legitimate in-flight ingester do not
# race. The ingester writes to .raw-staging/ first, atomic-renames into
# raw/ under the manifest lock; recovery acquires the same lock and
# re-checks membership, so it never picks up an in-flight file.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${REPO_ROOT}/hooks/session-start"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'sleep 0.3; rm -rf "${TESTDIR}" 2>/dev/null || true' EXIT

WIKI="${TESTDIR}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null

# Simulate an in-flight legitimate ingester: a file in .raw-staging/.
echo "in flight" > "${WIKI}/.raw-staging/inflight.md"
touch -t "$(date -v-30S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '30 seconds ago' '+%Y%m%d%H%M.%S')" "${WIKI}/.raw-staging/inflight.md"

# Drop an unrelated unmanifested file in raw/ — recovery should pick this up.
echo "user dropped this" > "${WIKI}/raw/dropped.md"
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" "${WIKI}/raw/dropped.md"

# Run hook
( cd "${WIKI}" && env -u WIKI_CAPTURE -u CLAUDE_AGENT_PARENT bash "${HOOK}" >/dev/null 2>&1 ) || true

# .raw-staging/inflight.md must be untouched (recovery skips reserved dirs)
[[ -f "${WIKI}/.raw-staging/inflight.md" ]] || fail "recovery touched .raw-staging/ (must be reserved)"

# dropped.md should be moved to inbox/
[[ -f "${WIKI}/inbox/dropped.md" ]] || fail "raw recovery did not move dropped.md"

echo "PASS: raw-staging skipped by recovery (no race)"
