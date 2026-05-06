#!/bin/bash
# Verify karpathy-wiki-ingest skill structure.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SKILL="${REPO_ROOT}/skills/karpathy-wiki-ingest/SKILL.md"
PAGE_REF="${REPO_ROOT}/skills/karpathy-wiki-ingest/references/page-conventions.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "${SKILL}" ]] || fail "skill file missing: ${SKILL}"
[[ -f "${PAGE_REF}" ]] || fail "page-conventions file missing: ${PAGE_REF}"

head -10 "${SKILL}" | grep -q '^name: karpathy-wiki-ingest' || fail "frontmatter missing name"
head -10 "${SKILL}" | grep -q '^description:' || fail "frontmatter missing description"

# Required sections — orientation, page format, manifest, commit
grep -q -i '^## Orientation' "${SKILL}" || fail "missing Orientation section"
grep -q -i 'manifest' "${SKILL}" || fail "missing manifest section"
grep -q -i 'commit' "${SKILL}" || fail "missing commit section"

# Role guardrail (project / main lens)
grep -q -i 'role' "${SKILL}" || fail "missing role guardrail"
grep -qi 'project\|main' "${SKILL}" || fail "missing project/main lens guidance"

# Pointer to capture-schema (shared contract)
grep -q 'capture-schema.md' "${SKILL}" || fail "no pointer to capture-schema.md"

# page-conventions.md content
grep -q -i 'cross-link' "${PAGE_REF}" || fail "page-conventions missing cross-link convention"
grep -q -i 'frontmatter' "${PAGE_REF}" || fail "page-conventions missing frontmatter section"

# No iron-law duplication
if grep -q 'NO WIKI WRITE IN THE FOREGROUND' "${SKILL}"; then
  fail "iron law duplicated in ingest skill (single source: using-karpathy-wiki/SKILL.md)"
fi

# No announce-line duplication
if grep -q -i 'announce' "${SKILL}"; then
  fail "announce-line contract duplicated in ingest skill (single source: using-karpathy-wiki/SKILL.md)"
fi

echo "PASS: karpathy-wiki-ingest skill structure"
