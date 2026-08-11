# Clean-session and scheduler acceptance — 2026-08-11

## Scope

This acceptance used a disposable project wiki and two independent Claude Code
sessions started with no session persistence. The explicit plugin working tree
was loaded in each session. No existing wiki was discovered, inspected,
migrated, or mutated.

## SessionStart mode

- Claude Sonnet with low effort emitted the required first line:
  `Using the karpathy-wiki skill to answer from wiki.`
- The answer cited the disposable wiki page rather than relying on the prompt.
- The SessionStart hook launched one bounded test-provider tick.
- The run produced one `started`, one `completed`, one archive, and no remaining
  slot or processing file.

## Scheduled mode

- A second clean session emitted the same loader announce line.
- A pending capture and an old inbox source remained unchanged.
- No scan, claim, provider run, or new run-history event occurred during
  SessionStart.

## Real macOS LaunchAgent

- A LaunchAgent with a path-derived label was installed under a temporary
  `HOME` and reported `state: installed`, `loaded: true`.
- `RunAtLoad` invoked one short scheduled tick against the disposable wiki.
- The tick produced one `started`, one `completed`, one archive, and released
  its slot.
- Uninstall reported `state: not installed`, `loaded: false`, and changed the
  local mode back to `session_start`.
- Independent post-run checks confirmed that neither the label nor plist nor a
  matching process remained.

Raw hook events, provider runtime events, stderr, and local paths are retained
only under the Git-ignored `raw/2026-08-11T15-34-39Z-clean-sessions/`
directory.
