#!/bin/bash
# Global scheduler lifecycle against a fake launchctl and temporary HOME only.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WIKI_BIN="${REPO_ROOT}/bin/wiki"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"
PYTHON_REAL="$(python3 -c 'import sys; print(sys.executable)')"

fail() { echo "FAIL: $*" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
export HOME="${TMP}/home"
export WIKI_CONFIG_HOME="${TMP}/config-home"
export WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME=1
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
export PATH="${TMP}/fake-bin:$(dirname "${PYTHON_REAL}"):/usr/bin:/bin"

write_config() {
  local root="$1"
  local mode="${2:-session_start}"
  cat > "${root}/.wiki-config.local" <<EOF
[ingest]
dispatch_mode = "${mode}"
schedule_interval_seconds = 61
max_processes = 3
default_profile = "test"
heartbeat_seconds = 5
stale_after_seconds = 30
usage_monitor = "off"

[ingest.profiles.test]
provider = "codex"
model = "test"
reasoning_effort = "low"
max_processes = 3

[settings]
auto_commit = false
EOF
}

config_value() {
  python3 "${REPO_ROOT}/scripts/wiki-config-read.py" "$1/.wiki-config.local" "$2"
}

global_plist() {
  printf '%s/Library/LaunchAgents/com.toolboxmd.karpathy-wiki.scheduler.plist\n' "${HOME}"
}

WIKI_ONE="${TMP}/Wiki One"
WIKI_TWO="${TMP}/Wiki Two"
bash "${INIT}" main "${WIKI_ONE}" >/dev/null
bash "${INIT}" project "${WIKI_TWO}" >/dev/null
write_config "${WIKI_ONE}" session_start
write_config "${WIKI_TWO}" session_start

# Global install creates exactly one constant-label plist and does not enable a wiki.
bash "${WIKI_BIN}" scheduler install >/dev/null \
  || fail "global scheduler install failed"
PLIST="$(global_plist)"
[[ -f "${PLIST}" ]] || fail "global scheduler plist was not created"
[[ "$(config_value "${WIKI_ONE}" ingest.dispatch_mode)" == "session_start" ]] \
  || fail "global install changed wiki activation"
python3 - "${PLIST}" <<'PY'
import plistlib, sys
with open(sys.argv[1], "rb") as handle:
    data = plistlib.load(handle)
assert data["Label"] == "com.toolboxmd.karpathy-wiki.scheduler"
assert data["ProgramArguments"][1:] == ["scheduler", "tick-all"]
assert data["StartInterval"] == 60
PY

# Reinstall is idempotent and keeps the same global plist.
before="$(shasum -a 256 "${PLIST}")"
bash "${WIKI_BIN}" scheduler install >/dev/null \
  || fail "idempotent global scheduler reinstall failed"
[[ "$(shasum -a 256 "${PLIST}")" == "${before}" ]] \
  || fail "idempotent global reinstall rewrote the plist unexpectedly"

# Enable and disable mutate only the requested wiki runtime.
bash "${WIKI_BIN}" scheduler enable "${WIKI_ONE}" >/dev/null \
  || fail "scheduler enable failed"
[[ "$(config_value "${WIKI_ONE}" ingest.dispatch_mode)" == "scheduled" ]] \
  || fail "enable did not switch selected wiki to scheduled"
[[ "$(config_value "${WIKI_TWO}" ingest.dispatch_mode)" == "session_start" ]] \
  || fail "enable changed another wiki"
bash "${WIKI_BIN}" scheduler disable "${WIKI_ONE}" >/dev/null \
  || fail "scheduler disable failed"
[[ "$(config_value "${WIKI_ONE}" ingest.dispatch_mode)" == "session_start" ]] \
  || fail "disable did not switch selected wiki to session_start"

# v0.3.0 compatibility: install <wiki> installs global scheduler and enables only that wiki.
bash "${WIKI_BIN}" scheduler install "${WIKI_TWO}" >/dev/null \
  || fail "compat scheduler install <wiki> failed"
[[ "$(config_value "${WIKI_TWO}" ingest.dispatch_mode)" == "scheduled" ]] \
  || fail "compat install did not enable the selected wiki"
compat_out="$(bash "${WIKI_BIN}" scheduler uninstall "${WIKI_TWO}")"
grep -Fq 'disabled wiki; global scheduler left installed' <<< "${compat_out}" \
  || fail "compat uninstall did not leave the global scheduler installed"
[[ -f "${PLIST}" ]] || fail "compat uninstall removed global scheduler"

# Status detects global health and per-wiki mismatch.
python3 "${REPO_ROOT}/scripts/wiki_config.py" update-runtime \
  --wiki "${WIKI_ONE}" --dispatch-mode scheduled >/dev/null
rm -f "${WIKI_SCHEDULER_TEST_STATE}/com.toolboxmd.karpathy-wiki.scheduler"
status_out="$(bash "${WIKI_BIN}" scheduler status)"
grep -Fq 'state: mismatch' <<< "${status_out}" \
  || fail "global status missed plist-present but unloaded mismatch"
status_wiki="$(bash "${WIKI_BIN}" scheduler status "${WIKI_ONE}")"
grep -Fq 'state: mismatch' <<< "${status_wiki}" \
  || fail "per-wiki status missed scheduled without loaded global scheduler"

# A failed bootstrap on a fresh HOME leaves no plist.
BROKEN_HOME="${TMP}/broken-home"
mkdir -p "${BROKEN_HOME}"
export HOME="${BROKEN_HOME}"
export WIKI_SCHEDULER_TEST_FAIL_BOOTSTRAP=1
bash "${WIKI_BIN}" scheduler install >/dev/null 2>&1 \
  && fail "injected bootstrap failure should fail install"
unset WIKI_SCHEDULER_TEST_FAIL_BOOTSTRAP
[[ ! -e "$(global_plist)" ]] || fail "failed global install left a plist"

echo "PASS: global scheduler install/reinstall/enable/disable/status lifecycle"
