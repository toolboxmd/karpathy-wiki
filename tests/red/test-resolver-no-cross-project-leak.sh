#!/bin/bash
# RED: wiki_root_from_cwd must NOT return ~/wiki/ from inside a project
# directory that itself has no .wiki-config.
#
# Bug (0.2.8 #9): scripts/wiki-lib.sh:57-60 probes ${dir}/wiki/.wiki-config
# at every walk-up level. From ${HOME}/proj/A/sub, walk-up reaches ${HOME}
# and finds ${HOME}/wiki/.wiki-config, then routes captures from project A
# to the main wiki. Captures bleed across project boundaries.
#
# Constraint pairs with #11: walk-up still works for finding .wiki-config
# at parent dirs of cwd (legitimate subdir-of-project case), but the
# nested-`wiki/` discovery must happen ONLY at leaf cwd.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LIB="${REPO_ROOT}/scripts/wiki-lib.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "${LIB}" ]] || fail "wiki-lib.sh missing"

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

# Stand up a fake $HOME with a main wiki at $HOME/wiki/.
FAKE_HOME="${TESTDIR}/home"
mkdir -p "${FAKE_HOME}/wiki"
cat > "${FAKE_HOME}/wiki/.wiki-config" <<EOF
role = "main"
created = "2026-05-06"
EOF

# Project A under $HOME with a sub/dir/. Project A has NO .wiki-config of
# its own and NO ./wiki/ subdir.
PROJ_A="${FAKE_HOME}/proj/A"
mkdir -p "${PROJ_A}/sub"

# Source wiki-lib in a fresh shell with HOME overridden, then call
# wiki_root_from_cwd from PROJ_A/sub.
result=$(HOME="${FAKE_HOME}" bash -c "
  source '${LIB}'
  cd '${PROJ_A}/sub'
  wiki_root_from_cwd 2>/dev/null || echo '<empty>'
")

# Must NOT return the main wiki at $HOME/wiki.
if [[ "${result}" == "${FAKE_HOME}/wiki" ]]; then
  fail "wiki_root_from_cwd leaked main wiki from inside project A. Got: ${result}"
fi

# Acceptable outcomes: empty (project A has no wiki) or any path UNDER
# ${PROJ_A} (if walk-up hit a config we placed there — we didn't).
if [[ "${result}" != "<empty>" && "${result}" != "${PROJ_A}"* ]]; then
  fail "wiki_root_from_cwd returned unexpected path from project A: ${result}"
fi

echo "PASS: wiki_root_from_cwd does not leak ~/wiki across project boundaries"
