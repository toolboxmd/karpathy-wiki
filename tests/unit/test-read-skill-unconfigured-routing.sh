#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
READ_SKILL="${REPO_ROOT}/skills/karpathy-wiki-read/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

grep -Fq '### Step A.0: Unconfigured workspace' "${READ_SKILL}" \
  || fail "read skill has no explicit unconfigured-workspace branch"
grep -Fq 'continue directly at Step F' "${READ_SKILL}" \
  || fail "unconfigured workspace does not route to the cold-result path"
grep -Fq 'The capture skill is the sole owner of orphan preservation' "${READ_SKILL}" \
  || fail "read skill bypasses capture-owned orphan handling"
grep -Fq '`main`, or `both` question. Do not add a second setup prompt here.' "${READ_SKILL}" \
  || fail "read skill duplicates or bypasses capture-owned routing UX"
grep -Fq 'Malformed or incomplete configured routing is an error' "${READ_SKILL}" \
  || fail "read skill conflates broken routing with a fresh workspace"

echo "PASS: read skill delegates unconfigured cold results to capture-owned routing"
