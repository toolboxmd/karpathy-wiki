#!/bin/bash
# Test: wiki_capture_archive strips .processing suffix when archiving.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

tmp="$(mktemp -d)"
trap "rm -rf '${tmp}'" EXIT

mkdir -p "${tmp}/wiki/.wiki-pending"
touch "${tmp}/wiki/.wiki-config"

# Create a fake .processing capture.
cat > "${tmp}/wiki/.wiki-pending/2026-04-24T12-00-00Z-foo.md.processing" <<'EOF'
---
title: "test"
---
body
EOF

# Source the lib + capture helpers.
source "${REPO_ROOT}/scripts/wiki-lib.sh"
source "${REPO_ROOT}/scripts/wiki-capture.sh"

# Set ingest log var so log_info doesn't try to walk the cwd.
WIKI_INGEST_LOG="${tmp}/wiki/.ingest.log"
export WIKI_INGEST_LOG

wiki_capture_archive "${tmp}/wiki" "${tmp}/wiki/.wiki-pending/2026-04-24T12-00-00Z-foo.md.processing"

# Assert: archive/YYYY-MM/2026-04-24T12-00-00Z-foo.md exists (no .processing).
date_dir="$(date +%Y-%m)"
expected="${tmp}/wiki/.wiki-pending/archive/${date_dir}/2026-04-24T12-00-00Z-foo.md"
if [[ ! -f "${expected}" ]]; then
  echo "FAIL: expected archived file at ${expected}"
  echo "Found: $(find "${tmp}/wiki/.wiki-pending/archive" -type f)"
  exit 1
fi

# Assert: no .processing file remains anywhere under .wiki-pending.
strays="$(find "${tmp}/wiki/.wiki-pending" -name '*.processing' | wc -l | tr -d ' ')"
if [[ "${strays}" -ne 0 ]]; then
  echo "FAIL: ${strays} .processing files remain after archive"
  exit 1
fi

echo "PASS: wiki_capture_archive strips .processing suffix"
echo "ALL PASS"
