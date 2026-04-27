#!/usr/bin/env python3
"""Recursive _index.md builder for the karpathy-wiki.

Usage:
    wiki-build-index.py --wiki-root <root> --rebuild-all
    wiki-build-index.py --wiki-root <root> <directory>   # rebuild one subtree

Each directory under a top-level category gets an _index.md with:

  # <Directory Name>

  ## Pages (in this directory)
  - [Title](page.md) — (q: 4.00) full description from frontmatter
  - ...

  ## Subdirectories
  - [child/](child/_index.md) — N pages
    - Title1, Title2

The root index.md is a small MOC pointing at top-level <category>/_index.md files.

Locks: each _index.md write is guarded by its own lock acquired immediately
before the write and released immediately after. Lock-slug scheme matches
wiki-lock.sh's tr '/' '-' | tr '.' '-' so the in-Python lock and the bash
locking library share the same lockfile namespace and cannot collide.
Per-corrigendum C-J: stale-lock reclaim is intentionally NOT implemented;
v2.4 will add a CLI shim on wiki-lock.sh to unify this.

Imports from wiki_yaml for shared parsing primitives.

Exit codes:
    0 - success
    1 - argument or filesystem error
"""
import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from wiki_yaml import extract_frontmatter, parse_yaml

LOCK_TIMEOUT_S = 30
LOCK_POLL_S = 1


def _discover(wiki_root: Path) -> dict:
    script = Path(__file__).parent / "wiki-discover.py"
    result = subprocess.run(
        ["python3", str(script), "--wiki-root", str(wiki_root)],
        capture_output=True, text=True
    )
    if result.returncode != 0:
        raise RuntimeError(f"wiki-discover.py failed: {result.stderr.strip()}")
    return json.loads(result.stdout)


def _read_frontmatter(page: Path) -> dict:
    text = page.read_text()
    fm = extract_frontmatter(text)
    if fm is None:
        return {}
    try:
        return parse_yaml(fm)
    except ValueError:
        return {}


def _quality(fm: dict) -> str:
    q = fm.get("quality", {})
    if not isinstance(q, dict):
        return ""
    overall = q.get("overall")
    if overall is None:
        return ""
    # Corrigendum C-D: parse_yaml returns float 4.0 for "4.00"; format to 2 decimals.
    try:
        return f"(q: {float(overall):.2f}) "
    except (TypeError, ValueError):
        return f"(q: {overall}) "


def _description(fm: dict, page: Path) -> str:
    """Return the first non-empty paragraph of the body, truncated to 200 chars."""
    text = page.read_text()
    end = text.find("\n---\n", 4)
    if end < 0:
        return ""
    body = text[end + 5:].strip()
    para = body.split("\n\n", 1)[0].replace("\n", " ").strip()
    if len(para) > 200:
        para = para[:200] + "..."
    return para


def _acquire_lock(wiki_root: Path, rel_path: str) -> Path:
    """Atomic lock create matching wiki-lock.sh's slug scheme.

    rel_path is the wiki-relative page path (e.g. 'concepts/_index.md').
    Slug is rel_path with '/' and '.' both replaced by '-' (mirroring
    wiki-lock.sh:14-15). This ensures the lock-namespace is shared with
    the bash locking library.
    """
    slug = rel_path.replace("/", "-").replace(".", "-") + ".lock"
    lockdir = wiki_root / ".locks"
    lockdir.mkdir(exist_ok=True)
    lockfile = lockdir / slug
    deadline = time.time() + LOCK_TIMEOUT_S
    while time.time() < deadline:
        try:
            with lockfile.open("x") as fd:
                fd.write(f"build-index:{rel_path}:{time.time()}\n")
            return lockfile
        except FileExistsError:
            time.sleep(LOCK_POLL_S)
    raise TimeoutError(f"lock timeout: {rel_path}")


def _release_lock(lockfile: Path) -> None:
    lockfile.unlink(missing_ok=True)


