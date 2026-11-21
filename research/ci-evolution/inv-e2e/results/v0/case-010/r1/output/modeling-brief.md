# Modeling Brief — ZooKeeper Zab V0 (exact-old baseline)

## 1. System Overview

- **System**: Apache ZooKeeper 3.7.0-SNAPSHOT exact-old source, Java; 13,771 lines in the twelve priority files.
- **Category**: Category A (distributed/message-passing). Quorum peers exchange election and Zab packets, persist epochs/logs/snapshots, and schedule connection, sync, commit, apply, and snapshot work independently.
- **Protocol surface**: crash-fault leader election, Zab discovery, DIFF/TRUNC/SNAP synchronization, ordered proposal broadcast, quorum commitment, and recovery.
- **Concurrency**: the peer main thread owns role loops, but election send/receive workers, one learner handler and sender per connection, sync processors, commit workers, and snapshot threads interleave (`QuorumPeer.java:1344-1497`; `LearnerHandler.java:325-375,457-753`; `SyncRequestProcessor.java:155-250`; `CommitProcessor.java:197-420`).
- **Input constraint**: this brief uses only `/work/source` and `/work/scope.md`. The single neutral commit has no usable archaeology; external history, issues, papers, later trees, and remembered incident labels were not consulted.

## 2. Scenarios

### Scenario 1: Election and durable epoch stair-steps

**Mechanism**: Election evidence, accepted epoch, current epoch, and phase changes occur at distinct messaging and durable-file boundaries.

**Evidence**:

- Election preference orders peer epoch, zxid, then server id; completion requires an intersecting configured quorum (`FastLeaderElection.java:722-777,1012-1088`).
- The leader collects reported accepted epochs, durably advances accepted epoch, checks follower state summaries, then durably advances current epoch (`Leader.java:1391-1471,657-660`).
- A learner persists accepted epoch before ACKEPOCH and current epoch before its NEWLEADER ACK (`Learner.java:483-526,726-760`).
- The two epoch values use separate atomic files (`QuorumPeer.java:2140-2173`).

**Affected paths**: `FastLeaderElection.lookForLeader`, `Leader.getEpochToPropose`, `Leader.waitForEpochAck`, `Learner.registerWithLeader`, `QuorumPeer.setAcceptedEpoch`, `QuorumPeer.setCurrentEpoch`.

**Suggested modeling approach**:

- Variables: `electionVotes`, `electedLeader`, `acceptedEpoch`, `currentEpoch`, `phase`, `leaderOf`, `newLeaderAckSet`.
- Actions: split election finish, accepted-epoch persistence, ACKEPOCH collection, current-epoch persistence, NEWLEADER quorum, and broadcast entry.
- Crash retains published epoch values but loses election and connection state.

**Priority**: High. Epoch and history consistency spans multiple durable/message boundaries and is well suited to finite-state interleaving.

### Scenario 2: Synchronization selection and forwarding cut

**Mechanism**: DIFF, TRUNC, and SNAP choose different recovery transforms; the leader establishes a forwarding cut before transfer completes, so new proposals may queue concurrently.

**Evidence**:

- `syncFollower` selects empty DIFF, TRUNC, committed-log DIFF, on-disk-log DIFF, or SNAP from explicit zxid-range conditions (`LearnerHandler.java:775-932,946-1036`).
- Mode selection, catch-up queue construction, and `startForwarding` hold the committed-log read lock; packet transmission occurs later on a sender thread (`LearnerHandler.java:791-923,325-375`).
- `startForwarding` queues committed-but-not-applied and outstanding proposals before registering the follower (`Leader.java:1289-1321`).
- SNAP replaces the learner database; TRUNC clears, cuts, reopens, and reloads; DIFF queues subsequent log work (`Learner.java:553-668`; `ZKDatabase.java:599-610`).
- NEWLEADER ACK and UPTODATE do not join all asynchronously queued persistence/application work (`Learner.java:726-785`).

**Affected paths**: `LearnerHandler.syncFollower`, `LearnerHandler.queueCommittedProposals`, `Leader.startForwarding`, `Learner.syncWithLeader`, `Follower.followLeader`.

**Suggested modeling approach**:

- Variables: `syncMode`, `syncComplete`, `newLeaderAcks`, and the separate `prepared`, `durable`, `committed`, and `applied` histories.
- Actions: `ChooseSyncMode`, proposal/commit/flush events observed during DIFF, `CompleteLearnerSync`, `FormNewLeaderQuorum`, and `SetZabState(BROADCAST)` remain separate.
- DIFF advances through the ordinary per-transaction pipeline and can commit before its local flush drains; TRUNC and SNAP perform source-authorized state replacement at the observed sync-completion boundary.

