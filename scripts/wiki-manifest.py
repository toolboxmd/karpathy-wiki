#!/usr/bin/env python3
"""Hash manifest for raw/ files — v2-hardened schema.

Usage:
    wiki-manifest.py build    <wiki_root>
    wiki-manifest.py diff     <wiki_root>
    wiki-manifest.py migrate  <wiki_root>
    wiki-manifest.py validate <wiki_root>

Canonical schema for <wiki_root>/.manifest.json (one per wiki):

    {
      "raw/2026-04-24-example.md": {
        "sha256": "<64-hex>",
        "origin": "<absolute path>" or "conversation",
        "copied_at": "<ISO-8601 UTC>",
        "last_ingested": "<ISO-8601 UTC>",
        "referenced_by": ["concepts/...", "sources/...", ...]
      }
    }

build: rewrite `.manifest.json` with current sha256 for every raw file.
       Preserves `origin`, `copied_at`, `referenced_by` from prior entries.
       `last_ingested` is refreshed to now.
diff:  compare live raw/ sha256 against manifest. Prints CLEAN or NEW/MODIFIED/
       DELETED lines.
migrate: one-time migration for v2 -> v2-hardening:
       Merges any legacy <wiki_root>/raw/.manifest.json into the unified
       <wiki_root>/.manifest.json, normalizes field names (source -> origin,
       added -> copied_at), strips `referenced_by` entries that don't exist
       on disk, and deletes the legacy raw/.manifest.json.
"""

import hashlib
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path


def _atomic_write_json(path: Path, payload: str) -> None:
    """Write `payload` to `path` atomically: write to .tmp, then os.rename.

    POSIX guarantees rename is atomic when source and destination are on
    the same filesystem. A concurrent reader sees either the old file or
    the new file, never a partial write.
    """
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(payload)
    os.rename(tmp, path)


def _hash_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def _scan_raw(wiki_root: Path) -> dict[str, str]:
    result: dict[str, str] = {}
    raw = wiki_root / "raw"
    if not raw.exists():
        return result
    for p in raw.rglob("*"):
        if p.is_file() and not p.name.startswith("."):
            rel = str(p.relative_to(wiki_root))
            result[rel] = _hash_file(p)
    return result


def _load_json(path: Path) -> dict:
    if not path.exists():
        return {}
    with path.open("r") as f:
        return json.load(f)


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def cmd_build(wiki_root: Path) -> int:
    hashes = _scan_raw(wiki_root)
    existing = _load_json(wiki_root / ".manifest.json")
    now = _now_iso()
    out: dict[str, dict] = {}
    for rel, sha in hashes.items():
        prev = existing.get(rel, {}) if isinstance(existing.get(rel), dict) else {}
        entry = {
            "sha256": sha,
            "origin": prev.get("origin", ""),
            "copied_at": prev.get("copied_at", now),
            "last_ingested": now,
            "referenced_by": prev.get("referenced_by", []),
        }
        # Normalize missing/legacy origin.
        if not entry["origin"]:
            entry["origin"] = prev.get("source", "")  # legacy key
        out[rel] = entry
    _atomic_write_json(
        wiki_root / ".manifest.json",
        json.dumps(out, indent=2, sort_keys=True) + "\n",
    )
    return 0


def cmd_diff(wiki_root: Path) -> int:
    manifest = _load_json(wiki_root / ".manifest.json")
    live = _scan_raw(wiki_root)

    lines: list[str] = []
    for rel, sha in live.items():
        entry = manifest.get(rel)
        if not isinstance(entry, dict):
            lines.append(f"NEW: {rel}")
        elif entry.get("sha256") != sha:
            lines.append(f"MODIFIED: {rel}")
    for rel in manifest:
        if rel not in live:
            lines.append(f"DELETED: {rel}")

    if not lines:
        print("CLEAN")
    else:
        print("\n".join(lines))
    return 0


