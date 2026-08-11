#!/bin/bash
# Scheduler lifecycle against a fake launchctl and temporary HOME only.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WIKI_BIN="${REPO_ROOT}/bin/wiki"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"
PYTHON="$(command -v python3)"

fail() { echo "FAIL: $*" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
export HOME="${TMP}/home"
mkdir -p "${HOME}" "${TMP}/fake-bin" "${TMP}/launch-state"
export WIKI_SCHEDULER_TEST_STATE="${TMP}/launch-state"
export WIKI_SCHEDULER_TEST_LOG="${TMP}/launchctl.log"

cat > "${TMP}/fake-bin/launchctl" <<'SH'
#!/bin/bash
set -e
printf '%s\n' "$*" >> "${WIKI_SCHEDULER_TEST_LOG}"
case "$1" in
  print)
    label="${2##*/}"
    [[ -f "${WIKI_SCHEDULER_TEST_STATE}/${label}" ]]
    ;;
  bootstrap)
    [[ "${WIKI_SCHEDULER_TEST_FAIL_BOOTSTRAP:-0}" != "1" ]] || exit 5
    label="$(basename "$3" .plist)"
    : > "${WIKI_SCHEDULER_TEST_STATE}/${label}"
    ;;
  bootout)
    label="${2##*/}"
    rm -f "${WIKI_SCHEDULER_TEST_STATE}/${label}"
    ;;
  *) exit 64 ;;
esac
SH
chmod +x "${TMP}/fake-bin/launchctl"
export PATH="${TMP}/fake-bin:$(dirname "${PYTHON}"):/usr/bin:/bin"

write_config() {
  local root="$1"
  local interval="${2:-60}"
  cat > "${root}/.wiki-config.local" <<EOF
[ingest]
dispatch_mode = "session_start"
schedule_interval_seconds = ${interval}
max_processes = 1
default_profile = "test"
heartbeat_seconds = 5
stale_after_seconds = 30
usage_monitor = "off"

[ingest.profiles.test]
provider = "codex"
model = "test"
reasoning_effort = "low"

[settings]
auto_commit = false
EOF
}

config_value() {
  python3 "${REPO_ROOT}/scripts/wiki-config-read.py" "$1/.wiki-config.local" "$2"
}

plist_for() {
  find "${HOME}/Library/LaunchAgents" -maxdepth 1 -name 'com.toolboxmd.karpathy-wiki.*.plist' -type f \
    | while IFS= read -r path; do
        if /usr/bin/grep -Fq "$1" "${path}"; then printf '%s\n' "${path}"; fi
      done
}

WIKI_ONE="${TMP}/Wiki One"
bash "${INIT}" main "${WIKI_ONE}" >/dev/null
write_config "${WIKI_ONE}" 61

# Install changes mode only after successful bootstrap.
bash "${WIKI_BIN}" scheduler install "${WIKI_ONE}" >/dev/null \
  || fail "scheduler install failed"
[[ "$(config_value "${WIKI_ONE}" ingest.dispatch_mode)" == "scheduled" ]] \
  || fail "install did not switch mode to scheduled"
PLIST_ONE="$(plist_for "$(cd "${WIKI_ONE}" && pwd -P)")"
[[ -f "${PLIST_ONE}" ]] || fail "install did not create the wiki LaunchAgent"
python3 - "${PLIST_ONE}" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as handle:
    data = plistlib.load(handle)
assert data["StartInterval"] == 61
assert data["ProgramArguments"][2].endswith("Wiki One")
PY

# Reinstall is idempotent and updates a changed interval.
sed -i.bak 's/schedule_interval_seconds = 61/schedule_interval_seconds = 97/' \
  "${WIKI_ONE}/.wiki-config.local"
rm -f "${WIKI_ONE}/.wiki-config.local.bak"
bash "${WIKI_BIN}" scheduler install "${WIKI_ONE}" >/dev/null \
  || fail "idempotent scheduler reinstall failed"
