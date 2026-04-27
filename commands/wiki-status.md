---
allowed-tools: Bash(wiki status:*), Bash(bash bin/wiki status:*)
description: Show karpathy-wiki health report (categories, counts, drift, quality, last ingest)
---

## Wiki status

!`wiki status 2>&1 || bash bin/wiki status 2>&1`

## Your task

Read the output above and present it cleanly to the user. Note any anomalies (drift, pages below 3.5 quality, dirty git state, depth violations, soft-ceiling crossings). Don't run any other commands.
