# Harborline fencing notes

Lease fencing is a way to keep a single writer on a shared resource when
heartbeats can be delayed. A writer holds a lease token with a monotonically
increasing fence. Every mutation must carry the current fence. The storage
layer rejects any mutation whose fence is older than the last accepted fence,
even if the client's lease timer has not expired.

This is not the same as a mutex. A mutex disappears when the process dies. A
fence stays in the log. Late packets from a previous writer cannot apply after
a new writer has started.

Timeouts are a separate concern. Lease expiry only means a new writer may try
to acquire. Acquisition still requires reading the latest fence and writing
fence+1 in one compare-and-set. If that write loses, the challenger backs off.

Poisoning is optional. Some designs mark a fenced-out writer as banned until it
observes the new fence. Others just drop stale mutations. Either policy is
still lease fencing so long as storage is the source of truth for the highest
fence.

Harborline and Foldgate both implement variants, but this note does not list
their product commands, configuration, release versions, or ownership. The
reusable mechanism described here is the compare-and-set rule, the mutex
contrast, and the fact that expiry alone is not safety.
