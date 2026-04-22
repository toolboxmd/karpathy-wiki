#!/usr/bin/env python3
"""Hash manifest for raw/ files.

Usage:
    wiki-manifest.py build <wiki_root>
    wiki-manifest.py diff <wiki_root>

build: writes .manifest.json mapping raw/ paths to sha256.
diff: compares live raw/ against manifest; prints CLEAN or a list of
      NEW: / MODIFIED: / DELETED: lines to stdout.
"""

import hashlib
import json
import sys
from pathlib import Path


def _hash_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _scan_raw(wiki_root: Path) -> dict[str, str]:
    """Return {relative-path-from-wiki-root: sha256} for each file in raw/."""
    result: dict[str, str] = {}
    raw = wiki_root / "raw"
    if not raw.exists():
        return result
    for p in raw.rglob("*"):
        if p.is_file() and not p.name.startswith("."):
            rel = str(p.relative_to(wiki_root))
            result[rel] = _hash_file(p)
    return result


def _load_manifest(wiki_root: Path) -> dict:
    path = wiki_root / ".manifest.json"
    if not path.exists():
        return {}
    with path.open("r") as f:
        return json.load(f)


def cmd_build(wiki_root: Path) -> int:
    from datetime import datetime, timezone

    hashes = _scan_raw(wiki_root)
    existing = _load_manifest(wiki_root)
    now = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    out = {}
    for rel, sha in hashes.items():
        prev = existing.get(rel, {})
        out[rel] = {
            "sha256": sha,
            "last_ingested": prev.get("last_ingested", now),
        }
    (wiki_root / ".manifest.json").write_text(
        json.dumps(out, indent=2, sort_keys=True) + "\n"
    )
    return 0


def cmd_diff(wiki_root: Path) -> int:
    manifest = _load_manifest(wiki_root)
    live = _scan_raw(wiki_root)

    lines: list[str] = []

    for rel, sha in live.items():
        if rel not in manifest:
            lines.append(f"NEW: {rel}")
        elif manifest[rel].get("sha256") != sha:
            lines.append(f"MODIFIED: {rel}")

    for rel in manifest:
        if rel not in live:
            lines.append(f"DELETED: {rel}")

    if not lines:
        print("CLEAN")
    else:
        print("\n".join(lines))
    return 0


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: wiki-manifest.py {build|diff} <wiki_root>", file=sys.stderr)
        return 1

    cmd = sys.argv[1]
    wiki_root = Path(sys.argv[2]).resolve()
    if not wiki_root.is_dir():
        print(f"not a directory: {wiki_root}", file=sys.stderr)
        return 1

    if cmd == "build":
        return cmd_build(wiki_root)
    if cmd == "diff":
        return cmd_diff(wiki_root)
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
