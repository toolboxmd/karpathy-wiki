#!/bin/bash
# RED: `wiki status` total-pages count must filter to the actual wiki content
# set, not every .md under the wiki root.
#
# Bug (0.2.8 #6): scripts/wiki-status.sh:23 globs every .md under <wiki>/
# (excluding .wiki-pending/). That counts root index.md, per-category
# _index.md files, and any .md under raw/ or other reserved dirs. The
# user-facing "total pages: N" line is silently inflated.
#
# Test stands up a temp wiki with:
#   - 3 real concept pages under concepts/
#   - 1 root index.md (auto-created by wiki-init)
#   - 2 _index.md (one per category — concepts and entities)
#   - 1 file in raw/
#   - 1 file in .wiki-pending/archive/
# Asserts `wiki status` reports "total pages: 3".
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"
STATUS="${REPO_ROOT}/scripts/wiki-status.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -x "${STATUS}" ]] || fail "wiki-status.sh missing"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

WIKI="${TMP}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null

# Real concept pages
mkdir -p "${WIKI}/concepts" "${WIKI}/entities"
for n in 1 2 3; do
  cat > "${WIKI}/concepts/p${n}.md" <<EOF
---
type: [concept]
title: "p${n}"
---
body p${n}.
EOF
done

# Per-category _index.md
for cat in concepts entities; do
  cat > "${WIKI}/${cat}/_index.md" <<EOF
---
type: [index]
---
index for ${cat}.
EOF
done

# raw/ + archive
mkdir -p "${WIKI}/.wiki-pending/archive"
echo "raw" > "${WIKI}/raw/something.md"
echo "old" > "${WIKI}/.wiki-pending/archive/old-capture.md"

# Run status, grab the total pages line.
out=$(bash "${STATUS}" "${WIKI}" 2>/dev/null)

total_line=$(echo "${out}" | grep -i '^total pages:' | head -1)
[[ -n "${total_line}" ]] || fail "no 'total pages:' line in status output:\n${out}"

count=$(echo "${total_line}" | awk '{print $NF}')

if [[ "${count}" != "3" ]]; then
  echo "Status output:"
  echo "${out}"
  fail "expected 'total pages: 3', got '${total_line}'"
fi

echo "PASS: wiki status counts only real content pages (3, not inflated)"
