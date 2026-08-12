#!/bin/bash
# Runtime config contract for the provider-aware ingest dispatcher.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONFIG="${REPO_ROOT}/scripts/wiki_config.py"
export WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME=1
# shellcheck source=/dev/null
source "${REPO_ROOT}/scripts/wiki-lib.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

make_wiki() {
  local root="$1"
  local role="${2:-main}"
  mkdir -p "${root}/.wiki-pending"
  printf '# Schema\n' > "${root}/schema.md"
  printf '# Index\n' > "${root}/index.md"
  cat > "${root}/.wiki-config" <<EOF
role = "${role}"
created = "2026-08-11"
EOF
}

write_valid_local() {
  local root="$1"
  cat > "${root}/.wiki-config.local" <<'EOF'
[ingest]
dispatch_mode = "scheduled"
max_processes = 10
default_profile = "grok_medium"
fallback_profile = "sonnet_low"
heartbeat_seconds = 30
stale_after_seconds = 600
usage_monitor = "auto"

[ingest.profiles.grok_medium]
provider = "grok"
executable = "/Applications/Grok Build/grok"
model = "grok-4.5"
reasoning_effort = "medium"
max_processes = 8

[ingest.profiles.sonnet_low]
provider = "claude"
model = "sonnet"
reasoning_effort = "low"

[settings]
auto_commit = true
EOF
}

test_valid_config_returns_normalized_json() {
  local wiki="${TESTDIR}/valid"
  make_wiki "${wiki}"
  write_valid_local "${wiki}"

  local output
  output="$(python3 "${CONFIG}" validate --wiki "${wiki}" --json)" || fail "valid config did not validate"
  python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["wiki_role"] == "main"
assert d["ingest"]["dispatch_mode"] == "scheduled"
assert d["ingest"]["max_processes"] == 10
assert d["ingest"]["max_attempts"] == 4
assert d["ingest"]["profiles"]["grok_medium"]["executable"] == "/Applications/Grok Build/grok"
assert d["ingest"]["profiles"]["sonnet_low"]["executable"] == "claude"
assert d["settings"]["auto_commit"] is True
' <<< "${output}" || fail "normalized config JSON is incorrect"
  echo "PASS: test_valid_config_returns_normalized_json"
}

test_missing_local_is_actionable() {
  local wiki="${TESTDIR}/missing"
  make_wiki "${wiki}"
  local canonical_wiki
  canonical_wiki="$(cd "${wiki}" && pwd -P)"

  local output rc
  set +e
  output="$(python3 "${CONFIG}" validate --wiki "${wiki}" 2>&1)"
  rc=$?
  set -e
  [[ "${rc}" -ne 0 ]] || fail "missing local config should fail"
  grep -Fq "runtime configuration missing: ${canonical_wiki}/.wiki-config.local" <<< "${output}" || fail "missing local path not reported"
  grep -Fq "Run: wiki config init-local ${canonical_wiki}" <<< "${output}" || fail "init-local command not reported"
  echo "PASS: test_missing_local_is_actionable"
}

test_legacy_structural_config_requires_migration() {
  local wiki="${TESTDIR}/legacy"
  make_wiki "${wiki}"
  local canonical_wiki
  canonical_wiki="$(cd "${wiki}" && pwd -P)"
  cat >> "${wiki}/.wiki-config" <<'EOF'

[platform]
agent_cli = "claude"
headless_command = "claude -p"

[settings]
auto_commit = true
EOF

  local output rc
  set +e
  output="$(python3 "${CONFIG}" validate --wiki "${wiki}" 2>&1)"
  rc=$?
  set -e
  [[ "${rc}" -ne 0 ]] || fail "legacy config should fail"
  grep -Fq "legacy ingest configuration detected in ${canonical_wiki}/.wiki-config" <<< "${output}" || fail "legacy config not identified"
  grep -Fq "Run: wiki config migrate ${canonical_wiki} --trust-workspace" <<< "${output}" || fail "migration command not reported"
  echo "PASS: test_legacy_structural_config_requires_migration"
}

expect_invalid() {
  local name="$1"
  local expected="$2"
  local config_body="$3"
  local wiki="${TESTDIR}/invalid-${name}"
  make_wiki "${wiki}"
  printf '%s\n' "${config_body}" > "${wiki}/.wiki-config.local"

  local output rc
  set +e
  output="$(python3 "${CONFIG}" validate --wiki "${wiki}" 2>&1)"
  rc=$?
  set -e
  [[ "${rc}" -ne 0 ]] || fail "${name} should fail validation"
  grep -Fq "${expected}" <<< "${output}" || fail "${name} missing '${expected}'; got: ${output}"
}

