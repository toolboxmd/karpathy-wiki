#!/bin/bash
# RED: Claude Code SessionStart hook output must include hookEventName.
#
# Bug report (2026-05-06): A fresh `claude` session in ~/dev/default fired:
#   SessionStart:startup hook error
#   Hook JSON output validation failed — hookSpecificOutput is missing
#   required field "hookEventName"
#
# Cause: hooks/session-start emits {"hookSpecificOutput":{"additionalContext":"..."}}
# for the Claude Code branch (CLAUDE_PLUGIN_ROOT set, COPILOT_CLI unset).
# Claude Code's hook schema requires hookEventName: "SessionStart" inside
# hookSpecificOutput. The other two harness branches (Cursor's snake-case
# additional_context, Copilot's top-level additionalContext) do not need
# it (verified against cursor.com/docs/agent/hooks and
# docs.github.com/copilot/reference/hooks-configuration).
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
HOOK="${REPO_ROOT}/hooks/session-start"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -f "${HOOK}" ]] || fail "hook missing"

# Run the hook with the Claude Code harness signature: CLAUDE_PLUGIN_ROOT set,
# CURSOR_PLUGIN_ROOT unset, COPILOT_CLI unset.
output=$(env -u WIKI_CAPTURE -u CLAUDE_AGENT_PARENT -u CURSOR_PLUGIN_ROOT -u COPILOT_CLI \
  CLAUDE_PLUGIN_ROOT="${REPO_ROOT}" \
  bash "${HOOK}" 2>/dev/null || true)

# It must be Claude-Code-shaped: hookSpecificOutput nested.
echo "${output}" | grep -q '"hookSpecificOutput"' \
  || fail "Claude Code branch did not emit hookSpecificOutput. Output: ${output:0:200}"

# Must contain hookEventName: "SessionStart" inside that nested object.
# Pipe the raw hook output to Python so embedded escaped newlines survive
# verbatim (heredoc-with-${output} mangles them).
echo "${output}" | python3 -c '
import json, sys
raw = sys.stdin.read()
try:
    data = json.loads(raw)
except json.JSONDecodeError as e:
    print(f"hook output is not valid JSON: {e}", file=sys.stderr)
    sys.exit(1)

hso = data.get("hookSpecificOutput")
if not isinstance(hso, dict):
    print("hookSpecificOutput missing or not an object", file=sys.stderr)
    sys.exit(1)

if hso.get("hookEventName") != "SessionStart":
    got = repr(hso.get("hookEventName"))
    print("hookEventName missing or wrong: " + got + " (need SessionStart)", file=sys.stderr)
    sys.exit(1)

if not hso.get("additionalContext"):
    print("additionalContext missing or empty", file=sys.stderr)
    sys.exit(1)

print("OK: hookSpecificOutput has hookEventName=SessionStart and non-empty additionalContext")
' || fail "hookEventName check failed"

# Cursor branch must NOT have hookEventName (it's snake_case top-level).
cursor_out=$(env -u WIKI_CAPTURE -u CLAUDE_AGENT_PARENT -u COPILOT_CLI \
  CURSOR_PLUGIN_ROOT="${REPO_ROOT}" CLAUDE_PLUGIN_ROOT="${REPO_ROOT}" \
  bash "${HOOK}" 2>/dev/null || true)
echo "${cursor_out}" | grep -q '"additional_context"' \
  || fail "Cursor branch did not emit additional_context"
if echo "${cursor_out}" | grep -q '"hookEventName"'; then
  fail "Cursor branch should NOT include hookEventName"
fi

echo "PASS: SessionStart hook emits Claude-Code-required hookEventName, Cursor branch unchanged"
