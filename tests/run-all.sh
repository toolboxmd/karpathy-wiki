#!/bin/bash
# Run all deterministic tests or one focused contract group.
set -e

# Existing behavioral fixtures write a checkout-local runtime file. Production
# never enables this compatibility switch. Security tests explicitly unset it
# to exercise the external trust boundary.
export WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME=1

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  echo "usage: bash tests/run-all.sh [full|skill|capture|scanner|dispatcher|provider|config|scheduler|schema|full-only]" >&2
  echo "       bash tests/run-all.sh --list <group>" >&2
}

is_known_group() {
  case "$1" in
    full|skill|capture|scanner|dispatcher|provider|config|scheduler|schema|full-only) return 0 ;;
    *) return 1 ;;
  esac
}

# Each deterministic test has one primary ownership group. Tests that span
# several subsystems or cover low-frequency operator flows remain full-only.
group_for_test() {
  case "$1" in
    unit/test-capture-skill.sh|\
    unit/test-codex-plugin-packaging.sh|\
    unit/test-deep-orientation-cold-start.sh|\
    unit/test-ingest-runs-record.sh|\
    unit/test-ingest-skill-provider-neutral.sh|\
    unit/test-ingest-skill.sh|\
    unit/test-loader-has-capture-resist-table.sh|\
    unit/test-session-start-loader-injection.sh|\
    unit/test-session-start-payload-budget.sh|\
    unit/test-skill-split-no-overlap.sh|\
    unit/test-using-karpathy-wiki-loader.sh)
      echo "skill"
      ;;
    unit/test-archive-strips-processing.sh|\
    unit/test-capture-atomic-publish.sh|\
    unit/test-capture-evidence-path.sh|\
    unit/test-capture-headless-unconfigured-cwd-aborts.sh|\
    unit/test-selective-promotion.sh|\
    unit/test-capture.sh|\
    unit/test-wiki-capture-cli.sh|\
    unit/test-wiki-capture-silent-bootstrap.sh)
      echo "capture"
      ;;
    unit/test-inbox-drift-scan.sh|\
    unit/test-mtime-defer.sh|\
    unit/test-raw-recovery-no-duplicate-captures.sh|\
    unit/test-raw-recovery.sh|\
    unit/test-raw-staging-no-race.sh)
      echo "scanner"
      ;;
    integration/test-dispatcher-concurrency.sh|\
    integration/test-dispatcher-refill.sh|\
    integration/test-session-start.sh|\
    integration/test-untrusted-checkout.sh|\
    unit/test-dispatch-scan-routing.sh|\
    unit/test-dispatcher-slots.sh|\
    unit/test-ingest-run-events.sh|\
    unit/test-no-direct-spawn-path.sh|\
    unit/test-session-start-claude-code-hookeventname.sh|\
    unit/test-worker-heartbeat.sh|\
    unit/test-worker-reconciliation.sh)
      echo "dispatcher"
      ;;
    integration/test-codex-spark-ingest.sh|\
    integration/test-provider-fallback.sh|\
    integration/test-provider-worker.sh|\
    integration/test-worker-lifecycle.sh|\
    unit/test-provider-adapters.sh|\
    unit/test-provider-classification.sh|\
    unit/test-usage-monitor.sh)
      echo "provider"
      ;;
    integration/test-leg2-end-to-end.sh|\
    unit/test-config-read.sh|\
    unit/test-lib.sh|\
    unit/test-resolver-no-cross-project-leak.sh|\
    unit/test-resolver-walks-up.sh|\
    unit/test-runtime-config-migrate.sh|\
    unit/test-runtime-config.sh|\
    unit/test-single-authority-routing.sh|\
    unit/test-wiki-resolve.sh|\
    unit/test-wiki-use.sh)
      echo "config"
      ;;
    integration/test-scheduler-lifecycle.sh|\
    unit/test-scheduler-plist.sh)
      echo "scheduler"
      ;;
    unit/test-backfill-quality.sh|\
    unit/test-build-index.sh|\
    unit/test-discover.sh|\
    unit/test-fix-frontmatter.sh|\
    unit/test-index-threshold-fires.sh|\
    unit/test-lint-tags.sh|\
    unit/test-manifest-validate.sh|\
    unit/test-manifest.sh|\
    unit/test-migrate-v2-hardening.sh|\
    unit/test-migrate-v2.2.sh|\
    unit/test-migrate-v2.3.sh|\
    unit/test-normalize-frontmatter.sh|\
    unit/test-relink.sh|\
    unit/test-reserved-set-update.sh|\
    unit/test-validate-code-block-skip.sh|\
    unit/test-validate-deleted-categories.sh|\
    unit/test-validate-page.sh|\
    unit/test-yaml-helper.sh)
      echo "schema"
      ;;
    *)
      echo "full-only"
      ;;
  esac
}

list_only=false
group="${1:-full}"
if [[ "${group}" == "--list" ]]; then
  list_only=true
  group="${2:-}"
  [[ "$#" -eq 2 ]] || { usage; exit 2; }
elif [[ "$#" -gt 1 ]]; then
  usage
  exit 2
fi

if ! is_known_group "${group}"; then
  echo "unknown test group: ${group}" >&2
  usage
  exit 2
fi

shopt -s nullglob
all_tests=()
for test_path in "${SCRIPT_DIR}"/unit/test-*.sh "${SCRIPT_DIR}"/integration/test-*.sh; do
  all_tests+=("${test_path#${SCRIPT_DIR}/}")
done

selected_tests=()
for test_path in "${all_tests[@]}"; do
  owner="$(group_for_test "${test_path}")"
  if [[ "${group}" == "full" || "${owner}" == "${group}" ]]; then
    selected_tests+=("${test_path}")
  fi
done

if [[ "${#selected_tests[@]}" -eq 0 ]]; then
  echo "test group selected no tests: ${group}" >&2
  exit 2
fi

echo "selected group: ${group}"
if [[ "${list_only}" == true ]]; then
  printf '%s\n' "${selected_tests[@]}"
  exit 0
fi

echo "executing ${#selected_tests[@]} test files:"
printf '  - %s\n' "${selected_tests[@]}"
echo

passed=0
failed=0
failed_tests=()

run() {
  local name="$1"
  shift
  echo "=== ${name} ==="
  if "$@"; then
    passed=$((passed + 1))
  else
    failed=$((failed + 1))
    failed_tests+=("${name}")
  fi
  echo
}

for test_path in "${selected_tests[@]}"; do
  run "${test_path}" bash "${SCRIPT_DIR}/${test_path}"
done

echo "========================"
echo "passed: ${passed}"
echo "failed: ${failed}"
if [[ "${failed}" -gt 0 ]]; then
  echo "failing tests:"
  for t in "${failed_tests[@]}"; do echo "  - ${t}"; done
  exit 1
fi
