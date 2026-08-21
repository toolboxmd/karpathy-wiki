#!/usr/bin/env python3
"""Safe provider adapters for detached karpathy-wiki ingesters."""

from __future__ import annotations

import base64
from dataclasses import dataclass
import hashlib
import json
import os
from pathlib import Path
import re
import shlex
import shutil
from typing import Any

from wiki_yaml import extract_frontmatter, parse_yaml


SUPPORTED_PROVIDERS = {"claude", "codex", "grok"}
SUPPORTED_GROK_IMAGE_MIME_TYPES = {"image/jpeg", "image/png"}
IMAGE_LIKE_SUFFIXES = {
    ".avif",
    ".bmp",
    ".gif",
    ".heic",
    ".heif",
    ".jpeg",
    ".jpg",
    ".png",
    ".tif",
    ".tiff",
    ".webp",
}


class ProviderError(ValueError):
    """An actionable provider configuration/capability error."""


@dataclass(frozen=True)
class ProviderInvocation:
    provider: str
    model: str
    reasoning_effort: str
    argv: list[str]
    environment: dict[str, str]
    prompt: str
    stdin_bytes: bytes | None
    run_dir: Path
    stdout_path: Path
    stderr_path: Path
    prompt_path: Path | None = None
    output_last_message_path: Path | None = None


@dataclass(frozen=True)
class NativeImageAttachment:
    path: Path
    data: bytes
    mime_type: str
    sha256: str


def resolve_executable(
    executable: str, *, forbidden_roots: tuple[Path, ...] = ()
) -> str:
    """Resolve one executable scalar without ever parsing it as a command."""

    if not isinstance(executable, str) or not executable.strip():
        raise ProviderError("provider executable must be a non-empty string")
    expanded = os.path.expanduser(executable)
    if os.sep in expanded:
        path = Path(expanded)
        if not path.is_absolute():
            raise ProviderError(
                "provider executable must be an executable name or an absolute path"
            )
        path = path.resolve()
        if not path.is_file() or not os.access(path, os.X_OK):
            raise ProviderError(f"provider executable is missing or not executable: {path}")
        resolved_path = path
    else:
        resolved = shutil.which(expanded)
        if resolved is None:
            raise ProviderError(f"provider executable not found on PATH: {expanded}")
        resolved_path = Path(resolved).resolve()
    for raw_root in forbidden_roots:
        root = Path(raw_root).expanduser().resolve()
        try:
            resolved_path.relative_to(root)
        except ValueError:
            continue
        raise ProviderError(
            f"provider executable resolves inside the trusted workspace: {resolved_path}"
        )
    return str(resolved_path)


def _safe_run_id(run_id: str) -> str:
    if not re.fullmatch(r"[A-Za-z0-9._-]+", run_id):
        raise ProviderError("provider run_id contains unsafe path characters")
    return run_id


def _prompt(root: Path, capture: Path, plugin_root: Path) -> str:
    skill = plugin_root / "skills" / "karpathy-wiki-ingest" / "SKILL.md"
    helper = plugin_root / "scripts" / "wiki-complete-ingest.sh"
    return (
        "You are the selected detached wiki ingester for exactly one capture.\n"
        f"Wiki root: {root}\n"
        f"Claimed capture: {capture}\n"
        f"Plugin root: {plugin_root}\n"
        f"Load and follow this ingest skill exactly: {skill}\n"
        "Perform the ingest yourself. Do not launch or delegate to another model "
        "or agentic CLI, and do not substitute the configured model or effort.\n"
        f"After the semantic work succeeds, close it only with: bash {shlex.quote(str(helper))}\n"
        "Exit non-zero if deterministic completion fails.\n"
    )


def _image_prompt(prompt: str) -> str:
    return (
        prompt
        + "\nNative ACP image evidence is attached below in the exact order declared "
        "by the capture. Inspect the native image content blocks directly. A file "
        "path, filename, read_file result, or tool call is not proof that an image "
        "was shown to the model. Do not silently downgrade visual evidence to a "
        "path-only or read_file-only workflow. Preserve every declared original "
        "under the normal raw-evidence and manifest protocol.\n"
    )


def _detect_supported_image_mime(data: bytes) -> str | None:
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    return None


def _canonical_declared_file(raw_path: str, label: str) -> Path:
    if not isinstance(raw_path, str) or not raw_path.strip():
        raise ProviderError(f"{label} must be a non-empty absolute path")
    declared = Path(raw_path).expanduser()
    if not declared.is_absolute():
        raise ProviderError(f"{label} must be an absolute path: {raw_path}")
    try:
        canonical = declared.resolve(strict=True)
    except FileNotFoundError as exc:
        raise ProviderError(f"missing {label}: {declared}") from exc
    except OSError as exc:
        raise ProviderError(f"cannot resolve {label}: {declared}: {exc}") from exc
    if not canonical.is_file():
        raise ProviderError(f"{label} is not a regular file: {canonical}")
    return canonical


