# Reproducible builds after the lockfile rewrite

RivetKit is a command-line tool that writes a `rivet.lock` file from a
workspace manifest. The 0.4 rewrite changed the default lock format from a JSON
blob to a line-oriented record file so diffs stay readable in review.

Install remains `cargo install rivetkit --locked`. The binary name is `rivet`.
The only required argument is a path to `rivet.toml`. Running `rivet stamp`
walks workspace members, hashes source trees with BLAKE3, and writes one record
per crate. `rivet stamp --check` exits non-zero when the lock is stale.
`rivet explain <crate>` prints the hashed paths that contributed to a record.

The tool refuses network access during stamp. Fetching is a separate command,
`rivet fetch`, and it is disabled unless `RIVET_ALLOW_FETCH=1` is set.
Maintainers added that split after a CI incident where a stale cache still
produced a lock.

Configuration lives in `[stamp]` inside `rivet.toml`. `ignore` is a list of
glob patterns. `seed` is an optional 32-byte hex string that salts hashes.
Leaving seed unset is the supported default. `rivet stamp` does not bump a
semver field. Versioning is the caller's job.

RivetKit is not a package registry and does not publish crates. It only records
what is already on disk. Teams that want a higher-level reproducible build
policy still need their own CI rules. RivetKit only supplies the lockfile
primitive.
