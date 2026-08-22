# Loomferry publishing

The Loomferry cutover is a time-boxed effort for the Northridge docs team, not
a standing program. Window: 14 working days starting the first Monday after
the 2.3 tag. Goal: stop publishing the nightly docs bundle as a tarball on the
fileserver and start publishing through Loomferry's snapshot channel.

In scope: inventory the current scp job, write a Loomferry recipe for the docs
package, dual-publish for five days, flip the canonical URL, then delete the
scp job. Out of scope: rewriting the docs theme, migrating other teams, and
enabling Loomferry's experimental delta codec.

Exit criteria: the canonical URL returns 200 for three consecutive snapshots,
the fileserver path returns 404, and the runbook has one rollback command.
Rollback is restoring the scp job from the tagged recipe in the ops repo. That
is the whole project.

Loomferry itself is an existing tool, but this note only gives the cutover
window, scope, exit criteria, and rollback.

Staffing is two people. If the 2.3 tag slips, the window slides by the same
number of days. There is no phase 2. Dual publish is a five-day bridge inside
the window, not a permanent architecture.