def _load_native_image(path: Path, label: str) -> NativeImageAttachment:
    try:
        data = path.read_bytes()
    except OSError as exc:
        raise ProviderError(f"cannot read {label}: {path}: {exc}") from exc
    mime_type = _detect_supported_image_mime(data)
    if mime_type not in SUPPORTED_GROK_IMAGE_MIME_TYPES:
        supported = ", ".join(sorted(SUPPORTED_GROK_IMAGE_MIME_TYPES))
        raise ProviderError(
            f"unsupported image format for {label}: {path}; supported MIME types: {supported}"
        )
    return NativeImageAttachment(
        path=path,
        data=data,
        mime_type=mime_type,
        sha256=hashlib.sha256(data).hexdigest(),
    )


def _capture_frontmatter(capture: Path) -> dict[str, Any]:
    try:
        text = capture.read_text(encoding="utf-8")
    except FileNotFoundError as exc:
        raise ProviderError(f"claimed capture is missing: {capture}") from exc
    except (OSError, UnicodeDecodeError) as exc:
        raise ProviderError(f"cannot read claimed capture: {capture}: {exc}") from exc
    raw_frontmatter = extract_frontmatter(text)
    if raw_frontmatter is None:
        return {}
    try:
        parsed = parse_yaml(raw_frontmatter)
    except ValueError as exc:
        raise ProviderError(f"claimed capture frontmatter is malformed: {capture}: {exc}") from exc
    return parsed


def _grok_native_images(capture: Path) -> list[NativeImageAttachment]:
    """Return only explicitly declared images in capture-stable order."""

    frontmatter = _capture_frontmatter(capture)
    evidence = frontmatter.get("evidence")
    evidence_type = frontmatter.get("evidence_type")
    raw_attachments = frontmatter.get("attachments", [])
    if raw_attachments in (None, ""):
        raw_attachments = []
    if not isinstance(raw_attachments, list) or any(
        not isinstance(item, str) or not item.strip() for item in raw_attachments
    ):
        raise ProviderError("capture attachments must be a list of non-empty absolute paths")

    file_backed = evidence_type in {"file", "mixed"} and isinstance(evidence, str)
    evidence_path: Path | None = None
    evidence_is_image_intent = (
        file_backed and Path(evidence).suffix.lower() in IMAGE_LIKE_SUFFIXES
    )
    if file_backed and (raw_attachments or evidence_is_image_intent):
        label = (
            "declared image evidence"
            if evidence_is_image_intent
            else "capture evidence file"
        )
        evidence_path = _canonical_declared_file(evidence, label)
    elif file_backed:
        declared = Path(evidence).expanduser()
        if declared.is_absolute() and declared.is_file():
            try:
                evidence_path = declared.resolve(strict=True)
            except OSError:
                evidence_path = None

    images: list[NativeImageAttachment] = []
    if evidence_path is not None:
        try:
            with evidence_path.open("rb") as handle:
                prefix = handle.read(16)
        except OSError as exc:
            if evidence_is_image_intent or raw_attachments:
                raise ProviderError(
                    f"cannot read capture evidence file: {evidence_path}: {exc}"
                ) from exc
            prefix = b""
        if _detect_supported_image_mime(prefix) is not None:
            images.append(_load_native_image(evidence_path, "declared image evidence"))
        elif evidence_is_image_intent:
            _load_native_image(evidence_path, "declared image evidence")

    if raw_attachments:
        if evidence_path is None:
            raise ProviderError(
                "declared image attachments require an existing file-backed capture evidence path"
            )
        evidence_root = evidence_path.parent
        for index, raw_path in enumerate(raw_attachments, start=1):
            label = f"declared image attachment {index}"
            attachment_path = _canonical_declared_file(raw_path, label)
            try:
                attachment_path.relative_to(evidence_root)
            except ValueError as exc:
                raise ProviderError(
                    f"declared image attachment is outside the capture evidence directory: "
                    f"{attachment_path} (allowed root: {evidence_root})"
                ) from exc
            images.append(_load_native_image(attachment_path, label))
    return images


def _safe_prompt_json_limit() -> int:
    try:
        arg_max = int(os.sysconf("SC_ARG_MAX"))
    except (AttributeError, OSError, TypeError, ValueError):
        arg_max = 1024 * 1024
    environment_bytes = sum(
        len(key.encode()) + len(value.encode()) + 2 for key, value in os.environ.items()
    )
    return max(0, arg_max - environment_bytes - 64 * 1024)


