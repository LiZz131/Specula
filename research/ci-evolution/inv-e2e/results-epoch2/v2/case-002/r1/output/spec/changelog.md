# Validation repair changelog

## Round 1 - Trace Validation

- [fix] Trace selection: removed the hard-coded `follower-snap` scenario
  predicate so every trace record in the caller-selected NDJSON file is an
  obligation (audit failures: follower DIFF, quorum, and restart/recovery).
- [fix] Trace domain: generalized servers, epochs, and zxid counter values to
  cover all five retained exact-old traces without modifying trace data.
- [fix] State validation: added schema checks, post-state checks for all five
  captured peer fields, and event-specific zxid/pipeline checks for all 15
  instrumented event names.
- [fix] State-transition validation: replaced trace-fed common-field assignments
  with source-backed event gates. Accepted/current epoch, role, phase, and sync
  mode can now change only at their corresponding probes (including the nested
  election phase update in `setPeerState`), so post-state comparisons are not
  tautologies. Protocol leaders are recorded when accepted-epoch persistence
  binds the newly elected role to its Zab epoch.
- [fix] Trace abstraction: represented uninstrumented leader-side proposal and
  commit callbacks by the minimum implied common prefix, and treated snapshot
  installation as the explicit history-replacement boundary.

## Round 1 - Model Checking

- [fix-spec] `EnterSyncPhase`: required the follower's accepted epoch to equal
  the leader's persisted epoch, matching `Learner.registerWithLeader` before
  synchronization. This closes the Case-B counterexample in
  `base-canonical-repair.log` where an epoch-1 entry became durable at a
  follower whose accepted epoch was still 0.
- [fix-spec] `ReceiveProposal`/`ReceiveCommit`: required a broadcast learner's
  synchronized current epoch to match the packet epoch. This closes the
  round-3 stale-connection counterexample where a follower still synchronized
  to epoch 1 accepted an epoch-2 proposal from a re-elected server with the same
  identity.
- [fix-spec] `CompleteSync`: bound completion to equal accepted epochs at the
  learner and sync source. This closes the depth-24 counterexample where a
  pre-crash TRUNC session completed after the same leader identity restarted
  in a later epoch.
- [fix-spec] Canonical bounds retain three voters, two epochs, one transaction,
  and one bounded crash/drop/snapshot while permitting both canonical base and
  MC BFS to exhaust naturally. The broader prior run remains preserved as
  limited open-frontier evidence.
- [fix] Canonical exploration: enabled `Permutations(Server)` symmetry in base
  and MC configs. This quotients only voter renamings and leaves all three
  servers, behaviors, actions, and properties in scope.
- [fix] Canonical exploration: added an explicit TLC level-23 state constraint
  to base and MC. The bound exceeds the preserved depth-22 mutation/apply
  witness and retains crash/restart/re-election prefixes; only a natural
  zero-queue completion counts as canonical success.

## Result

Converged in one repair round. All five retained exact-old traces passed before
canonical checking. Canonical base BFS completed with 52,034,534 generated and
6,354,157 distinct states; canonical MC BFS completed with 171,870,841 generated
and 21,701,056 distinct states. Both reached depth 23, exited zero, reported no
violation, and left zero states on the queue. No bug-hunting finding was produced.
The older timeout/open-frontier logs remain preserved as limited evidence only.

---

# Incremental run case-002 (`baseline` -> `update`)

## Generation (MODEL_CHANGE_REQUIRED; analysis-report.md §U1-U4)

- [update] `CompleteSync` DIFF branch: buffers the leader history in `proposed`
  and persists nothing (Learner.java:561-565, 616-643). V0 copied `durable[l]`.
- [update] `ClearSyncMode`: now inside NEWLEADER after `setCurrentEpoch`, starts
  the learner processors in State.INITIAL (`zkState`), Learner.java:749-751.
- [update] new `LogSyncProposal` (logRequest of buffered packets; NEWLEADER window
  or after UPTODATE), `AckNewLeader` (Learner.java:760), `ReceiveUpToDate`
  (startServing, Learner.java:765-767); `EnterBroadcast` requires RUNNING.
- [repair] new `CountNewLeaderAck`; `LeaderBroadcast` waits for a NEWLEADER-ACK
  quorum instead of followers already in BROADCAST, commits/serves the leader's
  history (Leader.java:660-712, 1497-1535, 1547-1586).
- [repair] `EnterSyncPhase`/`SelectSync` accept a leader still in DISCOVERY (after
  the epoch-ACK quorum) or already BROADCAST; `FollowLeader` only from LOOKING.
- [repair] `ObserveCommit` requires an existing certificate; `QueueLearnerProposal`
  removed (no implementation path); `ReceiveProposal` buffers during sync and
  de-duplicates; `ReceiveCommit` during sync only after UPTODATE; `FsyncOne` of a
  learner without a leader connection forces without an ACK.
