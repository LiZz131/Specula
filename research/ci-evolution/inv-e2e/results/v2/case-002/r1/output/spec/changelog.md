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

# Incremental run (updated source, artifact commit `update` 2efbdfc3)

## Round I1 - Generation (MODEL_CHANGE_REQUIRED)
- [update] `CompleteSync` -> `ReceiveSyncPayload` (stream buffered in `pendingSync`; TRUNC/SNAP install on disk), `PersistCurrentEpoch`, `ClearSyncMode` (now required after setCurrentEpoch and before the ACK, Learner.java:749-750), new `AckNewLeader` (logRequest enqueue when `NewLeaderLogsPending`, ACK counted in leader `nlAcks`), `EnterBroadcast` (UPTODATE; requires leader activated; commits the streamed history).
- [repair] `LeaderBroadcast`: activation on a NEWLEADER-ACK quorum (Leader.waitForNewLeaderAck) instead of followers in BROADCAST; commits/certifies the leader's loaded history (`recovered`, from Leader.java:593 loadData).
- [repair] `BeginElection`: RUNNING leave flushes the pipeline (shutdown); INITIAL leave (updated window) is a no-op (canShutdown false) and the started SyncRequestProcessor keeps running.
- [repair] removed `QueueLearnerProposal` / `ObserveCommit` (no implementation counterpart); `FollowLeader` only from LOOKING.
- [add] `Update.tla` (Affected/Interaction/EnvUpdate/discharge, focused RecoveryInit family), `UpdateProps.tla` (NewLeaderAckDurableStep, CommittedDurableOnQuorum, LeaderCompleteness, SyncedLogMatchesLeader, PendingOnlyDuringSync); `SyncCompletionJustified` strengthened with `nlAckSent`.
- [preflight] SANY clean for base/MC/Update/Trace (spec/output/update/sany-*.log).

## Round I1 - Validation (harness rebase + traces)
- [harness] prior patch rebased (only the `BroadcastReady` hunk re-anchored to `zk.startServing()`); update probes added; build OK (`spec/output/update/build-instrumented.log`).
- [harness] all 4 prior scenarios + `DIFFSyncConsistencyTest` + 2 observation tests pass and emit nonempty traces.
- [fix-capture] `NewLeaderAckSent` emitted after the network write let the leader's `NewLeaderAckCounted` precede it (trace-*-r1 failures at events 18/28/28); probe moved before the write, post-write probe `NewLeaderAckWritten` added; traces re-collected (first collection kept in traces/superseded-capture-r1).
- [fix-replay-config] `Trace.cfg` MaxEpoch 3 -> 4 (update trace reaches epoch 4).
- [fix-trace] SNAP sessions persist a snapshot, not txn-log records: disk-position check limited to non-SNAP sessions (`snapSession`).
- [fix-trace] inherited interpretation repaired: `ElectionWon` zxid is the elected leader's (FLE proposedZxid); several servers may be LEADING at once in different, not yet established epochs (`OneActiveLeaderPerEpochTrace` counts established leaders); `PeerRoleChanged/PhaseChanged/SyncModeChanged/FollowerRegistered/BroadcastReady` report the in-memory position.
- [fix-spec] (trace-driven, update-diff-sync-consistency event 106) added `memHist`: votes, ACKEPOCH position, sync selection and a new leader's served history use the in-memory database, which lags the log after an INITIAL-state abort (no fast-forward) and, for learners, after a RUNNING leave (fast-forward precedes the sync-processor flush). Leader leave flushes before the fast-forward (ProposalRequestProcessor.shutdown).
- [add] `TraceSync.tla`: action-level replay of the learner DIFF path through the reference actions (follower-diff, update-observe-ack-durability).
- [result] final regression on the stable candidate: 7/7 fresh traces pass `Trace.tla` with TraceMatched, 2/2 pass `TraceSync.tla` (spec/output/update/final-trace*-*.log). Archived V0 traces are superseded (rejected by the mandatory update detail schema; old ordering removed by the update).

## Round I1 - Model checking
- [bug] MC-1 (U1/U2): `NewLeaderAckDurable` and `CommittedDurableOnQuorum` violated (final-focused-ackdurable, final-focused-quorumdurable); old-semantics controls violate too (pre-existing gap, narrowed not closed by the update).
- [bug] MC-2 (U4): `LeaderCompleteness` violated from the reachable post-activation state without any crash (final-hunt-postact-leak) and with crashes allowed (final-hunt-postact-crash); matches real trace update-diff-sync-consistency events 103-126.
- See spec/output/update/campaign-summary.md for every campaign outcome.
- [fix-inv] `SyncedLogMatchesLeader` (Case A): the first formulation (follower durable log prefix-comparable with its committed history) rejected a duplicated re-logged record of a committed transaction (`output/update/hunt-ghost-duplicate-caseA.log`), which ZooKeeper's idempotent replay tolerates (zookeeperAdmin.md:2599); revised to "every txn in a broadcasting follower's log is known to its current leader". Evidence E5/E5c/E5g.
- [bug] MC-3 (pre-existing, unchanged learner shutdown order): `SyncedLogMatchesLeader` violated (`output/update/final-hunt-ghost.log`, admitted by `final-hunt-ghost-full.log`).
