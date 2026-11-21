# Fresh new-version trace inventory (schemaVersion 3)

Source: artifact HEAD b16ba7105238d46b0d51e3cc5d92ce9fe16de834 + harness/patches/instrumentation.patch. Validation logs: spec/output/trace-<name>-v3.log (TLC, Trace.cfg, PROPERTIES TraceMatched).

| Trace | Lines | Distinct events | TLC result |
|---|---:|---:|---|
| `traces/election-ordered-v3.ndjson` | 80 | 21 | PASS (complete, TraceMatched) |
| `traces/restart-catchup-v3.ndjson` | 141 | 21 | PASS (complete, TraceMatched) |
| `traces/upd-snap-exit-diff-v3.ndjson` | 273 | 23 | PASS (complete, TraceMatched) |
| `traces/upd-serving-exit-v3.ndjson` | 120 | 21 | PASS (complete, TraceMatched) |
| `traces/upd-snap-complete-v3.ndjson` | 151 | 22 | PASS (complete, TraceMatched) |

## Event inventory and consumption

| Event | Count | Consumed by Trace.tla wrapper | Fields emitted |
|---|---:|---|---|
| ApplyTxn | 56 | yes | msg.lastZxid, msg.tx, state.acceptedEpoch, state.currentEpoch, state.phase, state.role, state.running, state.syncMode |
| BeginSnapshot | 13 | yes | msg.lastZxid, msg.syncSnap, state.acceptedEpoch, state.currentEpoch, state.phase, state.role, state.running, state.syncMode |
| ChooseSyncMode | 41 | yes | state.acceptedEpoch, state.currentEpoch, state.phase, state.role, state.running, state.syncMode |
| CommitProposal | 19 | yes | msg.tx, state.acceptedEpoch, state.commitWitness, state.currentEpoch, state.phase, state.role, state.running, state.syncMode |
| CompleteLearnerSync | 20 | yes | msg.leader, state.acceptedEpoch, state.currentEpoch, state.phase, state.role, state.running, state.syncMode |
| FinishElection | 29 | yes | msg.electionEpoch, msg.leader, state.acceptedEpoch, state.currentEpoch, state.phase, state.role, state.running, state.syncMode |
| FinishSnapshot | 13 | yes | msg.lastZxid, msg.syncSnap, state.acceptedEpoch, state.currentEpoch, state.phase, state.role, state.running, state.syncMode |
| FlushTxnLog | 56 | yes | msg.leaked, msg.tx, state.acceptedEpoch, state.currentEpoch, state.phase, state.queue, state.role, state.running, state.syncMode |
| FollowerCommit | 37 | yes | msg.tx, state.acceptedEpoch, state.currentEpoch, state.pending, state.phase, state.role, state.running, state.syncMode |
| FollowerPendingProposal | 37 | yes | msg.tx, state.acceptedEpoch, state.currentEpoch, state.pending, state.phase, state.role, state.running, state.syncMode |
| FormNewLeaderQuorum | 8 | yes | state.acceptedEpoch, state.currentEpoch, state.phase, state.role, state.running, state.syncMode |
| GracefulShutdown | 26 | yes | state.acceptedEpoch, state.currentEpoch, state.phase, state.role, state.running, state.syncMode |
| LeaderPropose | 19 | yes | msg.tx, state.acceptedEpoch, state.currentEpoch, state.phase, state.role, state.running, state.syncMode |
| LearnerShutdown | 39 | yes | msg.dbInit, msg.full, msg.leakedNow, msg.leakedQueue, msg.served, state.acceptedEpoch, state.currentEpoch, state.phase, state.role, state.running, state.syncMode |
| LoadSyncSnapshot | 6 | yes | msg.lastZxid, state.acceptedEpoch, state.currentEpoch, state.phase, state.role, state.running, state.syncMode |
| PersistAcceptedEpoch | 24 | yes | state.acceptedEpoch, state.currentEpoch, state.phase, state.role, state.running, state.syncMode |
| PersistCurrentEpoch | 28 | yes | state.acceptedEpoch, state.currentEpoch, state.phase, state.role, state.running, state.syncMode |
| QueueForSync | 56 | yes | msg.tx, state.acceptedEpoch, state.currentEpoch, state.phase, state.queue, state.role, state.running, state.syncMode |
| RecordProposalAck | 38 | yes | msg.source, msg.tx, state.acceptedEpoch, state.acks, state.currentEpoch, state.phase, state.role, state.running, state.syncMode |
| ReloadDatabase | 1 | yes | state.acceptedEpoch, state.currentEpoch, state.phase, state.recovered, state.role, state.running, state.syncMode |
| RestartLoadDatabase | 26 | yes | state.acceptedEpoch, state.currentEpoch, state.phase, state.recovered, state.role, state.running, state.syncMode |
| SetPeerState | 58 | yes | state.acceptedEpoch, state.currentEpoch, state.phase, state.role, state.running, state.syncMode |
| SetZabState | 115 | yes | state.acceptedEpoch, state.currentEpoch, state.phase, state.role, state.running, state.syncMode |

## LearnerShutdown variants observed (served, full, leakedNow, dbInit, nonempty leakedQueue)

- (False, False, False, True, False): 18
- (False, True, False, False, False): 1
- (True, False, True, True, False): 20

## Instrumented events not observed in any fresh trace

TruncateLog, ApplySyncCommit

FlushTxnLog with msg.leaked=true observed: 0
