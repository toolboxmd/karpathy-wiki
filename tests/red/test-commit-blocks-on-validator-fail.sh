#!/bin/bash
# RED: scripts/wiki-commit.sh must reject commits when any wiki page in the
# staged set fails wiki-validate-page.py.
#
# Bug (0.2.8 #3): The ingest skill says "the ingester MUST NOT call
# wiki-commit.sh until every touched page passes the validator"
# (skills/karpathy-wiki-ingest/SKILL.md:398). This is prose enforcement
# only — a sloppy ingester (or a future codepath that bypasses the skill
# prose) can call wiki-commit.sh on a malformed page and silently land it
# in the wiki history. The user has no way to observe this failure mode;
# they see the broken page only after it rots downstream LLM context.
#
# Test:
#   1. Stand up a temp wiki with `git init` so commits are possible.
#   2. Write a page missing required frontmatter fields under concepts/.
#   3. Call wiki-commit.sh and assert non-zero exit + no commit created.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"
COMMIT="${REPO_ROOT}/scripts/wiki-commit.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -x "${COMMIT}" ]] || fail "wiki-commit.sh missing"

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

WIKI="${TMP}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null

# wiki-init already runs `git init` and produces an initial commit; just
# set local git identity so subsequent commits don't fail in CI envs.
( cd "${WIKI}" && \
  git config user.email test@example.com && \
  git config user.name test )

base_sha=$(cd "${WIKI}" && git rev-parse HEAD)

# Write a malformed page: missing required frontmatter `type` field.
mkdir -p "${WIKI}/concepts"
cat > "${WIKI}/concepts/bad.md" <<'EOF'
---
title: "Bad Page"
tags: [test]
sources: ["conversation"]
created: "2026-05-06T00:00:00Z"
updated: "2026-05-06T00:00:00Z"
---

This page is missing the required `type` frontmatter field. The
validator should reject it. wiki-commit.sh must not commit it.
EOF

# Sanity-check that the validator actually rejects this page (otherwise
# we're testing the wrong thing).
if python3 "${REPO_ROOT}/scripts/wiki-validate-page.py" --wiki-root "${WIKI}" "${WIKI}/concepts/bad.md" >/dev/null 2>&1; then
  fail "validator unexpectedly accepted the malformed page; the test is broken, not the bug"
fi

# Call wiki-commit.sh. It should exit non-zero AND leave HEAD unchanged.
bash "${COMMIT}" "${WIKI}" "should be blocked" >/dev/null 2>&1 && rc=0 || rc=$?

new_sha=$(cd "${WIKI}" && git rev-parse HEAD)

if [[ "${rc}" == 0 ]]; then
  fail "wiki-commit.sh exited 0 despite malformed page (expected non-zero)"
fi

if [[ "${new_sha}" != "${base_sha}" ]]; then
  fail "wiki-commit.sh created a commit despite validator failure: ${base_sha} → ${new_sha}"
fi

echo "PASS: wiki-commit.sh blocks commit when a staged page fails the validator"
