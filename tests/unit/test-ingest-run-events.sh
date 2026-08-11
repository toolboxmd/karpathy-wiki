#!/bin/bash
# Locked JSONL run events: concurrency, malformed history, and idempotence.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
PYTHONPATH="${REPO_ROOT}/scripts"
export PYTHONPATH

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT
WIKI="${TESTDIR}/wiki"
mkdir -p "${WIKI}/.locks"

pids=()
for i in $(seq 1 10); do
  python3 -c 'import sys; from wiki_dispatch import append_run_event; append_run_event(sys.argv[1], {"run_id": f"in-{sys.argv[2]}", "capture": "x.md", "status": "started", "at": "2026-08-11T00:00:00Z"})' "${WIKI}" "${i}" &
  pids+=("$!")
done
for pid in "${pids[@]}"; do wait "${pid}" || fail "concurrent event append failed"; done

python3 - "${WIKI}/.ingest-runs.jsonl" <<'PY' || fail "event lines are not valid JSONL"
import json, pathlib, sys
lines = pathlib.Path(sys.argv[1]).read_text().splitlines()
assert len(lines) == 10
assert len({json.loads(line)["run_id"] for line in lines}) == 10
PY

# One malformed complete line and one truncated final line must not hide the
# valid history before them.
printf '%s\n' '{malformed}' >> "${WIKI}/.ingest-runs.jsonl"
printf '%s' '{"run_id":"partial"' >> "${WIKI}/.ingest-runs.jsonl"
python3 - "${WIKI}" <<'PY' || fail "robust event reader contract failed"
import sys
from wiki_dispatch import read_run_events
events, malformed = read_run_events(sys.argv[1])
assert len(events) == 10, len(events)
assert malformed == 2, malformed
PY

# Rebuild a clean log, then assert a terminal status is append-once per run.
: > "${WIKI}/.ingest-runs.jsonl"
python3 - "${WIKI}" <<'PY' || fail "terminal event idempotence failed"
import pathlib, sys
from wiki_dispatch import append_run_event, read_run_events
root = sys.argv[1]
event = {"run_id": "in-terminal", "capture": "x.md", "status": "completed", "at": "2026-08-11T00:00:00Z"}
assert append_run_event(root, event, idempotent_terminal=True) is True
assert append_run_event(root, event, idempotent_terminal=True) is False
events, malformed = read_run_events(root)
assert malformed == 0
assert [e["status"] for e in events] == ["completed"]
PY

echo "PASS: run events are concurrent-safe, robust, and terminal-idempotent"
