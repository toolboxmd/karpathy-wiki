#!/bin/bash
# Verify wiki-resolve.sh exit codes for every combination of pointer
# state x cwd state. ≥ 14 cases per spec test surface.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESOLVE="${REPO_ROOT}/scripts/wiki-resolve.sh"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -x "${RESOLVE}" ]] || fail "wiki-resolve.sh missing or not executable"

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

# Use a pointer file inside TESTDIR to avoid touching the user's real ~/.wiki-pointer
export WIKI_POINTER_FILE="${TESTDIR}/.wiki-pointer"

# Helper: assert exit code from wiki-resolve.sh in a given cwd
assert_exit() {
  local desc="$1"
  local cwd="$2"
  local expected="$3"
  local actual
  ( cd "${cwd}" && bash "${RESOLVE}" >/dev/null 2>&1 ) && actual=0 || actual=$?
  [[ "${actual}" == "${expected}" ]] || \
    fail "${desc}: expected exit ${expected}, got ${actual}"
}

# Helper: assert stdout from wiki-resolve.sh contains a path
assert_returns() {
  local desc="$1"
  local cwd="$2"
  local expected="$3"
  local actual
  actual=$( cd "${cwd}" && bash "${RESOLVE}" 2>/dev/null )
  echo "${actual}" | grep -qF "${expected}" || \
    fail "${desc}: expected output to contain '${expected}', got '${actual}'"
}

# Set up fixtures
MAIN="${TESTDIR}/main-wiki"
PROJECT="${TESTDIR}/proj"
bash "${INIT}" main "${MAIN}" >/dev/null
mkdir -p "${PROJECT}"
bash "${INIT}" project "${PROJECT}/wiki" "${MAIN}" >/dev/null

# Project-pointer config at PROJECT
cat > "${PROJECT}/.wiki-config" <<EOF
role = "project-pointer"
wiki = "./wiki"
created = "2026-05-06"
fork_to_main = false
EOF

UNCONFIGURED="${TESTDIR}/scratch"
mkdir -p "${UNCONFIGURED}"

# Case 1: pointer missing → exit 10
rm -f "${WIKI_POINTER_FILE}"
assert_exit "pointer missing" "${UNCONFIGURED}" 10

# Case 2: pointer = none + cwd has .wiki-config (fork_to_main = false) → 0
echo "none" > "${WIKI_POINTER_FILE}"
assert_exit "pointer=none + cwd has config (fork=false)" "${PROJECT}" 0
assert_returns "pointer=none + cwd has config (fork=false)" "${PROJECT}" "${PROJECT}/wiki"

# Case 3: pointer = none + cwd has .wiki-config with fork_to_main = true → 12
sed -i.bak 's/fork_to_main = false/fork_to_main = true/' "${PROJECT}/.wiki-config"
assert_exit "pointer=none + cwd has fork_to_main=true" "${PROJECT}" 12
sed -i.bak 's/fork_to_main = true/fork_to_main = false/' "${PROJECT}/.wiki-config"

# Case 4: pointer = none + cwd unconfigured → 11
assert_exit "pointer=none + cwd unconfigured" "${UNCONFIGURED}" 11

# Case 5: pointer valid + cwd has project-pointer (fork=false) → 0, returns project wiki
echo "${MAIN}" > "${WIKI_POINTER_FILE}"
assert_exit "pointer valid + project-pointer + fork=false" "${PROJECT}" 0
assert_returns "pointer valid + project-pointer + fork=false" "${PROJECT}" "${PROJECT}/wiki"

# Case 6: pointer valid + cwd has project-pointer (fork=true) → 0, returns [project, main]
sed -i.bak 's/fork_to_main = false/fork_to_main = true/' "${PROJECT}/.wiki-config"
output=$( cd "${PROJECT}" && bash "${RESOLVE}" )
echo "${output}" | grep -qF "${PROJECT}/wiki" || fail "fork mode: project wiki missing"
echo "${output}" | grep -qF "${MAIN}" || fail "fork mode: main wiki missing"
sed -i.bak 's/fork_to_main = true/fork_to_main = false/' "${PROJECT}/.wiki-config"

