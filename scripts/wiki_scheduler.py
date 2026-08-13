#!/usr/bin/env python3
"""Install and inspect the macOS LaunchAgent for one karpathy-wiki root."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile
from typing import Any

from wiki_config import ConfigError, validate_runtime_config


LABEL_PREFIX = "com.toolboxmd.karpathy-wiki"


class SchedulerError(RuntimeError):
    """An actionable scheduler error safe to print to the user."""


def scheduler_identity(wiki: Path, home: Path) -> tuple[str, Path]:
    root = Path(wiki).expanduser().resolve()
    digest = hashlib.sha256(str(root).encode("utf-8")).hexdigest()[:16]
    label = f"{LABEL_PREFIX}.{digest}"
    plist_path = Path(home).expanduser() / "Library" / "LaunchAgents" / f"{label}.plist"
    return label, plist_path


def build_launch_agent(
    wiki: Path,
    wiki_executable: Path,
    label: str,
    interval: int,
    path_value: str,
    runtime_config_home: Path | None = None,
) -> dict[str, Any]:
    root = Path(wiki).expanduser().resolve()
    executable = Path(wiki_executable).expanduser().resolve()
    environment = {"PATH": path_value}
    if runtime_config_home is not None:
        environment["WIKI_CONFIG_HOME"] = str(
            Path(runtime_config_home).expanduser().resolve()
        )
    return {
        "Label": label,
        "ProgramArguments": [
            str(executable),
            "tick",
            str(root),
            "--source",
            "scheduled",
            "--scan",
        ],
        "WorkingDirectory": str(root),
        "StartInterval": interval,
        "RunAtLoad": True,
        "ProcessType": "Background",
        "EnvironmentVariables": environment,
        "StandardOutPath": str(root / ".ingest.log"),
        "StandardErrorPath": str(root / ".ingest.log"),
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
            "adapter currently supports macOS only. Use a portable `wiki tick "
            "<wiki> --source scheduled --scan` in your own scheduler instead."
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


def _is_loaded(executable: str, label: str) -> bool:
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
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout or "no diagnostics").strip()
        raise SchedulerError(f"wiki scheduler: could not update local mode: {detail}")


def _restore_plist(path: Path, previous: bytes | None) -> None:
    if previous is None:
        path.unlink(missing_ok=True)
    else:
        _atomic_write(path, previous)


def install(wiki: str | Path) -> dict[str, Any]:
    config = validate_runtime_config(wiki)
    root = Path(config["wiki_root"])
    launchctl = _launchctl()
    label, plist_path = scheduler_identity(root, _home())
    interval = config["ingest"]["schedule_interval_seconds"]
    runtime_path = Path(config["runtime_config_path"])
    runtime_home = None
    if os.environ.get("WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME") != "1":
        runtime_home = runtime_path.parents[2]
    payload = build_launch_agent(
        root,
        _plugin_root() / "bin" / "wiki",
        label,
        interval,
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

    if was_loaded:
        _run_launchctl(launchctl, ["bootout", f"{_domain()}/{label}"])
    try:
        _atomic_write(plist_path, candidate)
        _run_launchctl(launchctl, ["bootstrap", _domain(), str(plist_path)])
    except Exception:
        _restore_plist(plist_path, previous)
        if was_loaded and previous is not None:
            _run_launchctl(
                launchctl, ["bootstrap", _domain(), str(plist_path)], check=False
            )
        raise

    try:
        _update_mode(root, "scheduled")
    except Exception:
        _run_launchctl(
            launchctl, ["bootout", f"{_domain()}/{label}"], check=False
        )
        _restore_plist(plist_path, previous)
        if was_loaded and previous is not None:
            _run_launchctl(
                launchctl, ["bootstrap", _domain(), str(plist_path)], check=False
            )
        raise

    return {
        "state": "installed",
        "wiki": str(root),
        "label": label,
        "plist": str(plist_path),
        "configured_mode": "scheduled",
        "loaded": True,
        "interval_seconds": interval,
    }


def uninstall(wiki: str | Path) -> dict[str, Any]:
    config = validate_runtime_config(wiki)
    root = Path(config["wiki_root"])
    launchctl = _launchctl()
    label, plist_path = scheduler_identity(root, _home())
    try:
        previous = plist_path.read_bytes()
    except FileNotFoundError:
        previous = None
    except OSError as exc:
        raise SchedulerError(f"wiki scheduler: cannot read {plist_path}: {exc}") from exc
    was_loaded = _is_loaded(launchctl, label)

    if was_loaded:
        _run_launchctl(launchctl, ["bootout", f"{_domain()}/{label}"])
    plist_path.unlink(missing_ok=True)
    try:
        _update_mode(root, "session_start")
    except Exception:
        _restore_plist(plist_path, previous)
        if was_loaded and previous is not None:
            _run_launchctl(
                launchctl, ["bootstrap", _domain(), str(plist_path)], check=False
            )
        raise

    return {
        "state": "not installed",
        "wiki": str(root),
        "label": label,
        "plist": str(plist_path),
        "configured_mode": "session_start",
        "loaded": False,
        "interval_seconds": config["ingest"]["schedule_interval_seconds"],
    }


def status(wiki: str | Path) -> dict[str, Any]:
    config = validate_runtime_config(wiki)
    root = Path(config["wiki_root"])
    label, plist_path = scheduler_identity(root, _home())
    mode = config["ingest"]["dispatch_mode"]
    launchctl = os.environ.get("WIKI_LAUNCHCTL_EXECUTABLE") or shutil.which("launchctl")
    loaded: bool | None = None
    if launchctl:
        loaded = _is_loaded(launchctl, label)
    plist_exists = plist_path.is_file()
    installed = plist_exists and loaded is True

    if launchctl is None:
        state = "unavailable"
    elif mode == "scheduled" and installed:
        state = "installed"
    elif mode == "session_start" and not plist_exists and not loaded:
        state = "not installed"
    else:
        state = "mismatch"

    return {
        "state": state,
        "wiki": str(root),
        "label": label,
        "plist": str(plist_path),
        "plist_exists": plist_exists,
        "configured_mode": mode,
        "loaded": loaded,
        "interval_seconds": config["ingest"]["schedule_interval_seconds"],
        "launchctl_available": launchctl is not None,
    }


def _print_human(result: dict[str, Any]) -> None:
    loaded = result.get("loaded")
    loaded_text = "unavailable" if loaded is None else ("yes" if loaded else "no")
    print(f"state: {result['state']}")
    print(f"configured mode: {result['configured_mode']}")
    print(f"loaded: {loaded_text}")
    print(f"interval: {result['interval_seconds']} seconds")
    print(f"label: {result['label']}")
    print(f"plist: {result['plist']}")
    if result["state"] == "mismatch":
        print("action: run `wiki scheduler install <wiki>` or `wiki scheduler uninstall <wiki>`")
    elif result["state"] == "unavailable":
        print("action: use a portable scheduled `wiki tick <wiki> --source scheduled --scan`")


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    for command in ("install", "uninstall", "status"):
        child = subparsers.add_parser(command)
        child.add_argument("--wiki", required=True)
        child.add_argument("--json", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv or sys.argv[1:])
    try:
        if args.command == "install":
            result = install(args.wiki)
        elif args.command == "uninstall":
            result = uninstall(args.wiki)
        else:
            result = status(args.wiki)
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
