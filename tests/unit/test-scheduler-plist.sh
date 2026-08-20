#!/bin/bash
# Pure LaunchAgent generation: no launchctl calls and no user files.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

python3 - "${REPO_ROOT}" <<'PY'
import plistlib
import sys
from pathlib import Path

repo = Path(sys.argv[1])
sys.path.insert(0, str(repo / "scripts"))
from wiki_scheduler import (
    GLOBAL_SCHEDULER_LABEL,
    build_launch_agent,
    scheduler_identity,
)

wiki = Path("/tmp/Wiki With Spaces").resolve()
label, plist_path = scheduler_identity(Path("/tmp/Home With Spaces"))
same_label, _ = scheduler_identity(Path("/different/home"))
assert label == same_label == GLOBAL_SCHEDULER_LABEL
assert plist_path.name == f"{label}.plist"

payload = build_launch_agent(
    repo / "bin" / "wiki",
    label,
    73,
    "/custom/bin:/usr/bin:/bin",
    Path("/tmp/Trusted Config Home"),
)
encoded = plistlib.dumps(payload, fmt=plistlib.FMT_XML, sort_keys=True)
decoded = plistlib.loads(encoded)
args = decoded["ProgramArguments"]
assert args == [
    str((repo / "bin" / "wiki").resolve()),
    "scheduler",
    "tick-all",
]
assert decoded["Label"] == label
assert decoded["StartInterval"] == 73
assert decoded["RunAtLoad"] is True
assert decoded["EnvironmentVariables"] == {
    "PATH": "/custom/bin:/usr/bin:/bin",
    "WIKI_CONFIG_HOME": str(Path("/tmp/Trusted Config Home").resolve()),
}
assert decoded["StandardOutPath"].endswith("/scheduler/scheduler.log")
assert decoded["StandardErrorPath"].endswith("/scheduler/scheduler.log")
print("PASS: global LaunchAgent plist is stable, path-safe, and complete")
PY

python3 - "${REPO_ROOT}/README.md" <<'PY'
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(encoding="utf-8")
upgrade = text.split("To update a GitHub installation:", 1)[1].split(
    "For development from a local checkout:", 1
)[0]
remove = upgrade.index("codex plugin remove")
add = upgrade.index("codex plugin add")
install = upgrade.index("wiki scheduler install")
assert remove < add < install
assert "one machine scheduler" in upgrade
assert "ask Codex" in upgrade
assert not any(
    line.strip().startswith("wiki scheduler ") for line in upgrade.splitlines()
)
print("PASS: documented plugin upgrade refreshes one global scheduler")
PY
