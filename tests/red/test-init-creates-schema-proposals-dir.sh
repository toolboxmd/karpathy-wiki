#!/bin/bash
# RED: wiki-init.sh must create .wiki-pending/schema-proposals/ at init.
#
# Bug (0.2.8 #12): The ingest skill (skills/karpathy-wiki-ingest/SKILL.md
# step 7.6) tells the ingester to write schema-proposal files into
# <wiki>/.wiki-pending/schema-proposals/ when a category-threshold fires.
# wiki-init.sh creates .wiki-pending/ (line 61) but not the schema-proposals/
# subdir. First time a threshold fires, the writer crashes (or silently
# no-ops if it tolerates missing dirs).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -x "${INIT}" ]] || fail "wiki-init.sh missing or not executable"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

bash "${INIT}" main "${TMP}/wiki" >/dev/null

[[ -d "${TMP}/wiki/.wiki-pending/schema-proposals" ]] \
  || fail "schema-proposals dir not created at init: ${TMP}/wiki/.wiki-pending/schema-proposals"

echo "PASS: wiki-init creates .wiki-pending/schema-proposals/"
