#!/bin/bash
# RED: spawn-ingester prompt must reference the current split skill, not the
# deleted v2.4 monolith.
#
# Bug (0.2.8 #5): scripts/wiki-spawn-ingester.sh:53 builds the ingest prompt
# but says only "Follow the karpathy-wiki skill's INGEST operation exactly."
# That phrasing is ambiguous in the v2.4 split world — the legacy
# `skills/karpathy-wiki/SKILL.md` was deleted and the ingest contract now
# lives in `skills/karpathy-wiki-ingest/SKILL.md`. The prompt must point at
# the current skill explicitly so a fresh spawned ingester loads the right
# operational surface.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SPAWNER="${REPO_ROOT}/scripts/wiki-spawn-ingester.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "${SPAWNER}" ]] || fail "spawner missing: ${SPAWNER}"

# Extract the prompt template line(s). The prompt is built between
# `prompt="..."` and the next blank line.
prompt_block=$(awk '/^prompt="/,/^$/' "${SPAWNER}")

[[ -n "${prompt_block}" ]] || fail "could not extract prompt block from spawner"

# MUST NOT reference the deleted monolith.
if echo "${prompt_block}" | grep -q 'skills/karpathy-wiki/SKILL\.md'; then
  fail "prompt references deleted monolith skills/karpathy-wiki/SKILL.md"
fi

# MUST reference the current ingest skill so the spawned ingester loads the
# right operational contract.
if ! echo "${prompt_block}" | grep -q 'skills/karpathy-wiki-ingest/SKILL\.md'; then
  fail "prompt does not reference skills/karpathy-wiki-ingest/SKILL.md"
fi

echo "PASS: spawner prompt references skills/karpathy-wiki-ingest/SKILL.md and not the deleted monolith"
