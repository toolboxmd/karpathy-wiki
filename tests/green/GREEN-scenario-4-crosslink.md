# GREEN Scenario 4 — Missed-cross-link at ingest

**Goal:** Verify the ingester adds cross-links to obviously-related existing pages when introducing a new page on the same topic.

## Setup

- Clean `/tmp/karpathy-wiki-test-green4/`.
- Copy `/Users/lukaszmaj/dev/toolboxmd/karpathy-wiki/tests/fixtures/small-wiki/` to `/tmp/karpathy-wiki-test-green4/wiki/`.
- Add a NEW raw source at `/tmp/karpathy-wiki-test-green4/wiki/raw/2026-04-24-rate-limit-detection.md` with this body:
  ```markdown
  # Detecting rate-limit hits programmatically

  When your client gets a 429, you want to know which provider returned it
  (Jina, Cloudflare Browser Rendering, etc.) so you can apply the right
  backoff. Most providers expose X-RateLimit-* headers.

  Example: Jina Reader uses X-RateLimit-Remaining. Cloudflare Browser
  Rendering uses cf-ray plus 429 status without a dedicated header.
  ```
- The existing fixture already contains `concepts/jina-reader.md`, `concepts/cloudflare-browser-rendering.md`, `concepts/rate-limiting.md` and an `index.md` listing them.

The karpathy-wiki skill IS installed.

## Scenario prompt

Run (verbatim) as a Task-tool subagent prompt:

```
You are a headless ingester invoked by the karpathy-wiki skill. WIKI_ROOT is
/tmp/karpathy-wiki-test-green4/wiki/. A new raw file exists at raw/2026-04-24-rate-limit-detection.md.
Write a capture, claim it, and ingest it per the skill's ingest steps 1-12,
including step 7.5 (missed-cross-link check).

After ingest, stop and report:
1. What concept page did you create?
2. Which existing pages did you link to from the new page?
3. Which existing pages gained backlinks to the new page?
4. Full text of the new page.
```

## Expected compliance

- Field 1: a page at `concepts/rate-limit-detection.md` (or similar slug).
- Field 2: new page links to `concepts/jina-reader.md`, `concepts/cloudflare-browser-rendering.md`, AND `concepts/rate-limiting.md` (all three are obviously related and are in the pre-existing index).
- Field 3: at least ONE of the existing pages (jina-reader, cloudflare-browser-rendering, rate-limiting) gained a backlink to the new page, either via a "## See also" section or inline reference. This is the whole point of step 7.5.
- Field 4: new page has valid frontmatter (validator-green), with `quality:` block populated, and body references at least two of the three prior pages by wiki-path.

## Failure patterns to watch for

- Agent creates the new page but links to nothing in the existing wiki. Step 7.5 SHOULD have added links.
- Agent links from the NEW page to existing pages but doesn't update the existing pages with backlinks. Step 7.5's contract is bidirectional — if page B is "obviously related", page B should gain a link too (or a "See also" entry).
- Agent "over-propagates" — creates spurious links to every page in the index. Step 7.5 limits itself to pages `index.md` and the obvious-related-to test; over-linking is also a failure.

Document failures and patch SKILL.md step 7.5 to close rationalizations (same REFACTOR loop as Scenarios 1-3 in Task 23).
