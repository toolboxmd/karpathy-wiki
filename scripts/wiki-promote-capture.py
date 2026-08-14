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
import stat
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


def _without_yaml_inline_comment(value: str) -> str:
    """Remove an unquoted YAML comment while preserving quoted hash characters."""
    single_quoted = False
    double_quoted = False
    escaped = False
    for index, character in enumerate(value):
        if double_quoted and character == "\\" and not escaped:
            escaped = True
            continue
        if character == '"' and not single_quoted and not escaped:
            double_quoted = not double_quoted
        elif character == "'" and not double_quoted:
            single_quoted = not single_quoted
        elif (
            character == "#"
            and not single_quoted
            and not double_quoted
            and (index == 0 or value[index - 1].isspace())
        ):
            return value[:index].rstrip()
        escaped = False
    return value


def _scalar(text: str, key: str) -> str | None:
    lines, closing = _frontmatter(text)
    pattern = re.compile(rf"^{re.escape(key)}:\s*(.*?)\s*$")
    matches: list[str] = []
    for line in lines[1:closing]:
        match = pattern.match(line.rstrip("\r\n"))
        if not match:
            continue
        matches.append(match.group(1))
    if len(matches) > 1:
        raise PromotionError(f"duplicate authoritative frontmatter key: {key}")
    if not matches:
        return None
    value = _without_yaml_inline_comment(matches[0])
    if value in {"null", "~", ""}:
        return None
    if len(value) >= 2 and value[0] == value[-1] == '"':
        try:
            decoded = json.loads(value)
        except json.JSONDecodeError as exc:
            raise PromotionError(f"invalid JSON-compatible scalar for {key}") from exc
        if not isinstance(decoded, str):
            raise PromotionError(f"frontmatter scalar {key} must be a string")
        return decoded
    if len(value) >= 2 and value[0] == value[-1] == "'":
        return value[1:-1]
    return value


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


def _remove_scalars(path: Path, keys: set[str]) -> None:
    text = path.read_text(encoding="utf-8")
    lines, closing = _frontmatter(text)
    filtered = [lines[0]]
    filtered.extend(
        line for line in lines[1:closing] if line.split(":", 1)[0].strip() not in keys
    )
    filtered.extend(lines[closing:])
    if filtered != lines:
        _atomic_write(path, "".join(filtered))


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


def _config_home() -> Path:
    override = os.environ.get("WIKI_CONFIG_HOME")
    if override:
        return Path(override).expanduser().resolve()
    xdg = os.environ.get("XDG_CONFIG_HOME")
    if xdg:
        return (Path(xdg).expanduser() / "karpathy-wiki").resolve()
    return (Path.home() / ".config" / "karpathy-wiki").resolve()


def _is_within(path: Path, parent: Path) -> bool:
    try:
        path.relative_to(parent)
        return True
    except ValueError:
        return False


def _workspace_identity(root: Path) -> Path:
    parent_pointer = root.parent / ".wiki-config"
    try:
        text = parent_pointer.read_text(encoding="utf-8")
    except OSError:
        text = ""
    target = re.search(r'^wiki\s*=\s*"(.*)"\s*$', text, flags=re.MULTILINE)
    if re.search(r'^role\s*=\s*"project-pointer"\s*$', text, flags=re.MULTILINE) and target:
        candidate = Path(target.group(1)).expanduser()
        if not candidate.is_absolute():
            candidate = root.parent / candidate
        if candidate.resolve() == root:
            return root.parent.resolve()
    result = subprocess.run(
        ["git", "-C", str(root), "rev-parse", "--show-toplevel"],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=False,
    )
    return Path(result.stdout.strip()).resolve() if result.returncode == 0 else root


def _pin_path(root: Path, promotion_id: str) -> tuple[Path, Path]:
    workspace = _workspace_identity(root)
    identity = hashlib.sha256(str(root).encode("utf-8")).hexdigest()
    return _config_home() / "promotions" / identity / f"{promotion_id}.json", workspace


def _ensure_private_pin_parent(path: Path, root: Path, main: Path | None = None) -> None:
    base = _config_home()
    if _is_within(path, root) or (main is not None and _is_within(path, main)):
        raise PromotionError("promotion pin store must be outside all wiki checkouts")
    for directory in (base, base / "promotions", path.parent):
        directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        info = directory.lstat()
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISDIR(info.st_mode):
            raise PromotionError(f"promotion pin directory is not a regular directory: {directory}")
        if hasattr(os, "getuid") and info.st_uid != os.getuid():
            raise PromotionError(f"promotion pin directory has the wrong owner: {directory}")
        os.chmod(directory, 0o700)


