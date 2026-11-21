# Instrumentation specification

Updated for the incremental run against artifact commit `update` (2efbdfc).
The top-level `../instrumentation-spec.md` is an identical copy.

## 1. Trace event schema

Each line is one JSON object with `tag="trace"`, scenario, monotonic process-local
sequence, actual wall-clock milliseconds, `System.nanoTime`, Java thread id/name,
and an `event` object. The event contains `name`, `node`, decimal zxid string,
`txnEpoch`, `txnCounter`, and `state`.

| Trace field | Implementation source | TLA+ projection |
|---|---|---|
| `acceptedEpoch` | `QuorumPeer.getAcceptedEpoch()` | `acceptedEpoch[node]` |
| `currentEpoch` | `QuorumPeer.getCurrentEpoch()` | `currentEpoch[node]` |
| `role` | `getPeerState()` | `role[node]` |
| `phase` | `getZabState()` | `phase[node]` |
| `syncMode` | `getSyncMode()` | `syncMode[node]` |
| `txnCounter` + `txnEpoch` | zxid decomposition | entry id + epoch |

Generic ZooKeeperServer probes use `-1`/`unknown` for inaccessible peer fields.
`Trace.ValidateCommonPostState` validates every available peer field and always
validates the emitted synchronization mode. `Trace.ValidateEventPostState`
additionally consumes the zxid fields according to the emitting event: epoch
persistence, last-log/synchronization positions, snapshot/broadcast position,
or the applicable proposal/append/durable/commit/apply pipeline prefix.
Common fields are not copied into the model generically: each can change only at
its source-backed probe (`AcceptedEpochPersisted`, `CurrentEpochPersisted`,
`PeerRoleChanged`/the nested election `PhaseChanged`, `PhaseChanged`, or
`SyncModeChanged`). Other full-state events must agree with the prior modeled
value. The raw `zxid` envelope field is required, while its finite
`txnEpoch`/`txnCounter` projections drive the TLA+ entry checks so the preserved
numeric-zxid trace remains readable by TLC.

## 2. Action-to-code mapping