test_invalid_values_are_rejected_by_dotted_key() {
  expect_invalid "mode" "ingest.dispatch_mode" $'[ingest]\ndispatch_mode = "cron"\nmax_processes = 1\ndefault_profile = "p"\n[ingest.profiles.p]\nprovider = "grok"\nmodel = "grok-4.5"\nreasoning_effort = "medium"'
  expect_invalid "limit" "ingest.max_processes" $'[ingest]\ndispatch_mode = "session_start"\nmax_processes = 0\ndefault_profile = "p"\n[ingest.profiles.p]\nprovider = "grok"\nmodel = "grok-4.5"\nreasoning_effort = "medium"'
  expect_invalid "default" "ingest.default_profile" $'[ingest]\ndispatch_mode = "session_start"\nmax_processes = 1\ndefault_profile = "missing"\n[ingest.profiles.p]\nprovider = "grok"\nmodel = "grok-4.5"\nreasoning_effort = "medium"'
  expect_invalid "provider" "ingest.profiles.p.provider" $'[ingest]\ndispatch_mode = "session_start"\nmax_processes = 1\ndefault_profile = "p"\n[ingest.profiles.p]\nprovider = "unknown"\nmodel = "x"\nreasoning_effort = "medium"'
  expect_invalid "effort" "ingest.profiles.p.reasoning_effort" $'[ingest]\ndispatch_mode = "session_start"\nmax_processes = 1\ndefault_profile = "p"\n[ingest.profiles.p]\nprovider = "grok"\nmodel = "x"\nreasoning_effort = "turbo"'
  expect_invalid "heartbeat" "ingest.stale_after_seconds" $'[ingest]\ndispatch_mode = "session_start"\nmax_processes = 1\ndefault_profile = "p"\nheartbeat_seconds = 30\nstale_after_seconds = 60\n[ingest.profiles.p]\nprovider = "grok"\nmodel = "x"\nreasoning_effort = "medium"'
  expect_invalid "profile-name" "unsafe profile name" $'[ingest]\ndispatch_mode = "session_start"\nmax_processes = 1\ndefault_profile = "bad.profile"\n[ingest.profiles."bad.profile"]\nprovider = "grok"\nmodel = "x"\nreasoning_effort = "medium"'
  echo "PASS: test_invalid_values_are_rejected_by_dotted_key"
}

test_fallback_is_optional_but_must_resolve_and_differ() {
  local wiki="${TESTDIR}/no-fallback"
  make_wiki "${wiki}"
  cat > "${wiki}/.wiki-config.local" <<'EOF'
[ingest]
dispatch_mode = "session_start"
max_processes = 1
default_profile = "codex_profile"
usage_monitor = "off"

[ingest.profiles.codex_profile]
provider = "codex"
model = "gpt-5.3-codex-spark"
reasoning_effort = "medium"
EOF
  python3 "${CONFIG}" validate --wiki "${wiki}" >/dev/null || fail "fallback should be optional"

  cat > "${wiki}/.wiki-config.local" <<'EOF'
[ingest]
dispatch_mode = "session_start"
max_processes = 1
default_profile = "codex_profile"
fallback_profile = "codex_profile"

[ingest.profiles.codex_profile]
provider = "codex"
model = "gpt-5.3-codex-spark"
reasoning_effort = "medium"
EOF
  local output
  output="$(python3 "${CONFIG}" validate --wiki "${wiki}" 2>&1 || true)"
  grep -Fq "ingest.fallback_profile" <<< "${output}" || fail "same fallback/default should fail"
  echo "PASS: test_fallback_is_optional_but_must_resolve_and_differ"
}

test_codexbar_is_not_required_for_validation() {
  local wiki="${TESTDIR}/no-codexbar"
  make_wiki "${wiki}"
  write_valid_local "${wiki}"
  local isolated_bin="${TESTDIR}/no-codexbar-bin"
  mkdir -p "${isolated_bin}"
  ln -s "$(command -v python3)" "${isolated_bin}/python3"
  PATH="${isolated_bin}:/usr/bin:/bin" python3 "${CONFIG}" validate --wiki "${wiki}" >/dev/null || fail "CodexBar absence should not invalidate config"
  echo "PASS: test_codexbar_is_not_required_for_validation"
}

