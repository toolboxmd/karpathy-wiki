#!/bin/bash
# The SessionStart hook must short-circuit for EVERY sentinel that a
# spawned child `claude -p` carries — not just the ingester ones.
#
# wiki-sweep.sh runs its worker as:
#     WIKI_SWEEP_INSIDE=1 claude -p "<prompt>"
# That child session fires SessionStart again. Without WIKI_SWEEP_INSIDE in
# the guard, every sweep worker runs the full loader + drift-scan + drain,
# each drain spawning more `claude -p` — the observed 663-process fork bomb
# (2026-07-14). Regression test for that root cause.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${REPO_ROOT}/hooks/session-start"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "${HOOK}" ]] || fail "hook missing"

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT
bash "${REPO_ROOT}/scripts/wiki-init.sh" main "${TESTDIR}/wiki" >/dev/null

cd "${TESTDIR}/wiki"

# Sanity: without any sentinel the hook DOES do its work (so a green result
# below cannot come from a hook that is broken for everyone).
output_normal=$(env -u WIKI_CAPTURE -u CLAUDE_AGENT_PARENT -u WIKI_SWEEP_INSIDE \
  bash "${HOOK}" 2>/dev/null || true)
echo "${output_normal}" | grep -q 'additionalContext' \
  || fail "normal session: hook did not emit additionalContext (test fixture broken)"

# Every sentinel a spawned child carries must skip the hook entirely.
for sentinel in WIKI_CAPTURE CLAUDE_AGENT_PARENT WIKI_SWEEP_INSIDE; do
  out=$(env -u WIKI_CAPTURE -u CLAUDE_AGENT_PARENT -u WIKI_SWEEP_INSIDE \
    "${sentinel}=1" bash "${HOOK}" 2>/dev/null || true)
  if [[ -n "${out}" ]]; then
    fail "${sentinel} set: hook produced stdout (\"${out:0:80}\") — guard breached, sweep children will fork-bomb"
  fi
done

# The sentinel list in the hook must stay in sync with what wiki-sweep.sh
# actually exports onto its `claude -p` child. If a new WIKI_SWEEP_*_INSIDE
# style sentinel appears in the sweep script, this catches it.
SWEEP="${REPO_ROOT}/scripts/wiki-sweep.sh"
if [[ -f "${SWEEP}" ]]; then
  while IFS= read -r var; do
    grep -q "${var}" "${HOOK}" \
      || fail "wiki-sweep.sh sets ${var} on its claude -p child but hooks/session-start does not guard on it"
  done < <(grep -oE '\b[A-Z_]*INSIDE[A-Z_]*=1[[:space:]]*\\?[[:space:]]*$' "${SWEEP}" \
             | sed 's/=1.*//' | sort -u)
fi

echo "PASS: SessionStart hook skips for all spawned-child sentinels"
