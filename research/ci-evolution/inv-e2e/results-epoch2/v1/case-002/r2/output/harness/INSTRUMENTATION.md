# Harness instrumentation (incremental update)

Synchronous opt-in probes (`SpecularTrace`, enabled by `-Dspecular.trace.file`) installed only in
`../work-source`; exact patch `patches/instrumentation.patch` against neutral commit 2efbdfc. Event schema,
writer, and all prior probes are unchanged except the class/property rename (Specula -> Specular).

Changed points for the update:

| Probe | Location (updated source) | Purpose |
|---|---|---|
| `BroadcastReady` (moved) | `Learner.syncWithLeader`, after `zk.startServing()` (was after `zk.startup()`) | UPTODATE processed, serving |
| `SyncProposalBuffered` (new) | `Learner.syncWithLeader` PROPOSAL case, after `packetsNotCommitted.add(pif)` | producer of the hand-off |
| `SyncProposalApplied` (new) | COMMIT case with `!writeToTxnLog`, after `packetsNotCommitted.remove()` | SNAP/TRUNC in-memory apply |
| `NewLeaderAckSent` (new) | NEWLEADER case, after `writePacket(ACK newLeaderZxid, true)` | affected action boundary |

Event-to-spec mapping and field consumption: `../instrumentation-spec.md` §4 and `../spec/Trace.tla`
(`NextSyncPending`, `NextLearnerStage`, `ValidateEventPostState`). Old-revision control build:
`../controls/old-instrumentation.patch` applied to the `1414ebf` versions of the two changed files.
Rebuild/rerun: `harness/run.sh` (see README).
