# Specula harness — incremental update c780d355 (rebased from exact-old V0)

`run.sh` (one command) prepares `../build/` (copy of `../artifact` at the
update commit c780d355, GOPATH overlay with protobuf v1.3.5 / x/net v0.7.0 and
a scheduler-only `pkg/testutil` shim), applies `patches/instrumentation.patch`,
runs six real in-tree three-node scenarios and writes fresh NDJSON to
`../traces/`. `validate.sh` replays every fresh trace with TLC (TraceMatched +
post-state checks), runs the stale-ack evidence oracles and the mutated-trace
negative controls. `repro.sh` runs the reproduction/control tests on the
update and baseline trees.

Rebase record: the V0 patch (`patches/instrumentation-v0.patch`, relative to
the V0 neutral baseline) applied cleanly to the update commit (no drift in
`node.go`/`raft.go`). v2 keeps every V0 hunk and adds only:

- state fields `pending` and `readStates` (update-mandatory);
- read-message context capture from `Entries[0].Data`;
- probes `ForwardReadIndex` and `HandleReadIndexResponse` in `stepFollower`;
- four update scenarios (`TestSpeculaTraceReadReuse`, `...ForwardedRead`,
  `...StepDownWithPending`, `...StaleAckReuse`).

```sh
/work/current/.specula-output/harness/run.sh
/work/current/.specula-output/harness/validate.sh
/work/current/.specula-output/harness/repro.sh
```

Go 1.27's vet rejects an old logger printf idiom, so tests run with
`-vet=off`; compilation and execution are otherwise unmodified.
