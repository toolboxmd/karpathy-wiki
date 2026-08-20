#!/bin/bash
# A live provider child keeps the processing capture fresh.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DISPATCH="${REPO_ROOT}/scripts/wiki_dispatch.py"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
cleanup() {
  local lease pid provider
  for lease in "${TESTDIR}"/wiki/.locks/ingest-slots/*.lock; do
    [[ -f "${lease}" ]] || continue
    pid="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("wrapper_pid", ""))' "${lease}" 2>/dev/null || true)"
    provider="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("provider_pid", ""))' "${lease}" 2>/dev/null || true)"
    [[ "${pid}" =~ ^[0-9]+$ ]] && kill "${pid}" 2>/dev/null || true
    [[ "${provider}" =~ ^[0-9]+$ ]] && kill "${provider}" 2>/dev/null || true
  done
  sleep 0.2
  rm -rf "${TESTDIR}"
}
trap cleanup EXIT
WIKI="${TESTDIR}/wiki"
mkdir -p "${WIKI}/.wiki-pending"
printf '# Schema\n' > "${WIKI}/schema.md"
printf '# Index\n' > "${WIKI}/index.md"
printf 'role = "project"\n' > "${WIKI}/.wiki-config"
cat > "${WIKI}/.wiki-config.local" <<'EOF'
[ingest]
dispatch_mode = "scheduled"
max_processes = 1
default_profile = "p"
heartbeat_seconds = 5
stale_after_seconds = 30
usage_monitor = "off"
max_attempts = 4
[ingest.profiles.p]
provider = "codex"
model = "test"
reasoning_effort = "low"
[settings]
auto_commit = false
EOF
printf 'heartbeat\n' > "${WIKI}/.wiki-pending/heartbeat.md"

# Keep the fake provider alive well beyond slow Cloud worker startup. Cleanup
# terminates it after the heartbeat assertions, so this does not extend runtime.
WIKI_DISPATCH_TEST_MODE=1 \
WIKI_DISPATCH_TEST_PROVIDER_MODE=hold \
WIKI_DISPATCH_TEST_PROVIDER_SECONDS=10 \
WIKI_DISPATCH_TEST_HEARTBEAT_SECONDS=0.1 \
WIKI_DISPATCH_TEST_NO_REFILL=1 \
  python3 "${DISPATCH}" tick --wiki "${WIKI}" --source manual

processing="${WIKI}/.wiki-pending/heartbeat.md.processing"
for _ in $(seq 1 100); do [[ -f "${processing}" ]] && break; sleep 0.01; done
[[ -f "${processing}" ]] || fail "worker never claimed capture"
before="$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_mtime_ns)' "${processing}")"
sleep 0.35
after="$(python3 -c 'import os,sys; print(os.stat(sys.argv[1]).st_mtime_ns)' "${processing}")"
[[ "${after}" -gt "${before}" ]] || fail "processing mtime was not refreshed by heartbeat"

python3 - "${WIKI}/.locks/ingest-slots/1.lock" <<'PY' || fail "lease does not record provider PID"
import json, sys
lease = json.load(open(sys.argv[1]))
assert lease["wrapper_pid"] > 0
assert lease["provider_pid"] > 0
PY

echo "PASS: live worker refreshes heartbeat and records both PIDs"
