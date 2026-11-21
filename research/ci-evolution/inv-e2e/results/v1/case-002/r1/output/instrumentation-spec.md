# Instrumentation specification (updated source, incremental run)

Source: `/work/current/.specula-output/artifact` at neutral commit `update`
(`2efbdfc3754df193bce05b9792297c813377cdaf`). Patch:
`harness/patches/instrumentation.patch` (rebased from the prior V0 patch; the
only drifted hunk was the prior `BroadcastReady` probe after `zk.startup()`,
which no longer exists in `Learner.syncWithLeader`).

Abbreviations as in `spec/base.tla` (L = quorum/Learner.java, Ldr = Leader.java,
LH = LearnerHandler.java, ZKS = ZooKeeperServer.java, FZK = FollowerZooKeeperServer.java,
SRP = SyncRequestProcessor.java, QP = QuorumPeer.java, FLE = FastLeaderElection.java).

## 1. Event schema

Event line (`tag = "trace"`): `scenario`, `seq` (process-local, assigned under the
writer lock), real `timeMillis`/`timeNanos`, Java `thread{id,name}`, and `event`:

| Field | Source | TLA+ use |
|---|---|---|
| `name` | probe | selects the wrapper in `Trace.tla` |
| `node` | `QuorumPeer.getId()` / `ZooKeeperServer.getServerId()` | acting server |
| `zxid`, `txnEpoch`, `txnCounter` | probe argument | entry `[id |-> epoch*1000+counter, epoch |-> epoch]`, or position checks |
| `state.acceptedEpoch`, `state.currentEpoch` | QP getters (`-1` if not a peer probe) | `acceptedEpoch[node]`, `currentEpoch[node]` post-state |
| `state.role`, `state.phase` | `getPeerState()`, `getZabState()` | `role[node]`, `phase[node]` post-state |
| `state.syncMode` | `getSyncMode()` | `syncMode[node]` post-state (peer probes only) |
| `peer` | counterpart sid (new) | message sender for `NewLeaderAckReceived`, `AckReceived` |
| `aux` | probe detail (new) | `ZkStartup` server state; `SyncCommitReceived` branch |

Config line (`tag = "config"`, new): one per participant, `servers` = voting
members of its quorum verifier. `Trace.tla` derives `Server` from it.

## 2. Action-to-code mapping

