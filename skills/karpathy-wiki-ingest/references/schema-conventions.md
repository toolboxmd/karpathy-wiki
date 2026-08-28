# Wiki schema.md conventions

Single source of truth for headings in `<wiki>/schema.md`. Init seeds a new wiki
with this layout. Ingest and doctor edit the live file; they do not invent
new top-level headings. Plugin page-conventions stay the page-body defaults.

A wiki may add extra frontmatter keys and body sections under Page contract.
It may lengthen or shorten the Doctor cadence list. The last cadence number
repeats.

## Role
`main` or `project`. Copied from `.wiki-config` at init.

## Categories
One bullet per discovered top-level category directory. Init seeds the four
defaults. Later patches refresh from the directory tree.

## Objects
Learned object tokens, one per line after the heading. Init seeds:

```
(none yet)
```

A token belongs here when the walked index has 6 or more hits on it (title,
one-liner, or tag list) and it is a knowledge-object name. Drop function
words, pointer-stub language (`merged`, `pointer`), brand and source-owner
names, and tags that sit on more than half of that index unless the token
also has 6+ title or one-liner hits. Tokens that fall back under 6 hits are
pruned; the list is the current qualifying set, not a historical union.

## Tag Taxonomy (bounded)
Tags the wiki has accepted. One spelling per idea. Init starts empty of
specific tags.

## Numeric Thresholds
Required bullets (wording may grow, these keys stay):

- Split a page when it holds two distinct knowledge objects, or it is still too long after dropping repetition. Two sources about the same object augment one page.
- Archive a raw source: referenced by 5+ wiki pages
- Restructure top-level category: 500+ pages within it
- Doctor cadence: 10, 20, 50, 100

Doctor cadence is completed ingestions since the last successful doctor.
Intervals apply in order; the last number repeats. Skip, sha-match,
thin-reject, and failed ingestions do not count.

## Page contract
Plugin defaults live in the ingest page-conventions. Extra frontmatter keys
already present on pages are listed as bullets. If it names none, write only
the plugin defaults.
