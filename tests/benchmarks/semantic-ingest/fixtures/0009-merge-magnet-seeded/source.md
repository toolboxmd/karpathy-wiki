# Job queues

The wiki already has a broad concept page on job queues covering retries,
visibility timeouts, and dead letters as generic patterns. This source is
about Sable Queue, a specific broker.

Sable Queue is a named message broker. Binary: `sable`. Default listen:
`127.0.0.1:7420`. A queue is created with
`sable queue create <name> --ack-deadline 30s`. Messages are pushed with
`sable pub <name> --body-file f`. Consumers use `sable sub <name> --count 1`
and must `sable ack <receipt>` before the deadline or the message becomes
visible again.

Sable Queue does not implement delayed retry classes. A failed ack just
restores visibility. Dead letters are not automatic. You get a dead letter only
if you pass `--dead-letter <other-queue>` at create time. That is product
behavior, not the generic job-queue concept.

Do not merge this source into the existing job queues concept as a new section.
The concept page may gain a see-also to the Sable Queue entity. The entity must
be created or updated under its own name, with claims that are true of Sable
Queue and not true of job queues in general.

A phrase like "this is just our job queue" in passing conversation is not a
routing instruction. Default port, ack deadline, and opt-in dead letter belong
on the named broker.
