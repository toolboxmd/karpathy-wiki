#!/bin/bash
# Concurrent ticks must never exceed the configured per-wiki process ceiling.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DISPATCH="${REPO_ROOT}/scripts/wiki_dispatch.py"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
cleanup() {
  local lease pid
  while IFS= read -r lease; do
    [[ -n "${lease}" ]] || continue
    pid="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1])).get("wrapper_pid", ""))' "${lease}" 2>/dev/null || true)"
    [[ "${pid}" =~ ^[0-9]+$ ]] && kill "${pid}" 2>/dev/null || true
  done < <(find "${TESTDIR}" -type f -path '*/.locks/ingest-slots/*.lock' 2>/dev/null || true)
  rm -rf "${TESTDIR}"
}
trap cleanup EXIT
WIKI="${TESTDIR}/wiki"
mkdir -p "${WIKI}/.wiki-pending"
printf '# Schema\n' > "${WIKI}/schema.md"
printf '# Index\n' > "${WIKI}/index.md"
printf 'role = "project"\ncreated = "2026-08-11"\n' > "${WIKI}/.wiki-config"
cat > "${WIKI}/.wiki-config.local" <<'EOF'
[ingest]
dispatch_mode = "scheduled"
max_processes = 3
default_profile = "test_profile"
heartbeat_seconds = 5
stale_after_seconds = 30
usage_monitor = "off"

[ingest.profiles.test_profile]
provider = "codex"
model = "test-model"
reasoning_effort = "low"
max_processes = 3

[settings]
auto_commit = false
EOF

for i in $(seq -w 1 20); do
  printf 'capture %s\n' "${i}" > "${WIKI}/.wiki-pending/${i}.md"
done

pids=()
for _ in $(seq 1 10); do
  WIKI_DISPATCH_TEST_MODE=1 \
  WIKI_DISPATCH_TEST_WORKER_HOLD_SECONDS=10 \
    python3 "${DISPATCH}" tick --wiki "${WIKI}" --source manual &
  pids+=("$!")
done

for pid in "${pids[@]}"; do wait "${pid}" || fail "a concurrent tick failed"; done

processing="$(find "${WIKI}/.wiki-pending" -maxdepth 1 -type f -name '*.md.processing' | wc -l | tr -d ' ')"
leases="$(find "${WIKI}/.locks/ingest-slots" -maxdepth 1 -type f -name '*.lock' | wc -l | tr -d ' ')"
[[ "${processing}" -eq 3 ]] || fail "expected three processing captures after concurrent ticks, got ${processing}"
[[ "${leases}" -eq 3 ]] || fail "expected three leases after concurrent ticks, got ${leases}"

python3 - "${WIKI}/.locks/ingest-slots" <<'PY'
import json, pathlib, sys
leases = sorted(pathlib.Path(sys.argv[1]).glob("*.lock"))
slots = []
for path in leases:
    data = json.loads(path.read_text())
    slots.append(data["slot"])
    assert data["wrapper_pid"] > 0
    assert data["capture"].endswith(".md.processing")
assert len(slots) == len(set(slots)) == 3
PY

echo "PASS: ten concurrent ticks respect max_processes=3"
