#!/bin/bash
# One local workspace runtime is the only authority for project|main|both.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
USE="${REPO_ROOT}/scripts/wiki-use.sh"
RESOLVE="${REPO_ROOT}/scripts/wiki-resolve.sh"
CONFIG="${REPO_ROOT}/scripts/wiki_config.py"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
TESTDIR="$(cd "${TESTDIR}" && pwd -P)"
trap 'rm -rf "${TESTDIR}"' EXIT
export XDG_CONFIG_HOME="${TESTDIR}/config-home"
export WIKI_POINTER_FILE="${TESTDIR}/.wiki-pointer"
unset WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME

MAIN="${TESTDIR}/main"
WORKSPACE="${TESTDIR}/workspace"
mkdir -p "${WORKSPACE}"
bash "${REPO_ROOT}/scripts/wiki-init.sh" main "${MAIN}" >/dev/null
printf '%s\n' "${MAIN}" > "${WIKI_POINTER_FILE}"

route_path() {
  python3 "${CONFIG}" route-path --workspace "${WORKSPACE}"
}

route_json() {
  python3 "${CONFIG}" route-get --workspace "${WORKSPACE}" --json
}

resolver_plan() {
  (cd "${WORKSPACE}" && bash "${RESOLVE}" --plan)
}

assert_route() {
  local expected_mode="$1"
  local expected_primary="$2"
  local expected_policy="$3"
  local expected_main="$4"
  route_json | python3 -c '
import json, sys
data = json.load(sys.stdin)
expected_mode, expected_primary, expected_policy, expected_main = sys.argv[1:]
assert data["mode"] == expected_mode, data
assert data["primary_wiki"] == expected_primary, data
assert data["promotion_policy"] == expected_policy, data
assert data.get("main_wiki") == (expected_main or None), data
' "${expected_mode}" "${expected_primary}" "${expected_policy}" "${expected_main}" \
    || fail "workspace route did not match ${expected_mode}"
}

# One command creates project mode and one private authoritative runtime.
(cd "${WORKSPACE}" && bash "${USE}" project) >/dev/null \
  || fail "wiki use project failed"
PROJECT="${WORKSPACE}/wiki"
RUNTIME="$(route_path)"
[[ -f "${RUNTIME}" ]] || fail "workspace routing runtime was not created"
[[ "${RUNTIME}" == "${XDG_CONFIG_HOME}/karpathy-wiki/workspaces/"*'/runtime.toml' ]] \
  || fail "routing runtime is not in the external workspace store: ${RUNTIME}"
[[ ! -e "${WORKSPACE}/.wiki-mode" ]] || fail "wiki use wrote legacy .wiki-mode"
if [[ -f "${WORKSPACE}/.wiki-config" ]]; then
  ! grep -Eq '^(fork_to_main|main) = ' "${WORKSPACE}/.wiki-config" \
    || fail "tracked project pointer contains routing authority"
fi
assert_route project "${PROJECT}" none ""
grep -q '"mode": "project"' <<< "$(resolver_plan)" \
  || fail "resolver did not report project mode"

# Repeating the same selection is byte-for-byte idempotent.
before_hash="$(shasum -a 256 "${RUNTIME}" | awk '{print $1}')"
(cd "${WORKSPACE}" && bash "${USE}" project) >/dev/null \
  || fail "repeated wiki use project failed"
after_hash="$(shasum -a 256 "${RUNTIME}" | awk '{print $1}')"
[[ "${after_hash}" == "${before_hash}" ]] \
  || fail "idempotent mode selection rewrote the runtime"

# both is one selection, keeps the original capture local, and exposes one
# exact main target for later selective promotion.
(cd "${WORKSPACE}" && bash "${USE}" both) >/dev/null \
  || fail "wiki use both failed"
assert_route both "${PROJECT}" selective "${MAIN}"
both_plan="$(resolver_plan)"
grep -q '"mode": "both"' <<< "${both_plan}" || fail "resolver missed both mode"
grep -q '"promotion_policy": "selective"' <<< "${both_plan}" \
  || fail "both mode did not enable selective promotion"
[[ "$(bash "${RESOLVE}" --plan 2>/dev/null || true)" != "${both_plan}" ]] \
  || true

# main is a direct switch, not a second consent ceremony, and does not delete
# the existing project wiki.
(cd "${WORKSPACE}" && bash "${USE}" main) >/dev/null \
  || fail "wiki use main failed"
