#!/bin/bash
# Test: wiki-discover.py walks wiki root, emits expected JSON.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DISCOVER="${REPO_ROOT}/scripts/wiki-discover.py"

setup() {
  TMP="$(mktemp -d)"
  WIKI="${TMP}/wiki"
  mkdir -p "${WIKI}/concepts" "${WIKI}/entities" "${WIKI}/queries" "${WIKI}/ideas" \
           "${WIKI}/raw" "${WIKI}/.wiki-pending" "${WIKI}/.locks" "${WIKI}/.obsidian" \
           "${WIKI}/inbox"
  touch "${WIKI}/.wiki-config"
}
teardown() { rm -rf "${TMP}"; }

test_categories_listed() {
  setup
  out="$(python3 "${DISCOVER}" --wiki-root "${WIKI}")"
  echo "${out}" | python3 -c "import json,sys; d=json.load(sys.stdin); assert sorted(d['categories'])==['concepts','entities','ideas','queries'], d"
  teardown
}

test_reserved_skipped() {
  setup
  out="$(python3 "${DISCOVER}" --wiki-root "${WIKI}")"
  echo "${out}" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'raw' not in d['categories'] and 'inbox' not in d['categories'] and '.obsidian' not in d['categories'], d"
  teardown
}

test_dotted_skipped() {
  setup
  mkdir -p "${WIKI}/.git"
  out="$(python3 "${DISCOVER}" --wiki-root "${WIKI}")"
  echo "${out}" | python3 -c "import json,sys; d=json.load(sys.stdin); assert '.git' not in d['categories']"
  teardown
}

test_depth_correct_flat() {
  setup
  echo "stub" > "${WIKI}/concepts/foo.md"
  out="$(python3 "${DISCOVER}" --wiki-root "${WIKI}")"
  echo "${out}" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['depths']['concepts']==1, d"
  teardown
}

test_depth_correct_nested() {
  setup
  mkdir -p "${WIKI}/projects/a/b/c"
  echo "stub" > "${WIKI}/projects/a/b/c/foo.md"
  out="$(python3 "${DISCOVER}" --wiki-root "${WIKI}")"
  echo "${out}" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['depths']['projects']==4, d"
  teardown
}

test_counts_correct() {
  setup
  echo "stub" > "${WIKI}/concepts/foo.md"
  echo "stub" > "${WIKI}/concepts/bar.md"
  echo "stub" > "${WIKI}/entities/baz.md"
  out="$(python3 "${DISCOVER}" --wiki-root "${WIKI}")"
  echo "${out}" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['counts']['concepts']==2 and d['counts']['entities']==1, d"
  teardown
}

test_json_shape_has_required_keys() {
  setup
  out="$(python3 "${DISCOVER}" --wiki-root "${WIKI}")"
  echo "${out}" | python3 -c "import json,sys; d=json.load(sys.stdin); [d[k] for k in ('categories','reserved','depths','counts')]"
  teardown
}

test_reserved_set_exposed() {
  setup
  out="$(python3 "${DISCOVER}" --wiki-root "${WIKI}")"
  echo "${out}" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'raw' in d['reserved'] and 'inbox' in d['reserved']"
  teardown
}

test_missing_wiki_root_exits_nonzero() {
  if python3 "${DISCOVER}" --wiki-root /no/such/path 2>/dev/null; then
    echo "FAIL: discover should exit non-zero on missing wiki-root"
    exit 1
  fi
}

test_top_level_md_files_ignored() {
  setup
  echo "stub" > "${WIKI}/README.md"
  out="$(python3 "${DISCOVER}" --wiki-root "${WIKI}")"
  echo "${out}" | python3 -c "
import json, sys
d = json.load(sys.stdin)
# README.md is a file, not a directory — must not appear as a category
assert 'README.md' not in d['categories'], d
assert 'README' not in d['categories'], d
" || { echo "FAIL: top-level .md treated as category"; teardown; exit 1; }
  teardown
}

test_categories_listed
test_reserved_skipped
test_dotted_skipped
test_depth_correct_flat
test_depth_correct_nested
test_counts_correct
test_json_shape_has_required_keys
test_reserved_set_exposed
test_missing_wiki_root_exits_nonzero
test_top_level_md_files_ignored
echo "all tests passed"
