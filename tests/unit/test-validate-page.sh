#!/bin/bash
# Tests for wiki-validate-page.py (base rules).
# Phase A rules: required fields, type whitelist, ISO-8601 dates, flat sources list,
# markdown link resolution (wiki-root mode), raw-source existence (wiki-root mode).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
TOOL="${REPO_ROOT}/scripts/wiki-validate-page.py"
FIX="${REPO_ROOT}/tests/fixtures/validate-page-cases"

pass_count=0
fail_count=0
say_pass() { echo "PASS: $1"; pass_count=$((pass_count+1)); }
say_fail() { echo "FAIL: $1"; fail_count=$((fail_count+1)); }

expect_exit() {
  # expect_exit <expected-rc> <label> -- <python3 ...>
  local expected="$1" label="$2"; shift 2
  shift  # consume --
  if "$@" >/dev/null 2>&1; then
    actual=0
  else
    actual=$?
  fi
  if [[ "${actual}" -eq "${expected}" ]]; then
    say_pass "${label}"
  else
    say_fail "${label} (expected rc=${expected}, got ${actual})"
  fi
}

# -- Single-file mode (no --wiki-root) --

expect_exit 0 "good-concept passes" -- python3 "${TOOL}" "${FIX}/good-concept.md"
expect_exit 1 "missing title fails" -- python3 "${TOOL}" "${FIX}/missing-title.md"
expect_exit 1 "bad type fails" -- python3 "${TOOL}" "${FIX}/bad-type.md"
expect_exit 1 "date-not-iso fails" -- python3 "${TOOL}" "${FIX}/date-not-iso.md"
expect_exit 1 "sources-nested fails" -- python3 "${TOOL}" "${FIX}/sources-nested.md"
expect_exit 1 "no-frontmatter fails" -- python3 "${TOOL}" "${FIX}/no-frontmatter.md"

# -- Wiki-root mode --
WIKI_FIX="${FIX}/wiki-root-mode"

expect_exit 0 "valid cross-link passes in wiki-root mode" -- \
  python3 "${TOOL}" --wiki-root "${WIKI_FIX}" "${WIKI_FIX}/concepts/valid-cross-link.md"

expect_exit 1 "broken link fails in wiki-root mode" -- \
  python3 "${TOOL}" --wiki-root "${WIKI_FIX}" "${WIKI_FIX}/concepts/broken-link.md"

expect_exit 1 "missing raw source fails in wiki-root mode" -- \
  python3 "${TOOL}" --wiki-root "${WIKI_FIX}" "${WIKI_FIX}/concepts/missing-source.md"

expect_exit 0 "valid concept in sources/ dir passes in wiki-root mode" -- \
  python3 "${TOOL}" --wiki-root "${WIKI_FIX}" "${WIKI_FIX}/sources/2026-04-24-x.md"

expect_exit 1 "concept with missing raw source fails in wiki-root mode" -- \
  python3 "${TOOL}" --wiki-root "${WIKI_FIX}" "${WIKI_FIX}/sources/orphan-source.md"

# -- stderr messages --
out="$(python3 "${TOOL}" "${FIX}/missing-title.md" 2>&1 >/dev/null || true)"
echo "${out}" | grep -q "missing required field: title" \
  && say_pass "stderr: missing title mentions 'missing required field: title'" \
  || say_fail "stderr: expected 'missing required field: title', got: ${out}"

out="$(python3 "${TOOL}" "${FIX}/bad-type.md" 2>&1 >/dev/null || true)"
echo "${out}" | grep -q "type must be one of" \
  && say_pass "stderr: bad type mentions 'type must be one of'" \
  || say_fail "stderr: expected 'type must be one of', got: ${out}"

# -- Phase B: quality block --
expect_exit 0 "good-with-quality passes" -- python3 "${TOOL}" "${FIX}/good-with-quality.md"
expect_exit 1 "quality-missing fails" -- python3 "${TOOL}" "${FIX}/quality-missing.md"
expect_exit 1 "quality-score-out-of-range fails" -- python3 "${TOOL}" "${FIX}/quality-score-out-of-range.md"
expect_exit 1 "quality-overall-mismatch fails" -- python3 "${TOOL}" "${FIX}/quality-overall-mismatch.md"
expect_exit 1 "quality-bad-rated-by fails" -- python3 "${TOOL}" "${FIX}/quality-bad-rated-by.md"

out="$(python3 "${TOOL}" "${FIX}/quality-missing.md" 2>&1 >/dev/null || true)"
echo "${out}" | grep -q "missing required field: quality" \
  && say_pass "stderr: quality-missing mentions missing quality" \
  || say_fail "stderr: expected 'missing required field: quality', got: ${out}"

out="$(python3 "${TOOL}" "${FIX}/quality-overall-mismatch.md" 2>&1 >/dev/null || true)"
echo "${out}" | grep -q "quality.overall" \
  && say_pass "stderr: overall-mismatch mentions quality.overall" \
  || say_fail "stderr: expected 'quality.overall' in stderr, got: ${out}"

# -- YAML parser: URL in sources list must NOT be mis-parsed as a nested mapping --
# Regression test for the "https://..." parser bug.
# The ":" inside "https://" must not cause the item to be treated as {key: value}.
expect_exit 0 "sources-with-url passes (URL is a string, not a nested mapping)" -- python3 "${TOOL}" "${FIX}/sources-with-url.md"

out="$(python3 "${TOOL}" "${FIX}/sources-with-url.md" 2>&1 >/dev/null || true)"
if echo "${out}" | grep -q "nested mapping"; then
  say_fail "URL source was mis-parsed as nested mapping; got: ${out}"
else
  say_pass "stderr: URL source did NOT trigger 'nested mapping' violation"
fi

echo
echo "passed: ${pass_count}"
echo "failed: ${fail_count}"
if [[ "${fail_count}" -gt 0 ]]; then exit 1; fi
echo "ALL PASS"
