#!/bin/bash
# Verify that capture never invents pointer or routing state. Selection belongs
# to the explicit one-step `wiki use project|main|both` command.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
WIKI_BIN="${REPO_ROOT}/bin/wiki"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

# Build a fake $HOME with a structurally-correct main wiki at $HOME/wiki/.
FAKE_HOME="${TESTDIR}/home"
mkdir -p "${FAKE_HOME}"
bash "${INIT}" main "${FAKE_HOME}/wiki" >/dev/null
# No runtime config is needed: all headline cases stop before dispatch.

# NOTE: we deliberately do NOT create ${FAKE_HOME}/.wiki-pointer.  That's
# the upgrade scenario this test exists to cover.

export HOME="${FAKE_HOME}"
export WIKI_POINTER_FILE="${FAKE_HOME}/.wiki-pointer"
export WIKI_ORPHANS_DIR="${FAKE_HOME}/.wiki-orphans"
export CLAUDE_HEADLESS=1

BODY=$(printf 'A real chat-only body that comfortably exceeds 1500 bytes.\n%.0s' {1..40})

# ---------------------------------------------------------------------------
# Case 1: even a complete $HOME/wiki does not silently select or write state.
# ---------------------------------------------------------------------------
SCRATCH1="${TESTDIR}/scratch1"
mkdir -p "${SCRATCH1}"
( cd "${SCRATCH1}" && echo "${BODY}" | bash "${WIKI_BIN}" capture \
    --title "PointerBootstrap" --kind chat-only --suggested-action create ) >/dev/null 2>&1 \
  && fail "case 1 (post-0.2.9): bootstrap + unconfigured cwd should abort with orphan"
[[ ! -f "${WIKI_POINTER_FILE}" ]] \
  || fail "case 1: capture silently created a main pointer"
[[ ! -f "${SCRATCH1}/.wiki-mode" ]] \
  || fail "case 1: abort path must not write .wiki-mode (was: $(cat "${SCRATCH1}/.wiki-mode" 2>/dev/null))"
ls "${WIKI_ORPHANS_DIR}/" 2>/dev/null | grep -q '\.md$' \
  || fail "case 1: body should be preserved as orphan"

# ---------------------------------------------------------------------------
# Case 2: pointer missing AND no $HOME/wiki at all → fall through to
# existing headless-orphan path (no prompt, no bootstrap, orphan preserved).
# ---------------------------------------------------------------------------
FAKE_HOME2="${TESTDIR}/home2"
mkdir -p "${FAKE_HOME2}"
export HOME="${FAKE_HOME2}"
export WIKI_POINTER_FILE="${FAKE_HOME2}/.wiki-pointer"
export WIKI_ORPHANS_DIR="${FAKE_HOME2}/.wiki-orphans"

SCRATCH2="${TESTDIR}/scratch2"
mkdir -p "${SCRATCH2}"
( cd "${SCRATCH2}" && echo "${BODY}" | bash "${WIKI_BIN}" capture \
    --title "NoBootstrapPossible" --kind chat-only --suggested-action create ) 2>/dev/null \
  && fail "case 2: no \$HOME/wiki + no pointer should abort with orphan"
[[ ! -f "${WIKI_POINTER_FILE}" ]] \
  || fail "case 2: pointer should NOT have been created (no \$HOME/wiki to bootstrap from)"
[[ -d "${WIKI_ORPHANS_DIR}" ]] \
  || fail "case 2: orphan dir should have been created"
ls "${WIKI_ORPHANS_DIR}/" | grep -q '\.md$' \
  || fail "case 2: orphan body should have been preserved"

# ---------------------------------------------------------------------------
# Case 3: $HOME/wiki exists but is NOT a structurally-correct main wiki
# (missing schema.md). Bootstrap MUST NOT fire — fall through to existing
# flow. This guards against silently writing a pointer at a half-built or
# non-wiki directory the user has at $HOME/wiki/.
# ---------------------------------------------------------------------------
FAKE_HOME3="${TESTDIR}/home3"
mkdir -p "${FAKE_HOME3}/wiki/.wiki-pending"
# A .wiki-config with role="main" but missing schema.md / index.md.
cat > "${FAKE_HOME3}/wiki/.wiki-config" <<'EOF'
role = "main"
EOF
export HOME="${FAKE_HOME3}"
export WIKI_POINTER_FILE="${FAKE_HOME3}/.wiki-pointer"
export WIKI_ORPHANS_DIR="${FAKE_HOME3}/.wiki-orphans"

SCRATCH3="${TESTDIR}/scratch3"
mkdir -p "${SCRATCH3}"
( cd "${SCRATCH3}" && echo "${BODY}" | bash "${WIKI_BIN}" capture \
    --title "HalfBuilt" --kind chat-only --suggested-action create ) 2>/dev/null \
  && fail "case 3: half-built \$HOME/wiki should NOT trigger bootstrap"
[[ ! -f "${WIKI_POINTER_FILE}" ]] \
  || fail "case 3: pointer should NOT have been written for half-built wiki"

# ---------------------------------------------------------------------------
# Case 4: $HOME/wiki exists with role="project" (not main). Bootstrap MUST
# NOT fire — that's not the user's main wiki, even if structurally complete.
# ---------------------------------------------------------------------------
FAKE_HOME4="${TESTDIR}/home4"
mkdir -p "${FAKE_HOME4}"
bash "${INIT}" main "${FAKE_HOME4}/wiki" >/dev/null
sed -i.bak 's|role = "main"|role = "project"|' "${FAKE_HOME4}/wiki/.wiki-config"
rm -f "${FAKE_HOME4}/wiki/.wiki-config.bak"
export HOME="${FAKE_HOME4}"
export WIKI_POINTER_FILE="${FAKE_HOME4}/.wiki-pointer"
export WIKI_ORPHANS_DIR="${FAKE_HOME4}/.wiki-orphans"

SCRATCH4="${TESTDIR}/scratch4"
mkdir -p "${SCRATCH4}"
( cd "${SCRATCH4}" && echo "${BODY}" | bash "${WIKI_BIN}" capture \
    --title "WrongRole" --kind chat-only --suggested-action create ) 2>/dev/null \
  && fail "case 4: \$HOME/wiki with role=project should NOT trigger bootstrap"
[[ ! -f "${WIKI_POINTER_FILE}" ]] \
  || fail "case 4: pointer should NOT have been written when role != main"

echo "PASS: bin/wiki capture never bootstraps pointer or routing state"
