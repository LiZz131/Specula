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

# Incremental update (case-002, run incr-8c80add29fe2)

Source revisions: prior exact-old snapshot (`/work/old-source`, neutral commit
`baseline` 1414ebf) -> updated snapshot (`/work/new-source`, neutral commit
`update` 2efbdfc, artifact tree `artifact/`). Changed files:
`ZooKeeperServer.java`, `quorum/Learner.java`, new test
`quorum/DIFFSyncConsistencyTest.java`. No history, issue, or external research
was used; the only requirement text is in the supplied source and test.

## Disposition (Chapter 1): MODEL_CHANGE_REQUIRED

Projection of each changed branch onto the model vocabulary:

| Changed branch | Old behaviour | New behaviour | Projected effect |
|---|---|---|---|
| `Learner.syncWithLeader` NEWLEADER case (`Learner.java:726-760`) | snapshot (SNAP/TRUNC), `setCurrentEpoch`, ACK NEWLEADER; buffered `packetsNotCommitted` stay in the learner thread | additionally `setSyncMode(NONE)`, `zk.startupWithoutServing()` (request processors started, state INITIAL), `fzk.logRequest` for every buffered entry, clear buffer, **then** ACK | `queued/proposed` of the learner grow before the ACK; `AppendOne`/`FsyncOne` and per-txn ACK messages become enabled inside the sync window; `syncMode` cleared before the ACK. Different enablement/atomicity => model change. |
| post-UPTODATE (`Learner.java:763-785`) | `setSoTimeout`, `setSyncMode(NONE)`, `zk.startup()` then log/commit buffers | `zk.startServing()` then log remaining buffer / commit | only post-NEWLEADER proposals remain to be handed off |
| `ZooKeeperServer.startup` split (`ZooKeeperServer.java:669-704`) | one `startup()` -> RUNNING | `startupWithoutServing()` -> INITIAL, `startServing()` -> RUNNING | serving gate unchanged for clients; `canShutdown()` (`:784`) is false in INITIAL (lifecycle; code-review CR-2) |

The prior suite could not express the changed window: its `CompleteSync`
installed the leader's history *durably and atomically* and its
`LeaderBroadcast` waited for followers to reach BROADCAST (which really happens
only after UPTODATE, i.e. after the leader started). Both are implementation-
backed repairs required by the update (Chapter 2), recorded separately in
`spec/changelog.md`.

## Update Scenarios

### US-1: NEWLEADER hand-off of synchronized history (affected action)
**Mechanism**: DIFF contents (PROPOSAL/COMMIT pairs) are buffered in
`packetsNotCommitted`; the update hands them to `FollowerZooKeeperServer.logRequest`
(`FollowerZooKeeperServer.java:82-89`, enqueue only) before the NEWLEADER ACK.
**Evidence**: `Learner.java:614,641,667,744-760`; Zab1_0Test DIFF conversation.
**Model**: `SelectSync` (DIFF -> `syncPending`), `LearnerNewLeader`, `LearnerAckNewLeader`.
**Property**: `Update!AckedHistoryHandedOff` (expected to hold for the update,
violated by the old-behaviour control).

### US-2: NEWLEADER ACK vs. transaction-log durability (changed atomicity boundary)
**Mechanism**: `logRequest` only enqueues to `SyncRequestProcessor`; `append` and
`FileTxnLog.commit` (fsync) run later on SyncThread (`SyncRequestProcessor.java:
181-249`), while the learner thread writes the ACK immediately (`Learner.java:760`).
**Requirement evidence**: source intent comment `Learner.java:748` ("make sure sync
the uncommitted logs before commit them (ACK NEWLEADER)"); test rationale
`DIFFSyncConsistencyTest.java:124-131`.
**Model**: `LearnerAckNewLeader` vs `AppendOne`/`FsyncOne`/`Crash`.
**Property**: `Update!NewLeaderAckDurable`.

### US-3: Counted ACK -> leader serves initial history -> crash -> re-election (interaction)
**Mechanism**: `Leader.waitForNewLeaderAck` counts the ACK (`Leader.java:1547-1575`),
`startZkServer` serves the tree rebuilt from the whole log (`Leader.java:593,688`).
If the acking learner crashes before its SyncThread fsync, it restarts with
`currentEpoch` = new epoch (persisted at `Learner.java:743`) but without the
entries; FLE prefers the higher epoch (`FastLeaderElection.totalOrderPredicate`).
**Requirement evidence**: `DIFFSyncConsistencyTest.java:186-201` ("Data
inconsistency detected", "violation of ZAB").
**Model**: US-2 actions + `LeaderBroadcast`, `Crash`, `Restart`, election actions.
**Property**: `Update!CommittedSurvivesLeaderChange`.

### Code-review scenarios (no model counterexample; outside safety granularity)
- **CR-1 (liveness)**: `packetsNotCommitted.clear()` at NEWLEADER (`Learner.java:757`)
  leaves the deque empty; a COMMIT forwarded after NEWLEADER for a proposal
  buffered before it reaches `pif = packetsNotCommitted.peekFirst()` then
  `pif.hdr` (`Learner.java:645-647`) -> NullPointerException, learner abandons sync.
  The leader queues NEWLEADER after `startForwarding` (`LearnerHandler.java:551,596-599`).
- **CR-2 (lifecycle)**: a learner failing between `startupWithoutServing()` and
  `startServing()` leaves state INITIAL, so `LearnerZooKeeperServer.shutdown()`
  returns early (`ZooKeeperServer.java:784-786`, `LearnerZooKeeperServer.java:155-159`)
  and the started SyncRequestProcessor/CommitProcessor are not shut down.
- **CR-3 (liveness)**: SyncThread may write a per-txn ACK (`SendAckRequestProcessor`)
  before the learner thread writes the NEWLEADER ACK; `LearnerHandler` treats the
  first ACK as the NEWLEADER ACK and `waitForNewLeaderAck` rejects its zxid
  (`Leader.java:1555-1563`).

These have no model counterexample (below the safety granularity) and were confirmed separately:
CR-1, CR-2 and CR-3 are REPRODUCED (`spec/confirmation-CR-1.md`, `-CR-2.md`, `-CR-3.md`); all three are absent
from the old revision. The model-checking finding MC-1 (US-2/US-3) is REPRODUCED on both revisions
(`spec/confirmation-MC-1.md`).

## Modeling decisions for the update
- Keep the prior granularity; add `syncPending`, `learnerStage`, `nlAcks`
  (volatile) and the history variable `everCommitted`.
- `NewLeaderLogsPending` selects the new (TRUE, all standard cfgs) or old (FALSE,
  attribution control only) hand-off point; it never weakens a property.
- Late joiners to an already-broadcasting leader remain excluded (prior
  restriction `EnterSyncPhase` requires the leader in SYNC); documented limit.
- Excluded: socket timeouts (`setSoTimeout` moved), JMX/metrics registration,
  session tracker start, observers (`ObserverZooKeeperServer` branch unchanged).
