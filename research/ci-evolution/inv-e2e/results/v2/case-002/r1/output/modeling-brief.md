# Specula V0 modeling brief: ZooKeeper Zab exact-old prior

## 1. System overview

This is a code-derived model of the Java ZooKeeper quorum server in the
immutable `/work/source` tree. It is **Category A (distributed/message-passing)**:
peers elect a leader, synchronize histories, and exchange proposal, ACK, and
commit packets across independent threads. The core scope spans roughly 10 KLOC
across quorum, request-pipeline, database, transaction-log, and snapshot code.
Fast leader election orders candidates by peer epoch, last zxid, then server id;
Zab discovery establishes a new epoch before synchronization and broadcast.
Disk append, fsync, ACK creation, quorum commit, and application are deliberately
separate atomic steps. No upstream history, issue tracker, or later revision was
consulted.

## 2. Scenarios

### Scenario 1: Election, epoch persistence, and activation

**Mechanism**: A peer becomes a protocol leader through separate election,
accepted-epoch, current-epoch, and NEWLEADER-quorum transitions.

**Evidence**:

- Code analysis: `FastLeaderElection.java:722-746` implements the candidate
  ordering; `:1029-1047` requires a quorum before leaving election.
- Code analysis: `Leader.java:602-663` runs epoch proposal, epoch ACK, and
  NEWLEADER ACK barriers; `:1396-1476` persists/validates epoch summaries.
- Code analysis: `QuorumPeer.java:2150-2173` writes epoch files before updating
  the in-memory epoch.

**Affected code paths**: `lookForLeader`, `getEpochToPropose`,
`waitForEpochAck`, `waitForNewLeaderAck`, `setAcceptedEpoch`, `setCurrentEpoch`.

**Suggested modeling approach**: Track role, public Zab phase, accepted/current
epoch, votes, and per-epoch leader sets. Split election, discovery completion,
current-epoch persistence, follower broadcast entry, and leader broadcast entry.

**Priority**: High. **Rationale**: These transitions gate every mutation and
encode the implementation's active-leader safety boundary.

### Scenario 2: DIFF, TRUNC, and SNAP history synchronization

**Mechanism**: The leader selects one of three recovery modes under its database
log lock, while the learner installs or truncates history before acknowledging
NEWLEADER.

**Evidence**:

- Code analysis: `LearnerHandler.java:775-933` selects DIFF/TRUNC/SNAP and calls
  `startForwarding` while protected by the committed-log read lock.
- Code analysis: `Learner.java:546-603` performs deserialization or truncation;
  `:621-747` buffers proposals/commits and persists the new current epoch.
- Code analysis: `ZKDatabase.java:599-622` truncates then reloads, or clears and
  deserializes a snapshot.

**Affected code paths**: `syncFollower`, `queueCommittedProposals`,
`syncWithLeader`, `truncateLog`, `deserializeSnapshot`, `startForwarding`.

**Suggested modeling approach**: Track `syncMode`, `syncSource`,
`syncJustified`, durable/committed/applied histories, and snapshots. Separate
public sync-phase entry, mode selection, history installation, epoch persistence,
and broadcast entry. Permit rollback only in explicit crash/sync actions.

**Priority**: High. **Rationale**: This is the only implementation path that can
legitimately replace or shorten a peer's history.

### Scenario 3: Proposal pipeline, durability, commit, and apply

**Mechanism**: Propose/queue, transaction-log append, fsync/ACK, quorum commit,
commit delivery, and state-machine application occur on independent processors.

**Evidence**:

- Code analysis: `ProposalRequestProcessor.java:66-91` proposes before queuing
  the leader's disk sync.
- Code analysis: `SyncRequestProcessor.java:181-215` appends and batches;
  `:227-249` fsyncs before invoking the ACK processor.
- Code analysis: `FollowerZooKeeperServer.java:82-110` queues proposals and
  separately matches commit zxids to the queue head.
- Code analysis: `Leader.java:890-963` commits only an in-order proposal with
  quorum ACKs; `ZooKeeperServer.java:1747-1785` performs application.

**Affected code paths**: `propose`, `append`, `commit`, `processAck`,
`tryToCommit`, follower `logRequest`, follower `commit`, server `processTxn`.

**Suggested modeling approach**: Use prefix-ordered proposed, queued, appended,
durable, committed, and applied histories; ACK sets; commit certificates; and
proposal/ACK/commit messages. Model local follower apply as requiring the
leader's quorum certificate, not that follower's own fsync.

**Priority**: High. **Rationale**: The separation is directly observable in the
real trace and is the central safety-critical concurrency boundary.

### Scenario 4: Snapshot, crash, restart, and re-election

**Mechanism**: Snapshot state and transaction-log state persist independently;
restart restores the snapshot and replays durable edits before the peer can be
synchronized to the elected leader.

**Evidence**:

- Code analysis: `FileTxnSnapLog.java:243-304` restores a snapshot and replays
  edits; `:317-367` applies each recovered transaction.
