# Validation and checking mismatch classification

| Preserved log | Symptom | Classification | Resolution |
|---|---|---|---|
| `trace-election-validation-attempt1.log` | NDJSON default path was used | Environment/invocation error: `IOEnv` reads an environment variable, not a JVM system property | reran with `JSON=/absolute/path`; no spec or property change |
| `trace-restart-validation-attempt1.log` | `OrderedHistories` failed after restart when a volatile queue contained only transaction 2 | Invariant mismatch: `pendingTxns` and `SyncRequestProcessor.queuedRequests` are ordered work suffixes, not durable history prefixes | retained prefix requirements for durable/committed/applied histories; changed only volatile queues to strict ordered fragments |
| `trace-restart-validation-attempt2.log` | replay stopped on a `FollowerPendingProposal` while the follower was in `SYNCHRONIZATION` | Spec/atomicity mismatch: exact-old DIFF handles PROPOSAL and COMMIT inside `syncWithLeader`; COMMIT/application can race the follower's independent sync flush | admitted the source-observed sync-phase proposal/commit steps; kept normal ACK dependent on completed `FlushTxnLog`; DIFF completion no longer invents local durability |
| `model-checking-attempt1.log` | `OrderedHistories` failed when the model delivered transaction 2 to a follower before transaction 1 | Spec transition bug: the receive action omitted exact-old ordered learner-channel delivery | added the FIFO receive guard `t = Len(prepared[f]) + 1`; no implementation finding |

The later trace-validation logs replay every event and satisfy `TraceMatched`. No faithful safety property was deleted or weakened to turn a failure green. The durability-backed ACK and quorum-backed apply properties remained unchanged throughout debugging.

