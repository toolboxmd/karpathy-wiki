#!/bin/bash
# Verify karpathy-wiki-doctor skill structure and census contract.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SKILL="${REPO_ROOT}/skills/karpathy-wiki-doctor/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "${SKILL}" ]] || fail "skill file missing: ${SKILL}"

head -12 "${SKILL}" | grep -q '^name: karpathy-wiki-doctor' || fail "frontmatter missing name"
head -12 "${SKILL}" | grep -q '^description:' || fail "frontmatter missing description"
head -12 "${SKILL}" | grep -qi 'Detached doctor' || fail "description must say detached doctor"

grep -q 'wiki-complete-doctor.sh' "${SKILL}" || fail "skill missing complete-doctor helper"
grep -q '.wiki-pending/rewrite-jobs/' "${SKILL}" || fail "skill missing rewrite-jobs path"
grep -q 'wiki-schema-patch.py' "${SKILL}" || fail "skill must patch schema.md"
grep -q 'wiki-validate-page.py' "${SKILL}" || fail "skill must name page validation script"
grep -q 'wiki-lint-tags.py' "${SKILL}" || fail "skill must name tag lint script"
grep -q 'wiki-collapse-tag.py' "${SKILL}" || fail "skill must collapse tags via helper"
grep -q 'wiki-topical-keep-tags.py' "${SKILL}" \
  || fail "skill must run topical-keep helper"
grep -q 'Do not remove `sources:`' "${SKILL}" \
  || fail "skill must forbid removing sources"
grep -q 'same-idea' "${SKILL}" || fail "skill must use same-idea collapse"
grep -q 'not the same idea' "${SKILL}" \
  || fail "skill must skip false synonym pairs"
grep -q 'tag-drift' "${SKILL}" || fail "skill must consume tag-drift issues"
grep -q 'Do not write' "${SKILL}" || fail "skill must forbid synonym-pair bullets"
grep -q 'synonym pairs' "${SKILL}" || fail "skill must name synonym pairs as forbidden"
grep -qi 'frontmatter' "${SKILL}" || fail "skill missing frontmatter edits"
grep -qi 'related' "${SKILL}" || fail "skill missing related-list edits"

if grep -qi 'rewrite page bodies\|rewrite the body\|rewrite page synthesis' "${SKILL}"; then
  :
else
  grep -q 'Leave page synthesis unchanged' "${SKILL}" \
    || fail "skill must leave page synthesis unchanged"
fi
grep -q 'Do not execute the rewrite' "${SKILL}" \
  || fail "skill must record rewrite jobs without executing them"
grep -q 'wiki-archive-schema-proposals.py' "${SKILL}" \
  || fail "skill must archive leftover schema-proposals"
if grep -q 'Do not apply historical 200-line' "${SKILL}"; then
  fail "skill still teaches the old schema-proposal queue"
fi
if grep -qi 'file a schema-proposal' "${SKILL}"; then
  fail "skill must not instruct filing schema-proposal captures"
fi
if grep -q 'NO WIKI WRITE IN THE FOREGROUND' "${SKILL}"; then
  fail "iron law duplicated in doctor skill"
fi

echo "PASS: doctor skill structure"
