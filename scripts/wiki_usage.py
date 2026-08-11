#!/usr/bin/env python3
"""Optional CodexBar usage preflight with conservative failure semantics."""

from __future__ import annotations

from dataclasses import dataclass
import json
import os
from pathlib import Path
import shutil
import subprocess
from typing import Any


@dataclass(frozen=True)
class UsageResult:
    monitor_available: bool
    exhausted: bool
    resets_at: str | None = None
    reason: str = ""


def _unavailable(reason: str) -> UsageResult:
    return UsageResult(False, False, None, reason)


def _records(payload: Any) -> list[dict[str, Any]]:
    if isinstance(payload, dict):
        return [payload]
    if isinstance(payload, list):
        return [item for item in payload if isinstance(item, dict)]
    return []


def parse_codexbar_usage(text: str, provider: str) -> UsageResult:
    """Return only availability/exhaustion; never retain account identity."""

    try:
        payload = json.loads(text)
    except (json.JSONDecodeError, TypeError):
        return _unavailable("malformed usage output")
    matches = [
        record for record in _records(payload) if record.get("provider") == provider
    ]
    if not matches:
        return _unavailable("provider missing from usage output")

    windows: list[dict[str, Any]] = []
    for record in matches:
        usage = record.get("usage")
        if not isinstance(usage, dict):
            continue
        for name in ("primary", "secondary", "tertiary"):
            window = usage.get(name)
            if isinstance(window, dict):
                windows.append(window)
    if not windows:
        return _unavailable("no active usage windows")

    exhausted_resets: list[str] = []
    exhausted = False
    for window in windows:
        used = window.get("usedPercent")
        explicit_state = str(window.get("status", window.get("state", ""))).lower()
        window_exhausted = (
            isinstance(used, (int, float))
            and not isinstance(used, bool)
            and used >= 100
        ) or explicit_state in {"exhausted", "limit_reached", "rate_limited"}
        if not window_exhausted:
            continue
        exhausted = True
        reset = window.get("resetsAt")
        if isinstance(reset, str) and reset:
            exhausted_resets.append(reset)

    # `pace.willLastToReset` is intentionally ignored: it predicts future
    # depletion and is not evidence that the provider is unavailable now.
    return UsageResult(
        monitor_available=True,
        exhausted=exhausted,
        resets_at=max(exhausted_resets) if exhausted_resets else None,
        reason="explicit active-window exhaustion" if exhausted else "active window available",
    )


def _resolve_optional_executable(executable: str) -> str | None:
    expanded = os.path.expanduser(executable)
    if os.sep in expanded:
        path = Path(expanded).resolve()
        if path.is_file() and os.access(path, os.X_OK):
            return str(path)
        return None
    return shutil.which(expanded)


def check_codexbar_usage(
    provider: str,
    timeout_seconds: float,
    *,
    executable: str = "codexbar",
) -> UsageResult:
    """Run CodexBar briefly; every monitor failure means reactive fallback."""

    resolved = _resolve_optional_executable(executable)
    if resolved is None:
        return _unavailable("CodexBar not installed")
    try:
        result = subprocess.run(
            [resolved, "usage", "--provider", provider, "--format", "json"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout_seconds,
            check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return _unavailable("CodexBar unavailable")
    if result.returncode != 0:
        return _unavailable("CodexBar returned non-zero")
    return parse_codexbar_usage(result.stdout, provider)