def _base_environment(
    root: Path, capture: Path, run_id: str, plugin_root: Path
) -> dict[str, str]:
    return {
        "WIKI_ROOT": str(root),
        "WIKI_CAPTURE": str(capture),
        "WIKI_RUN_ID": run_id,
        "WIKI_PLUGIN_ROOT": str(plugin_root),
    }


def build_provider_invocation(
    profile: dict[str, Any],
    wiki_root: Path,
    capture: Path,
    run_id: str,
    plugin_root: Path,
) -> ProviderInvocation:
    """Build a provider argv array and run-scoped paths; never a shell string."""

    provider = profile.get("provider")
    if provider not in SUPPORTED_PROVIDERS:
        raise ProviderError(f"unsupported ingest provider: {provider!r}")
    executable = profile.get("executable")
    model = profile.get("model")
    effort = profile.get("reasoning_effort")
    for key, value in (
        ("executable", executable),
        ("model", model),
        ("reasoning_effort", effort),
    ):
        if not isinstance(value, str) or not value.strip():
            raise ProviderError(f"provider profile {key} must be a non-empty string")

    root = Path(wiki_root).expanduser().resolve()
    claimed = Path(capture).expanduser().resolve()
    plugin = Path(plugin_root).expanduser().resolve()
    native_images = _grok_native_images(claimed) if provider == "grok" else []
    safe_run_id = _safe_run_id(run_id)
    run_dir = root / ".locks" / "ingest-runs" / safe_run_id
    run_dir.mkdir(parents=True, exist_ok=True)
    prompt = _prompt(root, claimed, plugin)
    if native_images:
        prompt = _image_prompt(prompt)
    stdout_path = run_dir / "stdout.jsonl"
    stderr_path = run_dir / "stderr.log"
    environment = _base_environment(root, claimed, safe_run_id, plugin)

    prompt_path: Path | None = None
    output_path: Path | None = None
    stdin_bytes: bytes | None = None

    if provider == "claude":
        argv = [
            executable,
            "--plugin-dir",
            str(plugin),
            "--model",
            model,
            "--effort",
            effort,
            "--permission-mode",
            "auto",
            "--no-chrome",
            "--no-session-persistence",
            "--output-format",
            "json",
            "-p",
            prompt,
        ]
    elif provider == "grok":
        argv = [
            executable,
            "--cwd",
            str(root),
            "--model",
            model,
            "--reasoning-effort",
            effort,
            # Headless automation needs the bypass mode. Do not also pass
            # --permission-mode auto: Grok CLI 1.0.5 can then start with
            # yolo_mode=false and cancel a permission request after 30s.
            "--always-approve",
            "--max-turns",
            "150",
            "--no-memory",
            "--no-subagents",
            "--output-format",
            "streaming-json",
        ]
        if native_images:
            content_blocks: list[dict[str, str]] = [
                {"type": "text", "text": prompt}
            ]
            content_blocks.extend(
                {
                    "type": "image",
                    "data": base64.b64encode(image.data).decode("ascii"),
                    "mimeType": image.mime_type,
                }
                for image in native_images
            )
            prompt_json = json.dumps(content_blocks, separators=(",", ":"))
            prompt_json_bytes = len(prompt_json.encode("utf-8"))
            prompt_json_limit = _safe_prompt_json_limit()
            if prompt_json_bytes > prompt_json_limit:
                raise ProviderError(
                    "native ACP image payload is too large for the provider process "
                    f"argument limit: {prompt_json_bytes} bytes exceeds {prompt_json_limit} bytes"
                )
            argv.extend(["--prompt-json", prompt_json])
        else:
            prompt_path = run_dir / "prompt.md"
            prompt_path.write_text(prompt, encoding="utf-8")
            argv.extend(["--prompt-file", str(prompt_path)])
    else:
        output_path = run_dir / "output-last-message.txt"
        stdin_bytes = prompt.encode("utf-8")
        argv = [
            executable,
            "--model",
            model,
            "-c",
            f'model_reasoning_effort="{effort}"',
            "--cd",
            str(root),
            "--sandbox",
            "danger-full-access",
            "exec",
            "--ephemeral",
            # A detached ingester must not inherit model-incompatible options
            # (for example reasoning.summary) from the operator's config.toml.
            # Authentication is still loaded by Codex with this flag.
            "--ignore-user-config",
            "--skip-git-repo-check",
            "--json",
            "--output-last-message",
            str(output_path),
            "-",
        ]

    # Safe attribution metadata contains no prompt, argv, account identity, or
    # credential-bearing environment values. Failure diagnostics and explicit
    # acceptance runs may retain it for audit.
    invocation_metadata: dict[str, Any] = {
        "run_id": safe_run_id,
        "provider": provider,
        "model": model,
        "reasoning_effort": effort,
    }
    if native_images:
        invocation_metadata.update(
            {
                "prompt_transport": "native_acp_content_blocks",
                "content_block_types": ["text"] + ["image"] * len(native_images),
                "image_count": len(native_images),
                "images": [
                    {
                        "ordinal": index,
                        "mime_type": image.mime_type,
                        "bytes": len(image.data),
                        "sha256": image.sha256,
                    }
                    for index, image in enumerate(native_images, start=1)
                ],
            }
        )
    (run_dir / "invocation.json").write_text(
        json.dumps(
            invocation_metadata,
            sort_keys=True,
            separators=(",", ":"),
        )
        + "\n",
        encoding="utf-8",
    )

    return ProviderInvocation(
        provider=provider,
        model=model,
        reasoning_effort=effort,
        argv=argv,
        environment=environment,
        prompt=prompt,
        stdin_bytes=stdin_bytes,
        run_dir=run_dir,
        stdout_path=stdout_path,
        stderr_path=stderr_path,
        prompt_path=prompt_path,
        output_last_message_path=output_path,
    )


