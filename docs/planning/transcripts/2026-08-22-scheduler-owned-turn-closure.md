# Pressure scenario: scheduler-owned turn closure

**Context.** The wiki is configured in `scheduled` mode. The main agent has
successfully written a required capture with `bin/wiki capture`, while another
capture is already running or the scheduler is observing a retry cooldown.

## Before this change

The capture skill tells the main agent to inspect `.wiki-pending/` before
ending the turn. Any queued `.md` file, or a sufficiently old
`.md.processing` file, means the turn is not done and the main agent must
handle the queue first.

That rule fails in the scheduled architecture:

1. `bin/wiki capture` returns success and the durable handoff is complete.
2. The scheduler intentionally leaves the new capture queued until a global or
   per-wiki lease is available, or until a retry cooldown expires.
3. The main agent sees the expected queue entry and refuses to end the session.
4. Rechecking cannot make progress because queue ownership belongs to the
   detached scheduler and worker, not to the foreground session.

Mechanically enforcing the same check in a Stop hook would turn expected
asynchronous state into an unbounded session-ending block. It also would not
detect a missed capture: a trigger the agent never wrote leaves no queue entry
for the hook to inspect.

## After this change

The foreground contract ends when every required `bin/wiki capture` command
returns success. The durable queue is then owned by the scheduler, including
claiming, leases, retries, cooldowns, and failed-work handling. The main agent
does not wait for `.wiki-pending/` to drain and no Stop hook is registered.

A capture command failure still belongs to the foreground turn and must be
handled or surfaced before the agent stops. This preserves the only boundary
the main agent can enforce without taking scheduler ownership.

## Falsifying the change

Configure a wiki in `scheduled` mode, keep one worker lease occupied, and make
the main agent write another valid capture. The agent must be allowed to end
the turn once the capture command succeeds, while the queued file remains for
the scheduler. If the foreground agent waits for that file to disappear or
tries to ingest it directly, the old ownership error has returned.
