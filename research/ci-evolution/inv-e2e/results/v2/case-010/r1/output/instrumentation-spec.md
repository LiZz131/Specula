# Specula V0 instrumentation specification

## Scope and activation

The probes are an opt-in Category-A (distributed/message-passing) trace layer in the writable exact-old tree only. `SpeculaTrace` opens a mutex-protected NDJSON writer when the JVM property `specula.trace.file` is nonempty; without that property every probe returns without opening a file. Each line is flushed synchronously so the file order is the observed cross-thread event order. The pristine tree at `/work/source` is never loaded or edited by the harness.

The wire envelope is:

```json
{"tag":"trace","ts":123,"event":{"name":"ActionName","nid":"s1","state":{},"msg":{}}}
```

`state` always contains `running`, `role`, `phase`, `syncMode`, `acceptedEpoch`, and `currentEpoch`. Schema-version 2 events also carry the post-state fields modified by that event. The probe's mutex-protected shadow histories are updated only at the cited real-code observation points; they do not synthesize protocol events. Raw zxids are mapped, under the same writer mutex, to dense integers in first-observed order. Only create, create2, delete, and setData requests are included; session, authentication, reconfiguration, and administrative transactions remain outside the V0 transaction alphabet.

The event-specific state mapping is: recovery captures `prepared`, `syncQueued`, `pending`, `durable`, `recoveryVisible`, `syncComplete`, and `newLeaderReady`; election completion captures `leaderOf`; learner-sync completion captures `prepared`, `durable`, `recoveryVisible`, `committed`, `applied`, and `syncComplete`; new-leader quorum captures `newLeaderReady`; proposal/pending/queue/flush capture their corresponding history plus `nextTxn` or durability witnesses; ACK captures `acks`; leader commit captures `committed`, `globalCommitted`, and `commitWitness`; follower commit and apply capture their corresponding histories; snapshot begin/finish capture `snapshotBusy` and the captured/published image. Events whose only modified key field is one of the six common fields use that common field as their event-specific post-state evidence. `Trace.tla` requires every schema-version 2 field and compares it with the primed base-spec state.

## Event map

| Event | Exact-old observation point | TLA+ transition / abstraction boundary |
|---|---|---|
| `RestartLoadDatabase` | `QuorumPeer.loadDataBase`, after database/epoch consistency checks | `RestartLoadDatabase`; durable state becomes recovery-visible |
| `GracefulShutdown` | `QuorumPeer.shutdown`, immediately after `running=false` | `GracefulShutdown` |
| `FinishElection` | all three successful returns from `FastLeaderElection.lookForLeader`, after `setPeerState` and `leaveInstance` | `ObserveElectionResult`; the source quorum predicate supplies an abstract quorum witness |
| `SetPeerState` | `QuorumPeer.setPeerState`, immediately after the synchronized role write and before the nested election-phase update | `ObserveSetPeerState` |
| `SetZabState` | `QuorumPeer.setZabState`, after the atomic state write | `ObserveSetZabState` |
| `PersistAcceptedEpoch` | `QuorumPeer.setAcceptedEpoch`, after the atomic file replacement and cached-field update | `PersistAcceptedEpoch` |
| `PersistCurrentEpoch` | `QuorumPeer.setCurrentEpoch`, after the atomic file replacement and cached-field update | `PersistCurrentEpoch` |
| `ChooseSyncMode` | `QuorumPeer.setSyncMode`, after the atomic state write | `ChooseSyncMode`; the last non-`NONE` mode is retained for completion metadata |
| `CompleteLearnerSync` | `Follower.followLeader`, after `syncWithLeader` returns and before entry to broadcast | `CompleteLearnerSync`; DIFF proposal/commit queue effects are separately visible before this event, while TRUNC/SNAP replacement is summarized at this sync-return boundary |
| `FormNewLeaderQuorum` | `Leader.lead`, immediately after `waitForNewLeaderAck` succeeds | `ObserveNewLeaderQuorum`; success implies the source quorum certificate |
| `LeaderPropose` | `Leader.propose`, after insertion into `outstandingProposals` and before `sendPacket` | `LeaderPropose`; placement preserves propose-before-receive order in the serialized trace |
| `FollowerPendingProposal` | `FollowerZooKeeperServer.logRequest`, after insertion into `pendingTxns` | `FollowerPendingProposal` |
| `QueueForSync` | `SyncRequestProcessor.processRequest`, after enqueue | `QueueForSync` |
| `FlushTxnLog` | `SyncRequestProcessor.flush`, after `ZKDatabase.commit`, once for each flushed modeled request and before the ACK processor | `FlushTxnLog`; this is normal ACK durability evidence |
| `RecordProposalAck` | `Leader.processAck`, immediately after `Proposal.addAck` | `RecordProposalAck`; message includes ACK source |
| `CommitProposal` | `Leader.tryToCommit`, after enqueue into the leader commit processor | `CommitProposal`; source code reached a quorum result |
| `FollowerCommit` | `FollowerZooKeeperServer.commit`, after moving the head pending request to the commit processor | `FollowerCommit` |
| `ApplyTxn` | `FinalRequestProcessor.applyRequest`, after `ZooKeeperServer.processTxn` | `ApplyTxn` |
| `BeginSnapshot` | `ZooKeeperServer.takeSnapshot`, immediately before `FileTxnSnapLog.save` | `BeginSnapshot`; captures the fuzzy input image |
| `FinishSnapshot` | same method, after successful save | `FinishSnapshot`; publishes the captured image |

