#!/bin/bash
# Explicit, paid-provider acceptance for the Codex adapter and ingest lifecycle.
# Ordinary test runs skip it. Enable with RUN_CODEX_SPARK_ACCEPTANCE=1.
set -euo pipefail

if [[ "${RUN_CODEX_SPARK_ACCEPTANCE:-0}" != "1" ]]; then
  echo "SKIP: set RUN_CODEX_SPARK_ACCEPTANCE=1 to run real Codex Spark acceptance"
  exit 0
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DISPATCH="${REPO_ROOT}/scripts/wiki_dispatch.py"
MODEL="gpt-5.3-codex-spark"
EFFORT="medium"
CODEX_EXECUTABLE="$(command -v codex || true)"
RAW_PARENT="${REPO_ROOT}/tests/acceptance/dispatcher/raw"
RUN_STAMP="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
RAW_RUN="${RAW_PARENT}/${RUN_STAMP}"

fail() { echo "FAIL: $*" >&2; exit 1; }

[[ -n "${CODEX_EXECUTABLE}" ]] || fail "codex executable is not available"
codex --version | grep -q 'codex-cli' || fail "codex CLI preflight failed"

TMP_BASE="${TMPDIR:-/tmp}"
TESTDIR="$(mktemp -d "${TMP_BASE%/}/karpathy wiki spark.XXXXXX")"
WIKI="${TESTDIR}/wiki with spaces"
SOURCE="${WIKI}/inbox/relay retry policy.md"
PREFLIGHT_OUTPUT="${TESTDIR}/spark-preflight-last.txt"
PREFLIGHT_EVENTS="${TESTDIR}/spark-preflight.jsonl"
KEEP_FIXTURE="${WIKI_ACCEPTANCE_KEEP_TMP:-0}"

preserve_raw() {
  local outcome="$1"
  mkdir -p "${RAW_RUN}"
  printf '%s\n' \
    "outcome=${outcome}" \
    "model=${MODEL}" \
    "reasoning_effort=${EFFORT}" \
    "codex_version=$(codex --version 2>/dev/null || echo unavailable)" \
    > "${RAW_RUN}/run-metadata.txt"
  [[ -f "${PREFLIGHT_EVENTS}" ]] && cp "${PREFLIGHT_EVENTS}" "${RAW_RUN}/spark-preflight.jsonl"
  [[ -f "${PREFLIGHT_OUTPUT}" ]] && cp "${PREFLIGHT_OUTPUT}" "${RAW_RUN}/spark-preflight-last.txt"
  [[ -f "${WIKI}/.ingest-runs.jsonl" ]] && cp "${WIKI}/.ingest-runs.jsonl" "${RAW_RUN}/ingest-runs.jsonl"
  [[ -f "${WIKI}/.ingest.log" ]] && cp "${WIKI}/.ingest.log" "${RAW_RUN}/ingest.log"
  [[ -d "${WIKI}/.locks/ingest-runs" ]] && cp -R "${WIKI}/.locks/ingest-runs" "${RAW_RUN}/provider-runs"
  if [[ -d "${WIKI}/concepts" ]]; then
    mkdir -p "${RAW_RUN}/wiki-pages"
    for category in concepts entities queries ideas; do
      [[ -d "${WIKI}/${category}" ]] && cp -R "${WIKI}/${category}" "${RAW_RUN}/wiki-pages/${category}"
    done
    cp "${WIKI}/index.md" "${RAW_RUN}/wiki-pages/index.md" 2>/dev/null || true
    cp "${WIKI}/log.md" "${RAW_RUN}/wiki-pages/log.md" 2>/dev/null || true
    cp "${WIKI}/.manifest.json" "${RAW_RUN}/manifest.json" 2>/dev/null || true
  fi
}

cleanup() {
  local rc=$?
  preserve_raw "$([[ "${rc}" -eq 0 ]] && echo passed || echo failed)" || true
  if [[ "${KEEP_FIXTURE}" == "1" ]]; then
    echo "Acceptance fixture retained: ${TESTDIR}"
  else
    local attempt
    for attempt in $(seq 1 100); do
      rm -rf "${TESTDIR}" 2>/dev/null && break
      sleep 0.05
    done
  fi
  return "${rc}"
}
trap cleanup EXIT

bash "${REPO_ROOT}/scripts/wiki-init.sh" project "${WIKI}" >/dev/null
cat > "${WIKI}/.wiki-config.local" <<EOF
[ingest]
dispatch_mode = "scheduled"
max_processes = 1
default_profile = "spark_medium"
max_attempts = 1
heartbeat_seconds = 10
stale_after_seconds = 600
usage_monitor = "auto"
usage_monitor_timeout_seconds = 1
rate_limit_retry_seconds = 30

[ingest.profiles.spark_medium]
provider = "codex"
executable = "${CODEX_EXECUTABLE}"
model = "${MODEL}"
reasoning_effort = "${EFFORT}"
max_processes = 1
usage_provider = "codex"