- [update] Update.tla, Update-*.cfg, invariant-evidence decisions (E1-E3, K1-K6).

## Validation round V1 - harness rebase

- [harness] prior patch applied except the `BroadcastReady`-after-`zk.startup()`
  hunk (source drift, `spec/output/harness-rebase-apply.log`); probe moved after
  `zk.startServing()`.
- [harness] new probes `NewLeaderAckSent`, `NewLeaderAckCounted`,
  `NewLeaderAckMismatch` (with `peer`), `PeerDatabaseLoaded`; `CommitDelivered`
  moved before the CommitProcessor hand-off and `NewLeaderAckSent` before the
  ACK write (serialization-race fixes, capture layer only).
- [scenario] new update scenario `DIFFSyncConsistencyTest#testInconsistentDueToUncommittedLog`
  (added by the update) and three repetitions of the DIFF fixture.

## Validation round V1 - trace validation

- [fix] Trace.tla rewritten as hybrid: update-window and SyncRequestProcessor/
  apply events replay base Actions with post-state checks; election/discovery and
  leader-side/broadcast pipeline events keep the V0 observed projection
  (inherited limitation; producers not instrumented).
- [fix] `ElectionWon` zxid is FLE's `proposedZxid` (winning vote), not the
  learner's own position (Trace: diff-sync-uncommitted-log, seq 58). Latent V0
  interpretation error.
- [fix-spec] (Case B, trace) `recovered` re-interpreted as the in-memory database
  history; votes (`HistoryAtLeast`), sync choice, leader summary and
  `LeaderBroadcast` read it; `BeginElection` drains+fast-forwards only a RUNNING
  server; `ApplyOne` advances it.  Evidence: diff-sync-uncommitted-log seq 98
  reports lastLoggedZxid (1,1) while the log holds (1,2) (INITIAL-state shutdown
  skipped, ZooKeeperServer.java:784-786, LearnerZooKeeperServer.java:155-159).
- [fix-spec] new `leaderSummaryEpoch` and `FollowerAhead` guard on `SelectSync`
  (Leader.java:1447-1454).
- [fix-spec] `ReceiveUpToDate` exposes the learner's in-memory database as its
  applied/committed prefix (Trace: leader-abandon-restart-recovery event 145,
  restart reload).  BroadcastReady check strengthened to the exact data-tree zxid.
- [fix] Trace.cfg no longer enables OneActiveLeaderPerEpoch (role LEADING precedes
  the new accepted epoch at trace granularity; kept in all MC cfgs).
- [result] all 8 fresh traces pass (`spec/output/trace/r4-*.log`).

## Round 1 - Model Checking (incremental campaigns)

- [mc] standard `MC.cfg` (pre-TRUNC/SNAP repair): 56,514,298 distinct states to the
  depth-30 bound, no violation, 6,141,983 queued at the 30-min budget (LIMITED_COVERAGE).
- [bug] MC-1 `AckNewLeader`: NEWLEADER ACK before the DIFF suffix is durable
  (`UpdNewLeaderAckAfterDurable`, `UpdEstablishedHistoryDurableOnQuorum`; crash consequence
  `UpdLeaderCompleteness`). Case C (real traces show the same order).
- [bug] MC-2 `BeginElection` from State.INITIAL + `LeaderBroadcast` on a stale in-memory
  database: `UpdLeaderCompleteness` (Init-rooted two-phase witness; trace-prefix continuation).
  Case C.
- [fix-inv] Update.tla: `ApplyOne` moved from the omitted context into
  `InteractionActions` (it advances `recovered`, read by votes); `EnvUpdate` rewritten in
  constructive form (same rely) after the open run failed to enumerate it.
- [fix-spec] (Case B) `CompleteSync` TRUNC/SNAP: the learner keeps its certified prefix inside
  H or adopts the leader's, whichever is longer; V0 replaced it by the leader's prefix, which
  could drop below the learner's own snapshot (`PipelinePrefix` counterexample in
  `upd-full-followup-2s-r1`; implementation: ZKDatabase.truncateLog reloads snapshot + log,
  ZKDatabase.java:599-611). Campaigns running at that time were stopped and rerun; full trace
  regression r5 passed (8/8); finding witnesses re-derived on the repaired model.
- [note] independent of the update: TRUNC does not remove snapshots newer than the truncation
  point (FileTxnSnapLog.truncateLog, persistence/FileTxnSnapLog.java:502-524); the model keeps
  `recovered = H` after TRUNC. Recorded for separate work; not exercised by any trace.

## Result

Generation, validation and model checking completed on the final artifacts. Fresh trace suite:
8/8 replayed (r5). Standard and update campaigns: budget-limited, no violation except the two
update-path findings MC-1 and MC-2 (Case C, see `bug-report.md`, `findings.json`), with
Init-rooted and real-trace-rooted witnesses. Coverage limits: `output/mc/campaign-summary.md`.
