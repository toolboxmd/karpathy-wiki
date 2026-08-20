#!/bin/bash
# Provider adapters build argv arrays without shell parsing or silent fallback.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
export PYTHONPATH="${REPO_ROOT}/scripts"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT
WIKI="${TESTDIR}/wiki with spaces"
PLUGIN="${TESTDIR}/plugin with spaces"
CAPTURE="${WIKI}/.wiki-pending/capture with spaces.md.processing"
mkdir -p "${WIKI}/.wiki-pending" "${PLUGIN}"
printf 'capture\n' > "${CAPTURE}"

python3 - "${WIKI}" "${PLUGIN}" "${CAPTURE}" <<'PY' || fail "provider argv contract failed"
import json, pathlib, sys
from wiki_providers import build_provider_invocation

wiki, plugin, capture = (pathlib.Path(value).resolve() for value in sys.argv[1:])
run_id = "in-test"

def profile(provider, executable, model, effort):
    return {"provider": provider, "executable": executable, "model": model, "reasoning_effort": effort}

claude = build_provider_invocation(
    profile("claude", "/Applications/Claude Code/claude", "sonnet", "low"),
    wiki, capture, run_id, plugin,
)
assert claude.argv == [
    "/Applications/Claude Code/claude",
    "--plugin-dir", str(plugin),
    "--model", "sonnet",
    "--effort", "low",
    "--permission-mode", "auto",
    "--no-chrome",
    "--no-session-persistence",
    "--output-format", "json",
    "-p", claude.prompt,
]
assert claude.stdin_bytes is None

grok = build_provider_invocation(
    profile("grok", "/Applications/Grok Build/grok", "grok-4.5", "medium"),
    wiki, capture, run_id, plugin,
)
assert grok.argv == [
    "/Applications/Grok Build/grok",
    "--cwd", str(wiki),
    "--model", "grok-4.5",
    "--reasoning-effort", "medium",
    "--always-approve",
    "--max-turns", "150",
    "--no-memory",
    "--no-subagents",
    "--output-format", "streaming-json",
    "--prompt-file", str(grok.prompt_path),
]
assert grok.prompt_path.read_text() == grok.prompt
assert grok.stdin_bytes is None

codex = build_provider_invocation(
    profile("codex", "/Applications/Codex CLI/codex", "gpt-5.3-codex-spark", "high"),
    wiki, capture, run_id, plugin,
)
assert codex.argv == [
    "/Applications/Codex CLI/codex",
    "--model", "gpt-5.3-codex-spark",
    "-c", 'model_reasoning_effort="high"',
    "--cd", str(wiki),
    "--sandbox", "danger-full-access",
    "exec",
    "--ephemeral",
    "--ignore-user-config",
    "--skip-git-repo-check",
    "--json",
    "--output-last-message", str(codex.output_last_message_path),
    "-",
]
assert codex.stdin_bytes == codex.prompt.encode()
metadata = json.loads((codex.run_dir / "invocation.json").read_text())
assert metadata == {
    "run_id": run_id,
    "provider": "codex",
    "model": "gpt-5.3-codex-spark",
    "reasoning_effort": "high",
}

for invocation in (claude, grok, codex):
    assert isinstance(invocation.argv, list)
    assert all(isinstance(arg, str) for arg in invocation.argv)
    assert str(wiki) in invocation.argv or invocation.provider == "claude"
    assert invocation.model in invocation.argv
    assert invocation.reasoning_effort in " ".join(invocation.argv)
    assert invocation.run_dir.is_dir()
PY

python3 - <<'PY' || fail "unknown provider should fail"
from pathlib import Path
from wiki_providers import ProviderError, build_provider_invocation
try:
    build_provider_invocation(
        {"provider":"unknown","executable":"x","model":"m","reasoning_effort":"low"},
        Path("/tmp/wiki"), Path("/tmp/wiki/.wiki-pending/x.md.processing"), "in-x", Path("/tmp/plugin")
    )
except ProviderError:
    pass
else:
    raise AssertionError("unknown provider accepted")
PY

python3 - "${TESTDIR}" <<'PY' || fail "missing executable preflight failed"
import pathlib, sys
from wiki_providers import ProviderError, resolve_executable
missing = pathlib.Path(sys.argv[1]) / "does not exist" / "provider"
try:
    resolve_executable(str(missing))
except ProviderError as exc:
    assert "executable" in str(exc)
else:
    raise AssertionError("missing executable accepted")
PY

python3 - <<'PY' || fail "relative executable path validation failed"
from wiki_providers import ProviderError, resolve_executable

try:
    resolve_executable("bin/codex")
except ProviderError as exc:
    assert "absolute path" in str(exc)
else:
    raise AssertionError("relative executable path accepted")
PY

python3 - "${TESTDIR}" <<'PY' || fail "workspace executable containment failed"
import os
import pathlib
import sys
from wiki_providers import ProviderError, resolve_executable

workspace = pathlib.Path(sys.argv[1]) / "checkout"
workspace.mkdir()
executable = workspace / "provider"
executable.write_text("#!/bin/sh\nexit 0\n")
executable.chmod(0o755)
link = pathlib.Path(sys.argv[1]) / "provider-link"
link.symlink_to(executable)

for candidate in (str(executable), str(link)):
    try:
        resolve_executable(candidate, forbidden_roots=(workspace,))
    except ProviderError as exc:
        assert "trusted workspace" in str(exc)
    else:
        raise AssertionError(f"workspace executable accepted: {candidate}")

old_path = os.environ.get("PATH", "")
os.environ["PATH"] = f"{workspace}:{old_path}"
try:
    resolve_executable("provider", forbidden_roots=(workspace,))
except ProviderError as exc:
    assert "trusted workspace" in str(exc)
else:
    raise AssertionError("PATH-resolved workspace executable accepted")
PY

echo "PASS: provider adapters preserve argv boundaries, model, effort, and paths"
