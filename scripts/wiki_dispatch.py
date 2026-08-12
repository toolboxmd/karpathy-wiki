#!/usr/bin/env python3
"""Bounded, one-shot dispatcher for karpathy-wiki ingest captures.

The dispatcher owns queue claims and per-wiki process slots. Provider command
construction and semantic ingest work are intentionally separate concerns.
"""

from __future__ import annotations

import argparse
import concurrent.futures
from datetime import datetime, timezone
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import signal
import shutil
import subprocess
import sys
import tempfile
import time
from typing import Any, TextIO

from wiki_config import ConfigError, validate_runtime_config
from wiki_providers import (
    ProviderError,
    ProviderInvocation,
    build_provider_invocation,
    classify_provider_result,
    redact_diagnostic_file,
    resolve_executable,
)
from wiki_usage import check_codexbar_usage


AUTOMATIC_SOURCE_MODES = {
    "session_start": "session_start",
    "scheduled": "scheduled",
}
ALWAYS_ALLOWED_SOURCES = {"manual", "capture", "worker_completion"}
ALL_SOURCES = set(AUTOMATIC_SOURCE_MODES) | ALWAYS_ALLOWED_SOURCES


class DispatchError(RuntimeError):
    """A dispatcher failure safe to show without a traceback."""


class WorkerInterrupted(BaseException):
    """Internal signal used to guarantee worker cleanup."""


def _utc_now() -> str:
    return datetime.now(timezone.utc).isoformat().replace("+00:00", "Z")


def read_run_events(wiki: str | Path) -> tuple[list[dict[str, Any]], int]:
    """Read complete valid JSONL events and count malformed/partial records."""

    path = Path(wiki) / ".ingest-runs.jsonl"
    try:
        raw = path.read_bytes()
    except FileNotFoundError:
        return [], 0
    except OSError as exc:
        raise DispatchError(f"wiki dispatch: cannot read run history: {exc}") from exc

    malformed = 0
    chunks = raw.split(b"\n")
    if raw and not raw.endswith(b"\n"):
        chunks.pop()
        malformed += 1
    elif chunks and chunks[-1] == b"":
        chunks.pop()

    events: list[dict[str, Any]] = []
    for chunk in chunks:
        if not chunk.strip():
            continue
        try:
            event = json.loads(chunk.decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            malformed += 1
            continue
        if not isinstance(event, dict):
            malformed += 1
            continue
        events.append(event)
    return events, malformed


def append_run_event(
    wiki: str | Path,
    event: dict[str, Any],
    *,
    idempotent_terminal: bool = False,
) -> bool:
    """Append one locked JSONL event; optionally deduplicate run+status."""

    root = Path(wiki)
    lock_path = root / ".locks" / "ingest-runs.lock"
    log_path = root / ".ingest-runs.jsonl"
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    encoded = json.dumps(event, sort_keys=True, separators=(",", ":"))
    if len(encoded.encode("utf-8")) > 4095:
        raise DispatchError("wiki dispatch: run event exceeds 4095 bytes")

    with lock_path.open("a+", encoding="utf-8") as lock:
        fcntl.flock(lock.fileno(), fcntl.LOCK_EX)
        if idempotent_terminal:
            events, _malformed = read_run_events(root)
            if any(
                previous.get("run_id") == event.get("run_id")
                and previous.get("status") == event.get("status")
                for previous in events
            ):
                return False

        with log_path.open("a+b") as handle:
            handle.seek(0, os.SEEK_END)
            if handle.tell() > 0:
                handle.seek(-1, os.SEEK_END)
                if handle.read(1) != b"\n":
                    handle.seek(0, os.SEEK_END)
                    handle.write(b"\n")
            handle.seek(0, os.SEEK_END)
            handle.write(encoded.encode("utf-8") + b"\n")
            handle.flush()
            os.fsync(handle.fileno())
    return True


def _capture_event_name(processing_name: str) -> str:
    suffix = ".processing"
    return processing_name[: -len(suffix)] if processing_name.endswith(suffix) else processing_name


def _next_attempt(root: Path, capture_name: str) -> int:
    events, _malformed = read_run_events(root)
    attempts = [
        event.get("attempt")
        for event in events
        if event.get("capture") == capture_name
        and event.get("status") == "transient_failure"
        and isinstance(event.get("attempt"), int)
    ]
    return max(attempts, default=0) + 1


def _future_retry(value: Any) -> datetime | None:
    if not isinstance(value, str) or not value:
        return None
    try:
        parsed = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed if parsed > datetime.now(timezone.utc) else None


def _cooling_profiles(root: Path, ingest: dict[str, Any]) -> set[str]:
    """Return profiles with a still-active rate-limit/reset window."""

    events, _malformed = read_run_events(root)
    cooling_until: dict[str, datetime] = {}
    for event in events:
        profile_name = event.get("profile")
        if profile_name not in ingest["profiles"]:
            continue
        profile = ingest["profiles"][profile_name]
        if event.get("provider") != profile["provider"]:
            continue
        if event.get("model") != profile["model"]:
            continue
        if event.get("status") in {
            "provider_rate_limited",
            "usage_preflight_exhausted",
            "configuration_or_auth_failure",
        }:
            retry = _future_retry(event.get("retry_after"))
            if retry is not None and retry > cooling_until.get(
                profile_name, datetime.min.replace(tzinfo=timezone.utc)
            ):
                cooling_until[profile_name] = retry
    # A concurrent run can complete after another run on the same profile has
    # opened a cooldown. Completion is therefore never evidence that the
    # provider is available again; only expiry or a profile/model change is.
    return set(cooling_until)


def _usage_preflight_profiles(
    root: Path,
    ingest: dict[str, Any],
    candidates: list[str],
) -> set[str]:
    if ingest["usage_monitor"] == "off" or not candidates:
        return set()
    executable = os.environ.get("WIKI_CODEXBAR_EXECUTABLE", "codexbar")
    timeout = ingest["usage_monitor_timeout_seconds"]

    def inspect(name: str) -> tuple[str, Any]:
        usage_provider = ingest["profiles"][name]["usage_provider"]
        return name, check_codexbar_usage(
            usage_provider, timeout, executable=executable
        )

    results: list[tuple[str, Any]] = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(candidates)) as pool:
        futures = [pool.submit(inspect, name) for name in candidates]
        for future in futures:
            try:
                results.append(future.result())
            except Exception:
                # Monitoring is optional; unexpected monitor failures are
                # treated exactly like an unavailable CodexBar installation.
                continue

    exhausted: set[str] = set()
    for name, result in results:
        if not result.monitor_available or not result.exhausted:
            continue
        reset = _future_retry(result.resets_at)
        if result.resets_at is not None and reset is None:
            # Stale usage output whose reset is already past is not evidence
            # that the provider is unavailable now.
            continue
        retry_at = (
            reset
            if reset is not None
            else datetime.fromtimestamp(
                time.time() + ingest["rate_limit_retry_seconds"], timezone.utc
            )
        )
        retry_text = retry_at.isoformat().replace("+00:00", "Z")
        profile = ingest["profiles"][name]
        digest = hashlib.sha256(
            f"{name}\0{profile['provider']}\0{profile['model']}\0{retry_text}".encode()
        ).hexdigest()[:16]
        append_run_event(
            root,
            {
                "run_id": f"usage-{digest}",
                "capture": None,
                "status": "usage_preflight_exhausted",
                "profile": name,
                "provider": profile["provider"],
                "model": profile["model"],
                "retry_after": retry_text,
                "at": _utc_now(),
            },
            idempotent_terminal=True,
        )
        exhausted.add(name)
    return exhausted


