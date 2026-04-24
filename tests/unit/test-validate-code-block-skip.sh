#!/bin/bash
# Test: validator skips markdown links inside fenced and inline code spans.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
VALIDATOR="${REPO_ROOT}/scripts/wiki-validate-page.py"

tmp="$(mktemp -d)"
trap "rm -rf '${tmp}'" EXIT

mkdir -p "${tmp}/wiki/concepts" "${tmp}/wiki/raw"
touch "${tmp}/wiki/.wiki-config"
cat > "${tmp}/wiki/concepts/foo.md" <<'EOF'
---
title: "Foo"
type: concept
tags: [test]
sources:
  - raw/foo.md
created: "2026-04-24T12:00:00Z"
updated: "2026-04-24T12:00:00Z"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 5
  overall: 5.00
  rated_at: "2026-04-24T12:00:00Z"
  rated_by: ingester
---

This page demonstrates portable links: `[Title](path.md)` is the format.

Inside an inline span: `[Foo](nope.md)` should not trigger the validator.

```
[Bar](also-nope.md)
```

But this real link MUST trigger: [Real](nonexistent.md).
EOF
echo "raw" > "${tmp}/wiki/raw/foo.md"

output="$(python3 "${VALIDATOR}" --wiki-root "${tmp}/wiki" "${tmp}/wiki/concepts/foo.md" 2>&1 || true)"

# Should report exactly one broken link: nonexistent.md
nonexistent_count="$(echo "${output}" | grep -c 'nonexistent.md' || true)"
path_count="$(echo "${output}" | grep -c 'path.md' || true)"
also_nope_count="$(echo "${output}" | grep -c 'also-nope.md' || true)"

if [[ "${nonexistent_count}" -ne 1 ]]; then
  echo "FAIL: expected 1 violation for nonexistent.md, got ${nonexistent_count}. Output: ${output}"
  exit 1
fi
if [[ "${path_count}" -ne 0 ]]; then
  echo "FAIL: validator flagged path.md inside inline code span (${path_count} times). Output: ${output}"
  exit 1
fi
if [[ "${also_nope_count}" -ne 0 ]]; then
  echo "FAIL: validator flagged also-nope.md inside fenced code block (${also_nope_count} times). Output: ${output}"
  exit 1
fi

echo "PASS: validator skips fenced + inline code link examples"
echo "ALL PASS"
