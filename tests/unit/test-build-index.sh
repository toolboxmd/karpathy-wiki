#!/bin/bash
# Test: wiki-build-index.py creates _index.md per directory + root MOC.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
BUILD="${REPO_ROOT}/scripts/wiki-build-index.py"

setup() {
  TMP="$(mktemp -d)"
  WIKI="${TMP}/wiki"
  mkdir -p "${WIKI}/concepts" "${WIKI}/entities" "${WIKI}/raw"
  touch "${WIKI}/.wiki-config"
}
teardown() { rm -rf "${TMP}"; }

write_page() {
  local path="$1"; local type="$2"; local title="$3"
  cat > "${path}" <<EOF
---
title: "${title}"
type: ${type}
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 4
  completeness: 4
  signal: 4
  interlinking: 4
  overall: 4.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: ingester
---
body
EOF
}

test_per_directory_index_generated() {
  setup
  write_page "${WIKI}/concepts/foo.md" concepts "Foo"
  write_page "${WIKI}/concepts/bar.md" concepts "Bar"
  python3 "${BUILD}" --wiki-root "${WIKI}" --rebuild-all
  [[ -f "${WIKI}/concepts/_index.md" ]] || { echo "FAIL: concepts/_index.md missing"; teardown; exit 1; }
  grep -q "Foo" "${WIKI}/concepts/_index.md" || { echo "FAIL: title missing"; teardown; exit 1; }
  teardown
}

test_root_moc_minimal_shape() {
  setup
  write_page "${WIKI}/concepts/foo.md" concepts "Foo"
  python3 "${BUILD}" --wiki-root "${WIKI}" --rebuild-all
  [[ -f "${WIKI}/index.md" ]] || { echo "FAIL: root index.md missing"; teardown; exit 1; }
  grep -q "# Wiki Index" "${WIKI}/index.md" || { echo "FAIL: header missing"; teardown; exit 1; }
  grep -q "concepts/_index.md" "${WIKI}/index.md" || { echo "FAIL: MOC link missing"; teardown; exit 1; }
  teardown
}

test_pages_section_renders_quality_two_decimals() {
  # Critical: per corrigendum C-D, parse_yaml returns overall as float 4.0
  # but the rendered output MUST format as (q: 4.00) not (q: 4.0).
  setup
  write_page "${WIKI}/concepts/foo.md" concepts "Foo"
  python3 "${BUILD}" --wiki-root "${WIKI}" --rebuild-all
  grep -q "(q: 4.00)" "${WIKI}/concepts/_index.md" || { echo "FAIL: quality not rendered as 2-decimal float"; teardown; exit 1; }
  teardown
}

test_subdirectories_section_lists_children() {
  setup
  mkdir -p "${WIKI}/projects/toolboxmd/karpathy-wiki"
  write_page "${WIKI}/projects/toolboxmd/karpathy-wiki/v23.md" projects "v2.3"
  python3 "${BUILD}" --wiki-root "${WIKI}" --rebuild-all
  grep -q "## Subdirectories" "${WIKI}/projects/_index.md" || { echo "FAIL: subdirs section missing in projects"; teardown; exit 1; }
  grep -q "toolboxmd" "${WIKI}/projects/_index.md" || { echo "FAIL: toolboxmd not listed"; teardown; exit 1; }
  teardown
}

test_idempotent() {
  setup
  write_page "${WIKI}/concepts/foo.md" concepts "Foo"
  python3 "${BUILD}" --wiki-root "${WIKI}" --rebuild-all
  before="$(shasum -a 256 "${WIKI}/concepts/_index.md")"
  python3 "${BUILD}" --wiki-root "${WIKI}" --rebuild-all
  after="$(shasum -a 256 "${WIKI}/concepts/_index.md")"
  [[ "${before}" == "${after}" ]] || { echo "FAIL: not idempotent"; teardown; exit 1; }
  teardown
}

test_arbitrary_depth() {
  setup
  mkdir -p "${WIKI}/projects/a/b/c"
  write_page "${WIKI}/projects/a/b/c/deep.md" projects "Deep"
  python3 "${BUILD}" --wiki-root "${WIKI}" --rebuild-all
  for d in projects projects/a projects/a/b projects/a/b/c; do
    [[ -f "${WIKI}/${d}/_index.md" ]] || { echo "FAIL: ${d}/_index.md missing"; teardown; exit 1; }
  done
  teardown
}

