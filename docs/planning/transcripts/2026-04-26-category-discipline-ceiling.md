# Pressure scenario: 9th-category soft ceiling (Rule 3)

**Context.** Fresh agent session. Fixture wiki with EIGHT categories already present:

```
~/wiki-fixture/
├── concepts/
├── entities/
├── queries/
├── ideas/
├── projects/
├── journal/
├── research/
└── prototypes/
```

Capture trigger fires for content that the cheap model wants to file in a NEW 9th category called `experiments/`.

## Without v2.3 SKILL.md update

Behavior trace:

1. Cheap model decides at step 5: "this content fits a new category called `experiments`."
2. `mkdir ~/wiki-fixture/experiments/`.
3. Files capture in `experiments/foo.md`.
4. Discovery on next ingest picks up the 9th category. Status report doesn't flag the soft-ceiling crossing (no Rule 3 yet).

**Result:** category count creeps to 9, then 10, then 11 over subsequent sessions without any speed bump. Orientation cost grows: every agent reading schema.md sees an ever-longer category list, and the cheap model's "where does this go?" decision space expands proportionally.

## With v2.3 SKILL.md update

Rule 3 fires at ingester step 5:

1. Cheap model checks `wiki-discover.py` output: current category count is 8.
2. Wants to create a 9th category. Rule 3 says: file a schema-proposal capture instead of mkdir-ing.
3. Cheap model files `~/wiki-fixture/.wiki-pending/schema-proposals/2026-04-26T12-30-15Z-9th-category-experiments.md` with proposal rationale.
4. The current capture is filed in best-fit existing category (likely `prototypes/` or `research/`).
5. User reviews the schema-proposal next session. If approved, user `mkdir`-s themselves to override the soft-ceiling.

**Result:** agent doesn't autonomously inflate the category count. User retains gate-keeper role at growth boundaries. The soft-ceiling speed bump is decoration-vs-mechanism honest: there IS a mechanism (the schema-proposal capture), and the user-status line gives visibility.

## Falsifying the change

If Rule 3's prompt is removed from the cheap model's step-5 instructions, the agent would `mkdir` the 9th category directly (the "without" behavior). The pressure scenario can be re-run by giving an agent only the SKILL.md without the Category discipline section and seeing the regression.

`wiki-status.sh` also surfaces "category count vs soft-ceiling 8" — if the agent bypassed the rule, the user would see the count climb and could inspect the recent ingests.
