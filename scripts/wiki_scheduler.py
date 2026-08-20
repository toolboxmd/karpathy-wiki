#!/usr/bin/env python3
"""Install, inspect, and run the machine-wide karpathy-wiki scheduler."""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
import time
from typing import Any

from wiki_config import (
    ConfigError,
    ensure_scheduler_runtime_config,
    enumerate_trusted_wiki_runtimes,
    scheduler_config_path,
    scheduler_slot_root,
    scheduler_state_path,
    validate_runtime_config,
)


GLOBAL_SCHEDULER_LABEL = "com.toolboxmd.karpathy-wiki.scheduler"
LEGACY_LABEL_PREFIX = "com.toolboxmd.karpathy-wiki."


class SchedulerError(RuntimeError):
    """An actionable scheduler error safe to print to the user."""


def scheduler_identity(home: Path) -> tuple[str, Path]:
    root = Path(home).expanduser()
    plist_path = root / "Library" / "LaunchAgents" / f"{GLOBAL_SCHEDULER_LABEL}.plist"
    return GLOBAL_SCHEDULER_LABEL, plist_path


def build_launch_agent(
    wiki_executable: Path,
    label: str,
    interval: int,
    path_value: str,
    runtime_config_home: Path | None = None,
) -> dict[str, Any]:
    executable = Path(wiki_executable).expanduser().resolve()
    config_home = (
        Path(runtime_config_home).expanduser().resolve()
        if runtime_config_home is not None
        else scheduler_config_path().parents[1].resolve()
    )
    log_path = config_home / "scheduler" / "scheduler.log"
    environment = {"PATH": path_value}
    if runtime_config_home is not None:
        environment["WIKI_CONFIG_HOME"] = str(config_home)
    return {
        "Label": label,
        "ProgramArguments": [str(executable), "scheduler", "tick-all"],
        "WorkingDirectory": str(Path.home()),
        "StartInterval": interval,
        "RunAtLoad": True,
        "ProcessType": "Background",
        "EnvironmentVariables": environment,
        "StandardOutPath": str(log_path),
        "StandardErrorPath": str(log_path),
    }


def _plugin_root() -> Path:
    return Path(__file__).resolve().parent.parent


def _home() -> Path:
    raw = os.environ.get("HOME")
    if not raw:
        raise SchedulerError("wiki scheduler: HOME is not set")
    return Path(raw).expanduser()


def _launchctl() -> str:
    configured = os.environ.get("WIKI_LAUNCHCTL_EXECUTABLE")
    executable = configured or shutil.which("launchctl")
    if not executable:
        raise SchedulerError(
            "wiki scheduler: launchctl is unavailable; the built-in scheduled "
            "adapter currently supports macOS only. Use a portable `wiki "
            "scheduler tick-all` in your own scheduler instead."
        )
    return executable


def _domain() -> str:
    return f"gui/{os.getuid()}"


def _run_launchctl(
    executable: str, arguments: list[str], *, check: bool = True
) -> subprocess.CompletedProcess[str]:
    try:
        result = subprocess.run(
            [executable, *arguments],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired) as exc:
        raise SchedulerError(f"wiki scheduler: launchctl failed: {exc}") from exc
    if check and result.returncode != 0:
        detail = (result.stderr or result.stdout or "no diagnostics").strip()
        raise SchedulerError(
            f"wiki scheduler: launchctl {' '.join(arguments[:1])} failed "
            f"(exit {result.returncode}): {detail[:1000]}"
        )
    return result


def _is_loaded(executable: str, label: str = GLOBAL_SCHEDULER_LABEL) -> bool:
    result = _run_launchctl(
        executable, ["print", f"{_domain()}/{label}"], check=False
    )
    return result.returncode == 0


def _plist_bytes(payload: dict[str, Any]) -> bytes:
    encoded = plistlib.dumps(payload, fmt=plistlib.FMT_XML, sort_keys=True)
    decoded = plistlib.loads(encoded)
    if decoded != payload:
        raise SchedulerError("wiki scheduler: generated LaunchAgent failed validation")
    return encoded


def _atomic_write(path: Path, content: bytes, mode: int = 0o644) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, raw_temp = tempfile.mkstemp(prefix=f".{path.name}.tmp-", dir=path.parent)
    temp = Path(raw_temp)
    try:
        with os.fdopen(descriptor, "wb") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp, mode)
        os.replace(temp, path)
    except Exception:
        temp.unlink(missing_ok=True)
        raise


