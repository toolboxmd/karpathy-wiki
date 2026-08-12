#!/bin/bash
# Real clean Claude sessions plus a temporary real macOS LaunchAgent acceptance.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
CLAUDE_EXECUTABLE="$(command -v claude || true)"
RUN_STAMP="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
RAW_RUN="${SCRIPT_DIR}/raw/${RUN_STAMP}-clean-sessions"

fail() { echo "FAIL: $*" >&2; exit 1; }
[[ -n "${CLAUDE_EXECUTABLE}" ]] || fail "claude executable is not available"

TMP_BASE="${TMPDIR:-/tmp}"
TESTDIR="$(mktemp -d "${TMP_BASE%/}/karpathy wiki clean session.XXXXXX")"
export WIKI_CONFIG_HOME="${TESTDIR}/trusted-config"
WIKI="${TESTDIR}/wiki with spaces"
SCHEDULER_HOME="${TESTDIR}/scheduler-home"
SESSION_START_TRANSCRIPT="${TESTDIR}/session-start.jsonl"
SESSION_START_STDERR="${TESTDIR}/session-start.stderr.log"
SCHEDULED_TRANSCRIPT="${TESTDIR}/scheduled.jsonl"
SCHEDULED_STDERR="${TESTDIR}/scheduled.stderr.log"
SCHEDULER_INSTALL_JSON="${TESTDIR}/scheduler-install.json"
SCHEDULER_STATUS_JSON="${TESTDIR}/scheduler-status.json"
SCHEDULER_UNINSTALL_JSON="${TESTDIR}/scheduler-uninstall.json"
SCHEDULER_LABEL=""
SCHEDULER_PLIST=""

preserve_raw() {
  local outcome="$1"
  mkdir -p "${RAW_RUN}"
  printf '%s\n' \
    "outcome=${outcome}" \
    "claude_version=$(${CLAUDE_EXECUTABLE} --version 2>/dev/null || echo unavailable)" \
    > "${RAW_RUN}/run-metadata.txt"
  for path in \
    "${SESSION_START_TRANSCRIPT}" "${SESSION_START_STDERR}" \
    "${SCHEDULED_TRANSCRIPT}" "${SCHEDULED_STDERR}" \
    "${SCHEDULER_INSTALL_JSON}" "${SCHEDULER_STATUS_JSON}" \
    "${SCHEDULER_UNINSTALL_JSON}"; do
    [[ -f "${path}" ]] && cp "${path}" "${RAW_RUN}/$(basename "${path}")"
  done
  [[ -f "${WIKI}/.ingest-runs.jsonl" ]] && cp "${WIKI}/.ingest-runs.jsonl" "${RAW_RUN}/ingest-runs.jsonl"
  [[ -f "${WIKI}/.ingest.log" ]] && cp "${WIKI}/.ingest.log" "${RAW_RUN}/ingest.log"
}

