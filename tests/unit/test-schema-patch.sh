#!/bin/bash
# wiki-schema-patch.py updates Objects, tags, and Categories from indexes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"
BUILD="${REPO_ROOT}/scripts/wiki-build-index.py"
PATCH="${REPO_ROOT}/scripts/wiki-schema-patch.py"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "${PATCH}" ]] || fail "wiki-schema-patch.py missing"

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
sources: []
summary: "${title} summary"
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
body
EOF
}

test_six_homepage_pages_add_object_and_tags() {
  setup
  local i
  for i in 1 2 3 4 5 6; do
    write_page "${TESTDIR}/wiki/concepts/home-${i}.md" \
      "Homepage layout ${i}" "[homepage, cro]"
  done
  python3 "${BUILD}" --wiki-root "${TESTDIR}/wiki" --rebuild-all
  python3 "${PATCH}" --wiki-root "${TESTDIR}/wiki"
  objects="$(awk '/^## Objects/{f=1;next} /^## /{f=0} f' "${TESTDIR}/wiki/schema.md")"
  printf '%s\n' "${objects}" | grep -q '^- homepage$' \
    || { echo "FAIL: homepage not added to Objects"; cat "${TESTDIR}/wiki/schema.md"; teardown; exit 1; }
  grep -q '^- cro$' "${TESTDIR}/wiki/schema.md" \
    || { echo "FAIL: cro not added to Tag Taxonomy"; teardown; exit 1; }
  if grep -q '(none yet)' "${TESTDIR}/wiki/schema.md"; then
    echo "FAIL: Objects still none yet after 6 hits"; teardown; exit 1
  fi
  echo "PASS: test_six_homepage_pages_add_object_and_tags"
  teardown
}

test_five_pages_do_not_add_object() {
  setup
  local i
  for i in 1 2 3 4 5; do
    write_page "${TESTDIR}/wiki/concepts/home-${i}.md" \
      "Homepage layout ${i}" "[homepage]"
  done
  python3 "${BUILD}" --wiki-root "${TESTDIR}/wiki" --rebuild-all
  python3 "${PATCH}" --wiki-root "${TESTDIR}/wiki"
  objects="$(awk '/^## Objects/{f=1;next} /^## /{f=0} f' "${TESTDIR}/wiki/schema.md")"
  if printf '%s\n' "${objects}" | grep -q '^- homepage$'; then
    echo "FAIL: 5 hits must not add object"; echo "${objects}"; teardown; exit 1
  fi
  echo "PASS: test_five_pages_do_not_add_object"
  teardown
}

test_categories_refresh_from_directories() {
  setup
  mkdir -p "${TESTDIR}/wiki/journal"
  python3 "${PATCH}" --wiki-root "${TESTDIR}/wiki"
  grep -q 'journal/' "${TESTDIR}/wiki/schema.md" \
    || { echo "FAIL: journal category missing"; teardown; exit 1; }
  echo "PASS: test_categories_refresh_from_directories"
  teardown
}

test_brand_leading_title_still_learns_homepage() {
  setup
  local i
  for i in 1 2 3 4 5 6; do
    write_page "${TESTDIR}/wiki/concepts/home-${i}.md" \
      "Naturbiss homepage ${i}" "[homepage]"
  done
  python3 "${BUILD}" --wiki-root "${TESTDIR}/wiki" --rebuild-all
  python3 "${PATCH}" --wiki-root "${TESTDIR}/wiki"
  objects="$(awk '/^## Objects/{f=1;next} /^## /{f=0} f' "${TESTDIR}/wiki/schema.md")"
  printf '%s\n' "${objects}" | grep -q '^- homepage$' \
    || { echo "FAIL: homepage missing when titles lead with a brand"; echo "${objects}"; teardown; exit 1; }
  echo "PASS: test_brand_leading_title_still_learns_homepage"
  teardown
}

test_tag_only_cluster_learns_object() {
  setup
  local i
  for i in 1 2 3 4 5 6; do
    write_page "${TESTDIR}/wiki/concepts/pdp-${i}.md" \
      "Offer tile ${i}" "[pdp]"
  done
  python3 "${BUILD}" --wiki-root "${TESTDIR}/wiki" --rebuild-all
  python3 "${PATCH}" --wiki-root "${TESTDIR}/wiki"
  objects="$(awk '/^## Objects/{f=1;next} /^## /{f=0} f' "${TESTDIR}/wiki/schema.md")"
  printf '%s\n' "${objects}" | grep -q '^- pdp$' \
    || { echo "FAIL: tag-only cluster did not add pdp"; echo "${objects}"; teardown; exit 1; }
  echo "PASS: test_tag_only_cluster_learns_object"
  teardown
}

test_extra_frontmatter_key_enters_page_contract() {
  setup
  write_page "${TESTDIR}/wiki/concepts/home.md" "Homepage" "[homepage]"
  python3 - "${TESTDIR}/wiki/concepts/home.md" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
text = text.replace("tags: [homepage]\n", "tags: [homepage]\nsurface: homepage\n")
path.write_text(text)
PY
  python3 "${PATCH}" --wiki-root "${TESTDIR}/wiki"
  contract="$(awk '/^## Page contract/{f=1;next} /^## /{f=0} f' "${TESTDIR}/wiki/schema.md")"
  printf '%s\n' "${contract}" | grep -q '^- surface$' \
    || { echo "FAIL: extra key surface missing from Page contract"; echo "${contract}"; teardown; exit 1; }
  if printf '%s\n' "${contract}" | grep -q '^- title$'; then
    echo "FAIL: plugin default title leaked into Page contract"; teardown; exit 1
  fi
  echo "PASS: test_extra_frontmatter_key_enters_page_contract"
  teardown
}

