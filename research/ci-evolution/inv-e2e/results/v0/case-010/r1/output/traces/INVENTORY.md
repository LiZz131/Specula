# Trace inventory (case-010 incremental run)

## Final fresh new-version trace suite (schema v3, harness label `v3b`, source `update` b16ba71)

Produced by one `harness/run.sh` invocation (`spec/output/harness-run-v3b.log`); every JUnit test passed.

| Trace | Scenario test | Lines | sha256 (first 16) | Final replay log | Result |
|---|---|---:|---|---|---|
| `traces/election-ordered-v3b.ndjson` | SpeculaTraceScenarioTest#testElectionAndOrderedMutations (V0 regression) | 86 | `dd168457256fcfae` | `spec/output/final-gate-trace-election-ordered-v3b.log` | PASS: TraceMatched checked, 87 distinct states, queue empty |
| `traces/restart-catchup-v3b.ndjson` | SpeculaTraceScenarioTest#testStartupMutationRestartAndCatchup (V0 regression) | 158 | `dabbd77327f630ae` | `spec/output/final-gate-trace-restart-catchup-v3b.log` | PASS: TraceMatched checked, 159 distinct states, queue empty |
| `traces/snap-abort-rejoin-v3b.ndjson` | QuorumPeerMainTest#testDiffSyncAfterSnap (test added by the update) | 306 | `90bb188936b0e568` | `spec/output/final-gate-trace-snap-abort-rejoin-v3b.log` | PASS: TraceMatched checked, 307 distinct states, queue empty |
| `traces/snap-complete-restart-v3b.ndjson` | SpeculaTraceScenarioTest#testForcedSnapRejoinCompletesAndRestarts (update-derived) | 119 | `8d0c99f215eb9702` | `spec/output/final-gate-trace-snap-complete-restart-v3b.log` | PASS: TraceMatched checked, 120 distinct states, queue empty |

Earlier fresh set `*-v3.ndjson` (same harness minus the fourth scenario) is retained; its replays (`gate2-trace-*-v3.log`) passed against the pre-final Trace.tla and are superseded by the v3b gate.

### Event inventory across the final suite

| Event | Count |
|---|---:|
| `AckNewLeader` | 15 |
| `ApplyTxn` | 50 |
| `BeginSnapshot` | 5 |
| `ChooseSyncMode` | 31 |
| `CommitProposal` | 17 |
| `CompleteLearnerSync` | 15 |
| `FinishElection` | 21 |
| `FinishSnapshot` | 5 |
| `FlushTxnLog` | 50 |
| `FollowerCommit` | 33 |
| `FollowerPendingProposal` | 33 |
| `FormNewLeaderQuorum` | 5 |
| `GracefulShutdown` | 20 |
| `LeaderPropose` | 17 |
| `LearnerApplySnapshot` | 2 |
| `LearnerShutdown` | 31 |
| `LearnerSyncCommit` | 11 |
| `LearnerSyncPacket` | 11 |
| `LearnerSyncSnapshot` | 1 |
| `LearnerUpToDate` | 15 |
| `ObserveReportedZxid` | 16 |
| `PersistAcceptedEpoch` | 15 |
| `PersistCurrentEpoch` | 20 |
| `QueueForSync` | 50 |
| `RecordProposalAck` | 34 |
| `RestartLoadDatabase` | 21 |
| `SetPeerState` | 42 |
| `SetZabState` | 83 |

Every event name has a consuming `TraceNext` disjunct in `spec/Trace.tla`. Reference actions with no
real observation: `LearnerTruncateLog` (no TRUNC sync occurred), `LeaderShutdown`, `Crash`,
`BeginElectionRound`, `CastVote` (votes not instrumented), `LearnerSyncCommit` with `inMemory=true`
(no COMMIT arrived inside a SNAP/TRUNC window in the real runs), `RecordEpochAck` (replayed only via
`ObserveReportedZxid`). These are validation gaps covered only by model checking.

## Field-consumption (non-vacuity) evidence (final Trace.tla)

| Input | Config | Expected rejection line | Observed |
|---|---|---:|---|
| `traces/snap-abort-rejoin-v3b.ndjson` (real) | `Trace-oldsemantics-control.cfg` (exact-old learner exit) | 173 (`LearnerShutdown`, fullyShutDown=true) | rejected at 173 (`spec/output/final-nonvacuity-oldsemantics-snap-abort-rejoin-v3b.log`) |
| `traces/mutants/M1-applysnapshot-memLast-v3b.ndjson` | `Trace.cfg` | 172 | rejected at 172 |
| `traces/mutants/M2-snapshutdown-memInit-v3b.ndjson` | `Trace.cfg` | 173 | rejected at 173 |
| `traces/mutants/M3-reload-durableLast-v3b.ndjson` | `Trace.cfg` | 176 | rejected at 176 |
| `traces/mutants/M4-reported-after-reload-v3b.ndjson` | `Trace.cfg` | 180 | rejected at 180 |

Mutants are synthetic diagnostic inputs, not implementation traces.

## Archived V0 traces (old-version evidence, immutable copies)

| Trace | Disposition |
|---|---|
| `traces/election-ordered.ndjson`, `traces/restart-catchup.ndjson` (schema v1) | Superseded: same scenarios re-executed on the updated source (`*-v3b`); lack the schema-v3 fields required by the updated `Trace.tla`. Not replayed. |
| `traces/election-ordered-stateful.ndjson`, `traces/restart-catchup-stateful.ndjson` (schema v2) | Superseded as above; their probe source is not preserved in the V0 harness (provenance gap). Not replayed. |

