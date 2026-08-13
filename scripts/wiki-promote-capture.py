#!/usr/bin/env python3
"""Persist a project ingester's selective promotion decision safely."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
from typing import Any


class PromotionError(RuntimeError):
    pass


def _frontmatter(text: str) -> tuple[list[str], int]:
    lines = text.splitlines(keepends=True)
    if not lines or lines[0].rstrip("\r\n") != "---":
        raise PromotionError("promotion source has no YAML frontmatter")
    for index in range(1, len(lines)):
        if lines[index].rstrip("\r\n") == "---":
            return lines, index
    raise PromotionError("promotion source has unclosed YAML frontmatter")


def _scalar(text: str, key: str) -> str | None:
    lines, closing = _frontmatter(text)
    pattern = re.compile(rf"^{re.escape(key)}:\s*(.*?)\s*$")
    for line in lines[1:closing]:
        match = pattern.match(line.rstrip("\r\n"))
        if not match:
            continue
        value = match.group(1)
        if value in {"null", "~", ""}:
            return None
        if len(value) >= 2 and value[0] == value[-1] and value[0] in {'"', "'"}:
            value = value[1:-1]
        return value
    return None


def _set_scalars(path: Path, updates: dict[str, str | None]) -> None:
    text = path.read_text(encoding="utf-8")
    lines, closing = _frontmatter(text)
    pending = dict(updates)
    for index in range(1, closing):
        key = lines[index].split(":", 1)[0]
        if key not in pending:
            continue
        value = pending.pop(key)
        rendered = "null" if value is None else json.dumps(value, ensure_ascii=False)
        lines[index] = f"{key}: {rendered}\n"
    for key, value in pending.items():
        rendered = "null" if value is None else json.dumps(value, ensure_ascii=False)
        lines.insert(closing, f"{key}: {rendered}\n")
        closing += 1
    _atomic_write(path, "".join(lines))


def _atomic_write(path: Path, text: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    handle = tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=path.parent, prefix=f".{path.name}.", delete=False
    )
    temp = Path(handle.name)
    try:
        with handle:
            handle.write(text)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp, 0o644)
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)


def _read_json(path: Path) -> dict[str, Any] | None:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None
    except (OSError, json.JSONDecodeError) as exc:
        raise PromotionError(f"invalid promotion receipt {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise PromotionError(f"invalid promotion receipt {path}: expected object")
    return value


def _source_context() -> tuple[Path, Path, Path, str, str]:
    root_value = os.environ.get("WIKI_ROOT", "")
    capture_value = os.environ.get("WIKI_CAPTURE", "")
    plugin_value = os.environ.get("WIKI_PLUGIN_ROOT", "")
    if not root_value or not capture_value or not plugin_value:
        raise PromotionError("WIKI_ROOT, WIKI_CAPTURE, and WIKI_PLUGIN_ROOT are required")
    root = Path(root_value).expanduser().resolve()
    capture = Path(capture_value).expanduser().resolve()
    plugin = Path(plugin_value).expanduser().resolve()
    if capture.parent != root / ".wiki-pending" or not capture.name.endswith(".md.processing"):
        raise PromotionError("WIKI_CAPTURE must be a .md.processing file in WIKI_ROOT/.wiki-pending")
    if not capture.is_file():
        raise PromotionError("promotion source capture is missing")
    structural = (root / ".wiki-config").read_text(encoding="utf-8")
    if not re.search(r'^role\s*=\s*"project"\s*$', structural, flags=re.MULTILINE):
        raise PromotionError("selective promotion requires a project wiki")
    source_text = capture.read_text(encoding="utf-8")
    if _scalar(source_text, "promotion_policy") != "selective":
        raise PromotionError("capture is not eligible for selective promotion")
    capture_id = _scalar(source_text, "capture_id")
    if not capture_id or not re.fullmatch(r"cap-[A-Za-z0-9._-]+", capture_id):
        raise PromotionError("selective capture has no valid portable capture_id")
    promotion_id = "prom-" + hashlib.sha256(capture_id.encode("utf-8")).hexdigest()[:24]
    return root, capture, plugin, capture_id, promotion_id


def _main_wiki() -> Path:
    pointer = Path(
        os.environ.get("WIKI_POINTER_FILE", str(Path.home() / ".wiki-pointer"))
    ).expanduser()
    try:
        value = pointer.read_text(encoding="utf-8").strip()
    except OSError as exc:
        raise PromotionError(f"main wiki pointer is unavailable: {pointer}: {exc}") from exc
    if not value or value == "none":
        raise PromotionError("selective promotion requires a configured main wiki")
    main = Path(value).expanduser().resolve()
    try:
        structural = (main / ".wiki-config").read_text(encoding="utf-8")
    except OSError as exc:
        raise PromotionError(f"main wiki pointer target is invalid: {main}: {exc}") from exc
    if not re.search(r'^role\s*=\s*"main"\s*$', structural, flags=re.MULTILINE):
        raise PromotionError("main wiki pointer target does not have role=main")
    for required in ("schema.md", "index.md", ".wiki-pending"):
        if not (main / required).exists():
            raise PromotionError(f"main wiki pointer target is incomplete: missing {required}")
    return main


def _configured_main_wiki() -> Path | None:
    pointer = Path(
        os.environ.get("WIKI_POINTER_FILE", str(Path.home() / ".wiki-pointer"))
    ).expanduser()
    try:
        value = pointer.read_text(encoding="utf-8").strip()
    except FileNotFoundError:
        return None
    if not value or value == "none":
        return None
    return _main_wiki()


def _existing_target(main: Path, name: str) -> Path | None:
    candidates = [
        main / ".wiki-pending" / name,
        main / ".wiki-pending" / f"{name}.processing",
        main / ".wiki-pending" / "failed" / name,
    ]
    candidates.extend((main / ".wiki-pending" / "archive").glob(f"*/{name}"))
    return next((path for path in candidates if path.is_file()), None)


def _existing_target_by_promotion_id(main: Path, promotion_id: str) -> Path | None:
    pending = main / ".wiki-pending"
    candidates = list(pending.glob(f"*-{promotion_id}.md"))
    candidates.extend(pending.glob(f"*-{promotion_id}.md.processing"))
    candidates.extend((pending / "failed").glob(f"*-{promotion_id}.md"))
    candidates.extend((pending / "archive").glob(f"*/*-{promotion_id}.md"))
    existing = [path for path in candidates if path.is_file()]
    if len(existing) > 1:
        raise PromotionError(f"multiple promotion targets found for {promotion_id}")
    return existing[0] if existing else None


def _validate_existing(path: Path, capture_id: str, promotion_id: str) -> None:
    text = path.read_text(encoding="utf-8")
    if _scalar(text, "capture_id") != promotion_id or _scalar(text, "propagated_from") != capture_id:
        raise PromotionError(f"promotion target collision at {path}")


def _derived_capture(
    *, title: str, body: str, capture_id: str, promotion_id: str, captured_at: str
) -> str:
    return "\n".join(
        [
            "---",
            f"title: {json.dumps(title, ensure_ascii=False)}",
            'evidence: "conversation"',
            'evidence_type: "conversation"',
            'capture_kind: "chat-only"',
            'suggested_action: "auto"',
            "suggested_pages: []",
            f"captured_at: {json.dumps(captured_at)}",
            'captured_by: "project-ingester"',
            f"capture_id: {json.dumps(promotion_id)}",
            'promotion_policy: "none"',
            "promotion_decision: null",
            "promotion_id: null",
            f"propagated_from: {json.dumps(capture_id)}",
            "---",
            "",
            body.rstrip(),
            "",
        ]
    )


def keep_local() -> int:
    root, capture, _plugin, capture_id, promotion_id = _source_context()
    state_dir = root / ".locks" / "promotions"
    state_dir.mkdir(parents=True, exist_ok=True)
    with (state_dir / f"{promotion_id}.lock").open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        if _read_json(state_dir / f"{promotion_id}.json") is not None:
            raise PromotionError("promotion intent already exists and cannot become keep-local")
        decision = _scalar(capture.read_text(encoding="utf-8"), "promotion_decision")
        if decision == "promoted":
            raise PromotionError("capture is already promoted and cannot become keep-local")
        if decision == "keep-local":
            return 0
        main = _configured_main_wiki()
        if main is not None:
            existing = _existing_target_by_promotion_id(main, promotion_id)
            if existing is not None:
                _validate_existing(existing, capture_id, promotion_id)
                raise PromotionError("promotion target already exists and cannot become keep-local")
        _set_scalars(capture, {"promotion_decision": "keep-local", "promotion_id": None})
    return 0


def verify_decision() -> int:
    root, capture, _plugin, capture_id, promotion_id = _source_context()
    text = capture.read_text(encoding="utf-8")
    decision = _scalar(text, "promotion_decision")
    recorded_promotion_id = _scalar(text, "promotion_id")
    receipt_path = root / ".locks" / "promotions" / f"{promotion_id}.json"

    if decision == "keep-local":
        if recorded_promotion_id is not None:
            raise PromotionError("keep-local decision must not carry a promotion_id")
        if receipt_path.exists():
            raise PromotionError("keep-local decision conflicts with a promotion receipt")
        return 0
    if decision != "promoted":
        raise PromotionError("selective capture has no terminal promotion decision")
    if recorded_promotion_id != promotion_id:
        raise PromotionError("promoted decision has an invalid deterministic promotion_id")

    receipt = _read_json(receipt_path)
    if receipt is None or receipt.get("status") != "published":
        raise PromotionError("promoted decision has no published receipt")
    if receipt.get("source_capture_id") != capture_id:
        raise PromotionError("published receipt source identity mismatch")
    main_value = receipt.get("main_wiki")
    target_name = receipt.get("target_name")
    if not isinstance(main_value, str) or not isinstance(target_name, str):
        raise PromotionError("published receipt lacks its durable target")
    target = _existing_target(Path(main_value).resolve(), target_name)
    if target is None:
        raise PromotionError("published promotion target is no longer durable")
    _validate_existing(target, capture_id, promotion_id)
    return 0


def publish(title: str, body_file: str) -> int:
    root, capture, plugin, capture_id, promotion_id = _source_context()
    if not title.strip() or "\n" in title or len(title) > 160:
        raise PromotionError("promotion title must be one line of 1 to 160 characters")
    body_path = Path(body_file).expanduser().resolve()
    try:
        body = body_path.read_text(encoding="utf-8")
    except OSError as exc:
        raise PromotionError(f"cannot read promotion body: {body_path}: {exc}") from exc
    if len(body.encode("utf-8")) < 1500:
        raise PromotionError("promotion body must contain at least 1500 bytes of reusable detail")

    main = _main_wiki()
    state_dir = root / ".locks" / "promotions"
    state_dir.mkdir(parents=True, exist_ok=True)
    lock_path = state_dir / f"{promotion_id}.lock"
    receipt_path = state_dir / f"{promotion_id}.json"
    with lock_path.open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        source_decision = _scalar(
            capture.read_text(encoding="utf-8"), "promotion_decision"
        )
        source_promotion_id = _scalar(
            capture.read_text(encoding="utf-8"), "promotion_id"
        )
        if source_decision == "keep-local":
            raise PromotionError("keep-local is terminal and cannot become promoted")
        if source_decision == "promoted" and source_promotion_id != promotion_id:
            raise PromotionError("source capture has a conflicting promotion identity")
        receipt = _read_json(receipt_path)
        if receipt is not None:
            if receipt.get("source_capture_id") != capture_id:
                raise PromotionError("promotion receipt source identity mismatch")
            pinned_main = Path(str(receipt.get("main_wiki", ""))).resolve()
            if pinned_main != main:
                raise PromotionError("main wiki pointer changed after promotion intent")
            target_name = str(receipt.get("target_name", ""))
            captured_at = str(receipt.get("captured_at", ""))
        else:
            recovered = _existing_target_by_promotion_id(main, promotion_id)
            if recovered is not None:
                _validate_existing(recovered, capture_id, promotion_id)
                target_name = recovered.name.removesuffix(".processing")
                captured_at = _scalar(recovered.read_text(encoding="utf-8"), "captured_at")
                if not captured_at:
                    raise PromotionError(f"promotion target lacks captured_at at {recovered}")
            else:
                captured_at = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")
                target_name = f"{captured_at}-{promotion_id}.md"
            receipt = {
                "promotion_id": promotion_id,
                "source_capture_id": capture_id,
                "main_wiki": str(main),
                "target_name": target_name,
                "captured_at": captured_at,
                "status": "intent",
            }
            _atomic_write(receipt_path, json.dumps(receipt, indent=2, sort_keys=True) + "\n")

        if (
            os.environ.get("WIKI_PROMOTION_TEST_MODE") == "1"
            and os.environ.get("WIKI_PROMOTION_TEST_FAIL_AFTER_INTENT") == "1"
        ):
            raise PromotionError("injected failure after promotion intent")

        target = _existing_target(main, target_name)
        if target is None:
            content = _derived_capture(
                title=title.strip(),
                body=body,
                capture_id=capture_id,
                promotion_id=promotion_id,
                captured_at=captured_at,
            )
            final = main / ".wiki-pending" / target_name
            temp_handle = tempfile.NamedTemporaryFile(
                mode="w", encoding="utf-8", dir=final.parent, prefix=".promotion.", delete=False
            )
            temp = Path(temp_handle.name)
            try:
                with temp_handle:
                    temp_handle.write(content)
                    temp_handle.flush()
                    os.fsync(temp_handle.fileno())
                os.chmod(temp, 0o644)
                try:
                    os.link(temp, final)
                except FileExistsError:
                    pass
            finally:
                temp.unlink(missing_ok=True)
            target = _existing_target(main, target_name)
            if target is None:
                raise PromotionError("atomic main capture publication failed")
        _validate_existing(target, capture_id, promotion_id)

        if (
            os.environ.get("WIKI_PROMOTION_TEST_MODE") == "1"
            and os.environ.get("WIKI_PROMOTION_TEST_FAIL_AFTER_PUBLISH") == "1"
        ):
            raise PromotionError("injected failure after promotion publication")

        _set_scalars(
            capture,
            {"promotion_decision": "promoted", "promotion_id": promotion_id},
        )
        receipt["status"] = "published"
        receipt["published_path"] = str(target.relative_to(main))
        _atomic_write(receipt_path, json.dumps(receipt, indent=2, sort_keys=True) + "\n")

    dispatch = plugin / "scripts" / "wiki_dispatch.py"
    result = subprocess.run(
        [sys.executable, str(dispatch), "tick", "--wiki", str(main), "--source", "capture"],
        check=False,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.PIPE,
        text=True,
        env=os.environ.copy(),
    )
    if result.returncode != 0:
        detail = result.stderr.strip() or "dispatcher unavailable"
        print(f"wiki promote: main capture saved; dispatch deferred: {detail}", file=sys.stderr)
    return 0


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="wiki-promote-capture.py")
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("keep-local")
    subparsers.add_parser("verify")
    publish_parser = subparsers.add_parser("publish")
    publish_parser.add_argument("--title", required=True)
    publish_parser.add_argument("--body-file", required=True)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv or sys.argv[1:])
    try:
        if args.command == "keep-local":
            return keep_local()
        if args.command == "verify":
            return verify_decision()
        return publish(args.title, args.body_file)
    except (PromotionError, OSError) as exc:
        print(f"wiki promote: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