objects_section() {
  awk '/^## Objects/{f=1;next} /^## /{f=0} f' "${TESTDIR}/wiki/schema.md"
}

contract_section() {
  awk '/^## Page contract/{f=1;next} /^## /{f=0} f' "${TESTDIR}/wiki/schema.md"
}

test_junk_and_spray_tags_are_not_objects() {
  setup
  local i
  for i in $(seq 1 12); do
    write_page "${TESTDIR}/wiki/concepts/home-${i}.md" \
      "Homepage layout not merged first ${i}" "[cro, homepage]"
  done
  python3 "${BUILD}" --wiki-root "${TESTDIR}/wiki" --rebuild-all
  python3 "${PATCH}" --wiki-root "${TESTDIR}/wiki"
  objects="$(objects_section)"
  printf '%s\n' "${objects}" | grep -q '^- homepage$' \
    || { echo "FAIL: homepage missing from Objects"; echo "${objects}"; teardown; exit 1; }
  for junk in not merged first cro; do
    if printf '%s\n' "${objects}" | grep -q "^- ${junk}$"; then
      echo "FAIL: ${junk} must not be an Object"; echo "${objects}"; teardown; exit 1
    fi
  done
  grep -q '^- cro$' "${TESTDIR}/wiki/schema.md" \
    || { echo "FAIL: cro missing from Tag Taxonomy"; teardown; exit 1; }
  echo "PASS: test_junk_and_spray_tags_are_not_objects"
  teardown
}

test_stale_object_is_pruned() {
  setup
  local i
  for i in 1 2 3 4 5 6; do
    write_page "${TESTDIR}/wiki/concepts/home-${i}.md" \
      "Homepage layout ${i}" "[homepage]"
  done
  python3 "${BUILD}" --wiki-root "${TESTDIR}/wiki" --rebuild-all
  python3 "${PATCH}" --wiki-root "${TESTDIR}/wiki"
  objects="$(objects_section)"
  printf '%s\n' "${objects}" | grep -q '^- homepage$' \
    || { echo "FAIL: homepage missing before prune"; echo "${objects}"; teardown; exit 1; }
  rm -f "${TESTDIR}/wiki/concepts/home-4.md" \
    "${TESTDIR}/wiki/concepts/home-5.md" \
    "${TESTDIR}/wiki/concepts/home-6.md"
  python3 "${BUILD}" --wiki-root "${TESTDIR}/wiki" --rebuild-all
  python3 "${PATCH}" --wiki-root "${TESTDIR}/wiki"
  objects="$(objects_section)"
  if printf '%s\n' "${objects}" | grep -q '^- homepage$'; then
    echo "FAIL: homepage still listed after dropping under 6 hits"; echo "${objects}"; teardown; exit 1
  fi
  echo "PASS: test_stale_object_is_pruned"
  teardown
}

test_annotated_contract_key_is_not_duplicated() {
  setup
  python3 - "${TESTDIR}/wiki/schema.md" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
needle = "If it names none, write only the plugin defaults.\n"
insert = needle + "Extra frontmatter keys:\n- evidence_class: internal_shop_fact | customer_evidence | external_expert_claim | ingest_operations\n- source_owner: the person or corpus, only when evidence_class is external_expert_claim\n"
if needle not in text:
    raise SystemExit("seed schema missing page-contract prose")
path.write_text(text.replace(needle, insert, 1))
PY
  write_page "${TESTDIR}/wiki/concepts/home.md" "Homepage" "[homepage]"
  python3 - "${TESTDIR}/wiki/concepts/home.md" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
text = path.read_text()
text = text.replace("tags: [homepage]\n", "tags: [homepage]\nevidence_class: external_expert_claim\nsource_owner: Carl Weische\n")
path.write_text(text)
PY
  python3 "${PATCH}" --wiki-root "${TESTDIR}/wiki"
  contract="$(contract_section)"
  count="$(printf '%s\n' "${contract}" | grep -c '^- evidence_class' || true)"
  if [[ "${count}" -ne 1 ]]; then
    echo "FAIL: evidence_class bullet listed ${count} times in Page contract"; echo "${contract}"; teardown; exit 1
  fi
  printf '%s\n' "${contract}" | grep -q '^- evidence_class:' \
    || { echo "FAIL: annotated evidence_class bullet lost"; echo "${contract}"; teardown; exit 1; }
  if printf '%s\n' "${contract}" | grep -qx -- '- evidence_class'; then
    echo "FAIL: bare evidence_class duplicate appended"; echo "${contract}"; teardown; exit 1
  fi
  echo "PASS: test_annotated_contract_key_is_not_duplicated"
  teardown
}

test_six_homepage_pages_add_object_and_tags
test_five_pages_do_not_add_object
test_categories_refresh_from_directories
test_brand_leading_title_still_learns_homepage
test_tag_only_cluster_learns_object
test_extra_frontmatter_key_enters_page_contract
test_junk_and_spray_tags_are_not_objects
test_stale_object_is_pruned
test_annotated_contract_key_is_not_duplicated
echo "ALL PASS"
