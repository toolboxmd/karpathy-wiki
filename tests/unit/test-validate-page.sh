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
echo "${out}" | grep -q "missing required field: quality" \
  && say_pass "stderr: bad type (single-file mode) mentions 'missing required field: quality'" \
  || say_fail "stderr: expected 'missing required field: quality', got: ${out}"

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

# v2.3: Phase A new checks
TMPV3="$(mktemp -d)"
trap "rm -rf '${TMPV3}'" EXIT

# Build a fixture wiki for v2.3 cases
mkdir -p "${TMPV3}/wiki/concepts" "${TMPV3}/wiki/projects/toolboxmd/karpathy-wiki" "${TMPV3}/wiki/journal" "${TMPV3}/wiki/raw"
touch "${TMPV3}/wiki/.wiki-config"
echo "stub" > "${TMPV3}/wiki/concepts/foo.md"

cat > "${TMPV3}/wiki/projects/toolboxmd/karpathy-wiki/v23.md" <<'V3EOF'
---
title: "v2.3"
type: projects
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 5
  overall: 5.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: ingester
---

See [foo](/concepts/foo.md).
V3EOF

expect_exit 0 "v2.3: leading-/ link resolves from wiki root" -- \
  python3 "${TOOL}" --wiki-root "${TMPV3}/wiki" "${TMPV3}/wiki/projects/toolboxmd/karpathy-wiki/v23.md"

# Phase A: type/path cross-check is WARNING only -- exit 0
cat > "${TMPV3}/wiki/concepts/mismatch.md" <<'V3EOF'
---
title: "Mismatch"
type: entities
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 5
  overall: 5.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: ingester
---
body
V3EOF
expect_exit 0 "v2.3 Phase A: type/path mismatch is WARNING only" -- \
  python3 "${TOOL}" --wiki-root "${TMPV3}/wiki" "${TMPV3}/wiki/concepts/mismatch.md"

out_warn="$(python3 "${TOOL}" --wiki-root "${TMPV3}/wiki" "${TMPV3}/wiki/concepts/mismatch.md" 2>&1 1>/dev/null || true)"
echo "${out_warn}" | grep -q "WARNING.*type.*entities" \
  && say_pass "v2.3 Phase A: cross-check WARNING line emitted to stderr" \
  || say_fail "v2.3 Phase A: expected WARNING line, got: ${out_warn}"

# Discovery returns dynamic types -- `journal/` IS a category
cat > "${TMPV3}/wiki/journal/2026-04-26.md" <<'V3EOF'
---
title: "Today"
type: journal
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 5
  overall: 5.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: ingester
---
body
V3EOF
expect_exit 0 "v2.3: dynamic category 'journal' from discovery is valid" -- \
  python3 "${TOOL}" --wiki-root "${TMPV3}/wiki" "${TMPV3}/wiki/journal/2026-04-26.md"

# Discovery failure: bogus wiki-root.
expect_exit 1 "v2.3: discovery failure exits non-zero" -- \
  python3 "${TOOL}" --wiki-root "/nonexistent/v23/path/zzz" "/nonexistent/v23/path/zzz/concepts/foo.md"

# Depth->=5 hard reject (always-on)
mkdir -p "${TMPV3}/wiki/concepts/a/b/c/d"
cat > "${TMPV3}/wiki/concepts/a/b/c/d/deep.md" <<'V3EOF'
---
title: "Deep"
type: concepts
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 5
  overall: 5.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: ingester
---
body
V3EOF
expect_exit 1 "v2.3: depth >=5 hard rejects" -- \
  python3 "${TOOL}" --wiki-root "${TMPV3}/wiki" "${TMPV3}/wiki/concepts/a/b/c/d/deep.md"

echo
echo "passed: ${pass_count}"
echo "failed: ${fail_count}"
if [[ "${fail_count}" -gt 0 ]]; then exit 1; fi
echo "ALL PASS"