def _build_directory_index(directory: Path, wiki_root: Path, reserved: set[str]) -> None:
    """Write _index.md for one directory."""
    if directory.resolve() == wiki_root.resolve():
        # Wiki root is owned by _build_root_moc; never write _index.md here.
        return
    lines = []
    name = directory.name if directory != wiki_root else "Wiki Root"
    lines.append(f"# {name}")
    lines.append("")

    # Pages section
    pages = sorted([
        p for p in directory.iterdir()
        if p.is_file() and p.name.endswith(".md") and p.name != "_index.md"
    ])
    lines.append("## Pages (in this directory)")
    if not pages:
        lines.append("(none)")
    else:
        for p in pages:
            fm = _read_frontmatter(p)
            title = fm.get("title", p.stem)
            qual = _quality(fm)
            desc = _description(fm, p)
            entry = f"- [{title}]({p.name}) — {qual}{desc}".rstrip(" —")
            lines.append(entry)
    lines.append("")

    # Subdirectories section — exclude reserved names per discovery
    subdirs = sorted([
        d for d in directory.iterdir()
        if d.is_dir() and not d.name.startswith(".") and d.name not in reserved
    ])
    lines.append("## Subdirectories")
    if not subdirs:
        lines.append("(none)")
    else:
        for d in subdirs:
            child_pages = [
                p for p in d.rglob("*.md")
                if p.name != "_index.md"
                and not any(
                    part in reserved or part.startswith(".")
                    for part in p.relative_to(d).parts[:-1]
                )
            ]
            count = len(child_pages)
            titles_brief = []
            for p in sorted(child_pages)[:5]:
                fm = _read_frontmatter(p)
                titles_brief.append(fm.get("title", p.stem))
            lines.append(f"- [{d.name}/]({d.name}/_index.md) — {count} pages")
            if titles_brief:
                lines.append(f"  - {', '.join(titles_brief)}")
    lines.append("")

    rel = str(directory.relative_to(wiki_root)) if directory != wiki_root else ""
    target = directory / "_index.md"
    lock_key = (rel + "/_index.md").lstrip("/") if rel else "_index.md"
    lock = _acquire_lock(wiki_root, lock_key)
    try:
        target.write_text("\n".join(lines) + "\n")
    finally:
        _release_lock(lock)


def _build_root_moc(wiki_root: Path, disc: dict) -> None:
    """Write the small root index.md MOC."""
    lines = ["# Wiki Index", ""]
    for cat in disc["categories"]:
        c = disc["counts"].get(cat, 0)
        d = disc["depths"].get(cat, 1)
        depth_note = f", {d} levels deep" if d > 1 else ""
        # Title-case for human-readability; handles hyphens/underscores.
        display = cat.replace("-", " ").replace("_", " ").title()
        lines.append(f"- [{display}]({cat}/_index.md) — {c} pages{depth_note}")
    target = wiki_root / "index.md"
    lock = _acquire_lock(wiki_root, "index.md")
    try:
        target.write_text("\n".join(lines) + "\n")
    finally:
        _release_lock(lock)


def rebuild_all(wiki_root: Path) -> None:
    disc = _discover(wiki_root)
    reserved = set(disc["reserved"])
    # Walk every directory under each category, in path-order, building leaves first.
    all_dirs: list[Path] = []
    for cat in disc["categories"]:
        cat_root = wiki_root / cat
        if not cat_root.is_dir():
            continue
        for d in cat_root.rglob("*"):
            if d.is_dir() and not d.name.startswith(".") and d.name not in reserved:
                all_dirs.append(d)
        all_dirs.append(cat_root)
    # Sort by depth descending (leaves first), then by path.
    all_dirs.sort(key=lambda d: (-len(d.parts), str(d)))
    for d in all_dirs:
        _build_directory_index(d, wiki_root, reserved)
    _build_root_moc(wiki_root, disc)


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    p.add_argument("--wiki-root", required=True)
    p.add_argument("--rebuild-all", action="store_true")
    p.add_argument("directory", nargs="?")
    args = p.parse_args()
    root = Path(args.wiki_root).resolve()
    if not root.is_dir():
        print(f"not a directory: {root}", file=sys.stderr)
        return 1
    try:
        if args.rebuild_all:
            rebuild_all(root)
        elif args.directory:
            d = Path(args.directory).resolve()
            disc = _discover(root)
            reserved = set(disc["reserved"])
            _build_directory_index(d, root, reserved)
            _build_root_moc(root, disc)
        else:
            print("usage: wiki-build-index.py --wiki-root <root> (--rebuild-all | <dir>)", file=sys.stderr)
            return 1
    except (RuntimeError, TimeoutError) as e:
        print(str(e), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
