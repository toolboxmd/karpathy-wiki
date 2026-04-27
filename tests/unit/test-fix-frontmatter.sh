#!/bin/bash
# Test: wiki-fix-frontmatter.py recomputes type: from path; frontmatter-only.
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
FIX="${REPO_ROOT}/scripts/wiki-fix-frontmatter.py"

setup() {
  TMP="$(mktemp -d)"
  WIKI="${TMP}/wiki"
  mkdir -p "${WIKI}/concepts" "${WIKI}/ideas" "${WIKI}/raw"
  touch "${WIKI}/.wiki-config"
}
teardown() { rm -rf "${TMP}"; }

test_concept_singular_to_plural() {
  setup
  cat > "${WIKI}/concepts/foo.md" <<'EOF'
---
title: "Foo"
type: concept
tags: [test]
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
---

body
EOF
  python3 "${FIX}" --wiki-root "${WIKI}" "${WIKI}/concepts/foo.md"
  grep -q "^type: concepts$" "${WIKI}/concepts/foo.md" || { echo "FAIL: type not rewritten to concepts"; exit 1; }
  teardown
}

test_idea_path_value_correction() {
  setup
  cat > "${WIKI}/ideas/foo.md" <<'EOF'
---
title: "Foo"
type: concept
tags: [test]
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
---

body
EOF
  python3 "${FIX}" --wiki-root "${WIKI}" "${WIKI}/ideas/foo.md"
  grep -q "^type: ideas$" "${WIKI}/ideas/foo.md" || { echo "FAIL: ideas/ page not corrected"; exit 1; }
  teardown
}

test_idempotent() {
  setup
  cat > "${WIKI}/concepts/foo.md" <<'EOF'
---
title: "Foo"
type: concepts
tags: [test]
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
---

body
EOF
  before="$(shasum -a 256 "${WIKI}/concepts/foo.md")"
  python3 "${FIX}" --wiki-root "${WIKI}" "${WIKI}/concepts/foo.md"
  after="$(shasum -a 256 "${WIKI}/concepts/foo.md")"
  [[ "${before}" == "${after}" ]] || { echo "FAIL: not idempotent"; exit 1; }
  teardown
}

test_preserves_human_quality() {
  setup
  cat > "${WIKI}/concepts/foo.md" <<'EOF'
---
title: "Foo"
type: concept
tags: [test]
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
quality:
  accuracy: 5
  completeness: 5
  signal: 5
  interlinking: 5
  overall: 5.00
  rated_at: "2026-04-26T12:00:00Z"
  rated_by: human
---

body
EOF
  python3 "${FIX}" --wiki-root "${WIKI}" "${WIKI}/concepts/foo.md"
  grep -q "rated_by: human" "${WIKI}/concepts/foo.md" || { echo "FAIL: human rating clobbered"; exit 1; }
  teardown
}

test_frontmatter_only_body_with_type_marker() {
  setup
  cat > "${WIKI}/concepts/foo.md" <<'EOF'
---
title: "Foo"
type: concept
tags: [test]
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
---

Body with a teaching example:

```yaml
type: idea
status: open
```

end of body.
EOF
  python3 "${FIX}" --wiki-root "${WIKI}" "${WIKI}/concepts/foo.md"
  # frontmatter type rewritten
  grep -q "^type: concepts$" "${WIKI}/concepts/foo.md" || { echo "FAIL: frontmatter not rewritten"; exit 1; }
  # body type:idea preserved verbatim
  grep -q "^type: idea$" "${WIKI}/concepts/foo.md" || { echo "FAIL: body type literal lost"; exit 1; }
  teardown
}

test_frontmatter_only_body_with_dashes_marker() {
  setup
  cat > "${WIKI}/concepts/foo.md" <<'EOF'
---
title: "Foo"
type: concept
tags: [test]
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
---

Some body text.

---

A horizontal rule above; another type marker would be valid prose:
type: example

end.
EOF
  python3 "${FIX}" --wiki-root "${WIKI}" "${WIKI}/concepts/foo.md"
  grep -q "^type: concepts$" "${WIKI}/concepts/foo.md" || { echo "FAIL: frontmatter not rewritten"; exit 1; }
  grep -q "^type: example$" "${WIKI}/concepts/foo.md" || { echo "FAIL: body type literal lost (--- not respected as horizontal rule)"; exit 1; }
  teardown
}

test_full_wiki_batch() {
  setup
  for i in 1 2 3; do
    cat > "${WIKI}/concepts/c${i}.md" <<EOF
---
title: "C${i}"
type: concept
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
---
body
EOF
  done
  python3 "${FIX}" --wiki-root "${WIKI}" --all
  for i in 1 2 3; do
    grep -q "^type: concepts$" "${WIKI}/concepts/c${i}.md" || { echo "FAIL: c${i} not rewritten"; exit 1; }
  done
  teardown
}

test_no_extra_whitespace_added() {
  # Per corrigendum C-B: reconstruction must not add extra newlines.
  setup
  cat > "${WIKI}/concepts/foo.md" <<'EOF'
---
title: "Foo"
type: concept
tags: []
sources: []
created: "2026-04-26T12:00:00Z"
updated: "2026-04-26T12:00:00Z"
---

body line 1
body line 2
EOF
  size_before="$(wc -c < "${WIKI}/concepts/foo.md")"
  python3 "${FIX}" --wiki-root "${WIKI}" "${WIKI}/concepts/foo.md"
  size_after="$(wc -c < "${WIKI}/concepts/foo.md")"
  # delta = len("concepts") - len("concept") = 1
  delta=$(( size_after - size_before ))
  [[ "${delta}" -eq 1 ]] || { echo "FAIL: size delta ${delta}, expected 1"; exit 1; }
  # No triple newline introduced
  if grep -P '\n\n\n' "${WIKI}/concepts/foo.md" 2>/dev/null; then
    echo "FAIL: triple newline introduced"
    exit 1
  fi
  teardown
}

test_concept_singular_to_plural
test_idea_path_value_correction
test_idempotent
test_preserves_human_quality
test_frontmatter_only_body_with_type_marker
test_frontmatter_only_body_with_dashes_marker
test_full_wiki_batch
test_no_extra_whitespace_added
echo "all tests passed"