def cmd_migrate(wiki_root: Path) -> int:
    """One-time migration: consolidate two manifests into one, strip dead refs.

    Reads:
      <wiki_root>/.manifest.json          (legacy outer, schema {copied_at, origin})
      <wiki_root>/raw/.manifest.json      (legacy inner, schema {source, added, referenced_by})

    Writes:
      <wiki_root>/.manifest.json          unified schema

    Removes:
      <wiki_root>/raw/.manifest.json      (deleted after successful merge)
    """
    outer = _load_json(wiki_root / ".manifest.json")
    inner_path = wiki_root / "raw" / ".manifest.json"
    inner = _load_json(inner_path)

    # Normalize outer -- keys are already wiki-root-relative (raw/...)
    merged: dict[str, dict] = {}
    for rel, e in outer.items():
        if not isinstance(e, dict):
            continue
        merged[rel] = {
            "sha256": e.get("sha256", ""),
            "origin": e.get("origin", e.get("source", "")),
            "copied_at": e.get("copied_at", e.get("added", "")),
            "last_ingested": e.get("last_ingested", e.get("copied_at", e.get("added", ""))),
            "referenced_by": list(e.get("referenced_by", []) or []),
        }

    # Merge inner -- keys in the inner are relative to raw/ (no "raw/" prefix).
    for inner_rel, e in inner.items():
        if not isinstance(e, dict):
            continue
        rel = f"raw/{inner_rel}" if not inner_rel.startswith("raw/") else inner_rel
        entry = merged.setdefault(rel, {
            "sha256": "",
            "origin": "",
            "copied_at": "",
            "last_ingested": "",
            "referenced_by": [],
        })
        if not entry.get("origin"):
            entry["origin"] = e.get("source", e.get("origin", ""))
        if not entry.get("copied_at"):
            entry["copied_at"] = e.get("added", e.get("copied_at", ""))
        if not entry.get("last_ingested"):
            entry["last_ingested"] = e.get("last_ingested", entry["copied_at"])
        # Union referenced_by
        inner_refs = list(e.get("referenced_by", []) or [])
        refs = entry["referenced_by"]
        for r in inner_refs:
            if r not in refs:
                refs.append(r)

    # Recompute sha256 against live files; populate where missing.
    live = _scan_raw(wiki_root)
    now = _now_iso()
    for rel, sha in live.items():
        entry = merged.setdefault(rel, {
            "sha256": "",
            "origin": "",
            "copied_at": now,
            "last_ingested": now,
            "referenced_by": [],
        })
        entry["sha256"] = sha
        if not entry.get("copied_at"):
            entry["copied_at"] = now
        if not entry.get("last_ingested"):
            entry["last_ingested"] = now

    # Strip dead references: only keep referenced_by entries whose target
    # file is verifiably absent (i.e. the parent directory exists but the
    # file does not). If the parent directory does not exist we cannot
    # confirm absence — keep the reference so migration is conservative.
    for rel, entry in merged.items():
        alive = []
        for ref in entry.get("referenced_by", []):
            ref_path = wiki_root / ref
            if ref_path.exists():
                alive.append(ref)
            elif not ref_path.parent.exists():
                # Can't verify — keep the reference.
                alive.append(ref)
            # else: parent dir exists, file does not -> dead ref, drop it.
        entry["referenced_by"] = alive

    # Write unified.
    _atomic_write_json(
        wiki_root / ".manifest.json",
        json.dumps(merged, indent=2, sort_keys=True) + "\n",
    )

    # Delete legacy inner (if it existed).
    if inner_path.exists():
        inner_path.unlink()

    return 0


def cmd_validate(wiki_root: Path) -> int:
    """Verify every manifest entry has a non-empty `origin` matching either
    the literal "conversation" or an absolute filesystem path. Empty,
    evidence-type-as-origin ("file"/"mixed"/"conversation" used wrongly),
    and relative-path origins are violations.
    """
    manifest_path = wiki_root / ".manifest.json"
    if not manifest_path.is_file():
        print(f"no manifest at {manifest_path}", file=sys.stderr)
        return 1
    manifest = _load_json(manifest_path)
    bad: list[str] = []
    for k, v in manifest.items():
        if not isinstance(v, dict):
            bad.append(f"{k}: entry is not an object")
            continue
        o = v.get("origin", "")
        if not isinstance(o, str):
            bad.append(f"{k}: origin must be a string, got {type(o).__name__}")
            continue
        if o == "":
            bad.append(f"{k}: empty origin")
        elif o in ("file", "mixed"):
            bad.append(f"{k}: origin is literal evidence_type {o!r}")
        elif o != "conversation" and not o.startswith("/"):
            bad.append(
                f"{k}: origin must be 'conversation' or an absolute path, "
                f"got {o!r}"
            )
    for line in bad:
        print(line, file=sys.stderr)
    return 0 if not bad else 1


def main() -> int:
    if sys.version_info < (3, 11):
        print("python 3.11+ required", file=sys.stderr)
        return 1

    if len(sys.argv) != 3:
        print("usage: wiki-manifest.py {build|diff|migrate|validate} <wiki_root>",
              file=sys.stderr)
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
    if cmd == "migrate":
        return cmd_migrate(wiki_root)
    if cmd == "validate":
        return cmd_validate(wiki_root)
    print(f"unknown command: {cmd}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