test_project_pointer_is_not_a_wiki_runtime_root() {
  local root="${TESTDIR}/pointer"
  mkdir -p "${root}"
  cat > "${root}/.wiki-config" <<'EOF'
role = "project-pointer"
wiki = "./wiki"
created = "2026-08-11"
fork_to_main = false
EOF
  local output rc
  set +e
  output="$(python3 "${CONFIG}" validate --wiki "${root}" 2>&1)"
  rc=$?
  set -e
  [[ "${rc}" -ne 0 ]] || fail "project pointer should not validate as runtime root"
  grep -Fq "project pointer, not a wiki root" <<< "${output}" || fail "project pointer error is not actionable"
  echo "PASS: test_project_pointer_is_not_a_wiki_runtime_root"
}

test_shell_readers_do_not_cross_config_scopes() {
  local wiki="${TESTDIR}/scope-readers"
  make_wiki "${wiki}"
  write_valid_local "${wiki}"
  [[ "$(wiki_structural_config_get "${wiki}" role)" == "main" ]] || fail "structural reader missed role"
  [[ "$(wiki_runtime_config_get "${wiki}" settings.auto_commit)" == "true" ]] || fail "runtime reader missed auto_commit"
  if wiki_structural_config_get "${wiki}" settings.auto_commit >/dev/null 2>&1; then
    fail "structural reader silently crossed into runtime config"
  fi
  echo "PASS: test_shell_readers_do_not_cross_config_scopes"
}

test_update_runtime_changes_only_adapter_owned_fields() {
  local wiki="${TESTDIR}/update-runtime"
  make_wiki "${wiki}"
  write_valid_local "${wiki}"

  python3 "${CONFIG}" update-runtime \
    --wiki "${wiki}" \
    --dispatch-mode session_start \
    --fork-to-main >/dev/null || fail "runtime update failed"

  local output
  output="$(python3 "${CONFIG}" show --wiki "${wiki}")" || fail "updated config did not validate"
  python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["ingest"]["dispatch_mode"] == "session_start"
assert d["routing"]["fork_to_main"] is True
assert d["ingest"]["default_profile"] == "grok_medium"
assert d["ingest"]["profiles"]["grok_medium"]["model"] == "grok-4.5"
assert d["ingest"]["profiles"]["sonnet_low"]["reasoning_effort"] == "low"
assert d["settings"]["auto_commit"] is True
' <<< "${output}" || fail "runtime update changed unrelated fields"

  python3 "${CONFIG}" update-runtime --wiki "${wiki}" --no-fork-to-main >/dev/null \
    || fail "runtime routing reset failed"
  [[ "$(wiki_runtime_config_get "${wiki}" routing.fork_to_main)" == "false" ]] \
    || fail "runtime routing reset was not persisted"

  local error rc
  set +e
  error="$(python3 "${CONFIG}" update-runtime --wiki "${wiki}" 2>&1)"
  rc=$?
  set -e
  [[ "${rc}" -ne 0 ]] || fail "empty runtime update should fail"
  grep -Fq "no update option supplied" <<< "${error}" \
    || fail "empty runtime update error is not actionable"
  echo "PASS: test_update_runtime_changes_only_adapter_owned_fields"
}

test_existing_local_config_repairs_ignore_entry() {
  local wiki="${TESTDIR}/repair-ignore"
  make_wiki "${wiki}"
  write_valid_local "${wiki}"
  printf 'custom-line\n' > "${wiki}/.gitignore"
  local before_local
  before_local="$(shasum -a 256 "${wiki}/.wiki-config.local")"

  python3 "${CONFIG}" init-local --wiki "${wiki}" >/dev/null \
    || fail "idempotent init-local failed"
  [[ "$(shasum -a 256 "${wiki}/.wiki-config.local")" == "${before_local}" ]] \
    || fail "idempotent init-local rewrote runtime choices"
  grep -Fxq 'custom-line' "${wiki}/.gitignore" \
    || fail "idempotent init-local lost existing gitignore content"
  [[ "$(grep -Fxc '.wiki-config.local' "${wiki}/.gitignore")" -eq 1 ]] \
    || fail "idempotent init-local did not repair ignore entry exactly once"
  echo "PASS: test_existing_local_config_repairs_ignore_entry"
}

test_checkout_runtime_config_is_not_trusted_implicitly() {
  local wiki="${TESTDIR}/untrusted-checkout"
  make_wiki "${wiki}" project
  write_valid_local "${wiki}"

  local output rc
  set +e
  output="$(env -u WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME \
    XDG_CONFIG_HOME="${TESTDIR}/untrusted-config-home" \
    python3 "${CONFIG}" validate --wiki "${wiki}" 2>&1)"
  rc=$?
  set -e
  [[ "${rc}" -ne 0 ]] || fail "checkout runtime config was trusted implicitly"
  grep -Fq 'trusted runtime configuration missing' <<< "${output}" \
    || fail "missing external trust error is not actionable: ${output}"
  grep -Fq 'wiki config init-local' <<< "${output}" \
    || fail "missing external trust error omitted the consent command"
  echo "PASS: test_checkout_runtime_config_is_not_trusted_implicitly"
}

