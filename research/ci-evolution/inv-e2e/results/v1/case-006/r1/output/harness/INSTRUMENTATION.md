# Specula harness (V0, rebased V1 for the `update` revision)

V1 one-command path (from any directory):

```sh
/work/current/.specula-output/harness/run.sh       # update revision -> traces/*.ndjson
/work/current/.specula-output/harness/validate.sh  # SANY + TLC replay of fresh traces
TARGET_REV=7289d1c5e049933b90a9692bbf508714bee02fce TRACE_DIR=$PWD/build/old-traces \
  LOG_PATH=$PWD/spec/output/harness-run-old-control.log harness/run.sh  # old control
TARGET_REV=<rev> harness/repro.sh <log>             # MC-1 reproduction test
```

`apply.sh` now exports the requested commit of the writable artifact repository
(`git archive`) into `build/tree-<sha12>` and applies the patch there, so the
artifact working tree stays clean (V0 patched `/work/work-source` in place and
pinned a different neutral commit id). `gopath.sh` rebuilds the V0 GOPATH overlay
(protobuf v1.3.5, x/net v0.7.0, scheduler-only `pkg/testutil` shim). Go here is
1.27.4; `-vet=off` is kept for the old logger idiom. Every build/test runs under
`timeout 10m`.

Changed instrumentation points (V1): `raft.go` stepFollower `MsgReadIndex`
(`ForwardReadIndex`) and `MsgReadIndexResp` (`HandleReadIndexResponse`), and the
read-message ctx capture in `specula_trace.go`. Three update scenarios were
added to `specula_trace_test.go`; `repro/specula_repro_readindex_test.go` is a
standalone (non-instrumented) reproduction copied into the build tree.

--- V0 notes (historical) ---

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
