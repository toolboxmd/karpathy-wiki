#!/bin/bash
# Completion must refill a bounded two-slot queue without exceeding the ceiling.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DISPATCH="${REPO_ROOT}/scripts/wiki_dispatch.py"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
cleanup() {
  local attempt
  for attempt in $(seq 1 100); do
    rm -rf "${TESTDIR}" 2>/dev/null && return 0
    sleep 0.05
  done
  rm -rf "${TESTDIR}"
}
trap cleanup EXIT

WIKI="${TESTDIR}/wiki"
bash "${REPO_ROOT}/scripts/wiki-init.sh" project "${WIKI}" >/dev/null
cat > "${WIKI}/.wiki-config.local" <<'EOF'
[ingest]
dispatch_mode = "scheduled"
max_processes = 2
default_profile = "test"
max_attempts = 1
heartbeat_seconds = 5
stale_after_seconds = 30
usage_monitor = "off"

[ingest.profiles.test]
provider = "codex"
model = "test"
reasoning_effort = "low"
max_processes = 2

[settings]
auto_commit = false
EOF

for number in 1 2 3 4 5; do
  printf '%s\n' '---' "title: \"Capture ${number}\"" '---' \
    > "${WIKI}/.wiki-pending/0${number}.md"
done

WIKI_DISPATCH_TEST_MODE=1 \
WIKI_DISPATCH_TEST_PROVIDER_MODE=complete_success \
  python3 "${DISPATCH}" tick --wiki "${WIKI}" --source manual

deadline=$((SECONDS + 10))
while [[ "${SECONDS}" -lt "${deadline}" ]]; do
  archived="$(find "${WIKI}/.wiki-pending/archive" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
  leases="$(find "${WIKI}/.locks/ingest-slots" -type f -name '*.lock' 2>/dev/null | wc -l | tr -d ' ')"
  if [[ "${archived}" -eq 5 && "${leases}" -eq 0 ]]; then
    break
  fi
  sleep 0.05
done

[[ "${archived:-0}" -eq 5 ]] || fail "expected five archived captures, got ${archived:-0}"
[[ "${leases:-1}" -eq 0 ]] || fail "slot leases remain after queue drain"
if find "${WIKI}/.wiki-pending" -maxdepth 1 -type f \( -name '*.md' -o -name '*.processing' \) | grep -q .; then
  fail "pending or processing captures remain after queue drain"
fi

python3 - "${WIKI}/.ingest-runs.jsonl" <<'PY' || fail "refill event history violated the ceiling"
import json
import sys

events = [json.loads(line) for line in open(sys.argv[1]) if line.strip()]
active = 0
maximum = 0
started = set()
completed = set()
for event in events:
    run_id = event.get("run_id")
    status = event.get("status")
    if status == "started":
        assert run_id not in started
        started.add(run_id)
        active += 1
        maximum = max(maximum, active)
    elif status == "completed":
        assert run_id in started and run_id not in completed
        completed.add(run_id)
        active -= 1
        assert active >= 0

assert len(started) == len(completed) == 5, (len(started), len(completed))
assert maximum <= 2, maximum
assert active == 0
PY

echo "PASS: completion refills five captures through two slots without exceeding max_processes=2"