# Case 7: cwd has .wiki-mode = main-only + pointer valid → 0, returns [main]
echo "main-only" > "${UNCONFIGURED}/.wiki-mode"
assert_exit "cwd .wiki-mode=main-only + pointer valid" "${UNCONFIGURED}" 0
assert_returns "cwd .wiki-mode=main-only + pointer valid" "${UNCONFIGURED}" "${MAIN}"
rm "${UNCONFIGURED}/.wiki-mode"

# Case 8: cwd has .wiki-mode = main-only + pointer = none → 12
echo "none" > "${WIKI_POINTER_FILE}"
echo "main-only" > "${UNCONFIGURED}/.wiki-mode"
assert_exit "cwd .wiki-mode=main-only + pointer=none" "${UNCONFIGURED}" 12
rm "${UNCONFIGURED}/.wiki-mode"

# Case 9: cwd has BOTH .wiki-config AND .wiki-mode → 13
echo "${MAIN}" > "${WIKI_POINTER_FILE}"
echo "main-only" > "${PROJECT}/.wiki-mode"
assert_exit "cwd has both .wiki-config and .wiki-mode" "${PROJECT}" 13
rm "${PROJECT}/.wiki-mode"

# Case 10: cwd has .wiki-config role=main but missing schema.md → 14
HALF="${TESTDIR}/half-built"
mkdir -p "${HALF}/.wiki-pending"
cat > "${HALF}/.wiki-config" <<EOF
role = "main"
created = "2026-05-06"
fork_to_main = false
EOF
echo "{}" > "${HALF}/.manifest.json"
echo "# Index" > "${HALF}/index.md"
# schema.md is missing
assert_exit "cwd half-built (no schema.md)" "${HALF}" 14
echo "# Schema" > "${HALF}/schema.md"
# index.md is now present, schema.md present, .wiki-pending/ present — should resolve fine
assert_exit "cwd fully built" "${HALF}" 0

# Case 11: pointer-target half-built (project-pointer's wiki dir missing schema) → 14
BROKEN_MAIN="${TESTDIR}/broken-main"
mkdir -p "${BROKEN_MAIN}/.wiki-pending"
cat > "${BROKEN_MAIN}/.wiki-config" <<EOF
role = "main"
created = "2026-05-06"
fork_to_main = false
EOF
echo "{}" > "${BROKEN_MAIN}/.manifest.json"
echo "# Index" > "${BROKEN_MAIN}/index.md"
# schema.md missing
echo "${BROKEN_MAIN}" > "${WIKI_POINTER_FILE}"
echo "main-only" > "${UNCONFIGURED}/.wiki-mode"
assert_exit "pointer target half-built" "${UNCONFIGURED}" 14
rm "${UNCONFIGURED}/.wiki-mode"
rm -rf "${BROKEN_MAIN}"

# Case 12: pointer points at non-main wiki (role=project) → 10
PROJ_AS_POINTER="${TESTDIR}/proj-as-pointer"
bash "${INIT}" project "${PROJ_AS_POINTER}" >/dev/null
echo "${PROJ_AS_POINTER}" > "${WIKI_POINTER_FILE}"
echo "main-only" > "${UNCONFIGURED}/.wiki-mode"
assert_exit "pointer target role=project (not main)" "${UNCONFIGURED}" 10
rm "${UNCONFIGURED}/.wiki-mode"

# Case 13: broken pointer (path doesn't exist) → 10
echo "/nonexistent/path/to/wiki" > "${WIKI_POINTER_FILE}"
assert_exit "broken pointer path" "${UNCONFIGURED}" 10

# Case 14: pointer is a symlink to a valid main → 0
echo "${MAIN}" > "${WIKI_POINTER_FILE}.target"
ln -sf "${WIKI_POINTER_FILE}.target" "${WIKI_POINTER_FILE}"
echo "main-only" > "${UNCONFIGURED}/.wiki-mode"
assert_exit "symlink pointer to valid main" "${UNCONFIGURED}" 0
rm "${UNCONFIGURED}/.wiki-mode"
rm -f "${WIKI_POINTER_FILE}" "${WIKI_POINTER_FILE}.target"

echo "PASS: wiki-resolve.sh exit-code matrix (14 cases)"
