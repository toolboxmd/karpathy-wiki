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
