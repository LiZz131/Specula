# Specula modeling brief — incremental update (case-002)

Category: **A (distributed / message passing)**, unchanged from V0.
Source: artifact `1414ebf` (baseline, V0) → `2efbdfc` (update).  Disposition:
**MODEL_CHANGE_REQUIRED** (see `analysis-report.md` §Incremental update).

## U. Update scenarios

### Scenario U-1: NEWLEADER ACK versus learner durability
**Mechanism**: the update logs buffered DIFF proposals (`fzk.logRequest`) before ACKing
NEWLEADER, but `logRequest` only enqueues to the SyncRequestProcessor; the ACK is sent before
append/fsync (Learner.java:752-760, FollowerZooKeeperServer.java:82-90,
SyncRequestProcessor.java:155-251).  The leader starts serving on a NEWLEADER-ACK quorum
(Leader.java:661-688).
**Evidence**: code; fresh trace `follower-diff` (ACK seq 13, `TxnDurable` seq 21+); real
`diff-sync` replay violates `NewLeaderAckImpliesDurable` (`spec/output/trace-update-props-summary.txt`).
**Model**: `LearnerLogPendingOne`, `LearnerSendNewLeaderAck`, `AppendOne`, `FsyncOne`, `Crash`,
`Restart`, `LeaderStartZkServer`.  **Properties**: U3 `NewLeaderAckImpliesDurable`, U4
`AckedHistoryRetained`, U1 `LeaderCompleteness`.  **Hunt**: `Update-hunt-crash-window.cfg`.

### Scenario U-2: UPTODATE failure after the ACK (shutdown skipped in INITIAL)
**Mechanism**: `startupWithoutServing` leaves the instance in INITIAL; if the learner fails
before UPTODATE, `LearnerZooKeeperServer.shutdown`/`ZooKeeperServer.shutdown` return early
(`canShutdown`), so the DataTree is not fast-forwarded from the log; FLE/FOLLOWERINFO/
`Leader.lead` use the DataTree position, so an in-process re-election can elect a leader that
lacks the txn the previous leader served.
**Evidence**: code (ZooKeeperServer.java:784-807, LearnerZooKeeperServer.java:155-173,
QuorumPeer.java:1257-1262, ZooKeeperServer.java:480-503); fresh trace `diff-sync`
(`ZkShutdownSkipped` INITIAL, tree 1.1 / log 1.2, LOOKING at 1.1); supplementary real run
(`harness/repro`, `traces/repro-stale-tree-reelection-1.ndjson`).
**Model**: `ServerShutdown`, `CastVote`, `WinElection`, `SyncWithLeader`.  **Properties**: U4,
U1, U2.  **Hunt**: `Update-hunt-reelection.cfg`.

### Scenario U-3: UPTODATE path after early logging
**Mechanism**: after UPTODATE the learner only starts serving, logs packets buffered after
NEWLEADER and commits all buffered zxids (Learner.java:762-786).  **Model**:
`LearnerUptodateStartServing/LogOne/CommitOne`, `LearnerEnterBroadcast`, `ApplyOne`.
**Properties**: `ServingApplyRequiresCommitCertificate`, `SyncCompletionJustified`,
`CommittedHistoriesPrefix`.  **Canary**: `Update-hunt-uptodate.cfg`.

### Scenario U-4: restart path covered by the new test
DIFFSyncConsistencyTest restarts every follower process; `Restore` replays the logged txn
(new behaviour).  **Model**: `Crash`, `Restart`, elections.  Expected to satisfy U1 when no
in-process re-election occurs (validated trace `diff-sync`, U1 holds along it).

## Update properties (`spec/Update.tla`)
| ID | Property | Kind | Scenario |
|---|---|---|---|
| U1 | `LeaderCompleteness` | new safety (consequence) | U-1, U-2, U-4 |
| U2 | `CommittedAgreesWithQuorumHistory` | interaction safety | U-2 |
| U3 | `NewLeaderAckImpliesDurable` | update intent (Learner.java:747 comment) | U-1 |
| U4 | `AckedHistoryRetained` | interaction via FLE/FOLLOWERINFO consumer | U-1, U-2 |
| — | `UpdateStructural` | structural | all |

## Defect ledger (incremental)
| ID | Description | Verification | Status |
|---|---|---|---|
| MC-1 | NEWLEADER ACK precedes learner fsync; a crash after the ACK loses a txn the new leader served (U-1) | MC + trace | see `spec/bug-report.md` |
| MC-2 | Skipped shutdown in INITIAL leaves a stale DataTree; in-process re-election loses the served txn (U-2) | MC + trace + real reproduction (new and old) | see `spec/bug-report.md` |
| MC-3 | TRUNC to a zxid absent from the learner log keeps the next entry (FileTxnLog.truncate); learner serves an uncommitted txn (update-independent) | MC | see `spec/bug-report.md` |
| CR-1 | Per-txn ACKs from the SendAckRequestProcessor started at NEWLEADER can precede the NEWLEADER ACK; LearnerHandler reads the first ACK as the NEWLEADER ACK and Leader.waitForNewLeaderAck ignores a mismatched zxid → leader may miss the quorum (availability only) | CR | not model-checked (FIFO channel not modeled); not observed in fresh traces |

## Exclusions (unchanged unless noted)
Observers (`ObserverZooKeeperServer` path of the change is not logged at NEWLEADER), dynamic
reconfiguration, sessions/digests/payload semantics, metrics/JMX, socket timeouts as timing
(modelled as nondeterministic role exits), FIFO ordering of the learner channel (CR-1).

---

# Prior V0 modeling brief (exact-old baseline, retained)

## Specula V0 modeling brief: ZooKeeper Zab exact-old prior

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

