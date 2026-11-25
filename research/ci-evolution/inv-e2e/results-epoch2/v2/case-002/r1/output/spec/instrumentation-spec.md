# Instrumentation specification (revision `update`, case-002)

Rebased from the V0 specification (`../instrumentation-spec.md` of the prior run).
Source paths are relative to `zookeeper-server/src/main/java/org/apache/zookeeper/server/`.
The patch is `../harness/patches/instrumentation.patch` (against neutral commit
`update`, `2efbdfc3754df193bce05b9792297c813377cdaf`).

## 1. Trace event schema

One JSON object per line with `tag="trace"`, `scenario`, process-local `seq`,
real `timeMillis`/`timeNanos`, Java `thread` id/name, and `event`:
`name`, `node` (`s<sid>`), decimal `zxid` string, `txnEpoch`, `txnCounter`,
optional `peer` (`s<sid>`, mandatory for `NewLeaderAckCounted`/`NewLeaderAckMismatch`),
and `state` = {acceptedEpoch, currentEpoch, role, phase, syncMode} read from the
QuorumPeer (generic ZooKeeperServer probes write -1/"unknown"/"NONE").

| Trace field | Implementation source | TLA+ projection |
|---|---|---|
| `acceptedEpoch` | `QuorumPeer.getAcceptedEpoch()` | `acceptedEpoch[node]` |
| `currentEpoch` | `QuorumPeer.getCurrentEpoch()` | `currentEpoch[node]` |
| `role` | `getPeerState()` | `role[node]` (Zab1_0Test fixture: LOOKING -> following) |
| `phase` | `getZabState()` | `phase[node]` |
| `syncMode` | `getSyncMode()` | `syncMode[node]` (checked when the probe reads the peer) |
| `txnCounter`+`txnEpoch` | zxid decomposition | entry id + epoch |
| `peer` | sid argument of `Leader.waitForNewLeaderAck` | element of `nlAcks[node]` |

Peer-state probes report `QuorumPeer.getLastLoggedZxid()`, i.e. the in-memory
database's lastProcessedZxid (`quorum/QuorumPeer.java:1257-1262`); `Trace.tla`
compares it with `recovered[node]` (not with the durable log).

## 2. Action-to-code mapping

`A` = replayed through the base Action with post-state checks; `O` = inherited
observed projection (unchanged, uninstrumented producers).