def _update_mode(root: Path, mode: str) -> None:
    tool = _plugin_root() / "scripts" / "wiki_config.py"
    result = subprocess.run(
        [
            sys.executable,
            str(tool),
            "update-runtime",
            "--wiki",
            str(root),
            "--dispatch-mode",
            mode,
        ],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=False,
        env=os.environ.copy(),
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "no diagnostics").strip()
        raise SchedulerError(f"wiki scheduler: could not update local mode: {detail}")


def _restore_plist(path: Path, previous: bytes | None) -> None:
    if previous is None:
        path.unlink(missing_ok=True)
    else:
        _atomic_write(path, previous)


def _legacy_plists(home: Path) -> list[Path]:
    launch_agents = home / "Library" / "LaunchAgents"
    if not launch_agents.is_dir():
        return []
    return sorted(
        path
        for path in launch_agents.glob(f"{LEGACY_LABEL_PREFIX}*.plist")
        if path.name != f"{GLOBAL_SCHEDULER_LABEL}.plist"
    )


def install_global() -> dict[str, Any]:
    scheduler = ensure_scheduler_runtime_config()["scheduler"]
    launchctl = _launchctl()
    label, plist_path = scheduler_identity(_home())
    runtime_home = scheduler_config_path().parents[1]
    payload = build_launch_agent(
        _plugin_root() / "bin" / "wiki",
        label,
        scheduler["interval_seconds"],
        os.environ.get("PATH", "/usr/local/bin:/usr/bin:/bin"),
        runtime_home,
    )
    candidate = _plist_bytes(payload)
    try:
        previous = plist_path.read_bytes()
    except FileNotFoundError:
        previous = None
    except OSError as exc:
        raise SchedulerError(f"wiki scheduler: cannot read {plist_path}: {exc}") from exc

    was_loaded = _is_loaded(launchctl, label)
    legacy = _legacy_plists(_home())
    legacy_bytes: dict[Path, bytes] = {}
    legacy_loaded: list[Path] = []
    for path in legacy:
        try:
            legacy_bytes[path] = path.read_bytes()
        except OSError:
            continue
        legacy_label = path.stem
        if _is_loaded(launchctl, legacy_label):
            legacy_loaded.append(path)

    if was_loaded:
        _run_launchctl(launchctl, ["bootout", f"{_domain()}/{label}"])
    for path in legacy_loaded:
        _run_launchctl(launchctl, ["bootout", f"{_domain()}/{path.stem}"], check=False)

    try:
        _atomic_write(plist_path, candidate)
        _run_launchctl(launchctl, ["bootstrap", _domain(), str(plist_path)])
        for path in legacy:
            path.unlink(missing_ok=True)
    except Exception:
        _restore_plist(plist_path, previous)
        if was_loaded and previous is not None:
            _run_launchctl(
                launchctl, ["bootstrap", _domain(), str(plist_path)], check=False
            )
        for path, content in legacy_bytes.items():
            _atomic_write(path, content)
        for path in legacy_loaded:
            _run_launchctl(
                launchctl, ["bootstrap", _domain(), str(path)], check=False
            )
        raise

    return {
        "state": "installed",
        "label": label,
        "plist": str(plist_path),
        "loaded": True,
        "interval_seconds": scheduler["interval_seconds"],
        "max_total_processes": scheduler["max_total_processes"],
        "max_processes_per_wiki": scheduler["max_processes_per_wiki"],
        "legacy_removed": len(legacy),
    }


def enable(wiki: str | Path) -> dict[str, Any]:
    config = validate_runtime_config(wiki)
    root = Path(config["wiki_root"])
    _update_mode(root, "scheduled")
    return {"state": "enabled", "wiki": str(root), "configured_mode": "scheduled"}


def disable(wiki: str | Path) -> dict[str, Any]:
    config = validate_runtime_config(wiki)
    root = Path(config["wiki_root"])
    _update_mode(root, "session_start")
    return {"state": "disabled", "wiki": str(root), "configured_mode": "session_start"}