**Priority**: High. It is the principal bridge between recovered accepted histories and safe serving state.

### Scenario 3: Proposal, flush, ACK, commit, and apply pipeline

**Mechanism**: Proposal broadcast, local queueing, buffered append, fsync/flush, normal ACK, global commit, and local apply are independently scheduled.

**Evidence**:

- A leader queues a proposal before sending the request to its sync processor (`ProposalRequestProcessor.java:68-90`; `Leader.java:1215-1256`).
- `SyncRequestProcessor` separates queue, append, batched commit, and downstream ACK callback (`SyncRequestProcessor.java:72-85,155-250,273-278`).
- Normal self/follower ACKs are downstream of log commit (`AckRequestProcessor.java:40-48`; `SendAckRequestProcessor.java:40-63`).
- The leader commits only an in-order proposal with all required quorum ACK sets, then separately queues local application (`Leader.java:890-962,974-1041`).
- A follower matches COMMIT against the pending head, then its commit processor and final processor apply later (`FollowerZooKeeperServer.java:80-110`; `CommitProcessor.java:288-412`; `FinalRequestProcessor.java:111-160`).

**Affected paths**: `ProposalRequestProcessor.processRequest`, `Leader.propose`, `SyncRequestProcessor.run/flush`, `Leader.processAck/tryToCommit`, `FollowerZooKeeperServer.logRequest/commit`, `FinalRequestProcessor.applyRequest`.

**Suggested modeling approach**:

- Variables: `prepared`, `syncQueued`, `durable`, `pending`, `acks`, `durabilityEvidence`, `globalCommitted`, `committed`, `applied`.
- Actions: one action per source boundary named above.
- Application requires a global commit certificate backed by a durable quorum. It does not require that the applying slow follower itself has already flushed; the source permits COMMIT and sync threads to race.

**Priority**: High. This is the smallest faithful abstraction for the requested persistence and request-processing ordering.

### Scenario 4: Snapshot, shutdown, restart, and reconciliation

**Mechanism**: Snapshots and WALs retain different frontiers; restart replays durable accepted entries before election, while later synchronization may explicitly truncate or replace them.

**Evidence**:

- Periodic snapshots run on an independent thread after log roll (`SyncRequestProcessor.java:180-201`).
- Snapshot filename zxid is sampled before serialization; failure may leave an invalid file that recovery skips (`FileTxnSnapLog.java:464-493`; `FileSnap.java:68-119`).
- Recovery loads the latest valid snapshot then replays complete WAL records and rebuilds the in-memory synchronization cache (`FileTxnSnapLog.java:243-368`; `ZKDatabase.java:272-341`).
- A WAL record is accepted history, not itself a global commit certificate.
- Graceful shutdown drains the sync thread and flushes pending work; abrupt crash need not (`SyncRequestProcessor.java:254-270`; `ZooKeeperServer.java:803-850`).

**Affected paths**: `ZooKeeperServer.takeSnapshot`, `FileTxnSnapLog.save/restore`, `ZKDatabase.loadDataBase/truncateLog`, `QuorumPeer.loadDataBase/shutdown`.

**Suggested modeling approach**:

- Variables: `snapshotPublished`, `snapshotImage`, `snapshotBusy`, `durable`, `recoveryVisible`, `running`, `lastTransition`.
- Actions: `BeginSnapshot`, `FinishSnapshot`, `GracefulShutdown`, `Crash`, `RestartLoadDatabase`, and source-authorized sync replacement/truncation.
- The modeled `applied` history means client-visible broadcast state; non-serving recovery replay is represented separately.

**Priority**: High. It tests the requested recovery semantics without treating every durable record as committed.

## 3. Modeling Recommendations

### 3.1 Model

| What | Why | How |
|---|---|---|
| Fixed three-participant majority | All selected baseline tests use a stable participant set | `Server={s0,s1,s2}`, `Quorum(Q) == 2*Cardinality(Q)>3` |
| Roles and Zab phases | Role and phase are independent source fields | Per-server `role`, `phase`, `leaderOf`, `running` |
| Accepted/current epoch split | Separate files and protocol milestones | Separate variables and actions |
| DIFF/TRUNC/SNAP | Each transforms recovered history differently | Explicit mode and sync actions |
| Queue/flush/ACK/commit/apply | Independent threads expose ordering | Separate per-transaction transitions |
| Global durability certificate | Local durability is not required at every applying follower | Retained `durabilityEvidence` plus commit witness |
| Graceful shutdown and abrupt crash | Only graceful shutdown drains queues | Two fault actions |
| Snapshot begin/finish | Snapshot serialization interleaves with later work | In-flight image then publication |