cleanup() {
  local rc=$?
  if [[ -n "${SCHEDULER_LABEL}" ]]; then
    launchctl bootout "gui/$(id -u)/${SCHEDULER_LABEL}" >/dev/null 2>&1 || true
  fi
  if [[ -n "${SCHEDULER_PLIST}" && "${SCHEDULER_PLIST}" == "${SCHEDULER_HOME}"/* ]]; then
    rm -f "${SCHEDULER_PLIST}"
  fi
  preserve_raw "$([[ "${rc}" -eq 0 ]] && echo passed || echo failed)" || true
  local attempt
  for attempt in $(seq 1 100); do
    rm -rf "${TESTDIR}" 2>/dev/null && break
    sleep 0.05
  done
  return "${rc}"
}
trap cleanup EXIT

bash "${REPO_ROOT}/scripts/wiki-init.sh" project "${WIKI}" >/dev/null
mkdir -p "${SCHEDULER_HOME}"
cat > "${WIKI}/.wiki-config.local" <<'EOF'
[ingest]
dispatch_mode = "session_start"
schedule_interval_seconds = 60
max_processes = 1
default_profile = "test"
max_attempts = 1
heartbeat_seconds = 5
stale_after_seconds = 30
usage_monitor = "off"

[ingest.profiles.test]
provider = "codex"
model = "test"
reasoning_effort = "low"
max_processes = 1

[settings]
auto_commit = false
EOF
python3 "${REPO_ROOT}/scripts/wiki_config.py" migrate-local \
  --wiki "${WIKI}" --trust-workspace "${WIKI}" >/dev/null
RUNTIME_CONFIG="$(python3 "${REPO_ROOT}/scripts/wiki_config.py" path --wiki "${WIKI}")"

NOW="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
cat > "${WIKI}/queries/acceptance-runtime-role.md" <<EOF
---
title: "Acceptance runtime role"
type: queries
tags: [acceptance, runtime]
sources: [conversation]
created: "${NOW}"
updated: "${NOW}"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 3
  overall: 4.50
  rated_at: "${NOW}"
  rated_by: human
---

This disposable acceptance fixture declares the project wiki role. It exists
only to prove that a clean parent session received and followed the loader.
EOF
python3 "${REPO_ROOT}/scripts/wiki-build-index.py" --wiki-root "${WIKI}" --rebuild-all

cat > "${WIKI}/.wiki-pending/session-start-capture.md" <<'EOF'
---
title: "SessionStart bounded tick acceptance"
---

Disposable runtime-only capture.
EOF

QUESTION='Using the wiki, what role does this disposable acceptance fixture declare? Follow the plugin rules already loaded, and answer in one short sentence.'

run_clean_claude() {
  local transcript="$1"
  local stderr_log="$2"
  (
    cd "${WIKI}"
    env -u WIKI_CAPTURE -u CLAUDE_AGENT_PARENT \
      WIKI_DISPATCH_TEST_MODE=1 \
      WIKI_DISPATCH_TEST_PROVIDER_MODE=complete_success \
      WIKI_DISPATCH_TEST_NO_REFILL=1 \
      "${CLAUDE_EXECUTABLE}" \
        --plugin-dir "${REPO_ROOT}" \
        --model sonnet \
        --effort low \
        --permission-mode auto \
        --no-chrome \
        --no-session-persistence \
        --setting-sources project \
        --include-hook-events \
        --output-format stream-json \
        --verbose \
        -p "${QUESTION}"
  ) > "${transcript}" 2> "${stderr_log}"
}

run_clean_claude "${SESSION_START_TRANSCRIPT}" "${SESSION_START_STDERR}"

deadline=$((SECONDS + 10))
while [[ "${SECONDS}" -lt "${deadline}" ]]; do
  if find "${WIKI}/.wiki-pending/archive" -type f -name 'session-start-capture.md' 2>/dev/null | grep -q .; then
    break
  fi
  sleep 0.05
done
find "${WIKI}/.wiki-pending/archive" -type f -name 'session-start-capture.md' 2>/dev/null | grep -q . \
  || fail "clean SessionStart did not run one bounded tick"

python3 - "${SESSION_START_TRANSCRIPT}" <<'PY' \
  || fail "clean SessionStart transcript is missing loader evidence"
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text(errors="replace")
assert "Using the karpathy-wiki skill to" in text
assert "answer from wiki" in text
assert "SessionStart" in text
PY

event_lines_before="$(wc -l < "${WIKI}/.ingest-runs.jsonl" | tr -d ' ')"
python3 "${REPO_ROOT}/scripts/wiki_config.py" update-runtime \
  --wiki "${WIKI}" --dispatch-mode scheduled >/dev/null
cat > "${WIKI}/.wiki-pending/scheduled-loader-only.md" <<'EOF'
---
title: "Scheduled loader-only acceptance"
---

This capture must remain pending during a clean SessionStart.
EOF
printf '%s\n' 'This source must not be scanned by SessionStart in scheduled mode.' \
  > "${WIKI}/inbox/scheduled-source.md"
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S')" "${WIKI}/inbox/scheduled-source.md"

run_clean_claude "${SCHEDULED_TRANSCRIPT}" "${SCHEDULED_STDERR}"
sleep 0.5

event_lines_after="$(wc -l < "${WIKI}/.ingest-runs.jsonl" | tr -d ' ')"
[[ "${event_lines_after}" -eq "${event_lines_before}" ]] \
  || fail "scheduled-mode SessionStart dispatched queue work"
[[ -f "${WIKI}/.wiki-pending/scheduled-loader-only.md" ]] \
  || fail "scheduled-mode SessionStart claimed a pending capture"
[[ -f "${WIKI}/inbox/scheduled-source.md" ]] \
  || fail "scheduled-mode SessionStart moved the inbox source"
if compgen -G "${WIKI}/.wiki-pending/drift-*scheduled-source*" >/dev/null; then
  fail "scheduled-mode SessionStart scanned the inbox"
fi
python3 - "${SCHEDULED_TRANSCRIPT}" <<'PY' \
  || fail "scheduled-mode clean transcript is missing loader evidence"
import pathlib, sys
text = pathlib.Path(sys.argv[1]).read_text(errors="replace")
assert "Using the karpathy-wiki skill to" in text
assert "answer from wiki" in text
assert "SessionStart" in text
PY

# Prove the real macOS adapter runs one short scheduled tick. The LaunchAgent
# lives under a temporary HOME and is uninstalled before the fixture is removed.
rm -f "${WIKI}/.wiki-pending/scheduled-loader-only.md" "${WIKI}/inbox/scheduled-source.md"
FAKE_CODEX="${TESTDIR}/fake-codex"
cat > "${FAKE_CODEX}" <<'EOF'
#!/bin/bash
exec /bin/bash "${WIKI_PLUGIN_ROOT}/scripts/wiki-complete-ingest.sh"
EOF
chmod +x "${FAKE_CODEX}"
python3 - "${RUNTIME_CONFIG}" "${FAKE_CODEX}" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
text = path.read_text()
text = text.replace('model = "test"', 'model = "acceptance-fake"')
text = text.replace('reasoning_effort = "low"', 'reasoning_effort = "minimal"')
text = text.replace('executable = "codex"', 'executable = ' + json.dumps(sys.argv[2]))
path.write_text(text)
PY
python3 "${REPO_ROOT}/scripts/wiki_config.py" validate --wiki "${WIKI}" >/dev/null
cat > "${WIKI}/.wiki-pending/launchagent-capture.md" <<'EOF'
---
title: "Real LaunchAgent short tick acceptance"
---

Disposable runtime-only capture.
EOF

HOME="${SCHEDULER_HOME}" bash "${REPO_ROOT}/bin/wiki" scheduler install "${WIKI}" --json \
  > "${SCHEDULER_INSTALL_JSON}"
SCHEDULER_LABEL="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["label"])' "${SCHEDULER_INSTALL_JSON}")"
SCHEDULER_PLIST="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["plist"])' "${SCHEDULER_INSTALL_JSON}")"

deadline=$((SECONDS + 20))
while [[ "${SECONDS}" -lt "${deadline}" ]]; do
  if find "${WIKI}/.wiki-pending/archive" -type f -name 'launchagent-capture.md' 2>/dev/null | grep -q .; then
    break
  fi
  sleep 0.1
done
find "${WIKI}/.wiki-pending/archive" -type f -name 'launchagent-capture.md' 2>/dev/null | grep -q . \
  || fail "real LaunchAgent did not invoke a short scheduled tick"

# The archive move happens just before the wrapper writes its terminal event.
# Wait for the complete lifecycle, not merely the first observable file move.
deadline=$((SECONDS + 10))
while [[ "${SECONDS}" -lt "${deadline}" ]]; do
  completed_count="$(python3 - "${WIKI}/.ingest-runs.jsonl" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
count = 0
if path.exists():
    for line in path.read_text().splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        count += event.get("capture") == "launchagent-capture.md" and event.get("status") == "completed"
print(count)
PY
)"
  active_leases="$(find "${WIKI}/.locks/ingest-slots" -type f -name '*.lock' 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "${completed_count}" -eq 1 && "${active_leases}" -eq 0 ]]; then
    break
  fi
  sleep 0.05
done
[[ "${completed_count:-0}" -eq 1 && "${active_leases:-1}" -eq 0 ]] \
  || fail "real LaunchAgent archived before the wrapper closed and released the run"

HOME="${SCHEDULER_HOME}" bash "${REPO_ROOT}/bin/wiki" scheduler status "${WIKI}" --json \
  > "${SCHEDULER_STATUS_JSON}"
python3 - "${SCHEDULER_STATUS_JSON}" <<'PY' || fail "real LaunchAgent status is not installed"
import json, sys
data = json.load(open(sys.argv[1]))
assert data["state"] == "installed" and data["loaded"] is True
PY

HOME="${SCHEDULER_HOME}" bash "${REPO_ROOT}/bin/wiki" scheduler uninstall "${WIKI}" --json \
  > "${SCHEDULER_UNINSTALL_JSON}"
python3 - "${SCHEDULER_UNINSTALL_JSON}" "${SCHEDULER_PLIST}" <<'PY' \
  || fail "real LaunchAgent uninstall did not clean up exact state"
import json, pathlib, sys
data = json.load(open(sys.argv[1]))
assert data["state"] == "not installed" and data["loaded"] is False
assert data["configured_mode"] == "session_start"
assert not pathlib.Path(sys.argv[2]).exists()
PY
SCHEDULER_LABEL=""
SCHEDULER_PLIST=""

echo "PASS: clean SessionStart transcript contains the loader announce and one bounded tick"
echo "PASS: clean scheduled-mode transcript contains the loader and performs no SessionStart queue work"
echo "PASS: temporary real LaunchAgent invoked one short scheduled tick and was uninstalled"
echo "Raw ignored acceptance evidence: ${RAW_RUN}"