| Event | Location and trigger (rebased) | Mode / base Action | Checked fields |
|---|---|---|---|
| `PeerDatabaseLoaded` | `quorum/QuorumPeer.java` `loadDataBase`, after epochs load (new) | A: `Restart` (after `Crash` of a previously active peer) | role, phase, epochs, `recovered`=`durable` zxid |
| `ElectionWon` | `quorum/FastLeaderElection.java` `setPeerState`, after `self.setPeerState` | O | role; zxid = winning vote's zxid (some server's `recovered`) |
| `PeerRoleChanged` | `QuorumPeer.setPeerState`, after assignment | O | role, phase, epochs, `recovered` zxid |
| `PhaseChanged` (election/discovery/sync) | `QuorumPeer.setZabState`, after assignment | O (resets the round; RUNNING shutdown drain/fast-forward) | phase, `recovered` zxid, `durable = queued` on RUNNING shutdown |
| `PhaseChanged` (broadcast, leader) | same | A: `LeaderBroadcast` | phase, epoch marker |
| `PhaseChanged` (broadcast, learner) | same | A: `EnterBroadcast` | phase |
| `AcceptedEpochPersisted` / leader `CurrentEpochPersisted` | `QuorumPeer.setAcceptedEpoch/setCurrentEpoch` | O | epochs |
| learner `CurrentEpochPersisted` | `QuorumPeer.setCurrentEpoch` from `Learner.java:743` | A: `PersistCurrentEpoch` | currentEpoch |
| `FollowerRegistered` | `Learner.registerWithLeader`, after ACKEPOCH write | O | `recovered` zxid |
| `SyncModeChanged` (DIFF/TRUNC/SNAP) | `QuorumPeer.setSyncMode` | A: `SelectSync` | syncMode |
| `SyncModeChanged` (NONE) | `QuorumPeer.setSyncMode` from `Learner.java:750` | A: `ClearSyncMode` (processors start, INITIAL) | syncMode |
| `SyncSelected` | `Learner.syncWithLeader`, after directive processing | A: `CompleteSync` | leader `recovered` zxid, `syncJustified` |
| `SnapshotInstalled` | same, SNAP only | check | snapshot/durable zxid |
| `ProposalQueued` (sync phase) | `FollowerZooKeeperServer.logRequest`, after `pendingTxns.add` (`Learner.java:752-757`, `:777-783`) | A: `LogSyncProposal` | `queued` zxid |
| `ProposalQueued` (broadcast) | same, from `Follower.processPacket` | O | `queued` zxid |
| `NewLeaderAckSent` | `Learner.syncWithLeader`, immediately before `writePacket(ACK newLeaderZxid)` (`Learner.java:760`) (new) | A: `AckNewLeader` | epoch marker, `newLeaderAcked`, queued = proposed |
| `NewLeaderAckCounted` | `Leader.waitForNewLeaderAck`, after `newLeaderProposal.addAck(sid)` (new) | A: `CountNewLeaderAck(node, peer)` | `peer` in `nlAcks[node]` |
| `NewLeaderAckMismatch` | same, mismatched-zxid branch (new) | check | `peer` not in `nlAcks[node]` |
| `BroadcastReady` | `Learner.syncWithLeader`, after `zk.startServing()` (moved, `Learner.java:767`) | A: `ReceiveUpToDate` | `zkState`=running, `recovered`/`applied` zxid |
| `TxnAppended` | `SyncRequestProcessor.run`, after DB append | A (non-leader): `AppendOne`; O (leader) | `appended` zxid |
| `TxnDurable` | `SyncRequestProcessor.flush`, after DB commit, before ACK processor | A (non-leader): `FsyncOne`; O (leader) | `durable` zxid |
| `CommitDelivered` | `FollowerZooKeeperServer.commit`, **before** `commitProcessor.commit` (moved) | A (sync phase): `ObserveCommit`; O (broadcast) | `committed` zxid, certificate |
| `TxnApplied` | `ZooKeeperServer.processTxn(Request)`, after apply | A (follower): `ApplyOne`; O (leader) | `applied` zxid, certificate |

Silent steps in `Trace.tla` (each enabled only by the next event): `SilentBufferProposal`
(uninstrumented leader proposal forwarded to a synchronizing learner),
`SilentLeaderCommit` (uninstrumented `Leader.tryToCommit` of a buffered COMMIT),
`SilentCrashBeforeReload` (`base!Crash` of the previous in-JVM QuorumPeer instance
before `PeerDatabaseLoaded`).

## 3. Special considerations

- The writer is synchronized and opens/appends/closes per event; sequence order is
  the serialization order of concurrent probes. Two capture points were moved to
  remove serialization races: `CommitDelivered` before the CommitProcessor hand-off
  and `NewLeaderAckSent` before the ACK write.
- Tracing is opt-in (`-Dspecula.trace.file`, `-Dspecula.trace.scenario`); the
  `specula` names are kept because this workspace uses `.specula-output`.
- The update scenario (`DIFFSyncConsistencyTest`) restarts peers inside one JVM; the
  reload is observed by `PeerDatabaseLoaded`.
- Zab1_0Test fixtures (`follower-snap`, `follower-diff`) use a test-thread leader:
  `Trace.TraceInit` seeds its history, and the DIFF fixture's directive zxid (taken
  from an unrelated database, `Zab1_0Test.java:721-755`) is not compared.
