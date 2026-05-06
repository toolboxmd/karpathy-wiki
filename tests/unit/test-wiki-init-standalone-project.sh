#!/bin/bash
# Verify wiki-init.sh project <path> works without a main_path argument.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

# Standalone project mode: no third argument
bash "${INIT}" project "${TESTDIR}/wiki" >/dev/null \
  || fail "wiki-init.sh project <path> (no main) must succeed"

# Verify config has role = "project" and NO main field
config="${TESTDIR}/wiki/.wiki-config"
[[ -f "${config}" ]] || fail "no .wiki-config written"
grep -q '^role = "project"' "${config}" || fail "config role != \"project\""
if grep -q '^main = ' "${config}"; then
  fail "standalone project should NOT have a main field"
fi

# Required structure
for f in index.md log.md schema.md .manifest.json .gitignore; do
  [[ -e "${TESTDIR}/wiki/${f}" ]] || fail "missing ${f}"
done

# Existing two-arg form still works
bash "${INIT}" project "${TESTDIR}/wiki2" "${TESTDIR}/wiki" >/dev/null \
  || fail "wiki-init.sh project <path> <main> must still succeed"
grep -q '^main = ' "${TESTDIR}/wiki2/.wiki-config" || fail "with-main form lost main field"

echo "PASS: wiki-init.sh standalone project mode"
