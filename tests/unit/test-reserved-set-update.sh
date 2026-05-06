#!/bin/bash
# Verify wiki_yaml.py and wiki-relink.py reserved sets are updated:
# - inbox is reserved (in both)
# - Clippings is removed (from both)
# - .raw-staging is reserved (in wiki_yaml.py, OR auto-skipped in wiki-relink.py via dot prefix)
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
YAML_PY="${REPO_ROOT}/scripts/wiki_yaml.py"
RELINK_PY="${REPO_ROOT}/scripts/wiki-relink.py"

fail() { echo "FAIL: $*" >&2; exit 1; }

# wiki_yaml.py reserved set
grep -q 'RESERVED.*inbox' "${YAML_PY}" || fail "wiki_yaml.py RESERVED missing 'inbox'"
if grep -q 'RESERVED.*Clippings' "${YAML_PY}"; then
  fail "wiki_yaml.py RESERVED still contains 'Clippings'"
fi

# wiki-relink.py reserved tuple
grep -q '"inbox"' "${RELINK_PY}" || fail "wiki-relink.py reserved tuple missing 'inbox'"
if grep -q '"Clippings"' "${RELINK_PY}"; then
  fail "wiki-relink.py reserved tuple still contains 'Clippings'"
fi

# .raw-staging: covered by dot-prefix auto-skip in wiki-relink.py (line 80 already
# uses p.startswith(".") check). Verify that check is still in place.
grep -q 'startswith(".")' "${RELINK_PY}" \
  || fail "wiki-relink.py lost the dot-prefix auto-skip; .raw-staging may surface as a category"

echo "PASS: reserved-set update"
