# Platform rate limiting with Foldgate

Foldgate documents a per-process rate window. Local docs say:
`foldgate allow --key <id> --limit 5 --every 1s` returns `ok` or `deny` based
on an in-memory sliding window in that process. The window is not shared.
Restarting the process resets counts. Two processes with the same key do not
coordinate.

Related platform docs are easy to confuse with this command, but this note
does not say the limiter is cluster-wide, that `deny` implies a downstream
429, or that keys are tenant ids.

The concrete behavior here is the command, the per-process memory, the
reset-on-restart behavior, and the lack of coordination between processes. A
footnote says a replica-aware window has been discussed in a design channel,
with no spec.

A replica-aware window has only been discussed, with no spec and no schedule.
Foldgate here is a local allow/deny counter with explicit non-sharing.
