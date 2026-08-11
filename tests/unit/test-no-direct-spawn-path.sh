#!/bin/bash
# The bounded dispatcher is the only runtime path allowed to claim or launch
# ingest work. Legacy command-string spawning must not silently return.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ ! -e "${REPO_ROOT}/scripts/wiki-spawn-ingester.sh" ]] \
  || fail "legacy direct spawner still exists"

if rg -n 'wiki-spawn-ingester|headless_command|claude[[:space:]]+-p' \
    "${REPO_ROOT}/bin" "${REPO_ROOT}/hooks" \
    "${REPO_ROOT}/scripts/wiki-ingest-now.sh" \
    "${REPO_ROOT}/scripts/wiki-complete-ingest.sh" \
    "${REPO_ROOT}/scripts/wiki_dispatch.py" \
    "${REPO_ROOT}/scripts/wiki_providers.py" >/dev/null; then
  fail "a runtime entrypoint still contains a legacy direct-spawn path"
fi

grep -Fq '"karpathy-wiki-ingest"' "${REPO_ROOT}/scripts/wiki_providers.py" \
  || fail "provider adapters do not point workers at the current ingest skill"
grep -Fq '"SKILL.md"' "${REPO_ROOT}/scripts/wiki_providers.py" \
  || fail "provider adapters do not load the ingest skill entrypoint"

echo "PASS: bounded dispatcher is the only ingest launch path"
