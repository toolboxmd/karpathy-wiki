#!/usr/bin/env python3
"""Render read-only ingest runtime health without hiding content status."""

from __future__ import annotations

from datetime import datetime, timezone
import json
import os
from pathlib import Path
import shutil
import sys
import time
from typing import Any

from wiki_config import ConfigError, validate_runtime_config
from wiki_dispatch import _capture_needs_more_detail, read_run_events
from wiki_scheduler import SchedulerError, status as scheduler_status


def _runtime_error_state(message: str) -> str:
    if "legacy ingest configuration detected" in message:
        return "migration required"
    if "runtime configuration missing" in message:
        return "missing"
    return "invalid"


def _future(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed if parsed > datetime.now(timezone.utc) else None


def _active_cooldowns(
    events: list[dict[str, Any]], ingest: dict[str, Any]
) -> dict[str, str]:
    active: dict[str, datetime] = {}
    for event in events:
        name = event.get("profile")
        if name not in ingest["profiles"]:
            continue
        profile = ingest["profiles"][name]
        if event.get("provider") not in {None, profile["provider"]}:
            continue
        if event.get("model") not in {None, profile["model"]}:
            continue
        if event.get("status") in {
            "provider_rate_limited",
            "usage_preflight_exhausted",
            "configuration_or_auth_failure",
        }:
            retry = _future(event.get("retry_after"))
            if retry is not None and retry > active.get(
                name, datetime.min.replace(tzinfo=timezone.utc)
            ):
                active[name] = retry
    return {
        name: retry.isoformat().replace("+00:00", "Z")
        for name, retry in active.items()
    }


def _active_slots(root: Path, stale_after: int) -> tuple[int, int]:
    slot_root = root / ".locks" / "ingest-slots"
    active = 0
    stalled = 0
    for lease_path in sorted(slot_root.glob("*.lock")):
        active += 1
        try:
            lease = json.loads(lease_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        capture = lease.get("capture")
        if not isinstance(capture, str) or Path(capture).name != capture:
            continue
        processing = root / ".wiki-pending" / capture
        try:
            age = time.time() - processing.stat().st_mtime
        except OSError:
            continue
        if age > stale_after:
            stalled += 1
    return active, stalled


def _usage_monitor_state(ingest: dict[str, Any]) -> str:
    if ingest["usage_monitor"] == "off":
        return "off"
    candidate = os.environ.get("WIKI_CODEXBAR_EXECUTABLE", "codexbar")
    if os.path.isabs(candidate):
        available = Path(candidate).is_file() and os.access(candidate, os.X_OK)
    else:
        available = shutil.which(candidate) is not None
    return "codexbar" if available else "reactive"


def render(wiki: str | Path) -> int:
    root = Path(wiki).expanduser().resolve()
    try:
        config = validate_runtime_config(root)
    except ConfigError as exc:
        message = str(exc)
        print(f"runtime config: {_runtime_error_state(message)}")
        for line in message.splitlines():
            print(line)
        return 0

    ingest = config["ingest"]
    active, stalled = _active_slots(root, ingest["stale_after_seconds"])
    events, malformed = read_run_events(root)
    cooldowns = _active_cooldowns(events, ingest)
    failed = sum(1 for path in (root / ".wiki-pending" / "failed").glob("*.md") if path.is_file())
    needs_more_detail = sum(
        1
        for path in (root / ".wiki-pending").glob("*.md")
        if path.is_file() and _capture_needs_more_detail(path)
    )

    scheduler = "n/a"
    scheduler_action: str | None = None
    scheduler_result: dict[str, Any] = {}
    try:
        scheduler_result = scheduler_status(root)
        raw_state = scheduler_result["state"]
        if raw_state == "unavailable":
            scheduler = "mismatch" if ingest["dispatch_mode"] == "scheduled" else "n/a"
        else:
            scheduler = raw_state
        if scheduler == "mismatch":
            command = "install" if ingest["dispatch_mode"] == "scheduled" else "disable"
            scheduler_action = (
                "wiki scheduler install"
                if command == "install"
                else f"wiki scheduler {command} {root}"
            )
    except (ConfigError, SchedulerError, OSError):
        scheduler = "mismatch" if ingest["dispatch_mode"] == "scheduled" else "n/a"

    fallback = ingest.get("fallback_profile") or "none"
    print("runtime config: configured")
    print(f"dispatch mode: {ingest['dispatch_mode']}")
    print(f"scheduler: {scheduler}")
    if scheduler_action:
        print(f"scheduler action: {scheduler_action}")
    print(f"active ingests: {active} / 1")
    if "active_global_slots" in scheduler_result:
        print(
            "global ingests: "
            f"{scheduler_result['active_global_slots']} / {scheduler_result['max_total_processes']}"
        )
    print(
        f"profiles: default={ingest['default_profile']}, "
        f"fallback={fallback}"
    )
    if cooldowns:
        rendered = ", ".join(
            f"{name} until {retry}" for name, retry in sorted(cooldowns.items())
        )
    else:
        rendered = "none"
    print(f"provider cooldowns: {rendered}")
    print(f"stalled heartbeat: {stalled}")
    print(f"failed captures: {failed}")
    print(f"captures needing more detail: {needs_more_detail}")
    print(f"run history malformed lines: {malformed}")
    print(f"usage monitor: {_usage_monitor_state(ingest)}")
    return 0


def main(argv: list[str]) -> int:
    if len(argv) != 1:
        print("usage: wiki_runtime_status.py <wiki-root>", file=sys.stderr)
        return 1
    return render(argv[0])


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
