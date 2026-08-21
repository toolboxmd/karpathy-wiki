---
title: karpathy-wiki ideas
status: living-document
last_reviewed: 2026-08-21
---

# IDEAS

Product ideas, experiments, future options, and rejected ideas retained only to
avoid re-proposal. These are not committed work. Promote an idea to `TODO.md` or
`ISSUES.md` only when it becomes a concrete next action or a known problem.

## Future: `bin/wiki orient` CLI shortcut for the read-protocol Step A

```yaml
status: deferred
priority: p2
effort: low
labels: [read-protocol, follow-up]
revisit_when:
  "0.2.7 has been in the wild for a release cycle and we have evidence
  about whether the prose-only read protocol produces reliable behavior.
  If agents reliably orient via the prose ladder, ship the conservative
  flavor of `bin/wiki orient` to make orientation cheaper. If agents
  drift on the prose, the CLI shortcut alone won't fix it — first
  sharpen the loader's resist-table."
refs:
  - skills/karpathy-wiki-read/SKILL.md (Step A — orient)
  - skills/using-karpathy-wiki/SKILL.md (Iron Rule 4 + resist-table)
```

The 0.2.7 read protocol restores orientation as a prose procedure: the
agent reads `<wiki>/schema.md` and the relevant `<wiki>/<category>/_index.md`
itself. Two file reads per first-orient. Once-per-session amortization
makes this cheap, but it relies on the agent following the prose.

`bin/wiki orient` would automate the orient step. Two flavors:

- **Conservative**: `bin/wiki orient` (no args) prints schema +
  category indexes + recent log entries. Agent still reads candidate
  pages itself. Collapses two file reads into one CLI call. Lower
  drift surface than the aggressive version because the agent still
  reads the candidates.
- **Aggressive**: `bin/wiki orient "<query>"` does the substring/tag
  match server-side and prints the top candidate paths + summaries.
  Agent jumps straight to Step C. Higher drift risk: the agent might
  skip the index reading and over-trust the server-side match.

Ship conservative first. Promote to aggressive only if real-session
evidence shows the conservative version produces reliable orientation
without the agent skipping it.

---
## v2.4 deferrals (out of scope from v2.3)

```yaml
status: open
priority: p2
effort: medium
labels: [v2.4, follow-up]
refs:
  - docs/planning/2026-04-25-karpathy-wiki-v2.3-spec.md (out-of-scope section)
```

Items deferred from v2.3:

- **Automated retroactive global link migration** — v2.3 only rewrote inbound links to the 4 moved pages; ~50+ other relative links throughout the wiki stayed in their existing form. A bulk migration script that converts every `../foo.md` to `/category/foo.md` would polish the wiki but is non-urgent.
- **`wiki create-category <name>` CLI** — v2.3 contract is `mkdir`. If friction surfaces from heavy use, a small CLI wrapper that does `mkdir + name validation + initial _index.md skeleton` is straightforward.
- **Cosmetic reorg of historical migration scripts to `scripts/historical/`** — `wiki-migrate-v2-hardening.sh`, `wiki-migrate-v2.2.sh`, `wiki-migrate-v2.3.sh` accumulate. Moving them to `scripts/historical/` (or similar) keeps the active scripts dir clean.
- **`wiki doctor` real implementation** — still a stub. Now with the recursive `_index.md` tree, the smartest-model re-rate path is unblocked; orphan repair and tag-synonym consolidation also become cleaner.
- **Per-`_index.md` schema-proposal firing** — the SKILL.md ingester step 7.6 has prose for this but it's not exercised by an actual ingester run yet (would happen during an organic ingest after v2.3 ships).
- **Singular `type:` orphan recovery** — if anyone hand-writes a page with singular `type:` post-v2.3, the validator hard-rejects. A friendlier `wiki fix-type` CLI that runs `wiki-fix-frontmatter.py` on the offending page would smooth this.

Each of these is a candidate for a future ship; none block v2.3.
## `--max-turns` / `--max-budget-usd` on spawned ingester

```yaml
status: rejected
priority: p3
effort: low
labels: [defers-to-user-policy]
revisit_when:
  "N/A — user explicitly rejected in v2.1 planning. Budget and turn caps are
  user-account concerns, not skill concerns. Revisit ONLY if the skill gets used
  in constrained contexts (e.g., GitHub Actions CI) where a runaway ingester
  would block the pipeline."
refs:
  - docs/planning/2026-04-24-karpathy-wiki-v2.1-missed-capture-patch.md#deliberate-scope-cuts
```

Kept in this file with `status: rejected` specifically so future-us doesn't
re-propose the same thing without seeing the prior reasoning. The underlying
concern (runaway ingester) is handled by the stalled-capture recovery mechanism
shipped in v2.1.

---
## `--json-schema` structured ingester output

```yaml
status: deferred
priority: p3
effort: high
labels: [post-mvp, reliability]
revisit_when:
  "Ingester starts producing malformed output in the wild — e.g. missing quality
  blocks, wrong date format, or the existing Tier-1 lint (read back every page
  link) starts failing regularly. Currently no pain point."
refs:
  - ~/wiki/concepts/claude-code-headless-subagents.md (--json-schema
    documentation)
  - scripts/wiki-validate-page.py (the current pain-point surface if malformed
    output lands)
```

Cleaner success signal than parsing `.ingest.log`. Let the ingester emit a
structured summary object (pages created, pages updated, manifest entries
written, validator result) that the parent can parse to decide whether to retry
or surface an error.

---