| Spec action | Exact-old location and trigger | Event | Fields/notes |
|---|---|---|---|
| Election role decision | `FastLeaderElection.setPeerState`, after role assignment | `ElectionWon` | peer state + last zxid |
| Public role | `QuorumPeer.setPeerState`, after assignment | `PeerRoleChanged` | full peer state + last logged zxid |
| Public phase | `QuorumPeer.setZabState`, after assignment | `PhaseChanged` | full peer state + last logged zxid |
| Accepted epoch | `QuorumPeer.setAcceptedEpoch`, after file and memory update | `AcceptedEpochPersisted` | full state + epoch zxid |
| Current epoch | `QuorumPeer.setCurrentEpoch`, after file and memory update | `CurrentEpochPersisted` | full state + epoch zxid |
| Epoch registration | `Learner.registerWithLeader`, after ACKEPOCH write | `FollowerRegistered` | full state + last log zxid |
| Sync-phase/mode | `QuorumPeer.setSyncMode`, after assignment | `SyncModeChanged` | full state + last logged zxid |
| Sync selection | `Learner.syncWithLeader`, after directive processing | `SyncSelected` | mode and leader zxid |
| Snapshot install | same, after deserialize/signature/lastProcessed update | `SnapshotInstalled` | installed zxid |
| `LearnerUpToDate` (UPTODATE consumed, server RUNNING) | `Learner.syncWithLeader`, after `zk.startServing()` (rebased: was after `zk.startup()`) | `BroadcastReady` | data-tree last processed zxid; checked against `applied'` |
| `LearnerProposal` | `Learner.syncWithLeader` case PROPOSAL, after `packetsNotCommitted.add` | `SyncProposalBuffered` | txn zxid; `sync.pending`/`sync.committed`/`sync.toLog` post-state, checked against `Len(pnc')`, `Len(pcm')`, `toLog'` |
| `LearnerCommit` | case COMMIT/COMMITANDACTIVATE, before `packetsNotCommitted.peekFirst()` | `SyncCommitReceived` | commit zxid; buffer fields are the PRE-state (`Len(pnc)`, `Len(pcm)`, `toLog`); an empty buffer selects the NullPointerException branch |
| `LearnerNewLeader` | case NEWLEADER, `setCurrentEpoch` probe while the learner is in the sync loop | `CurrentEpochPersisted` | new epoch, checked against `currentEpoch'` |
| `LearnerStartupWithoutServing` | case NEWLEADER, `setSyncMode(NONE)` probe (update) | `SyncModeChanged` (NONE) | sync mode NONE, data-tree zxid |
| `LearnerLogPending` | `FollowerZooKeeperServer.logRequest` during NEWLEADER (update) | `ProposalQueued` | txn zxid; must be the head of `pnc` and appear in `queued'` |
| `LearnerAckNewLeader` | case NEWLEADER, after `writePacket(ACK newLeaderZxid)` | `NewLeaderAcked` | buffer fields pre/post: `pending` must be 0 (`pnc` cleared), `committed` = `Len(pcm)` |
| `LearnerLogAfterUpToDate` / `LearnerCommitAfterUpToDate` | post-loop `logRequest` / `fzk.commit` | `ProposalQueued` / `CommitDelivered` while `syncStage = serving` | txn zxid vs `queued'` / `committed'` |
| Learner exception | `Follower.followLeader` catch | `FollowerException` | `detail` = exception class; marks the session failed |
| QuorumPeer start | `QuorumPeer.loadDataBase`, after epochs are read | `DatabaseLoaded` | loaded data-tree zxid, checked against `recovered'` (= forced log) |
| Learner proposal queue | `FollowerZooKeeperServer.logRequest`, after `pendingTxns.add` | `ProposalQueued` | txn zxid + full state |
| Log append | `SyncRequestProcessor.run`, after successful DB append | `TxnAppended` | txn zxid/thread |
| Log durability | `SyncRequestProcessor.flush`, after DB commit and before ACK processor | `TxnDurable` | txn zxid/thread |
| Commit delivery | `FollowerZooKeeperServer.commit`, after commit-processor enqueue | `CommitDelivered` | txn zxid + full state |
| Apply | `ZooKeeperServer.processTxn`, after database apply/committed-log update | `TxnApplied` | txn zxid/thread |

## 3. Special considerations

- The writer is synchronized, opens/appends/closes per event, and starts no
  background thread. Sequence order is therefore the serialization order of
  concurrently executing implementation probes.
- Tracing is opt-in with `-Dspecula.trace.file`; disabled probes return before
  reading extra peer state. Instrumentation changes only `/work/work-source`.
- `Zab1_0Test` uses a `ConversableFollower` fixture whose peer role remains
  LOOKING while the real learner protocol runs. `Trace.tla` documents and maps
  that fixture role to modeled FOLLOWING only for those follower scenarios.
- Follower COMMIT/application and disk sync use different threads. An observed
  application may precede local fsync while remaining quorum-certified.
- Public role/phase zxids with counter zero are epoch markers or the empty-log
  position; their epoch is validated against accepted epoch rather than treated
  as a transaction entry.
- Role/phase/registration/sync-mode probes report `QuorumPeer.getLastLoggedZxid()`, i.e. the
  in-memory data tree (`DbPos`), which is NOT fast-forwarded when a learner exits from the
  update's INITIAL server state; Trace checks these zxids against `DbPos`, not the log.
- Leader-side LearnerHandler packet production is not instrumented: `Trace.TraceDeliverPacket`
  supplies exactly the packet the next learner event consumes (Zab1_0Test fixtures likewise).
- The preserved source-relative patch is
  `../harness/patches/instrumentation.patch` (applies to a fresh copy of `artifact/`).
