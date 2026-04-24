#!/bin/bash
# Test: validator rejects type: source after v2.2 cut.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VALIDATOR="${REPO_ROOT}/scripts/wiki-validate-page.py"

tmp="$(mktemp -d)"
trap "rm -rf '${tmp}'" EXIT

mkdir -p "${tmp}/wiki/sources" "${tmp}/wiki/raw"
touch "${tmp}/wiki/.wiki-config"
cat > "${tmp}/wiki/sources/foo.md" <<'EOF'
---
title: "Source: Foo"
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

# Run validator; expect type-not-allowed violation.
output="$(python3 "${VALIDATOR}" --wiki-root "${tmp}/wiki" "${tmp}/wiki/sources/foo.md" 2>&1 || true)"
if echo "${output}" | grep -q "type must be one of"; then
  echo "PASS: validator rejects type: source"
else
  echo "FAIL: expected type-rejection, got: ${output}"
  exit 1
fi

echo "ALL PASS"
