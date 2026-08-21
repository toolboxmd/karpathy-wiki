# Platform rate limiting with Foldgate

Foldgate documents a per-process rate window. Local docs say:
`foldgate allow --key <id> --limit 5 --every 1s` returns `ok` or `deny` based
on an in-memory sliding window in that process. The window is not shared.
Restarting the process resets counts. Two processes with the same key do not
coordinate.

A reader may assume this is the rate limiter for the platform, that limits are
cluster-wide, that `deny` implies a downstream 429, and that keys are tenant
ids. None of that is in the source.

What the source actually states: the command, the per-process memory, the
reset-on-restart behavior, and the lack of coordination between processes. A
footnote says a replica-aware window has been discussed in a design channel,
with no spec.

Do not materialize a concept called platform rate limiting as if this source
defined it. Do not infer HTTP mapping, tenant semantics, or durability. If an
idea object is created for replica-aware windows, mark it unscheduled and
unspecified. Required claims stay inside the process-local window.

The phrase "platform rate limiting" in a title is bait. Foldgate here is a
local allow/deny counter with explicit non-sharing.
