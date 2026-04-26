#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"

test_extract_frontmatter() {
  out="$(printf -- '---\ntitle: foo\n---\nbody\n' | python3 "${REPO_ROOT}/scripts/wiki_yaml.py")"
  echo "${out}" | grep -q '"title": "foo"' || { echo "FAIL: title not parsed"; exit 1; }
}

test_quality_block_parsed_as_dict() {
  out="$(printf -- '---\ntitle: foo\nquality:\n  accuracy: 4\n  overall: 4.00\n  rated_by: ingester\n---\nbody\n' | python3 "${REPO_ROOT}/scripts/wiki_yaml.py")"
  echo "${out}" | python3 -c "import json, sys; d = json.load(sys.stdin); assert isinstance(d['quality'], dict); assert d['quality']['rated_by'] == 'ingester'; assert d['quality']['accuracy'] == 4"
}

test_url_in_sources_not_misparsed() {
  out="$(printf -- '---\ntitle: foo\nsources:\n  - https://example.com/foo\n---\nbody\n' | python3 "${REPO_ROOT}/scripts/wiki_yaml.py")"
  echo "${out}" | python3 -c "import json, sys; d = json.load(sys.stdin); assert d['sources'] == ['https://example.com/foo'], d"
}

test_split_frontmatter_round_trip() {
  python3 - <<'PYEOF'
import sys
sys.path.insert(0, "scripts")
from wiki_yaml import split_frontmatter
text = "---\ntitle: foo\ntype: concepts\n---\nbody line 1\nbody line 2\n"
opener, fm, after = split_frontmatter(text)
assert opener == "---\n", repr(opener)
assert fm == "title: foo\ntype: concepts", repr(fm)
assert after.startswith("---\n"), repr(after)
# Round-trip MUST be exact
reconstructed = opener + fm + "\n" + after
assert reconstructed == text, f"diff: orig={text!r} reconstructed={reconstructed!r}"
PYEOF
}

test_oracle_against_validator_parser() {
  python3 - <<'PYEOF'
import sys, importlib.util
sys.path.insert(0, "scripts")
from wiki_yaml import parse_yaml

# v2.3: wiki-validate-page.py no longer defines _parse_yaml locally; it
# imports parse_yaml from wiki_yaml. The oracle now verifies that the
# validator module exposes the same function object (or at minimum produces
# identical results via the canonical shared implementation).
spec = importlib.util.spec_from_file_location("validate_module", "scripts/wiki-validate-page.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
# The validator must expose parse_yaml (imported from wiki_yaml).
assert hasattr(mod, "parse_yaml"), "wiki-validate-page.py must expose parse_yaml via import"
validator_parse = mod.parse_yaml

inputs = [
    "title: foo\ntags: [a, b]\n",
    "quality:\n  accuracy: 4\n  overall: 4.00\n",
    "sources:\n  - https://example.com/foo\n",
    "tags:\n  - a\n  # comment\n  - b\n",
    "quality:\n  accuracy: 4\n    deeper: 1\n",
]
fails = []
for fm in inputs:
    try:
        canonical = parse_yaml(fm)
        canonical_err = None
    except Exception as e:
        canonical = None
        canonical_err = type(e).__name__

    try:
        via_validator = validator_parse(fm)
        validator_err = None
    except Exception as e:
        via_validator = None
        validator_err = type(e).__name__

    if canonical_err != validator_err or canonical != via_validator:
        fails.append({
            "input": fm,
            "canonical": (canonical, canonical_err),
            "via_validator": (via_validator, validator_err),
        })

if fails:
    import json
    print("ORACLE FAILED:")
    print(json.dumps(fails, indent=2, default=str))
    sys.exit(1)
print("oracle matches all inputs")
PYEOF
}

test_split_frontmatter_no_body() {
  python3 - <<'PYEOF'
import sys
sys.path.insert(0, "scripts")
from wiki_yaml import split_frontmatter
text = "---\ntitle: foo\n---\n"
opener, fm, after = split_frontmatter(text)
assert opener == "---\n", repr(opener)
assert fm == "title: foo", repr(fm)
assert after == "---\n", repr(after)
reconstructed = opener + fm + "\n" + after
assert reconstructed == text, f"diff: {text!r} vs {reconstructed!r}"
PYEOF
}

test_split_frontmatter_no_trailing_newline() {
  python3 - <<'PYEOF'
import sys
sys.path.insert(0, "scripts")
from wiki_yaml import split_frontmatter
text = "---\ntitle: foo\n---\nbody"
opener, fm, after = split_frontmatter(text)
assert opener == "---\n", repr(opener)
assert fm == "title: foo", repr(fm)
assert after == "---\nbody", repr(after)
reconstructed = opener + fm + "\n" + after
assert reconstructed == text, f"diff: {text!r} vs {reconstructed!r}"
PYEOF
}

test_split_frontmatter_crlf_returns_none() {
  python3 - <<'PYEOF'
import sys
sys.path.insert(0, "scripts")
from wiki_yaml import split_frontmatter
# CRLF line endings — split_frontmatter does not handle these (LF-only by design)
text = "---\r\ntitle: foo\r\n---\r\nbody\r\n"
opener, fm, after = split_frontmatter(text)
# Documented behavior: returns (None, None, None) for non-LF input
assert (opener, fm, after) == (None, None, None), f"got: {(opener, fm, after)}"
PYEOF
}

test_extract_frontmatter
test_quality_block_parsed_as_dict
test_url_in_sources_not_misparsed
test_split_frontmatter_round_trip
test_oracle_against_validator_parser
test_split_frontmatter_no_body
test_split_frontmatter_no_trailing_newline
test_split_frontmatter_crlf_returns_none
echo "all tests passed"
