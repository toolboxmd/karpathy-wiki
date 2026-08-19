#!/bin/bash
# Verify resolution from the single private workspace routing authority.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RESOLVE="${REPO_ROOT}/scripts/wiki-resolve.sh"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"
CONFIG="${REPO_ROOT}/scripts/wiki_config.py"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -x "${RESOLVE}" ]] || fail "wiki-resolve.sh missing or not executable"

TESTDIR="$(mktemp -d)"
TESTDIR="$(cd "${TESTDIR}" && pwd -P)"
trap 'rm -rf "${TESTDIR}"' EXIT
export XDG_CONFIG_HOME="${TESTDIR}/config-home"
export WIKI_POINTER_FILE="${TESTDIR}/.wiki-pointer"
unset WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME

MAIN="${TESTDIR}/main"
WORKSPACE="${TESTDIR}/workspace"
PROJECT="${WORKSPACE}/wiki"
mkdir -p "${WORKSPACE}"
bash "${INIT}" main "${MAIN}" >/dev/null
bash "${INIT}" project "${PROJECT}" "${MAIN}" >/dev/null
printf '%s\n' "${MAIN}" > "${WIKI_POINTER_FILE}"

assert_exit() {
  local desc="$1" cwd="$2" expected="$3" actual
  (cd "${cwd}" && bash "${RESOLVE}" --plan >/dev/null 2>&1) && actual=0 || actual=$?
  [[ "${actual}" -eq "${expected}" ]] \
    || fail "${desc}: expected exit ${expected}, got ${actual}"
}

set_route() {
  python3 "${CONFIG}" route-set --workspace "${WORKSPACE}" "$@" >/dev/null
}

assert_plan() {
  local expected_mode="$1" expected_primary="$2" expected_policy="$3" expected_main="$4"
  (cd "${WORKSPACE}" && bash "${RESOLVE}" --plan) | python3 -c '
import json, sys
plan = json.load(sys.stdin)
mode, primary, policy, main = sys.argv[1:]
assert plan["mode"] == mode, plan
assert plan["primary_wiki"] == primary, plan
assert plan["promotion_policy"] == policy, plan
assert plan.get("main_wiki") == (main or None), plan
' "${expected_mode}" "${expected_primary}" "${expected_policy}" "${expected_main}" \
    || fail "plan mismatch for ${expected_mode}"
}

# 1. No runtime is unconfigured even if a main pointer exists.
assert_exit "unconfigured workspace" "${WORKSPACE}" 11

# 2. Tracked routing fields cannot authorize a target.
cat > "${WORKSPACE}/.wiki-config" <<EOF
role = "project-pointer"
wiki = "./wiki"
fork_to_main = true
main = "${MAIN}"
EOF
printf 'main-only\n' > "${WORKSPACE}/.wiki-mode"
assert_exit "tracked markers only" "${WORKSPACE}" 11

# 3. Project mode has one project target and no promotion.
set_route --mode project --project-wiki "${PROJECT}"
assert_plan project "${PROJECT}" none ""
[[ "$(cd "${WORKSPACE}" && bash "${RESOLVE}")" == "${PROJECT}" ]] \
  || fail "project mode did not emit exactly one target"

# 4. Nested directories inherit the nearest workspace runtime.
mkdir -p "${WORKSPACE}/src/deep"
[[ "$(cd "${WORKSPACE}/src/deep" && bash "${RESOLVE}")" == "${PROJECT}" ]] \
  || fail "nested cwd did not inherit the workspace route"

# 5. Both remains one project target and carries selective policy in the plan.
set_route --mode both --project-wiki "${PROJECT}" --main-wiki "${MAIN}"
assert_plan both "${PROJECT}" selective "${MAIN}"
[[ "$(cd "${WORKSPACE}" && bash "${RESOLVE}" | wc -l | tr -d ' ')" -eq 1 ]] \
  || fail "both mode emitted multiple initial targets"

# 6. Main mode directly selects the pinned main target.
set_route --mode main --main-wiki "${MAIN}"
assert_plan main "${MAIN}" none "${MAIN}"

# 7. Changing or removing the global pointer does not retarget live routing.
printf '%s\n' "${TESTDIR}/somewhere-else" > "${WIKI_POINTER_FILE}"
assert_plan main "${MAIN}" none "${MAIN}"
rm -f "${WIKI_POINTER_FILE}"
assert_plan main "${MAIN}" none "${MAIN}"

# 8. A configured target that becomes incomplete is a target error.
rm -f "${MAIN}/schema.md"
assert_exit "incomplete configured main" "${WORKSPACE}" 14
printf '# Schema\n' > "${MAIN}/schema.md"
assert_plan main "${MAIN}" none "${MAIN}"

# 9. Malformed runtime data fails closed as configuration error.
RUNTIME="$(python3 "${CONFIG}" route-path --workspace "${WORKSPACE}")"
cp "${RUNTIME}" "${TESTDIR}/runtime.valid"
python3 - "${RUNTIME}" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_text(path.read_text(encoding="utf-8").replace('mode = "main"', 'mode = false'), encoding="utf-8")
PY
assert_exit "non-string mode" "${WORKSPACE}" 13
cp "${TESTDIR}/runtime.valid" "${RUNTIME}"
chmod 0600 "${RUNTIME}"

# 10. A sibling without its own runtime cannot inherit across directories.
SIBLING="${TESTDIR}/sibling"
mkdir -p "${SIBLING}"
assert_exit "unconfigured sibling" "${SIBLING}" 11

echo "PASS: wiki-resolve.sh single-authority matrix (10 cases)"