### 3.2 Do Not Model

| What | Rationale |
|---|---|
| Serialization bytes, TCP framing, metrics, logging, JMX, authentication, allocation, numeric widths | Explicitly excluded by `/work/scope.md`; no modeled transition depends on them |
| Observers | They do not vote; the required baseline safety questions are covered by participants |
| Dynamic membership/reconfiguration | The fresh baseline harness uses one immutable three-participant view. Current and pending quorum logic is documented but left for an incremental extension. |
| Session lifecycle and read concurrency | The harness filters to create/setData mutations; these details do not change Zab ordering at this abstraction |
| Torn bytes and silent disk corruption | Complete durable records are the persistence atom; these faults are outside the stated crash model |
| Known-incident reproduction tests | This is a neutral prior. Existing tests were used only to learn normal source semantics. |

## 4. Proposed Extensions

| Extension | Variables | Purpose | Scenario |
|---|---|---|---|
| Epoch stair-step | `acceptedEpoch`, `currentEpoch`, `epochAcks` | Preserve separate durable milestones | 1 |
| Sync plan | `syncMode`, `syncComplete`, per-server histories | Justify transition to broadcast and preserve DIFF versus replacement boundaries | 2 |
| Persistence pipeline | `prepared`, `syncQueued`, `durable`, `acks` | Preserve queue/flush/ACK atomicity | 3 |
| Commit certificate | `durabilityEvidence`, `commitWitness`, `globallyCommitted` | Express quorum-backed durability | 3 |
| Recovery state | `recoveryVisible`, `snapshotPublished`, `snapshotImage`, `snapshotBusy` | Separate accepted WAL from serving commit state | 4 |

## 5. Proposed Invariants

| Invariant | Type | Description | Targets |
|---|---|---|---|
| `TypeOK` | Safety | All records, functions, modes, epochs, and histories are well typed | Baseline |
| `ActiveLeaderUniqueness` | Safety | At most one running LEADING peer broadcasts in a current epoch | 1 |
| `AcceptedEpochGECurrentEpoch` | Safety | A peer never has accepted epoch below current epoch | 1 |
| `CommittedPrefixAgreement` | Safety | Per-server committed histories agree on common prefixes | 2, 3, 4 |
| `NormalAckHasDurabilityEvidence` | Safety | Every normal ACK records a completed persistence boundary | 3 |
| `ApplyHasCommitCertificate` | Safety | Client-visible apply is globally committed with a quorum durability witness | 3 |
| `OrderedHistories` | Safety | All modeled transaction histories preserve global zxid order | 2, 3, 4 |
| `SyncEntryJustified` | Safety | A broadcasting follower completed a selected leader sync | 2, 4 |
| `MonotoneUnlessRecovery` | Safety/action | Durable, commit, and apply frontiers only retract on explicit recovery/TRUNC/SNAP actions | 2, 4 |
| `SnapshotPublishedValid` | Safety | A published snapshot originated from a begun snapshot image | 4 |

## 6. Findings Pending Verification

### 6.1 Model-Checkable

| ID | Forward-looking question | Expected oracle | Scenario |
|---|---|---|---|
| MC-EPOCH | Can a crash between accepted/current epoch publications permit conflicting active leaders or an epoch/history mismatch? | `ActiveLeaderUniqueness`, `AcceptedEpochGECurrentEpoch` | 1 |
| MC-SYNC | Can a follower enter broadcast without a history justified by its DIFF/TRUNC/SNAP exchange when live proposals interleave? | `SyncEntryJustified`, `CommittedPrefixAgreement` | 2 |
| MC-PIPE | Can independently scheduled queue/flush/ACK/commit/apply steps create an apply lacking a durable quorum certificate? | `NormalAckHasDurabilityEvidence`, `ApplyHasCommitCertificate` | 3 |
| MC-RECOVERY | Can restart replay plus explicit synchronization expose a formerly accepted but uncommitted suffix in broadcast state? | `CommittedPrefixAgreement`, `ApplyHasCommitCertificate` | 4 |

### 6.2 Test-Verifiable

| ID | Question | Suggested test |
|---|---|---|
| TV-1 | Do fresh startup, client mutation, full restart, lagging-follower restart, and recovery retain the expected committed values? | Instrumented `SpeculaTraceScenarioTest` |
| TV-2 | Are every emitted event and field consumed by `Trace.tla`? | NDJSON schema/event inventory plus TLC replay |

### 6.3 Code-Review-Only

