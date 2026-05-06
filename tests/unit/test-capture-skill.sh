#!/bin/bash
# Verify karpathy-wiki-capture skill structure.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SKILL="${REPO_ROOT}/skills/karpathy-wiki-capture/SKILL.md"
SCHEMA_REF="${REPO_ROOT}/skills/karpathy-wiki-capture/references/capture-schema.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "${SKILL}" ]] || fail "skill file missing: ${SKILL}"
[[ -f "${SCHEMA_REF}" ]] || fail "reference file missing: ${SCHEMA_REF}"

# Frontmatter
head -10 "${SKILL}" | grep -q '^name: karpathy-wiki-capture' || fail "frontmatter missing name"
head -10 "${SKILL}" | grep -q '^description:' || fail "frontmatter missing description"

# Required sections
grep -q '^## Trigger' "${SKILL}" || fail "missing 'Trigger' section"
grep -q '^## Capture file format' "${SKILL}" || fail "missing 'Capture file format' section"
grep -q '^## Body sufficiency' "${SKILL}" || fail "missing 'Body sufficiency' section"
grep -q 'bin/wiki capture' "${SKILL}" || fail "no reference to bin/wiki capture (canonical entry point)"

# Subagent-report workflow guidance
grep -qi 'subagent report' "${SKILL}" || fail "missing subagent-report workflow"
grep -q 'wiki ingest-now' "${SKILL}" || fail "no reference to wiki ingest-now"

# Pointer to schema reference
grep -q 'capture-schema.md' "${SKILL}" || fail "no pointer to references/capture-schema.md"

# capture-schema.md content
grep -q 'capture_kind' "${SCHEMA_REF}" || fail "schema ref missing capture_kind enum"
grep -q 'raw-direct' "${SCHEMA_REF}" || fail "schema ref missing raw-direct kind"
grep -q 'chat-attached' "${SCHEMA_REF}" || fail "schema ref missing chat-attached kind"
grep -q 'chat-only' "${SCHEMA_REF}" || fail "schema ref missing chat-only kind"

# Iron laws not duplicated here (single source of truth is the loader)
if grep -q 'NO WIKI WRITE IN THE FOREGROUND' "${SKILL}"; then
  fail "iron law duplicated in capture skill (single source: using-karpathy-wiki/SKILL.md)"
fi

echo "PASS: karpathy-wiki-capture skill structure"