python3 - "${PLIST_ONE}" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as handle:
    assert plistlib.load(handle)["StartInterval"] == 97
PY

# A failed bootstrap on a fresh wiki leaves both mode and plist untouched.
WIKI_FAIL="${TMP}/Wiki Failing"
bash "${INIT}" project "${WIKI_FAIL}" >/dev/null
write_config "${WIKI_FAIL}" 60
export WIKI_SCHEDULER_TEST_FAIL_BOOTSTRAP=1
bash "${WIKI_BIN}" scheduler install "${WIKI_FAIL}" >/dev/null 2>&1 \
  && fail "injected bootstrap failure should fail install"
unset WIKI_SCHEDULER_TEST_FAIL_BOOTSTRAP
[[ "$(config_value "${WIKI_FAIL}" ingest.dispatch_mode)" == "session_start" ]] \
  || fail "failed bootstrap changed dispatch mode"
[[ -z "$(plist_for "$(cd "${WIKI_FAIL}" && pwd -P)")" ]] \
  || fail "failed bootstrap left a new plist installed"

# A second installed wiki proves uninstall targets only the requested label.
WIKI_TWO="${TMP}/Wiki Two"
bash "${INIT}" project "${WIKI_TWO}" >/dev/null
write_config "${WIKI_TWO}" 71
bash "${WIKI_BIN}" scheduler install "${WIKI_TWO}" >/dev/null \
  || fail "second scheduler install failed"
PLIST_TWO="$(plist_for "$(cd "${WIKI_TWO}" && pwd -P)")"
bash "${WIKI_BIN}" scheduler uninstall "${WIKI_ONE}" >/dev/null \
  || fail "scheduler uninstall failed"
[[ "$(config_value "${WIKI_ONE}" ingest.dispatch_mode)" == "session_start" ]] \
  || fail "uninstall did not switch the exact wiki to session_start"
[[ ! -e "${PLIST_ONE}" ]] || fail "uninstall left the exact wiki plist"
[[ -e "${PLIST_TWO}" ]] || fail "uninstall removed another wiki's plist"

# Status reports both mismatch directions without mutating anything.
python3 "${REPO_ROOT}/scripts/wiki_config.py" update-runtime \
  --wiki "${WIKI_TWO}" --dispatch-mode session_start >/dev/null
status_out="$(bash "${WIKI_BIN}" scheduler status "${WIKI_TWO}")"
grep -Fq 'state: mismatch' <<< "${status_out}" \
  || fail "status missed installed + session_start mismatch"

python3 "${REPO_ROOT}/scripts/wiki_config.py" update-runtime \
  --wiki "${WIKI_FAIL}" --dispatch-mode scheduled >/dev/null
status_out="$(bash "${WIKI_BIN}" scheduler status "${WIKI_FAIL}")"
grep -Fq 'state: mismatch' <<< "${status_out}" \
  || fail "status missed scheduled + not-installed mismatch"

# Without launchctl, install is actionable and leaves config unchanged.
NO_LAUNCHCTL_PATH="$(dirname "${PYTHON}")"
set +e
missing_out="$(PATH="${NO_LAUNCHCTL_PATH}" "${PYTHON}" \
  "${REPO_ROOT}/scripts/wiki_scheduler.py" install --wiki "${WIKI_FAIL}" 2>&1)"
missing_rc=$?
set -e
[[ "${missing_rc}" -ne 0 ]] || fail "missing launchctl should fail"
grep -Fq 'launchctl is unavailable' <<< "${missing_out}" \
  || fail "missing launchctl error is not actionable"
[[ "$(config_value "${WIKI_FAIL}" ingest.dispatch_mode)" == "scheduled" ]] \
  || fail "missing launchctl changed config"

echo "PASS: scheduler install/reinstall/failure/uninstall/status lifecycle"
