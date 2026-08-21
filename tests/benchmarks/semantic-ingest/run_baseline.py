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
import os
from pathlib import Path
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


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(65536), b""):
            digest.update(chunk)
    return digest.hexdigest()


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


def claim_covered(claim: str, text: str) -> bool:
    tokens = token_set(claim)
    if not tokens:
        return True
    haystack = token_set(text)
    overlap = len(tokens & haystack)
    return overlap >= max(1, min(len(tokens), 3))


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
    if not isinstance(expected_data.get("objects"), list) or not expected_data["objects"]:
        raise RuntimeError(f"{path.name}: expected objects missing")

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
    subprocess.run(
        ["bash", str(SCRIPTS / "wiki-init.sh"), "project", str(wiki)],
        env=env,
        check=True,
        stdout=subprocess.DEVNULL,
    )
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
    source_copy = wiki / "inbox" / fixture.name / "source.md"
    source_copy.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(fixture / "source.md", source_copy)

    title = context.get("title") or fixture.name
    capture_name = f"baseline-{fixture.name}.md"
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
            f"capture_id: {yaml_scalar('cap-' + hashlib.sha1(fixture.name.encode()).hexdigest())}",
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
    for category in CONTENT_CATEGORIES:
        root = wiki / category
        if not root.exists():
            continue
        for path in root.rglob("*.md"):
            if path.name == "_index.md":
                continue
            text = path.read_text(encoding="utf-8", errors="replace")
            fm_raw = extract_frontmatter(text)
            fm = parse_yaml(fm_raw) if fm_raw is not None else {}
            rel = str(path.relative_to(wiki))
            pages.append(
                {
                    "path": rel,
                    "category": rel.split("/", 1)[0],
                    "title": str(fm.get("title") or path.stem),
                    "type": fm.get("type"),
                    "text": text,
                }
            )
    return pages


def match_page(obj: dict[str, Any], pages: list[dict[str, Any]]) -> tuple[dict[str, Any] | None, str]:
    names = [str(item).lower() for item in obj.get("match", {}).get("names", [])]
    identifiers = [
        str(item).lower() for item in obj.get("match", {}).get("identifiers", [])
    ]
    required_category = obj.get("category", {}).get("required")
    allowed = set(obj.get("category", {}).get("allowed") or [])
    forbidden = set(obj.get("category", {}).get("forbidden") or [])

    best: dict[str, Any] | None = None
    best_score = 0
    best_status = "miss"
    for page in pages:
        hay = f"{page['path']} {page['title']} {page['text']}".lower()
        score = 0
        score += sum(3 for name in names if name and name in hay)
        score += sum(2 for ident in identifiers if ident and ident in hay)
        if score <= best_score:
            continue
        category = page["category"]
        if category in forbidden:
            status = "absorbed"
        elif required_category and category != required_category:
            status = "kind_confusion"
        elif allowed and category not in allowed:
            status = "kind_confusion"
        else:
            status = "matched"
        best = page
        best_score = score
        best_status = status
    return best, best_status


def score_case(fixture: Path, wiki: Path, status: str) -> dict[str, Any]:
    expected = load_yaml(fixture / "expected.yaml")
    pages = collect_pages(wiki)
    object_results = []
    counts: Counter[str] = Counter()
    for obj in expected["objects"]:
        page, match_status = match_page(obj, pages)
        claims = obj.get("claims", {})
        text = page["text"] if page is not None else ""
        must = claims.get("must") or []
        must_not = claims.get("must_not") or []
        must_hits = [claim for claim in must if claim_covered(str(claim), text)]
        must_not_hits = [
            claim for claim in must_not if claim_covered(str(claim), text)
        ]
        presence = obj.get("presence")
        kind = obj.get("kind")
        if kind == "hold" and presence == "required":
            outcome = "passed" if not pages or status == "needs_more_detail" else "failed"
        elif presence == "forbidden":
            outcome = "passed" if page is None else "failed"
        elif match_status == "matched" and len(must_hits) == len(must) and not must_not_hits:
            outcome = "passed"
        elif match_status in {"absorbed", "kind_confusion"}:
            outcome = match_status
        else:
            outcome = "failed"
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
    return {
        "case_id": expected["case_id"],
        "slug": expected["slug"],
        "run_status": status,
        "page_count": len(pages),
        "pages": [
            {"path": page["path"], "title": page["title"], "type": page["type"]}
            for page in pages
        ],
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
    workspace = case_dir / "workspace"
    wiki = workspace / "wiki"
    workspace.mkdir(parents=True)
    init_wiki(wiki, workspace, env, args)
    copy_seed(fixture, wiki)
    capture_name = write_capture(fixture, wiki)
    subprocess.run(
        [sys.executable, str(SCRIPTS / "wiki_dispatch.py"), "tick", "--wiki", str(wiki), "--source", "manual"],
        env=env,
        check=True,
    )
    status = wait_for_capture(wiki, capture_name, args.timeout_seconds)
    result = score_case(fixture, wiki, status)
    result["wiki"] = str(wiki)
    runs = wiki / ".ingest-runs.jsonl"
    if runs.exists():
        shutil.copy2(runs, case_dir / "ingest-runs.jsonl")
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
        "",
        "| Case | Status | Pages | Passed | Failed | Absorbed | Kind confusion |",
        "| --- | --- | ---: | ---: | ---: | ---: | ---: |",
    ]
    for result in payload.get("results", []):
        summary = result.get("summary", {})
        lines.append(
            "| {case} | {status} | {pages} | {passed} | {failed} | {absorbed} | {kind} |".format(
                case=f"{result['case_id']}-{result['slug']}",
                status=result.get("run_status", ""),
                pages=result.get("page_count", 0),
                passed=summary.get("passed", 0),
                failed=summary.get("failed", 0),
                absorbed=summary.get("absorbed", 0),
                kind=summary.get("kind_confusion", 0),
            )
        )
    lines.append("")
    lines.append("Scoring is heuristic v0 and should be reviewed before product decisions.")
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--fixtures-dir", default=str(BENCH_ROOT / "fixtures"))
    parser.add_argument("--output-dir", default=str(BENCH_ROOT / "runs" / "baseline-current"))
    parser.add_argument("--case", action="append", default=[])
    parser.add_argument("--run-provider", action="store_true")
    parser.add_argument("--provider", choices=["codex", "grok", "claude"], default="codex")
    parser.add_argument("--model")
    parser.add_argument("--effort", default="medium")
    parser.add_argument("--executable")
    parser.add_argument("--timeout-seconds", type=int, default=900)
    parser.add_argument("--heartbeat-seconds", type=int, default=10)
    args = parser.parse_args(argv)

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
        "mode": "provider" if args.run_provider else "validate-only",
        "repo_head": repo_head,
        "skill": {
            "path": str(skill.relative_to(REPO_ROOT)),
            "sha256": sha256_file(skill),
        },
        "fixtures": fixture_summary,
        "results": [],
    }

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
        for fixture in fixtures:
            payload["results"].append(run_provider_case(fixture, output_root, args, env))

    (output_root / "baseline.json").write_text(
        json.dumps(payload, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    write_markdown_report(output_root / "baseline.md", payload)
    print(f"wrote {output_root / 'baseline.json'}")
    print(f"fixtures: {len(fixtures)}")
    print(f"skill_sha256: {payload['skill']['sha256']}")
    if not args.run_provider:
        print("validate-only: pass --run-provider with --model to run detached ingesters")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
