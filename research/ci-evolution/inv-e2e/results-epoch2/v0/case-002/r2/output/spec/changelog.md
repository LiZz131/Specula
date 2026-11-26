# Changelog — incremental run incr-13b3a238967b (updated source 2efbdfc)

The prior V0 changelog is preserved verbatim in `changelog-v0.md`.

## Generation (Chapter 1-5) — MODEL_CHANGE_REQUIRED

Source-driven (the update):
- [update] `LearnerNewLeader` (new Action): NEWLEADER persists the snapshot
  (SNAP/TRUNC) and currentEpoch, starts the learner pipeline (INITIAL), and
  *enqueues* the buffered proposals (pendingTxns + SyncRequestProcessor queue)
  before the NEWLEADER ACK; the buffer is cleared.
- [update] `LearnerAckNewLeader` (new Action): the NEWLEADER ACK is a separate
  learner-thread step; FsyncOne of an enqueued entry may write ACK(zxid) on
  the same stream first.
- [update] `LearnerUpToDate` (new Action): UPTODATE ACK, startServing
  (RUNNING), logs only post-NEWLEADER buffered proposals, commits deferred
  zxids (fold of FollowerZooKeeperServer.commit incl. its exit branch).
- [update] `RoleExit`: a learner that leaves while INITIAL is not shut down
  (`canShutdown()` false): no drain; its leaked SyncThread keeps forcing.
- [update] Update.tla, Update-*.cfg created.

Repairs of prior-model defects (independent of the source-delta label; see
`../update-analysis.md` "Prior-model defects"):
- [repair] `CompleteSync` (atomic install of the leader's durable history at the
  learner) replaced by the stream-driven learner steps above plus
  `LeaderSyncFollower`/`LeaderSendNewLeader`/`LearnerReadMode`/
  `LearnerSyncProposal`/`LearnerSyncCommit`.
- [repair] `LeaderBroadcast` now requires a NEWLEADER-ACK quorum
  (`LeaderReadNewLeaderAck`), not learners in BROADCAST; UPTODATE is sent only
  after the leader started (`LeaderSendUpToDate`).
- [repair] Learners can synchronize with an established leader (removed the
  `phase[leader] = "sync"` guard; FLE out-of-election join path in `ElectFollow`).
- [repair] Removed `QueueLearnerProposal`/`ObserveCommit` (follower-invented
  transactions) and `messages`/`DropMessage`; leader<->learner traffic is two
  FIFO TCP streams per learner; connection loss is a role exit.
- [repair] `HistoryAtLeast` compares (currentEpoch, zxid) instead of length.
- [repair] Election/discovery follows the code: `ElectLeader`/`ElectFollow`,
  `LeaderProposeEpoch` (getEpochToPropose), counted/uncounted `AcceptEpoch`,
  `FinishDiscovery` (epoch quorum); `leadersByEpoch` is now a ghost of
  established epochs, so `ElectionSafety` is no longer vacuous.
- [repair] `OneActiveLeaderPerEpoch` revised to established leaders
  (two leaders may concurrently *propose* an epoch in DISCOVERY).
- [new-prop] `CommittedAgreement` (ghost `globalCommitted`): no two different
  entries ever committed at one position (crash resets volatile views, so the
  current-view `CommittedHistoriesPrefix` alone cannot see lost commits).
- [repair] MC bounds: `Txn = {t1, t2}` (one transaction cannot express
  divergent histories); fault counters: crash, abandon.
- [repair] Trace.tla rewritten to fire reference Actions (the prior Trace
  rebuilt state from events without calling base Actions).
- Generation preflight: SANY clean for base/MC/Update/Trace; the VAV tool could
  not parse tuple-valued operators (tool limitation; TLC reports unassigned
  variables at run time instead).

## Round 1 - Trace Validation (fresh new-version traces)

- [fix-trace] Trace.cfg/Trace.tla: `TraceMatched` uses the existential
  queue-based completion property; the prior `<>(l > Len)` is universal over the
  silent-vote / follower-choice branches and failed on dead branches.  A
  separate witness config (`Trace-witness.cfg`, invariant `TraceIncomplete`)
  records a full-consumption behavior for every trace.
- [fix-trace] Follower `CurrentEpochPersisted` inside NEWLEADER is captured
  before `setSyncMode(NONE)`; its mode field is compared with the pre-step mode.
- [fix-trace] Fixture SNAP packets certify the snapshot entries (the fixture
  leader's snapshot is committed state) (Trace: follower-snap.ndjson).
- [fix-spec] `LeaderSyncFollower`: the LearnerHandler syncs once
  `waitForEpochAck` returns (epoch-ACK quorum, `electingFinished`), before the
  leader thread's `setCurrentEpoch`/SYNCHRONIZATION (Trace:
  diff-sync-uncommitted.ndjson seq 14 vs 28/30; Leader.java:1442-1475).
- [fix-spec] `RoleExit` drains only RUNNING servers; INITIAL learners leak the
  SyncThread (Trace: diff-sync-uncommitted.ndjson seq 116-119, TxnDurable and
  AckSent after the role exit).  Quiescence guards (`queued = durable`) on
  `ElectLeader` and `LeaderSyncFollower` record the timing assumption.
- [fix-trace] Probe-ordering races handled by bounded early firing:
  NEWLEADER ACK read before its write probe (seq 35/36), UPTODATE queued before
  the leader's BROADCAST probe (seq 37/38), commit probes inside `processAck`
  before the ACK probe (quorum seq 47/49; abandon seq 86/87).
- [fix] `ModelSymmetry` moved from base.tla to MC.tla (TLC pre-evaluated
  `Permutations(Txn)` over the trace's transaction set).

## Round 1 - Model Checking (update campaign)

- [fix-rely] Update.tla `EnvJoin`: frame on the ghost `rollbackAuthorized`
  (real steps reset it); discharge r1 counterexample
  `output/update-discharge-bfs-r1-frame-mismatch.log`.  Reference unchanged.
- [refactor] Update properties moved to `UpdateProps.tla` (shared by Update.tla
  and the trace oracle `TraceOracle.tla`); no semantic change.
- [bug] LearnerNewLeader/LearnerAckNewLeader/LeaderBroadcast: MC-1
  `CommittedQuorumDurable` (focused 10 states, open 10 states, seeded full
  MCNext, and the reference behavior replaying `diff-sync-uncommitted`).
- [bug] LearnerNewLeader/FsyncOne/LeaderReadNewLeaderAck: MC-2
  `NewLeaderAckFirst` (focused 10 states; full MCNext simulation 58 and 61 states).
- [bug] LearnerNewLeader/LearnerSyncCommit: MC-3 `SyncCommitHasPendingProposal`
  (full MCNext simulation 60 states; focused BFS).
- No Case A/B counterexample remained; no reference Action was changed after
  the trace-validation gate (the final 7-trace regression ran on the final
  base/Trace artifacts).

## Result

Converged in one validation round (Trace repairs + one reference repair batch
before the model-checking gate) and one model-checking round (rely frame fix
only).  Bug hunting: 3 model-checking bugs (MC-1..MC-3) plus 2 code-review
findings (CR-4, CR-5), all reproduced on the updated implementation; old-tree
controls: MC-1 also fails (pre-existing), MC-2, MC-3, CR-4, CR-5 pass
(introduced by the update).  All exploration budget-limited; see
`model-checking-campaign.md`.