def _atomic_write_private(path: Path, value: dict[str, Any], root: Path, main: Path) -> None:
    _ensure_private_pin_parent(path, root, main)
    if path.exists() or path.is_symlink():
        info = path.lstat()
        if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
            raise PromotionError(f"promotion pin is not a regular file: {path}")
    handle = tempfile.NamedTemporaryFile(
        mode="w", encoding="utf-8", dir=path.parent, prefix=f".{path.name}.", delete=False
    )
    temp = Path(handle.name)
    try:
        with handle:
            json.dump(value, handle, indent=2, sort_keys=True)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp, 0o600)
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)


def _read_pin(root: Path, capture_id: str, promotion_id: str) -> dict[str, Any] | None:
    path, _workspace = _pin_path(root, promotion_id)
    if not path.exists() and not path.is_symlink():
        return None
    _ensure_private_pin_parent(path, root)
    info = path.lstat()
    if stat.S_ISLNK(info.st_mode) or not stat.S_ISREG(info.st_mode):
        raise PromotionError(f"promotion pin is not a regular file: {path}")
    if hasattr(os, "getuid") and info.st_uid != os.getuid():
        raise PromotionError(f"promotion pin has the wrong owner: {path}")
    if info.st_mode & 0o077:
        raise PromotionError(f"promotion pin must have mode 0600: {path}")
    pin = _read_json(path)
    expected = {
        "schema_version": 1,
        "source_capture_id": capture_id,
        "promotion_id": promotion_id,
        "canonical_project_wiki": str(root),
    }
    if pin is None or any(pin.get(key) != value for key, value in expected.items()):
        raise PromotionError("promotion pin canonical identity mismatch")
    if not isinstance(pin.get("canonical_workspace"), str) or not pin["canonical_workspace"]:
        raise PromotionError("promotion pin lacks its historical canonical workspace")
    main_value, target_name = pin.get("canonical_main_wiki"), pin.get("target_name")
    if not isinstance(main_value, str) or not isinstance(target_name, str):
        raise PromotionError("promotion pin lacks its canonical target")
    if not re.fullmatch(rf"\d{{4}}-\d{{2}}-\d{{2}}T\d{{2}}-\d{{2}}-\d{{2}}Z-{re.escape(promotion_id)}\.md", target_name):
        raise PromotionError("promotion pin target name mismatch")
    return pin


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


def _validate_main_wiki(main: Path) -> Path:
    main = main.expanduser().resolve()
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
    return _validate_main_wiki(Path(value))


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
    try:
        return _validate_main_wiki(Path(value))
    except PromotionError:
        # This lookup is only a defensive search for a publication that might
        # predate durable intent. With no receipt or source pin, an unavailable
        # current pointer is not evidence that a publication target exists.
        return None


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


def _pin_target(pin: dict[str, Any], capture_id: str, promotion_id: str) -> tuple[Path, str, str]:
    main = _validate_main_wiki(Path(str(pin["canonical_main_wiki"])))
    target_name = str(pin["target_name"])
    captured_at = str(pin.get("created_at", ""))
    if not captured_at or target_name != f"{captured_at}-{promotion_id}.md":
        raise PromotionError("promotion pin creation identity mismatch")
    target = _existing_target(main, target_name)
    if target is not None:
        _validate_existing(target, capture_id, promotion_id)
    return main, target_name, captured_at