[settings]
auto_commit = false
EOF
python3 "${REPO_ROOT}/scripts/wiki_config.py" validate --wiki "${WIKI}" >/dev/null

# Capability/entitlement preflight. This requests the exact model and effort;
# an unavailable model is a hard failure and is never substituted.
printf '%s\n' 'Reply with exactly SPARK_PREFLIGHT_OK. Do not use tools.' \
  | "${CODEX_EXECUTABLE}" \
      --model "${MODEL}" \
      -c "model_reasoning_effort=\"${EFFORT}\"" \
      --cd "${WIKI}" \
      --sandbox danger-full-access \
      exec --ephemeral --ignore-user-config --skip-git-repo-check --json \
      --output-last-message "${PREFLIGHT_OUTPUT}" - \
      > "${PREFLIGHT_EVENTS}"
grep -Fxq 'SPARK_PREFLIGHT_OK' "${PREFLIGHT_OUTPUT}" \
  || fail "Spark preflight did not return the exact marker"

write_source_cold() {
  cat > "${SOURCE}" <<'EOF'
# Relay retry policy

This project operates a component called Relay. The accepted delivery policy is:

- Retry a failed delivery exactly three times.
- Wait 2 seconds, then 8 seconds, then 30 seconds.
- Stop immediately after a permanent HTTP 4xx response except 408 or 429.
- Record the final failure as `relay_delivery_exhausted`.

This is an approved project decision, not a proposal.
EOF
}

write_source_augmented() {
  cat > "${SOURCE}" <<'EOF'
# Relay retry policy

This project operates a component called Relay. The accepted delivery policy is:

- Retry a failed delivery exactly three times.
- Wait 2 seconds, then 8 seconds, then 30 seconds.
- Stop immediately after a permanent HTTP 4xx response except 408 or 429.
- Record the final failure as `relay_delivery_exhausted`.
- Apply deterministic jitter of 20% to each waiting period, seeded by the delivery ID.
- Cap the total retry window at 45 seconds.

The deterministic jitter and 45-second cap were approved on 2026-08-11. These
details augment the existing Relay policy; they do not replace its three-retry rule.
EOF
}

write_capture() {
  local filename="$1"
  local title="$2"
  local action="$3"
  local timestamp
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  cat > "${WIKI}/.wiki-pending/${filename}" <<EOF
---
title: "${title}"
evidence: "${SOURCE}"
evidence_type: "file"
capture_kind: "raw-direct"
suggested_action: "${action}"
suggested_pages:
  - concepts/relay-retry-policy.md
captured_at: "${timestamp}"
captured_by: "codex-spark-acceptance"
propagated_from: null
---

Raw-direct acceptance capture. Read the evidence path above and follow the
provider-neutral ingest skill. Perform the work yourself without delegation.
EOF
}

event_count() {
  local capture="$1"
  local status="$2"
  python3 - "${WIKI}/.ingest-runs.jsonl" "${capture}" "${status}" <<'PY'
import json
import pathlib
import sys

path = pathlib.Path(sys.argv[1])
capture, status = sys.argv[2:]
if not path.exists():
    print(0)
else:
    count = 0
    for line in path.read_text().splitlines():
        try:
            event = json.loads(line)
        except json.JSONDecodeError:
            continue
        count += event.get("capture") == capture and event.get("status") == status
    print(count)
PY
}

wait_for_capture() {
  local capture="$1"
  local deadline=$((SECONDS + 900))
  while [[ "${SECONDS}" -lt "${deadline}" ]]; do
    if [[ "$(event_count "${capture}" completed)" -eq 1 ]]; then
      return 0
    fi
    if [[ "$(event_count "${capture}" failed)" -gt 0 ]] \
       || [[ "$(event_count "${capture}" configuration_or_auth_failure)" -gt 0 ]] \
       || [[ "$(event_count "${capture}" provider_rate_limited)" -gt 0 ]]; then
      echo "Provider events for ${capture}:" >&2
      grep -F "\"capture\":\"${capture}\"" "${WIKI}/.ingest-runs.jsonl" >&2 || true
      return 1
    fi
    sleep 1
  done
  return 1
}

run_ingest() {
  local capture="$1"
  WIKI_CODEXBAR_EXECUTABLE="${TESTDIR}/codexbar-not-installed" \
  WIKI_DISPATCH_ACCEPTANCE_RETAIN_ARTIFACTS=1 \
    python3 "${DISPATCH}" tick --wiki "${WIKI}" --source manual
  wait_for_capture "${capture}" || fail "Spark ingest did not complete: ${capture}"
}

snapshot_content() {
  local output="$1"
  python3 - "${WIKI}" "${output}" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
result = {}
for category in ("concepts", "entities", "queries", "ideas"):
    for path in (root / category).rglob("*.md"):
        if path.name == "_index.md":
            continue
        result[str(path.relative_to(root))] = hashlib.sha256(path.read_bytes()).hexdigest()
pathlib.Path(sys.argv[2]).write_text(json.dumps(result, sort_keys=True) + "\n")
PY
}

