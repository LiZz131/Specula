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

# Incremental update (run incr-13b3a238967b, source 1414ebf -> 2efbdfc)

Disposition: **MODEL_CHANGE_REQUIRED** (evidence: `update-analysis.md`).
Category A is unchanged.  The update moves the follower's pipeline start and
the enqueueing of DIFF/buffered proposals from UPTODATE to NEWLEADER, before the
NEWLEADER ACK, and splits `ZooKeeperServer.startup` into
`startupWithoutServing` (INITIAL) + `startServing` (RUNNING).

## Update Scenarios

### Scenario U-DUR: NEWLEADER ACK vs durability of the synchronized history

**Mechanism**: the NEWLEADER ACK feeds the leader's NEWLEADER quorum, which
commits the leader's initial history (Leader.lead:663-712), but the learner
only *enqueues* the DIFF proposals (FollowerZooKeeperServer.logRequest:80-89)
and has already persisted the new currentEpoch (Learner.java:743).
**Evidence**: Learner.java:743-760 (new), SyncRequestProcessor.run/flush:156-252,
the update's own comment at Learner.java:748; fresh trace
`traces/diff-sync-uncommitted.ndjson` seq 108-118: s1 writes the NEWLEADER ACK
(108), the leader reads it (110) and starts broadcasting (115) while s1's DIFF
entry (1,2) is forced only at seq 118.
**Path**: old producer (leader DIFF + NEWLEADER) -> affected `LearnerNewLeader`/
`LearnerAckNewLeader` -> old consumer `LeaderReadNewLeaderAck`/`LeaderBroadcast`
-> crash -> re-election (`HistoryAtLeast` uses currentEpoch first).
**Properties**: `CommittedQuorumDurable` (U1), `CommittedAgreement`.
**Priority**: High.

### Scenario U-ACK: proposal ACK before the NEWLEADER ACK

**Mechanism**: `startupWithoutServing` starts SyncRequestProcessor ->
SendAckRequestProcessor before the learner thread writes the NEWLEADER ACK on
the same stream; LearnerHandler.run:609-623 treats the first ACK as the
NEWLEADER ACK and `waitForNewLeaderAck` ignores a mismatching zxid.
**Evidence**: Learner.java:751-760, SendAckRequestProcessor.java:40-59,
LearnerHandler.java:609-623, Leader.java:1547-1588; fresh trace
`traces/diff-ack-before-newleader-ack.ndjson` seq 13-16 (AckSent (1,1) before
NewLeaderAckSent) and the failing assertion in
`spec/output/harness-diff-ack-before-newleader-ack.log`.
**Property**: `NewLeaderAckFirst` (U2).  **Priority**: High (liveness of epoch
establishment; lost ACK for outstanding proposals).

### Scenario U-NPE: COMMIT after NEWLEADER for a proposal buffered before it

**Mechanism**: `packetsNotCommitted.clear()` at NEWLEADER (Learner.java:757)
while the unchanged COMMIT case dereferences `packetsNotCommitted.peekFirst()`
without a null check (Learner.java:645-646).  An established leader forwards an
outstanding PROPOSAL before NEWLEADER (Leader.startForwarding) and its COMMIT
after NEWLEADER.
**Evidence**: fresh trace `traces/diff-commit-after-newleader.ndjson` (learner
stops after `LearnerSyncCommit`, seq 13), harness assertion failure.
**Property**: `SyncCommitHasPendingProposal` (U3).  **Priority**: High
(learner cannot join while proposals are in flight).

### Scenario U-SPLIT: deferred commits vs split logging

**Mechanism**: pendingTxns now receives the pre-NEWLEADER proposals at
NEWLEADER and the post-NEWLEADER ones at UPTODATE; the deferred commit fold
(FollowerZooKeeperServer.commit) exits on a head mismatch.
**Property**: `DeferredCommitMatchesPending` (U4).  **Priority**: Medium.

### Scenario U-LEAK: failure between NEWLEADER and UPTODATE (CR)

`ZooKeeperServer.canShutdown()` (RUNNING/ERROR only) makes
`LearnerZooKeeperServer.shutdown` a no-op for an INITIAL learner: processors
and SyncThread leak and the data tree is not fast-forwarded.  Modeled for its
history effect only (no drain; leaked forcing continues).  Fresh trace
`diff-sync-uncommitted.ndjson` seq 116-119 (forcing/ACK after role exit) and
seq 131 (the peer then votes/leads with data-tree zxid (1,1) while its log has
(1,2)).

## Defect ledger (update)

| ID | Location | Trigger | Wrong behavior | Evidence | Category | Verification | Scenario | Known |
|----|----------|---------|----------------|----------|----------|--------------|----------|-------|
| D-1 | `quorum/Learner.java:743-760`, `FollowerZooKeeperServer.java:80-89` | DIFF sync; learner crashes after NEWLEADER ACK, before SyncRequestProcessor forces | entries committed by the NEWLEADER quorum are on fewer than a quorum of logs; with currentEpoch already advanced the learner can win the next election and truncate them | code + trace seq 108-118 | protocol | MC | U-DUR | none |
| D-2 | `quorum/Learner.java:751-760` vs `LearnerHandler.java:609-623` | DIFF/buffered proposals forced and ACKed before the learner thread writes the NEWLEADER ACK | leader consumes the proposal ACK as NEWLEADER ACK, ignores it; NEWLEADER quorum can fail (leader timeout) and the proposal ACK is lost | code + trace + failing harness assertion | protocol | MC | U-ACK | none |
| D-3 | `quorum/Learner.java:645-646` after `:757` | PROPOSAL before NEWLEADER, its COMMIT after NEWLEADER | NullPointerException, learner aborts synchronization | code + trace + failing harness assertion | low-level/protocol | MC | U-NPE | none |
| D-4 | `quorum/Learner.java:711-725,764-767` | pre-Zab1.0 leader (UPTODATE without NEWLEADER) | `startServing()` without `startupWithoutServing()`: processors never set up | code | low-level | CR | — | none (out of scope: legacy protocol) |
| D-5 | `ZooKeeperServer.java:784-786` with `Learner.java:751` | learner fails between NEWLEADER and UPTODATE | shutdown skipped: processors/threads leak, no fast-forward; stale data-tree zxid used for votes and leader loading | code + trace seq 116-131 | concurrency | CR | U-LEAK | none |

## Update outcome (after validation and model checking)

Scenarios U-DUR, U-ACK, U-NPE produced model-checking counterexamples and were
reproduced on the updated implementation (MC-1..MC-3); U-SPLIT showed no
violation within budget; U-LEAK (D-5) and D-4 were reproduced as code-review
findings CR-4 and CR-5.  See `analysis-report.md` (final section).