| ID | Observation | Suggested action |
|---|---|---|
| CR-1 | `forceSync=no` weakens the physical durability interpretation of normal ACKs (`FileTxnLog.java:371-405`). | State `forceSync=yes` as the baseline durability assumption; parameterize in a later extension if needed. |
| CR-2 | The in-memory name `committedLog` includes every replayed durable WAL record (`ZKDatabase.java:272-341`). | Keep terminology distinct in specs and reviews; do not infer a quorum certificate from the field name. |

## 7. Reference Pointers

- Full evidence map: `analysis-report.md`.
- Priority exact-old files: `Leader.java`, `Learner.java`, `LearnerHandler.java`, `Follower.java`, `FollowerZooKeeperServer.java`, `QuorumPeer.java`, `ZooKeeperServer.java`, `ZKDatabase.java`, `SyncRequestProcessor.java`, `FileTxnSnapLog.java`.
- Source-derived tests: `Zab1_0Test.java:510-865`; `QuorumPeerMainTest.java:75-127`; harness `SpeculaTraceScenarioTest`.
- No external reference algorithm or upstream material was used.

---

## 8. Incremental update (neutral commits `baseline` f8533cd -> `update` b16ba71)

### 8.1 Source delta and disposition

| File | Change |
|---|---|
| `Learner.java:861-865` (`shutdown`) | `zk.shutdown()` became `zk.shutdown(self.getSyncMode().equals(QuorumPeer.SyncMode.SNAP))` |
| `ZooKeeperServer.java:803-810` (`shutdown(boolean)`) | when `!canShutdown()` and `fullyShutDown`, `zkDb.clear()` before the early return |
| `QuorumPeerMainTest.java` | new `testDiffSyncAfterSnap` (forced SNAP, exception right after reading NEWLEADER, rejoin, restart, read every node) |

**Disposition: `MODEL_CHANGE_REQUIRED`.** `Learner.shutdown` runs whenever a follower leaves `followLeader` (`QuorumPeer.java:1468-1479`) and from `QuorumPeer.shutdown` (`:1544-1546`). Before the update a learner that had replaced its data tree with the leader's SNAP image (`Learner.java:565-586`) but had not yet reached the NEWLEADER snapshot (`:739-741`) kept that non-durable image: its server is not RUNNING, so `shutdown(false)` returned early (`ZooKeeperServer.java:784-786,808-809`). The next `getLastLoggedZxid` (`QuorumPeer.java:1257-1262`) — read by the election vote (`FastLeaderElection.java:867-875,942`) and by FOLLOWERINFO/ACKEPOCH (`Learner.java:487,524`) — therefore reported the image's zxid. After the update the ZKDatabase is cleared and reloaded from disk on that next read. Projected onto the model vocabulary the post-state of a learner exit with `syncMode = SNAP` changes (reported history: leader image -> durable history), so the old/new post-state sets differ. `syncMode` is already a modeled variable; the V0 model had no in-memory/durable split, no learner-exit action, and an atomic `CompleteLearnerSync`, so it could not express either branch.

### 8.2 Model granularity chosen

- `memDb`/`memInit` (ZKDatabase data tree / `initialized`) separate from `durable` (snapshot + txn log). `LastLoggedHist(s)` is what the peer reports.
- `Learner.syncWithLeader` split at its packet/persistence boundaries: `ChooseSyncMode` (leader decision + first packet), `LearnerApplySnapshot`, `LearnerTruncateLog`, `LearnerSyncPacket` (PROPOSAL buffered), `LearnerSyncCommit` (in-memory `processTxn` for SNAP/TRUNC before NEWLEADER, `packetsCommitted` otherwise), `LearnerSyncSnapshot`, `LearnerPersistCurrentEpoch`, `LearnerNewLeaderModeNone`, NEWLEADER logging, `LearnerAckNewLeader`, `LearnerUpToDate`, `CompleteLearnerSync`.
- `LearnerShutdown` carries the updated branch (constant `UpdateFullShutdownOnSnap`; `FALSE` only in differential controls), `FollowerExitToLooking`, `EnterElectionPhase`, `ReloadDatabase`, `LeaderShutdown`.
- Late joiners sync with an established leader; elections use FLE's vote rule (candidate at least as up to date as the voter, by currentEpoch then reported zxid) and the out-of-election join rule.
- Transaction ids are global in proposal order (= zxid order); histories may skip ids, which represents divergent earlier-epoch proposals and makes TRUNC meaningful.

### 8.3 Update Scenarios

