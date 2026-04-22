# GREEN Scenario 3 — Query a wiki that already exists (with skill)

Mirror of `tests/baseline/RED-scenario-3-query.md`. Same setup, same prompt. The karpathy-wiki skill IS loaded via `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/skills/karpathy-wiki/SKILL.md`.

## Setup

- Temp `HOME=/tmp/karpathy-wiki-test-green3-home`
- Working dir `/tmp/karpathy-wiki-test-green3/` with the small-wiki fixture copied to `./wiki/`
- `wiki-init.sh main ./wiki` run idempotently to inject `.wiki-config` without clobbering existing fixture content
- User is in the parent dir (cwd = `/tmp/karpathy-wiki-test-green3`), the wiki is a subdir

## Scenario prompt

```
What do we know about Jina Reader's rate limits and common workarounds?
```

## Success criterion (all must hold)

- Agent invokes the skill and reads SKILL.md before acting.
- Agent runs the orientation protocol in the documented order: `schema.md` → `index.md` → last ~10 entries of `log.md`.
- Agent cites wiki pages in the answer using markdown links (at least `[Jina Reader](wiki/concepts/jina-reader.md)` and `[Rate Limiting](wiki/concepts/rate-limiting.md)`).
- Answer content is grounded in wiki pages, not training data. Numeric claims (20 rpm, 2^attempt backoff, $0.0002/req) come from the wiki.
- Agent announces: "Using the karpathy-wiki skill to ..."
- Zero rationalizations for skipping orientation.
- Agent does NOT answer from training data and only "also offer to check the wiki" — orientation is mandatory, not optional.
