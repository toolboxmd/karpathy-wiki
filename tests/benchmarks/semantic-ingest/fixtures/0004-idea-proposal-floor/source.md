# Trestle check command

Proposal: a non-writing check command on Trestle CLI.

Today `trestle gen` writes TypeScript bindings into `src/generated` and that
dirties the tree during CI typecheck experiments. A shadow compile would run
the same binder in memory, typecheck against a temporary overlay, and exit with
diagnostics. No files would be written unless `--commit` is passed.

This is a proposal, not a shipped feature. Trestle 2.1 has `trestle gen` and
`trestle clean` only. There is no `trestle check`.

Why not reuse `trestle gen --dry-run`? Dry-run currently prints the file list
and skips codegen. It does not run the typechecker, so it cannot catch binder
bugs that only appear in the produced types.

Sketch: add a ShadowFs that implements the same write trait as the real emitter
but buffers blobs. Pipe those blobs into the existing tsc wrapper with a root
overlay. Keep the cache key identical to `gen` so a later `--commit` is a
rename, not a rebuild.

Open question: should shadow compile be a flag on `gen` or a new subcommand.
The lean is subcommand so CI job names stay obvious.

Current Trestle behavior in this note is limited to `trestle gen` and
`trestle clean`. Nobody has agreed to schedule the shadow compile work, and no
release version or date is attached. Implementation detail in the sketch is
intent, not an API contract.
