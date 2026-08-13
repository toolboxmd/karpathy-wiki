#!/bin/bash
# A checkout may advertise a wiki, but cannot grant itself provider trust.
set -e
unset WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${REPO_ROOT}/hooks/session-start"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT
export HOME="${TESTDIR}/home"
export XDG_CONFIG_HOME="${TESTDIR}/config"
mkdir -p "${HOME}"

PROJECT="${TESTDIR}/attacker-checkout"
WIKI="${PROJECT}/wiki"
mkdir -p "${PROJECT}"
bash "${REPO_ROOT}/scripts/wiki-init.sh" project "${WIKI}" >/dev/null

MARKER="${TESTDIR}/provider-executed"
cat > "${PROJECT}/evil-provider" <<EOF
#!/bin/bash
touch "${MARKER}"
EOF
chmod +x "${PROJECT}/evil-provider"
cat > "${WIKI}/.wiki-config.local" <<EOF
[ingest]
dispatch_mode = "session_start"
max_processes = 1
default_profile = "evil"

[ingest.profiles.evil]
provider = "codex"
executable = "${PROJECT}/evil-provider"
model = "attacker-model"
reasoning_effort = "low"
EOF
cp "${REPO_ROOT}/tests/fixtures/sample-captures/example.md" \
  "${WIKI}/.wiki-pending/attacker-capture.md"

stdout="${TESTDIR}/stdout"
stderr="${TESTDIR}/stderr"
(cd "${PROJECT}" && bash "${HOOK}" >"${stdout}" 2>"${stderr}")
sleep 0.3

grep -q 'additionalContext' "${stdout}" || fail "untrusted checkout lost loader injection"
grep -q 'trusted runtime configuration missing' "${stderr}" \
  || fail "untrusted checkout did not report the missing local trust record: $(cat "${stderr}")"
[[ ! -e "${MARKER}" ]] || fail "checkout-configured provider executed"
[[ ! -e "${WIKI}/.ingest.log" ]] || fail "untrusted hook wrote a checkout log"
[[ ! -e "${WIKI}/.ingest-runs.jsonl" ]] || fail "untrusted hook wrote run events"
if find "${WIKI}/.locks" -type f -print -quit 2>/dev/null | grep -q .; then
  fail "untrusted hook created lock state"
fi
[[ -f "${WIKI}/.wiki-pending/attacker-capture.md" ]] \
  || fail "untrusted hook claimed the pending capture"

set +e
tick_output="$(python3 "${REPO_ROOT}/scripts/wiki_dispatch.py" tick \
  --wiki "${WIKI}" --source manual --scan 2>&1)"
tick_rc=$?
set -e
[[ "${tick_rc}" -ne 0 ]] || fail "direct tick bypassed the trust gate"
grep -q 'trusted runtime configuration missing' <<< "${tick_output}" \
  || fail "direct tick trust refusal is not actionable"

(cd "${PROJECT}" && bash "${REPO_ROOT}/hooks/stop")
[[ ! -e "${WIKI}/.ingest.log" ]] || fail "untrusted Stop hook wrote a checkout log"
[[ -f "${WIKI}/.wiki-pending/attacker-capture.md" ]] \
  || fail "direct tick claimed the pending capture before trust validation"

echo "PASS: untrusted checkout is loader-only across hooks and direct tick"

# A checkout-owned project pointer must not be able to redirect capture into a
# different workspace's already-trusted wiki. This is a separate boundary from
# rejecting checkout-owned provider executables: the target runtime is valid,
# but it was trusted for another workspace.
TRUSTED_PROJECT="${TESTDIR}/trusted-project"
TRUSTED_WIKI="${TRUSTED_PROJECT}/wiki"
mkdir -p "${TRUSTED_PROJECT}"
bash "${REPO_ROOT}/scripts/wiki-init.sh" project "${TRUSTED_WIKI}" >/dev/null
python3 "${REPO_ROOT}/scripts/wiki_config.py" init-local \
  --wiki "${TRUSTED_WIKI}" \
  --trust-workspace "${TRUSTED_WIKI}" \
  --default-provider codex \
  --default-model test-model \
  --default-effort low >/dev/null

POINTER_ATTACK="${TESTDIR}/pointer-attacker"
mkdir -p "${POINTER_ATTACK}"
cat > "${POINTER_ATTACK}/.wiki-config" <<EOF
role = "project-pointer"
wiki = "${TRUSTED_WIKI}"
fork_to_main = false
EOF
printf 'none\n' > "${HOME}/.wiki-pointer"
BODY="${TESTDIR}/capture-body"
python3 - <<'PY' > "${BODY}"
print("attacker-controlled capture body " * 60)
PY
pending_before="$(find "${TRUSTED_WIKI}/.wiki-pending" -type f | wc -l | tr -d ' ')"
set +e
pointer_output="$(cd "${POINTER_ATTACK}" && \
  bash "${REPO_ROOT}/bin/wiki" capture --title redirected --kind chat-only \
    --body-file "${BODY}" 2>&1)"
pointer_rc=$?
set -e
[[ "${pointer_rc}" -ne 0 ]] || fail "untrusted project pointer redirected a capture"
pending_after="$(find "${TRUSTED_WIKI}/.wiki-pending" -type f | wc -l | tr -d ' ')"
[[ "${pending_after}" == "${pending_before}" ]] \
  || fail "untrusted project pointer wrote into a trusted wiki"

echo "PASS: checkout-defined pointers cannot cross trusted workspace boundaries"
