---
title: Jina Reader
type: concept
tags: [api, rate-limit]
created: 2026-04-18
updated: 2026-04-20
sources: [raw/2026-04-18-jina-reader.md]
---

Jina Reader is a URL-to-markdown conversion API useful for agents that need clean page content.

## Rate Limits (Free Tier)
- 20 requests per minute
- Documented in error response header `X-RateLimit-Remaining`
- See [Rate Limiting](rate-limiting.md) for general patterns

## Workarounds
- Exponential backoff (preferred — see [Rate Limiting](rate-limiting.md))
- Paid tier at $0.0002/request removes the limit

## See also
- [Cloudflare Browser Rendering](cloudflare-browser-rendering.md) — alternative when Jina can't handle JS-heavy sites
