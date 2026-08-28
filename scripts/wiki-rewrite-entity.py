#!/usr/bin/env python3
"""Rewrite a catalog entity into an entity map and move claim sources.

Usage:
    wiki-rewrite-entity.py --wiki-root <wiki> --job-file <job.md>
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from wiki_yaml import extract_frontmatter, parse_yaml, split_frontmatter


def _job(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    raw = extract_frontmatter(text) or text
    parsed = parse_yaml(raw)
    if not isinstance(parsed, dict):
        raise ValueError("rewrite job is not a mapping")
    return parsed


def _wiki_rel(wiki: Path, rel: str) -> Path:
    return (wiki / rel.lstrip("/")).resolve()


def _load_page(path: Path) -> tuple[str, str, dict, str]:
    text = path.read_text(encoding="utf-8")
    opener, block, after = split_frontmatter(text)
    if opener is None or block is None or after is None:
        raise ValueError(f"page has no frontmatter: {path}")
    parsed = parse_yaml(block)
    if not isinstance(parsed, dict):
        raise ValueError(f"page frontmatter is not a mapping: {path}")
    return opener, block, parsed, after


def _sources(parsed: dict) -> list[str]:
    raw = parsed.get("sources") or []
    if not isinstance(raw, list):
        return []
    out: list[str] = []
    for item in raw:
        value = str(item).strip()
        if value:
            out.append(value)
    return out


def _set_list_field(path: Path, key: str, items: list[str]) -> None:
    opener, block, _parsed, after = _load_page(path)
    lines: list[str] = []
    skipped = False
    for line in block.splitlines(keepends=True):
        if line.startswith(f"{key}:"):
            skipped = True
            continue
        if skipped and (line.startswith("  - ") or line.startswith("    - ")):
            continue
        skipped = False
        lines.append(line)
    if items:
        rendered = f"{key}:\n" + "".join(f"  - {item}\n" for item in items)
    else:
        rendered = f"{key}: []\n"
    new_block = "".join(lines)
    needle = f"\n{key}:"
    if needle in f"\n{new_block}":
        new_block = "".join(lines)
    if "\ncreated:" in new_block:
        new_block = new_block.replace("\ncreated:", "\n" + rendered + "created:", 1)
    else:
        new_block = new_block.rstrip() + "\n" + rendered
    path.write_text(opener + new_block + "\n" + after)


def _set_body(path: Path, body: str) -> None:
    opener, block, _parsed, _after = _load_page(path)
    if not body.endswith("\n"):
        body += "\n"
    path.write_text(opener + block + "\n---\n\n" + body)


def rewrite_entity(wiki: Path, job_file: Path) -> str:
    job = _job(job_file)
    kind = str(job.get("kind") or "").strip().lower()
    token = str(job.get("object") or job_file.stem).strip()
    pages = job.get("pages") or []
    if not isinstance(pages, list) or not pages:
        raise ValueError("entity rewrite job has no pages")
    entity_rel = None
    playbook_rels: list[str] = []
    for rel in pages:
        clean = str(rel).lstrip("/")
        if clean.startswith("entities/") or Path(clean).stem == token:
            if entity_rel is None:
                entity_rel = clean
                continue
        playbook_rels.append(clean)
    if entity_rel is None:
        candidate = f"entities/{token}.md"
        if (wiki / candidate).is_file():
            entity_rel = candidate
    if entity_rel is None:
        raise ValueError("entity rewrite job has no entity page")
    if kind == "cluster":
        raise ValueError("rewrite job is a cluster compact, not an entity map")
    entity_path = _wiki_rel(wiki, entity_rel)
    if not entity_path.is_file():
        raise ValueError(f"entity page missing: {entity_rel}")

    _opener, _block, entity_parsed, _after = _load_page(entity_path)
    entity_sources = _sources(entity_parsed)
    playbook_paths: list[tuple[str, Path, list[str]]] = []
    claimed: set[str] = set()
    for rel in playbook_rels:
        path = _wiki_rel(wiki, rel)
        if not path.is_file():
            continue
        _o, _b, parsed, _a = _load_page(path)
        srcs = _sources(parsed)
        playbook_paths.append((rel, path, srcs))
        claimed.update(srcs)

    identity: list[str] = []
    seen_identity: set[str] = set()
    for src in entity_sources:
        if src in claimed:
            continue
        if src in seen_identity:
            continue
        seen_identity.add(src)
        identity.append(src)

    for rel, path, srcs in playbook_paths:
        merged: list[str] = []
        seen: set[str] = set()
        for src in srcs:
            if src in seen:
                continue
            seen.add(src)
            merged.append(src)
        _set_list_field(path, "sources", merged)

    _set_list_field(entity_path, "sources", identity)
    related = ["/" + rel.lstrip("/") for rel, _path, _srcs in playbook_paths]
    _set_list_field(entity_path, "related", related)

    title = str(entity_parsed.get("title") or token)
    bullets = []
    for rel, path, _srcs in playbook_paths:
        _o, _b, parsed, _a = _load_page(path)
        label = str(parsed.get("title") or Path(rel).stem)
        bullets.append(f"- [{label}](/{rel.lstrip('/')})")
    if bullets:
        playbook_section = "## Playbooks\n\n" + "\n".join(bullets) + "\n"
    else:
        playbook_section = "## Playbooks\n\n(none named in this job)\n"
    body = (
        f"{title} is an entity map: who or what, main frameworks, and "
        "pointers to playbooks. Identity sources stay here. Claim sources "
        "live on the playbooks.\n\n"
        f"{playbook_section}"
    )
    _set_body(entity_path, body)
    return token


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Rewrite a catalog entity into a map.")
    parser.add_argument("--wiki-root", required=True)
    parser.add_argument("--job-file", required=True)
    args = parser.parse_args(argv)
    wiki = Path(args.wiki_root)
    job = Path(args.job_file)
    if not wiki.is_dir() or not job.is_file():
        print("wiki-rewrite-entity: wiki or job missing", file=sys.stderr)
        return 2
    try:
        token = rewrite_entity(wiki, job)
    except (ValueError, OSError) as exc:
        print(f"wiki-rewrite-entity: {exc}", file=sys.stderr)
        return 1
    print(token)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