assert_route main "${MAIN}" none "${MAIN}"
[[ -d "${PROJECT}" ]] || fail "switching to main deleted the project wiki"
[[ ! -e "${WORKSPACE}/.wiki-mode" ]] || fail "main mode used legacy .wiki-mode"

# A tracked contributor-controlled fork flag never broadens the local choice.
cat > "${WORKSPACE}/.wiki-config" <<EOF
role = "project-pointer"
wiki = "./wiki"
fork_to_main = true
main = "${MAIN}"
EOF
(cd "${WORKSPACE}" && bash "${USE}" project) >/dev/null \
  || fail "project mode failed with a legacy tracked pointer"
assert_route project "${PROJECT}" none ""

# Removing local runtime makes the checkout unconfigured. The tracked marker
# alone cannot authorize project or main routing.
saved_runtime="${TESTDIR}/saved-runtime.toml"
cp "${RUNTIME}" "${saved_runtime}"
rm "${RUNTIME}"
set +e
(cd "${WORKSPACE}" && bash "${RESOLVE}" --plan) >/dev/null 2>&1
rc=$?
set -e
[[ "${rc}" -eq 11 ]] || fail "tracked pointer authorized routing without local runtime (rc=${rc})"
cp "${saved_runtime}" "${RUNTIME}"
chmod 0600 "${RUNTIME}"

# A failed mode switch preserves the authoritative runtime byte-for-byte.
before_hash="$(shasum -a 256 "${RUNTIME}" | awk '{print $1}')"
printf '%s\n' "${TESTDIR}/missing-main" > "${WIKI_POINTER_FILE}"
set +e
(cd "${WORKSPACE}" && bash "${USE}" both) >/dev/null 2>&1
rc=$?
set -e
[[ "${rc}" -ne 0 ]] || fail "both accepted a broken main target"
after_hash="$(shasum -a 256 "${RUNTIME}" | awk '{print $1}')"
[[ "${after_hash}" == "${before_hash}" ]] \
  || fail "failed mode switch changed the previous runtime"

# Existing routes are revalidated against their workspace trust boundary.
FOREIGN_PROJECT="${TESTDIR}/foreign-project"
bash "${REPO_ROOT}/scripts/wiki-init.sh" project "${FOREIGN_PROJECT}" >/dev/null
cp "${RUNTIME}" "${TESTDIR}/runtime.before-foreign"
python3 - "${RUNTIME}" "${PROJECT}" "${FOREIGN_PROJECT}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
project, foreign = sys.argv[2:]
text = path.read_text(encoding="utf-8")
text = text.replace(
    f'project_wiki = "{project}"',
    f'project_wiki = "{foreign}"',
)
path.write_text(text, encoding="utf-8")
PY
set +e
route_json >/dev/null 2>&1
rc=$?
set -e
[[ "${rc}" -ne 0 ]] \
  || fail "an existing route accepted a project wiki outside its workspace"
cp "${TESTDIR}/runtime.before-foreign" "${RUNTIME}"
chmod 0600 "${RUNTIME}"

# A route explicitly owned by HOME is visible both at HOME and below it, but
# the search still stops at that boundary instead of walking above it.
HOME_WORKSPACE="${TESTDIR}/home-workspace"
mkdir -p "${HOME_WORKSPACE}/nested"
HOME="${HOME_WORKSPACE}" python3 "${CONFIG}" route-set \
  --workspace "${HOME_WORKSPACE}" --mode main --main-wiki "${MAIN}" >/dev/null
for start in "${HOME_WORKSPACE}" "${HOME_WORKSPACE}/nested"; do
  HOME="${HOME_WORKSPACE}" python3 "${CONFIG}" route-find \
    --cwd "${start}" --json | grep -Fq '"mode": "main"' \
    || fail "HOME-owned routing was not found from ${start}"
done

# Invalid mode types and values fail closed.
python3 - "${RUNTIME}" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
text = text.replace('mode = "project"', 'mode = "false"')
path.write_text(text, encoding="utf-8")
PY
set +e
route_json >/dev/null 2>&1
rc=$?
set -e
[[ "${rc}" -ne 0 ]] || fail "invalid routing mode was accepted"

echo "PASS: single authoritative workspace routing"