def _receipt_for_pin(pin: dict[str, Any], status: str) -> dict[str, Any]:
    return {
        "promotion_id": pin["promotion_id"],
        "source_capture_id": pin["source_capture_id"],
        "main_wiki": pin["canonical_main_wiki"],
        "target_name": pin["target_name"],
        "captured_at": pin["created_at"],
        "status": status,
    }


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
        _remove_scalars(capture, {"promotion_main_wiki"})
        if _read_json(state_dir / f"{promotion_id}.json") is not None:
            raise PromotionError("promotion intent already exists and cannot become keep-local")
        if _read_pin(root, capture_id, promotion_id) is not None:
            raise PromotionError("trusted promotion intent already exists and cannot become keep-local")
        source_text = capture.read_text(encoding="utf-8")
        decision = _scalar(source_text, "promotion_decision")
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
    state_dir = root / ".locks" / "promotions"
    state_dir.mkdir(parents=True, exist_ok=True)
    receipt_path = state_dir / f"{promotion_id}.json"
    with (state_dir / f"{promotion_id}.lock").open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        _remove_scalars(capture, {"promotion_main_wiki"})
        text = capture.read_text(encoding="utf-8")
        decision = _scalar(text, "promotion_decision")
        recorded_promotion_id = _scalar(text, "promotion_id")

        if decision == "keep-local":
            if recorded_promotion_id is not None:
                raise PromotionError("keep-local decision must not carry a promotion_id")
            if receipt_path.exists() or _read_pin(root, capture_id, promotion_id) is not None:
                raise PromotionError("keep-local decision conflicts with promotion intent")
            return 0
        if decision != "promoted":
            raise PromotionError("selective capture has no terminal promotion decision")
        if recorded_promotion_id != promotion_id:
            raise PromotionError("promoted decision has an invalid deterministic promotion_id")

        pin = _read_pin(root, capture_id, promotion_id)
        if pin is None:
            raise PromotionError("promoted decision has no trusted promotion pin")
        main, target_name, _captured_at = _pin_target(pin, capture_id, promotion_id)
        existing_receipt = _read_json(receipt_path)
        if existing_receipt is not None and any(
            existing_receipt.get(key) != expected
            for key, expected in _receipt_for_pin(pin, existing_receipt.get("status", "")).items()
            if key != "status"
        ):
            raise PromotionError("promotion receipt conflicts with trusted promotion pin")
        target = _existing_target(main, target_name)
        if target is None:
            raise PromotionError("published promotion target is no longer durable")
        receipt = _receipt_for_pin(pin, "published")
        receipt["published_path"] = str(target.relative_to(main))
        _atomic_write(receipt_path, json.dumps(receipt, indent=2, sort_keys=True) + "\n")
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
    body = body.rstrip()
    if len(body.encode("utf-8")) < 1500:
        raise PromotionError("promotion body must contain at least 1500 bytes of reusable detail")

    state_dir = root / ".locks" / "promotions"
    state_dir.mkdir(parents=True, exist_ok=True)
    lock_path = state_dir / f"{promotion_id}.lock"
    receipt_path = state_dir / f"{promotion_id}.json"
    with lock_path.open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        # Compatibility only: this tracked field existed on review branches but
        # is contributor-controlled and is never publication authority.
        _remove_scalars(capture, {"promotion_main_wiki"})
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
        pin_path, workspace = _pin_path(root, promotion_id)
        pin = _read_pin(root, capture_id, promotion_id)
        if pin is None:
            main = _main_wiki()
            recovered = _existing_target_by_promotion_id(main, promotion_id)
            captured_at = (
                _scalar(recovered.read_text(encoding="utf-8"), "captured_at")
                if recovered is not None
                else datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M-%SZ")
            )
            if not captured_at:
                raise PromotionError("existing promotion target lacks captured_at")
            target_name = (
                recovered.name.removesuffix(".processing")
                if recovered is not None
                else f"{captured_at}-{promotion_id}.md"
            )
            pin = {
                "schema_version": 1,
                "source_capture_id": capture_id,
                "promotion_id": promotion_id,
                "canonical_project_wiki": str(root),
                "canonical_workspace": str(workspace),
                "canonical_main_wiki": str(main),
                "target_name": target_name,
                "created_at": captured_at,
            }
            _atomic_write_private(pin_path, pin, root, main)
        main, target_name, captured_at = _pin_target(pin, capture_id, promotion_id)

        if (
            os.environ.get("WIKI_PROMOTION_TEST_MODE") == "1"
            and os.environ.get("WIKI_PROMOTION_TEST_FAIL_AFTER_PIN") == "1"
        ):
            raise PromotionError("injected failure after trusted promotion pin")

        if receipt is not None:
            if receipt.get("source_capture_id") != capture_id:
                raise PromotionError("promotion receipt source identity mismatch")
            pinned_main = Path(str(receipt.get("main_wiki", ""))).resolve()
            if pinned_main != main:
                raise PromotionError("promotion receipt conflicts with pinned main wiki")
            if receipt.get("target_name") != target_name or receipt.get("captured_at") != captured_at:
                raise PromotionError("promotion receipt conflicts with trusted promotion pin")
        else:
            receipt = _receipt_for_pin(pin, "intent")
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
