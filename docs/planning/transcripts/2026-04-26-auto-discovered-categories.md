# Pressure scenario: auto-discovered categories rule

**Context.** Fresh agent session. Fixture wiki at `~/wiki-fixture/` with only `concepts/` directory (no `projects/`). User asks: "Tell me about my project's recent decisions."

## Without v2.3 SKILL.md update

Agent's behavior trace:

1. Reads schema.md → sees only `concepts/`, `entities/`, `queries/`, `ideas/` listed under `## Categories`. No mention that mkdir adds a category.
2. Reads index.md → sees same.
3. Capture trigger fires for "decision made with rationale."
4. Agent picks `concepts/foo.md` as target page. The cheap model has no notion that `projects/` could be a valid category — the validator's hardcoded `VALID_TYPES = {"concept", "entity", "query"}` would reject anything else, so the model is conservative.
5. Capture written. Ingester runs. Page lands in `concepts/`.

**Result:** project-specific decisions land in the concepts mega-bucket, indistinguishable from general principles. The user later searches for "what did we decide about X" and gets a noisy hit-list mixing principles and project-specific decisions.

## With v2.3 SKILL.md update

Agent reads the new "Auto-discovered categories (v2.3+)" section. Behavior trace:

1. Reads schema.md → still sees only the 4 existing categories, but the prose explains the contract: any top-level `mkdir` creates a category, except names in the reserved set.
2. Capture trigger fires for "decision made with rationale."
3. Agent considers at ingester step 5: "this is a project decision. Should it go in `concepts/` or in a new `projects/`?" The Rule 1 prompt fires: "would `projects/` reach 3 pages soon?" — yes (we have multiple project decisions queued in the conversation).
4. Agent: `mkdir ~/wiki-fixture/projects/`. Files capture in `projects/foo.md` with `type: projects` (path-derived plural).
5. Validator passes (Phase A WARNING-only on type-membership; post-Phase D would still pass since `projects/` is now in discovery's category list).
6. Next ingest's discovery picks up `projects/`. Wiki regenerates schema.md mirror, MOC, sub-indexes.

**Result:** project-specific knowledge lives in `projects/`, separated from general principles. The user's later search distinguishes the two cleanly.

## Falsifying the change

If a future regression breaks the auto-discovery prose (e.g., someone adds a hardcoded category list back), the agent on this fixture will revert to the "without" behavior and file the page in `concepts/`. CI cannot directly catch this (there's no automated agent invocation), but the existence of this transcript fixture means a maintainer can re-run the scenario manually after any SKILL.md change to verify the rule still holds.