def _write_json_atomic(path: Path, payload: dict[str, Any], mode: int = 0o600) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, raw_temp = tempfile.mkstemp(prefix=f".{path.name}.tmp-", dir=path.parent)
    temp = Path(raw_temp)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(payload, handle, sort_keys=True, separators=(",", ":"))
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp, mode)
        os.replace(temp, path)
    finally:
        temp.unlink(missing_ok=True)


def _read_lease(path: Path) -> dict[str, Any] | None:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError):
        return None
    return data if isinstance(data, dict) else None


def _pid_alive(pid: Any) -> bool:
    if isinstance(pid, bool) or not isinstance(pid, int) or pid < 1:
        return False
    try:
        os.kill(pid, 0)
    except ProcessLookupError:
        return False
    except PermissionError:
        return True
    return True


def _pending_from_processing(processing: Path) -> Path | None:
    if not processing.name.endswith(".processing"):
        return None
    return processing.with_name(processing.name[: -len(".processing")])


def _requeue_processing(processing: Path) -> bool:
    pending = _pending_from_processing(processing)
    if pending is None or not processing.is_file():
        return False
    if pending.exists():
        return False
    try:
        os.replace(processing, pending)
    except FileNotFoundError:
        return False
    return True


def _capture_needs_more_detail(path: Path) -> bool:
    """Recognize the ingester's explicit human-edit deferral marker."""

    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError):
        return False
    if not text.startswith("---\n"):
        return False
    closing = text.find("\n---\n", 4)
    if closing < 0:
        return False
    frontmatter = text[4:closing]
    return re.search(
        r"^needs_more_detail:\s*true\s*$", frontmatter, flags=re.MULTILINE
    ) is not None


def _dispatch_paths(root: Path) -> tuple[Path, Path, Path]:
    lock_root = root / ".locks"
    return (
        lock_root / "ingest-dispatch.lock",
        lock_root / "ingest-slots",
        root / ".wiki-pending",
    )


