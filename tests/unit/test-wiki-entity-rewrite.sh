#!/bin/bash
# Entity-map rewrite: identity sources stay, claim sources move, one commit.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WIKI_BIN="${REPO_ROOT}/bin/wiki"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"
SKILL="${REPO_ROOT}/skills/karpathy-wiki-rewrite/SKILL.md"
DOCTOR_SKILL="${REPO_ROOT}/skills/karpathy-wiki-doctor/SKILL.md"
export WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME=1

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -x "${REPO_ROOT}/scripts/wiki-rewrite-entity.py" ]] || fail "wiki-rewrite-entity.py is not executable"

TESTDIR="$(mktemp -d)"
TESTDIR="$(cd "${TESTDIR}" && pwd -P)"
export WIKI_CONFIG_HOME="${TESTDIR}/config-home"
trap 'rm -rf "${TESTDIR}"' EXIT

make_wiki() {
  local root="$1"
  bash "${INIT}" main "${root}" >/dev/null
  cat > "${root}/.wiki-config.local" <<'EOF'
[ingest]
dispatch_mode = "scheduled"
max_processes = 1
default_profile = "test_profile"
heartbeat_seconds = 5
stale_after_seconds = 30
usage_monitor = "off"
[ingest.profiles.test_profile]
provider = "codex"
model = "test-model"
reasoning_effort = "low"
[settings]
auto_commit = true
EOF
}

write_page() {
  local path="$1" title="$2" type="$3" sources_yaml="$4" body="$5"
  cat > "${path}" <<EOF
---
title: "${title}"
type: ${type}
tags: [carl-weische]
sources:
${sources_yaml}
summary: "${title}"
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
${body}
EOF
}

seed_fat_entity() {
  local wiki="$1"
  mkdir -p "${wiki}/raw" "${wiki}/entities" "${wiki}/concepts" "${wiki}/.wiki-pending/rewrite-jobs"
  printf 'handle\n' > "${wiki}/raw/handle.md"
  printf 'agency\n' > "${wiki}/raw/agency.md"
  printf 'check-in\n' > "${wiki}/raw/check-in.md"
  printf 'homepage claim\n' > "${wiki}/raw/homepage-hero.md"
  printf 'pdp claim\n' > "${wiki}/raw/pdp-proof.md"
  printf 'duplicate row\n' > "${wiki}/raw/homepage-hero.md"
  write_page "${wiki}/entities/carl-weische.md" "Carl Weische" entities \
    "  - raw/handle.md
  - raw/agency.md
  - raw/check-in.md
  - raw/homepage-hero.md
  - raw/pdp-proof.md
  - raw/homepage-hero.md" \
    "Catalog dump of every Carl source."
  write_page "${wiki}/concepts/homepage-playbook.md" "Homepage playbook" concepts \
    "  - raw/homepage-hero.md" \
    "Homepage playbook body."
  write_page "${wiki}/concepts/pdp-playbook.md" "PDP playbook" concepts \
    "  - raw/pdp-proof.md" \
    "PDP playbook body."
  cat > "${wiki}/.wiki-pending/rewrite-jobs/carl-weische.md" <<'EOF'
---
kind: entity
object: carl-weische
pages:
  - /entities/carl-weische.md
  - /concepts/homepage-playbook.md
  - /concepts/pdp-playbook.md
---
EOF
}

source_lines() {
  python3 - "$1" "${REPO_ROOT}/scripts" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, sys.argv[2])
from wiki_yaml import extract_frontmatter, parse_yaml
text = Path(sys.argv[1]).read_text()
parsed = parse_yaml(extract_frontmatter(text) or "")
for item in parsed.get("sources") or []:
    print(item)
PY
}

unique_source_count() {
  local wiki="$1"
  {
    source_lines "${wiki}/entities/carl-weische.md"
    source_lines "${wiki}/concepts/homepage-playbook.md"
    source_lines "${wiki}/concepts/pdp-playbook.md"
  } | sort -u | grep -c . || true
}

test_skill_names_entity_map() {
  grep -q 'kind: entity' "${SKILL}" || fail "rewrite skill missing entity jobs"
  grep -q 'Identity sources stay' "${SKILL}" || fail "rewrite skill missing identity-source rule"
  grep -q 'Claim sources move' "${SKILL}" || fail "rewrite skill missing claim-source rule"
  grep -q 'Do not remove `sources:`' "${DOCTOR_SKILL}" \
    || fail "doctor skill must still forbid deleting sources"
  echo "PASS: test_skill_names_entity_map"
}