def uninstall_global(*, force: bool = False) -> dict[str, Any]:
    scheduled = [
        record
        for record in enumerate_trusted_wiki_runtimes()
        if record.get("valid")
        and record.get("config", {}).get("ingest", {}).get("dispatch_mode") == "scheduled"
    ]
    if scheduled and not force:
        raise SchedulerError(
            "wiki scheduler uninstall: scheduled wikis remain enabled; "
            "disable them first or pass --force"
        )
    launchctl = _launchctl()
    label, plist_path = scheduler_identity(_home())
    was_loaded = _is_loaded(launchctl, label)
    if was_loaded:
        _run_launchctl(launchctl, ["bootout", f"{_domain()}/{label}"])
    plist_path.unlink(missing_ok=True)
    return {
        "state": "not installed",
        "label": label,
        "plist": str(plist_path),
        "loaded": False,
    }


def _global_status() -> dict[str, Any]:
    scheduler = ensure_scheduler_runtime_config()["scheduler"]
    label, plist_path = scheduler_identity(_home())
    launchctl = os.environ.get("WIKI_LAUNCHCTL_EXECUTABLE") or shutil.which("launchctl")
    loaded: bool | None = None
    if launchctl:
        loaded = _is_loaded(launchctl, label)
    plist_exists = plist_path.is_file()
    if launchctl is None:
        state = "unavailable"
    elif plist_exists and loaded:
        state = "installed"
    elif not plist_exists and not loaded:
        state = "not installed"
    else:
        state = "mismatch"

    records = enumerate_trusted_wiki_runtimes()
    valid = [record for record in records if record.get("valid")]
    scheduled = [
        record
        for record in valid
        if record["config"]["ingest"]["dispatch_mode"] == "scheduled"
    ]
    active_slots = len(list(scheduler_slot_root().glob("*.lock"))) if scheduler_slot_root().exists() else 0
    return {
        "state": state,
        "label": label,
        "plist": str(plist_path),
        "plist_exists": plist_exists,
        "loaded": loaded,
        "interval_seconds": scheduler["interval_seconds"],
        "max_total_processes": scheduler["max_total_processes"],
        "max_processes_per_wiki": scheduler["max_processes_per_wiki"],
        "active_global_slots": active_slots,
        "registered_wikis": len(valid),
        "scheduled_wikis": len(scheduled),
        "invalid_wikis": len([record for record in records if not record.get("valid")]),
        "launchctl_available": launchctl is not None,
    }


def status(wiki: str | Path | None = None) -> dict[str, Any]:
    global_state = _global_status()
    if wiki is None:
        return global_state
    config = validate_runtime_config(wiki)
    root = Path(config["wiki_root"])
    mode = config["ingest"]["dispatch_mode"]
    if mode == "scheduled" and global_state["state"] == "installed":
        state = "installed"
    elif mode == "session_start":
        state = "session_start"
    else:
        state = "mismatch"
    return {
        **global_state,
        "state": state,
        "wiki": str(root),
        "configured_mode": mode,
        "pending_count": len(list((root / ".wiki-pending").glob("*.md"))),
        "active_slot": (root / ".locks" / "ingest-slots" / "1.lock").is_file(),
        "profile": config["ingest"]["default_profile"],
        "schedule_interval_seconds": config["ingest"]["schedule_interval_seconds"],
    }


def _read_state() -> dict[str, Any]:
    path = scheduler_state_path()
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}
    return data if isinstance(data, dict) else {}


def _write_state(data: dict[str, Any]) -> None:
    path = scheduler_state_path()
    path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, raw_temp = tempfile.mkstemp(prefix=f".{path.name}.tmp-", dir=path.parent)
    temp = Path(raw_temp)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, sort_keys=True, separators=(",", ":"))
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp, 0o600)
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)


def _due_records(records: list[dict[str, Any]], state: dict[str, Any]) -> list[dict[str, Any]]:
    now = time.time()
    last_runs = state.get("last_runs")
    if not isinstance(last_runs, dict):
        last_runs = {}
    due: list[dict[str, Any]] = []
    for record in records:
        if not record.get("valid"):
            continue
        config = record["config"]
        if config["ingest"]["dispatch_mode"] != "scheduled":
            continue
        root = config["wiki_root"]
        last = last_runs.get(root)
        interval = config["ingest"]["schedule_interval_seconds"]
        if not isinstance(last, (int, float)) or now - float(last) >= interval:
            due.append(record)
    return due


def _rotate(records: list[dict[str, Any]], cursor: str | None) -> list[dict[str, Any]]:
    ordered = sorted(records, key=lambda record: record["config"]["wiki_root"])
    if not ordered or cursor is None:
        return ordered
    for index, record in enumerate(ordered):
        if record["config"]["wiki_root"] > cursor:
            return ordered[index:] + ordered[:index]
    return ordered


