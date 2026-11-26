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

V0: none. Incremental run (update 2efbdfc): CR-2 (learner failure between
NEWLEADER and UPTODATE leaves an INITIAL server that is never shut down) and
CR-3 (a learner proposal ACK can be consumed as its NEWLEADER ACK); see §8.2
U3/U4 and §8.5.

## 7. Reference pointers

- Full analysis: `/work/prior/.specula-output/analysis-report.md`
- Binding scope: `/work/scope.md`
- Key source: `FastLeaderElection.java`, `Leader.java`, `Learner.java`,
  `LearnerHandler.java`, `SyncRequestProcessor.java`, `ZKDatabase.java`, and
  persistence classes under `/work/source/zookeeper-server/src/main/java`.


## 8. Incremental update 2efbdfc ("update" over "baseline" 1414ebf)

Disposition (Chapter 1): **MODEL_CHANGE_REQUIRED**. Category A is unchanged.

### 8.1 Source delta and projection

| Changed branch (new source) | Old behavior | New behavior | Projection onto the model |
|---|---|---|---|
| `Learner.syncWithLeader` NEWLEADER case (`Learner.java:726-761`) | persist currentEpoch, ACK NEWLEADER; buffered `packetsNotCommitted` stay volatile until after UPTODATE (old `Learner.java:766-774`) | persist currentEpoch, `setSyncMode(NONE)`, `zk.startupWithoutServing()`, `fzk.logRequest` for every buffered proposal (enqueue to SyncRequestProcessor, `FollowerZooKeeperServer.java:86-88`), clear buffer, then ACK | `queued`/`proposed` of the learner grow **before** the NEWLEADER ACK is counted; durability still happens later in `AppendOne`/`FsyncOne`; `syncMode` reset moves before the ACK |
| UPTODATE epilogue (`Learner.java:764-767`) | `setSoTimeout`, `setSyncMode(NONE)`, `zk.startup()` (RUNNING) | only `zk.startServing()` (RUNNING) | pipeline start boundary moves from UPTODATE to NEWLEADER |
| `ZooKeeperServer.startup` split (`ZooKeeperServer.java:669-704`) | one `startup()` → RUNNING | `startupWithoutServing()` → INITIAL, `startServing()` → RUNNING | unchanged consumer `canShutdown()` (`:784-786`) now sees INITIAL for a learner that fails between NEWLEADER and UPTODATE: its shutdown, flush and `fastForwardDataBase` are skipped |
| new test `DIFFSyncConsistencyTest` | — | expresses the intended guarantee (data seen at the old leader must survive at the next leader) | requirement evidence; new harness scenario |

The V0 abstraction (`CompleteSync` copied the leader's durable history into
the learner's *durable* log atomically, `LeaderBroadcast` counted followers
already in BROADCAST, and the leader never committed its recovered history)
could express neither the old nor the new ordering, so the post-state sets of
the NEWLEADER step differ under the existing vocabulary (`queued` changes,
atomic boundary moves). Repairs of those V0 defects are listed in
`spec/changelog.md` separately from the source-driven changes.

### 8.2 Update Scenarios

**U1 — NEWLEADER logging before ACK (affected Action).** old producer
`LearnerHandler.syncFollower`/`startForwarding` (PROPOSAL/COMMIT payload) →
`SyncWithLeaderNewLeader` → old consumer `Leader.waitForNewLeaderAck`.
Observed by `SyncProposalBuffered`, `ProposalQueued`, `NewLeaderAck`,
`NewLeaderAckCounted`. Informs `NewLeaderAckAfterLogging`.

**U2 — ACK-before-fsync window commits the leader's initial history.**
`SyncWithLeaderNewLeader` (queued, not durable) → `LeaderBroadcast`
(startZkServer serves the whole loaded history, `Leader.java:663-712`) →
`FsyncOne` later. Crash of the acking learner before `FsyncOne` and a
re-election without the old leader can lose a transaction that clients
already read. Code: `Learner.java:752-760` (no wait for the SyncRequestProcessor
flush), `SyncRequestProcessor.java:166-246`. Informs `CommittedQuorumDurable`
(new), `CommittedNeverLostByLeader` (new), `CommittedHistoriesPrefix` (kept).

**U3 — learner failure between NEWLEADER and UPTODATE (INITIAL server).**
`SyncWithLeaderNewLeader` → exception before UPTODATE → `Learner.shutdown` →
`ZooKeeperServer.shutdown` returns early because `canShutdown()` is false for
INITIAL (`ZooKeeperServer.java:803-807`, `LearnerZooKeeperServer.java:155-158`).
Request processors (SyncThread, CommitProcessor, …) keep running and the data
tree is not fast-forwarded, so the peer's FLE vote (`getLastLoggedZxid`, data
tree) can lag its durable log. Observed in the fresh trace
`diff-sync-uncommitted-log` (events 91-103). Model: `BeginElection` leaves the
pipeline running; the stale-tree vote is **not modeled** (votes use `durable`)
— recorded as code-review finding CR-2.

**U4 — proposal ACK racing the NEWLEADER ACK.** The SyncRequestProcessor
started at NEWLEADER can write a proposal ACK (`SendAckRequestProcessor`)
before the learner thread writes the NEWLEADER ACK; `LearnerHandler.run`
treats the first ACK after NEWLEADER as the NEWLEADER ACK
(`LearnerHandler.java:611-623`) and `waitForNewLeaderAck` rejects a mismatched
zxid without counting the learner (`Leader.java:1555-1563`). Availability
(liveness) only; messages are unordered in the model and the probe
`NewLeaderAckRejected` was added. Recorded as code-review scenario CR-3.

### 8.3 Properties

| Property | Decision | Where |
|---|---|---|
| `CommittedQuorumDurable` | add (requirement) | `Update.tla` |
| `CommittedNeverLostByLeader` | add (requirement, interaction via re-election) | `Update.tla` (observer `everCommitted`) |
| `NewLeaderAckAfterLogging` | add (update comment `Learner.java:748`) | `Update.tla`; implementation check in `Trace.tla` `NewLeaderAck` |
| `TypeOK` | modify (representation) | `base.tla` |
| other reference properties | keep (evidence in `spec/invariant-evidence.json`) | `base.tla` |

### 8.4 Exclusions (unchanged scope)

Observers (`ObserverZooKeeperServer` branch), pre-Zab-1.0 leaders (no NEWLEADER
before UPTODATE: `startServing` without `startupWithoutServing`), socket
timeouts (`setSoTimeout` move), reconfiguration packets, metrics/JMX
registration of the leaked processors.

### 8.5 Findings and code-review candidates (this run)

| ID | Source | Scenario | Property / observation | Status |
|---|---|---|---|---|
| MC-1 | model checking (`Update-hunt-durable.cfg`, `Update-hunt-loss-witness.cfg`) | U2 | `CommittedQuorumDurable`, `CommittedNeverLostByLeader` violated | REPRODUCED (`spec/confirmation-MC-1.md`) |
| CR-2 | code review | U3 | leaked INITIAL learner server (processors, stale data tree) | REPRODUCED (`spec/confirmation-CR-2.md`) |
| CR-3 | code review | U4 | proposal ACK consumed as NEWLEADER ACK | REPRODUCED (`spec/confirmation-CR-3.md`) |
