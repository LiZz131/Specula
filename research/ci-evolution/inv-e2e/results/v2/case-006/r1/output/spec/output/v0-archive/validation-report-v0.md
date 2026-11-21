# V0 validation report

## Result

The exact-old model and harness are mutually consistent for both collected
traces, and bounded model checking found no neutral-property violation. Overall
status is limited coverage because the concrete traces cover two three-node
executions and several larger TLC searches reached their outer time limits.

## Trace-first evidence

- Harness: real exact-old three-node state machine and in-tree message router.
- Read trace: `traces/quorum_read.ndjson`, 28 records, 10,831 bytes, SHA-256
  `af0d0d4c326abbd2624bab163c4daff5693eef6a96a8aea1dae3e90d5b0d26f0`.
- Quorum-loss trace: `traces/quorum_loss.ndjson`, 15 records, 5,709 bytes,
  SHA-256
  `d51ef97f25236fa347b21dfc876cedb79bd3e931cf0eddf417cee7e71ea7af82`.
- Read TLC: 33 generated / 29 distinct states, full depth 29; quorum-loss
  TLC: 16 generated / 16 distinct states, full depth 16. All records consumed,
  temporal properties checked, and no error was found.
- Classification fixes: zero-entry Append commit broadcasts were added to the
  faithful base transition; empty JSON queues were made explicit arrays. No
  safety property was weakened.

## Model-checking evidence

| Run | Result | States / depth |
|---|---|---|
| `MC_complete_core.cfg` | complete, no error | 109,936 generated; 26,255 distinct; depth 23 |
| `MC_hunt_s1_election.cfg` | complete, no error | 71,848 generated; 18,550 distinct; depth 18 |
| `MC_hunt_s3_quorum.cfg` | complete, no error | 25,861 generated; 4,912 distinct; depth 20 |
| `MC.cfg` | 2-minute bound, no observed violation | last report 1,633,425 generated; 426,837 distinct; depth 17 |
| replication/read target configs | 20-second bounds, no observed violation | periodic lower bounds preserved in their logs |

Separate `Reach_*.cfg` checks deliberately negate a scenario flag and expect
an invariant violation as a reachability witness. They reached leader, commit,
quorum-check, Ready-read, and forwarded-read-response states. These witnesses
are non-vacuity evidence, not bug findings.

## Implementation tests

The focused exact-old tests and both rafttest network tests passed. The old
source requires a GOPATH overlay and `-vet=off` under Go 1.23 because modern vet
rejects an old logger forwarding idiom. The missing out-of-scope
`pkg/testutil` import used only by unrelated node test compilation is supplied
by a documented scheduler shim in the overlay; the focused tests do not call
it.

## Modeling correction classification

An early MC counterexample was a spec/integration error: outbound messages were
deliverable before the sender's Ready HardState/log was durable, allowing an
execution the exact-old Node contract forbids across crash/restart. The MC
composed base/MC network now requires sender persistence before vote, append,
or heartbeat delivery. Trace replay continues to model direct `raft.Step` tests at the core
boundary. The corrected configurations were rerun; this is not an
implementation finding.
