# Exact-old Specula V0 harness

`run.sh` idempotently applies `patches/instrumentation.patch` to the neutral
baseline in `/work/work-source`, runs two real in-tree three-node Raft network
scenarios, and writes fresh NDJSON to `../traces/quorum_read.ndjson` and
`../traces/quorum_loss.ndjson`.

The patch adds only disabled-by-default probes plus two tests. Production code
behavior is unchanged unless the test calls `speculaTraceStart`. The preserved
patch is relative to neutral commit
`1852bbdec48ec0c188eaed7451070bbb60672192` and includes all four modified or
added files. `src/` retains standalone copies of the two added harness files.

Run from any directory:

```sh
/work/prior/.specula-output/harness/run.sh
/work/prior/.specula-output/harness/validate.sh
```

The GOPATH overlay under `../build/` pins the two ordinary dependencies needed
by this pre-module source tree. Go 1.23's vet rejects an exact-old logger printf
forwarding idiom, so the harness uses `-vet=off`; compilation and tests remain
otherwise unchanged.
