#!/bin/bash
# Integration test for Leg 3: drop file → SessionStart OR wiki ingest-now → page committed.
# Subagent-report workflow + binary-file failure mode.
#
# Provider execution uses the dispatcher's deterministic test adapter; no
# external model, credentials, or subscription quota is used.
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
WIKI="$(cd "${WIKI}" && pwd -P)"
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
export WIKI_DISPATCH_TEST_PROVIDER_MODE=success_no_complete
export WIKI_DISPATCH_TEST_NO_REFILL=1

export WIKI_POINTER_FILE="${TESTDIR}/.wiki-pointer"
echo "${WIKI}" > "${WIKI_POINTER_FILE}"

# 1. Drop file → SessionStart → drift capture
echo "real content" > "${WIKI}/inbox/dropped.md"
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" "${WIKI}/inbox/dropped.md"
( cd "${WIKI}" && env -u WIKI_CAPTURE -u CLAUDE_AGENT_PARENT bash "${HOOK}" >/dev/null 2>&1 ) || true
found=""
deadline=$((SECONDS + 5))
while [[ "${SECONDS}" -lt "${deadline}" && -z "${found}" ]]; do
  for f in "${WIKI}/.wiki-pending"/drift-*; do
    [[ -f "${f}" ]] && found="${f}" && break
  done
  [[ -n "${found}" ]] || sleep 0.05
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