- Code analysis: `ZKDatabase.java:284-303` initializes from storage;
  `ZooKeeperServer.java:789-841` drains processors and may fast-forward the DB.
- Code analysis: `FileTxnLog.java:375-405` flushes and forces log channels.

**Affected code paths**: `restore`, `fastForwardFromEdits`, `loadDataBase`,
`takeSnapshot`, `shutdown`, peer main loop re-election.

**Suggested modeling approach**: Distinguish snapshots, durable logs, and
tentative recovered history. Crash drops non-durable pipeline stages and resets
visible state to the snapshot; restart reloads the durable history for later
election/sync. Mark only crash or sync replacement as authorized rollback.

**Priority**: High. **Rationale**: Recovery crosses persistent and volatile
boundaries and is required by the binding scope.

## 3. Modeling recommendations

### 3.1 Model

- Fixed voting membership and majority quorum: sufficient to exercise the
  exact-old quorum barriers in Scenarios 1 and 3.
- Separate accepted/current epochs and public phases: source persists them at
  distinct points (Scenario 1).
- DIFF/TRUNC/SNAP as guarded choices with explicit completion (Scenario 2).
- Cumulative pipeline prefixes and explicit messages (Scenario 3).
- Snapshot/durable/recovered state plus crash, restart, and message loss
  (Scenario 4).

### 3.2 Do not model

- Dynamic reconfiguration and observers: present in source but outside the
  neutral binding scope's fixed participant scenarios.
- Sessions, watches, ACLs, digests, and concrete znode payloads: application
  semantics do not affect the ordered-history properties checked here.
- Socket framing, TLS/SASL, JMX, metrics, batching heuristics, and fsync latency:
  operational details not needed for protocol safety.
- Wall-clock liveness and failure detectors: no fairness/availability claim is
  justified by the bounded environment.

## 4. Proposed extensions

| Extension | Variables | Purpose | Scenario |
|---|---|---|---|
| Election/epoch phases | `role`, `phase`, `acceptedEpoch`, `currentEpoch`, `votes`, `leadersByEpoch` | Represent source activation barriers | 1 |
| Sync modes | `syncMode`, `syncSource`, `syncJustified` | Represent DIFF/TRUNC/SNAP selection and completion | 2 |
| Pipeline histories | `proposed`, `queued`, `appended`, `durable`, `committed`, `applied` | Preserve exact processor atomicity | 3 |
| Quorum certificates | `acked`, `commitCertified`, `messages` | Distinguish local fsync from global commit durability | 3 |
| Recovery state | `snapshot`, `recovered`, `rollbackAuthorized`, `up` | Represent crash/restart and legitimate repair | 4 |

## 5. Proposed invariants

| Invariant | Type | Description | Targets |
|---|---|---|---|
| `TypeOK` | Safety | All variables remain in declared finite domains | All |
| `ElectionSafety` | Safety | At most one elected leader per epoch | 1 |
| `OneActiveLeaderPerEpoch` | Safety | At most one live leading peer per accepted epoch | 1 |
| `CommittedHistoriesPrefix` | Safety | Any two committed histories are prefix comparable | 2, 3, 4 |
| `ApplyRequiresCommitCertificate` | Safety | Applied entries are committed and quorum-certified | 3 |
| `PipelinePrefix` | Safety | Durable/appended/queued/proposed and snapshot/applied stages remain prefixes | 2, 3, 4 |
| `EpochHistoryConsistency` | Safety | Current epoch and durable history do not exceed accepted epoch | 1, 4 |
| `SyncCompletionJustified` | Safety | A broadcasting follower completed a selected sync and persisted its epoch | 2 |
| `HistoryPositionsMonotonicExceptRecovery` | Safety | History lengths shrink only in marked crash/sync repair steps | 2, 4 |

## 6. Findings pending verification

### 6.1 Model-checkable

| ID | Description | Expected invariant violation | Scenario |
|---|---|---|---|
| Q1 | Can election/discovery interleavings create two active leaders in one epoch? | `ElectionSafety` or `OneActiveLeaderPerEpoch` | 1 |
| Q2 | Can a learner enter broadcast without a selected and completed history sync? | `SyncCompletionJustified` | 2 |
| Q3 | Can processor/message interleavings apply an entry without a leader quorum certificate? | `ApplyRequiresCommitCertificate` | 3 |
| Q4 | Can crash/restart or sync shorten history outside an explicit recovery boundary? | `HistoryPositionsMonotonicExceptRecovery` | 4 |

### 6.2 Test-verifiable

| ID | Description | Suggested test approach |
|---|---|---|
| T1 | Concrete SNAP and DIFF persistence behavior | Existing `Zab1_0Test` conversations with synchronous probes |
| T2 | Real election/client/shutdown and abandonment/restart | Existing `QuorumPeerMainTest` scenarios with per-run traces |

### 6.3 Code-review-only

None. This fresh prior did not identify a source defect requiring manual
confirmation; it records open mechanism questions rather than a known incident.

