# Ambervault retry policy

How do I look up the retry class for a failed Ambervault export job?

Operators ask this during incidents. The answer is not on the dashboard home
page. From the operator CLI, run:

`ambervault jobs inspect <job-id> --fields retry_class,next_attempt,last_error`

`retry_class` is one of `immediate`, `backoff`, or `dead`. `immediate` means
the dispatcher retries on the next tick. `backoff` means `next_attempt` is the
earliest legal time. `dead` means a human must requeue.

If the job id is unknown, look up by export target:

`ambervault jobs list --kind export --target <name> --status failed --limit 20`

The list is newest first. Do not grep application logs for `retry_class`; that
string is not emitted on the happy path.

A common false friend is the HTTP status on the export callback. A 429 from a
downstream sink does not map one-to-one onto `retry_class`. The mapping lives
in the dispatcher, not in the sink.

This note is a lookup procedure. It is not a design of Ambervault, not a
taxonomy of retry policies, and not a proposal to change those classes. If a
job is `dead`, the lookup answer is "requeue by a human," not a new feature
idea.
