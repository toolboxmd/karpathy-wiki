---
title: Cloudflare Browser Rendering
type: concept
tags: [api, browser]
created: 2026-04-19
updated: 2026-04-20
sources: [raw/2026-04-19-cloudflare-br.md]
---

Cloudflare Browser Rendering API runs a headless Chrome in Cloudflare Workers and returns rendered HTML/markdown. Good for JS-heavy sites that Jina can't parse.

## Rate Limits
- Free tier: 10 req/min, 5 concurrent
- See [Rate Limiting](rate-limiting.md) for backoff patterns

## Usage
- Endpoint: `/browser-rendering/markdown`
- Auth via Cloudflare account ID + API token (see `.env`)

## See also
- [Jina Reader](jina-reader.md) — faster alternative when JS rendering isn't needed
