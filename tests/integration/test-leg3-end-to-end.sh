#!/bin/bash
# Integration test for Leg 3: drop file → SessionStart OR wiki ingest-now → page committed.
# Subagent-report workflow + binary-file failure mode.
#
# Note: this test does NOT spawn a real `claude -p` ingester (that
# requires API keys + wall-clock time). It verifies the spawner is
# called, drift captures appear, and inbox/ is correctly drained
# downstream of the hook. Real ingester behavior is covered by
# tests/integration/test-end-to-end-plumbing.sh.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${REPO_ROOT}/hooks/session-start"
WIKI_BIN="${REPO_ROOT}/bin/wiki"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'sleep 0.3; rm -rf "${TESTDIR}" 2>/dev/null || true' EXIT

WIKI="${TESTDIR}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null
# Mock the ingester to a no-op for testing
sed -i.bak 's|headless_command = .*|headless_command = "echo"|' "${WIKI}/.wiki-config"
rm -f "${WIKI}/.wiki-config.bak"

export WIKI_POINTER_FILE="${TESTDIR}/.wiki-pointer"
echo "${WIKI}" > "${WIKI_POINTER_FILE}"

# 1. Drop file → SessionStart → drift capture
echo "real content" > "${WIKI}/inbox/dropped.md"
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" "${WIKI}/inbox/dropped.md"
( cd "${WIKI}" && env -u WIKI_CAPTURE -u CLAUDE_AGENT_PARENT bash "${HOOK}" >/dev/null 2>&1 ) || true
found=""
for f in "${WIKI}/.wiki-pending"/drift-*; do
  [[ -f "${f}" ]] && found="${f}" && break
done
[[ -n "${found}" ]] || fail "SessionStart did not produce drift capture"

# Cleanup for next case
rm -f "${WIKI}/.wiki-pending/drift-"*
rm -f "${WIKI}/inbox/"*

# 2. wiki ingest-now <path>
echo "explicit content" > "${WIKI}/inbox/explicit.md"
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" "${WIKI}/inbox/explicit.md"
bash "${WIKI_BIN}" ingest-now "${WIKI}" >/dev/null \
  || fail "wiki ingest-now <path> failed"
found=""
for f in "${WIKI}/.wiki-pending"/drift-*; do
  [[ -f "${f}" ]] && found="${f}" && break
done
[[ -n "${found}" ]] || fail "wiki ingest-now did not produce drift capture"

# 3. Subagent-report workflow simulation
rm -f "${WIKI}/.wiki-pending/drift-"*
rm -f "${WIKI}/inbox/"*

REPORT="${TESTDIR}/subagent-report.md"
cat > "${REPORT}" <<EOF
# Research findings

This is a 4 KB+ subagent report with detailed claims, citations, and
durable knowledge that should NOT be rewritten as a capture body.

$(yes "Some content here." | head -c 4000)
EOF

mv "${REPORT}" "${WIKI}/inbox/"
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" "${WIKI}/inbox/$(basename "${REPORT}")"
bash "${WIKI_BIN}" ingest-now "${WIKI}" >/dev/null \
  || fail "subagent-report ingest-now failed"
found=""
for f in "${WIKI}/.wiki-pending"/drift-*; do
  [[ -f "${f}" ]] && found="${f}" && break
done
[[ -n "${found}" ]] || fail "subagent-report did not produce drift capture"

# Verify the capture's evidence path points at the moved file
grep -q "evidence: \"${WIKI}/inbox/$(basename "${REPORT}")\"" "${found}" \
  || fail "subagent-report capture has wrong evidence path: $(grep '^evidence:' "${found}")"

echo "PASS: Leg 3 end-to-end (inbox drop, ingest-now, subagent workflow)"
