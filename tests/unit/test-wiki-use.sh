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
  local root="$1" workspace="${2:-$1}"
  cat > "${root}/.wiki-config.local" <<EOF
[trust]
wiki_root = "$(cd "${root}" && pwd -P)"
workspace_root = "$(cd "${workspace}" && pwd -P)"

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

# Case 9b: pointer commands synchronize an existing target runtime so an
# operator can explicitly resolve an old pointer/runtime mismatch.
POINTER_RUNTIME="${TESTDIR}/pointer-runtime"
mkdir -p "${POINTER_RUNTIME}"
bash "${INIT}" project "${POINTER_RUNTIME}/wiki" "${MAIN}" >/dev/null
write_runtime_config "${POINTER_RUNTIME}/wiki" "${POINTER_RUNTIME}"
cat > "${POINTER_RUNTIME}/.wiki-config" <<'EOF'
role = "project-pointer"
wiki = "./wiki"
created = "2026-08-13"
fork_to_main = false
EOF
( cd "${POINTER_RUNTIME}" && bash "${USE}" both ) >/dev/null \
  || fail "wiki use both on project pointer with runtime failed"
[[ "$(wiki_runtime_config_get "${POINTER_RUNTIME}/wiki" routing.fork_to_main)" == "true" ]] \
  || fail "wiki use both did not synchronize the target runtime true"
( cd "${POINTER_RUNTIME}" && bash "${USE}" project ) >/dev/null \
  || fail "wiki use project on project pointer with runtime failed"
[[ "$(wiki_runtime_config_get "${POINTER_RUNTIME}/wiki" routing.fork_to_main)" == "false" ]] \
  || fail "wiki use project did not synchronize the target runtime false"

# If target-runtime synchronization fails after the pointer mutation, the
# pointer choice must roll back rather than leaving a new mismatch.
sed -i.bak 's/^fork_to_main = false/fork_to_main = "invalid"/' \
  "${POINTER_RUNTIME}/wiki/.wiki-config.local"
rm -f "${POINTER_RUNTIME}/wiki/.wiki-config.local.bak"
( cd "${POINTER_RUNTIME}" && bash "${USE}" both ) 2>/dev/null \
  && fail "wiki use both succeeded with an invalid target runtime"
grep -q '^fork_to_main = false' "${POINTER_RUNTIME}/.wiki-config" \
  || fail "failed runtime synchronization did not roll back the pointer"

# Case 9c: a project pointer cannot synchronize a runtime trusted for a
# different workspace. Trust must be checked before either side is mutated.
VICTIM_WORKSPACE="${TESTDIR}/victim-workspace"
ATTACKER_WORKSPACE="${TESTDIR}/attacker-workspace"
SHARED_WIKI="${TESTDIR}/custom/shared-project-wiki"
EXTERNAL_CONFIG_HOME="${TESTDIR}/external-config-home"
mkdir -p "${VICTIM_WORKSPACE}" "${ATTACKER_WORKSPACE}"
bash "${INIT}" project "${SHARED_WIKI}" "${MAIN}" >/dev/null
cat > "${VICTIM_WORKSPACE}/.wiki-config" <<EOF
role = "project-pointer"
wiki = "${SHARED_WIKI}"
fork_to_main = false
EOF
env -u WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME \
  XDG_CONFIG_HOME="${EXTERNAL_CONFIG_HOME}" \
  python3 "${REPO_ROOT}/scripts/wiki_config.py" init-local \
    --wiki "${SHARED_WIKI}" --trust-workspace "${VICTIM_WORKSPACE}" \
    --default-provider codex --default-model test-model \
    --default-effort low --no-fork-to-main >/dev/null
cat > "${ATTACKER_WORKSPACE}/.wiki-config" <<EOF
role = "project-pointer"
wiki = "${SHARED_WIKI}"
fork_to_main = false
EOF
attacker_before="$(cat "${ATTACKER_WORKSPACE}/.wiki-config")"
for attempted_mode in both project; do
  if [[ "${attempted_mode}" == "project" ]]; then
    env -u WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME \
      XDG_CONFIG_HOME="${EXTERNAL_CONFIG_HOME}" \
      python3 "${REPO_ROOT}/scripts/wiki_config.py" update-runtime \
        --wiki "${SHARED_WIKI}" --fork-to-main >/dev/null
  fi
  runtime_before="$(env -u WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME \
    XDG_CONFIG_HOME="${EXTERNAL_CONFIG_HOME}" \
    python3 "${REPO_ROOT}/scripts/wiki_config.py" get \
      --wiki "${SHARED_WIKI}" --key routing.fork_to_main)"
  ( cd "${ATTACKER_WORKSPACE}" && \
    env -u WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME \
      XDG_CONFIG_HOME="${EXTERNAL_CONFIG_HOME}" \
      bash "${USE}" "${attempted_mode}" ) 2>/dev/null \
    && fail "wiki use ${attempted_mode} synchronized another workspace's runtime"
  [[ "$(cat "${ATTACKER_WORKSPACE}/.wiki-config")" == "${attacker_before}" ]] \
    || fail "wiki use ${attempted_mode} mutated the untrusted pointer"
  runtime_after="$(env -u WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME \
    XDG_CONFIG_HOME="${EXTERNAL_CONFIG_HOME}" \
    python3 "${REPO_ROOT}/scripts/wiki_config.py" get \
      --wiki "${SHARED_WIKI}" --key routing.fork_to_main)"
  [[ "${runtime_after}" == "${runtime_before}" ]] \
    || fail "wiki use ${attempted_mode} mutated another workspace's runtime"
done

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
