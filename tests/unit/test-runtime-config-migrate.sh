#!/bin/bash
# Safe migration and local-config initialization use disposable fixtures only.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
CONFIG="${REPO_ROOT}/scripts/wiki_config.py"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

make_legacy_wiki() {
  local root="$1"
  mkdir -p "${root}/.wiki-pending"
  printf '# Schema\n' > "${root}/schema.md"
  printf '# Index\n' > "${root}/index.md"
  cat > "${root}/.wiki-config" <<'EOF'
role = "project"
main = "/legacy/machine/wiki"
created = "2026-08-11"
fork_to_main = true

[platform]
agent_cli = "claude"
headless_command = "claude --model sonnet --effort high -p"

[settings]
auto_commit = false
EOF
  cat > "${root}/.gitignore" <<'EOF'
.locks/
.ingest.log
custom-user-line
EOF
}

migration_args() {
  printf '%s\n' \
    --default-provider grok \
    --default-model grok-4.5 \
    --default-effort medium \
    --fallback-provider claude \
    --fallback-model sonnet \
    --fallback-effort low \
    --max-processes 10 \
    --dispatch-mode scheduled
}

run_migrate() {
  local root="$1"
  shift
  local args=()
  while IFS= read -r arg; do args+=("${arg}"); done < <(migration_args)
  python3 "${CONFIG}" migrate --wiki "${root}" "${args[@]}" "$@"
}

test_dry_run_is_complete_and_non_mutating() {
  local wiki="${TESTDIR}/dry-run"
  make_legacy_wiki "${wiki}"
  local before_config before_ignore output
  before_config="$(shasum -a 256 "${wiki}/.wiki-config")"
  before_ignore="$(shasum -a 256 "${wiki}/.gitignore")"

  output="$(run_migrate "${wiki}" --dry-run)" || fail "dry-run failed"
  [[ "$(shasum -a 256 "${wiki}/.wiki-config")" == "${before_config}" ]] || fail "dry-run changed structural config"
  [[ "$(shasum -a 256 "${wiki}/.gitignore")" == "${before_ignore}" ]] || fail "dry-run changed gitignore"
  [[ ! -e "${wiki}/.wiki-config.local" ]] || fail "dry-run created local config"
  find "${wiki}" -maxdepth 1 -name '.wiki-config.backup-*' | grep -q . && fail "dry-run created backup"
  grep -Fq -- '--- proposed .wiki-config ---' <<< "${output}" || fail "dry-run omitted structural proposal"
  grep -Fq -- '--- proposed trusted runtime config:' <<< "${output}" || fail "dry-run omitted trusted runtime proposal"
  grep -Fq 'default_profile = "grok_medium"' <<< "${output}" || fail "dry-run omitted selected default"
  grep -Fq 'fallback_profile = "claude_low"' <<< "${output}" || fail "dry-run omitted selected fallback"
  echo "PASS: test_dry_run_is_complete_and_non_mutating"
}

test_real_migration_splits_config_and_preserves_user_gitignore() {
  local wiki="${TESTDIR}/real"
  make_legacy_wiki "${wiki}"
  local output
  output="$(run_migrate "${wiki}")" || fail "real migration failed"

  grep -q '^role = "project"' "${wiki}/.wiki-config" || fail "structural role lost"
  grep -q '^created = "2026-08-11"' "${wiki}/.wiki-config" || fail "created date lost"
  if rg -q 'platform|settings|headless_command|main =|fork_to_main' "${wiki}/.wiki-config"; then
    fail "operational fields remain in structural config"
  fi
  [[ -f "${wiki}/.wiki-config.local" ]] || fail "local config missing"
  python3 "${CONFIG}" validate --wiki "${wiki}" >/dev/null || fail "migrated config does not validate"
  bash "${REPO_ROOT}/bin/wiki" config validate "${wiki}" >/dev/null || fail "public wiki config validate wrapper failed"
  grep -q '^fork_to_main = true' "${wiki}/.wiki-config.local" || fail "routing flag not preserved locally"
  grep -q '^auto_commit = false' "${wiki}/.wiki-config.local" || fail "auto_commit not preserved locally"
  [[ "$(grep -c '^\.wiki-config\.local$' "${wiki}/.gitignore")" -eq 0 ]] || fail "migration added an obsolete local-config ignore entry"
  grep -q '^custom-user-line$' "${wiki}/.gitignore" || fail "custom gitignore line lost"
  local backup_count
  backup_count="$(find "${wiki}" -maxdepth 1 -name '.wiki-config.backup-*' | wc -l | tr -d ' ')"
  [[ "${backup_count}" -eq 1 ]] || fail "expected one structural backup, got ${backup_count}"
  grep -Fq 'migration complete' <<< "${output}" || fail "completion message missing"
  echo "PASS: test_real_migration_splits_config_and_preserves_user_gitignore"
}

