# Instrumentation specification (updated revision, run incr-13b3a238967b)

Category A single-file NDJSON traces.  Writer: `SpecularTrace` (rebased from
the prior `SpeculaTrace`; synchronized, opens/appends/closes per event, opt-in
through `-Dspecular.trace.file`, scenario name `-Dspecular.trace.scenario`).

## 1. Event schema

`{"tag":"trace","scenario","seq","timeMillis","timeNanos","thread":{id,name},
"event":{"name","node","peer","info","zxid","txnEpoch","txnCounter",
"state":{"acceptedEpoch","currentEpoch","role","phase","syncMode"}}}`

* `node` = `s<myid>` of the emitting peer; `peer` = `s<sid>` of the remote
  learner for LearnerHandler events (else empty); `info` = leader sync mode for
  `LeaderSyncQueued` (else empty).
* `txnEpoch/txnCounter` decompose `zxid`; Trace.tla consumes them as the entry
  identity `[id |-> <<epoch,counter>>, epoch |-> epoch]`.
* Generic ZooKeeperServer probes (`TxnAppended/TxnDurable/TxnApplied`) report
  `-1/unknown` peer fields; Trace.tla compares peer fields only when present.

## 2. Event -> reference Action mapping (all consumed by `Trace.tla`)

| Event | Code location (updated tree) | Capture | Trace.tla handling |
|---|---|---|---|
| `PeerRoleChanged` | `QuorumPeer.setPeerState` after assignment | post | looking: fire `BeginElection` if not yet looking; leading/following: prospective-role check |
| `ElectionWon` | `FastLeaderElection.setPeerState` | post | prospective-role check |
| `PhaseChanged` | `QuorumPeer.setZabState` | post | election: `BeginElection`; discovery: `ElectLeader`/`ElectFollow`; sync: `FinishDiscovery`/`EnterSyncPhase`; broadcast: `LeaderBroadcast`/`EnterBroadcast` |
| `AcceptedEpochPersisted` | `QuorumPeer.setAcceptedEpoch` | post | leader: fire `LeaderProposeEpoch` (epoch checked); follower: prospective check |
| `FollowerRegistered` | `Learner.registerWithLeader` after ACKEPOCH | post | fire `AcceptEpoch` |
| `CurrentEpochPersisted` | `QuorumPeer.setCurrentEpoch` | post | leader: prospective check before `FinishDiscovery`; follower: check inside `LearnerNewLeader` |
| `LeaderSyncQueued` (new) | `LearnerHandler.run` after `syncFollower` | post | fire `LeaderSyncFollower(node, peer, info)` |
| `NewLeaderQueued` (new) | `LearnerHandler.run` after NEWLEADER queued/flushed | post | fire `LeaderSendNewLeader` |
| `SyncModeChanged` | `QuorumPeer.setSyncMode` | post | DIFF/TRUNC/SNAP: fire `LearnerReadMode`; NONE: check |
| `SyncSelected`, `SnapshotInstalled` | `Learner.syncWithLeader` after directive | post | check (SNAP/TRUNC base zxid) |
| `LearnerSyncProposal` (new) | sync loop PROPOSAL after `packetsNotCommitted.add` | post | fire `LearnerSyncProposal`; buffered entry checked |
| `LearnerSyncCommit` (new) | sync loop COMMIT, before `peekFirst` | pre | fire `LearnerSyncCommit` (includes the NPE branch); packet entry checked |
| `NewLeaderReceived` (new) | NEWLEADER case entry | pre | fire `LearnerNewLeader` (update) |
| `ProposalQueued` | `FollowerZooKeeperServer.logRequest` after `pendingTxns.add` | post | broadcast: fire `ReceiveProposal`; inside NEWLEADER/UPTODATE: check entry enqueued |
| `NewLeaderAckSent` (new) | after NEWLEADER ACK `writePacket` | post | fire `LearnerAckNewLeader` (or check if fired early) |
| `NewLeaderAckRead` (new) | `LearnerHandler.run` after reading first ACK | post | fire `LeaderReadNewLeaderAck`; consumed ACK zxid must equal the event zxid |
| `UpToDateQueued` (new) | `LearnerHandler.run` after UPTODATE queued | post | fire `LeaderSendUpToDate` |
| `UpToDateReceived` (new) | UPTODATE case entry | pre | fire `LearnerUpToDate` (update) |
| `BroadcastReady` | after `zk.startServing()` | post | check served base zxid, RUNNING |
| `CommitDelivered` | `FollowerZooKeeperServer.commit` after hand-off | post | broadcast: fire `ReceiveCommit`; UPTODATE: check committed |
| `LeaderProposed` (new) | `Leader.propose` after `sendPacket` | post | fire `Propose` |
| `LeaderCommitted` (new) | `Leader.commit` after `sendPacket` | post | fire `Commit` |
| `LeaderAckReceived` (new) | LearnerHandler ACK case after `processAck` | post | fire `LeaderProcessAck`; ACK zxid checked |
| `TxnAppended` | `SyncRequestProcessor.run` after append | post | fire `AppendOne` |
| `TxnDurable` | `SyncRequestProcessor.flush` after DB commit | post | fire `FsyncOne` (produces the ACK) |
| `AckSent` (new) | `SendAckRequestProcessor.processRequest` after write | post | check entry durable / ACK produced |
| `TxnApplied` | `ZooKeeperServer.processTxn` | post | fire `ApplyOne` |

## 3. Mandatory update fields and the predicates that compare them

* NEWLEADER effect: `NewLeaderReceived` fires `LearnerNewLeader`; the following
  `CurrentEpochPersisted` (epoch), `SyncModeChanged(NONE)` (mode) and each
  `ProposalQueued` (entry present in `queued` and `pendingTxns`) are compared
  against the post-state of that step (`OnCurrentEpochPersisted`,
  `OnSyncModeChanged`, `OnProposalQueued`).
* ACK ordering: `NewLeaderAckRead`/`LeaderAckReceived` require the head of the
  modeled learner->leader stream to be the ACK the leader actually read
  (`AckHeadMatches`).  This is the comparison that validates the update's new
  interleaving (proposal ACK before NEWLEADER ACK) in
  `traces/diff-ack-before-newleader-ack.ndjson` and the normal order elsewhere.
* Durability: `TxnAppended`/`TxnDurable` compare the appended/forced entry with
  the modeled pipeline head (`Last(appended')`, `Last(durable')`).
* Sync COMMIT handling: `LearnerSyncCommit` compares the consumed packet entry.

## 4. Documented silent steps / probe races (Trace.tla)

* FLE votes are not instrumented: `SilentVote` (CastVote) only before an
  election event.
* Zab1_0Test fixture leader: `FixtureSend` supplies the packet consumed by the
  next learner event (fixture, not implementation code).
* Probe-ordering races (post-probes serialized after a dependent probe of
  another thread): `SilentAckNewLeader`, `SilentLeaderBroadcast`,
  `SilentSendUpToDate`, `SilentSendNewLeader`, `SilentPropose`,
  `SilentCommit`, `SilentProcessAck`.  Each fires the base Action only when the
  next event requires it; the later probe is then validated as a check.
* Not compared: the zxid of `PeerRoleChanged/PhaseChanged/ElectionWon` (it is
  the in-memory data-tree position, which the model does not represent for
  non-serving peers); the peer-state fields of `AckSent` (read concurrently by
  the SyncThread).
