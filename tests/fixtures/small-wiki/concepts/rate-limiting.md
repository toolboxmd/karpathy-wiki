---
title: Rate Limiting
type: concept
tags: [pattern, api]
created: 2026-04-20
updated: 2026-04-20
sources: [raw/2026-04-20-rate-limits.md]
---

Patterns for handling API rate limits gracefully.

## Exponential Backoff
Simplest and most compatible. Retry after `2^attempt` seconds, cap at 60s.

## Token Bucket
Use when you need sustained throughput. Refills at a known rate.

## Request Queue
Use when rate limit is low and you need order preservation.

## Applied in
- [Jina Reader](jina-reader.md)
- [Cloudflare Browser Rendering](cloudflare-browser-rendering.md)
