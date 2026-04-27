#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TOOL="${REPO_ROOT}/scripts/wiki-lint-tags.py"

make_page() {
  local path="$1" tags="$2"
  mkdir -p "$(dirname "${path}")"
  cat > "${path}" <<EOF
---
title: "$(basename "${path}" .md)"
type: concept
tags: ${tags}
sources:
  - raw/x.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
quality:
  accuracy: 3
  completeness: 3
  signal: 3
  interlinking: 3
  overall: 3.00
  rated_at: "2026-04-24T12:00:00Z"
  rated_by: ingester
---

body
EOF
}

setup() {
  TESTDIR="$(mktemp -d)"
  WIKI="${TESTDIR}/wiki"
  mkdir -p "${WIKI}/concepts"
}

teardown() { rm -rf "${TESTDIR}"; }

test_all_mode_flags_prefix_synonym() {
  setup
  make_page "${WIKI}/concepts/a.md" '[dentistry]'
  make_page "${WIKI}/concepts/b.md" '[dentistries]'
  out="$(python3 "${TOOL}" --wiki-root "${WIKI}" --all 2>&1 || true)"
  echo "${out}" | grep -q "dentistry" && echo "${out}" | grep -q "dentistries" \
    && echo "${out}" | grep -qi "synonym" \
    || { echo "FAIL: prefix synonym not flagged. out: ${out}"; teardown; exit 1; }
  echo "PASS: test_all_mode_flags_prefix_synonym"
  teardown
}

test_all_mode_flags_levenshtein_synonym() {
  setup
  make_page "${WIKI}/concepts/a.md" '[dental]'
  make_page "${WIKI}/concepts/b.md" '[dentl]'
  out="$(python3 "${TOOL}" --wiki-root "${WIKI}" --all 2>&1 || true)"
  echo "${out}" | grep -q "dental" && echo "${out}" | grep -q "dentl" \
    || { echo "FAIL: levenshtein synonym not flagged. out: ${out}"; teardown; exit 1; }
  echo "PASS: test_all_mode_flags_levenshtein_synonym"
  teardown
}

test_all_mode_respects_schema_synonym_list() {
  setup
  # Heuristics alone do NOT catch dentistry vs dental (prefix only 4,
  # distance > 2). Schema list should catch it.
  make_page "${WIKI}/concepts/a.md" '[dental]'
  make_page "${WIKI}/concepts/b.md" '[dentistry]'
  cat > "${WIKI}/schema.md" <<'EOF'
# Wiki Schema

## Tag Synonyms
- dental == dentistry
EOF
  out="$(python3 "${TOOL}" --wiki-root "${WIKI}" --all 2>&1 || true)"
  echo "${out}" | grep -qi "schema-listed synonym" \
    || { echo "FAIL: schema synonym not detected. out: ${out}"; teardown; exit 1; }
  echo "PASS: test_all_mode_respects_schema_synonym_list"
  teardown
}

test_single_page_mode_reports_new_tag() {
  setup
  make_page "${WIKI}/concepts/existing.md" '[a, b]'
  make_page "${WIKI}/concepts/new.md" '[c]'
  out="$(python3 "${TOOL}" --wiki-root "${WIKI}" "${WIKI}/concepts/new.md" 2>&1 || true)"
  echo "${out}" | grep -q "new tag: c" \
    || { echo "FAIL: new tag not surfaced. out: ${out}"; teardown; exit 1; }
  echo "PASS: test_single_page_mode_reports_new_tag"
  teardown
}

test_single_page_exit_is_zero_even_when_flagged() {
  setup
  make_page "${WIKI}/concepts/existing.md" '[a]'
  make_page "${WIKI}/concepts/new.md" '[b]'
  python3 "${TOOL}" --wiki-root "${WIKI}" "${WIKI}/concepts/new.md" 2>/dev/null
  echo "PASS: test_single_page_exit_is_zero_even_when_flagged"
  teardown
}

test_all_mode_flags_prefix_synonym
test_all_mode_flags_levenshtein_synonym
test_all_mode_respects_schema_synonym_list
test_single_page_mode_reports_new_tag
test_single_page_exit_is_zero_even_when_flagged
echo "ALL PASS"
