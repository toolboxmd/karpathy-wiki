#!/bin/bash
# Test: wiki-status.sh reports last_ingest from the manifest, not log.md.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
STATUS="${REPO_ROOT}/scripts/wiki-status.sh"

tmp="$(mktemp -d)"
trap "rm -rf '${tmp}'" EXIT

mkdir -p "${tmp}/wiki/raw" "${tmp}/wiki/.wiki-pending"
cat > "${tmp}/wiki/.wiki-config" <<'EOF'
role = "main"
created = "2026-04-22"
EOF

# Manifest claims last_ingested 2026-05-01.
cat > "${tmp}/wiki/.manifest.json" <<'EOF'
{
  "raw/foo.md": {
    "sha256": "abc",
    "origin": "conversation",
    "copied_at": "2026-04-24T12:00:00Z",
    "last_ingested": "2026-05-01T15:30:00Z",
    "referenced_by": []
  },
  "raw/bar.md": {
    "sha256": "def",
    "origin": "conversation",
    "copied_at": "2026-04-24T12:00:00Z",
    "last_ingested": "2026-04-24T12:00:00Z",
    "referenced_by": []
  }
}
EOF
echo "raw" > "${tmp}/wiki/raw/foo.md"
echo "raw" > "${tmp}/wiki/raw/bar.md"

# log.md has an OLDER date than the manifest's max -- to prove status reads
# from the manifest, not from log.md.
cat > "${tmp}/wiki/log.md" <<'EOF'
# Wiki Log

## [2026-04-22] init | wiki created
EOF

output="$(bash "${STATUS}" "${tmp}/wiki" 2>&1 || true)"
if echo "${output}" | grep -q "^last ingest: 2026-05-01"; then
  echo "PASS: status reads last ingest from manifest (max last_ingested)"
else
  echo "FAIL: expected 'last ingest: 2026-05-01', output: ${output}"
  exit 1
fi

echo "ALL PASS"
