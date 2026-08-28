# RED: rewrite jobs stay as sibling farms

## Observed pressure

Doctor files a cluster rewrite job for two cart siblings. Without a
detached rewriter skill, the foreground session either ignores the job
or compacting happens inside doctor. Index still lists both pages.

Evidence: spec #31 / ticket #36; Naturbiss cart/PDP sibling farms.

## Failure mode

`wiki rewrite` is missing or is a stub. Scheduler tick never starts
`job=rewrite`. Completing a job does not leave pointer files or a
single playbook on the index.

## Required behavior

A detached rewrite worker drains one cluster job in the shared ingest
pool. Two siblings become one playbook; pointer files remain and are
omitted from the index; the job is one git commit. Doctor still does
not rewrite page synthesis.
