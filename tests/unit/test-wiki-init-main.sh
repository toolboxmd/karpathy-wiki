#!/bin/bash
# Verify wiki-init-main.sh bootstraps ~/.wiki-pointer correctly.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INIT_MAIN="${REPO_ROOT}/scripts/wiki-init-main.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

export WIKI_POINTER_FILE="${TESTDIR}/.wiki-pointer"
export WIKI_INIT_MAIN_HOME="${TESTDIR}/home"  # Override $HOME-scan root for testing
mkdir -p "${WIKI_INIT_MAIN_HOME}"

# Case 1: silent migration when a unique main wiki exists at depth ≤ 2
bash "${REPO_ROOT}/scripts/wiki-init.sh" main "${WIKI_INIT_MAIN_HOME}/wiki" >/dev/null
echo "n" | bash "${INIT_MAIN}" 2>/dev/null  # 'n' is a safe choice if the script prompts
[[ -f "${WIKI_POINTER_FILE}" ]] || fail "silent migration: pointer not written"
[[ "$(cat "${WIKI_POINTER_FILE}")" == "${WIKI_INIT_MAIN_HOME}/wiki" ]] \
  || fail "silent migration: pointer points at wrong path: $(cat "${WIKI_POINTER_FILE}")"

# Case 2: pointer-already-exists no-op
mtime_before=$(stat -f %m "${WIKI_POINTER_FILE}" 2>/dev/null || stat -c %Y "${WIKI_POINTER_FILE}")
sleep 1
bash "${INIT_MAIN}" >/dev/null 2>&1
mtime_after=$(stat -f %m "${WIKI_POINTER_FILE}" 2>/dev/null || stat -c %Y "${WIKI_POINTER_FILE}")
[[ "${mtime_before}" == "${mtime_after}" ]] || fail "pointer-already-exists: pointer was rewritten"

# Case 3: 'none' choice (no main wiki)
rm -f "${WIKI_POINTER_FILE}"
rm -rf "${WIKI_INIT_MAIN_HOME}"
mkdir -p "${WIKI_INIT_MAIN_HOME}"
# Simulate user choosing 2 (no main wiki)
echo "2" | bash "${INIT_MAIN}" 2>/dev/null
[[ "$(cat "${WIKI_POINTER_FILE}")" == "none" ]] \
  || fail "'no main' choice: pointer should be 'none'"

# Case 4: multi-candidate prompt
rm -f "${WIKI_POINTER_FILE}"
rm -rf "${WIKI_INIT_MAIN_HOME}"
mkdir -p "${WIKI_INIT_MAIN_HOME}"
bash "${REPO_ROOT}/scripts/wiki-init.sh" main "${WIKI_INIT_MAIN_HOME}/wiki" >/dev/null
bash "${REPO_ROOT}/scripts/wiki-init.sh" main "${WIKI_INIT_MAIN_HOME}/work-wiki" >/dev/null
# Simulate user choosing option 1 (first candidate)
echo "1" | bash "${INIT_MAIN}" 2>/dev/null
ptr=$(cat "${WIKI_POINTER_FILE}")
[[ "${ptr}" == "${WIKI_INIT_MAIN_HOME}/wiki" || "${ptr}" == "${WIKI_INIT_MAIN_HOME}/work-wiki" ]] \
  || fail "multi-candidate: pointer should be one of the two; got '${ptr}'"

echo "PASS: wiki-init-main.sh bootstrap"
