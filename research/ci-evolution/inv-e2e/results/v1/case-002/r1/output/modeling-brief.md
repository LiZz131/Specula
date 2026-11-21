# Specula modeling brief: ZooKeeper Zab (incremental update over the V0 prior)

> Incremental run (case-002). Source: `artifact` commit `update`
> (2efbdfc3754df193bce05b9792297c813377cdaf) over `baseline`
> (1414ebfb1d16fd81abc38550a96950d919ecf805). Disposition:
> **MODEL_CHANGE_REQUIRED** (see `analysis-report.md` §Update reconnaissance).
> Sections 1-6 below are the V0 brief, annotated where the update or a repaired
> abstraction changes them; §8 adds the update Scenarios.

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

**Incremental revision**: the V0 `CompleteSync` installed the leader's durable
history atomically for every mode. Source (both revisions) shows DIFF never
installs anything persistent at selection: proposals/commits are buffered in
`packetsNotCommitted`/`packetsCommitted` (L:621-669) and reach the log only via
`FollowerZooKeeperServer.logRequest` -> asynchronous SyncRequestProcessor. The
reference now splits SyncDiff/SyncTrunc/SyncSnap, NEWLEADER handling
(PersistCurrentEpoch, ClearSyncMode, StartupWithoutServing, LogSyncProposal,
SendNewLeaderAck), UPTODATE handling (StartServing, CommitSyncPacket) and
EnterBroadcast; the leader activates on a quorum of NEWLEADER ACKs
(ReceiveNewLeaderAck, LeaderActivate) instead of on followers' broadcast phase.

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
| Recovery state | `snapshot`, `rollbackAuthorized`, `up` (V0 `recovered` removed: subsumed by `applied`, the in-memory data tree restored at Restart) | Represent crash/restart and legitimate repair | 4 |
| Update: learner session | `syncBuf`, `syncCommits`, `syncStarted`, `nlAckSent`, `epochSet` | packetsNotCommitted/packetsCommitted, directive consumed, NEWLEADER ACK written, ACKEPOCH/epoch settled | 5, 6 |
| Update: server state and activation | `zkState` (NONE/INITIAL/RUNNING), `nlAcks`, message kind `nlack` | startupWithoutServing/startServing, NEWLEADER ack quorum | 5, 6 |

## 5. Proposed invariants

| Invariant | Type | Description | Targets |
|---|---|---|---|
| `TypeOK` | Safety | All variables remain in declared finite domains | All |
| `ElectionSafety` | Safety | At most one elected leader per epoch | 1 |
| `OneActiveLeaderPerEpoch` | Safety | At most one live leading peer per accepted epoch | 1 |
| `CommittedHistoriesPrefix` | Safety | Any two committed histories are prefix comparable | 2, 3, 4 |
| `ServingApplyCommitted` (revises `ApplyRequiresCommitCertificate`) | Safety | A RUNNING (serving) server's data tree is a committed, certified prefix; restored/fast-forwarded uncommitted records are allowed only while not serving | 3, 4 |
| `PipelinePrefix` | Safety | Durable/appended/queued/proposed and snapshot/applied stages remain prefixes | 2, 3, 4 |
| `EpochHistoryConsistency` | Safety | Current epoch and durable history do not exceed accepted epoch | 1, 4 |
| `SyncCompletionJustified` | Safety | A broadcasting follower completed a selected sync and persisted its epoch | 2 |
| `HistoryPositionsMonotonicExceptRecovery` | Safety | History lengths shrink only in marked crash/sync repair steps | 2, 4 |
| `CommittedPersistedOnQuorum` (new, Update.tla) | Safety | Every history an active leader treats as committed is persisted (snapshot or fsynced log) on a quorum | 5 |
| `LeaderCompleteness` (new, Update.tla) | Safety | Every certified (committed) transaction is in every active leader's committed history | 5, 6 |

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

| Q5 | Can a leader activate on NEWLEADER ACKs whose DIFF records are queued but not yet fsynced, and lose them after a learner crash? | `CommittedPersistedOnQuorum`, `LeaderCompleteness` | 5 |
| Q6 | Can a learner that ACKed NEWLEADER and failed before UPTODATE (server still INITIAL) vote/lead with a data tree that omits the logged DIFF records? | `LeaderCompleteness` | 6 |

### 6.3 Code-review-only

| ID | Description | Evidence | Disposition |
|---|---|---|---|
| CR-A | SyncRequestProcessor proposal ACKs for records logged at NEWLEADER (L:752-757) can now reach the LearnerHandler before the NEWLEADER ACK (L:760); LH:613-624 accepts any ACK as the NEWLEADER ACK and Ldr:1555-1563 ignores a mismatched zxid without counting it. Effect: a learner may not count toward the NEWLEADER quorum (liveness / delayed activation only; the later real NEWLEADER ACK is ignored by processAck). | LH:613-624, Ldr:1546-1586, SRP:227-249, SendAckRequestProcessor:41-58 | Not modeled (liveness-only); recorded for review. |
| CR-B | Learner shutdown order: ZKS.shutdown fast-forwards the data tree (ZKS:845) before LZK:166-168 shuts the SyncRequestProcessor down (which flushes queued records), so the in-memory vote basis can miss just-flushed records. Pre-existing, unchanged by the update. | ZKS:803-851, LZK:155-173 | Abstracted (model flushes before fast-forward); recorded. |

