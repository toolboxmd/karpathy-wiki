# RED scenario — ingester picks wrong cross-links from titles alone

**Date:** 2026-05-06
**Skill change this justifies:** v2.4 Leg 4 — deep orientation (read 0-7 candidate pages in full before deciding what to write or which existing pages to cross-link).

## The scenario

A capture arrives describing "rate limits in the X API." The wiki has these existing concept pages:

- `concepts/rate-limits-and-burst-tokens.md` — about HTTP rate-limit headers, retry-after, exponential backoff. Generic, applies to any API.
- `concepts/x-api-quotas-vs-throughput.md` — about the X API specifically: quota enforcement at the GraphQL field level, not the HTTP level. Explicitly says "rate limit" is a misleading term for this API.

Pre-v2.4 ingester reads only the index and matches the new capture's title against page titles. "Rate limits in X API" matches `rate-limits-and-burst-tokens.md` strongly (3 of 5 keywords). The ingester writes a new page that augments `rate-limits-and-burst-tokens.md` and adds a `see also` link to it.

But that page is the WRONG canonical reference. The right one is `x-api-quotas-vs-throughput.md`, which explicitly handles the X-API-specific case the capture is about. The ingester missed it because the title used "quotas" instead of "rate-limits", which the title-match heuristic ranked lower.

## Why prose alone doesn't fix this

The pre-v2.4 ingester orientation reads `schema.md`, `index.md`, and the last 10 lines of `log.md`. None of these include the BODY of the candidate pages. Reading the index reveals what page titles exist; it does NOT reveal what those pages actually say. Title-only matching is the failure mode.

The fix is structural:
- Step 4 (deep orientation): from the capture, extract candidate signals (title, tags, frontmatter, body keywords for chat-only/chat-attached, filename + first 200 lines for raw-direct).
- Step 5: score candidates against the index by substring + tag match. Top 7 by score (descending), title-length ascending as tie-break (shorter titles rank higher for the same score; they are more general).
- Step 6: read the picked candidates IN FULL before deciding.
- Cold-start: ≤7 pages → role-prompt is primary lens, not the index. Index has insufficient gravity.

## Pass criterion

After Leg 4 ships:
- Ingester reads candidate pages in full during orientation; has the actual page bodies in context when deciding what to write or which to cross-link.
- Issue reporting catches the case where the ingester observes a contradiction or stale claim during this read; the issue is appended to `.ingest-issues.jsonl` for `wiki doctor` to act on later.
