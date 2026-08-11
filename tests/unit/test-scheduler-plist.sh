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
from wiki_scheduler import build_launch_agent, scheduler_identity

wiki = Path("/tmp/Wiki With Spaces").resolve()
label, plist_path = scheduler_identity(wiki, Path("/tmp/Home With Spaces"))
same_label, _ = scheduler_identity(wiki, Path("/different/home"))
other_label, _ = scheduler_identity(Path("/tmp/other-wiki"), Path("/tmp/Home With Spaces"))
assert label == same_label
assert label != other_label
assert label.startswith("com.toolboxmd.karpathy-wiki.")
assert plist_path.name == f"{label}.plist"

payload = build_launch_agent(
    wiki,
    repo / "bin" / "wiki",
    label,
    73,
    "/custom/bin:/usr/bin:/bin",
)
encoded = plistlib.dumps(payload, fmt=plistlib.FMT_XML, sort_keys=True)
decoded = plistlib.loads(encoded)
args = decoded["ProgramArguments"]
assert args == [
    str((repo / "bin" / "wiki").resolve()),
    "tick",
    str(wiki),
    "--source",
    "scheduled",
    "--scan",
]
assert decoded["Label"] == label
assert decoded["StartInterval"] == 73
assert decoded["RunAtLoad"] is True
assert decoded["EnvironmentVariables"]["PATH"] == "/custom/bin:/usr/bin:/bin"
assert decoded["StandardOutPath"] == str(wiki / ".ingest.log")
assert decoded["StandardErrorPath"] == str(wiki / ".ingest.log")
print("PASS: LaunchAgent plist is stable, path-safe, and complete")
PY
