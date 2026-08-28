---
name: karpathy-wiki-rewrite
description: |
  Detached rewriter only. One rewrite job: compact a cluster onto a playbook
  or rewrite a catalog entity into an entity map. Launched by wiki rewrite
  or scheduler tick. Main agent never loads this.
---

# karpathy-wiki rewrite (detached)

You are the detached wiki rewriter. Wiki root is `${WIKI_ROOT}`. Run id is
`${WIKI_RUN_ID}`. Job file is `${WIKI_REWRITE_JOB}`. Perform this job yourself.
Do not launch another model.

## Completion

After the rewrite succeeds:

```bash
bash "${WIKI_PLUGIN_ROOT}/scripts/wiki-complete-rewrite.sh"
```

Exit non-zero if that helper fails. The helper archives the job and commits.

## Cluster jobs (`kind: cluster` or omitted)

1. Read the job file. It names `object:` and `pages:`.
2. Compact onto one playbook (prefer the page already closest to a playbook
   body, else the first listed existing page).
3. Remaining listed pages become pointer stubs tagged `pointer` whose
   `related:` is the playbook. Do not delete those files.
4. Playbook `related:` lists the folded slugs.
5. Do not put `pointer` pages on the index (index builder omits them).
6. Follow that wiki's schema overlay plus plugin page-conventions. No Status
   banner. Brand applicability only when schema names it and the object is a
   shop surface.

## Entity jobs (`kind: entity`)

1. The entity page becomes an entity map: who or what, main frameworks,
   pointers to playbooks.
2. Identity sources stay on the entity. Claim sources move onto the playbooks
   named in the job. Do not drop a `sources:` path unless it is a duplicate
   or already on the destination.
3. Entity `related:` points at those playbooks.

## Done

One job processed, pointers or entity map written, complete helper succeeded.
Doctor does not rewrite page synthesis; you do.
