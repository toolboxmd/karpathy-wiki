# Semantic Ingest Labeling Guide

Label expected knowledge objects from the sanitized fixture source only.
Do not inspect current wiki output while writing gold labels.

## Object Identity

An expected object has an `id`, `kind`, `presence`, category constraints, match
aliases, and source-grounded claims.

Kinds in the MVP are:

- `entity`: named durable thing such as a tool, service, API, person, repo, or
  component.
- `concept`: reusable mechanism, pattern, principle, or comparison that remains
  true if named examples disappear.
- `query`: durable answer, audit, lookup, readiness check, or operational Q&A.
- `idea`: proposed future work or experiment, not committed as shipped.
- `project`: bounded workstream with scope, window, deliverables, and exit
  criteria.
- `hold`: source should remain raw, held, or low-evidence instead of becoming a
  canonical page.

## Presence

- `required`: must be realized as a page, update, section, or hold outcome.
- `optional`: allowed if source-grounded, but not required for pass.
- `forbidden`: must not be produced or absorbed as a primary page.

## Absorption And Under-Split

If all required claims for an entity appear inside a broad concept page, do not
count the entity as recalled. Mark it as absorbed. Absorption is an under-split
failure, not a partial success.

Example: a source about a named CLI called RivetKit should not pass if the
output is only `concepts/reproducible-builds.md` with a RivetKit section.

## Kind Confusion Versus Miss

A generated page can match the right object but the wrong kind. Count this as
kind confusion when the claims are present and grounded. Count it as a miss when
the object cannot be matched by name, alias, or source-grounded claims.

## Hold Cases

For low-evidence fixtures, the desired result can be zero canonical pages plus
a structured hold/raw outcome. A confident page that invents numbers, product
behavior, or mechanisms fails even if it cites the source.

## Faithfulness

Every `claims.must` item must be supported by the source. Every
`claims.must_not` item names an unsupported or contradicted claim. A useful
page with one `must_not` violation should fail faithfulness for that object.

## Fixture Examples

Entity floor: `RivetKit` is a named CLI with commands and limits. The expected
object is an entity. A reproducible-build concept is forbidden as the primary
realization.

Under-split fail: `Pylon Graph` and `Cragmap` are two tools plus a comparison
concept and an idea. A single `concepts/graph-databases.md` page absorbs four
objects and fails the split requirement.

Hold: `Marblehook` has only rumor evidence and one successful command. A
canonical answer with a numeric upload limit is forbidden.
