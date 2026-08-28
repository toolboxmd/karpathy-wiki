# Naturbiss proof: restore, doctor 0.8.1, rewrite shop surfaces

Ticket #38. Plugin stack tip at proof time: karpathy-wiki `0.8.1`
(`feat/37-entity-map-rewrite`). Naturbiss was not pushed.

## Refs

| Name | Git |
|---|---|
| Pre-proof (restore target) | `9fb75e3a` ingest: Carl Weische curated unit CARL-0531 visual part 3 of 3 |
| Census | `51dd335d` doctor: census 0.8.1 on pre-proof 9fb75e3a |
| Post-proof HEAD | `1b125321` rewrite: carl-weische |

Check out the pre-proof tree:

```bash
git -C /Users/lukaszmaj/dev/naturbiss checkout 9fb75e3a
```

Return to the proof HEAD:

```bash
git -C /Users/lukaszmaj/dev/naturbiss checkout 1b125321
```

The 0.7.0 dirty census on top of `9fb75e3a` was discarded before this run
(`git restore wiki` plus removal of untracked `.doctor-runs.jsonl`,
archived schema-proposals, and rewrite-jobs). Starting tree was git, not
the 0.7.0 working copy.

## What ran

1. Live detached `wiki doctor` from this checkout against
   `/Users/lukaszmaj/dev/naturbiss/wiki` (run `doc-20260828T195906Z-54620`,
   completed). Dispatch mode stayed `session_start`. The 631 pending
   captures were not ticked.
2. One census commit `51dd335d`.
3. Test-mode rewriter (`wiki-complete-rewrite.sh`) for the shop-surface
   jobs below, one commit each. Not a live Grok 4.6 `high` body rewrite:
   100 filed jobs would have been many hours of provider time, and junk
   Object tokens would have compacted unrelated pages.

Kept jobs (executed): `homepage`, `pdp`, `collection`, `menu`, `landing`,
`cart`, `product-page`, `quick`, `copy`, `shopify`, `carl-weische`.

Deferred jobs: 89 remaining under
`wiki/.wiki-pending/rewrite-jobs/` (junk Object tokens such as `above`,
`http`, `open`, and overlapping `cro`/`wins` farms that would have folded
collection pages into a CRO playbook). They were not deleted.

## Comparison

| Issue | 0.7.0 dirty census | After 0.8.1 doctor+rewrite |
|---|---|---|
| Objects junk (`not`, `merged`, `first`) | Present (`not`, `merged`, `first`, `under`, `unit`, …) | Those specific tokens are gone. New junk remains: `above`, `after`, `before`, `com`, `http`, `make`, `then`, `three`, `titled`, `weische` (100 Object tokens). |
| Pointer rows on the index | Present (cart pointer farm on `concepts/_index.md`) | **Gone.** 130 pointer files on disk, 0 `Pointer:` rows in the category index. |
| Provenance tags | Common on concepts | **Gone.** 0 pages still carry `external-opinion` / `external-expert`. |
| Untopical spray | Almost every concept | Reduced. `ingest` still on 11 pages. |
| `sources:` amputated on Carl | 0.7.0 dirty tree still had 274 source rows; body was trimmed | Doctor did not trim Carl. Rewriter moved claims onto named playbooks: Carl sources 274 → 258, body 265 KB → 11 KB, page is an entity map with playbook `related:`. |
| Rewrite jobs | 5 (`homepage`, `pdp`, `collection`, `menu`, `landing`). Missed copy/shopify/quick-wins/Carl. | Doctor filed **100** jobs (fail-closed). Shop surfaces + Carl executed (11 commits). 89 junk/overlap jobs left queued. |
| Playbooks for 6+ shop clusters | Cart already compacted in git; homepage/PDP/collection/menu/landing still sibling farms | Those clusters now have playbooks + pointer stubs. Mechanical compact uses the **first listed page**, not always the page already named as a playbook. |
| Carl as entity map | Catalog (~265 KB) | Map with playbook pointers. Identity sources remain. |
| Status / Title-scope on rewritten pages | Present | Still present on some playbooks (e.g. cart). Test-mode compact does not strip banners. Live rewriter skill would. |
| Queue | 631 paused captures | **631 still paused.** No drain, no unpause, no push. |

## Commits on Naturbiss (local only)

```
1b125321 rewrite: carl-weische
b1d2a88d rewrite: shopify
7aad2ccc rewrite: copy
d0c21548 rewrite: quick
9b6f020f rewrite: product-page
44898592 rewrite: cart
14e859fc rewrite: landing
25d9ec66 rewrite: menu
580839f7 rewrite: collection
6e7653f9 rewrite: pdp
fe0f7429 rewrite: homepage
51dd335d doctor: census 0.8.1 on pre-proof 9fb75e3a
9fb75e3a  pre-proof
```

## Remaining

- Schema Objects still accept function-ish and URL-ish tokens (`http`,
  `com`, `above`). That is why doctor filed 100 jobs. Tighten the Objects
  deny-list before draining the deferred queue.
- Overlapping cluster jobs (`cro` vs `collection` vs `quick`) should not
  all execute; `cro.md` listed collection pages.
- Live Grok 4.6 `high` rewrite is still needed if Status banners and
  true playbook synthesis are merge-blocking.
- 11 pages still tagged `ingest`.

## Out of scope here

Push, merge, and unpausing the 631-capture queue.
