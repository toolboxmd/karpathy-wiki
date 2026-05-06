#!/bin/bash
# Mechanical verification of plan invariants.
# Exits 0 on all green, 1 on any violation.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "${SCRIPT_DIR}/.." && pwd)"

fail=0
check() {
  local name="$1"; shift
  if "$@"; then
    echo "PASS: ${name}"
  else
    echo "FAIL: ${name}"
    fail=1
  fi
}

check "loader skill under 200 lines" \
  bash -c "[[ \$(wc -l < '${REPO}/skills/using-karpathy-wiki/SKILL.md') -lt 200 ]]"

check "capture skill under 250 lines" \
  bash -c "[[ \$(wc -l < '${REPO}/skills/karpathy-wiki-capture/SKILL.md') -lt 250 ]]"

check "read skill under 250 lines" \
  bash -c "[[ \$(wc -l < '${REPO}/skills/karpathy-wiki-read/SKILL.md') -lt 250 ]]"

check "ingest skill under 500 lines" \
  bash -c "[[ \$(wc -l < '${REPO}/skills/karpathy-wiki-ingest/SKILL.md') -lt 500 ]]"

check "legacy skills/karpathy-wiki/SKILL.md deleted (0.2.7 cleanup)" \
  bash -c "[[ ! -e '${REPO}/skills/karpathy-wiki/SKILL.md' ]]"

check "hooks.json has SessionStart matcher" \
  bash -c "grep -q 'startup|clear|compact' '${REPO}/hooks/hooks.json'"

check "hooks.json has Stop section" \
  bash -c "grep -q '\"Stop\"' '${REPO}/hooks/hooks.json'"

check "no WIKI_MAIN env var references" \
  bash -c "! grep -r 'WIKI_MAIN' '${REPO}/scripts' '${REPO}/skills' '${REPO}/hooks' 2>/dev/null"

check "no SKILL_DIR placeholder remains in any current SKILL.md" \
  bash -c "! grep -lq 'SKILL_DIR' '${REPO}/skills/using-karpathy-wiki/SKILL.md' '${REPO}/skills/karpathy-wiki-capture/SKILL.md' '${REPO}/skills/karpathy-wiki-read/SKILL.md' '${REPO}/skills/karpathy-wiki-ingest/SKILL.md'"

check "AGENTS.md is a symlink" \
  bash -c "[[ -L '${REPO}/AGENTS.md' ]]"

check ".gitattributes enforces LF" \
  bash -c "grep -q 'eol=lf' '${REPO}/.gitattributes'"

check "no run-hook.cmd present" \
  bash -c "[[ ! -e '${REPO}/hooks/run-hook.cmd' ]]"

check "all scripts are executable" \
  bash -c "[[ ! \$(find '${REPO}/scripts' '${REPO}/hooks' '${REPO}/bin' -type f \\( -name '*.sh' -o -name '*.py' -o -name 'session-start' -o -name 'stop' -o -name 'wiki' \\) ! -perm -u+x -print 2>/dev/null) ]]"

exit "${fail}"
