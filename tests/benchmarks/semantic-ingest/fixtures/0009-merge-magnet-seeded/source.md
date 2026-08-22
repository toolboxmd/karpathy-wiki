# Job queues

General job-queue notes cover retries, visibility timeouts, and dead letters
as broad patterns. These notes are about Sable Queue, a specific broker.

Sable Queue is a named message broker. Binary: `sable`. Default listen:
`127.0.0.1:7420`. A queue is created with
`sable queue create <name> --ack-deadline 30s`. Messages are pushed with
`sable pub <name> --body-file f`. Consumers use `sable sub <name> --count 1`
and must `sable ack <receipt>` before the deadline or the message becomes
visible again.

Sable Queue does not implement delayed retry classes. A failed ack just
restores visibility. Dead letters are not automatic. You get a dead letter only
if you pass `--dead-letter <other-queue>` at create time. That behavior is
specific to Sable Queue.

A phrase like "this is just our job queue" in passing conversation is too broad
for these details. Default port, ack deadline, and opt-in dead letter behavior
are Sable Queue facts, while generic job-queue systems vary.
