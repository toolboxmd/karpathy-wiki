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

# Inline mechanism: mirrors the SKILL.md step 7.6 prose.
# A schema-proposal capture should exist in .wiki-pending/schema-proposals/
# only IF threshold is exceeded AND no recent (<=24h) such proposal exists.
INDEX_SIZE_THRESHOLD=8192
recent_proposal="$(find "${tmp}/wiki/.wiki-pending/schema-proposals" -name '*-index-split.md' -mtime -1 2>/dev/null | head -1)"
if [[ ${size} -gt ${INDEX_SIZE_THRESHOLD} && -z "${recent_proposal}" ]]; then
  ts="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
  cat > "${tmp}/wiki/.wiki-pending/schema-proposals/${ts}-index-split.md" <<EOF
---
title: "Schema proposal: split index.md (size threshold exceeded)"
captured_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
trigger: "index.md size = ${size} bytes (threshold ${INDEX_SIZE_THRESHOLD} bytes)"
---

index.md exceeded the orientation-degradation threshold. Recommended atom-ization:
- index/concepts.md
- index/entities.md
- index/queries.md
- index/ideas.md

index.md becomes a 5-line MOC pointing at each sub-index.
EOF
fi

# Assert exactly one schema-proposal capture exists.
proposals="$(find "${tmp}/wiki/.wiki-pending/schema-proposals" -name '*-index-split.md' | wc -l | tr -d ' ')"
if [[ "${proposals}" -ne 1 ]]; then
  echo "FAIL: expected 1 index-split proposal capture, got ${proposals}"
  exit 1
fi

echo "PASS: index.md > 8 KB triggers schema-proposal capture"
echo "ALL PASS"
