#!/bin/bash
# Verify wiki-use.sh writes one private route and performs direct mode switches.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
USE="${REPO_ROOT}/scripts/wiki-use.sh"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"
CONFIG="${REPO_ROOT}/scripts/wiki_config.py"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
TESTDIR="$(cd "${TESTDIR}" && pwd -P)"
trap 'rm -rf "${TESTDIR}"' EXIT
export XDG_CONFIG_HOME="${TESTDIR}/config-home"
export WIKI_POINTER_FILE="${TESTDIR}/.wiki-pointer"
unset WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME

MAIN="${TESTDIR}/main"
bash "${INIT}" main "${MAIN}" >/dev/null
printf '%s\n' "${MAIN}" > "${WIKI_POINTER_FILE}"

route_for() {
  python3 "${CONFIG}" route-get --workspace "$1" --json
}

assert_mode() {
  local workspace="$1" mode="$2" primary="$3" policy="$4"
  route_for "${workspace}" | python3 -c '
import json, sys
route = json.load(sys.stdin)
mode, primary, policy = sys.argv[1:]
assert route["mode"] == mode, route
assert route["primary_wiki"] == primary, route
assert route["promotion_policy"] == policy, route
' "${mode}" "${primary}" "${policy}" || fail "route mismatch for ${mode}"
}

# 1. Project selection initializes the local wiki and only the private runtime.
PROJECT_WORKSPACE="${TESTDIR}/project-workspace"
mkdir -p "${PROJECT_WORKSPACE}"
(cd "${PROJECT_WORKSPACE}" && bash "${USE}" project) >/dev/null \
  || fail "wiki use project failed"
PROJECT="${PROJECT_WORKSPACE}/wiki"
[[ -d "${PROJECT}" ]] || fail "project mode did not initialize ./wiki"
[[ ! -e "${PROJECT_WORKSPACE}/.wiki-mode" ]] || fail "project mode wrote .wiki-mode"
[[ ! -e "${PROJECT_WORKSPACE}/.wiki-config" ]] || fail "project mode wrote tracked routing config"
assert_mode "${PROJECT_WORKSPACE}" project "${PROJECT}" none

# 2. Repeating a selection is byte-for-byte idempotent.
RUNTIME="$(python3 "${CONFIG}" route-path --workspace "${PROJECT_WORKSPACE}")"
cp "${RUNTIME}" "${TESTDIR}/runtime.before"
(cd "${PROJECT_WORKSPACE}" && bash "${USE}" project) >/dev/null \
  || fail "repeated project selection failed"
cmp -s "${TESTDIR}/runtime.before" "${RUNTIME}" \
  || fail "idempotent project selection rewrote runtime"

# 3. Both is one direct selection and pins the exact main target.
(cd "${PROJECT_WORKSPACE}" && bash "${USE}" both) >/dev/null \
  || fail "wiki use both failed"
assert_mode "${PROJECT_WORKSPACE}" both "${PROJECT}" selective
route_for "${PROJECT_WORKSPACE}" | grep -Fq "\"main_wiki\": \"${MAIN}\"" \
  || fail "both mode did not pin exact main target"

# 4. Main switches directly and preserves the existing project wiki.
(cd "${PROJECT_WORKSPACE}" && bash "${USE}" main) >/dev/null \
  || fail "wiki use main on an existing project failed"
assert_mode "${PROJECT_WORKSPACE}" main "${MAIN}" none
[[ -d "${PROJECT}" ]] || fail "main switch deleted project wiki"

# 5. A fresh main selection does not create an unused project wiki.
MAIN_WORKSPACE="${TESTDIR}/main-workspace"
mkdir -p "${MAIN_WORKSPACE}"
(cd "${MAIN_WORKSPACE}" && bash "${USE}" main) >/dev/null \
  || fail "fresh wiki use main failed"
assert_mode "${MAIN_WORKSPACE}" main "${MAIN}" none
[[ ! -d "${MAIN_WORKSPACE}/wiki" ]] || fail "main selection created an unused project wiki"
[[ ! -e "${MAIN_WORKSPACE}/.wiki-mode" ]] || fail "main selection wrote legacy .wiki-mode"

# 6. A fresh both selection creates project wiki and one complete route.
BOTH_WORKSPACE="${TESTDIR}/both-workspace"
mkdir -p "${BOTH_WORKSPACE}"
(cd "${BOTH_WORKSPACE}" && bash "${USE}" both) >/dev/null \
  || fail "fresh wiki use both failed"
assert_mode "${BOTH_WORKSPACE}" both "${BOTH_WORKSPACE}/wiki" selective

# 7. A broken pointer refuses main/both and preserves the prior route bytes.
cp "${RUNTIME}" "${TESTDIR}/runtime.before-failure"
printf '%s\n' "${TESTDIR}/missing-main" > "${WIKI_POINTER_FILE}"
(cd "${PROJECT_WORKSPACE}" && bash "${USE}" both) >/dev/null 2>&1 \
  && fail "both accepted a broken main pointer"
cmp -s "${TESTDIR}/runtime.before-failure" "${RUNTIME}" \
  || fail "failed selection changed the previous route"
printf '%s\n' "${MAIN}" > "${WIKI_POINTER_FILE}"

# 8. Tracked legacy markers are left structurally intact but never updated.
cat > "${PROJECT_WORKSPACE}/.wiki-config" <<'EOF'
role = "project-pointer"
wiki = "./wiki"
fork_to_main = true
EOF
printf 'main-only\n' > "${PROJECT_WORKSPACE}/.wiki-mode"
cp "${PROJECT_WORKSPACE}/.wiki-config" "${TESTDIR}/tracked.before"
cp "${PROJECT_WORKSPACE}/.wiki-mode" "${TESTDIR}/mode.before"
(cd "${PROJECT_WORKSPACE}" && bash "${USE}" project) >/dev/null \
  || fail "project selection failed with legacy marker present"
cmp -s "${TESTDIR}/tracked.before" "${PROJECT_WORKSPACE}/.wiki-config" \
  || fail "wiki use mutated tracked structural config"
cmp -s "${TESTDIR}/mode.before" "${PROJECT_WORKSPACE}/.wiki-mode" \
  || fail "wiki use deleted or rewrote the legacy marker"
assert_mode "${PROJECT_WORKSPACE}" project "${PROJECT}" none

# 9. An actual project wiki can be selected without inventing ingest config.
ACTUAL="${TESTDIR}/actual-project"
bash "${INIT}" project "${ACTUAL}" "${MAIN}" >/dev/null
(cd "${ACTUAL}" && bash "${USE}" both) >/dev/null \
  || fail "actual project wiki could not select both"
assert_mode "${ACTUAL}" both "${ACTUAL}" selective
[[ ! -e "${ACTUAL}/.wiki-config.local" ]] \
  || fail "mode selection invented ingest provider configuration"

# 10. Unknown modes fail without creating a routing runtime.
INVALID="${TESTDIR}/invalid-workspace"
mkdir -p "${INVALID}"
(cd "${INVALID}" && bash "${USE}" sideways) >/dev/null 2>&1 \
  && fail "unknown mode unexpectedly succeeded"
INVALID_RUNTIME="$(python3 "${CONFIG}" route-path --workspace "${INVALID}")"
[[ ! -e "${INVALID_RUNTIME}" ]] || fail "unknown mode created a runtime"

echo "PASS: wiki-use.sh single-authority modes (10 cases)"
