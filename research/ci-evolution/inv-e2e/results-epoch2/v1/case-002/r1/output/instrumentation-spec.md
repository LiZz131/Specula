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
- Tracing is opt-in with `-Dspecula.trace.file`; disabled probes return before
  reading extra peer state. Instrumentation changes only `/work/work-source`.
- `Zab1_0Test` uses a `ConversableFollower` fixture whose peer role remains
  LOOKING while the real learner protocol runs. `Trace.tla` documents and maps
  that fixture role to modeled FOLLOWING; phase, epochs, mode, and pipeline state
  remain checked independently.
- Follower COMMIT/application and disk sync use different threads. The observed
  apply-before-local-fsync order is modeled as a valid quorum-certified commit.
- The preserved patch is `harness/patches/instrumentation.patch`.


## V1 (updated source) changes

Rebased patch: `harness/patches/instrumentation.patch` (applies to commit
`update` of `artifact/`). The only V0 hunk that no longer applied was the
`BroadcastReady` probe after `zk.startup()`; it now follows `zk.startServing()`
(`Learner.java:767`). All other V0 probes are unchanged.

| Spec action | Location (new source) and trigger | Event | Mandatory fields | Consumed by `Trace.tla` |
|---|---|---|---|---|
| `FollowerProcessNewLeader` logRequest | `FollowerZooKeeperServer.logRequest` (existing `ProposalQueued`) while still SYNCHRONIZATION | `ProposalQueued` | zxid | `NewLeaderLog`: nlState NONE→LOGGED, zkState INITIAL |
| `FollowerSendNewLeaderAck` | `Learner.syncWithLeader` NEWLEADER branch, after `writePacket(ACK newLeaderZxid)` | `NewLeaderAckSent` | `update.queuedZxid/queuedEpoch/queuedCounter`, `loggedAtNewLeader`, `durableZxid/durableEpoch/durableCounter` (TxnDurable watermark, updated atomically with the `TxnDurable` record), `fsyncedZxidAtAck` (raw watermark written right after `FileTxnLog` force), `serverState` | `ValidateEventPostState`: currentEpoch = new epoch, syncMode NONE, logged ⇔ LOGGED, last queued = queuedEntry, DIFF: last durable = durableEntry, serverState NOT_RUNNING |
| `LeaderProcessNewLeaderAck` | `Leader.waitForNewLeaderAck`, per decision | `NewLeaderAckReceived` | `update.fromSid`, `update.disposition` ∈ {counted, counted-quorum, after-quorum, rejected-zxid-mismatch} | sync phase, epoch, shadowing, quorum = Cardinality(nlAcks) |
| `LeaderBroadcast` | existing leader `PhaseChanged` → broadcast | `PhaseChanged` | — | requires counted NEWLEADER quorum; certifies loaded history |
| `FollowerProcessUpToDate` | after `zk.startServing()` | `BroadcastReady` | DataTree last zxid | nlState must be ACKED; in-memory (`recovered`) position |
| `FsyncOne` → ACK | `SendAckRequestProcessor.processRequest`, after `writePacket` | `TxnAckSent` | zxid | entry durable; LOGGED ⇒ ackShadowed |
| `BeginElection` INITIAL branch | `ZooKeeperServer.shutdown` / `LearnerZooKeeperServer.shutdown` early return | `ShutdownSkipped` | `update.serverState` | INITIAL ⇒ zkState INITIAL, sets `memStale`; role/phase zxid may then equal the stale in-memory position |

Interpretation fixes (inherited checks): `ElectionWon` carries the elected
leader's vote zxid for followers; role/phase/`BroadcastReady` zxids are the
in-memory DataTree position (log, applied prefix, or stale in-memory history
after a skipped INITIAL shutdown). Update properties are evaluated on traces by
`TraceUpdateEvidence.tla` (code observation, not a pass/fail gate).
