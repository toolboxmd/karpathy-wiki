#!/usr/bin/env python3
"""Compact sibling pages onto a playbook and leave pointer stubs.

Usage:
    wiki-compact-cluster.py --wiki-root <wiki> --job-file <job.md>
    wiki-compact-cluster.py --wiki-root <wiki> --next-job
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from wiki_yaml import extract_frontmatter, parse_yaml, split_frontmatter

POINTER_BODY = "This file is a pointer. The knowledge object lives at {link}.\n"


def _job(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    raw = extract_frontmatter(text) or text
    parsed = parse_yaml(raw)
    if not isinstance(parsed, dict):
        raise ValueError("rewrite job is not a mapping")
    return parsed


def _wiki_rel(wiki: Path, rel: str) -> Path:
    clean = rel.lstrip("/")
    return (wiki / clean).resolve()


def is_cluster_job(job: dict, wiki: Path) -> bool:
    kind = str(job.get("kind") or "").strip().lower()
    if kind == "entity":
        return False
    if kind == "cluster":
        return True
    pages = job.get("pages") or []
    if isinstance(pages, list):
        for rel in pages:
            if str(rel).lstrip("/").startswith("entities/"):
                return False
    token = str(job.get("object") or "").strip()
    if token and (wiki / "entities" / f"{token}.md").is_file():
        return False
    return True


def next_cluster_job(wiki: Path) -> Path | None:
    folder = wiki / ".wiki-pending" / "rewrite-jobs"
    if not folder.is_dir():
        return None
    for path in sorted(p for p in folder.glob("*.md") if p.is_file()):
        try:
            job = _job(path)
        except (ValueError, OSError):
            continue
        if is_cluster_job(job, wiki):
            return path
    return None


def _page_body(path: Path) -> str:
    text = path.read_text(encoding="utf-8")
    _opener, _block, after = split_frontmatter(text)
    if after is None:
        return ""
    parts = after.split("\n", 1)
    return parts[1] if len(parts) > 1 else ""


def _rewrite_pointer(path: Path, playbook_rel: str, object_token: str) -> None:
    title = f"Pointer: merged {object_token} unit"
    fm = (
        "---\n"
        f'title: "{title}"\n'
        "type: concepts\n"
        "tags: [pointer]\n"
        'summary: "Pointer. Content for this unit is on the merged playbook page."\n'
        "sources:\n"
        "  - conversation\n"
        "related:\n"
        f"  - /{playbook_rel.lstrip('/')}\n"
        'created: "2026-08-28T00:00:00Z"\n'
        'updated: "2026-08-28T00:00:00Z"\n'
        "evidence_class: ingest_operations\n"
        "quality:\n"
        "  accuracy: 5\n"
        "  completeness: 2\n"
        "  signal: 3\n"
        "  interlinking: 4\n"
        "  overall: 3.50\n"
        '  rated_at: "2026-08-28T00:00:00Z"\n'
        "  rated_by: ingester\n"
        "---\n\n"
    )
    link = f"[playbook](/{playbook_rel.lstrip('/')})"
    path.write_text(fm + POINTER_BODY.format(link=link))


def _add_related(playbook: Path, pointer_rels: list[str]) -> None:
    text = playbook.read_text(encoding="utf-8")
    opener, block, after = split_frontmatter(text)
    if opener is None or block is None or after is None:
        return
    parsed = parse_yaml(block)
    related = parsed.get("related") if isinstance(parsed, dict) else None
    items = [str(x) for x in related] if isinstance(related, list) else []
    for rel in pointer_rels:
        item = "/" + rel.lstrip("/")
        if item not in items:
            items.append(item)
    lines = []
    skipped = False
    for line in block.splitlines(keepends=True):
        if line.startswith("related:"):
            skipped = True
            continue
        if skipped and (line.startswith("  - ") or line.startswith("    - ")):
            continue
        skipped = False
        lines.append(line)
    rendered = "related:\n" + "".join(f"  - {item}\n" for item in items)
    new_block = "".join(lines)
    if "\ncreated:" in new_block:
        new_block = new_block.replace("\ncreated:", "\n" + rendered + "created:", 1)
    else:
        new_block = new_block.rstrip() + "\n" + rendered
    playbook.write_text(opener + new_block + "\n" + after)


def _append_folded_bodies(
    playbook: Path, pointers: list[tuple[str, Path]]
) -> None:
    extra: list[str] = []
    for rel, path in pointers:
        body = _page_body(path).strip()
        if body:
            extra.append(f"## Folded from {rel}\n\n{body}")
    if not extra:
        return
    text = playbook.read_text(encoding="utf-8")
    if not text.endswith("\n"):
        text += "\n"
    playbook.write_text(text + "\n" + "\n\n".join(extra) + "\n")


def compact(wiki: Path, job_file: Path) -> str:
    job = _job(job_file)
    if not is_cluster_job(job, wiki):
        raise ValueError("rewrite job is an entity map, not a cluster compact")
    token = str(job.get("object") or job_file.stem).strip()
    pages = job.get("pages") or []
    if not isinstance(pages, list) or not pages:
        raise ValueError("rewrite job has no pages")
    existing: list[tuple[str, Path]] = []
    for rel in pages:
        path = _wiki_rel(wiki, str(rel))
        if path.is_file():
            existing.append((str(rel).lstrip("/"), path))
    if not existing:
        raise ValueError("rewrite job pages are missing")
    playbook_rel, playbook = existing[0]
    pointers = existing[1:]
    pointer_rels = [rel for rel, _path in pointers]
    _append_folded_bodies(playbook, pointers)
    for _rel, path in pointers:
        _rewrite_pointer(path, playbook_rel, token)
    if pointer_rels:
        _add_related(playbook, pointer_rels)
    rebuild = Path(__file__).parent / "wiki-build-index.py"
    subprocess.run(
        [sys.executable, str(rebuild), "--wiki-root", str(wiki), "--rebuild-all"],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    return token


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Compact a rewrite-job cluster.")
    parser.add_argument("--wiki-root", required=True)
    parser.add_argument("--job-file")
    parser.add_argument("--next-job", action="store_true")
    args = parser.parse_args(argv)
    wiki = Path(args.wiki_root)
    if not wiki.is_dir():
        print("wiki-compact-cluster: wiki missing", file=sys.stderr)
        return 2
    if args.next_job:
        nxt = next_cluster_job(wiki)
        if nxt is not None:
            print(nxt)
        return 0
    if not args.job_file:
        print("wiki-compact-cluster: --job-file is required", file=sys.stderr)
        return 2
    job = Path(args.job_file)
    if not job.is_file():
        print("wiki-compact-cluster: wiki or job missing", file=sys.stderr)
        return 2
    try:
        token = compact(wiki, job)
    except (ValueError, OSError) as exc:
        print(f"wiki-compact-cluster: {exc}", file=sys.stderr)
        return 1
    print(token)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