## 7. Reference pointers

- Full analysis: `analysis-report.md` (V0 copy: `spec/output/prior-v0/analysis-report-v0.md`)
- Binding scope: `/work/model-scope.md`; update metadata `/work/case.json`
- Key source: `FastLeaderElection.java`, `Leader.java`, `Learner.java`,
  `LearnerHandler.java`, `SyncRequestProcessor.java`, `ZKDatabase.java`, and
  persistence classes under `artifact/zookeeper-server/src/main/java` (commit `update`).



## 8. Update Scenarios (incremental run)

### Scenario 5: NEWLEADER ACK versus durability of synchronized records (changed)

**Mechanism**: In the updated `Learner.syncWithLeader` NEWLEADER branch the learner
persists the new current epoch (L:743), clears the sync mode (L:750), starts its
request processors without serving (L:751, ZKS:673), hands every buffered
proposal to `FollowerZooKeeperServer.logRequest` (L:752-757) and immediately
writes the NEWLEADER ACK (L:760). `logRequest` only enqueues
(FZK:82-89, SRP:291-297); append and fsync happen later on the SyncThread
(SRP:181-249). The leader counts the ACK toward its NEWLEADER quorum
(LH:613-624, Ldr:1546-1586) and then serves its whole loaded history
(Ldr:1497-1537, ZKS:480-512).

**Evidence**: diff hunk L:748-760 (comment: "make sure sync the uncommitted logs
before commit them (ACK NEWLEADER)"); fresh trace `traces/diff-sync-consistency.ndjson`
events 90-98 (ProposalQueued -> NewLeaderAckSent -> leader ZkStartup(RUNNING)
before the learner's TxnDurable) and `traces/follower-diff.ndjson` events 12-20;
requirement text `zookeeper-docs/.../zookeeperInternals.md:115-119, 192-197, 245-250`.

**Affected code paths**: `syncWithLeader`, `logRequest`, `SyncRequestProcessor.run/flush`,
`LearnerHandler.run`, `Leader.waitForNewLeaderAck`, `startZkServer`, `Crash`/restore.

**Modeling approach**: reference actions listed in §2 revision; crash drops
queued/appended-but-unforced records; update properties
`CommittedPersistedOnQuorum` and `LeaderCompleteness` (Update.tla).

**Priority**: High.

### Scenario 6: learner failure between NEWLEADER and UPTODATE (newly reachable state)

**Mechanism**: after `startupWithoutServing` the learner server is INITIAL. If the
learner fails before UPTODATE (socket timeout, leader loss), `Learner.shutdown`
-> `LearnerZooKeeperServer.shutdown` returns immediately because `canShutdown()`
is false for INITIAL (ZKS:784, LZK:155-159): no processor shutdown, no
`fastForwardDataBase` (ZKS:845). The SyncThread keeps writing the queued
records, but the in-memory data tree (the FLE vote zxid, QP:1257-1262, and a new
leader's loaded database, ZKS:480-512) does not contain them until the process
restarts.

**Evidence**: ZKS:784-807, LZK:155-173, QP:1257-1262; fresh trace
`traces/diff-sync-consistency.ndjson` events 109-117: s1 ACKs NEWLEADER for
txn 0x100000002, fails at UPTODATE, its SyncThread fsyncs the record (event 115),
and s1 then wins FLE with data-tree zxid 0x100000001 (events 116-117) while the
epoch-2 leader had already served 0x100000002.

**Modeling approach**: `zkState` (NONE/INITIAL/RUNNING); `BeginElection`
fast-forwards/flushes only from RUNNING; the vote (`HistoryAtLeast`) and leader
history use `applied` (data tree). Checked by `LeaderCompleteness`.

**Priority**: High.

### Exclusions specific to the update

- `isPreZAB1_0` UPTODATE-without-NEWLEADER path now calls `startServing` without
  any `startup*`; ZooKeeper 3.4+ leaders always send NEWLEADER, and the scope's
  fixed Zab 1.0 participants never take this path. Excluded; noted in the report.
- Observers (`ObserverZooKeeperServer` branch, unchanged) and reconfiguration
  packets (COMMITANDACTIVATE/INFORMANDACTIVATE) remain out of scope as in V0.
- `sock.setSoTimeout` moved earlier: timing only; its effect (an earlier socket
  timeout -> learner failure) is covered by nondeterministic `BeginElection`.