| Event | Code location / trigger | Reference action(s) | Post-state compared |
|---|---|---|---|
| `PeerRoleChanged` | QP.setPeerState after assignment | `WinElection` (leading), `FollowLeader` (following); looking: check only | role/phase/epochs |
| `ElectionWon` | FLE.setPeerState after `self.setPeerState` | check only | vote zxid = `applied[leaderOf]` zxid |
| `PhaseChanged` | QP.setZabState after assignment | election: `BeginElection`; discovery: `StartLeading`/`StartFollowing`; synchronization: `LeaderStartSync`/`EnterSyncPhase`; broadcast: `LeaderEnterBroadcast`/`EnterBroadcast` | role/phase/epochs, syncMode |
| `AcceptedEpochPersisted` | QP.setAcceptedEpoch after file+field | `LeaderProposeEpoch` / `AcceptEpoch` | `acceptedEpoch` = txnEpoch |
| `FollowerRegistered` | L.registerWithLeader after ACKEPOCH write | `SendAckEpoch` | zxid = learner data-tree zxid |
| `SyncModeChanged` | QP.setSyncMode | DIFF `SyncDiff`, TRUNC `SyncTrunc`, SNAP `SyncSnap`, NONE `ClearSyncMode` (now inside NEWLEADER, L:750) | syncMode |
| `SyncSelected` | L after the directive branch | check only | directive zxid (non-fixture scenarios) |
| `SnapshotInstalled` | L after SNAP deserialize | check only | data-tree zxid |
| `SyncProposalReceived` (new) | L case PROPOSAL after `packetsNotCommitted.add` | directive content: check `Known`; otherwise `ReceiveSyncProposal` | entry buffered/known |
| `SyncCommitReceived` (new) | L case COMMIT, all three branches (`aux` = applied/buffered/ignored) | directive content: check; otherwise `ReceiveSyncCommit` | entry in `syncCommits`/`applied` |
| `CurrentEpochPersisted` | QP.setCurrentEpoch | `LeaderPersistEpoch` / `PersistCurrentEpoch` | `currentEpoch` = txnEpoch |
| `ZkStartup` (new) | ZKS.startupWithServerState end, `aux` = INITIAL/RUNNING | INITIAL: `StartupWithoutServing` (L:751); RUNNING on leader: `LeaderActivate` (Ldr:1526) | `zkState`, data-tree zxid |
| `ProposalQueued` | FZK.logRequest after `pendingTxns.add` | sync phase: `LogSyncProposal` (L:752-757 or L:778-782); broadcast: `ReceiveProposal` | entry appended to `proposed`/`queued` |
| `NewLeaderAckSent` (new) | L:760 after `writePacket(ACK newLeaderZxid)` | `SendNewLeaderAck` | `nlAckSent`, empty `syncBuf`, epoch |
| `NewLeaderAckReceived` (new) | LH after reading the first post-NEWLEADER ACK | `ReceiveNewLeaderAck` | zxid = (acceptedEpoch, 0); ack set |
| `UpToDateReceived` (new) | L case UPTODATE | check `UpToDateReady` | leader active, ack consumed |
| `BroadcastReady` | L after `zk.startServing()` (moved from after `zk.startup()`) | `StartServing` | `zkState = RUNNING`, data-tree zxid |
| `CommitDelivered` | FZK.commit after `pendingTxns.remove`, now BEFORE `commitProcessor.commit` | sync phase: `CommitSyncPacket`; broadcast: `ReceiveCommit` | entry appended to `committed` |
| `TxnAppended` | SRP.run after `ZKDatabase.append` | `AppendOne` | last appended entry |
| `TxnDurable` | SRP.flush after DB commit, before next processor | `FsyncOne` | last durable entry |
| `TxnApplied` | ZKS.processTxn(Request) after DB apply | `ApplyOne` | last applied entry |
| `LeaderProposed` (new) | Ldr.propose after `outstandingProposals.put` | `Propose` | entry appended to leader `proposed` |
| `AckReceived` (new) | Ldr.processAck after `p.addAck(sid)` | follower: `DeliverAck`; self: check | `acked[id]` contains peer |
| `LeaderCommitted` (new) | Ldr.tryToCommit after `commit(zxid)` | `Commit` | entry appended to leader `committed` |

Silent actions in `Trace.tla`: `CastVote` (votes are not probed), `DeliverAck`
for acks that `processAck` ignores before `addAck`, and for fixture scenarios the
fixture leader's `ReceiveNewLeaderAck`/`DeliverAck`.

## 3. Special considerations

- The NEWLEADER window is the update: `CurrentEpochPersisted`,
  `SyncModeChanged(NONE)`, `ZkStartup(INITIAL)`, `ProposalQueued`* and
  `NewLeaderAckSent` are emitted by the learner thread in that order; the
  learner's `TxnAppended`/`TxnDurable` for those records come from the
  SyncThread and may follow `NewLeaderAckSent` (the persistence race under study).
- `CommitDelivered` was moved before `commitProcessor.commit` because the prior
  probe position let the CommitProcessor's `TxnApplied` precede it.
- Zab1_0Test `ConversableFollower` scenarios use a test-fixture leader that writes
  packets directly; `Trace.tla` seeds that fixture leader's state and lets its
  unobserved acknowledgement handling be silent. The fixture's DIFF/SNAP
  directive zxid is not a real leader position and is not compared.
- Generic ZooKeeperServer probes have no peer fields (`-1`/`unknown`); only their
  zxid/aux are compared.