def _json_objects(text: str) -> list[dict[str, Any]]:
    objects: list[dict[str, Any]] = []
    stripped = text.strip()
    if not stripped:
        return objects
    try:
        parsed = json.loads(stripped)
    except json.JSONDecodeError:
        parsed = None
    if isinstance(parsed, dict):
        return [parsed]
    for line in stripped.splitlines():
        try:
            parsed = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(parsed, dict):
            objects.append(parsed)
    return objects


def _error_fragments(payload: dict[str, Any]) -> list[str]:
    fragments: list[str] = []
    event_type = str(payload.get("type", "")).lower()
    status = str(payload.get("status", "")).lower()
    explicit_error = payload.get("error")
    is_error = (
        bool(payload.get("is_error"))
        or "error" in event_type
        or status in {"error", "failed", "failure"}
        or explicit_error not in (None, False, "", {})
    )
    if not is_error:
        return fragments
    selected: dict[str, Any] = {}
    for key in ("type", "status", "code", "status_code", "message", "error", "errors"):
        if key in payload:
            selected[key] = payload[key]
    fragments.append(json.dumps(selected, sort_keys=True, default=str))
    return fragments


RATE_LIMIT_PATTERNS = (
    "rate_limit",
    "rate limit",
    "usage limit",
    "quota exhausted",
    "quota exceeded",
    "too many requests",
    '"status": 429',
    '"status_code": 429',
    '"code": 429',
)
AUTH_PATTERNS = (
    "authentication",
    "unauthorized",
    "login required",
    "not logged in",
    "api key",
    "invalid key",
    '"status": 401',
    '"status": 403',
    '"status_code": 401',
    '"status_code": 403',
)
CAPABILITY_PATTERNS = (
    "invalid value",
    "invalid model",
    "unknown model",
    "model not found",
    "unsupported model",
    "unsupported reasoning",
    "unknown option",
    "unrecognized option",
    "unrecognized argument",
    "unexpected argument",
)


def classify_provider_result(
    provider: str, exit_code: int, stdout_text: str, stderr_text: str
) -> str:
    """Classify a technical provider result without interpreting answer prose."""

    if provider not in SUPPORTED_PROVIDERS:
        raise ProviderError(f"unsupported ingest provider: {provider!r}")
    if exit_code == 0:
        return "success"
    fragments: list[str] = []
    for payload in _json_objects(stdout_text):
        fragments.extend(_error_fragments(payload))
    # stderr is a provider diagnostic channel, unlike ordinary answer text.
    if stderr_text.strip():
        fragments.append(stderr_text)
    diagnostic = "\n".join(fragments).lower()
    if any(pattern in diagnostic for pattern in RATE_LIMIT_PATTERNS):
        return "provider_rate_limited"
    if any(pattern in diagnostic for pattern in AUTH_PATTERNS + CAPABILITY_PATTERNS):
        return "configuration_or_auth_failure"
    return "transient_failure"


SECRET_PATTERNS = (
    re.compile(r"(?i)(authorization\s*[:=]\s*bearer\s+)[^\s\"']+"),
    re.compile(r"(?i)((?:api[\s_-]?key|access[_-]?token|refresh[_-]?token)\s*[:=]\s*)[^\s\"']+"),
)


def redact_diagnostic_file(path: Path) -> None:
    """Best-effort redaction for retained provider diagnostics."""

    try:
        text = path.read_text(encoding="utf-8", errors="replace")
    except FileNotFoundError:
        return
    for pattern in SECRET_PATTERNS:
        text = pattern.sub(r"\1[REDACTED]", text)
    path.write_text(text, encoding="utf-8")
