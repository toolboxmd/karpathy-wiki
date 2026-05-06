#!/bin/bash
# Integration test for v2.4 Leg 1: loader injected, skills split correctly,
# old skill still loads, hook behavior consistent across contexts.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${REPO_ROOT}/hooks/session-start"

fail() { echo "FAIL: $*" >&2; exit 1; }

# 1. All four skill files exist
for f in \
  skills/using-karpathy-wiki/SKILL.md \
  skills/karpathy-wiki-capture/SKILL.md \
  skills/karpathy-wiki-capture/references/capture-schema.md \
  skills/karpathy-wiki-ingest/SKILL.md \
  skills/karpathy-wiki-ingest/references/page-conventions.md \
  skills/karpathy-wiki/SKILL.md
do
  [[ -f "${REPO_ROOT}/${f}" ]] || fail "missing: ${f}"
done

# 2. Old skill description marks itself deprecated
grep -q 'DEPRECATED in v2.4' "${REPO_ROOT}/skills/karpathy-wiki/SKILL.md" \
  || fail "old skill description not updated"

# 3. Hook execution order: env-guard → loader → wiki-resolution
# Check by inspecting hook source (no need to mock the runtime — the
# unit tests already cover the runtime behavior end-to-end).
hook_src="$(cat "${HOOK}")"
guard_line=$(echo "${hook_src}" | grep -n 'WIKI_CAPTURE.*CLAUDE_AGENT_PARENT' | head -1 | cut -d: -f1)
loader_line=$(echo "${hook_src}" | grep -n 'EXTREMELY_IMPORTANT' | head -1 | cut -d: -f1)
resolve_line=$(echo "${hook_src}" | grep -n 'wiki_root_from_cwd' | head -1 | cut -d: -f1)
[[ -n "${guard_line}" && -n "${loader_line}" && -n "${resolve_line}" ]] \
  || fail "hook missing one of: env guard, loader injection, wiki resolution"
[[ "${guard_line}" -lt "${loader_line}" ]] \
  || fail "hook ordering: env guard ($guard_line) must come before loader ($loader_line)"
[[ "${loader_line}" -lt "${resolve_line}" ]] \
  || fail "hook ordering: loader injection ($loader_line) must come before wiki resolution ($resolve_line)"

# 4. Smoke-run the existing unit + integration tests still pass
bash "${REPO_ROOT}/tests/unit/test-using-karpathy-wiki-loader.sh" >/dev/null \
  || fail "loader unit test"
bash "${REPO_ROOT}/tests/unit/test-capture-skill.sh" >/dev/null \
  || fail "capture skill unit test"
bash "${REPO_ROOT}/tests/unit/test-ingest-skill.sh" >/dev/null \
  || fail "ingest skill unit test"
bash "${REPO_ROOT}/tests/unit/test-skill-split-no-overlap.sh" >/dev/null \
  || fail "skill-split overlap test"
bash "${REPO_ROOT}/tests/unit/test-session-start-loader-injection.sh" >/dev/null \
  || fail "loader injection test"

echo "PASS: Leg 1 end-to-end integration"
