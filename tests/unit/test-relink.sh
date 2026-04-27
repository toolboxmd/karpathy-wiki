#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
RELINK="${REPO_ROOT}/scripts/wiki-relink.py"

setup() {
  TMP="$(mktemp -d)"
  WIKI="${TMP}/wiki"
  mkdir -p "${WIKI}/concepts" "${WIKI}/projects/toolboxmd/karpathy-wiki" "${WIKI}/raw"
  touch "${WIKI}/.wiki-config"
}
teardown() { rm -rf "${TMP}"; }

test_rewrites_relative_link_to_leading_slash() {
  setup
  cat > "${WIKI}/concepts/source.md" <<'EOF'
See [v22](v22-architectural-cut.md) for context.
EOF
  cat > "${WIKI}/projects/toolboxmd/karpathy-wiki/v22-architectural-cut.md" <<'EOF'
content
EOF
  python3 "${RELINK}" --wiki-root "${WIKI}" \
    --moved "concepts/v22-architectural-cut.md=projects/toolboxmd/karpathy-wiki/v22-architectural-cut.md"
  grep -q "/projects/toolboxmd/karpathy-wiki/v22-architectural-cut.md" "${WIKI}/concepts/source.md" || {
    echo "FAIL: link not rewritten"
    teardown; exit 1
  }
  teardown
}

test_only_moved_pages_touched() {
  setup
  echo "[other](other-page.md) untouched" > "${WIKI}/concepts/source.md"
  python3 "${RELINK}" --wiki-root "${WIKI}" \
    --moved "concepts/somepage.md=projects/x.md"
  # The other-page.md link must NOT be rewritten
  grep -q "(other-page.md)" "${WIKI}/concepts/source.md" || {
    echo "FAIL: unrelated link was rewritten"
    teardown; exit 1
  }
  teardown
}

test_idempotent() {
  setup
  cat > "${WIKI}/concepts/source.md" <<'EOF'
See [v22](/projects/toolboxmd/karpathy-wiki/v22.md).
EOF
  python3 "${RELINK}" --wiki-root "${WIKI}" \
    --moved "concepts/v22.md=projects/toolboxmd/karpathy-wiki/v22.md"
  before="$(shasum -a 256 "${WIKI}/concepts/source.md")"
  python3 "${RELINK}" --wiki-root "${WIKI}" \
    --moved "concepts/v22.md=projects/toolboxmd/karpathy-wiki/v22.md"
  after="$(shasum -a 256 "${WIKI}/concepts/source.md")"
  [[ "${before}" == "${after}" ]] || { echo "FAIL: not idempotent"; teardown; exit 1; }
  teardown
}

test_external_links_untouched() {
  setup
  cat > "${WIKI}/concepts/source.md" <<'EOF'
[external](https://example.com/path) and [anchor](#section).
EOF
  python3 "${RELINK}" --wiki-root "${WIKI}" \
    --moved "concepts/foo.md=projects/foo.md"
  grep -q "https://example.com/path" "${WIKI}/concepts/source.md" || { echo "FAIL: https link mangled"; teardown; exit 1; }
  grep -q "(#section)" "${WIKI}/concepts/source.md" || { echo "FAIL: anchor mangled"; teardown; exit 1; }
  teardown
}

test_handles_already_leading_slash_form() {
  setup
  cat > "${WIKI}/concepts/source.md" <<'EOF'
See [v22](/concepts/v22.md).
EOF
  python3 "${RELINK}" --wiki-root "${WIKI}" \
    --moved "concepts/v22.md=projects/toolboxmd/karpathy-wiki/v22.md"
  grep -q "/projects/toolboxmd/karpathy-wiki/v22.md" "${WIKI}/concepts/source.md" || {
    echo "FAIL: leading-/ form not rewritten"
    teardown; exit 1
  }
  teardown
}

test_rewrites_relative_link_to_leading_slash
test_only_moved_pages_touched
test_idempotent
test_external_links_untouched
test_handles_already_leading_slash_form
echo "all tests passed"
