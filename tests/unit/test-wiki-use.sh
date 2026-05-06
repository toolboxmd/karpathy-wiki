#!/bin/bash
# Verify wiki-use.sh subcommands and refusal cases.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
USE="${REPO_ROOT}/scripts/wiki-use.sh"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

MAIN="${TESTDIR}/main"
bash "${INIT}" main "${MAIN}" >/dev/null
export WIKI_POINTER_FILE="${TESTDIR}/.wiki-pointer"
echo "${MAIN}" > "${WIKI_POINTER_FILE}"

# Case 1: wiki use project (fresh cwd)
PROJ="${TESTDIR}/proj1"
mkdir -p "${PROJ}"
( cd "${PROJ}" && bash "${USE}" project ) >/dev/null \
  || fail "wiki use project failed"
[[ -d "${PROJ}/wiki" ]] || fail "wiki use project did not create ./wiki/"
[[ -f "${PROJ}/.wiki-config" ]] || fail "wiki use project did not write .wiki-config"
grep -q '^role = "project-pointer"' "${PROJ}/.wiki-config" || fail "config role != project-pointer"
grep -q '^fork_to_main = false' "${PROJ}/.wiki-config" || fail "fork_to_main should be false"

# Case 2: wiki use project (idempotent re-run)
( cd "${PROJ}" && bash "${USE}" project ) >/dev/null \
  || fail "wiki use project re-run failed"

# Case 3: wiki use main (fresh cwd, no pre-existing config)
PROJ_MAIN="${TESTDIR}/proj2"
mkdir -p "${PROJ_MAIN}"
( cd "${PROJ_MAIN}" && bash "${USE}" main ) >/dev/null \
  || fail "wiki use main failed"
[[ "$(cat "${PROJ_MAIN}/.wiki-mode")" == "main-only" ]] \
  || fail "wiki use main did not write 'main-only'"

# Case 4: wiki use main inside an existing wiki (refused)
( cd "${PROJ}" && bash "${USE}" main ) 2>/dev/null \
  && fail "wiki use main inside existing wiki should refuse"

# Case 5: wiki use both (fresh cwd)
PROJ_BOTH="${TESTDIR}/proj3"
mkdir -p "${PROJ_BOTH}"
( cd "${PROJ_BOTH}" && bash "${USE}" both ) >/dev/null \
  || fail "wiki use both failed"
grep -q '^fork_to_main = true' "${PROJ_BOTH}/.wiki-config" || fail "wiki use both: fork_to_main should be true"

# Case 6: wiki use both (when pointer = none) — refused
echo "none" > "${WIKI_POINTER_FILE}"
PROJ_BOTH_NOMAIN="${TESTDIR}/proj4"
mkdir -p "${PROJ_BOTH_NOMAIN}"
( cd "${PROJ_BOTH_NOMAIN}" && bash "${USE}" both ) 2>/dev/null \
  && fail "wiki use both should refuse when pointer = none"
echo "${MAIN}" > "${WIKI_POINTER_FILE}"

# Case 7: wiki use both (existing project, flips fork_to_main)
( cd "${PROJ}" && bash "${USE}" both ) >/dev/null \
  || fail "wiki use both on existing project failed"
grep -q '^fork_to_main = true' "${PROJ}/.wiki-config" || fail "wiki use both: did not flip fork_to_main"

# Case 8: wiki use project flips back
( cd "${PROJ}" && bash "${USE}" project ) >/dev/null \
  || fail "wiki use project (flip back) failed"
grep -q '^fork_to_main = false' "${PROJ}/.wiki-config" || fail "fork_to_main should be false again"

echo "PASS: wiki-use.sh"
