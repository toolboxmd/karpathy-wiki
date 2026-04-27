#!/bin/bash
# Test: validator rejects deleted-category and unknown type values (post-v2.3 flip).
#
# Renamed from test-validate-no-source-type.sh per corrigendum C-K. v2.3 dropped
# the static VALID_TYPES whitelist; valid types are discovered from the directory
# tree. So a `type: source` page in concepts/ now hard-fails on the type/path
# cross-check (type 'source' != path.parts[0] 'concepts'). Same defended invariant,
# new mechanism. Plus a new `type: nonsense` case proving the type-membership
# check rejects any non-discovered type.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VALIDATOR="${REPO_ROOT}/scripts/wiki-validate-page.py"

pass_count=0
fail_count=0
say_pass() { echo "PASS: $1"; pass_count=$((pass_count+1)); }
say_fail() { echo "FAIL: $1"; fail_count=$((fail_count+1)); }

tmp="$(mktemp -d)"
trap "rm -rf '${tmp}'" EXIT

# Build a wiki where 'sources' is NOT a directory (so it's not in discovery's
# categories list). A page with type: source in concepts/ then fails both:
#   1. type-membership: 'source' not in {'concepts'}
#   2. type/path cross-check: 'source' != 'concepts'
mkdir -p "${tmp}/wiki/concepts" "${tmp}/wiki/raw"
touch "${tmp}/wiki/.wiki-config"

# Test 1: type: source (deleted category) in concepts/ — must be rejected
cat > "${tmp}/wiki/concepts/foo.md" <<'EOF'
---
title: "Foo (typed source)"
type: source
tags: [test]
sources:
  - raw/foo.md
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
echo "raw" > "${tmp}/wiki/raw/foo.md"

if python3 "${VALIDATOR}" --wiki-root "${tmp}/wiki" "${tmp}/wiki/concepts/foo.md" 2>/dev/null; then
  say_fail "validator should reject type: source in concepts/ (deleted-category defense)"
else
  say_pass "validator rejects type: source in concepts/ (deleted-category defense)"
fi

# Test 2: type: nonsense — non-discovered type, must be rejected
cat > "${tmp}/wiki/concepts/bar.md" <<'EOF'
---
title: "Bar (unknown type)"
type: nonsense
tags: [test]
sources: []
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

if python3 "${VALIDATOR}" --wiki-root "${tmp}/wiki" "${tmp}/wiki/concepts/bar.md" 2>/dev/null; then
  say_fail "validator should reject type: nonsense (any non-discovered type)"
else
  say_pass "validator rejects type: nonsense (membership-check defense)"
fi

echo
echo "passed: ${pass_count}"
echo "failed: ${fail_count}"
[[ "${fail_count}" -eq 0 ]] || exit 1
echo "ALL PASS"
