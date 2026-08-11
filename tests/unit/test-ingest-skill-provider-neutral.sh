#!/bin/bash
# Provider identity and deterministic lifecycle ownership in the ingest skill.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SKILL="${REPO_ROOT}/skills/karpathy-wiki-ingest/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

if rg -n 'detached `claude -p` ingester|For the spawned `claude -p` ingester' "${SKILL}" >/dev/null; then
  fail "skill still assigns a Claude-specific ingester identity"
fi
if rg -ni 'cheap model' "${SKILL}" >/dev/null; then
  fail "skill still implies a second, nested model"
fi
rg -q 'detached wiki ingester' "${SKILL}" || fail "provider-neutral ingester identity missing"
rg -qi 'must not (launch|delegate).*another (model|agentic CLI)|do not (launch|delegate).*another (model|agentic CLI)' "${SKILL}" \
  || fail "cross-provider delegation guard missing"
rg -q 'WIKI_RUN_ID' "${SKILL}" || fail "runtime-provided run ID is not documented"
rg -q 'wiki-complete-ingest.sh' "${SKILL}" || fail "deterministic completion helper missing"
grep -Fq 'date -u +%Y-%m-%dT%H:%M:%SZ' "${SKILL}" \
  || fail "ingest skill does not pin generated metadata timestamps to UTC"

if rg -n 'RUN_ID="in-|ingest-runs\.lock|printf .*status.*spawned' "${SKILL}" >/dev/null; then
  fail "skill still asks the model to implement run-history mechanics"
fi

echo "PASS: ingest skill is provider-neutral and delegates lifecycle to runtime code"
