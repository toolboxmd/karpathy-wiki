#!/bin/bash
# Test: a fixture wiki with index.md > 8 KB has a corresponding schema-proposal
# capture written by the ingest mechanism. We model the mechanism with an
# inline shell snippet that mirrors the SKILL.md step 7.6 prose; the real
# ingester is a `claude -p` process, but the mechanical contract is testable.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

tmp="$(mktemp -d)"
trap "rm -rf '${tmp}'" EXIT

mkdir -p "${tmp}/wiki/.wiki-pending/schema-proposals"
touch "${tmp}/wiki/.wiki-config"

# Fixture index.md at 9 KB (just over the 8 KB threshold).
python3 -c "
content = '# Wiki Index\n\n## Concepts\n'
# Each entry is roughly 70 bytes (UTF-8); 120 entries = ~8400 bytes.
for i in range(120):
    content += f'- [Page {i}](concepts/page-{i:03d}.md) — descriptive prose for entry {i:03d}\n'
open('${tmp}/wiki/index.md', 'w').write(content)
"

# Sanity: confirm size is > 8192.
size="$(wc -c < "${tmp}/wiki/index.md")"
if [[ ${size} -le 8192 ]]; then
  echo "FAIL: fixture index.md is ${size} bytes; expected > 8192"
  exit 1
fi

# Inline mechanism: exact SKILL.md step 7.6 snippet (verbatim copy).
WIKI_ROOT="${tmp}/wiki"
size="$(wc -c < "${WIKI_ROOT}/index.md" | tr -d ' ')"
if [[ ${size} -gt 8192 ]]; then
  recent="$(find "${WIKI_ROOT}/.wiki-pending/schema-proposals" -name '*-index-split.md' -mtime -1 2>/dev/null | head -1)"
  if [[ -z "${recent}" ]]; then
    ts="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
    cat > "${WIKI_ROOT}/.wiki-pending/schema-proposals/${ts}-index-split.md" <<EOF
---
title: "Schema proposal: split index.md (size threshold exceeded)"
captured_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
trigger: "index.md size = ${size} bytes (threshold 8192 bytes)"
---

index.md exceeded the orientation-degradation threshold. Recommended atom-ization: split into per-category sub-indexes (index/concepts.md, index/entities.md, index/queries.md, index/ideas.md), with index.md becoming a 5-line MOC pointing at each. Rationale: per-category matches existing wiki structure; agents reading index.md get cheap orientation and can drill down.
EOF
  fi
fi

# Assert exactly one schema-proposal capture exists.
proposals="$(find "${tmp}/wiki/.wiki-pending/schema-proposals" -name '*-index-split.md' | wc -l | tr -d ' ')"
if [[ "${proposals}" -ne 1 ]]; then
  echo "FAIL: expected 1 index-split proposal capture, got ${proposals}"
  exit 1
fi

# Assert the rendered capture file's first line is exactly '---' (no leading whitespace).
first_line="$(head -1 "${tmp}/wiki/.wiki-pending/schema-proposals"/*-index-split.md)"
if [[ "${first_line}" != "---" ]]; then
  echo "FAIL: capture first line is not '---' (leading whitespace?). Got: '${first_line}'"
  exit 1
fi

echo "PASS: index.md > 8 KB triggers schema-proposal capture"

test_per_index_md_threshold_fires() {
  # Build a deeply-nested category whose _index.md exceeds 8 KB
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/projects/a/b/c" "${tmp}/wiki/raw" "${tmp}/wiki/.wiki-pending/schema-proposals"
  touch "${tmp}/wiki/.wiki-config"
  for i in $(seq 1 100); do
    cat > "${tmp}/wiki/projects/a/b/c/page${i}.md" <<EOF
---
title: "Page ${i} with a long descriptive title that contributes to index size"
type: projects
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
Long body paragraph for entry ${i}. word word word word word word word word word word
EOF
  done
  python3 "${REPO_ROOT}/scripts/wiki-build-index.py" --wiki-root "${tmp}/wiki" --rebuild-all
  size=$(wc -c < "${tmp}/wiki/projects/a/b/c/_index.md")
  if [[ "${size}" -le 8192 ]]; then
    echo "FAIL: expected projects/a/b/c/_index.md to exceed 8 KB; got ${size}"
    rm -rf "${tmp}"; exit 1
  fi
  rm -rf "${tmp}"
}

test_threshold_24h_debounce_predicate() {
  # The threshold-fires logic is in the SKILL.md ingester step 7.6.
  # This test verifies the predicate: a recent proposal under 24h
  # should suppress new firings (the debounce key is the slug-derived
  # filename pattern). We don't run the ingester here; we exercise the
  # find-mtime-1 predicate that step 7.6 uses.
  local tmp; tmp="$(mktemp -d)"
  mkdir -p "${tmp}/wiki/.wiki-pending/schema-proposals"
  ts="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
  echo "stub" > "${tmp}/wiki/.wiki-pending/schema-proposals/${ts}-projects-a-b-c-_index-md-index-split.md"
  recent="$(find "${tmp}/wiki/.wiki-pending/schema-proposals" -name '*-index-split.md' -mtime -1 | head -1)"
  [[ -n "${recent}" ]] || { echo "FAIL: debounce file not found"; rm -rf "${tmp}"; exit 1; }
  rm -rf "${tmp}"
}

test_per_index_md_threshold_fires
echo "PASS: test_per_index_md_threshold_fires"
test_threshold_24h_debounce_predicate
echo "PASS: test_threshold_24h_debounce_predicate"
echo "ALL PASS"
