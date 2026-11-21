# Harness operation

Run `./run.sh`. It invokes eight exact unit-test scenarios serially in
`/work/work-source`, with a 15-minute outer timeout per process, and writes fresh NDJSON files to
`../traces/`. Tests use the production exact-old Engine methods; only capture and scenario setup
are test-only. Missing `SPECULA_TRACE_FILE` makes the added tests no-op, so ordinary upstream test
runs are unaffected.

Capture is strong for the synchronous Engine boundary: vote, observed vote, role, complete local
log IDs, commit, committed/effective membership, learners, candidate grants, leader matches,
accepted log I/O, and emitted command kinds. It is intentionally not a RaftCore/storage capture;
durable callback state is covered by the formal model and remains a documented extension point.

The trace writer serializes each complete event under a mutex, appends exactly one newline, and
flushes. Scenarios do not start background processes.