write_source_cold
write_capture "01-cold.md" "Relay retry policy cold ingest" "create"
run_ingest "01-cold.md"
snapshot_content "${TESTDIR}/content-after-cold.json"
python3 - "${TESTDIR}/content-after-cold.json" <<'PY' || fail "cold ingest created no content page"
import json, sys
assert len(json.load(open(sys.argv[1]))) >= 1
PY

# Recreate the same inbox evidence path byte-for-byte. The sha256 short-circuit
# must archive the capture without changing or duplicating content pages.
write_source_cold
write_capture "02-exact-duplicate.md" "Relay retry policy exact duplicate" "auto"
run_ingest "02-exact-duplicate.md"
snapshot_content "${TESTDIR}/content-after-duplicate.json"
cmp -s "${TESTDIR}/content-after-cold.json" "${TESTDIR}/content-after-duplicate.json" \
  || fail "exact duplicate changed or duplicated content pages"

write_source_augmented
write_capture "03-related-augmentation.md" "Relay retry policy related augmentation" "augment"
run_ingest "03-related-augmentation.md"
snapshot_content "${TESTDIR}/content-after-augmentation.json"
rg -qi 'deterministic jitter|20%|45[- ]second' \
  "${WIKI}/concepts" "${WIKI}/entities" "${WIKI}/queries" "${WIKI}/ideas" \
  || fail "related augmentation is not retrievable from wiki content"

python3 "${REPO_ROOT}/scripts/wiki-manifest.py" validate "${WIKI}" >/dev/null \
  || fail "final manifest is invalid"

python3 - "${WIKI}" "${MODEL}" "${EFFORT}" <<'PY' \
  || fail "provider attribution, lifecycle, or non-delegation audit failed"
import json
import pathlib
import re
import shlex
import sys

root = pathlib.Path(sys.argv[1])
model, effort = sys.argv[2:]
events = [json.loads(line) for line in (root / ".ingest-runs.jsonl").read_text().splitlines() if line.strip()]
captures = ["01-cold.md", "02-exact-duplicate.md", "03-related-augmentation.md"]

for capture in captures:
    matching = [event for event in events if event.get("capture") == capture]
    assert sum(event.get("status") == "started" for event in matching) == 1, matching
    assert sum(event.get("status") == "completed" for event in matching) == 1, matching
    assert all(event.get("model") == model for event in matching), matching

archives = list((root / ".wiki-pending" / "archive").rglob("*.md"))
assert sorted(path.name for path in archives) == sorted(captures), archives
assert not list((root / ".wiki-pending").glob("*.processing"))
assert not list((root / ".wiki-pending").glob("*.md"))
assert not list((root / ".locks" / "ingest-slots").glob("*.lock"))

run_ids = [event["run_id"] for event in events if event.get("status") == "completed"]
assert len(run_ids) == 3

def command_events(path):
    commands = []
    for line in path.read_text(errors="replace").splitlines():
        try:
            payload = json.loads(line)
        except json.JSONDecodeError:
            continue
        stack = [payload]
        while stack:
            value = stack.pop()
            if isinstance(value, dict):
                if value.get("type") == "command_execution" and isinstance(value.get("command"), str):
                    commands.append(value["command"])
                stack.extend(value.values())
            elif isinstance(value, list):
                stack.extend(value)
    return commands

providers = {"claude", "grok", "codex"}

def invokes_provider(command, depth=0):
    if depth > 3:
        return None
    try:
        lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|()")
        lexer.whitespace_split = True
        tokens = list(lexer)
    except ValueError:
        tokens = command.split()
    separators = {";", "&&", "||", "|", "(", ")"}
    launchers = {"env", "sudo", "command", "nohup"}
    for index, token in enumerate(tokens):
        base = pathlib.Path(token).name
        previous = tokens[index - 1] if index else None
        if base in providers and (index == 0 or previous in separators or previous in launchers):
            return base
    for index, token in enumerate(tokens[:-1]):
        if token in {"-c", "-lc"}:
            nested = invokes_provider(tokens[index + 1], depth + 1)
            if nested:
                return nested
    return None

for run_id in run_ids:
    run_dir = root / ".locks" / "ingest-runs" / run_id
    metadata = json.loads((run_dir / "invocation.json").read_text())
    assert metadata == {
        "run_id": run_id,
        "provider": "codex",
        "model": model,
        "reasoning_effort": effort,
    }, metadata
    commands = command_events(run_dir / "stdout.jsonl")
    delegated = [(command, invokes_provider(command)) for command in commands]
    delegated = [(command, provider) for command, provider in delegated if provider]
    assert not delegated, delegated
PY

echo "PASS: three Codex Spark medium ingests completed through the real dispatcher"
echo "PASS: exact duplicate was a content no-op; related augmentation is retrievable"
echo "PASS: paths with spaces, missing CodexBar, attribution, lifecycle, and non-delegation checks passed"
echo "Raw ignored acceptance evidence: ${RAW_RUN}"
