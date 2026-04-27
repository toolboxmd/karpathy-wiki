#!/bin/bash
# Test: wiki-migrate-v2.2.sh in --dry-run mode lists every mutation it WOULD
# perform, given a fixture wiki that mirrors the v2.2 audit's findings.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MIGRATE="${REPO_ROOT}/scripts/wiki-migrate-v2.2.sh"

tmp="$(mktemp -d)"
trap "rm -rf '${tmp}'" EXIT

# Fixture: minimal wiki with each Phase D mutation target represented.
mkdir -p "${tmp}/wiki/concepts" \
         "${tmp}/wiki/sources" \
         "${tmp}/wiki/raw" \
         "${tmp}/wiki/.wiki-pending/archive/2026-04"
touch "${tmp}/wiki/.wiki-config"

# 1. Sources/ pages to delete.
echo "stub" > "${tmp}/wiki/sources/2026-04-24-foo.md"
echo "stub" > "${tmp}/wiki/sources/2026-04-24-bar.md"

# 2. A concept page citing sources/ in frontmatter (will be rewritten).
cat > "${tmp}/wiki/concepts/foo.md" <<'EOF'
---
title: "Foo"
type: concept
sources:
  - sources/2026-04-24-foo.md
---
body
EOF

# 3. A concept page with a body link to sources/ (will be cleaned).
cat > "${tmp}/wiki/concepts/bar.md" <<'EOF'
---
title: "Bar"
type: concept
sources:
  - raw/2026-04-24-bar.md
---
See [the source](../sources/2026-04-24-bar.md) for details.
EOF

# 4. starship-style same-dir-prefix-bug links.
cat > "${tmp}/wiki/concepts/starship.md" <<'EOF'
---
title: "Starship"
type: concept
sources:
  - "conversation"
---
- [Cyberpunk](concepts/cyberpunk.md)
- [Zellij](concepts/zellij.md)
EOF
echo "stub" > "${tmp}/wiki/concepts/cyberpunk.md"
echo "stub" > "${tmp}/wiki/concepts/zellij.md"

# 5. Manifest with empty-origin entries.
cat > "${tmp}/wiki/.manifest.json" <<'EOF'
{
  "raw/2026-04-24-bar.md": {
    "sha256": "x",
    "origin": "",
    "copied_at": "2026-04-24T12:00:00Z",
    "last_ingested": "2026-04-24T12:00:00Z",
    "referenced_by": []
  }
}
EOF
echo "raw" > "${tmp}/wiki/raw/2026-04-24-bar.md"

# 6. Archive .md.processing legacy files.
echo "stub" > "${tmp}/wiki/.wiki-pending/archive/2026-04/2026-04-24T12-00-00Z-old.md.processing"

# Run dry-run; capture output.
output="$(bash "${MIGRATE}" --dry-run "${tmp}/wiki" 2>&1)"
rc=$?
if [[ ${rc} -ne 0 ]]; then
  echo "FAIL: --dry-run exited ${rc}. Output: ${output}"
  exit 1
fi

# Assert each migration is announced in dry-run output.
for needle in \
  "would-remove sources/2026-04-24-foo.md" \
  "would-remove sources/2026-04-24-bar.md" \
  "would-rewrite concepts/foo.md sources: sources/ -> raw/" \
  "would-rewrite concepts/bar.md body-link sources/" \
  "would-fix-prefix concepts/starship.md" \
  "would-set-origin raw/2026-04-24-bar.md = conversation" \
  "would-rename .wiki-pending/archive/2026-04/2026-04-24T12-00-00Z-old.md.processing -> .md"; do
  if ! echo "${output}" | grep -q "${needle}"; then
    echo "FAIL: dry-run missing announcement: ${needle}"
    echo "Output was:"
    echo "${output}"
    exit 1
  fi
done

# Assert dry-run did NOT mutate anything.
[[ -f "${tmp}/wiki/sources/2026-04-24-foo.md" ]] || { echo "FAIL: dry-run deleted file"; exit 1; }
[[ "$(grep -c 'sources/2026-04-24-foo' "${tmp}/wiki/concepts/foo.md")" -eq 1 ]] || { echo "FAIL: dry-run rewrote frontmatter"; exit 1; }

echo "PASS: --dry-run announces every mutation without mutating"

# Now run for real.
bash "${MIGRATE}" "${tmp}/wiki" >/dev/null 2>&1

# Assert outcomes.
[[ ! -d "${tmp}/wiki/sources" ]] || [[ -z "$(ls -A "${tmp}/wiki/sources" 2>/dev/null)" ]] || { echo "FAIL: sources/ not removed"; ls "${tmp}/wiki/sources"; exit 1; }
grep -q '^  - raw/2026-04-24-foo.md' "${tmp}/wiki/concepts/foo.md" || { echo "FAIL: concepts/foo.md frontmatter not rewritten"; cat "${tmp}/wiki/concepts/foo.md"; exit 1; }
! grep -q 'sources/' "${tmp}/wiki/concepts/bar.md" || { echo "FAIL: concepts/bar.md body still references sources/"; cat "${tmp}/wiki/concepts/bar.md"; exit 1; }
grep -q '^- \[Cyberpunk\](cyberpunk.md)' "${tmp}/wiki/concepts/starship.md" || { echo "FAIL: starship.md prefix not fixed"; cat "${tmp}/wiki/concepts/starship.md"; exit 1; }
grep -q '"origin": "conversation"' "${tmp}/wiki/.manifest.json" || { echo "FAIL: manifest origin not set"; cat "${tmp}/wiki/.manifest.json"; exit 1; }
[[ -f "${tmp}/wiki/.wiki-pending/archive/2026-04/2026-04-24T12-00-00Z-old.md" ]] || { echo "FAIL: archive .processing not renamed"; ls "${tmp}/wiki/.wiki-pending/archive/2026-04"; exit 1; }
[[ ! -f "${tmp}/wiki/.wiki-pending/archive/2026-04/2026-04-24T12-00-00Z-old.md.processing" ]] || { echo "FAIL: archive .processing still present after rename"; exit 1; }

echo "PASS: live run applied every migration correctly"
echo "ALL PASS"