**U1 — SNAP-window learner exit (directly changed).** old producer `ChooseSyncMode(SNAP)`/`LearnerApplySnapshot` (and in-memory COMMITs) -> changed `LearnerShutdown` -> old consumers `ReloadDatabase`, `CastVote`/`FinishElection`, re-registration and the leader's DIFF choice, DIFF NEWLEADER without snapshot, later broadcast logging and restart. Expected (source): after the exit the peer reports only disk history; a rejoin then receives the missing transactions; no committed hole on disk. Real execution: `testDiffSyncAfterSnap` (fresh trace `snap-abort-rejoin-v3`). Properties: `ReportedHistoryDurable`, `SnapExitReportsDisk`, `DurableHistoryConsistent`.

**U2 — TRUNC-window learner exit (sibling branch the update does not cover).** TRUNC also keeps `snapshotNeeded = true` (`Learner.java:555,587-598`), so `writeToTxnLog` is false and a COMMIT read before NEWLEADER is applied only in memory (`:656-665`); the update's condition is `syncMode == SNAP` only (`:864`), so a TRUNC-mode exit keeps the in-memory transaction. TRUNC followed by forwarded PROPOSAL/COMMIT before NEWLEADER is produced by `LearnerHandler.syncFollower` case "peer newer than maxCommittedLog" (`LearnerHandler.java:854-863`) plus `Leader.startForwarding` (`Leader.java:1289-1322`, toBeApplied entries carry COMMIT; later commits are forwarded to the already registered handler). Uncertainty: reachability within bounds and whether the retained transaction can become a durable hole. Properties: `ReportedHistoryDurable`, `DurableHistoryConsistent`.

**U3 — DIFF learner exit between NEWLEADER and UPTODATE (adjacent unchanged path).** DIFF NEWLEADER logs buffered proposals without applying them (`Learner.java:752-757`); an exit before UPTODATE leaves the database under-reporting its own log (`shutdown(false)` early return). Checked to see whether the update's interaction with re-registration also needs this branch.

### 8.4 Update properties and placement

| Property | Kind | Location |
|---|---|---|
| `ReportedHistoryDurable` | new interaction property (exit -> election/registration consumers) | `Update.tla` |
| `SnapExitReportsDisk` | new property of the updated branch observed by its first reader | `Update.tla` |
| `DurableHistoryConsistent` | new general recovery property (no committed hole / no uncommitted record below a committed one on disk) | `base.tla` |
| `LeaderCompleteness` | new general Zab property | `base.tla` |
| `OrderedHistories` | revised (ordered, not dense prefixes) | `base.tla` |
| `LeaderUniquenessPerEpoch` | revised from `ActiveLeaderUniqueness` (Case A, see changelog) | `base.tla` |
| `SyncEntryJustified`, `MonotoneUnlessRecovery` | revised for exit windows / explicit SNAP-TRUNC replacement | `base.tla` |

### 8.5 Exclusions retained / added

Observers, ObserverMaster, reconfiguration (`COMMITANDACTIVATE`, `INFORMANDACTIVATE`), pre-Zab-1.0 UPTODATE snapshot path, same-epoch TRUNC inside `queueCommittedProposals` (needs equal-epoch divergence that one-leader-per-epoch excludes), `isMoreRecentThan` ACKEPOCH rejection, session transactions, digest checks. A deposed leader is not modeled proposing during its quorum-check window (keeps id order = zxid order); its proposals could never commit.

### 8.6 Code-review Scenarios (no counterexample required)

| ID | Observation | Status |
|---|---|---|
| CR-U1 | `syncMode` is never reset by `Learner.shutdown`; a stale `SNAP` makes a later exit that fails before the first sync packet fully clear (and reload) a database that is already disk-consistent. | Performance only; no safety consequence found. |
| CR-U2 | U2 above (TRUNC sibling). | Model checking produced an actual counterexample on the updated source: **MC-1** (`spec/bug-report.md`, `spec/findings.json`); no longer code-review-only. |

### 8.7 Model-checking outcome for the update Scenarios

- U1 (changed SNAP branch): the updated exit discards the SNAP image; the steered SNAP/DIFF-only schedule (`Update-hunt-snap-only-steered*.cfg`) is the check of the changed branch itself; the exact-old controls violate `ReportedHistoryDurable` (depth 39) and `DurableHistoryConsistent` (depth 55), so both properties detect the defect class the update repairs.
- U2 (TRUNC sibling): **MC-1** — a TRUNC-mode exit after an in-memory COMMIT keeps a non-durable record and later leaves a committed hole on disk; reached without any crash (learner ahead of the leader's applied frontier).
- U3 (DIFF exit after NEWLEADER): see `spec/output/final-update-hunt-diffwindow-steered2-bfs.log` and canary results in `spec/output/verification-summary.md`.
