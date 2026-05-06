#!/bin/bash
# Verify bin/wiki capture body-input contract, headless fallback,
# orphan preservation. Does NOT spawn a real ingester (uses a mock
# headless_command).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WIKI_BIN="${REPO_ROOT}/bin/wiki"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

MAIN="${TESTDIR}/main"
bash "${INIT}" main "${MAIN}" >/dev/null
# Override headless_command with no-op for testing
sed -i.bak 's|headless_command = .*|headless_command = "echo"|' "${MAIN}/.wiki-config"
rm -f "${MAIN}/.wiki-config.bak"

# Hermetic $HOME — required so bin/wiki capture's silent-bootstrap branch
# (added in 0.2.7) doesn't read the developer's real ~/wiki when this test
# unsets WIKI_POINTER_FILE.
FAKE_HOME="${TESTDIR}/home"
mkdir -p "${FAKE_HOME}"
export HOME="${FAKE_HOME}"
export WIKI_POINTER_FILE="${TESTDIR}/.wiki-pointer"
echo "${MAIN}" > "${WIKI_POINTER_FILE}"
export HOME_FOR_ORPHANS="${FAKE_HOME}"
export WIKI_ORPHANS_DIR="${HOME_FOR_ORPHANS}/.wiki-orphans"
export CLAUDE_HEADLESS=1  # Force headless mode in tests

# Case 1: chat-only via stdin
PROJ="${TESTDIR}/proj"
mkdir -p "${PROJ}"
echo "main-only" > "${PROJ}/.wiki-mode"
BODY=$(printf 'A real chat-only body that exceeds 1500 bytes.\n%.0s' {1..40})
( cd "${PROJ}" && echo "${BODY}" | bash "${WIKI_BIN}" capture --title "Test" --kind chat-only --suggested-action create ) >/dev/null \
  || fail "chat-only via stdin failed"
ls "${MAIN}/.wiki-pending/" | grep -q '\.md$' || fail "no capture appeared in main pending"

# Case 2: chat-only via --body-file
TMPBODY="$(mktemp)"
echo "${BODY}" > "${TMPBODY}"
( cd "${PROJ}" && bash "${WIKI_BIN}" capture --title "Test2" --kind chat-only --suggested-action create --body-file "${TMPBODY}" ) >/dev/null \
  || fail "chat-only via --body-file failed"

# Case 3: missing body (no stdin, no --body-file) → error
( cd "${PROJ}" && bash "${WIKI_BIN}" capture --title "Test3" --kind chat-only --suggested-action create < /dev/null ) 2>/dev/null \
  && fail "missing body should error"

# Case 4: max-body limit (256 KB)
HUGE_BODY=$(yes "x" | head -c 270000)
( cd "${PROJ}" && echo "${HUGE_BODY}" | bash "${WIKI_BIN}" capture --title "Huge" --kind chat-only --suggested-action create ) 2>/dev/null \
  && fail "body > 256 KB should error"

# Case 5: headless + unconfigured cwd + no pointer → orphan-preserve
rm -f "${WIKI_POINTER_FILE}"
SCRATCH="${TESTDIR}/scratch"
mkdir -p "${SCRATCH}"
( cd "${SCRATCH}" && echo "${BODY}" | bash "${WIKI_BIN}" capture --title "OrphanTest" --kind chat-only --suggested-action create ) 2>/dev/null \
  && fail "headless + no pointer + unconfigured cwd should abort"
[[ -d "${WIKI_ORPHANS_DIR}" ]] || fail "no orphan dir created"
ls "${WIKI_ORPHANS_DIR}/" | grep -q '\.md$' || fail "no orphan file in $WIKI_ORPHANS_DIR/"

# Case 6: headless + unconfigured cwd + valid pointer → auto-select main-only
echo "${MAIN}" > "${WIKI_POINTER_FILE}"
SCRATCH2="${TESTDIR}/scratch2"
mkdir -p "${SCRATCH2}"
( cd "${SCRATCH2}" && echo "${BODY}" | bash "${WIKI_BIN}" capture --title "AutoMain" --kind chat-only --suggested-action create ) >/dev/null \
  || fail "headless + valid pointer + unconfigured should auto-select main-only"
[[ -f "${SCRATCH2}/.wiki-mode" ]] || fail "auto-select main-only did not write .wiki-mode"
[[ "$(cat "${SCRATCH2}/.wiki-mode")" == "main-only" ]] || fail ".wiki-mode != main-only"

echo "PASS: bin/wiki capture body input + headless fallback + orphan preservation"
