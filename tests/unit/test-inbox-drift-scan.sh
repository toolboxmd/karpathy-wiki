#!/bin/bash
# Verify SessionStart hook scans inbox/ and creates raw-direct captures.
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
# Override headless_command to no-op
sed -i.bak 's|headless_command = .*|headless_command = "echo"|' "${WIKI}/.wiki-config"
rm -f "${WIKI}/.wiki-config.bak"

# Drop a file in inbox/ with mtime in the past (so it's not deferred)
printf '# Test note\n\nSome content for ingestion.\n' > "${WIKI}/inbox/note.md"
# Make it 10 seconds old so the 5-second mtime defer doesn't apply
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" "${WIKI}/inbox/note.md"

# Run the SessionStart hook with cwd = WIKI
( cd "${WIKI}" && env -u WIKI_CAPTURE -u CLAUDE_AGENT_PARENT bash "${HOOK}" >/dev/null 2>&1 ) || true

# Assert a raw-direct capture appeared in .wiki-pending/
ls "${WIKI}/.wiki-pending/" | grep -q '^drift-' \
  || fail "no drift- capture appeared in .wiki-pending/"

# Inspect the capture frontmatter for capture_kind: raw-direct
capture=$(ls "${WIKI}/.wiki-pending/drift-"*.md 2>/dev/null | head -1)
[[ -n "${capture}" ]] || fail "no drift- capture matches glob"
grep -q 'capture_kind: "raw-direct"' "${capture}" \
  || fail "drift capture missing capture_kind: raw-direct"
grep -q "evidence: \"${WIKI}/inbox/note.md\"" "${capture}" \
  || fail "drift capture evidence path wrong: $(grep '^evidence:' "${capture}")"

echo "PASS: inbox/ drift scan creates raw-direct captures"
