#!/bin/bash
# RED: wiki-resolve.sh must resolve a main-wiki pointer whose path contains
# spaces (e.g. an Obsidian vault at ".../Obsidian Vault/karpathy-wiki").
#
# Bug: scripts/wiki-resolve.sh:40 read the pointer with
#   tr -d '[:space:]'
# which strips ALL whitespace, including interior spaces in the path. A
# pointer "/home/u/Obsidian Vault/wiki" became "/home/u/ObsidianVault/wiki",
# whose .wiki-config does not exist, so the resolver returned exit 10
# ("pointer broken") and every capture orphaned. The same destructive strip
# lived in wiki-use.sh:27 and bin/wiki:198. Trimming must remove only
# leading/trailing whitespace (incl. a trailing CR on Windows), never
# interior spaces.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESOLVE="${REPO_ROOT}/scripts/wiki-resolve.sh"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"
USE="${REPO_ROOT}/scripts/wiki-use.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -x "${RESOLVE}" ]] || fail "wiki-resolve.sh missing or not executable"

TESTDIR="$(mktemp -d)"
TESTDIR="$(cd "${TESTDIR}" && pwd -P)"
trap 'rm -rf "${TESTDIR}"' EXIT
export XDG_CONFIG_HOME="${TESTDIR}/config-home"

# Fake $HOME so we never touch the real user's pointer/wiki.
FAKE_HOME="${TESTDIR}/home"
mkdir -p "${FAKE_HOME}"

# Main wiki at a path WITH a space, mirroring an Obsidian vault layout.
MAIN="${FAKE_HOME}/Obsidian Vault/karpathy-wiki"
bash "${INIT}" main "${MAIN}" >/dev/null

# Pointer references the spaced path. Include a trailing newline (normal)
# so the trim still has to drop the newline without eating the space.
printf '%s\n' "${MAIN}" > "${FAKE_HOME}/.wiki-pointer"
export WIKI_POINTER_FILE="${FAKE_HOME}/.wiki-pointer"

# Select main once so wiki-use must preserve the interior space when pinning.
WORK="${FAKE_HOME}/work"
mkdir -p "${WORK}"
(cd "${WORK}" && HOME="${FAKE_HOME}" bash "${USE}" main) >/dev/null

output=$( HOME="${FAKE_HOME}" bash -c "cd \"${WORK}\" && bash \"${RESOLVE}\"" 2>/dev/null ) && rc=0 || rc=$?

if [[ "${rc}" != 0 ]]; then
  fail "resolver exited ${rc} for spaced pointer path, expected 0 (the space in 'Obsidian Vault' was likely stripped)"
fi

if [[ "${output}" != "${MAIN}" ]]; then
  fail "resolver returned '${output}', expected '${MAIN}' (interior space must be preserved)"
fi

echo "PASS: resolver preserves interior spaces in the main-wiki pointer path"