test_entity_map_moves_claims_keeps_identity_and_commits_once() {
  local wiki="${TESTDIR}/entity-map"
  make_wiki "${wiki}"
  seed_fat_entity "${wiki}"
  local before after last unique_before unique_after
  unique_before="$(unique_source_count "${wiki}")"
  [[ "${unique_before}" -eq 5 ]] || fail "expected 5 unique source paths before, got ${unique_before}"
  before="$(cd "${wiki}" && git rev-list --count HEAD)"
  WIKI_REWRITE_TEST=1 bash "${WIKI_BIN}" rewrite "${wiki}" >/dev/null \
    || fail "entity rewrite test-mode failed"
  [[ ! -f "${wiki}/.wiki-pending/rewrite-jobs/carl-weische.md" ]] \
    || fail "entity job was not archived"
  grep -qv 'Catalog dump of every Carl source' "${wiki}/entities/carl-weische.md" \
    || fail "entity is still a catalog"
  grep -qi 'entity map\|playbook' "${wiki}/entities/carl-weische.md" \
    || fail "entity page is not a map"
  grep -q '/concepts/homepage-playbook.md' "${wiki}/entities/carl-weische.md" \
    || fail "entity related missing homepage playbook"
  grep -q '/concepts/pdp-playbook.md' "${wiki}/entities/carl-weische.md" \
    || fail "entity related missing pdp playbook"
  source_lines "${wiki}/entities/carl-weische.md" | grep -Fxq 'raw/handle.md' \
    || fail "identity source handle left the entity"
  source_lines "${wiki}/entities/carl-weische.md" | grep -Fxq 'raw/agency.md' \
    || fail "identity source agency left the entity"
  source_lines "${wiki}/entities/carl-weische.md" | grep -Fxq 'raw/check-in.md' \
    || fail "identity source check-in left the entity"
  if source_lines "${wiki}/entities/carl-weische.md" | grep -Fxq 'raw/homepage-hero.md'; then
    fail "claim source homepage-hero stayed on the entity"
  fi
  if source_lines "${wiki}/entities/carl-weische.md" | grep -Fxq 'raw/pdp-proof.md'; then
    fail "claim source pdp-proof stayed on the entity"
  fi
  source_lines "${wiki}/concepts/homepage-playbook.md" | grep -Fxq 'raw/homepage-hero.md' \
    || fail "homepage playbook lost its claim source"
  source_lines "${wiki}/concepts/pdp-playbook.md" | grep -Fxq 'raw/pdp-proof.md' \
    || fail "pdp playbook lost its claim source"
  unique_after="$(unique_source_count "${wiki}")"
  [[ "${unique_after}" -eq "${unique_before}" ]] \
    || fail "unique source paths dropped from ${unique_before} to ${unique_after}"
  after="$(cd "${wiki}" && git rev-list --count HEAD)"
  [[ "${after}" -eq $((before + 1)) ]] || fail "expected one entity rewrite commit"
  last="$(cd "${wiki}" && git log -1 --format=%s)"
  [[ "${last}" == "rewrite: carl-weische" ]] || fail "commit message was '${last}'"
  echo "PASS: test_entity_map_moves_claims_keeps_identity_and_commits_once"
}

test_doctor_does_not_trim_entity_sources() {
  local wiki="${TESTDIR}/doctor-sources"
  make_wiki "${wiki}"
  seed_fat_entity "${wiki}"
  WIKI_DOCTOR_TEST=1 bash "${WIKI_BIN}" doctor "${wiki}" >/dev/null \
    || fail "doctor test-mode failed with entity job present"
  source_lines "${wiki}/entities/carl-weische.md" | grep -Fxq 'raw/homepage-hero.md' \
    || fail "doctor trimmed a Carl source"
  grep -q 'Catalog dump of every Carl source' "${wiki}/entities/carl-weische.md" \
    || fail "doctor rewrote the entity body"
  [[ -f "${wiki}/.wiki-pending/rewrite-jobs/carl-weische.md" ]] \
    || fail "doctor executed the entity rewrite job"
  echo "PASS: test_doctor_does_not_trim_entity_sources"
}

test_skill_names_entity_map
test_entity_map_moves_claims_keeps_identity_and_commits_once
test_doctor_does_not_trim_entity_sources
echo "ALL PASS"