test_init_local_records_runtime_outside_checkout() {
  local wiki="${TESTDIR}/external-runtime"
  local config_home="${TESTDIR}/external-config-home"
  make_wiki "${wiki}" project

  env -u WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME \
    XDG_CONFIG_HOME="${config_home}" python3 "${CONFIG}" init-local \
    --wiki "${wiki}" \
    --trust-workspace "${wiki}" \
    --default-provider codex \
    --default-model test-model \
    --default-effort low >/dev/null \
    || fail "external init-local failed"

  local runtime_path
  runtime_path="$(env -u WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME \
    XDG_CONFIG_HOME="${config_home}" \
    python3 "${CONFIG}" path --wiki "${wiki}")" \
    || fail "runtime path command failed"
  [[ "${runtime_path}" == "${config_home}/karpathy-wiki/wikis/"*'/runtime.toml' ]] \
    || fail "runtime config is not under the user config home: ${runtime_path}"
  [[ -f "${runtime_path}" ]] || fail "external runtime config was not created"
  [[ "$(stat -f '%Lp' "${runtime_path}" 2>/dev/null || stat -c '%a' "${runtime_path}")" == "600" ]] \
    || fail "external runtime config is not mode 0600"
  [[ ! -e "${wiki}/.wiki-config.local" ]] \
    || fail "init-local wrote executable runtime configuration into the checkout"
  grep -Fq "wiki_root = \"$(cd "${wiki}" && pwd -P)\"" "${runtime_path}" \
    || fail "external runtime config is not bound to its trusted wiki root"
  env -u WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME \
  XDG_CONFIG_HOME="${config_home}" python3 "${CONFIG}" validate \
    --wiki "${wiki}" >/dev/null || fail "external runtime config did not validate"

  chmod 0644 "${runtime_path}"
  local output
  output="$(env -u WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME \
    XDG_CONFIG_HOME="${config_home}" python3 "${CONFIG}" validate \
    --wiki "${wiki}" 2>&1 || true)"
  grep -Fq 'must have mode 0600' <<< "${output}" \
    || fail "world-readable runtime config was accepted"
  chmod 0600 "${runtime_path}"
  echo "PASS: test_init_local_records_runtime_outside_checkout"
}

test_checkout_resolving_provider_executable_is_rejected() {
  local project="${TESTDIR}/provider-checkout"
  local wiki="${project}/wiki"
  local config_home="${TESTDIR}/provider-config-home"
  make_wiki "${wiki}" project
  cat > "${project}/.wiki-config" <<'EOF'
role = "project-pointer"
wiki = "./wiki"
EOF
  mkdir -p "${project}/bin"
  printf '#!/bin/bash\nexit 0\n' > "${project}/bin/evil-provider"
  chmod +x "${project}/bin/evil-provider"

  local output rc
  set +e
  output="$(env -u WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME \
    XDG_CONFIG_HOME="${config_home}" python3 "${CONFIG}" init-local \
    --wiki "${wiki}" \
    --trust-workspace "${project}" \
    --default-provider codex \
    --default-executable "${project}/bin/evil-provider" \
    --default-model test-model \
    --default-effort low 2>&1)"
  rc=$?
  set -e
  [[ "${rc}" -ne 0 ]] || fail "checkout executable was accepted"
  grep -Fq 'resolves inside the project checkout' <<< "${output}" \
    || fail "checkout executable rejection is not actionable: ${output}"
  echo "PASS: test_checkout_resolving_provider_executable_is_rejected"
}

test_valid_config_returns_normalized_json
test_missing_local_is_actionable
test_legacy_structural_config_requires_migration
test_invalid_values_are_rejected_by_dotted_key
test_fallback_is_optional_but_must_resolve_and_differ
test_codexbar_is_not_required_for_validation
test_project_pointer_is_not_a_wiki_runtime_root
test_shell_readers_do_not_cross_config_scopes
test_update_runtime_changes_only_adapter_owned_fields
test_existing_local_config_repairs_ignore_entry
test_checkout_runtime_config_is_not_trusted_implicitly
test_init_local_records_runtime_outside_checkout
test_checkout_resolving_provider_executable_is_rejected
echo "ALL PASS"
