#!/bin/bash
# RED: Codex must be able to discover this repository as one local plugin that
# exposes the Karpathy Wiki skills and its lifecycle hooks.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

python3 - "${REPO_ROOT}" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
codex_manifest_path = root / ".codex-plugin" / "plugin.json"
claude_manifest_path = root / ".claude-plugin" / "plugin.json"
marketplace_path = root / ".agents" / "plugins" / "marketplace.json"
hooks_path = root / "hooks" / "hooks.json"

for path in (
    codex_manifest_path,
    claude_manifest_path,
    marketplace_path,
    hooks_path,
):
    if not path.is_file():
        raise SystemExit(f"required packaging file missing: {path.relative_to(root)}")

codex = json.loads(codex_manifest_path.read_text())
claude = json.loads(claude_manifest_path.read_text())
marketplace = json.loads(marketplace_path.read_text())
hooks = json.loads(hooks_path.read_text())

if codex.get("name") != "karpathy-wiki":
    raise SystemExit("Codex plugin name must be karpathy-wiki")
if codex.get("version") != claude.get("version"):
    raise SystemExit("Codex and Claude plugin versions must match")
if codex.get("skills") != "./skills/":
    raise SystemExit("Codex manifest must expose ./skills/")
if marketplace.get("name") != "toolboxmd":
    raise SystemExit("Codex marketplace identifier must be toolboxmd")
if marketplace.get("interface", {}).get("displayName") != "toolbox.md":
    raise SystemExit("Codex marketplace display name must be toolbox.md")

skill_dirs = sorted(path.parent for path in (root / "skills").glob("*/SKILL.md"))
if not skill_dirs:
    raise SystemExit("Codex plugin exposes no skills")

hook_map = hooks.get("hooks", {})
for event in ("SessionStart", "Stop"):
    if event not in hook_map:
        raise SystemExit(f"hooks/hooks.json is missing {event}")

commands = [
    hook.get("command", "")
    for groups in hook_map.values()
    for group in groups
    for hook in group.get("hooks", [])
    if hook.get("type") == "command"
]
if not commands:
    raise SystemExit("hooks/hooks.json has no command hooks")
if not all("${CLAUDE_PLUGIN_ROOT}/" in command for command in commands):
    raise SystemExit("hook commands must resolve from the plugin root")

plugins = marketplace.get("plugins", [])
matches = [plugin for plugin in plugins if plugin.get("name") == "karpathy-wiki"]
if len(matches) != 1:
    raise SystemExit("local Codex marketplace must expose karpathy-wiki exactly once")

source = matches[0].get("source", {})
if source.get("source") != "local" or source.get("path") != "./":
    raise SystemExit("local Codex marketplace must point at the repository root")

print(
    "PASS: Codex plugin manifest, skills, hooks, version, and local marketplace agree"
)
PY
