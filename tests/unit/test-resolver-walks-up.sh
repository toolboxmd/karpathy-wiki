#!/bin/bash
# RED: wiki-resolve.sh must walk up from a subdir of a project to find
# the project's .wiki-config.
#
# Bug (0.2.8 #11): scripts/wiki-resolve.sh:15-17 explicitly says
# "Cwd-only resolution: walks NO parents." That contradicts MANUAL.md:108-110
# which promises captures from a subdir of a project route to the project
# wiki. v1 baseline (tmp/skill-v1-6ce0c77.md:44-46) had the parent-walk; the
# v2.4 split lost it.
#
# Constraint: walk-up must NOT cross into the user's $HOME root and pick up
# ~/wiki — that's the cross-project leak (#9). Walk up only inside the user's
# home tree, stop at $HOME.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESOLVE="${REPO_ROOT}/scripts/wiki-resolve.sh"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -x "${RESOLVE}" ]] || fail "wiki-resolve.sh missing"

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

# Stand up a fake $HOME inside TESTDIR so the test never touches the real
# user's pointer or wiki.
FAKE_HOME="${TESTDIR}/home"
mkdir -p "${FAKE_HOME}"

# Main wiki + pointer.
MAIN="${FAKE_HOME}/wiki"
bash "${INIT}" main "${MAIN}" >/dev/null
echo "${MAIN}" > "${FAKE_HOME}/.wiki-pointer"

# Project wiki at PROJ (project role), with subdir sub/dir/.
PROJ="${FAKE_HOME}/proj"
bash "${INIT}" project "${PROJ}" "${MAIN}" >/dev/null
mkdir -p "${PROJ}/sub/dir"

export WIKI_POINTER_FILE="${FAKE_HOME}/.wiki-pointer"

# From PROJ/sub/dir/, the resolver must return the project wiki, not the
# main wiki and not exit-11 (unconfigured).
output=$( HOME="${FAKE_HOME}" cd "${PROJ}/sub/dir" && \
          HOME="${FAKE_HOME}" bash "${RESOLVE}" 2>/dev/null ) && rc=0 || rc=$?

if [[ "${rc}" != 0 ]]; then
  fail "resolver from ${PROJ}/sub/dir exited ${rc}, expected 0 with project path on stdout"
fi

if [[ "${output}" != *"${PROJ}"* ]]; then
  fail "resolver from subdir did not return project wiki. Got: ${output}"
fi

if [[ "${output}" == *"${MAIN}"* && "${output}" != *"${PROJ}"* ]]; then
  fail "resolver leaked main wiki from subdir. Got: ${output}"
fi

echo "PASS: resolver walks up from subdir into project wiki"
