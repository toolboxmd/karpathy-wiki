# Marblehook upload limits

Hallway note, 12 Mar 2026. Someone on the infra rotation said Marblehook
"probably" drops uploads over a size limit. They did not remember the limit,
the error code, or whether it was the client or the server. I have not found a
flag, a config key, or a log line that says so.

I ran `marblehook put ./sample.bin` once with a 12MB file and it succeeded.
That does not prove unbounded size. It also does not prove a limit exists.

There is a chat line saying "maybe 100mb?" with a question mark. That is not a
spec. No man page, no `--help` text, and no failing reproduction are attached
to this note.

I am not ready to answer the size-limit question from this evidence. The only
observed command is one successful put of a 12MB file, and the size-limit claim
is still a rumor.
