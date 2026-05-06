#!/bin/bash
# Verify the using-karpathy-wiki loader skill exists and has the required structure.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOADER="${REPO_ROOT}/skills/using-karpathy-wiki/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "${LOADER}" ]] || fail "loader file missing: ${LOADER}"

# Frontmatter has name, description, and is short
head -20 "${LOADER}" | grep -q '^name: using-karpathy-wiki' || fail "frontmatter missing name"
head -20 "${LOADER}" | grep -q '^description:' || fail "frontmatter missing description"

# <SUBAGENT-STOP> block at the top of the body (after the second `---`)
# Find the second `---` (end of frontmatter), then check the next 30 lines.
awk '/^---/ {n++; if (n==2) {flag=1; next}} flag && n==2 {print}' "${LOADER}" | head -30 \
  | grep -q '<SUBAGENT-STOP>' || fail "missing <SUBAGENT-STOP> block near top of body"

# Pointers to the two on-demand skills
grep -q 'karpathy-wiki-capture' "${LOADER}" || fail "no pointer to karpathy-wiki-capture"
grep -q 'karpathy-wiki-ingest' "${LOADER}" || fail "no pointer to karpathy-wiki-ingest"

# Iron laws and announce-line contract carried forward
grep -q 'NO WIKI WRITE IN THE FOREGROUND' "${LOADER}" || fail "missing iron law: foreground"
grep -q 'announce' "${LOADER}" || fail "missing announce-line contract"

# Trigger taxonomy
grep -q 'TRIGGER' "${LOADER}" || fail "missing trigger taxonomy"

# Body length sanity (not a 500-line monster — this is the loader)
lines=$(wc -l < "${LOADER}")
if [[ "${lines}" -gt 200 ]]; then
  fail "loader is ${lines} lines; should be ≤ 200 (this is the loader, not the full body)"
fi

echo "PASS: using-karpathy-wiki loader structure"