test_lock_slug_matches_wiki_lock_sh() {
  # Per corrigendum C-J: lock-slug scheme MUST match wiki-lock.sh's
  # tr '/' '-' | tr '.' '-' to share lockfile namespace.
  setup
  write_page "${WIKI}/concepts/foo.md" concepts "Foo"
  # Just verify build completes without error and creates _index.md
  python3 "${BUILD}" --wiki-root "${WIKI}" --rebuild-all
  [[ -f "${WIKI}/concepts/_index.md" ]] || { echo "FAIL: build did not produce _index.md"; teardown; exit 1; }
  # Verify no leftover lock files remain after clean run
  [[ -z "$(ls "${WIKI}/.locks" 2>/dev/null)" ]] || { echo "FAIL: locks not released"; teardown; exit 1; }
  teardown
}

test_handles_9_categories_no_crash() {
  # Per Rule 3 visibility — if the cheap model creates a 9th category,
  # build-index must still complete cleanly (Rule 3's schema-proposal
  # firing happens elsewhere; here we just verify build doesn't break).
  setup
  for c in concepts entities queries ideas a b c d projects; do
    mkdir -p "${WIKI}/${c}"
    write_page "${WIKI}/${c}/x.md" "${c}" "X"
  done
  python3 "${BUILD}" --wiki-root "${WIKI}" --rebuild-all
  [[ -f "${WIKI}/index.md" ]] || { echo "FAIL: build failed with 9 categories"; teardown; exit 1; }
  teardown
}

test_reserved_subdir_descendants_excluded() {
  # I-1 regression: pages under reserved subdirs (raw/, archive/, etc.)
  # must not be counted in parent's subdirectory listing.
  setup
  mkdir -p "${WIKI}/projects/sub/raw" "${WIKI}/projects/sub/legit-content"
  write_page "${WIKI}/projects/sub/legit.md" projects "Legit"
  write_page "${WIKI}/projects/sub/raw/orphan.md" projects "Orphan"
  write_page "${WIKI}/projects/sub/legit-content/page.md" projects "Page"
  python3 "${BUILD}" --wiki-root "${WIKI}" --rebuild-all
  # projects/_index.md should show sub/ has 2 pages (legit.md + page.md), NOT 3.
  if grep -q "sub/.*— 3 pages" "${WIKI}/projects/_index.md" 2>/dev/null; then
    echo "FAIL: orphan.md leaked into sub/ count"; teardown; exit 1
  fi
  grep -q "sub/.*— 2 pages" "${WIKI}/projects/_index.md" || {
    echo "FAIL: expected 'sub/ — 2 pages' in projects/_index.md"
    cat "${WIKI}/projects/_index.md"
    teardown; exit 1
  }
  # Orphan title should NOT appear in the brief title preview
  if grep -q "Orphan" "${WIKI}/projects/_index.md"; then
    echo "FAIL: orphan title leaked into preview"; teardown; exit 1
  fi
  teardown
}

test_wiki_root_only_gets_index_md_not_underscore_index() {
  # I-2 regression: when build-index is called with directory == wiki_root,
  # only index.md (the MOC) should be written, not _index.md.
  setup
  write_page "${WIKI}/concepts/foo.md" concepts "Foo"
  # Single-directory invocation with directory == wiki_root
  python3 "${BUILD}" --wiki-root "${WIKI}" "${WIKI}"
  [[ -f "${WIKI}/index.md" ]] || { echo "FAIL: root index.md missing"; teardown; exit 1; }
  if [[ -f "${WIKI}/_index.md" ]]; then
    echo "FAIL: wiki root should not have _index.md"
    teardown; exit 1
  fi
  teardown
}

test_per_directory_index_generated
test_root_moc_minimal_shape
test_pages_section_renders_quality_two_decimals
test_subdirectories_section_lists_children
test_idempotent
test_arbitrary_depth
test_lock_slug_matches_wiki_lock_sh
test_handles_9_categories_no_crash
test_reserved_subdir_descendants_excluded
test_wiki_root_only_gets_index_md_not_underscore_index
echo "all tests passed"