def _try_dispatch_lock(path: Path) -> TextIO | None:
    path.parent.mkdir(parents=True, exist_ok=True)
    handle = path.open("a+", encoding="utf-8")
    try:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        handle.close()
        return None
    return handle


def _blocking_dispatch_lock(path: Path) -> TextIO:
    path.parent.mkdir(parents=True, exist_ok=True)
    handle = path.open("a+", encoding="utf-8")
    fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
    return handle


def _source_allowed(source: str, dispatch_mode: str) -> bool:
    if source in ALWAYS_ALLOWED_SOURCES:
        return True
    return AUTOMATIC_SOURCE_MODES.get(source) == dispatch_mode


def _processing_path(root: Path, capture_value: Any) -> Path | None:
    if not isinstance(capture_value, str):
        return None
    name = Path(capture_value).name
    if name != capture_value or not name.endswith(".md.processing"):
        return None
    return root / ".wiki-pending" / name


def _lease_archive_path(root: Path, lease: dict[str, Any]) -> Path | None:
    value = lease.get("expected_archive")
    if not isinstance(value, str):
        return None
    relative = Path(value)
    if relative.is_absolute() or ".." in relative.parts:
        return None
    candidate = (root / relative).resolve()
    archive_root = (root / ".wiki-pending" / "archive").resolve()
    try:
        candidate.relative_to(archive_root)
    except ValueError:
        return None
    return candidate


def _reconcile_dead_leases(root: Path, slot_root: Path, stale_after: int) -> None:
    """Recover stale dead leases without duplicating a live provider."""

    for lease_path in sorted(slot_root.glob("*.lock")):
        lease = _read_lease(lease_path)
        if lease is None:
            # An unreadable lease is safer left for explicit diagnosis than
            # silently ignored and counted as free capacity.
            continue
        processing = _processing_path(root, lease.get("capture"))
        wrapper_alive = _pid_alive(lease.get("wrapper_pid"))
        provider_alive = _pid_alive(lease.get("provider_pid"))
        heartbeat_stale = False
        if processing is not None and processing.exists():
            try:
                heartbeat_stale = time.time() - processing.stat().st_mtime > stale_after
            except FileNotFoundError:
                heartbeat_stale = False

        if wrapper_alive or provider_alive:
            if heartbeat_stale:
                append_run_event(
                    root,
                    {
                        "run_id": lease.get("run_id"),
                        "capture": _capture_event_name(str(lease.get("capture", ""))),
                        "status": "heartbeat_stalled",
                        "profile": lease.get("profile"),
                        "at": _utc_now(),
                    },
                    idempotent_terminal=True,
                )
            continue

        archive = _lease_archive_path(root, lease)
        if (processing is None or not processing.exists()) and archive is not None and archive.is_file():
            append_run_event(
                root,
                {
                    "run_id": lease.get("run_id"),
                    "capture": _capture_event_name(str(lease.get("capture", ""))),
                    "status": "completed",
                    "profile": lease.get("profile"),
                    "provider": lease.get("provider"),
                    "attempt": lease.get("attempt", 1),
                    "at": _utc_now(),
                    "recovered": True,
                },
                idempotent_terminal=True,
            )
            lease_path.unlink(missing_ok=True)
            continue

        if processing is not None and processing.exists() and not heartbeat_stale:
            # The wrapper may have exited in the instant before its cleanup.
            # Preserve the slot until the heartbeat crosses the stale threshold.
            continue
        if processing is not None:
            _requeue_processing(processing)
        lease_path.unlink(missing_ok=True)


def _valid_leases(slot_root: Path) -> list[tuple[Path, dict[str, Any]]]:
    leases: list[tuple[Path, dict[str, Any]]] = []
    for path in sorted(slot_root.glob("*.lock")):
        data = _read_lease(path)
        if data is not None:
            leases.append((path, data))
        else:
            # Corrupt state consumes capacity instead of allowing an unsafe
            # extra ingest. It is surfaced later by status/doctor.
            leases.append((path, {"profile": None, "slot": None}))
    return leases


def _select_profile(
    ingest: dict[str, Any],
    leases: list[tuple[Path, dict[str, Any]]],
    unavailable: set[str] | None = None,
) -> str | None:
    unavailable = unavailable or set()
    names = [ingest["default_profile"]]
    fallback = ingest.get("fallback_profile")
    if fallback:
        names.append(fallback)
    for name in names:
        if name in unavailable:
            continue
        profile_limit = ingest["profiles"][name]["max_processes"]
        active = sum(1 for _path, lease in leases if lease.get("profile") == name)
        if active < profile_limit:
            return name
    return None


def _free_slot(leases: list[tuple[Path, dict[str, Any]]], maximum: int) -> int | None:
    used = {
        lease.get("slot")
        for _path, lease in leases
        if isinstance(lease.get("slot"), int)
    }
    for slot in range(1, maximum + 1):
        if slot not in used:
            return slot
    return None


