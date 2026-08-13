#!/bin/bash
# Verify the shared scanner scans inbox/ and creates raw-direct captures.
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
SCAN="${REPO_ROOT}/scripts/wiki-scan.sh"
INIT="${REPO_ROOT}/scripts/wiki-init.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

TESTDIR="$(mktemp -d)"
trap 'rm -rf "${TESTDIR}"' EXIT

WIKI="${TESTDIR}/wiki"
bash "${INIT}" main "${WIKI}" >/dev/null
WIKI_CANONICAL="$(cd "${WIKI}" && pwd -P)"
# Drop a file in inbox/ with mtime in the past (so it's not deferred)
printf '# Test note\n\nSome content for ingestion.\n' > "${WIKI}/inbox/note.md"
# Make it 10 seconds old so the 5-second mtime defer doesn't apply
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" "${WIKI}/inbox/note.md"

# Run the shared source scanner directly; queue dispatch is tested separately.
bash "${SCAN}" "${WIKI}" >/dev/null

# Assert a raw-direct capture appeared in .wiki-pending/
capture=""
for f in "${WIKI}/.wiki-pending"/drift-*; do
  [[ -f "${f}" ]] || continue
  capture="${f}"
  break
done
[[ -n "${capture}" ]] || fail "no drift- capture appeared in .wiki-pending/"

# Inspect the capture frontmatter for capture_kind: raw-direct
grep -q 'capture_kind: "raw-direct"' "${capture}" \
  || fail "drift capture missing capture_kind: raw-direct"
grep -q "evidence: \"${WIKI_CANONICAL}/inbox/note.md\"" "${capture}" \
  || fail "drift capture evidence path wrong: $(grep '^evidence:' "${capture}")"
grep -Eq '^capture_id: "cap-[a-f0-9]+"' "${capture}" \
  || fail "scanner capture lacks portable capture_id"
grep -q '^promotion_policy: "none"' "${capture}" \
  || fail "main-wiki scanner capture should not be promotable"

# A nested project wiki configured for both marks scanner captures selective,
# while still queueing them only in the project wiki.
PROJECT_ROOT="${TESTDIR}/project-both"
PROJECT_WIKI="${PROJECT_ROOT}/wiki"
mkdir -p "${PROJECT_ROOT}"
bash "${INIT}" project "${PROJECT_WIKI}" "${WIKI}" >/dev/null
cat > "${PROJECT_ROOT}/.wiki-config" <<'EOF'
role = "project-pointer"
wiki = "./wiki"
created = "2026-08-12"
fork_to_main = true
EOF
printf 'project source\n' > "${PROJECT_WIKI}/inbox/project.md"
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" \
  "${PROJECT_WIKI}/inbox/project.md"
bash "${SCAN}" "${PROJECT_WIKI}" >/dev/null
project_capture="$(find "${PROJECT_WIKI}/.wiki-pending" -maxdepth 1 -type f -name 'drift-*.md' -print -quit)"
grep -q '^promotion_policy: "selective"' "${project_capture}" \
  || fail "both-mode project scanner capture lacks selective policy"

# A project wiki with trusted runtime configuration outside the checkout must
# receive the same selective policy. No obsolete .wiki-config.local file is
# present in the wiki root.
EXTERNAL_PROJECT="${TESTDIR}/external-project"
EXTERNAL_CONFIG_HOME="${TESTDIR}/external-config-home"
bash "${INIT}" project "${EXTERNAL_PROJECT}" "${WIKI}" >/dev/null
env -u WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME \
  XDG_CONFIG_HOME="${EXTERNAL_CONFIG_HOME}" \
  python3 "${REPO_ROOT}/scripts/wiki_config.py" init-local \
    --wiki "${EXTERNAL_PROJECT}" \
    --trust-workspace "${EXTERNAL_PROJECT}" \
    --default-provider codex \
    --default-model test-model \
    --default-effort low \
    --fork-to-main >/dev/null
[[ ! -e "${EXTERNAL_PROJECT}/.wiki-config.local" ]] \
  || fail "external runtime setup wrote checkout-local config"
printf 'external project source\n' > "${EXTERNAL_PROJECT}/inbox/external.md"
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" \
  "${EXTERNAL_PROJECT}/inbox/external.md"
env -u WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME \
  XDG_CONFIG_HOME="${EXTERNAL_CONFIG_HOME}" \
  bash "${SCAN}" "${EXTERNAL_PROJECT}" >/dev/null
external_capture="$(find "${EXTERNAL_PROJECT}/.wiki-pending" -maxdepth 1 -type f -name 'drift-*.md' -print -quit)"
grep -q '^promotion_policy: "selective"' "${external_capture}" \
  || fail "external runtime both-mode capture lacks selective policy"

# An existing external runtime config is authoritative when it explicitly
# disables promotion, even if an older parent pointer still says `both`.
cat > "${TESTDIR}/.wiki-config" <<EOF
role = "project-pointer"
wiki = "./external-project"
created = "2026-08-12"
fork_to_main = true
EOF
external_runtime="$(env -u WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME XDG_CONFIG_HOME="${EXTERNAL_CONFIG_HOME}" \
  python3 "${REPO_ROOT}/scripts/wiki_config.py" path --wiki "${EXTERNAL_PROJECT}")"
sed -i.bak 's/^fork_to_main = true/fork_to_main = false/' "${external_runtime}"
rm -f "${external_runtime}.bak"
[[ "$(env -u WIKI_CONFIG_TEST_ALLOW_CHECKOUT_RUNTIME XDG_CONFIG_HOME="${EXTERNAL_CONFIG_HOME}" \
  bash -c 'source "$1/scripts/wiki-lib.sh"; wiki_promotion_policy "$2"' _ "${REPO_ROOT}" "${EXTERNAL_PROJECT}")" == "none" ]] \
  || fail "explicit external runtime false fell back to stale parent pointer true"

# Publication failures must reach the caller instead of being swallowed by a
# later clean manifest check.
WIKI_FAIL="${TESTDIR}/publication-failure"
bash "${INIT}" main "${WIKI_FAIL}" >/dev/null
printf 'source remains durable\n' > "${WIKI_FAIL}/inbox/fail.md"
touch -t "$(date -v-10S '+%Y%m%d%H%M.%S' 2>/dev/null || date -d '10 seconds ago' '+%Y%m%d%H%M.%S')" \
  "${WIKI_FAIL}/inbox/fail.md"
FAKE_BIN="${TESTDIR}/fake-bin"
mkdir -p "${FAKE_BIN}"
cat > "${FAKE_BIN}/mktemp" <<'EOF'
#!/bin/bash
exit 1
EOF
chmod +x "${FAKE_BIN}/mktemp"
PATH="${FAKE_BIN}:${PATH}" bash "${SCAN}" "${WIKI_FAIL}" >/dev/null 2>&1 \
  && fail "scanner swallowed capture publication failure"
[[ -f "${WIKI_FAIL}/inbox/fail.md" ]] || fail "publication failure lost inbox source"

WIKI_MANIFEST_FAIL="${TESTDIR}/manifest-failure"
bash "${INIT}" main "${WIKI_MANIFEST_FAIL}" >/dev/null
printf '{not valid json\n' > "${WIKI_MANIFEST_FAIL}/.manifest.json"
bash "${SCAN}" "${WIKI_MANIFEST_FAIL}" >/dev/null 2>&1 \
  && fail "scanner treated a failed manifest diff as clean"

echo "PASS: inbox/ drift scan creates raw-direct captures"