test_completed_migration_is_idempotent() {
  local wiki="${TESTDIR}/idempotent"
  make_legacy_wiki "${wiki}"
  run_migrate "${wiki}" >/dev/null
  local before_config before_local before_ignore output
  before_config="$(shasum -a 256 "${wiki}/.wiki-config")"
  before_local="$(shasum -a 256 "${wiki}/.wiki-config.local")"
  before_ignore="$(shasum -a 256 "${wiki}/.gitignore")"
  output="$(run_migrate "${wiki}")" || fail "second migration should be a no-op"
  [[ "$(shasum -a 256 "${wiki}/.wiki-config")" == "${before_config}" ]] || fail "second migration changed structural config"
  [[ "$(shasum -a 256 "${wiki}/.wiki-config.local")" == "${before_local}" ]] || fail "second migration changed local config"
  [[ "$(shasum -a 256 "${wiki}/.gitignore")" == "${before_ignore}" ]] || fail "second migration changed gitignore"
  grep -Fq 'already migrated' <<< "${output}" || fail "idempotent no-op message missing"
  echo "PASS: test_completed_migration_is_idempotent"
}

test_init_local_requires_explicit_profile_in_headless_mode() {
  local wiki="${TESTDIR}/init-local"
  mkdir -p "${wiki}/.wiki-pending"
  printf '# Schema\n' > "${wiki}/schema.md"
  printf '# Index\n' > "${wiki}/index.md"
  printf 'role = "main"\ncreated = "2026-08-11"\n' > "${wiki}/.wiki-config"

  local output rc
  set +e
  output="$(python3 "${CONFIG}" init-local --wiki "${wiki}" 2>&1)"
  rc=$?
  set -e
  [[ "${rc}" -ne 0 ]] || fail "headless init-local should require provider/model/effort"
  grep -Fq -- '--default-provider' <<< "${output}" || fail "headless init-local did not print structured option example"

  python3 "${CONFIG}" init-local --wiki "${wiki}" \
    --default-provider codex \
    --default-model gpt-5.3-codex-spark \
    --default-effort medium \
    --max-processes 2 \
    --dispatch-mode session_start >/dev/null || fail "explicit init-local failed"
  python3 "${CONFIG}" validate --wiki "${wiki}" >/dev/null || fail "initialized local config invalid"
  [[ "$(grep -c '^\.wiki-config\.local$' "${wiki}/.gitignore")" -eq 1 ]] || fail "init-local did not add ignore entry"
  echo "PASS: test_init_local_requires_explicit_profile_in_headless_mode"
}

test_pointer_and_unknown_legacy_command_are_rejected() {
  local pointer="${TESTDIR}/pointer"
  mkdir -p "${pointer}"
  printf 'role = "project-pointer"\nwiki = "./wiki"\n' > "${pointer}/.wiki-config"
  local output
  output="$(run_migrate "${pointer}" --dry-run 2>&1 || true)"
  grep -Fq 'project pointer, not a wiki root' <<< "${output}" || fail "project pointer migration not rejected"

  local wiki="${TESTDIR}/unknown-command"
  make_legacy_wiki "${wiki}"
  sed -i.bak 's|headless_command = .*|headless_command = "custom-agent --magic"|' "${wiki}/.wiki-config"
  rm -f "${wiki}/.wiki-config.bak"
  output="$(python3 "${CONFIG}" migrate --wiki "${wiki}" --dry-run 2>&1 || true)"
  grep -Fq -- '--default-provider' <<< "${output}" || fail "unknown legacy command did not require explicit profile"
  [[ ! -e "${wiki}/.wiki-config.local" ]] || fail "unknown command migration mutated wiki"
  echo "PASS: test_pointer_and_unknown_legacy_command_are_rejected"
}

test_string_boolean_never_enables_legacy_routing() {
  local wiki="${TESTDIR}/string-boolean"
  make_legacy_wiki "${wiki}"
  sed -i.bak 's/fork_to_main = true/fork_to_main = "false"/' "${wiki}/.wiki-config"
  rm -f "${wiki}/.wiki-config.bak"
  local output rc
  set +e
  output="$(run_migrate "${wiki}" --dry-run 2>&1)"
  rc=$?
  set -e
  [[ "${rc}" -ne 0 ]] || fail "string boolean was coerced into routing authorization"
  grep -Fq 'fork_to_main must be true or false' <<< "${output}" \
    || fail "string boolean error is not actionable: ${output}"
  [[ ! -e "${wiki}/.wiki-config.local" ]] || fail "invalid migration wrote runtime state"
  echo "PASS: test_string_boolean_never_enables_legacy_routing"
}

