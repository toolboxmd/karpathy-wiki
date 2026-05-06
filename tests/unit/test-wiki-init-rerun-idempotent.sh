#!/bin/bash
# Verify wiki-init.sh on an existing wiki is idempotent (skips existing
# artifacts) and adds new pieces (inbox/, .raw-staging/, README.md).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

# 1. Initial main wiki creation
bash "${INIT}" main "${TESTDIR}/wiki" >/dev/null \
  || fail "first init must succeed"

# 2. Hand-edit an existing artifact to verify it's preserved on re-run
echo "USER EDIT" > "${TESTDIR}/wiki/index.md"
echo "USER README" > "${TESTDIR}/wiki/README.md"
mtime_before=$(stat -f %m "${TESTDIR}/wiki/.wiki-config" 2>/dev/null || stat -c %Y "${TESTDIR}/wiki/.wiki-config")

# 3. Delete inbox/ and .raw-staging/ to simulate v2.3-pre-upgrade state
rm -rf "${TESTDIR}/wiki/inbox" "${TESTDIR}/wiki/.raw-staging"

# 4. Re-run init
sleep 1  # ensure mtime granularity
bash "${INIT}" main "${TESTDIR}/wiki" >/dev/null \
  || fail "re-run must succeed"

# 5. User edits preserved
grep -q "USER EDIT" "${TESTDIR}/wiki/index.md" || fail "user-edited index.md was overwritten"
grep -q "USER README" "${TESTDIR}/wiki/README.md" || fail "user-edited README.md was overwritten"

# 6. Missing pieces created
[[ -d "${TESTDIR}/wiki/inbox" ]] || fail "re-run did not create inbox/"
[[ -d "${TESTDIR}/wiki/.raw-staging" ]] || fail "re-run did not create .raw-staging/"

# 7. .wiki-config not rewritten (preserves created date)
mtime_after=$(stat -f %m "${TESTDIR}/wiki/.wiki-config" 2>/dev/null || stat -c %Y "${TESTDIR}/wiki/.wiki-config")
[[ "${mtime_before}" == "${mtime_after}" ]] || fail ".wiki-config was rewritten on re-run"

# 8. Fresh init writes a README (the user one was preserved above; verify a fresh
#    init would produce a README too)
TESTDIR2="$(mktemp -d)"
bash "${INIT}" main "${TESTDIR2}/wiki" >/dev/null
[[ -f "${TESTDIR2}/wiki/README.md" ]] || fail "fresh init did not create README.md"
grep -q -i 'inbox' "${TESTDIR2}/wiki/README.md" || fail "README does not mention inbox/"
grep -q -i 'raw' "${TESTDIR2}/wiki/README.md" || fail "README does not mention raw/ rule"
rm -rf "${TESTDIR2}"

echo "PASS: wiki-init.sh re-runnable + creates v2.4 pieces"
