# Harness instrumentation

The harness uses synchronous, opt-in probes installed only in
`/work/work-source`. Set `specula.trace.file` to enable one-object-per-line
NDJSON output; without it, every probe returns without reading additional peer
state. The exact source-relative patch is preserved at
`patches/instrumentation.patch` against neutral commit
`774296b074905daf3924854264ec54c27842aa9f`.

Each record contains a process-local sequence, actual wall-clock and monotonic
time, Java thread identity, scenario name, event name, node, zxid decomposition,
and the available accepted/current epoch, role, phase, and synchronization mode.
The writer is synchronized, opens and closes the target for every event, and
starts no background work. Full event-to-code and event-to-spec mappings are in
`../instrumentation-spec.md`.

`run.sh` exercises SNAP, DIFF, quorum startup/client mutation/shutdown, and
leader abandonment/restart/recovery with a 240-second outer timeout per Maven
test. Existing traces are moved aside under a process-qualified name before a
fresh run, and the script rejects empty trace output.
