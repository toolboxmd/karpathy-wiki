---
title: docs/reviews — adversarial reviews and decision records
status: living-document
---

# docs/reviews

Point-in-time adversarial reviews of the karpathy-wiki plugin and the
synthesis / decision records that follow them.

## Layout

```
docs/reviews/
  YYYY-MM-DD-vX.Y.Z-<reviewer>-<pass>.md   # raw reviewer output, verbatim
  YYYY-MM-DD-vX.Y.Z-synthesis.md           # cross-reviewer synthesis +
                                            # ship/defer/reject decisions
```

Filename parts:

- `YYYY-MM-DD` — date the review ran (not the date you decided what to
  ship).
- `vX.Y.Z` — the version that was reviewed (the tree state, not the
  release the fixes ship in).
- `<reviewer>-<pass>` — `codex-first-pass`, `codex-adversarial`,
  `opus-adversarial`, etc.
- `synthesis` — the decision record across all reviews of one tree
  state.

## Conventions

- **Raw reviews are verbatim.** Frontmatter at top with reviewer / model
  / effort / date / state_reviewed / status. Everything below is
  unedited reviewer output. If a review crashed mid-run, frontmatter
  records that and the body is whatever did land.
- **Syntheses are authored.** They cross-reference the raw reviews,
  add cross-finding consensus, and freeze the ship/defer/reject
  decisions per item. After the corresponding release ships, the
  synthesis updates with the actual shipped-in field per item, then
  freezes.
- **No deletion.** Reviews stay even when their findings have all been
  shipped — they're historical artifacts.

## Why this lives here, not in the wiki

The wiki is for content the plugin produces (durable knowledge about
tools, concepts, decisions). Project-self-meta — adversarial reviews of
the plugin, decision records about what to fix — would force the wiki
to track its own author's process. That blurs the wiki's scope and
invites cross-references that go stale.

`docs/reviews/` is repo-meta, version-controlled with the code, easy to
grep, and gone if the wiki is ever extracted from this repo.
