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
| Broadcast-ready server | `Learner.syncWithLeader`, after `zk.startup()` | `BroadcastReady` | last processed zxid |
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
  reading extra peer state. Instrumentation changes only `harness/work-source` (a patched copy of `artifact/`).
- `Zab1_0Test` uses a `ConversableFollower` fixture whose peer role remains
  LOOKING while the real learner protocol runs. `Trace.tla` documents and maps
  that fixture role to modeled FOLLOWING; phase, epochs, mode, and pipeline state
  remain checked independently.
- Follower COMMIT/application and disk sync use different threads. The observed
  apply-before-local-fsync order is modeled as a valid quorum-certified commit.
- The preserved patch is `harness/patches/instrumentation.patch`.


## 4. Incremental revision for update 2efbdfc

The harness was rebased (not regenerated): `SpeculaTrace`/`specula.trace.*`
were renamed to `SpecularTrace`/`specular.trace.*`; every record now also has
`event.peer` (`"s<sid>"` or `"none"`). The V0 `BroadcastReady` probe moved from
after `zk.startup()` (removed by the update) to after `zk.startServing()`
(`Learner.java:767`). Update probes:

| Spec action / check | Updated-source location and trigger | Event | Fields / Trace.tla consumer |
|---|---|---|---|
| sync payload buffering (`CompleteSync`) | `Learner.syncWithLeader` PROPOSAL case, after `packetsNotCommitted.add(pif)` (`Learner.java:646`) | `SyncProposalBuffered` | txn zxid → `syncBuf` append; checked not duplicated and in session |
| sync commit buffering (`CompleteSync`) | COMMIT case, after `packetsCommitted.add` (`Learner.java:667`) | `SyncCommitBuffered` | txn zxid → `syncCommit`; must name a held proposal |
| NEWLEADER handler (`SyncWithLeaderNewLeader`) | NEWLEADER case, immediately **before** `writePacket(ACK newLeaderZxid)` (`Learner.java:760`) | `NewLeaderAck` | epoch zxid + full peer state; `ValidateEventPostState` requires current epoch = accepted = zxid epoch, sync mode `NONE`, empty `syncBuf` (all buffered proposals logged via `ProposalQueued` in buffer order after the epoch persisted), every buffered commit queued |
| NEWLEADER ack counting (`LeaderBroadcast` guard) | `Leader.waitForNewLeaderAck`, after `newLeaderProposal.addAck(sid)` (`Leader.java:1569`) | `NewLeaderAckCounted` | leader node, `peer` = acking sid, epoch zxid → `nlAcks`; peer must be the leader or a learner whose `NewLeaderAck` was replayed in the same epoch |
| rejected NEWLEADER ack (CR-3 observation) | same method, zxid-mismatch return (`Leader.java:1562`) | `NewLeaderAckRejected` | leader node, `peer`; zxid must not be the leader's NEWLEADER zxid |
| leader activation (`LeaderBroadcast`) | existing `PhaseChanged` (`Leader.java:712`) | `PhaseChanged` | requires `Cardinality(nlAcks) >= Quorum`; commits/serves the leader's durable history |
| UPTODATE (`SyncWithLeaderUpToDate`) | after `zk.startServing()` (`Learner.java:767`) | `BroadcastReady` | requires stage `newleader` and (non-fixture traces) a leader with an ack quorum |

Interpretation notes added in this revision: `ElectionWon.zxid` is the elected
vote's zxid (`FastLeaderElection.java:898-901`), `PeerRoleChanged`/
`PhaseChanged`/`BroadcastReady` zxids are data-tree zxids that may lag the
durable log (CR-2) or come from an unobserved restart restore; a reported
LEADING peer is projected to the model's `looking` until it persists its new
accepted epoch (`base!WinElection` is atomic).