## 7. Reference pointers

- Full analysis: `/work/prior/.specula-output/analysis-report.md`
- Binding scope: `/work/scope.md`
- Key source: `FastLeaderElection.java`, `Leader.java`, `Learner.java`,
  `LearnerHandler.java`, `SyncRequestProcessor.java`, `ZKDatabase.java`, and
  persistence classes under `/work/source/zookeeper-server/src/main/java`.


---

## 8. Incremental update (artifact commit `update`)

**Category**: A (unchanged). **Disposition**: MODEL_CHANGE_REQUIRED. Evidence
and projection: `analysis-report.md` section U.2. No history, issues or
external sources were consulted; all claims cite the supplied source.

### Scenario U1: NEWLEADER ACK versus durability of the synchronized history

**Mechanism**: the updated NEWLEADER branch hands the buffered DIFF/TRUNC
proposals to `FollowerZooKeeperServer.logRequest` (an enqueue into the
asynchronous `SyncRequestProcessor`) and immediately writes ACK(NEWLEADER);
`Leader.waitForNewLeaderAck` counts that ACK toward the activation quorum.
**Evidence**: Learner.java:745-760; FollowerZooKeeperServer.java:81-88;
SyncRequestProcessor.java:166-250; Leader.java:663, 688, 1547-1585; stated
contract Learner.java:757; zookeeperInternals.md:119, :194, :196-197.
**Actions**: ReceiveSyncPayload, PersistCurrentEpoch, ClearSyncMode,
AckNewLeader (affected); AppendOne, FsyncOne, LeaderBroadcast (interaction).
**Properties**: NewLeaderAckDurable (requirement), CommittedDurableOnQuorum.

### Scenario U2: crash inside the ACK/fsync window

**Mechanism**: U1 plus Crash (queued records are lost) and re-election.
**Properties**: LeaderCompleteness, CommittedHistoriesPrefix.

### Scenario U3: COMMIT of a pre-NEWLEADER proposal arriving after NEWLEADER

**Mechanism**: `packetsNotCommitted.clear()` at NEWLEADER (Learner.java:757);
the COMMIT case dereferences `packetsNotCommitted.peekFirst()` (Learner.java:645-646).
A learner joining an established leader receives outstanding proposals before
NEWLEADER (`Leader.startForwarding`, Leader.java:1294-1326) and their COMMITs
can be queued before UPTODATE (LearnerHandler.java:613-648).
**Verification route**: code observation / code-review finding CR-1 (the
reference model synchronizes only with a leader in its SYNCHRONIZATION phase,
inherited scope; late join is not modeled).

### Scenario U4: aborted synchronization in the INITIAL window

**Mechanism**: between NEWLEADER and UPTODATE the server is INITIAL
(`startupWithoutServing`); any failure (UPTODATE timeout, NPE of U3, leader
loss) runs `Learner.shutdown -> zk.shutdown()`, whose `canShutdown()` is false
(ZooKeeperServer.java:784-786, LearnerZooKeeperServer.java:155-158): processors
are not stopped and the database is not fast-forwarded. The leaked
`SyncRequestProcessor` persists the streamed txns while the in-memory database
(reported in FLE and ACKEPOCH, served by a new leader) lacks them.
**Actions**: BeginElection (from sync), AppendOne/FsyncOne (leaked),
CastVote/WinElection (memHist), SelectSync/ReceiveSyncPayload, LeaderBroadcast.
**Properties**: LeaderCompleteness, SyncedLogMatchesLeader.

### Scenario U5 (code-review note, not confirmed)

The learner's `SendAckRequestProcessor` may now write a txn ACK before
ACK(NEWLEADER); `Leader.waitForNewLeaderAck` would then reject the mismatched
zxid. No `NewLeaderAckRejected` event occurred in any fresh trace; kept as an
unconfirmed hypothesis only.

### Modeling recommendations applied

Model state added: `pendingSync`, `nlAckSent`, `nlAcks`, `certEpoch` (ghost),
`memHist`. Repairs of prior abstractions: atomic durable `CompleteSync`,
activation gated on follower BROADCAST, inventive `QueueLearnerProposal` /
`ObserveCommit`, leave-without-flush, durable-log votes. Excluded (unchanged):
observers, reconfiguration, sessions/watches, byte formats.

### Findings

| ID | Source | Summary |
|---|---|---|
| MC-1 | model checking | NEWLEADER quorum commits a history that is not durable on a quorum (U1/U2) |
| MC-2 | model checking | aborted sync after the NEWLEADER ACK leaves the in-memory database behind the log; a later-epoch leader activates without a committed txn (U4) |
| MC-3 | model checking (pre-existing) | a RUNNING learner's leave fast-forwards memory before flushing its sync processor; an uncommitted proposal persists outside the next leader's history (unchanged code, exposed by the trace-driven memHist refinement) |
| CR-1 | code review + observation | NPE on a post-NEWLEADER COMMIT for a proposal streamed before NEWLEADER (U3) |
