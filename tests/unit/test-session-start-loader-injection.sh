#!/bin/bash
# Verify the SessionStart hook injects the using-karpathy-wiki loader
# in normal contexts and skips it in subagent/ingester contexts.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${REPO_ROOT}/hooks/session-start"
LOADER="${REPO_ROOT}/skills/using-karpathy-wiki/SKILL.md"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "${HOOK}" ]] || fail "hook missing"
[[ -f "${LOADER}" ]] || fail "loader missing"

# Make a temp wiki so the drift-scan portion has something to look at
TESTDIR="$(mktemp -d)"
NOWIKI="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}" "${NOWIKI}"' EXIT
bash "${REPO_ROOT}/scripts/wiki-init.sh" main "${TESTDIR}/wiki" >/dev/null

cd "${TESTDIR}/wiki"

# Case 1: normal session — loader should be in additionalContext
output_normal=$(env -u WIKI_CAPTURE -u CLAUDE_AGENT_PARENT bash "${HOOK}" 2>/dev/null || true)
echo "${output_normal}" | grep -q 'additionalContext' \
  || fail "normal session: hook did not emit additionalContext"
echo "${output_normal}" | grep -q 'EXTREMELY_IMPORTANT' \
  || fail "normal session: additionalContext missing <EXTREMELY_IMPORTANT> wrapper"
echo "${output_normal}" | grep -q 'using-karpathy-wiki' \
  || fail "normal session: additionalContext missing loader name"

# Case 2: WIKI_CAPTURE set (we are inside an ingester) — no additionalContext
output_capture=$(WIKI_CAPTURE=1 bash "${HOOK}" 2>/dev/null || true)
if echo "${output_capture}" | grep -q 'additionalContext'; then
  fail "ingester context: hook leaked additionalContext"
fi

# Case 3: CLAUDE_AGENT_PARENT set (we are a subagent) — no additionalContext
output_subagent=$(env -u WIKI_CAPTURE CLAUDE_AGENT_PARENT=1 bash "${HOOK}" 2>/dev/null || true)
if echo "${output_subagent}" | grep -q 'additionalContext'; then
  fail "subagent context: hook leaked additionalContext"
fi

# Case 4: no wiki at cwd AND not under one — loader STILL injected
cd "${NOWIKI}"
output_nowiki=$(env -u WIKI_CAPTURE -u CLAUDE_AGENT_PARENT bash "${HOOK}" 2>/dev/null || true)
echo "${output_nowiki}" | grep -q 'additionalContext' \
  || fail "no-wiki cwd: hook did not emit additionalContext (loader must inject regardless of wiki presence)"

echo "PASS: SessionStart loader injection across all four contexts"
