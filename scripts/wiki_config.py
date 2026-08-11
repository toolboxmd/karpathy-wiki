#!/usr/bin/env python3
"""Load and validate karpathy-wiki structural and per-user runtime config.

The tracked ``.wiki-config`` identifies a wiki. Machine-local ingest settings
live in ignored ``.wiki-config.local``. This module is importable by runtime
scripts and also exposes a small CLI for tests and user-facing wrappers.
"""

from __future__ import annotations

import argparse
from datetime import datetime, timezone
import json
import os
import re
import shlex
import sys
import tempfile
from pathlib import Path
from typing import Any

try:
    import tomllib
except ImportError:  # pragma: no cover - repository already requires 3.11+
    print("python3.11+ required (tomllib not available)", file=sys.stderr)
    raise SystemExit(1)


SUPPORTED_WIKI_ROLES = {"main", "project"}
SUPPORTED_PROVIDERS = {"claude", "codex", "grok"}
SUPPORTED_EFFORTS = {"minimal", "low", "medium", "high", "xhigh", "max"}
SUPPORTED_DISPATCH_MODES = {"session_start", "scheduled"}
SUPPORTED_USAGE_MONITORS = {"auto", "off"}
LEGACY_OPERATIONAL_KEYS = {"platform", "settings", "main", "fork_to_main"}

INGEST_DEFAULTS: dict[str, Any] = {
    "schedule_interval_seconds": 60,
    "max_attempts": 4,
    "heartbeat_seconds": 30,
    "stale_after_seconds": 600,
    "usage_monitor": "auto",
    "usage_monitor_timeout_seconds": 5,
    "rate_limit_retry_seconds": 900,
}


class ConfigError(ValueError):
    """An actionable configuration error safe to print to the user."""


def _load_toml(path: Path, label: str) -> dict[str, Any]:
    try:
        with path.open("rb") as handle:
            data = tomllib.load(handle)
    except FileNotFoundError as exc:
        raise ConfigError(f"{label} not found: {path}") from exc
    except tomllib.TOMLDecodeError as exc:
        raise ConfigError(f"malformed {label}: {path}: {exc}") from exc
    except OSError as exc:
        raise ConfigError(f"cannot read {label}: {path}: {exc}") from exc
    if not isinstance(data, dict):
        raise ConfigError(f"{label} must be a TOML table: {path}")
    return data


def _invalid(key: str, message: str) -> ConfigError:
    return ConfigError(f"wiki: invalid runtime configuration: {key} {message}")


def _require_nonempty_string(table: dict[str, Any], key: str, dotted: str) -> str:
    value = table.get(key)
    if not isinstance(value, str) or not value.strip():
        raise _invalid(dotted, "must be a non-empty string")
    return value


def _positive_int(
    table: dict[str, Any], key: str, dotted: str, *, default: int | None = None
) -> int:
    value = table.get(key, default)
    if isinstance(value, bool) or not isinstance(value, int) or value < 1:
        raise _invalid(dotted, "must be an integer >= 1")
    return value


def _bool_value(
    table: dict[str, Any], key: str, dotted: str, *, default: bool
) -> bool:
    value = table.get(key, default)
    if not isinstance(value, bool):
        raise _invalid(dotted, "must be true or false")
    return value


def classify_wiki_root(wiki: str | Path) -> tuple[Path, dict[str, Any]]:
    """Return canonical root and structural config for a real wiki root."""

    root = Path(wiki).expanduser().resolve()
    structural_path = root / ".wiki-config"
    structural = _load_toml(structural_path, "structural configuration")
    role = structural.get("role")

    if role == "project-pointer":
        target = structural.get("wiki", "./wiki")
        raise ConfigError(
            f"wiki config: {root} is a project pointer, not a wiki root; "
            f"use the resolved wiki path ({target})"
        )
    if role not in SUPPORTED_WIKI_ROLES:
        raise ConfigError(
            f"wiki: invalid structural configuration: role must be one of "
            f"{', '.join(sorted(SUPPORTED_WIKI_ROLES))}"
        )

    for marker in ("schema.md", "index.md", ".wiki-pending"):
        if not (root / marker).exists():
            raise ConfigError(f"wiki: not a complete wiki root: missing {root / marker}")
    return root, structural


