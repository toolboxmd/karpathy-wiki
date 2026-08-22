#!/usr/bin/env python3
"""Run the semantic-ingest benchmark against the current wiki ingester.

Default mode is fixture validation only. Real provider execution is opt-in via
`--run-provider` because it starts detached model workers and may consume paid
quota.
"""

from __future__ import annotations

import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import time
from typing import Any


BENCH_ROOT = Path(__file__).resolve().parent
REPO_ROOT = BENCH_ROOT.parents[2]
SCRIPTS = REPO_ROOT / "scripts"
sys.path.insert(0, str(SCRIPTS))

from wiki_yaml import extract_frontmatter, parse_yaml  # noqa: E402


CONTENT_CATEGORIES = ("concepts", "entities", "queries", "ideas", "projects")
NON_CANONICAL_CATEGORIES = ("source-notes", "schema-proposals")
ALLOWED_TOP_LEVEL_CATEGORIES = set(CONTENT_CATEGORIES) | set(NON_CANONICAL_CATEGORIES)
RESERVED_TOP_LEVEL = {
    "raw",
    "inbox",
    "archive",
    "index",
    "README.md",
    "log.md",
    "schema.md",
}
EXPECTED_RAW_SOURCE = "raw/source.md"
EXPECTED_KINDS = {"entity", "concept", "query", "idea", "project", "hold"}
EXPECTED_PRESENCE = {"required", "optional", "forbidden"}
EXPECTED_REALIZATIONS = {
    "page_or_update",
    "page",
    "update",
    "section",
    "hold",
    "drop",
    "must_not_page",
}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def load_yaml(path: Path) -> Any:
    """Load YAML using PyYAML when available, otherwise Ruby stdlib YAML."""

    try:
        import yaml  # type: ignore

        with path.open("r", encoding="utf-8") as handle:
            return yaml.safe_load(handle)
    except ImportError:
        pass

    result = subprocess.run(
        [
            "ruby",
            "-ryaml",
            "-rjson",
            "-e",
            "puts JSON.generate(YAML.load_file(ARGV[0]))",
            str(path),
        ],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    if result.returncode != 0:
        raise RuntimeError(f"cannot parse YAML {path}: {result.stderr.strip()}")
    return json.loads(result.stdout)


def strip_frontmatter(text: str) -> str:
    if not text.startswith("---\n"):
        return text
    marker = "\n---\n"
    end = text.find(marker, 4)
    if end == -1:
        return text
    return text[end + len(marker) :]


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


def prepare_isolated_plugin_root(output_root: Path) -> Path:
    """Create a minimal plugin root without benchmark gold/spec files."""

    isolated = output_root / "isolated-plugin-root"
    if isolated.exists():
        shutil.rmtree(isolated)
    isolated.mkdir(parents=True)
    for name in ("scripts", "skills", "bin"):
        shutil.copytree(REPO_ROOT / name, isolated / name)
    return isolated


def slugify(text: str) -> str:
    out = []
    last_dash = False
    for char in text.lower():
        if char.isalnum():
            out.append(char)
            last_dash = False
        elif not last_dash:
            out.append("-")
            last_dash = True
    return "".join(out).strip("-") or "capture"


def yaml_scalar(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def yaml_list(values: list[str], indent: str = "  ") -> str:
    if not values:
        return "[]"
    return "\n" + "\n".join(f"{indent}- {yaml_scalar(value)}" for value in values)


def token_set(text: str) -> set[str]:
    tokens = []
    current = []
    for char in text.lower():
        if char.isalnum():
            current.append(char)
        elif current:
            token = "".join(current)
            if len(token) >= 4:
                tokens.append(token)
            current = []
    if current:
        token = "".join(current)
        if len(token) >= 4:
            tokens.append(token)
    stop = {
        "that",
        "this",
        "with",
        "from",
        "into",
        "only",
        "must",
        "source",
        "current",
    }
    return {token for token in tokens if token not in stop}


NEGATION_MARKERS = (
    " not ",
    "n't",
    " no ",
    " neither ",
    " without ",
    " do not ",
    " does not ",
    " did not ",
    " cannot ",
    " never ",
    " not current ",
    " not implemented ",
    " not automatic ",
    " does not exist ",
    " unscheduled ",
    " unspecified ",
)


def line_has_negation(line: str) -> bool:
    normalized = f" {line.lower()} ".replace(" not merely ", " ")
    return any(marker in normalized for marker in NEGATION_MARKERS)


def claim_has_negation(claim: str) -> bool:
    return line_has_negation(claim)


def line_covers_claim(claim: str, line: str) -> bool:
    special_tokens = re.findall(r"--[A-Za-z0-9-]+|[0-9][0-9.:]*[0-9]", claim.lower())
    tokens = token_set(claim)
    if not tokens:
        return True
    line_lower = line.lower()
    haystack = token_set(line_lower)
    overlap = len(tokens & haystack)
    if special_tokens and not all(token in line_lower for token in special_tokens):
        return False
    if len(tokens) <= 3:
        return overlap >= max(1, len(tokens) - 1)
    required = max(3, math.ceil(len(tokens) * 0.70))
    return overlap >= required


def claim_covered(claim: str, text: str) -> bool:
    negated_claim = claim_has_negation(claim)
    for raw_line in text.splitlines():
        if raw_line.lstrip().startswith("#"):
            continue
        if not negated_claim and line_has_negation(raw_line):
            continue
        if line_covers_claim(claim, raw_line):
            return True
    return False


def claim_violated(claim: str, text: str) -> bool:
    """Return true when a forbidden claim is asserted, not merely rejected."""

    tokens = token_set(claim)
    if not tokens:
        return False
    negated_claim = claim_has_negation(claim)
    for raw_line in text.splitlines():
        if raw_line.lstrip().startswith("#"):
            continue
        if not line_covers_claim(claim, raw_line):
            continue
        if not negated_claim and line_has_negation(raw_line):
            continue
        return True
    return False


def fixture_dirs(fixtures_root: Path, selected: list[str]) -> list[Path]:
    dirs = [path for path in sorted(fixtures_root.iterdir()) if path.is_dir()]
    if selected:
        wanted = set(selected)
        dirs = [
            path
            for path in dirs
            if path.name in wanted or path.name.split("-", 1)[0] in wanted
        ]
    return dirs


def require_type(value: Any, expected_type: type, label: str) -> None:
    if not isinstance(value, expected_type):
        raise RuntimeError(f"{label}: expected {expected_type.__name__}")


def validate_expected_contract(path: Path, expected_data: dict[str, Any]) -> None:
    """Validate the fixture contract without requiring a jsonschema dependency."""

    allowed_top = {"case_id", "slug", "notes", "objects"}
    extra = set(expected_data) - allowed_top
    if extra:
        raise RuntimeError(f"{path.name}: unexpected expected.yaml keys: {sorted(extra)}")
    require_type(expected_data.get("case_id"), str, f"{path.name}: case_id")
    require_type(expected_data.get("slug"), str, f"{path.name}: slug")
    objects = expected_data.get("objects")
    require_type(objects, list, f"{path.name}: objects")
    if not objects:
        raise RuntimeError(f"{path.name}: expected objects missing")
    for index, obj in enumerate(objects):
        label = f"{path.name}: objects[{index}]"
        require_type(obj, dict, label)
        required = {"id", "kind", "presence", "category", "realization", "match", "claims"}
        missing = required - set(obj)
        if missing:
            raise RuntimeError(f"{label}: missing keys: {sorted(missing)}")
        allowed = required | {"reason"}
        extra_obj = set(obj) - allowed
        if extra_obj:
            raise RuntimeError(f"{label}: unexpected keys: {sorted(extra_obj)}")
        if obj.get("kind") not in EXPECTED_KINDS:
            raise RuntimeError(f"{label}: unknown kind {obj.get('kind')!r}")
        if obj.get("presence") not in EXPECTED_PRESENCE:
            raise RuntimeError(f"{label}: unknown presence {obj.get('presence')!r}")
        if obj.get("realization") not in EXPECTED_REALIZATIONS:
            raise RuntimeError(f"{label}: unknown realization {obj.get('realization')!r}")
        require_type(obj.get("category"), dict, f"{label}: category")
        require_type(obj.get("match"), dict, f"{label}: match")
        require_type(obj["match"].get("names"), list, f"{label}: match.names")
        if not obj["match"]["names"]:
            raise RuntimeError(f"{label}: match.names missing")
        require_type(obj.get("claims"), dict, f"{label}: claims")
        require_type(obj["claims"].get("must"), list, f"{label}: claims.must")
        require_type(obj["claims"].get("must_not"), list, f"{label}: claims.must_not")


def validate_fixture(path: Path) -> dict[str, Any]:
    source = path / "source.md"
    context = path / "context.yaml"
    expected = path / "expected.yaml"
    for required in (source, context, expected):
        if not required.is_file():
            raise RuntimeError(f"{path.name}: missing {required.name}")

    context_data = load_yaml(context)
    expected_data = load_yaml(expected)
    case_id = path.name.split("-", 1)[0]
    if str(context_data.get("case_id")) != case_id:
        raise RuntimeError(f"{path.name}: context case_id mismatch")
    if str(expected_data.get("case_id")) != case_id:
        raise RuntimeError(f"{path.name}: expected case_id mismatch")
    validate_expected_contract(path, expected_data)

    return {
        "case_id": case_id,
        "slug": expected_data.get("slug", path.name.split("-", 1)[1]),
        "path": str(path),
        "source_sha256": sha256_file(source),
        "expected_object_count": len(expected_data["objects"]),
        "expected_required_count": sum(
            1 for obj in expected_data["objects"] if obj.get("presence") == "required"
        ),
        "expected_forbidden_count": sum(
            1 for obj in expected_data["objects"] if obj.get("presence") == "forbidden"
        ),
    }


def copy_seed(fixture: Path, wiki: Path) -> None:
    seed = fixture / "wiki_seed"
    if not seed.exists():
        return
    for source in seed.rglob("*"):
        if not source.is_file():
            continue
        relative = source.relative_to(seed)
        target = wiki / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)


def init_wiki(wiki: Path, workspace: Path, env: dict[str, str], args: argparse.Namespace) -> None:
    wiki = wiki.resolve()
    subprocess.run(
        ["bash", str(SCRIPTS / "wiki-init.sh"), "project", str(wiki)],
        env=env,
        check=True,
        stdout=subprocess.DEVNULL,
    )
    # wiki-init creates a standalone git repository inside the wiki root.
    # The runtime trust validator therefore treats the wiki root itself as the
    # canonical workspace for these disposable benchmark wikis.
    workspace = wiki.resolve()
    subprocess.run(
        [
            sys.executable,
            str(SCRIPTS / "wiki_config.py"),
            "route-set",
            "--workspace",
            str(workspace),
            "--mode",
            "project",
            "--project-wiki",
            str(wiki),
        ],
        env=env,
        check=True,
        stdout=subprocess.DEVNULL,
    )
    subprocess.run(
        [
            sys.executable,
            str(SCRIPTS / "wiki_config.py"),
            "init-local",
            "--wiki",
            str(wiki),
            "--trust-workspace",
            str(workspace),
            "--default-provider",
            args.provider,
            "--default-model",
            args.model,
            "--default-effort",
            args.effort,
            "--default-executable",
            args.executable,
            "--dispatch-mode",
            "scheduled",
            "--max-processes",
            "1",
            "--max-attempts",
            "1",
            "--heartbeat-seconds",
            str(args.heartbeat_seconds),
            "--stale-after-seconds",
            str(args.timeout_seconds),
            "--usage-monitor",
            "off",
            "--rate-limit-retry-seconds",
            "30",
            "--no-auto-commit",
        ],
        env=env,
        check=True,
        stdout=subprocess.DEVNULL,
    )


def write_capture(fixture: Path, wiki: Path) -> str:
    context = load_yaml(fixture / "context.yaml")
    case_id = fixture.name.split("-", 1)[0]
    source_copy = wiki / "inbox" / case_id / "source.md"
    source_copy.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(fixture / "source.md", source_copy)

    title = context.get("title") or fixture.name
    capture_name = f"baseline-{case_id}.md"
    capture = wiki / ".wiki-pending" / capture_name
    suggested_pages = context.get("suggested_pages") or []
    body = "\n".join(
        [
            "---",
            f"title: {yaml_scalar(str(title))}",
            f"evidence: {yaml_scalar(str(source_copy))}",
            'evidence_type: "file"',
            'capture_kind: "raw-direct"',
            f"suggested_action: {yaml_scalar(str(context.get('suggested_action', 'auto')))}",
            f"suggested_pages: {yaml_list([str(item) for item in suggested_pages])}",
            f"captured_at: {yaml_scalar(utc_now())}",
            'captured_by: "semantic-ingest-benchmark"',
            f"capture_id: {yaml_scalar('cap-' + hashlib.sha1(case_id.encode()).hexdigest())}",
            'promotion_policy: "none"',
            "promotion_decision: null",
            "promotion_id: null",
            "propagated_from: null",
            "---",
            "",
            "Benchmark raw-direct capture. Read the evidence path above and",
            "ingest the source into the appropriate wiki knowledge objects.",
            "",
        ]
    )
    capture.write_text(body, encoding="utf-8")
    return capture_name


def read_events(wiki: Path) -> list[dict[str, Any]]:
    path = wiki / ".ingest-runs.jsonl"
    if not path.exists():
        return []
    events = []
    for line in path.read_text(encoding="utf-8").splitlines():
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return events


def wait_for_capture(wiki: Path, capture_name: str, timeout: int) -> str:
    deadline = time.monotonic() + timeout
    terminal = {
        "completed",
        "failed",
        "configuration_or_auth_failure",
        "provider_rate_limited",
        "needs_more_detail",
    }
    while time.monotonic() < deadline:
        events = [
            event
            for event in read_events(wiki)
            if event.get("capture") == capture_name
        ]
        for event in reversed(events):
            status = event.get("status")
            if status in terminal:
                return str(status)
        time.sleep(1)
    return "timeout"


def collect_pages(wiki: Path) -> list[dict[str, Any]]:
    pages = []
    for root in sorted(wiki.iterdir()):
        if not root.is_dir():
            continue
        category = root.name
        if category.startswith(".") or category in RESERVED_TOP_LEVEL:
            continue
        for path in root.rglob("*.md"):
            if path.name == "_index.md":
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            fm_raw = extract_frontmatter(text)
            fm_error = None
            try:
                fm = parse_yaml(fm_raw) if fm_raw is not None else {}
                if not isinstance(fm, dict):
                    fm_error = "frontmatter is not a mapping"
                    fm = {}
            except Exception as exc:  # validator also reports the exact parse issue.
                fm_error = str(exc)
                fm = {}
            rel = str(path.relative_to(wiki))
            pages.append(
                {
                    "path": rel,
                    "category": rel.split("/", 1)[0],
                    "title": str(fm.get("title") or path.stem),
                    "type": fm.get("type"),
                    "frontmatter": fm,
                    "frontmatter_error": fm_error,
                    "text": text,
                }
            )
    return pages


def seed_page_texts(fixture: Path) -> dict[str, str]:
    seed = fixture / "wiki_seed"
    if not seed.exists():
        return {}
    texts = {}
    for path in seed.rglob("*.md"):
        if path.name == "_index.md":
            continue
        texts[str(path.relative_to(seed))] = path.read_text(
            encoding="utf-8", errors="replace"
        )
    return texts


def touched_page_paths(fixture: Path, pages: list[dict[str, Any]]) -> set[str]:
    seed = seed_page_texts(fixture)
    touched = set()
    for page in pages:
        previous = seed.get(page["path"])
        if previous is None or previous != page["text"]:
            touched.add(page["path"])
    return touched


def match_page(obj: dict[str, Any], pages: list[dict[str, Any]]) -> tuple[dict[str, Any] | None, str]:
    names = [str(item).lower() for item in obj.get("match", {}).get("names", [])]
    identifiers = [
        str(item).lower() for item in obj.get("match", {}).get("identifiers", [])
    ]
    required_category = obj.get("category", {}).get("required")
    allowed = set(obj.get("category", {}).get("allowed") or [])
    forbidden = set(obj.get("category", {}).get("forbidden") or [])
    presence = obj.get("presence")

    best: dict[str, Any] | None = None
    best_score = 0
    best_title_score = 0
    best_rank = -1
    best_status = "miss"
    for page in pages:
        title_hay = f"{page['path']} {page['title']}".lower()
        if presence == "forbidden":
            hay = title_hay
        else:
            hay = f"{title_hay} {page['text']}".lower()
        title_score = 0
        title_score += sum(20 for name in names if name and name in title_hay)
        title_score += sum(15 for ident in identifiers if ident and ident in title_hay)
        score = 0
        score += sum(3 for name in names if name and name in hay)
        score += sum(2 for ident in identifiers if ident and ident in hay)
        if score <= 0:
            continue
        category = page["category"]
        if category in forbidden:
            status = "absorbed"
            rank = 0
        elif required_category and category != required_category:
            status = "kind_confusion"
            rank = 1
        elif allowed and category not in allowed:
            status = "kind_confusion"
            rank = 1
        else:
            status = "matched"
            rank = 2
        if (rank, title_score, score) <= (best_rank, best_title_score, best_score):
            continue
        best = page
        best_score = score
        best_title_score = title_score
        best_rank = rank
        best_status = status
    return best, best_status


def expected_has_required_hold(expected: dict[str, Any]) -> bool:
    return any(
        obj.get("kind") == "hold" and obj.get("presence") == "required"
        for obj in expected.get("objects", [])
    )


def read_manifest(wiki: Path) -> dict[str, Any]:
    path = wiki / ".manifest.json"
    if not path.is_file():
        return {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}


def source_list(page: dict[str, Any]) -> list[str]:
    raw = page.get("frontmatter", {}).get("sources")
    if not isinstance(raw, list):
        return []
    return [str(item) for item in raw if isinstance(item, str) and str(item).strip()]


def manifest_referenced_pages(manifest: dict[str, Any]) -> set[str]:
    referenced: set[str] = set()
    for entry in manifest.values():
        if not isinstance(entry, dict):
            continue
        refs = entry.get("referenced_by")
        if isinstance(refs, list):
            referenced.update(str(item) for item in refs if isinstance(item, str))
    return referenced


def fixture_categories(fixture: Path, expected: dict[str, Any]) -> set[str]:
    categories: set[str] = set()
    for obj in expected.get("objects", []):
        category = obj.get("category") or {}
        if isinstance(category.get("required"), str):
            categories.add(category["required"])
        for key in ("allowed", "forbidden"):
            if isinstance(category.get(key), list):
                categories.update(str(item) for item in category[key])
    for path in seed_page_texts(fixture):
        categories.add(path.split("/", 1)[0])
    return categories


def run_check(command: list[str]) -> tuple[bool, str]:
    result = subprocess.run(
        command,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )
    output = "\n".join(part.strip() for part in (result.stdout, result.stderr) if part.strip())
    return result.returncode == 0, output


def evaluate_gates(
    fixture: Path,
    wiki: Path,
    status: str,
    pages: list[dict[str, Any]],
    expected: dict[str, Any],
) -> list[dict[str, Any]]:
    """Deterministic gates that must pass before semantic scoring is trusted."""

    gates: list[dict[str, Any]] = []
    required_hold = expected_has_required_hold(expected)
    terminal_ok = status == "completed" or (required_hold and status == "needs_more_detail")
    gates.append(
        {
            "name": "terminal_status",
            "passed": terminal_ok,
            "detail": f"status={status}",
        }
    )

    touched = touched_page_paths(fixture, pages)
    manifest = read_manifest(wiki)
    raw_entry = manifest.get(EXPECTED_RAW_SOURCE)
    raw_refs = set()
    if isinstance(raw_entry, dict) and isinstance(raw_entry.get("referenced_by"), list):
        raw_refs = {str(item) for item in raw_entry["referenced_by"]}
    missing_manifest_refs = sorted(path for path in touched if path not in raw_refs)
    gates.append(
        {
            "name": "current_raw_manifest_references_touched_pages",
            "passed": not missing_manifest_refs,
            "detail": ", ".join(missing_manifest_refs) or "ok",
        }
    )

    missing_sources = sorted(
        page["path"]
        for page in pages
        if page["path"] in touched and EXPECTED_RAW_SOURCE not in source_list(page)
    )
    gates.append(
        {
            "name": "touched_pages_cite_current_raw_source",
            "passed": not missing_sources,
            "detail": ", ".join(missing_sources) or "ok",
        }
    )

    malformed_frontmatter = sorted(
        f"{page['path']}: {page['frontmatter_error']}"
        for page in pages
        if page.get("frontmatter_error")
    )
    gates.append(
        {
            "name": "frontmatter_parse",
            "passed": not malformed_frontmatter,
            "detail": " | ".join(malformed_frontmatter) or "ok",
        }
    )

    type_mismatches = sorted(
        f"{page['path']} type={page.get('type')!r}"
        for page in pages
        if page.get("type") != page.get("category")
    )
    gates.append(
        {
            "name": "type_matches_path",
            "passed": not type_mismatches,
            "detail": ", ".join(type_mismatches) or "ok",
        }
    )

    unknown_categories = sorted(
        {
            page["category"]
            for page in pages
            if page["category"] not in ALLOWED_TOP_LEVEL_CATEGORIES
        }
    )
    gates.append(
        {
            "name": "no_unknown_categories",
            "passed": not unknown_categories,
            "detail": ", ".join(unknown_categories) or "ok",
        }
    )

    fixture_allowed = fixture_categories(fixture, expected)
    unexpected_fixture_categories = sorted(
        {
            page["category"]
            for page in pages
            if page["category"] in CONTENT_CATEGORIES and page["category"] not in fixture_allowed
        }
    )
    gates.append(
        {
            "name": "no_fixture_unexpected_categories",
            "passed": not unexpected_fixture_categories,
            "detail": ", ".join(unexpected_fixture_categories) or "ok",
        }
    )

    bad_ideas = sorted(
        page["path"]
        for page in pages
        if page["category"] == "ideas"
        and (not page.get("frontmatter", {}).get("status") or not page.get("frontmatter", {}).get("priority"))
    )
    gates.append(
        {
            "name": "idea_status_priority",
            "passed": not bad_ideas,
            "detail": ", ".join(bad_ideas) or "ok",
        }
    )

    validation_failures = []
    validator = SCRIPTS / "wiki-validate-page.py"
    if validator.is_file():
        for page in pages:
            ok, output = run_check([sys.executable, str(validator), "--wiki-root", str(wiki), str(wiki / page["path"])])
            if not ok:
                validation_failures.append(f"{page['path']}: {output}")
    gates.append(
        {
            "name": "page_validator",
            "passed": not validation_failures,
            "detail": " | ".join(validation_failures) or "ok",
        }
    )

    manifest_tool = SCRIPTS / "wiki-manifest.py"
    if manifest_tool.is_file():
        ok, output = run_check([sys.executable, str(manifest_tool), "validate", str(wiki)])
        gates.append(
            {
                "name": "manifest_validator",
                "passed": ok,
                "detail": output or "ok",
            }
        )

    index_tool = SCRIPTS / "wiki-build-index.py"
    if index_tool.is_file():
        with tempfile.TemporaryDirectory(prefix="semantic-ingest-index-check-") as temp:
            copy = Path(temp) / "wiki"
            shutil.copytree(wiki, copy, ignore=shutil.ignore_patterns(".git", ".locks"))
            ok, output = run_check(
                [sys.executable, str(index_tool), "--wiki-root", str(copy), "--rebuild-all"]
            )
        gates.append(
            {
                "name": "index_build",
                "passed": ok,
                "detail": output or "ok",
            }
        )

    return gates


def hold_text(wiki: Path) -> str:
    chunks = []
    for rel in ("log.md", ".ingest-runs.jsonl"):
        path = wiki / rel
        if path.is_file():
            chunks.append(path.read_text(encoding="utf-8", errors="replace"))
    return "\n".join(chunks)


def score_case(fixture: Path, wiki: Path, status: str) -> dict[str, Any]:
    expected = load_yaml(fixture / "expected.yaml")
    pages = collect_pages(wiki)
    gates = evaluate_gates(fixture, wiki, status, pages, expected)
    object_results = []
    counts: Counter[str] = Counter()
    assigned_required_pages: dict[str, str] = {}
    matched_expected_pages: set[str] = set()
    for obj in expected["objects"]:
        page, match_status = match_page(obj, pages)
        if page is not None and match_status in {"matched", "absorbed", "kind_confusion"}:
            matched_expected_pages.add(page["path"])
        claims = obj.get("claims", {})
        text = page["text"] if page is not None else ""
        claim_text = strip_frontmatter(text)
        must = claims.get("must") or []
        must_not = claims.get("must_not") or []
        must_hits = [claim for claim in must if claim_covered(str(claim), claim_text)]
        must_not_hits = [
            claim for claim in must_not if claim_violated(str(claim), claim_text)
        ]
        presence = obj.get("presence")
        kind = obj.get("kind")
        if kind == "hold" and presence == "required":
            hold_log = hold_text(wiki)
            hold_must_hits = [
                claim for claim in must if claim_covered(str(claim), hold_log)
            ]
            hold_must_not_hits = [
                claim for claim in must_not if claim_violated(str(claim), hold_log)
            ]
            hold_signal = "hold" in hold_log.lower() or status == "needs_more_detail"
            outcome = (
                "passed"
                if not pages and hold_signal and len(hold_must_hits) == len(must) and not hold_must_not_hits
                else "failed"
            )
            must_hits = hold_must_hits
            must_not_hits = hold_must_not_hits
        elif presence == "forbidden":
            seed = seed_page_texts(fixture)
            new_matching_page = page is not None and page["path"] not in seed and match_status == "matched"
            outcome = "failed" if new_matching_page or must_not_hits else "passed"
        elif presence == "optional" and (page is None or match_status != "matched"):
            outcome = "passed"
        elif match_status == "matched" and len(must_hits) == len(must) and not must_not_hits:
            outcome = "passed"
        elif match_status in {"absorbed", "kind_confusion"}:
            outcome = match_status
        else:
            outcome = "failed"
        if (
            outcome == "passed"
            and page is not None
            and presence in {"required", "optional"}
            and kind != "hold"
            and match_status == "matched"
        ):
            previous = assigned_required_pages.get(page["path"])
            if previous is not None:
                outcome = "under_split"
            else:
                assigned_required_pages[page["path"]] = str(obj.get("id"))
        counts[outcome] += 1
        object_results.append(
            {
                "id": obj.get("id"),
                "kind": kind,
                "presence": presence,
                "outcome": outcome,
                "match_status": match_status,
                "matched_page": page["path"] if page else None,
                "must_covered": len(must_hits),
                "must_total": len(must),
                "must_not_violations": must_not_hits,
            }
        )
    seed = seed_page_texts(fixture)
    unassigned_pages = sorted(
        page["path"]
        for page in pages
        if page["category"] in CONTENT_CATEGORIES
        and (page["path"] not in seed or page["path"] in touched_page_paths(fixture, pages))
        and page["path"] not in matched_expected_pages
    )
    gates.append(
        {
            "name": "no_unassigned_content_pages",
            "passed": not unassigned_pages,
            "detail": ", ".join(unassigned_pages) or "ok",
        }
    )
    gate_counts = Counter("passed" if gate["passed"] else "failed" for gate in gates)
    case_passed = (
        gate_counts.get("failed", 0) == 0
        and all(result["outcome"] == "passed" for result in object_results)
    )
    return {
        "case_id": expected["case_id"],
        "slug": expected["slug"],
        "run_status": status,
        "case_passed": case_passed,
        "page_count": len(pages),
        "pages": [
            {"path": page["path"], "title": page["title"], "type": page["type"]}
            for page in pages
        ],
        "gates": gates,
        "gate_summary": dict(gate_counts),
        "objects": object_results,
        "summary": dict(counts),
    }


def run_provider_case(
    fixture: Path,
    output_root: Path,
    args: argparse.Namespace,
    env: dict[str, str],
) -> dict[str, Any]:
    case_dir = output_root / "cases" / fixture.name
    if case_dir.exists():
        shutil.rmtree(case_dir)
    case_dir.mkdir(parents=True)
    with tempfile.TemporaryDirectory(prefix="semantic-ingest-case-") as temp:
        workspace = Path(temp) / "workspace"
        wiki = workspace / "wiki"
        workspace.mkdir(parents=True)
        init_wiki(wiki, workspace, env, args)
        copy_seed(fixture, wiki)
        capture_name = write_capture(fixture, wiki)
        subprocess.run(
            [
                sys.executable,
                str(SCRIPTS / "wiki_dispatch.py"),
                "tick",
                "--wiki",
                str(wiki),
                "--source",
                "manual",
            ],
            env=env,
            check=True,
        )
        status = wait_for_capture(wiki, capture_name, args.timeout_seconds)
        result = score_case(fixture, wiki, status)
        result["wiki_snapshot"] = str(case_dir / "wiki-snapshot")
        runs = wiki / ".ingest-runs.jsonl"
        if runs.exists():
            shutil.copy2(runs, case_dir / "ingest-runs.jsonl")
        provider_runs = wiki / ".locks" / "ingest-runs"
        if provider_runs.exists():
            shutil.copytree(provider_runs, case_dir / "provider-runs")
        shutil.copytree(
            wiki,
            case_dir / "wiki-snapshot",
            ignore=shutil.ignore_patterns(".locks", ".git"),
        )
        (case_dir / "result.json").write_text(
            json.dumps(result, indent=2, sort_keys=True) + "\n",
            encoding="utf-8",
        )
        return result


def run_snapshot_case(fixture: Path, output_root: Path, snapshots_root: Path) -> dict[str, Any]:
    case_dir = output_root / "cases" / fixture.name
    if case_dir.exists():
        shutil.rmtree(case_dir)
    case_dir.mkdir(parents=True)
    source_case_dir = snapshots_root / "cases" / fixture.name
    wiki = source_case_dir / "wiki-snapshot"
    if not wiki.is_dir():
        raise RuntimeError(f"{fixture.name}: missing wiki snapshot: {wiki}")
    status = "snapshot"
    previous_result = source_case_dir / "result.json"
    if previous_result.is_file():
        try:
            status = str(json.loads(previous_result.read_text(encoding="utf-8")).get("run_status"))
        except json.JSONDecodeError:
            status = "snapshot"
    result = score_case(fixture, wiki, status)
    result["wiki_snapshot"] = str(wiki)
    (case_dir / "result.json").write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    return result


def write_markdown_report(path: Path, payload: dict[str, Any]) -> None:
    lines = [
        "# Semantic Ingest Baseline",
        "",
        f"- generated_at: `{payload['generated_at']}`",
        f"- mode: `{payload['mode']}`",
        f"- skill_sha256: `{payload['skill']['sha256']}`",
        f"- repo_head: `{payload['repo_head']}`",
        f"- cases_passed: `{payload.get('metrics', {}).get('cases_passed', 0)}/{payload.get('metrics', {}).get('cases_total', 0)}`",
    ]
    if payload.get("source_snapshot_baseline"):
        source = payload["source_snapshot_baseline"]
        lines.extend(
            [
                f"- source_snapshot_dir: `{source.get('path')}`",
                f"- source_snapshot_skill_sha256: `{source.get('skill_sha256')}`",
                f"- source_snapshot_repo_head: `{source.get('repo_head')}`",
            ]
        )
    lines.extend(
        [
            "",
            "| Case | Status | Case pass | Pages | Gates failed | Passed | Failed | Absorbed | Kind confusion | Under-split |",
            "| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |",
        ]
    )
    for result in payload.get("results", []):
        summary = result.get("summary", {})
        gate_summary = result.get("gate_summary", {})
        lines.append(
            "| {case} | {status} | {case_pass} | {pages} | {gates_failed} | {passed} | {failed} | {absorbed} | {kind} | {under_split} |".format(
                case=f"{result['case_id']}-{result['slug']}",
                status=result.get("run_status", ""),
                case_pass="yes" if result.get("case_passed") else "no",
                pages=result.get("page_count", 0),
                gates_failed=gate_summary.get("failed", 0),
                passed=summary.get("passed", 0),
                failed=summary.get("failed", 0),
                absorbed=summary.get("absorbed", 0),
                kind=summary.get("kind_confusion", 0),
                under_split=summary.get("under_split", 0),
            )
        )
    if payload.get("metrics"):
        metrics = payload["metrics"]
        lines.extend(
            [
                "",
                "## Metrics",
                "",
                f"- required_object_recall_by_kind: `{metrics.get('required_object_recall_by_kind', {})}`",
                f"- forbidden_failures: `{metrics.get('forbidden_failures', 0)}`",
                f"- named_thing_in_concepts: `{metrics.get('named_thing_in_concepts', 0)}`",
                f"- under_split: `{metrics.get('under_split', 0)}`",
                f"- faithfulness_violations: `{metrics.get('faithfulness_violations', 0)}`",
                f"- hold_quality_failures: `{metrics.get('hold_quality_failures', 0)}`",
            ]
        )
    lines.append("")
    lines.append("Scoring is heuristic and gate-backed, but still requires human review before product decisions.")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def aggregate_metrics(results: list[dict[str, Any]]) -> dict[str, Any]:
    required_by_kind: dict[str, Counter[str]] = {}
    forbidden_failures = 0
    named_thing_in_concepts = 0
    under_split = 0
    faithfulness_violations = 0
    hold_quality_failures = 0
    for result in results:
        for obj in result.get("objects", []):
            kind = str(obj.get("kind"))
            presence = obj.get("presence")
            outcome = obj.get("outcome")
            if presence == "required":
                required_by_kind.setdefault(kind, Counter())
                required_by_kind[kind]["total"] += 1
                if outcome == "passed":
                    required_by_kind[kind]["passed"] += 1
            if presence == "forbidden" and outcome == "failed":
                forbidden_failures += 1
            if outcome == "absorbed" and obj.get("matched_page", "").startswith("concepts/"):
                named_thing_in_concepts += 1
            if outcome == "under_split":
                under_split += 1
            if obj.get("must_not_violations"):
                faithfulness_violations += len(obj["must_not_violations"])
            if kind == "hold" and outcome != "passed":
                hold_quality_failures += 1
    recall = {
        kind: f"{counts.get('passed', 0)}/{counts.get('total', 0)}"
        for kind, counts in sorted(required_by_kind.items())
    }
    return {
        "cases_total": len(results),
        "cases_passed": sum(1 for result in results if result.get("case_passed")),
        "required_object_recall_by_kind": recall,
        "forbidden_failures": forbidden_failures,
        "named_thing_in_concepts": named_thing_in_concepts,
        "under_split": under_split,
        "faithfulness_violations": faithfulness_violations,
        "hold_quality_failures": hold_quality_failures,
    }


def write_fixture_page(path: Path, category: str, title: str, body: str, sources: list[str] | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    sources = sources if sources is not None else ["raw/source.md"]
    extra = ""
    if category == "ideas":
        extra = "status: proposed\npriority: low\n"
    path.write_text(
        "\n".join(
            [
                "---",
                f"title: {yaml_scalar(title)}",
                f"type: {category}",
                "tags: []",
                f"sources: {yaml_list(sources)}",
                f"created: {yaml_scalar('2026-08-21T00:00:00Z')}",
                f"updated: {yaml_scalar('2026-08-21T00:00:00Z')}",
                extra.rstrip(),
                "quality:",
                "  accuracy: 5",
                "  completeness: 5",
                "  signal: 5",
                "  interlinking: 5",
                "  overall: 5.00",
                f"  rated_at: {yaml_scalar('2026-08-21T00:00:00Z')}",
                "  rated_by: ingester",
                "---",
                "",
                body,
                "",
            ]
        ).replace("\n\nquality:", "\nquality:")
        + "\n",
        encoding="utf-8",
    )


def write_manifest_for_pages(wiki: Path, refs: list[str]) -> None:
    (wiki / ".manifest.json").write_text(
        json.dumps(
            {
                EXPECTED_RAW_SOURCE: {
                    "sha256": "selftest",
                    "origin": "conversation",
                    "copied_at": "2026-08-21T00:00:00Z",
                    "last_ingested": "2026-08-21T00:00:00Z",
                    "referenced_by": refs,
                }
            },
            indent=2,
            sort_keys=True,
        )
        + "\n",
        encoding="utf-8",
    )


def init_selftest_wiki(root: Path, source: str = "selftest source") -> Path:
    wiki = root / "wiki"
    wiki.mkdir(parents=True)
    (wiki / ".wiki-config").write_text("", encoding="utf-8")
    (wiki / "schema.md").write_text("# Schema\n", encoding="utf-8")
    (wiki / "index.md").write_text("# Wiki Index\n", encoding="utf-8")
    (wiki / "log.md").write_text("# Wiki Log\n", encoding="utf-8")
    (wiki / "raw").mkdir()
    (wiki / "raw" / "source.md").write_text(source, encoding="utf-8")
    write_manifest_for_pages(wiki, [])
    return wiki


def assert_selftest(condition: bool, label: str, failures: list[str]) -> None:
    if condition:
        print(f"PASS: {label}")
    else:
        print(f"FAIL: {label}")
        failures.append(label)


def run_self_tests() -> int:
    failures: list[str] = []
    false_claim = "Queue creation uses --ack-deadline 30s and teleports messages to Mars."
    text = "Queue creation uses --ack-deadline 30s."
    assert_selftest(
        not claim_covered(false_claim, text),
        "claim_covered rejects flag-only false positives",
        failures,
    )
    assert_selftest(
        not claim_covered("The window is in-memory and per process.", "The window is not in-memory; it is persisted."),
        "claim_covered rejects negated positive claims",
        failures,
    )
    assert_selftest(
        claim_violated(
            "Foldgate is cluster-wide or the platform standard limiter.",
            "Foldgate is not merely a local helper. Foldgate is cluster-wide and the platform standard limiter.",
        ),
        "claim_violated is not masked by unrelated negation",
        failures,
    )

    with tempfile.TemporaryDirectory(prefix="semantic-ingest-selftest-") as temp:
        fixture = BENCH_ROOT / "fixtures" / "0001-entity-tool-floor"
        wiki = init_selftest_wiki(Path(temp), (fixture / "source.md").read_text(encoding="utf-8"))
        body = "RivetKit writes rivet.lock from rivet.toml. The binary name is rivet. rivet stamp hashes source trees with BLAKE3 and refuses network access. rivet fetch is separate and requires RIVET_ALLOW_FETCH=1."
        write_fixture_page(wiki / "concepts" / "reproducible-builds.md", "concepts", "Reproducible builds", body)
        write_manifest_for_pages(wiki, ["concepts/reproducible-builds.md"])
        result = score_case(fixture, wiki, "completed")
        assert_selftest(
            not result["case_passed"]
            and any(obj["outcome"] in {"absorbed", "failed"} for obj in result["objects"]),
            "concept dump does not pass entity floor",
            failures,
        )

    with tempfile.TemporaryDirectory(prefix="semantic-ingest-selftest-") as temp:
        fixture = BENCH_ROOT / "fixtures" / "0001-entity-tool-floor"
        wiki = init_selftest_wiki(Path(temp), (fixture / "source.md").read_text(encoding="utf-8"))
        entity_body = "RivetKit writes rivet.lock from rivet.toml.\nThe binary name is rivet.\nrivet stamp hashes source trees with BLAKE3 and refuses network access.\nrivet fetch is separate and requires RIVET_ALLOW_FETCH=1."
        write_fixture_page(wiki / "entities" / "rivetkit.md", "entities", "RivetKit", entity_body)
        write_fixture_page(wiki / "concepts" / "lockfile-primitive.md", "concepts", "Lockfile primitive", "Extra page that is not assigned to any expected object.")
        write_manifest_for_pages(wiki, ["entities/rivetkit.md", "concepts/lockfile-primitive.md"])
        result = score_case(fixture, wiki, "completed")
        assert_selftest(
            not result["case_passed"]
            and any(gate["name"] == "no_unassigned_content_pages" and not gate["passed"] for gate in result["gates"]),
            "extra unassigned content page fails",
            failures,
        )

    with tempfile.TemporaryDirectory(prefix="semantic-ingest-selftest-") as temp:
        fixture = BENCH_ROOT / "fixtures" / "0001-entity-tool-floor"
        wiki = init_selftest_wiki(Path(temp), (fixture / "source.md").read_text(encoding="utf-8"))
        entity_body = "RivetKit writes rivet.lock from rivet.toml.\nThe binary name is rivet.\nrivet stamp hashes source trees with BLAKE3 and refuses network access.\nrivet fetch is separate and requires RIVET_ALLOW_FETCH=1."
        write_fixture_page(wiki / "entities" / "rivetkit.md", "entities", "RivetKit", entity_body, sources=["raw/other.md"])
        write_manifest_for_pages(wiki, ["entities/rivetkit.md"])
        result = score_case(fixture, wiki, "completed")
        assert_selftest(
            not result["case_passed"]
            and any(gate["name"] == "touched_pages_cite_current_raw_source" and not gate["passed"] for gate in result["gates"]),
            "stale or wrong sources fail current raw source gate",
            failures,
        )

    with tempfile.TemporaryDirectory(prefix="semantic-ingest-selftest-") as temp:
        fixture = BENCH_ROOT / "fixtures" / "0001-entity-tool-floor"
        wiki = init_selftest_wiki(Path(temp), (fixture / "source.md").read_text(encoding="utf-8"))
        bad = wiki / "entities" / "rivetkit.md"
        bad.parent.mkdir(parents=True, exist_ok=True)
        bad.write_text("---\ntitle: [unterminated\n---\nRivetKit writes rivet.lock from rivet.toml.\n", encoding="utf-8")
        write_manifest_for_pages(wiki, ["entities/rivetkit.md"])
        result = score_case(fixture, wiki, "completed")
        assert_selftest(
            not result["case_passed"]
            and any(gate["name"] == "frontmatter_parse" and not gate["passed"] for gate in result["gates"]),
            "malformed frontmatter fails as a gate",
            failures,
        )

    with tempfile.TemporaryDirectory(prefix="semantic-ingest-selftest-") as temp:
        fixture = BENCH_ROOT / "fixtures" / "0003-query-lookup-floor"
        wiki = init_selftest_wiki(Path(temp), (fixture / "source.md").read_text(encoding="utf-8"))
        query_body = "Inspect retry_class, next_attempt, and last_error for a known job id.\nretry_class values are immediate, backoff, and dead.\nUnknown job id can be found by listing failed export jobs by target.\nA 429 on the export callback does not map one-to-one to retry_class."
        write_fixture_page(wiki / "queries" / "ambervault-retry-class-lookup.md", "queries", "Ambervault retry class lookup", query_body)
        write_fixture_page(wiki / "entities" / "ambervault.md", "entities", "Ambervault", "Ambervault export jobs appear in the lookup source.")
        write_manifest_for_pages(wiki, ["queries/ambervault-retry-class-lookup.md", "entities/ambervault.md"])
        result = score_case(fixture, wiki, "completed")
        assert_selftest(
            not result["case_passed"]
            and any(obj["id"] == "ambervault-product-page" and obj["outcome"] == "failed" for obj in result["objects"]),
            "sibling Ambervault entity fails lookup floor",
            failures,
        )

    with tempfile.TemporaryDirectory(prefix="semantic-ingest-selftest-") as temp:
        fixture = BENCH_ROOT / "fixtures" / "0006-mixed-multi-object-note"
        wiki = init_selftest_wiki(Path(temp), (fixture / "source.md").read_text(encoding="utf-8"))
        body = (fixture / "source.md").read_text(encoding="utf-8")
        write_fixture_page(wiki / "concepts" / "graph-databases.md", "concepts", "Graph databases", body)
        write_manifest_for_pages(wiki, ["concepts/graph-databases.md"])
        result = score_case(fixture, wiki, "completed")
        assert_selftest(
            not result["case_passed"]
            and result["summary"].get("under_split", 0) + result["summary"].get("absorbed", 0) > 0,
            "single combined page fails multi-object split",
            failures,
        )

    with tempfile.TemporaryDirectory(prefix="semantic-ingest-selftest-") as temp:
        fixture = BENCH_ROOT / "fixtures" / "0008-low-evidence-hold"
        wiki = init_selftest_wiki(Path(temp), (fixture / "source.md").read_text(encoding="utf-8"))
        result = score_case(fixture, wiki, "completed")
        assert_selftest(
            not result["case_passed"]
            and any(obj["id"] == "marblehook-upload-limit-hold" and obj["outcome"] == "failed" for obj in result["objects"]),
            "silent no-op does not satisfy hold quality",
            failures,
        )

    with tempfile.TemporaryDirectory(prefix="semantic-ingest-selftest-") as temp:
        fixture = BENCH_ROOT / "fixtures" / "0009-merge-magnet-seeded"
        wiki = init_selftest_wiki(Path(temp), (fixture / "source.md").read_text(encoding="utf-8"))
        copy_seed(fixture, wiki)
        write_fixture_page(
            wiki / "entities" / "sable-queue.md",
            "entities",
            "Sable Queue",
            "Sable Queue is a named message broker with binary sable. Default listen address is 127.0.0.1:7420. Queue creation uses --ack-deadline 30s. Dead letters are opt-in with --dead-letter at create time.",
        )
        concept = wiki / "concepts" / "job-queues.md"
        concept.write_text(
            concept.read_text(encoding="utf-8")
            + "\nSable Queue default listen address is 127.0.0.1:7420. Queue creation uses --ack-deadline 30s. Dead letters use --dead-letter.\n",
            encoding="utf-8",
        )
        write_manifest_for_pages(wiki, ["entities/sable-queue.md"])
        result = score_case(fixture, wiki, "completed")
        assert_selftest(
            not result["case_passed"]
            and any(obj["id"] == "job-queues-concept-absorption" and obj["outcome"] == "failed" for obj in result["objects"]),
            "seeded concept absorption fails merge-magnet case",
            failures,
        )

    if failures:
        print(f"self-test failures: {len(failures)}", file=sys.stderr)
        return 1
    print("all self-tests passed")
    return 0


def main(argv: list[str] | None = None) -> int:
    global SCRIPTS

    parser = argparse.ArgumentParser()
    parser.add_argument("--fixtures-dir", default=str(BENCH_ROOT / "fixtures"))
    parser.add_argument("--output-dir", default=str(BENCH_ROOT / "runs" / "baseline-current"))
    parser.add_argument("--case", action="append", default=[])
    parser.add_argument("--run-provider", action="store_true")
    parser.add_argument("--score-snapshots-dir")
    parser.add_argument("--provider", choices=["codex", "grok", "claude"], default="codex")
    parser.add_argument("--model")
    parser.add_argument("--effort", default="medium")
    parser.add_argument("--executable")
    parser.add_argument("--timeout-seconds", type=int, default=900)
    parser.add_argument("--heartbeat-seconds", type=int, default=10)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args(argv)

    if args.self_test:
        return run_self_tests()

    fixtures_root = Path(args.fixtures_dir).resolve()
    output_root = Path(args.output_dir).resolve()
    fixtures = fixture_dirs(fixtures_root, args.case)
    if not fixtures:
        raise SystemExit("no fixtures selected")

    fixture_summary = [validate_fixture(path) for path in fixtures]
    skill = REPO_ROOT / "skills" / "karpathy-wiki-ingest" / "SKILL.md"
    repo_head = subprocess.check_output(
        ["git", "rev-parse", "HEAD"], cwd=REPO_ROOT, text=True
    ).strip()
    payload: dict[str, Any] = {
        "generated_at": utc_now(),
        "mode": (
            "provider"
            if args.run_provider
            else "snapshot"
            if args.score_snapshots_dir
            else "validate-only"
        ),
        "repo_head": repo_head,
        "skill": {
            "path": str(skill.relative_to(REPO_ROOT)),
            "sha256": sha256_file(skill),
        },
        "fixtures": fixture_summary,
        "results": [],
    }

    if args.run_provider and args.score_snapshots_dir:
        raise SystemExit("--run-provider and --score-snapshots-dir are mutually exclusive")

    output_root.mkdir(parents=True, exist_ok=True)
    if args.run_provider:
        if not args.model:
            raise SystemExit("--model is required with --run-provider")
        if not args.executable:
            args.executable = shutil.which(args.provider) or ""
        if not args.executable:
            raise SystemExit("--executable is required with --run-provider")
        env = os.environ.copy()
        env["WIKI_CONFIG_HOME"] = str(output_root / "config-home")
        env["WIKI_CODEXBAR_EXECUTABLE"] = str(output_root / "codexbar-not-installed")
        isolated_root = prepare_isolated_plugin_root(output_root)
        payload["isolated_plugin_root"] = str(isolated_root)
        SCRIPTS = isolated_root / "scripts"
        for fixture in fixtures:
            payload["results"].append(run_provider_case(fixture, output_root, args, env))
    elif args.score_snapshots_dir:
        snapshots_root = Path(args.score_snapshots_dir).resolve()
        source_baseline = snapshots_root / "baseline.json"
        if source_baseline.is_file():
            try:
                source_payload = json.loads(source_baseline.read_text(encoding="utf-8"))
                payload["source_snapshot_baseline"] = {
                    "path": str(snapshots_root),
                    "generated_at": source_payload.get("generated_at"),
                    "repo_head": source_payload.get("repo_head"),
                    "skill_sha256": (source_payload.get("skill") or {}).get("sha256"),
                }
            except json.JSONDecodeError:
                payload["source_snapshot_baseline"] = {"path": str(snapshots_root)}
        for fixture in fixtures:
            payload["results"].append(run_snapshot_case(fixture, output_root, snapshots_root))

    payload["metrics"] = aggregate_metrics(payload["results"])

    (output_root / "baseline.json").write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    write_markdown_report(output_root / "baseline.md", payload)
    print(f"wrote {output_root / 'baseline.json'}")
    print(f"fixtures: {len(fixtures)}")
    print(f"skill_sha256: {payload['skill']['sha256']}")
    if not args.run_provider:
        if args.score_snapshots_dir:
            print("snapshot scoring: reused existing wiki snapshots")
        else:
            print("validate-only: pass --run-provider with --model to run detached ingesters")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
