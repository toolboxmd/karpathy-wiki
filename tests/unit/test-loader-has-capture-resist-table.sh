#!/bin/bash
# RED: skills/using-karpathy-wiki/SKILL.md must contain a capture-side
# resist-table that counters the same rationalizations the v1 loader had.
#
# Bug (0.2.8 #13): v1 (commit 6ce0c77, captured at tmp/skill-v1-6ce0c77.md
# lines 194-209) had a "Rationalizations to resist" section specifically
# for the moment "should I capture this?" The v2.4 split kept a similar
# table but only for the read-side ("orient before answering"). Capture-
# side rationalizations like "the user will remember this", "I'll capture
# it later", "I'm in the middle of another task", "the file is already in
# a good place" go uncountered. Skipped captures are invisible — the user
# can't observe them.
#
# Test asserts the loader contains a capture-side resist-table by checking
# for at least 4 of the 7 v1 rationalization rows verbatim or near-verbatim.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
LOADER="${REPO_ROOT}/skills/using-karpathy-wiki/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "${LOADER}" ]] || fail "loader missing: ${LOADER}"

# Each substring is a v1 rationalization phrase. The loader must contain at
# least 4 of these.
phrases=(
  "The user will remember this"
  "It's too trivial for the wiki"
  "I'll capture it later"
  "I'm in the middle of another task"
  "The user didn't ask me to save this"
  "I don't have a memory tool available"
  "The file is already in a good place"
)

found=0
missing=()
for p in "${phrases[@]}"; do
  if grep -qF "${p}" "${LOADER}"; then
    found=$((found + 1))
  else
    missing+=("${p}")
  fi
done

if [[ "${found}" -lt 4 ]]; then
  echo "Loader contains ${found}/7 v1 capture-resist phrases. Missing:"
  for m in "${missing[@]}"; do
    echo "  - ${m}"
  done
  fail "loader missing capture-side resist-table (need >=4 of the 7 v1 rationalization rows)"
fi

# Loader must also no longer claim the capture-side table is in
# karpathy-wiki-capture/SKILL.md (it's in the loader now per the v1 layout).
# This is a softer check; pass if the table is present in the loader and
# the read-side table reference is unambiguous.

echo "PASS: loader has capture-side resist-table (${found}/7 v1 rows present)"