test_atomic_failure_restores_every_file() {
  local wiki="${TESTDIR}/rollback"
  make_legacy_wiki "${wiki}"
  local before_config before_ignore
  before_config="$(shasum -a 256 "${wiki}/.wiki-config")"
  before_ignore="$(shasum -a 256 "${wiki}/.gitignore")"

  WIKI_CONFIG_TEST_FAIL_STAGE=after_structural run_migrate "${wiki}" >/dev/null 2>&1 && fail "forced failure unexpectedly succeeded"
  [[ "$(shasum -a 256 "${wiki}/.wiki-config")" == "${before_config}" ]] || fail "rollback did not restore structural config"
  [[ "$(shasum -a 256 "${wiki}/.gitignore")" == "${before_ignore}" ]] || fail "rollback did not restore gitignore"
  [[ ! -e "${wiki}/.wiki-config.local" ]] || fail "rollback left local config"
  echo "PASS: test_atomic_failure_restores_every_file"
}

test_same_provider_and_effort_can_use_distinct_models() {
  local wiki="${TESTDIR}/same-provider-models"
  mkdir -p "${wiki}/.wiki-pending"
  printf '# Schema\n' > "${wiki}/schema.md"
  printf '# Index\n' > "${wiki}/index.md"
  printf 'role = "main"\n' > "${wiki}/.wiki-config"

  python3 "${CONFIG}" init-local --wiki "${wiki}" \
    --default-provider codex \
    --default-model model-a \
    --default-effort low \
    --fallback-provider codex \
    --fallback-model model-b \
    --fallback-effort low \
    --max-processes 2 >/dev/null \
    || fail "same-provider fallback profile was rejected"

  python3 "${CONFIG}" validate --wiki "${wiki}" --json > "${wiki}/validated.json" \
    || fail "same-provider fallback config is invalid"
  python3 - "${wiki}/validated.json" <<'PY' \
    || fail "same-provider fallback profiles collided"
import json
import sys

config = json.load(open(sys.argv[1], encoding="utf-8"))
ingest = config["ingest"]
assert ingest["default_profile"] == "codex_low"
assert ingest["fallback_profile"] == "codex_low_model-b"
assert set(ingest["profiles"]) == {"codex_low", "codex_low_model-b"}
PY
  echo "PASS: test_same_provider_and_effort_can_use_distinct_models"
}

test_relative_executable_path_is_rejected() {
  local wiki="${TESTDIR}/relative-executable"
  mkdir -p "${wiki}/.wiki-pending"
  printf '# Schema\n' > "${wiki}/schema.md"
  printf '# Index\n' > "${wiki}/index.md"
  printf 'role = "main"\n' > "${wiki}/.wiki-config"
  cat > "${wiki}/.wiki-config.local" <<'EOF'
[ingest]
dispatch_mode = "session_start"
max_processes = 1
default_profile = "p"
[ingest.profiles.p]
provider = "codex"
executable = "bin/codex"
model = "model"
reasoning_effort = "low"
EOF

  local output
  output="$(python3 "${CONFIG}" validate --wiki "${wiki}" 2>&1 || true)"
  grep -Fq 'ingest.profiles.p.executable must be an executable name or an absolute path' <<< "${output}" \
    || fail "relative executable path did not produce a dotted actionable error"
  echo "PASS: test_relative_executable_path_is_rejected"
}

