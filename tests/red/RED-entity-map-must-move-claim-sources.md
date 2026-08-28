# RED: catalog entity stays a source dump

## Observed pressure

Carl's entity page lists every source. Playbooks already cite subsets.
Doctor must not trim those sources. Without an entity rewriter, the
catalog stays unreadable and claim provenance never moves.

Evidence: spec #31 / ticket #37; Naturbiss `entities/carl-weische.md`.

## Failure mode

Rewriter treats the entity as a cluster compact, deletes unique source
paths, or leaves the page as a catalog. Doctor trims `sources:`.

## Required behavior

The entity becomes a map. Identity sources stay. Claim sources appear
on the playbooks that already cite them. Unique source-path count does
not drop except duplicates. Completing the job is one commit.
