#!/bin/bash
# Verify the 5-second mtime defer protects against partial writes.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${REPO_ROOT}/hooks/session-start"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

WIKI="${TESTDIR}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null
sed -i.bak 's|headless_command = .*|headless_command = "echo"|' "${WIKI}/.wiki-config"
rm -f "${WIKI}/.wiki-config.bak"

# Drop a file with mtime = NOW (within 5s)
echo "fresh content" > "${WIKI}/inbox/fresh.md"
touch "${WIKI}/inbox/fresh.md"

# Run hook — should defer
( cd "${WIKI}" && env -u WIKI_CAPTURE -u CLAUDE_AGENT_PARENT bash "${HOOK}" >/dev/null 2>&1 ) || true

# No drift- capture should appear yet (the inbox emit was skipped due to defer).
for f in "${WIKI}/.wiki-pending"/drift-*; do
  [[ -f "${f}" ]] && fail "fresh-mtime file was not deferred: ${f}"
done

# Wait > 5 seconds and re-run
sleep 6
( cd "${WIKI}" && env -u WIKI_CAPTURE -u CLAUDE_AGENT_PARENT bash "${HOOK}" >/dev/null 2>&1 ) || true

# Now a capture SHOULD appear
found=""
for f in "${WIKI}/.wiki-pending"/drift-*; do
  [[ -f "${f}" ]] || continue
  found="${f}"; break
done
[[ -n "${found}" ]] || fail "after 6s wait, drift capture should appear"

echo "PASS: 5-second mtime defer"