test_migrate_local_requires_untracked_source_and_explicit_trust() {
  local project="${TESTDIR}/migrate-local"
  local wiki="${project}/wiki"
  local config_home="${TESTDIR}/migrate-local-config"
  mkdir -p "${project}"
  git -C "${project}" init -q
  mkdir -p "${wiki}/.wiki-pending"
  printf '# Schema\n' > "${wiki}/schema.md"
  printf '# Index\n' > "${wiki}/index.md"
  printf 'role = "project"\n' > "${wiki}/.wiki-config"
  local canonical_project
  canonical_project="$(cd "${project}" && pwd -P)"
  cat > "${wiki}/.wiki-config.local" <<'EOF'
[ingest]
dispatch_mode = "session_start"
max_processes = 1
default_profile = "codex_low"
[ingest.profiles.codex_low]
provider = "codex"
model = "test-model"
reasoning_effort = "low"
EOF

  local output
  output="$(env -u WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME \
    XDG_CONFIG_HOME="${config_home}" python3 "${CONFIG}" migrate-local \
    --wiki "${wiki}" --trust-workspace "${wiki}" --dry-run 2>&1 || true)"
  grep -Fq "must equal the canonical workspace: ${canonical_project}" <<< "${output}" \
    || fail "migrate-local accepted the wrong trust root"

  output="$(env -u WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME \
    XDG_CONFIG_HOME="${config_home}" python3 "${CONFIG}" migrate-local \
    --wiki "${wiki}" --trust-workspace "${project}" --dry-run)" \
    || fail "migrate-local dry-run failed"
  grep -Fq "trusted workspace: ${canonical_project}" <<< "${output}" \
    || fail "migrate-local dry-run omitted the canonical workspace"

  git -C "${project}" add -f wiki/.wiki-config.local
  output="$(env -u WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME \
    XDG_CONFIG_HOME="${config_home}" python3 "${CONFIG}" migrate-local \
    --wiki "${wiki}" --trust-workspace "${project}" 2>&1 || true)"
  grep -Fq 'refusing Git-tracked runtime config' <<< "${output}" \
    || fail "migrate-local imported a Git-tracked provider config"
  git -C "${project}" rm --cached -q wiki/.wiki-config.local

  printf '#!/bin/sh\nexit 0\n' > "${project}/evil-provider"
  chmod +x "${project}/evil-provider"
  sed -i.bak "/provider = \"codex\"/a\\
executable = \"${project}/evil-provider\"
" "${wiki}/.wiki-config.local"
  rm -f "${wiki}/.wiki-config.local.bak"
  output="$(env -u WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME \
    XDG_CONFIG_HOME="${config_home}" python3 "${CONFIG}" migrate-local \
    --wiki "${wiki}" --trust-workspace "${project}" 2>&1 || true)"
  grep -Fq 'resolves inside the project checkout' <<< "${output}" \
    || fail "migrate-local accepted a checkout executable: ${output}"
  local target
  target="$(env -u WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME \
    XDG_CONFIG_HOME="${config_home}" python3 "${CONFIG}" path --wiki "${wiki}")"
  [[ ! -e "${target}" ]] \
    || fail "failed migrate-local left an invalid trusted runtime file"
  sed -i.bak '/evil-provider/d' "${wiki}/.wiki-config.local"
  rm -f "${wiki}/.wiki-config.local.bak"

  env -u WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME \
    XDG_CONFIG_HOME="${config_home}" python3 "${CONFIG}" migrate-local \
    --wiki "${wiki}" --trust-workspace "${project}" >/dev/null \
    || fail "migrate-local did not import an ignored local config"
  env -u WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME \
    XDG_CONFIG_HOME="${config_home}" python3 "${CONFIG}" validate \
    --wiki "${wiki}" >/dev/null || fail "migrated external config is invalid"
  [[ -f "${wiki}/.wiki-config.local" ]] \
    || fail "migrate-local removed the inactive legacy copy"
  echo "PASS: test_migrate_local_requires_untracked_source_and_explicit_trust"
}

test_semantically_invalid_legacy_migration_restores_structural_config() {
  local wiki="${TESTDIR}/invalid-legacy-migration"
  make_legacy_wiki "${wiki}"
  local before_config
  before_config="$(shasum -a 256 "${wiki}/.wiki-config")"

  local args=()
  while IFS= read -r arg; do args+=("${arg}"); done < <(migration_args)
  local output rc
  set +e
  output="$(python3 "${CONFIG}" migrate --wiki "${wiki}" "${args[@]}" \
    --heartbeat-seconds 30 --stale-after-seconds 60 2>&1)"
  rc=$?
  set -e
  [[ "${rc}" -ne 0 ]] || fail "semantically invalid legacy migration succeeded"
  grep -Fq 'ingest.stale_after_seconds' <<< "${output}" \
    || fail "invalid migration did not report the semantic key"
  [[ "$(shasum -a 256 "${wiki}/.wiki-config")" == "${before_config}" ]] \
    || fail "invalid migration did not restore structural config"
  [[ ! -e "${wiki}/.wiki-config.local" ]] \
    || fail "invalid migration left runtime config"
  echo "PASS: test_semantically_invalid_legacy_migration_restores_structural_config"
}

test_dry_run_is_complete_and_non_mutating
test_real_migration_splits_config_and_preserves_user_gitignore
test_completed_migration_is_idempotent
test_init_local_requires_explicit_profile_in_headless_mode
test_pointer_and_unknown_legacy_command_are_rejected
test_string_boolean_never_enables_legacy_routing
test_atomic_failure_restores_every_file
test_same_provider_and_effort_can_use_distinct_models
test_relative_executable_path_is_rejected
test_migrate_local_requires_untracked_source_and_explicit_trust
test_semantically_invalid_legacy_migration_restores_structural_config
echo "ALL PASS"
