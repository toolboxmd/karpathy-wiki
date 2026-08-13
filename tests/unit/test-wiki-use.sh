#!/bin/bash
# Verify wiki-use.sh subcommands and refusal cases.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
USE="${REPO_ROOT}/scripts/wiki-use.sh"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"
export WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME=1
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/wiki-lib.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

MAIN="${TESTDIR}/main"
bash "${INIT}" main "${MAIN}" >/dev/null
export WIKI_POINTER_FILE="${TESTDIR}/.wiki-pointer"
echo "${MAIN}" > "${WIKI_POINTER_FILE}"

write_runtime_config() {
  local root="$1"
  cat > "${root}/.wiki-config.local" <<'EOF'
[ingest]
dispatch_mode = "session_start"
max_processes = 2
default_profile = "grok_medium"

[ingest.profiles.grok_medium]
provider = "grok"
model = "grok-test"
reasoning_effort = "medium"

[routing]
fork_to_main = false

[settings]
auto_commit = false
EOF
}

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
if grep -q '^main = ' "${PROJ_BOTH}/.wiki-config"; then
  fail "wiki use both wrote a machine-specific main path into tracked config"
fi

# Case 6: wiki use both (when pointer = none) — refused
echo "none" > "${WIKI_POINTER_FILE}"
PROJ_BOTH_NOMAIN="${TESTDIR}/proj4"
mkdir -p "${PROJ_BOTH_NOMAIN}"
( cd "${PROJ_BOTH_NOMAIN}" && bash "${USE}" both ) 2>/dev/null \
  && fail "wiki use both should refuse when pointer = none"
echo "${MAIN}" > "${WIKI_POINTER_FILE}"

# Case 6b: broken and non-main pointers are refused before config mutation.
BROKEN_BOTH="${TESTDIR}/broken-both"
mkdir -p "${BROKEN_BOTH}"
echo "${TESTDIR}/missing-main" > "${WIKI_POINTER_FILE}"
( cd "${BROKEN_BOTH}" && bash "${USE}" both ) 2>/dev/null \
  && fail "wiki use both accepted a broken pointer"
[[ ! -e "${BROKEN_BOTH}/.wiki-config" ]] || fail "broken pointer mutated cwd config"

NOT_MAIN="${TESTDIR}/not-main"
bash "${INIT}" project "${NOT_MAIN}" >/dev/null
echo "${NOT_MAIN}" > "${WIKI_POINTER_FILE}"
( cd "${BROKEN_BOTH}" && bash "${USE}" both ) 2>/dev/null \
  && fail "wiki use both accepted a non-main pointer"
[[ ! -e "${BROKEN_BOTH}/.wiki-config" ]] || fail "non-main pointer mutated cwd config"
echo "${MAIN}" > "${WIKI_POINTER_FILE}"

# Case 7: wiki use both (existing project, flips fork_to_main)
( cd "${PROJ}" && bash "${USE}" both ) >/dev/null \
  || fail "wiki use both on existing project failed"
grep -q '^fork_to_main = true' "${PROJ}/.wiki-config" || fail "wiki use both: did not flip fork_to_main"
if grep -q '^main = ' "${PROJ}/.wiki-config"; then
  fail "existing project config retained a machine-specific main path"
fi

# Case 8: wiki use project flips back
( cd "${PROJ}" && bash "${USE}" project ) >/dev/null \
  || fail "wiki use project (flip back) failed"
grep -q '^fork_to_main = false' "${PROJ}/.wiki-config" || fail "fork_to_main should be false again"

# Case 9: an actual wiki root keeps routing local and preserves its provider.
ACTUAL="${TESTDIR}/actual-wiki"
bash "${INIT}" project "${ACTUAL}" >/dev/null
write_runtime_config "${ACTUAL}"
structural_before="$(cat "${ACTUAL}/.wiki-config")"
( cd "${ACTUAL}" && bash "${USE}" both ) >/dev/null \
  || fail "wiki use both on actual wiki failed"
[[ "$(wiki_runtime_config_get "${ACTUAL}" routing.fork_to_main)" == "true" ]] \
  || fail "actual wiki did not store fork=true locally"
[[ "$(wiki_runtime_config_get "${ACTUAL}" ingest.profiles.grok_medium.model)" == "grok-test" ]] \
  || fail "actual wiki routing update changed the provider model"
[[ "$(cat "${ACTUAL}/.wiki-config")" == "${structural_before}" ]] \
  || fail "actual wiki routing update mutated tracked structural config"
( cd "${ACTUAL}" && bash "${USE}" project ) >/dev/null \
  || fail "wiki use project on actual wiki failed"
[[ "$(wiki_runtime_config_get "${ACTUAL}" routing.fork_to_main)" == "false" ]] \
  || fail "actual wiki did not store fork=false locally"

# Case 10: actual wiki without local runtime config gets an actionable error.
NO_LOCAL="${TESTDIR}/actual-without-local"
bash "${INIT}" project "${NO_LOCAL}" >/dev/null
set +e
error=$( cd "${NO_LOCAL}" && bash "${USE}" both 2>&1 )
rc=$?
set -e
[[ "${rc}" -ne 0 ]] || fail "wiki use both should refuse to invent local provider config"
grep -Fq "wiki config init-local ${NO_LOCAL}" <<< "${error}" \
  || fail "missing local runtime config error is not actionable"

# Case 11: both mode is meaningless inside the main wiki and must refuse.
write_runtime_config "${MAIN}"
( cd "${MAIN}" && bash "${USE}" both ) 2>/dev/null \
  && fail "wiki use both inside main wiki should refuse"

echo "PASS: wiki-use.sh"