def _test_mode() -> bool:
    return os.environ.get("WIKI_DISPATCH_TEST_MODE") == "1"


def _spawn_worker(
    root: Path,
    lease_path: Path,
    processing: Path,
    run_id: str,
    profile: str,
) -> subprocess.Popen[bytes]:
    if _test_mode() and os.environ.get("WIKI_DISPATCH_TEST_SPAWN_FAILURE") == "1":
        raise OSError("injected worker spawn failure")

    command = [
        sys.executable,
        str(Path(__file__).resolve()),
        "worker",
        "--wiki",
        str(root),
        "--lease",
        str(lease_path),
        "--capture",
        str(processing),
        "--run-id",
        run_id,
        "--profile",
        profile,
    ]
    log_path = root / ".ingest.log"
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with log_path.open("ab", buffering=0) as log:
        return subprocess.Popen(
            command,
            stdin=subprocess.DEVNULL,
            stdout=log,
            stderr=log,
            close_fds=True,
            start_new_session=True,
            env=os.environ.copy(),
        )


def _run_source_scan(root: Path) -> None:
    scanner = Path(__file__).resolve().parent / "wiki-scan.sh"
    try:
        result = subprocess.run(
            ["/bin/bash", str(scanner), str(root)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
            text=True,
            timeout=120,
            check=False,
            env=os.environ.copy(),
        )
    except subprocess.TimeoutExpired as exc:
        raise DispatchError("wiki dispatch: source scan timed out after 120 seconds") from exc
    if result.returncode != 0:
        detail = (result.stderr or "scanner exited without diagnostics").strip()
        raise DispatchError(f"wiki dispatch: source scan failed: {detail[:1000]}")


def dispatch_tick(
    root: Path,
    config: dict[str, Any],
    source: str,
    *,
    scan: bool = False,
) -> int:
    ingest = config["ingest"]
    if not _source_allowed(source, ingest["dispatch_mode"]):
        return 0
    if scan:
        if source not in {"session_start", "scheduled", "manual"}:
            raise DispatchError(
                f"wiki dispatch: source {source!r} cannot request a source scan"
            )
        _run_source_scan(root)

    unavailable_profiles: set[str] = set()
    if not _test_mode():
        for name, profile in ingest["profiles"].items():
            try:
                resolve_executable(
                    profile["executable"],
                    forbidden_roots=(Path(config["trusted_workspace"]),),
                )
            except ProviderError:
                unavailable_profiles.add(name)
        configured = [ingest["default_profile"]]
        if ingest.get("fallback_profile"):
            configured.append(ingest["fallback_profile"])
        if all(name in unavailable_profiles for name in configured):
            details = ", ".join(configured)
            raise DispatchError(
                f"wiki dispatch: no configured ingest profile has an available executable: {details}"
            )

    configured = [ingest["default_profile"]]
    if ingest.get("fallback_profile"):
        configured.append(ingest["fallback_profile"])
    unavailable_profiles.update(_cooling_profiles(root, ingest))
    monitor_candidates = [
        name for name in configured if name not in unavailable_profiles
    ]
    unavailable_profiles.update(
        _usage_preflight_profiles(root, ingest, monitor_candidates)
    )
    if all(name in unavailable_profiles for name in configured):
        return 0

    lock_path, slot_root, pending_root = _dispatch_paths(root)
    dispatch_lock = _try_dispatch_lock(lock_path)
    if dispatch_lock is None:
        return 0

    spawn_error: OSError | None = None
    try:
        slot_root.mkdir(parents=True, exist_ok=True)
        _reconcile_dead_leases(root, slot_root, ingest["stale_after_seconds"])
        leases = _valid_leases(slot_root)
        captures = sorted(
            (
                path
                for path in pending_root.glob("*.md")
                if not _capture_needs_more_detail(path)
            ),
            key=lambda path: path.name,
        )

        if _test_mode():
            remove_name = os.environ.get("WIKI_DISPATCH_TEST_REMOVE_AFTER_SCAN")
            if remove_name and Path(remove_name).name == remove_name:
                (pending_root / remove_name).unlink(missing_ok=True)

        capture_index = 0
        while len(leases) < ingest["max_processes"] and capture_index < len(captures):
            profile = _select_profile(ingest, leases, unavailable_profiles)
            slot = _free_slot(leases, ingest["max_processes"])
            if profile is None or slot is None:
                break

            pending = captures[capture_index]
            capture_index += 1
            if not pending.is_file():
                continue
            processing = pending.with_name(f"{pending.name}.processing")
            run_id = f"in-{int(time.time() * 1_000_000)}-{os.getpid()}-{slot}"
            lease_path = slot_root / f"{slot}.lock"
            archive_relative = Path(".wiki-pending") / "archive" / datetime.now().astimezone().strftime("%Y-%m") / pending.name
            lease = {
                "run_id": run_id,
                "slot": slot,
                "capture": processing.name,
                "profile": profile,
                "provider": ingest["profiles"][profile]["provider"],
                "attempt": _next_attempt(root, pending.name),
                "expected_archive": str(archive_relative),
                "wrapper_pid": 0,
                "provider_pid": None,
                "started_at": _utc_now(),
            }
            try:
                fd = os.open(lease_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
                with os.fdopen(fd, "w", encoding="utf-8") as handle:
                    json.dump(lease, handle, sort_keys=True, separators=(",", ":"))
                    handle.write("\n")
                    handle.flush()
                    os.fsync(handle.fileno())
            except FileExistsError:
                leases = _valid_leases(slot_root)
                continue

            try:
                os.replace(pending, processing)
            except FileNotFoundError:
                lease_path.unlink(missing_ok=True)
                continue

            try:
                worker = _spawn_worker(
                    root, lease_path, processing, run_id, profile
                )
            except OSError as exc:
                _requeue_processing(processing)
                lease_path.unlink(missing_ok=True)
                spawn_error = exc
                break

            lease["wrapper_pid"] = worker.pid
            _write_json_atomic(lease_path, lease)
            leases.append((lease_path, lease))
    finally:
        fcntl.flock(dispatch_lock.fileno(), fcntl.LOCK_UN)
        dispatch_lock.close()

    if spawn_error is not None:
        raise DispatchError(f"wiki dispatch: worker spawn failed: {spawn_error}")
    return 0


def _worker_cleanup(
    root: Path,
    lease_path: Path,
    processing: Path,
    run_id: str,
    *,
    requeue: bool,
) -> None:
    lock_path, _slot_root, _pending_root = _dispatch_paths(root)
    dispatch_lock = _blocking_dispatch_lock(lock_path)
    try:
        lease = _read_lease(lease_path)
        if lease is None or lease.get("run_id") != run_id:
            return
        if requeue:
            _requeue_processing(processing)
        lease_path.unlink(missing_ok=True)
    finally:
        fcntl.flock(dispatch_lock.fileno(), fcntl.LOCK_UN)
        dispatch_lock.close()


def _await_parent_lease(lease_path: Path, run_id: str) -> dict[str, Any]:
    deadline = time.monotonic() + 3
    while time.monotonic() < deadline:
        lease = _read_lease(lease_path)
        if (
            lease is not None
            and lease.get("run_id") == run_id
            and lease.get("wrapper_pid") == os.getpid()
        ):
            return lease
        time.sleep(0.01)
    raise DispatchError("wiki dispatch worker: parent did not finalize the slot lease")


def _update_worker_lease(
    lease_path: Path, run_id: str, **updates: Any
) -> dict[str, Any]:
    lease = _read_lease(lease_path)
    if lease is None or lease.get("run_id") != run_id:
        raise DispatchError("wiki dispatch worker: slot lease no longer belongs to this run")
    lease.update(updates)
    _write_json_atomic(lease_path, lease)
    return lease


def _test_provider_command(root: Path) -> tuple[list[str], str]:
    mode = os.environ.get("WIKI_DISPATCH_TEST_PROVIDER_MODE", "")
    if not mode and "WIKI_DISPATCH_TEST_WORKER_HOLD_SECONDS" in os.environ:
        mode = "hold"
    if not mode:
        raise DispatchError("wiki dispatch worker: test provider mode is required")
    if mode == "hold":
        seconds = os.environ.get(
            "WIKI_DISPATCH_TEST_PROVIDER_SECONDS",
            os.environ.get("WIKI_DISPATCH_TEST_WORKER_HOLD_SECONDS", "1"),
        )
        try:
            float(seconds)
        except ValueError as exc:
            raise DispatchError("invalid test provider duration") from exc
        code = (
            "import os,pathlib,sys,time; "
            "p=os.environ.get('WIKI_DISPATCH_TEST_PROVIDER_PID_FILE'); "
            "pathlib.Path(p).write_text(str(os.getpid())) if p else None; "
            "time.sleep(float(sys.argv[1]))"
        )
        return [sys.executable, "-c", code, seconds], mode
    if mode == "success_no_complete":
        return [sys.executable, "-c", "raise SystemExit(0)"], mode
    if mode == "complete_success":
        helper = Path(__file__).resolve().parent / "wiki-complete-ingest.sh"
        return ["/bin/bash", str(helper)], mode
    if mode == "needs_more_detail":
        code = (
            "import os,pathlib; "
            "p=pathlib.Path(os.environ['WIKI_CAPTURE']); "
            "pending=p.with_name(p.name.removesuffix('.processing')); "
            "pending.write_text('---\\nneeds_more_detail: true\\n' "
            "+ 'needs_more_detail_reason: \\\"test deferral\\\"\\n---\\n'); "
            "p.unlink()"
        )
        return [sys.executable, "-c", code], mode
    if mode == "transient_failure":
        return [sys.executable, "-c", "raise SystemExit(1)"], mode
    if mode == "rate_limited":
        return [sys.executable, "-c", "raise SystemExit(75)"], mode
    raise DispatchError(f"unknown test provider mode: {mode}")


def _provider_environment(root: Path, processing: Path, run_id: str) -> dict[str, str]:
    environment = os.environ.copy()
    environment.update(
        {
            "WIKI_ROOT": str(root),
            "WIKI_CAPTURE": str(processing),
            "WIKI_RUN_ID": run_id,
            "WIKI_PLUGIN_ROOT": str(Path(__file__).resolve().parent.parent),
        }
    )
    return environment


def _read_diagnostic_tail(path: Path, limit: int = 2 * 1024 * 1024) -> str:
    try:
        with path.open("rb") as handle:
            handle.seek(0, os.SEEK_END)
            size = handle.tell()
            handle.seek(max(0, size - limit), os.SEEK_SET)
            return handle.read().decode("utf-8", errors="replace")
    except FileNotFoundError:
        return ""


def _redact_retained_invocation(invocation: ProviderInvocation | None) -> None:
    if invocation is None:
        return
    redact_diagnostic_file(invocation.stdout_path)
    redact_diagnostic_file(invocation.stderr_path)
    if invocation.output_last_message_path is not None:
        redact_diagnostic_file(invocation.output_last_message_path)


def _completed_event_present(root: Path, run_id: str) -> bool:
    events, _malformed = read_run_events(root)
    return any(
        event.get("run_id") == run_id and event.get("status") == "completed"
        for event in events
    )


def _move_processing_to_failed(root: Path, processing: Path) -> Path | None:
    if not processing.is_file():
        return None
    pending = _pending_from_processing(processing)
    if pending is None:
        return None
    failed_root = root / ".wiki-pending" / "failed"
    failed_root.mkdir(parents=True, exist_ok=True)
    target = failed_root / pending.name
    if target.exists():
        raise DispatchError(f"wiki dispatch worker: failed capture already exists: {target}")
    os.replace(processing, target)
    return target


def _refill_after_worker(root: Path, config: dict[str, Any]) -> None:
    if _test_mode() and os.environ.get("WIKI_DISPATCH_TEST_NO_REFILL") == "1":
        return
    dispatch_tick(root, config, "worker_completion")


def _terminate_provider_group(
    child: subprocess.Popen[bytes] | None, timeout: float = 2
) -> None:
    """Stop an unfinished detached provider and every process it launched."""

    if child is None or child.poll() is not None:
        return
    try:
        os.killpg(child.pid, signal.SIGTERM)
    except ProcessLookupError:
        return
    except OSError:
        child.terminate()
    try:
        child.wait(timeout=timeout)
        return
    except subprocess.TimeoutExpired:
        pass
    try:
        os.killpg(child.pid, signal.SIGKILL)
    except ProcessLookupError:
        return
    except OSError:
        child.kill()
    child.wait()


def run_worker(
    root: Path,
    lease_path: Path,
    processing: Path,
    run_id: str,
    profile_name: str,
) -> int:
    child: subprocess.Popen[bytes] | None = None

    def interrupted(_signum: int, _frame: Any) -> None:
        raise WorkerInterrupted()

    signal.signal(signal.SIGTERM, interrupted)
    signal.signal(signal.SIGINT, interrupted)

    config = validate_runtime_config(root)
    ingest = config["ingest"]
    if profile_name not in ingest["profiles"]:
        raise DispatchError(f"wiki dispatch worker: unknown profile {profile_name!r}")
    lease = _await_parent_lease(lease_path, run_id)
    attempt = lease.get("attempt", 1)
    if not isinstance(attempt, int) or attempt < 1:
        raise DispatchError("wiki dispatch worker: invalid attempt in slot lease")
    capture_name = _capture_event_name(processing.name)
    profile = ingest["profiles"][profile_name]
    base_event = {
        "run_id": run_id,
        "capture": capture_name,
        "profile": profile_name,
        "provider": profile["provider"],
        "model": profile["model"],
        "attempt": attempt,
    }

    append_run_event(root, {**base_event, "status": "started", "at": _utc_now()})

    try:
        invocation: ProviderInvocation | None = None
        test_provider_mode = ""
        stdin_bytes: bytes | None = None
        if _test_mode():
            command, test_provider_mode = _test_provider_command(root)
            provider_env = _provider_environment(root, processing, run_id)
            log_path = root / ".ingest.log"
            stdout_handle = log_path.open("ab", buffering=0)
            stderr_handle = stdout_handle
        else:
            runtime_profile = dict(profile)
            runtime_profile["executable"] = resolve_executable(
                profile["executable"],
                forbidden_roots=(Path(config["trusted_workspace"]),),
            )
            invocation = build_provider_invocation(
                runtime_profile,
                root,
                processing,
                run_id,
                Path(__file__).resolve().parent.parent,
            )
            command = invocation.argv
            provider_env = os.environ.copy()
            provider_env.update(invocation.environment)
            stdin_bytes = invocation.stdin_bytes
            stdout_handle = invocation.stdout_path.open("wb", buffering=0)
            stderr_handle = invocation.stderr_path.open("wb", buffering=0)

        try:
            try:
                child = subprocess.Popen(
                    command,
                    cwd=root,
                    env=provider_env,
                    stdin=subprocess.PIPE if stdin_bytes is not None else subprocess.DEVNULL,
                    stdout=stdout_handle,
                    stderr=stderr_handle,
                    close_fds=True,
                    start_new_session=True,
                )
            except OSError as exc:
                raise DispatchError(f"wiki dispatch worker: provider spawn failed: {exc}") from exc
            _update_worker_lease(
                lease_path,
                run_id,
                provider_pid=child.pid,
                heartbeat_at=_utc_now(),
            )
            if stdin_bytes is not None:
                if child.stdin is None:
                    raise DispatchError("wiki dispatch worker: provider stdin pipe missing")
                try:
                    child.stdin.write(stdin_bytes)
                    child.stdin.flush()
                except BrokenPipeError:
                    pass
                finally:
                    child.stdin.close()

            heartbeat = float(ingest["heartbeat_seconds"])
            if _test_mode() and "WIKI_DISPATCH_TEST_HEARTBEAT_SECONDS" in os.environ:
                try:
                    heartbeat = float(os.environ["WIKI_DISPATCH_TEST_HEARTBEAT_SECONDS"])
                except ValueError as exc:
                    raise DispatchError("invalid test heartbeat duration") from exc
                if heartbeat <= 0:
                    raise DispatchError("test heartbeat duration must be positive")

            while True:
                try:
                    exit_code = child.wait(timeout=heartbeat)
                    break
                except subprocess.TimeoutExpired:
                    try:
                        os.utime(processing, None)
                    except FileNotFoundError:
                        pass
                    if _test_mode() and os.environ.get(
                        "WIKI_DISPATCH_TEST_FAIL_HEARTBEAT"
                    ) == "1":
                        raise DispatchError(
                            "wiki dispatch worker: injected heartbeat failure"
                        )
                    _update_worker_lease(
                        lease_path,
                        run_id,
                        provider_pid=child.pid,
                        heartbeat_at=_utc_now(),
                    )
        finally:
            stdout_handle.close()
            if stderr_handle is not stdout_handle:
                stderr_handle.close()

        archive = _lease_archive_path(root, lease)
        lifecycle_complete = (
            exit_code == 0
            and not processing.exists()
            and archive is not None
            and archive.is_file()
        )
        if lifecycle_complete:
            append_run_event(
                root,
                {**base_event, "status": "completed", "exit_code": 0, "at": _utc_now()},
                idempotent_terminal=True,
            )
            if not _completed_event_present(root, run_id):
                raise DispatchError("wiki dispatch worker: completion event could not be verified")
            _worker_cleanup(root, lease_path, processing, run_id, requeue=False)
            if invocation is not None and os.environ.get(
                "WIKI_DISPATCH_ACCEPTANCE_RETAIN_ARTIFACTS"
            ) != "1":
                shutil.rmtree(invocation.run_dir, ignore_errors=True)
            _refill_after_worker(root, config)
            return 0

        pending = _pending_from_processing(processing)
        explicitly_deferred = (
            exit_code == 0
            and not processing.exists()
            and pending is not None
            and pending.is_file()
            and _capture_needs_more_detail(pending)
        )
        if explicitly_deferred:
            append_run_event(
                root,
                {
                    **base_event,
                    "status": "needs_more_detail",
                    "exit_code": 0,
                    "at": _utc_now(),
                },
                idempotent_terminal=True,
            )
            _worker_cleanup(root, lease_path, processing, run_id, requeue=False)
            if invocation is not None and os.environ.get(
                "WIKI_DISPATCH_ACCEPTANCE_RETAIN_ARTIFACTS"
            ) != "1":
                shutil.rmtree(invocation.run_dir, ignore_errors=True)
            # Refill other work; marked captures are filtered until a human
            # expands the body and removes the deferral fields.
            _refill_after_worker(root, config)
            return 0

        if invocation is not None:
            result_class = classify_provider_result(
                invocation.provider,
                exit_code,
                _read_diagnostic_tail(invocation.stdout_path),
                _read_diagnostic_tail(invocation.stderr_path),
            )
        elif test_provider_mode == "rate_limited":
            result_class = "provider_rate_limited"
        else:
            result_class = "transient_failure"

        if result_class == "provider_rate_limited":
            _redact_retained_invocation(invocation)
            retry_at = datetime.fromtimestamp(
                time.time() + ingest["rate_limit_retry_seconds"], timezone.utc
            ).isoformat().replace("+00:00", "Z")
            append_run_event(
                root,
                {
                    **base_event,
                    "status": "provider_rate_limited",
                    "exit_code": exit_code,
                    "retry_after": retry_at,
                    "at": _utc_now(),
                },
            )
            _worker_cleanup(root, lease_path, processing, run_id, requeue=True)
            _refill_after_worker(root, config)
            return 0

        if result_class == "configuration_or_auth_failure":
            _redact_retained_invocation(invocation)
            retry_at = datetime.fromtimestamp(
                time.time() + ingest["rate_limit_retry_seconds"], timezone.utc
            ).isoformat().replace("+00:00", "Z")
            append_run_event(
                root,
                {
                    **base_event,
                    "status": "configuration_or_auth_failure",
                    "exit_code": exit_code,
                    "retry_after": retry_at,
                    "at": _utc_now(),
                },
            )
            _worker_cleanup(root, lease_path, processing, run_id, requeue=True)
            _refill_after_worker(root, config)
            return 1

        _redact_retained_invocation(invocation)
        append_run_event(
            root,
            {
                **base_event,
                "status": "transient_failure",
                "exit_code": exit_code,
                "at": _utc_now(),
            },
        )
        if attempt >= ingest["max_attempts"]:
            failed_path = _move_processing_to_failed(root, processing)
            append_run_event(
                root,
                {
                    **base_event,
                    "status": "failed",
                    "failed_path": str(failed_path.relative_to(root)) if failed_path else None,
                    "at": _utc_now(),
                },
                idempotent_terminal=True,
            )
            _worker_cleanup(root, lease_path, processing, run_id, requeue=False)
        else:
            _worker_cleanup(root, lease_path, processing, run_id, requeue=True)
        _refill_after_worker(root, config)
        return 1
    except (DispatchError, ProviderError, OSError):
        _terminate_provider_group(child)
        retry_at = datetime.fromtimestamp(
            time.time() + ingest["rate_limit_retry_seconds"], timezone.utc
        ).isoformat().replace("+00:00", "Z")
        try:
            append_run_event(
                root,
                {
                    **base_event,
                    "status": "configuration_or_auth_failure",
                    "retry_after": retry_at,
                    "at": _utc_now(),
                },
            )
        finally:
            _worker_cleanup(root, lease_path, processing, run_id, requeue=True)
        _refill_after_worker(root, config)
        raise
    except WorkerInterrupted:
        _terminate_provider_group(child)
        try:
            append_run_event(
                root,
                {**base_event, "status": "interrupted", "at": _utc_now()},
            )
        finally:
            _worker_cleanup(root, lease_path, processing, run_id, requeue=True)
        return 0


def _parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(prog="wiki_dispatch.py")
    subparsers = parser.add_subparsers(dest="command", required=True)

    tick = subparsers.add_parser("tick")
    tick.add_argument("--wiki", required=True)
    tick.add_argument("--source", required=True, choices=sorted(ALL_SOURCES))
    tick.add_argument("--scan", action="store_true")

    worker = subparsers.add_parser("worker")
    worker.add_argument("--wiki", required=True)
    worker.add_argument("--lease", required=True)
    worker.add_argument("--capture", required=True)
    worker.add_argument("--run-id", required=True)
    worker.add_argument("--profile", required=True)
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = _parse_args(argv or sys.argv[1:])
    try:
        if args.command == "tick":
            config = validate_runtime_config(args.wiki)
            root = Path(config["wiki_root"])
            return dispatch_tick(root, config, args.source, scan=args.scan)

        root = Path(args.wiki).expanduser().resolve()
        lease_path = Path(args.lease).expanduser().resolve()
        processing = Path(args.capture).expanduser().resolve()
        if lease_path.parent != root / ".locks" / "ingest-slots":
            raise DispatchError("wiki dispatch worker: lease is outside the wiki slot directory")
        if processing.parent != root / ".wiki-pending":
            raise DispatchError("wiki dispatch worker: capture is outside the pending directory")
        return run_worker(root, lease_path, processing, args.run_id, args.profile)
    except WorkerInterrupted:
        if args.command == "worker":
            try:
                _worker_cleanup(root, lease_path, processing, args.run_id, requeue=True)
            except Exception:
                pass
        return 0
    except (ConfigError, DispatchError, OSError) as exc:
        if args.command == "worker":
            try:
                _worker_cleanup(root, lease_path, processing, args.run_id, requeue=True)
            except Exception:
                pass
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
