# Instrumentation specification

## 1. Trace event schema

Each line is one JSON object with `tag="trace"`, scenario, monotonic process-local
sequence, actual wall-clock milliseconds, `System.nanoTime`, Java thread id/name,
and an `event` object. The event contains `name`, `node`, decimal zxid string,
`txnEpoch`, `txnCounter`, and `state`.

State fields map as follows:

| Trace field | Implementation source | TLA+ projection |
|---|---|---|
| `acceptedEpoch` | `QuorumPeer.getAcceptedEpoch()` | `acceptedEpoch[node]` |
| `currentEpoch` | `QuorumPeer.getCurrentEpoch()` | `currentEpoch[node]` |
| `role` | `getPeerState()` | `role[node]` |
| `phase` | `getZabState()` | `phase[node]` |
| `syncMode` | `getSyncMode()` | `syncMode[node]` |
| `txnCounter` + `txnEpoch` | zxid decomposition | entry id + epoch |

Generic ZooKeeperServer probes use `-1`/`unknown` for inaccessible peer fields;
`Trace.ValidatePostState` still validates every available field and always checks
the emitted sync mode. `zxid` is a JSON string because this CommunityModules JSON
reader cannot parse the implementation's unsigned-width decimal zxids as Java
32-bit integers.

## 2. Action-to-code mapping

| Spec action | Exact-old location and trigger | Event | Fields/notes |
|---|---|---|---|
| Election role decision | `FastLeaderElection.setPeerState`, after role assignment | `ElectionWon` | peer state + last zxid |
| Public role | `QuorumPeer.setPeerState`, after assignment | `PeerRoleChanged` | full peer state |
| Public phase | `QuorumPeer.setZabState`, after assignment | `PhaseChanged` | full peer state |
| Accepted epoch | `QuorumPeer.setAcceptedEpoch`, after file and memory update | `AcceptedEpochPersisted` | full state + epoch zxid |
| Current epoch | `QuorumPeer.setCurrentEpoch`, after file and memory update | `CurrentEpochPersisted` | full state + epoch zxid |
| Epoch registration | `Learner.registerWithLeader`, after ACKEPOCH write | `FollowerRegistered` | full state + last log zxid |
| Sync-phase/mode | `QuorumPeer.setSyncMode`, after assignment | `SyncModeChanged` | full state |
| Sync selection | `Learner.syncWithLeader`, after directive processing | `SyncSelected` | mode and leader zxid |
| Snapshot install | same, after deserialize/signature/lastProcessed update | `SnapshotInstalled` | installed zxid |
| Broadcast-ready server | `Learner.syncWithLeader`, after `zk.startServing()` (update; old: after `zk.startup()`) | `BroadcastReady` | last processed zxid |
| Learner proposal queue | `FollowerZooKeeperServer.logRequest`, after `pendingTxns.add` | `ProposalQueued` | txn zxid + full state |
| Log append | `SyncRequestProcessor.run`, after successful DB append | `TxnAppended` | txn zxid/thread |
| Log durability | `SyncRequestProcessor.flush`, after DB commit and before ACK processor | `TxnDurable` | txn zxid/thread |
| Commit delivery | `FollowerZooKeeperServer.commit`, after commit-processor enqueue | `CommitDelivered` | txn zxid + full state |
| Apply | `ZooKeeperServer.processTxn`, after database apply/committed-log update | `TxnApplied` | txn zxid/thread |

## 3. Special considerations

- The writer is synchronized, opens/appends/closes per event, flushes on close,
  and starts no background thread. Sequence order is therefore the serialization
  order of concurrently executing implementation probes.
- Tracing is opt-in with `-Dspecular.trace.file`; disabled probes return before
  reading extra peer state. Instrumentation changes only `/work/current/.specular-output/work-source`.
- `Zab1_0Test` uses a `ConversableFollower` fixture whose peer role remains
  LOOKING while the real learner protocol runs. `Trace.tla` documents and maps
  that fixture role to modeled FOLLOWING; phase, epochs, mode, and pipeline state
  remain checked independently.
- Follower COMMIT/application and disk sync use different threads. The observed
  apply-before-local-fsync order is modeled as a valid quorum-certified commit.
- The preserved patch is `harness/patches/instrumentation.patch`.



## 4. Incremental update probes (case-002, run incr-8c80add29fe2)

The prior probes are rebased unchanged onto the updated tree (class renamed
`SpecularTrace`, property `specular.trace.file`); `BroadcastReady` moved with
the code to just after `zk.startServing()`. New probes around the update window:

| Spec action | Updated location and trigger | Event | Fields / Trace check |
|---|---|---|---|
| `SelectSync` contents (DIFF buffering) | `Learner.syncWithLeader` PROPOSAL case, after `packetsNotCommitted.add(pif)` | `SyncProposalBuffered` | txn zxid; appends to `syncPending[node]`; checked in sync phase with stage selected/newleader/acked |
| SNAP/TRUNC in-memory apply | same, COMMIT case with `!writeToTxnLog`, after `packetsNotCommitted.remove()` | `SyncProposalApplied` | txn zxid; must be head of `syncPending`, mode SNAP/TRUNC |
| `LearnerNewLeader` hand-off | existing `ProposalQueued` (`FollowerZooKeeperServer.logRequest`) emitted inside the NEWLEADER case | `ProposalQueued` | removes the head of `syncPending`, adds to `proposed/queued` |
| `LearnerAckNewLeader` | NEWLEADER case, after `writePacket(ACK newLeaderZxid, true)` | `NewLeaderAckSent` | zxid = (newEpoch, 0); requires `currentEpoch' = epoch`, stage newleader, and (update semantics) `syncPending = <<>>` and `syncMode = NONE` |

Field consumption: `Trace.ValidateEventPostState` compares `txnEpoch/txnCounter`
of each new event with `syncPending`/`currentEpoch`, and the common post-state
check compares `syncMode` (cleared before the ACK by the update). The durable
position of the handed-off entries is observed through the existing
`TxnDurable` probe on SyncThread, so the relative order of `NewLeaderAckSent`
and `TxnDurable` in a fresh trace is direct implementation evidence for the
ACK-versus-fsync window (US-2).
