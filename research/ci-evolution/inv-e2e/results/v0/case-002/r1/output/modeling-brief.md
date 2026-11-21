# Specula modeling brief — incremental update (case-002)

Current source: `artifact/` commit `update` (2efbdfc3754d), parent `baseline` (1414ebfb1d16).
Changed files: `ZooKeeperServer.java`, `quorum/Learner.java`, new test
`DIFFSyncConsistencyTest.java`. Category A (distributed, message passing) is unchanged.
Prior suite: `/work/previous/.specula-output` (V0, exact-old). The V0 brief follows below
unchanged as historical context; §U supersedes it where they differ.

## U.1 Decision gate (Chapter 1)

**Disposition: MODEL_CHANGE_REQUIRED.** Projection of every changed branch onto the V0
vocabulary changes modeled post-states:

| Changed branch (new code) | Old behaviour | Projected difference |
|---|---|---|
| NEWLEADER: `setSyncMode(NONE)`, `zk.startupWithoutServing()` (Learner.java:749-751) | done after UPTODATE with `zk.startup()` | `syncMode` cleared and request processors (SyncRequestProcessor/SendAck/Commit) running before the NEWLEADER ACK; new server state INITIAL |
| NEWLEADER: `logRequest` for every `packetsNotCommitted` entry, then `clear()` (752-758) | logged after UPTODATE | `queued` grows before the ACK; durability still asynchronous (FollowerZooKeeperServer.logRequest only enqueues) |
| NEWLEADER ACK (759-760) | same packet, earlier relative to logging | ACK message now follows queueing, still precedes fsync |
| COMMIT handler (unchanged code, 648-676) consumes `packetsNotCommitted.peekFirst()` | buffer never cleared before UPTODATE | after NEWLEADER the buffer may be empty -> `pif.hdr` NullPointerException |
| UPTODATE: `zk.startServing()` (762-765) | `zk.startup()` | INITIAL -> RUNNING only; post-loop logging covers only post-NEWLEADER proposals |
| `ZooKeeperServer.startupWithServerState(INITIAL)` + `canShutdown()` (unchanged) | INITIAL never had processors | shutdown from INITIAL is a no-op: no drain/flush, no `fastForwardDataBase`; leaked SyncRequestProcessor keeps flushing |

V0 also mis-modelled the mechanism the update touches (atomic `CompleteSync` that made the
learner's history durable before NEWLEADER ACK, leader establishment requiring followers in
BROADCAST, no late join, election on log length rather than tree position). These are
recorded separately as model repairs in `spec/changelog.md`.

## U.2 Update Scenarios

### Scenario U-NPE: COMMIT of a pre-NEWLEADER proposal arrives after NEWLEADER
**Mechanism**: `Leader.startForwarding` (Leader.java:1294-1330) queues outstanding proposals
before `LearnerHandler` queues NEWLEADER (LearnerHandler.java:591-601); the COMMIT for such a
proposal is forwarded later if the quorum forms after NEWLEADER was queued. The update clears
`packetsNotCommitted` at NEWLEADER; the unchanged COMMIT handler dereferences
`packetsNotCommitted.peekFirst()` without a null check.
**Path**: old producer (startForwarding) -> affected (NEWLEADER clear) -> old consumer (COMMIT).
**Model**: `SelectSync` (Outstanding), `LeaderQueueNewLeader`, `Commit` (stream routing),
`LearnerLogPending`, `LearnerAckNewLeader`, `LearnerCommit` NPE branch -> `syncError`.
**Property**: `Update!NoSyncException`. Canary `NotCommitAfterNewLeaderReached`.
**Trace**: `traces/update-commit-after-newleader.ndjson` (real NullPointerException).

### Scenario U-DUR: NEWLEADER ACK before the synchronised history is durable
**Mechanism**: the update's comment states the intent "make sure sync the uncommitted logs
before commit them (ACK NEWLEADER)", but `logRequest` only enqueues to SyncRequestProcessor;
`writePacket(ACK)` does not wait for `ZKDatabase.commit()` (fsync). The leader counts the ACK
in `waitForNewLeaderAck` and serves its history as committed.
**Property**: `Update!NewLeaderAckDurable` (action property at the ACK step).
**Trace**: `traces/follower-diff.ndjson`, `traces/update-newleader-ack-durability.ndjson`.

### Scenario U-EPOCH: persisted current epoch ahead of the recoverable/voting history
**Mechanism**: `setCurrentEpoch(newEpoch)` is forced before the DIFF entries are durable
(crash case), and an exception between NEWLEADER and UPTODATE leaves the server in INITIAL,
whose shutdown does not fast-forward the tree, so `getLastLoggedZxid()` (FLE vote) reports the
pre-sync position with the new epoch (non-crash case). FLE prefers the higher epoch.
**Property**: `Update!EpochHistoryRecoverable`.
**Trace**: `traces/update-diff-sync-consistency.ndjson` events 94-110 (tree stays 0x100000001
after SocketTimeoutException while the log later holds 0x100000002; that server then wins).

### Scenario U-LOSS: consequence through re-election
**Path**: changed NEWLEADER window -> crash or INITIAL exit -> election by epoch ->
TRUNC/missing history at the new leader.
**Properties**: `Update!LeaderCompleteness`, `Update!CommittedNeverLost`.

## U.3 Modeling recommendations (applied)

Keep fixed membership/majority; one or two transactions; packet-level learner stream;
explicit INITIAL/RUNNING server state; tree (`recovered`/`applied`) distinct from log.
Do not model: observers, reconfiguration (COMMITANDACTIVATE/INFORMANDACTIVATE), Zab pre-1.0
(`isPreZAB1_0`), sockets/timeouts beyond session loss, snapshot fsync flag for TRUNC,
the ACK-ordering race between SendAckRequestProcessor and the NEWLEADER ACK (liveness only),
and the duplicate log records produced when a leaked SyncRequestProcessor and a new session
log the same zxid (modeled idempotently by `LogAppend`).

## U.4 Code-review-only candidates

| ID | Description | Evidence |
|---|---|---|
| CR-1 | Shutdown from the new INITIAL state is a no-op (`canShutdown()`), leaking the started SyncRequestProcessor/CommitProcessor threads and skipping `fastForwardDataBase` | ZooKeeperServer.java:784-805, LearnerZooKeeperServer.java:155-174; trace update-diff-sync-consistency (TxnDurable after LOOKING). **Folded into MC-3** once model checking produced an actual counterexample (`spec/confirmation-MC-3.md`); the thread leak itself is visible in reproduction logs (`NullPointerException ... this.learner.sock is null` from a leaked SendAckRequestProcessor). |

## U.5 Outcome
MC-1 (U-NPE) REPRODUCED; MC-2 (U-DUR/U-EPOCH, crash) ENV_LIMITED; MC-3 (U-LOSS/U-EPOCH, no crash)
REPRODUCED. See `spec/bug-report.md`, `spec/findings.json`, `spec/final-result.json`.

---

# (Prior) Specula V0 modeling brief: ZooKeeper Zab exact-old prior

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

