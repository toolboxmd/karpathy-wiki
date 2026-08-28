#!/bin/bash
# wiki-topical-keep-tags.py: provenance tags gone, spray tags dropped,
# sources and body unchanged.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"
KEEP="${REPO_ROOT}/scripts/wiki-topical-keep-tags.py"
SKILL="${REPO_ROOT}/skills/karpathy-wiki-doctor/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "${KEEP}" ]] || fail "wiki-topical-keep-tags.py missing"

setup() {
  TESTDIR="$(mktemp -d)"
  bash "${INIT}" main "${TESTDIR}/wiki" >/dev/null
}

teardown() { rm -rf "${TESTDIR}"; }

write_page() {
  local path="$1" title="$2" tags="$3"
  cat > "${path}" <<EOF
---
title: "${title}"
type: concepts
tags: ${tags}
sources:
  - raw/one.md
  - raw/two.md
  - raw/three.md
summary: "${title}"
evidence_class: external_expert_claim
source_owner: Carl Weische
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
Playbook body stays.
EOF
}

test_cart_keeps_object_and_owner_strips_spray() {
  setup
  local i
  for i in 1 2 3 4 5 6; do
    write_page "${TESTDIR}/wiki/concepts/other-${i}.md" \
      "Other layout ${i}" "[cro, dtc-marketing, external-opinion]"
  done
  write_page "${TESTDIR}/wiki/concepts/cart-playbook.md" \
    "Cart drawer playbook" "[cart, cro, external-opinion, external-expert, carl-weische]"
  python3 "${KEEP}" --wiki-root "${TESTDIR}/wiki" \
    || { echo "FAIL: helper exited nonzero"; teardown; exit 1; }
  python3 - <<PY
import sys
from pathlib import Path
sys.path.insert(0, "${REPO_ROOT}/scripts")
from wiki_yaml import extract_frontmatter, parse_yaml, split_frontmatter
path = Path("${TESTDIR}/wiki/concepts/cart-playbook.md")
text = path.read_text()
fm = parse_yaml(extract_frontmatter(text))
tags = [str(t) for t in (fm.get("tags") or [])]
sources = fm.get("sources") or []
if tags != ["cart", "carl-weische"]:
    print("FAIL: tags", tags)
    sys.exit(1)
if sources != ["raw/one.md", "raw/two.md", "raw/three.md"]:
    print("FAIL: sources mutated", sources)
    sys.exit(1)
opener, block, after = split_frontmatter(text)
if after is None or "Playbook body stays." not in after:
    print("FAIL: body rewritten")
    sys.exit(1)
print("ok")
PY
  echo "PASS: test_cart_keeps_object_and_owner_strips_spray"
  teardown
}

test_skill_forbids_source_deletion() {
  grep -q 'wiki-topical-keep-tags.py' "${SKILL}" \
    || fail "doctor skill must run topical-keep helper"
  grep -qi 'Do not remove .sources' "${SKILL}" \
    || grep -q 'must not remove `sources:`' "${SKILL}" \
    || fail "doctor skill must forbid removing sources"
  grep -q 'external-opinion' "${SKILL}" \
    || fail "doctor skill must name provenance tags"
  echo "PASS: test_skill_forbids_source_deletion"
}

test_cart_keeps_object_and_owner_strips_spray
test_skill_forbids_source_deletion
echo "ALL PASS"