def _legacy_config_error(root: Path) -> ConfigError:
    return ConfigError(
        f"wiki: legacy ingest configuration detected in {root / '.wiki-config'}\n"
        f"Run: wiki config migrate {root} --dry-run"
    )


def _missing_local_error(root: Path) -> ConfigError:
    return ConfigError(
        f"wiki: runtime configuration missing: {root / '.wiki-config.local'}\n"
        f"Run: wiki config init-local {root}"
    )


def validate_runtime_config(wiki: str | Path) -> dict[str, Any]:
    """Load, validate, and normalize the split runtime configuration."""

    root, structural = classify_wiki_root(wiki)
    if any(key in structural for key in LEGACY_OPERATIONAL_KEYS):
        raise _legacy_config_error(root)

    local_path = root / ".wiki-config.local"
    if not local_path.is_file():
        raise _missing_local_error(root)
    local = _load_toml(local_path, "runtime configuration")

    ingest = local.get("ingest")
    if not isinstance(ingest, dict):
        raise _invalid("ingest", "must be a TOML table")

    dispatch_mode = _require_nonempty_string(
        ingest, "dispatch_mode", "ingest.dispatch_mode"
    )
    if dispatch_mode not in SUPPORTED_DISPATCH_MODES:
        raise _invalid(
            "ingest.dispatch_mode",
            f"must be one of {', '.join(sorted(SUPPORTED_DISPATCH_MODES))}",
        )

    max_processes = _positive_int(
        ingest, "max_processes", "ingest.max_processes"
    )
    default_profile = _require_nonempty_string(
        ingest, "default_profile", "ingest.default_profile"
    )

    profiles = ingest.get("profiles")
    if not isinstance(profiles, dict) or not profiles:
        raise _invalid("ingest.profiles", "must declare at least one profile")
    if default_profile not in profiles:
        raise _invalid(
            "ingest.default_profile", f"references undeclared profile {default_profile!r}"
        )

    fallback_profile = ingest.get("fallback_profile")
    if fallback_profile is not None:
        if not isinstance(fallback_profile, str) or not fallback_profile.strip():
            raise _invalid("ingest.fallback_profile", "must be a non-empty string")
        if fallback_profile not in profiles:
            raise _invalid(
                "ingest.fallback_profile",
                f"references undeclared profile {fallback_profile!r}",
            )
        if fallback_profile == default_profile:
            raise _invalid(
                "ingest.fallback_profile", "must differ from ingest.default_profile"
            )

    heartbeat_seconds = _positive_int(
        ingest,
        "heartbeat_seconds",
        "ingest.heartbeat_seconds",
        default=INGEST_DEFAULTS["heartbeat_seconds"],
    )
    if heartbeat_seconds < 5:
        raise _invalid("ingest.heartbeat_seconds", "must be an integer >= 5")
    stale_after_seconds = _positive_int(
        ingest,
        "stale_after_seconds",
        "ingest.stale_after_seconds",
        default=INGEST_DEFAULTS["stale_after_seconds"],
    )
    if stale_after_seconds < 3 * heartbeat_seconds:
        raise _invalid(
            "ingest.stale_after_seconds",
            "must be at least 3 * ingest.heartbeat_seconds",
        )

    usage_monitor = ingest.get(
        "usage_monitor", INGEST_DEFAULTS["usage_monitor"]
    )
    if usage_monitor not in SUPPORTED_USAGE_MONITORS:
        raise _invalid(
            "ingest.usage_monitor",
            f"must be one of {', '.join(sorted(SUPPORTED_USAGE_MONITORS))}",
        )

    normalized_profiles: dict[str, dict[str, Any]] = {}
    for profile_name, raw_profile in profiles.items():
        dotted = f"ingest.profiles.{profile_name}"
        if not isinstance(profile_name, str) or not profile_name.strip():
            raise _invalid("ingest.profiles", "contains an empty profile name")
        if re.fullmatch(r"[A-Za-z0-9_-]+", profile_name) is None:
            raise _invalid(
                "ingest.profiles",
                f"contains unsafe profile name {profile_name!r}; use letters, digits, _ or -",
            )
        if not isinstance(raw_profile, dict):
            raise _invalid(dotted, "must be a TOML table")

        provider = _require_nonempty_string(raw_profile, "provider", f"{dotted}.provider")
        if provider not in SUPPORTED_PROVIDERS:
            raise _invalid(
                f"{dotted}.provider",
                f"must be one of {', '.join(sorted(SUPPORTED_PROVIDERS))}",
            )
        model = _require_nonempty_string(raw_profile, "model", f"{dotted}.model")
        effort = _require_nonempty_string(
            raw_profile, "reasoning_effort", f"{dotted}.reasoning_effort"
        )
        if effort not in SUPPORTED_EFFORTS:
            raise _invalid(
                f"{dotted}.reasoning_effort",
                f"must be one of {', '.join(sorted(SUPPORTED_EFFORTS))}",
            )
        executable = raw_profile.get("executable", provider)
        if not isinstance(executable, str) or not executable.strip():
            raise _invalid(f"{dotted}.executable", "must be a non-empty string")
        expanded_executable = os.path.expanduser(executable)
        if os.sep in expanded_executable and not Path(expanded_executable).is_absolute():
            raise _invalid(
                f"{dotted}.executable",
                "must be an executable name or an absolute path",
            )
        profile_limit = _positive_int(
            raw_profile,
            "max_processes",
            f"{dotted}.max_processes",
            default=max_processes,
        )
        usage_provider = raw_profile.get("usage_provider", provider)
        if not isinstance(usage_provider, str) or not usage_provider.strip():
            raise _invalid(f"{dotted}.usage_provider", "must be a non-empty string")

        normalized_profiles[profile_name] = {
            "provider": provider,
            "executable": executable,
            "model": model,
            "reasoning_effort": effort,
            "max_processes": min(profile_limit, max_processes),
            "usage_provider": usage_provider,
        }

    settings = local.get("settings", {})
    if not isinstance(settings, dict):
        raise _invalid("settings", "must be a TOML table")
    routing = local.get("routing", {})
    if not isinstance(routing, dict):
        raise _invalid("routing", "must be a TOML table")

    schedule_interval_seconds = _positive_int(
        ingest,
        "schedule_interval_seconds",
        "ingest.schedule_interval_seconds",
        default=INGEST_DEFAULTS["schedule_interval_seconds"],
    )
    max_attempts = _positive_int(
        ingest,
        "max_attempts",
        "ingest.max_attempts",
        default=INGEST_DEFAULTS["max_attempts"],
    )
    usage_monitor_timeout_seconds = _positive_int(
        ingest,
        "usage_monitor_timeout_seconds",
        "ingest.usage_monitor_timeout_seconds",
        default=INGEST_DEFAULTS["usage_monitor_timeout_seconds"],
    )
    rate_limit_retry_seconds = _positive_int(
        ingest,
        "rate_limit_retry_seconds",
        "ingest.rate_limit_retry_seconds",
        default=INGEST_DEFAULTS["rate_limit_retry_seconds"],
    )

    return {
        "wiki_root": str(root),
        "wiki_role": structural["role"],
        "ingest": {
            "dispatch_mode": dispatch_mode,
            "schedule_interval_seconds": schedule_interval_seconds,
            "max_processes": max_processes,
            "default_profile": default_profile,
            "fallback_profile": fallback_profile,
            "max_attempts": max_attempts,
            "heartbeat_seconds": heartbeat_seconds,
            "stale_after_seconds": stale_after_seconds,
            "usage_monitor": usage_monitor,
            "usage_monitor_timeout_seconds": usage_monitor_timeout_seconds,
            "rate_limit_retry_seconds": rate_limit_retry_seconds,
            "profiles": normalized_profiles,
        },
        "routing": {
            "fork_to_main": _bool_value(
                routing, "fork_to_main", "routing.fork_to_main", default=False
            )
        },
        "settings": {
            "auto_commit": _bool_value(
                settings, "auto_commit", "settings.auto_commit", default=True
            )
        },
    }


