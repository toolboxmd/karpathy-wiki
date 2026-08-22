# Pressure scenario: cold read in an unconfigured workspace

**Context.** A fresh agent receives a normal question in a directory with no
configured project, main, or both wiki route. The read skill loads before any
capture exists.

## Before this change

Step A starts by requiring `schema.md` and an index from a resolved wiki, but it
does not define what to do when no wiki can be resolved. Step F requires a
capture only after the candidate-count path has been reached.

A procedural agent can therefore fail like this:

1. It cannot find a wiki root, so it cannot read the Step A files.
2. It answers from non-wiki evidence.
3. It ends the turn without entering Step F.
4. No capture is attempted, so the existing capture-owned orphan and
   `project / main / both` prompt never run.

Real sessions often reach the capture fallback anyway, as shown by the user's
2026-08-22 screenshot, but that success depends on the agent inferring a branch
the read skill does not state.

## After this change

Step A.0 treats unconfigured routing as an explicit cold path. It skips
impossible schema/index reads and continues directly at Step F. Step F still
owns the answer and required capture; the capture skill remains the sole owner
of orphan preservation and the one routing question.

## Falsifying the change

In an unconfigured directory, ask a question that produces no independent
capture trigger. The agent must reach Step F and invoke the standard capture
flow. If it silently answers and stops, initializes a wiki without a choice, or
asks a second setup question before capture, the contract has regressed.