The full source patch is preserved in `harness/patches/instrumentation.patch`. The test class `SpeculaTraceScenarioTest` is the runnable scenario driver. Its two methods cover (1) startup election plus two ordered client mutations and (2) startup, committed mutation, full restart/recovery, a follower missing a second mutation, and follower catch-up.

## Fidelity and limitations

The global writer imposes trace-only serialization and synchronous I/O when enabled, so traces establish conformance for observed executions but not timing equivalence. Probe calls catch only writer I/O failures to avoid changing server control flow. They do not suppress system exceptions or synthesize protocol outcomes.

`CompleteLearnerSync`, `FinishElection`, and `FormNewLeaderQuorum` are completion observations: their detailed internal packet/voter identities are not all emitted. The trace spec records only implications already established by the exact-old return conditions. The shadow histories are instrumentation bookkeeping derived from emitted real events, not a second protocol implementation; the implementation objects and queues remain the authority for whether each probe executes. Ordinary model checking separately expands voter, epoch-ACK, sync-mode, log flush, proposal-ACK, commit, and crash interleavings.

## Incremental probes (case-010, rebased onto commit `update`)

Applied by `harness/apply_update_probes.py` after the unchanged V0 patch (`harness/patches/instrumentation-v0.patch`, applies cleanly to the updated tree). All new fields are required by `Trace.tla`.

| Event | Observation point (updated source) | TLA+ consumer and checked fields |
|---|---|---|
| `RestartLoadDatabase` | moved from inside `QuorumPeer.loadDataBase` to `QuorumPeer.start` after `loadDataBase()` (QuorumPeer.java:1088) | `RestartIfLogged`; `msg.dbInitialized` = `dbInitialized'` |
| `ReloadDatabase` (new) | `QuorumPeer.getLastLoggedZxid` after the reload of an uninitialized DB (QuorumPeer.java:1257-1262) | `ReloadIfLogged` -> `ReloadDatabase`; `msg.dbInitialized` |
| `LearnerShutdown` (new) | `Learner.shutdown` immediately after `zk.shutdown(fully)` (Learner.java:860-866) | `LearnerShutdownIfLogged`: `msg.fully` = `LearnerFully(s)`, `msg.zkRunning` = `LearnerZkRunning(s)`, `msg.syncAlive` = (`CodeVersion = "new"`) when the zk was running, `msg.dbInitialized` = `dbInitialized'` |
| `ReceiveSyncMode` (new) | `Learner.syncWithLeader` after the DIFF/SNAP/TRUNC branch (before `initConfigInZKDatabase`, Learner.java:603) | `ReceiveSyncIfLogged` -> `ReceiveSyncMode(s, leaderOf[s], msg.mode)` incl. the leader-side `ModeAllowed` guard; `msg.dbInitialized` |
| `SyncApplyCommitted` (new) | `Learner.syncWithLeader` COMMIT branch with `!writeToTxnLog`, after `zk.processTxn` (Learner.java:663) | `SyncApplyIfLogged` -> `SyncApplyCommitted(s, msg.tx)` |
| `FlushTxnLog` (changed) | as V0, plus `msg.stale` = the flushing processor's server is not the peer's active leader/follower/observer server | `FlushIfLogged`: stale -> `LeakedFlush`, else `FlushTxnLog` + V0 post-state checks |
| `ChooseSyncMode` NONE | unchanged probe; `setSyncMode(NONE)` occurs only at NEWLEADER (Learner.java:750) | routed to `LearnerAckNewLeader` |
| `BeginSnapshot`/`FinishSnapshot` | unchanged probe; inside a learner SNAP/TRUNC session these are the NEWLEADER snapshot (Learner.java:738-741) | routed to `BeginSyncSnapshot`/`PersistSyncSnapshot` |

The probes read real implementation state (`ZKDatabase.isInitialized`, the boolean passed to `zk.shutdown`, `ZooKeeperServer.isRunning` before the call, `LearnerZooKeeperServer.syncProcessor.isAlive()` after it, `QuorumPeer.getSyncMode`). The `stale` flag reads the peer's `leader/follower/observer` fields without taking the QuorumPeer monitor, to avoid a lock-order inversion with the trace mutex.