def _toml_string(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def _profile_name(provider: str, effort: str, qualifier: str | None = None) -> str:
    parts = [provider, effort]
    if qualifier:
        parts.append(qualifier)
    raw = "_".join(parts).lower()
    return re.sub(r"[^a-z0-9_-]+", "_", raw).strip("_")


def _render_structural_config(structural: dict[str, Any]) -> str:
    role = structural["role"]
    lines = [f"role = {_toml_string(role)}"]
    created = structural.get("created")
    if isinstance(created, str) and created:
        lines.append(f"created = {_toml_string(created)}")
    return "\n".join(lines) + "\n"


def _render_runtime_config(config: dict[str, Any]) -> str:
    ingest = config["ingest"]
    lines = [
        "[ingest]",
        f"dispatch_mode = {_toml_string(ingest['dispatch_mode'])}",
        f"schedule_interval_seconds = {ingest['schedule_interval_seconds']}",
        f"max_processes = {ingest['max_processes']}",
        f"default_profile = {_toml_string(ingest['default_profile'])}",
    ]
    if ingest.get("fallback_profile"):
        lines.append(
            f"fallback_profile = {_toml_string(ingest['fallback_profile'])}"
        )
    lines.extend(
        [
            f"max_attempts = {ingest['max_attempts']}",
            f"heartbeat_seconds = {ingest['heartbeat_seconds']}",
            f"stale_after_seconds = {ingest['stale_after_seconds']}",
            f"usage_monitor = {_toml_string(ingest['usage_monitor'])}",
            f"usage_monitor_timeout_seconds = {ingest['usage_monitor_timeout_seconds']}",
            f"rate_limit_retry_seconds = {ingest['rate_limit_retry_seconds']}",
        ]
    )

    for name, profile in ingest["profiles"].items():
        lines.extend(
            [
                "",
                f"[ingest.profiles.{name}]",
                f"provider = {_toml_string(profile['provider'])}",
                f"executable = {_toml_string(profile['executable'])}",
                f"model = {_toml_string(profile['model'])}",
                f"reasoning_effort = {_toml_string(profile['reasoning_effort'])}",
                f"max_processes = {profile['max_processes']}",
                f"usage_provider = {_toml_string(profile['usage_provider'])}",
            ]
        )

    lines.extend(
        [
            "",
            "[routing]",
            f"fork_to_main = {'true' if config['routing']['fork_to_main'] else 'false'}",
            "",
            "[settings]",
            f"auto_commit = {'true' if config['settings']['auto_commit'] else 'false'}",
        ]
    )
    return "\n".join(lines) + "\n"


def _gitignore_with_local_config(root: Path) -> str:
    path = root / ".gitignore"
    try:
        text = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        text = "# Runtime state (per-machine, never commit)\n"
    except OSError as exc:
        raise ConfigError(f"cannot read gitignore: {path}: {exc}") from exc

    lines = text.splitlines()
    if ".wiki-config.local" not in lines:
        if text and not text.endswith("\n"):
            text += "\n"
        text += ".wiki-config.local\n"
    return text


def _validate_generated_texts(structural_text: str, runtime_text: str) -> None:
    """Validate generated TOML through the public loader before replacement."""

    with tempfile.TemporaryDirectory(prefix="wiki-config-validate-") as tmp:
        root = Path(tmp)
        (root / ".wiki-pending").mkdir()
        (root / "schema.md").write_text("# Schema\n", encoding="utf-8")
        (root / "index.md").write_text("# Index\n", encoding="utf-8")
        (root / ".wiki-config").write_text(structural_text, encoding="utf-8")
        (root / ".wiki-config.local").write_text(runtime_text, encoding="utf-8")
        validate_runtime_config(root)


def _write_temp(path: Path, content: bytes, mode: int) -> Path:
    fd, raw_path = tempfile.mkstemp(prefix=f".{path.name}.tmp-", dir=path.parent)
    temp_path = Path(raw_path)
    try:
        with os.fdopen(fd, "wb") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.chmod(temp_path, mode)
    except Exception:
        temp_path.unlink(missing_ok=True)
        raise
    return temp_path


def _restore_path(path: Path, original: bytes | None, mode: int) -> None:
    if original is None:
        path.unlink(missing_ok=True)
        return
    restore = _write_temp(path, original, mode)
    os.replace(restore, path)


def _next_backup_path(structural_path: Path) -> Path:
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    candidate = structural_path.with_name(f".wiki-config.backup-{stamp}")
    suffix = 1
    while candidate.exists():
        candidate = structural_path.with_name(
            f".wiki-config.backup-{stamp}-{suffix}"
        )
        suffix += 1
    return candidate


def _apply_transaction(
    root: Path,
    replacements: list[tuple[Path, str, int]],
    *,
    backup_structural: bool,
) -> Path | None:
    originals: dict[Path, bytes | None] = {}
    modes: dict[Path, int] = {}
    temps: dict[Path, Path] = {}
    for path, content, mode in replacements:
        try:
            originals[path] = path.read_bytes()
        except FileNotFoundError:
            originals[path] = None
        except OSError as exc:
            raise ConfigError(f"cannot read transaction target: {path}: {exc}") from exc
        modes[path] = mode
        temps[path] = _write_temp(path, content.encode("utf-8"), mode)

    backup_path: Path | None = None
    structural_path = root / ".wiki-config"
    if backup_structural:
        original_structural = originals.get(structural_path)
        if original_structural is None:
            raise ConfigError(f"cannot back up missing structural config: {structural_path}")
        backup_path = _next_backup_path(structural_path)
        fd = os.open(backup_path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        with os.fdopen(fd, "wb") as handle:
            handle.write(original_structural)
            handle.flush()
            os.fsync(handle.fileno())

    replaced: list[Path] = []
    try:
        for path, _content, _mode in replacements:
            os.replace(temps[path], path)
            replaced.append(path)
            if (
                os.environ.get("WIKI_CONFIG_TEST_FAIL_STAGE") == "after_structural"
                and path == structural_path
            ):
                raise OSError("injected transaction failure after structural replace")
    except Exception as exc:
        rollback_errors: list[str] = []
        for path in reversed(replaced):
            try:
                _restore_path(path, originals[path], modes[path])
            except Exception as rollback_exc:  # pragma: no cover - catastrophic I/O
                rollback_errors.append(f"{path}: {rollback_exc}")
        detail = f"configuration transaction failed and was rolled back: {exc}"
        if rollback_errors:
            detail += f"; rollback errors: {'; '.join(rollback_errors)}"
        raise ConfigError(detail) from exc
    finally:
        for temp_path in temps.values():
            temp_path.unlink(missing_ok=True)
    return backup_path


def _read_explicit_profile(args: argparse.Namespace, prefix: str) -> dict[str, Any] | None:
    provider = getattr(args, f"{prefix}_provider")
    model = getattr(args, f"{prefix}_model")
    effort = getattr(args, f"{prefix}_effort")
    executable = getattr(args, f"{prefix}_executable")
    supplied = [provider is not None, model is not None, effort is not None]
    if not any(supplied):
        return None
    if not all(supplied):
        raise ConfigError(
            f"{prefix} profile requires --{prefix}-provider, --{prefix}-model, "
            f"and --{prefix}-effort together"
        )
    return {
        "provider": provider,
        "executable": executable or provider,
        "model": model,
        "reasoning_effort": effort,
    }


def _profile_options_example(command: str, root: Path) -> str:
    return (
        f"Run: wiki config {command} {root} "
        "--default-provider <codex|claude|grok> "
        "--default-model <model-id> --default-effort <effort> "
        "--max-processes <n> --dispatch-mode <session_start|scheduled>"
    )


def _infer_legacy_profile(structural: dict[str, Any]) -> dict[str, Any] | None:
    platform = structural.get("platform")
    if not isinstance(platform, dict):
        return None
    command = platform.get("headless_command")
    if not isinstance(command, str) or not command.strip():
        return None
    try:
        argv = shlex.split(command)
    except ValueError:
        return None
    if not argv:
        return None
    executable = argv[0]
    provider = Path(executable).name
    if provider not in SUPPORTED_PROVIDERS:
        return None

    def option_value(*names: str) -> str | None:
        for index, token in enumerate(argv[:-1]):
            if token in names:
                return argv[index + 1]
        return None

    model = option_value("--model", "-m")
    effort = option_value("--effort", "--reasoning-effort")
    if not model or not effort:
        return None
    return {
        "provider": provider,
        "executable": executable,
        "model": model,
        "reasoning_effort": effort,
    }


def _interactive_default_profile() -> dict[str, Any] | None:
    if not sys.stdin.isatty():
        return None
    provider = input("Default provider (codex/claude/grok): ").strip()
    model = input("Model ID: ").strip()
    effort = input("Reasoning effort: ").strip()
    if not provider or not model or not effort:
        return None
    return {
        "provider": provider,
        "executable": provider,
        "model": model,
        "reasoning_effort": effort,
    }


def _build_runtime_for_write(
    args: argparse.Namespace,
    *,
    structural: dict[str, Any],
    allow_legacy_inference: bool,
) -> dict[str, Any]:
    default = _read_explicit_profile(args, "default")
    if default is None and allow_legacy_inference:
        default = _infer_legacy_profile(structural)
    if default is None:
        default = _interactive_default_profile()
    if default is None:
        raise ConfigError(_profile_options_example(args.command, Path(args.wiki).resolve()))

    fallback = _read_explicit_profile(args, "fallback")
    default_name = _profile_name(default["provider"], default["reasoning_effort"])
    profiles: dict[str, dict[str, Any]] = {
        default_name: {
            **default,
            "max_processes": args.max_processes,
            "usage_provider": default["provider"],
        }
    }
    fallback_name: str | None = None
    if fallback is not None:
        fallback_name = _profile_name(
            fallback["provider"], fallback["reasoning_effort"]
        )
        if fallback_name == default_name:
            fallback_name = _profile_name(
                fallback["provider"],
                fallback["reasoning_effort"],
                fallback["model"],
            )
        if fallback_name == default_name:
            fallback_name = f"{fallback_name}_fallback"
        profiles[fallback_name] = {
            **fallback,
            "max_processes": args.max_processes,
            "usage_provider": fallback["provider"],
        }

    legacy_settings = structural.get("settings", {})
    legacy_auto_commit = (
        legacy_settings.get("auto_commit", True)
        if isinstance(legacy_settings, dict)
        else True
    )
    auto_commit = legacy_auto_commit if args.auto_commit is None else args.auto_commit
    legacy_fork = structural.get("fork_to_main", False)
    fork_to_main = legacy_fork if args.fork_to_main is None else args.fork_to_main

    config = {
        "ingest": {
            "dispatch_mode": args.dispatch_mode,
            "schedule_interval_seconds": args.schedule_interval_seconds,
            "max_processes": args.max_processes,
            "default_profile": default_name,
            "fallback_profile": fallback_name,
            "max_attempts": args.max_attempts,
            "heartbeat_seconds": args.heartbeat_seconds,
            "stale_after_seconds": args.stale_after_seconds,
            "usage_monitor": args.usage_monitor,
            "usage_monitor_timeout_seconds": args.usage_monitor_timeout_seconds,
            "rate_limit_retry_seconds": args.rate_limit_retry_seconds,
            "profiles": profiles,
        },
        "routing": {"fork_to_main": bool(fork_to_main)},
        "settings": {"auto_commit": bool(auto_commit)},
    }
    structural_text = _render_structural_config(structural)
    runtime_text = _render_runtime_config(config)
    _validate_generated_texts(structural_text, runtime_text)
    return config


def init_local_config(args: argparse.Namespace) -> int:
    root, structural = classify_wiki_root(args.wiki)
    if any(key in structural for key in LEGACY_OPERATIONAL_KEYS):
        raise _legacy_config_error(root)
    local_path = root / ".wiki-config.local"
    if local_path.exists():
        validate_runtime_config(root)
        gitignore_path = root / ".gitignore"
        gitignore_text = _gitignore_with_local_config(root)
        try:
            current_gitignore = gitignore_path.read_text(encoding="utf-8")
        except FileNotFoundError:
            current_gitignore = ""
        except OSError as exc:
            raise ConfigError(f"cannot read gitignore: {gitignore_path}: {exc}") from exc
        if current_gitignore != gitignore_text:
            _apply_transaction(
                root,
                [(gitignore_path, gitignore_text, 0o644)],
                backup_structural=False,
            )
        print(f"runtime configuration already exists: {local_path}")
        return 0

    config = _build_runtime_for_write(
        args, structural=structural, allow_legacy_inference=False
    )
    runtime_text = _render_runtime_config(config)
    gitignore_text = _gitignore_with_local_config(root)
    _apply_transaction(
        root,
        [
            (local_path, runtime_text, 0o600),
            (root / ".gitignore", gitignore_text, 0o644),
        ],
        backup_structural=False,
    )
    validate_runtime_config(root)
    print(f"runtime configuration initialized: {local_path}")
    return 0


def migrate_config(args: argparse.Namespace) -> int:
    root, structural = classify_wiki_root(args.wiki)
    local_path = root / ".wiki-config.local"
    legacy = any(key in structural for key in LEGACY_OPERATIONAL_KEYS)
    if not legacy:
        if local_path.exists():
            validate_runtime_config(root)
            print(f"runtime configuration already migrated: {root}")
            return 0
        raise _missing_local_error(root)

    config = _build_runtime_for_write(
        args, structural=structural, allow_legacy_inference=True
    )
    structural_text = _render_structural_config(structural)
    runtime_text = _render_runtime_config(config)
    gitignore_text = _gitignore_with_local_config(root)

    if args.dry_run:
        print("--- proposed .wiki-config ---")
        print(structural_text, end="")
        print("--- proposed .wiki-config.local ---")
        print(runtime_text, end="")
        print("--- proposed .gitignore addition ---")
        print(".wiki-config.local")
        print("dry-run complete; no files modified")
        return 0

    backup = _apply_transaction(
        root,
        [
            (root / ".wiki-config", structural_text, 0o644),
            (local_path, runtime_text, 0o600),
            (root / ".gitignore", gitignore_text, 0o644),
        ],
        backup_structural=True,
    )
    validate_runtime_config(root)
    print(f"migration complete: {root}")
    if backup is not None:
        print(f"backup: {backup}")
    return 0


def update_runtime_config(args: argparse.Namespace) -> int:
    """Atomically update the small runtime fields owned by plugin adapters."""

    root, structural = classify_wiki_root(args.wiki)
    config = validate_runtime_config(root)
    changed = False
    if args.dispatch_mode is not None:
        config["ingest"]["dispatch_mode"] = args.dispatch_mode
        changed = True
    if args.fork_to_main is not None:
        config["routing"]["fork_to_main"] = args.fork_to_main
        changed = True
    if not changed:
        raise ConfigError("wiki config update-runtime: no update option supplied")
    structural_text = _render_structural_config(structural)
    runtime_text = _render_runtime_config(config)
    _validate_generated_texts(structural_text, runtime_text)
    _apply_transaction(
        root,
        [(root / ".wiki-config.local", runtime_text, 0o600)],
        backup_structural=False,
    )
    validate_runtime_config(root)
    print(f"runtime configuration updated: {root / '.wiki-config.local'}")
    return 0


def _add_write_options(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--wiki", required=True)
    parser.add_argument("--default-provider", choices=sorted(SUPPORTED_PROVIDERS))
    parser.add_argument("--default-model")
    parser.add_argument("--default-effort", choices=sorted(SUPPORTED_EFFORTS))
    parser.add_argument("--default-executable")
    parser.add_argument("--fallback-provider", choices=sorted(SUPPORTED_PROVIDERS))
    parser.add_argument("--fallback-model")
    parser.add_argument("--fallback-effort", choices=sorted(SUPPORTED_EFFORTS))
    parser.add_argument("--fallback-executable")
    parser.add_argument("--max-processes", type=int, default=1)
    parser.add_argument(
        "--dispatch-mode", choices=sorted(SUPPORTED_DISPATCH_MODES), default="session_start"
    )
    parser.add_argument("--schedule-interval-seconds", type=int, default=60)
    parser.add_argument("--max-attempts", type=int, default=4)
    parser.add_argument("--heartbeat-seconds", type=int, default=30)
    parser.add_argument("--stale-after-seconds", type=int, default=600)
    parser.add_argument(
        "--usage-monitor", choices=sorted(SUPPORTED_USAGE_MONITORS), default="auto"
    )
    parser.add_argument("--usage-monitor-timeout-seconds", type=int, default=5)
    parser.add_argument("--rate-limit-retry-seconds", type=int, default=900)
    parser.add_argument(
        "--auto-commit", action=argparse.BooleanOptionalAction, default=None
    )
    parser.add_argument(
        "--fork-to-main", action=argparse.BooleanOptionalAction, default=None
    )


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    validate = subparsers.add_parser("validate", help="validate split runtime config")
    validate.add_argument("--wiki", required=True)
    validate.add_argument("--json", action="store_true")

    show = subparsers.add_parser("show", help="print normalized runtime config as JSON")
    show.add_argument("--wiki", required=True)

    init_local = subparsers.add_parser(
        "init-local", help="create ignored per-user runtime config"
    )
    _add_write_options(init_local)

    migrate = subparsers.add_parser(
        "migrate", help="split legacy tracked and per-user runtime config"
    )
    _add_write_options(migrate)
    migrate.add_argument("--dry-run", action="store_true")

    update = subparsers.add_parser(
        "update-runtime", help="update adapter-owned local runtime fields"
    )
    update.add_argument("--wiki", required=True)
    update.add_argument(
        "--dispatch-mode", choices=sorted(SUPPORTED_DISPATCH_MODES)
    )
    update.add_argument(
        "--fork-to-main", action=argparse.BooleanOptionalAction, default=None
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    try:
        if args.command == "init-local":
            return init_local_config(args)
        if args.command == "migrate":
            return migrate_config(args)
        if args.command == "update-runtime":
            return update_runtime_config(args)
        config = validate_runtime_config(args.wiki)
    except ConfigError as exc:
        print(str(exc), file=sys.stderr)
        return 2

    if args.command == "show" or args.json:
        print(json.dumps(config, indent=2, sort_keys=True))
    else:
        print(f"runtime configuration valid: {config['wiki_root']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