def tick_all() -> dict[str, Any]:
    scheduler = ensure_scheduler_runtime_config()["scheduler"]
    state = _read_state()
    records = _due_records(enumerate_trusted_wiki_runtimes(), state)
    ordered = _rotate(records, state.get("cursor") if isinstance(state.get("cursor"), str) else None)
    last_runs = state.get("last_runs")
    if not isinstance(last_runs, dict):
        last_runs = {}
    attempted = 0
    errors: list[dict[str, str]] = []
    from wiki_dispatch import dispatch_tick

    for record in ordered:
        if len(list(scheduler_slot_root().glob("*.lock"))) >= scheduler["max_total_processes"]:
            break
        config = record["config"]
        root = Path(config["wiki_root"])
        try:
            dispatch_tick(root, config, "scheduled", scan=True)
            attempted += 1
            last_runs[config["wiki_root"]] = time.time()
            state["cursor"] = config["wiki_root"]
        except Exception as exc:
            errors.append({"wiki": config["wiki_root"], "error": str(exc)})
    state["last_runs"] = last_runs
    state["updated_at"] = datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")
    _write_state(state)
    return {
        "state": "ok",
        "attempted_wikis": attempted,
        "errors": errors,
        "max_total_processes": scheduler["max_total_processes"],
        "max_processes_per_wiki": scheduler["max_processes_per_wiki"],
    }


def global_scheduler_installed() -> bool:
    try:
        return _global_status()["state"] == "installed"
    except Exception:
        return False


def _print_human(result: dict[str, Any]) -> None:
    if "message" in result:
        print(result["message"])
    loaded = result.get("loaded")
    if loaded is not None:
        loaded_text = "yes" if loaded else "no"
        print(f"loaded: {loaded_text}")
    for key in (
        "state",
        "configured_mode",
        "interval_seconds",
        "max_total_processes",
        "max_processes_per_wiki",
        "active_global_slots",
        "registered_wikis",
        "scheduled_wikis",
        "invalid_wikis",
        "label",
        "plist",
        "wiki",
        "pending_count",
        "active_slot",
        "profile",
        "attempted_wikis",
    ):
        if key in result:
            print(f"{key.replace('_', ' ')}: {result[key]}")
    if result.get("state") == "mismatch":
        print("action: run `wiki scheduler install`, `wiki scheduler enable <wiki>`, or `wiki scheduler disable <wiki>`")
    elif result.get("state") == "unavailable":
        print("action: use a portable scheduled `wiki scheduler tick-all`")
    for error in result.get("errors", []):
        print(f"invalid: {error.get('wiki')}: {error.get('error')}")


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    install = subparsers.add_parser("install")
    install.add_argument("wiki", nargs="?")
    install.add_argument("--json", action="store_true")

    uninstall = subparsers.add_parser("uninstall")
    uninstall.add_argument("wiki", nargs="?")
    uninstall.add_argument("--force", action="store_true")
    uninstall.add_argument("--json", action="store_true")

    for command in ("enable", "disable"):
        child = subparsers.add_parser(command)
        child.add_argument("wiki")
        child.add_argument("--json", action="store_true")

    status_parser = subparsers.add_parser("status")
    status_parser.add_argument("wiki", nargs="?")
    status_parser.add_argument("--json", action="store_true")

    tick = subparsers.add_parser("tick-all")
    tick.add_argument("--json", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv or sys.argv[1:])
    try:
        if args.command == "install":
            result = install_global()
            if args.wiki:
                enable(args.wiki)
                result["message"] = (
                    "migration notice: `wiki scheduler install <wiki>` now "
                    "installs the one machine scheduler and enables that wiki"
                )
        elif args.command == "uninstall":
            if args.wiki:
                result = disable(args.wiki)
                result["message"] = "disabled wiki; global scheduler left installed"
            else:
                result = uninstall_global(force=args.force)
        elif args.command == "enable":
            result = enable(args.wiki)
        elif args.command == "disable":
            result = disable(args.wiki)
        elif args.command == "status":
            result = status(args.wiki)
        else:
            result = tick_all()
    except (ConfigError, SchedulerError, OSError) as exc:
        print(str(exc), file=sys.stderr)
        return 1
    if args.json:
        print(json.dumps(result, indent=2, sort_keys=True))
    else:
        _print_human(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
