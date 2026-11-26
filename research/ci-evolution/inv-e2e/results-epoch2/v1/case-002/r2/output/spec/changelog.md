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

# Incremental run incr-8c80add29fe2 (case-002 update)

## Round U - Generation (source-driven update, MODEL_CHANGE_REQUIRED)
- [update] `LearnerNewLeader` (new, replaces `CompleteSync`+`PersistCurrentEpoch`+`ClearSyncMode`): NEWLEADER snapshot (SNAP/TRUNC), currentEpoch, and — for the update (`NewLeaderLogsPending=TRUE`) — `setSyncMode(NONE)` and hand-off of `syncPending` to `queued/proposed` before the ACK (Learner.java:726-758).
- [update] `LearnerAckNewLeader` (new): NEWLEADER ACK counted in the leader's `nlAcks` (Learner.java:760, Leader.java:1547-1575).
- [update] `EnterBroadcast`: UPTODATE processing; old-behaviour hand-off and sync-mode clear only when `NewLeaderLogsPending=FALSE` (Learner.java:763-785).
- [repair] `SelectSync`: DIFF contents go to volatile `syncPending`; TRUNC truncates durable history; SNAP installs a tentative tree (`recovered`) persisted only at NEWLEADER. The prior `CompleteSync` made the leader history durable atomically, hiding the ACK/fsync window (Learner.java:560-707).
- [repair] `LeaderBroadcast`: requires a quorum of NEWLEADER ACKs (was: followers already in BROADCAST, which in the implementation happens after UPTODATE) and serves/commits the leader's initial history (Leader.java:593,663-688).
- [repair] removed `QueueLearnerProposal` (learner invented txns) and unguarded `ObserveCommit`; `ReceiveProposal` buffers forwarded proposals during sync; `ObserveCommit` requires a leader-committed entry.
- [repair] `Crash` keeps the recoverable history (snapshot + later log, FileTxnSnapLog.restore); `FsyncOne` may complete without a live leader; role entry requires a drained pipeline (SyncRequestProcessor.shutdown join+flush).
- [add] `Update.tla`: Affected/Interaction actions, `FocusedSpec`, properties `AckedHistoryHandedOff`, `NewLeaderAckDurable`, `CommittedSurvivesLeaderChange`, seed canary, hypothetical-fix control.

## Round U - Trace Validation
- [harness] Rebased prior patch (renamed SpeculaTrace->SpecularTrace, specula.trace->specular.trace); `BroadcastReady` moved after `zk.startServing()`; new probes `SyncProposalBuffered`, `SyncProposalApplied`, `NewLeaderAckSent` (harness/patches/instrumentation.patch).
- [harness] attempt 1 used `mvn -o`; surefire provider missing offline -> no traces (spec/output/incr/harness/harness-results-attempt1-offline.ndjson); rerun online for build dependencies.
- [fix] Trace field interpretation (inherited defect): `PeerRoleChanged/PhaseChanged/FollowerRegistered/SyncModeChanged/BroadcastReady` zxid is `getLastLoggedZxid()`/`getDataTreeLastProcessedZxid()` = in-memory tree position (QuorumPeer.java:1257-1261), not the durable log tail; replaced `ZxidMatches(durable')`/`ZxidMatches(applied')` with `TreeZxidMatches` (Trace: follower-diff.ndjson event 15, diff-sync-consistency.ndjson event 120).
- [fix] `ElectionWon` zxid is FLE's `proposedZxid` (elected leader's position), FastLeaderElection.java:901 (Trace: diff-sync-consistency.ndjson event 56).
- [control] old-revision build with the same probes (controls/old-instrumentation.patch): its DIFF trace is rejected by the update check at `NewLeaderAckSent` (event 9) and accepted with `NewLeaderLogsPending=FALSE` (Trace-oldcontrol.cfg).
- Fresh new-version suite (5 traces) passes; 5 archived old-version traces also replay (no update probes; retained as regression evidence, superseded for update coverage).

## Round U - Model Checking
- [fix-spec] `LearnerAckNewLeader`: frame condition omitted `syncPending` (TLC attempt 1: "Successor state is not completely specified"); VAV analysis clean afterwards (`output/incr/vav-base.json`). Attempt-1 logs kept as `*-attempt1-vaverror.log`.
- [fix-spec] Seed literal (`UpdateSeed.tla`): `leadersByEpoch` domain extended to the 3-epoch configs (witness ran with MaxEpoch=2); TypeOK on the initial state.
- [bug] MC-1 `LearnerAckNewLeader`: NEWLEADER ACK precedes durability of the handed-off history; `NewLeaderAckDurable` violated (9 steps from the seed) and `CommittedSurvivesLeaderChange` violated (22 steps): a txn served after the NEWLEADER quorum is missing at the next leader (Case C; `bug-report.md`, `confirmation-MC-1.md`).
- [fix-spec] `FinishDiscovery`: added the `Leader.waitForEpochAck` "Follower is ahead of the leader" guard (Leader.java:1442-1455, StateSummary.java:42-44). Case B, found while classifying the hypothetical-fix control counterexample (`seed-fixedcontrol-r1-pre-discovery-guard.log`: epoch-3 discovery quorum containing a follower with a newer summary) and also used by the first MC-1 U3 path. All campaign runs were repeated on the repaired model; first-round logs kept as `*-r1-pre-discovery-guard.log`.
- [bug] MC-1 re-confirmed on the repaired model: U2 in 9 steps, U3 in 22 steps (`output/incr/MC-1-U2-counterexample.out`, `MC-1-U3-counterexample.out`). Old-behaviour control violates U1 (10 steps) and U3 in 21 steps without a crash (`MC-1-oldcontrol-U3-counterexample.out`).
- Final trace regression on the final artifacts: 5/5 fresh traces pass (`output/incr/final-trace-*.log`); old-revision control trace still rejected under update semantics.
- Campaign results on the final model: see `model-checking-summary.md` (standard MC and simulation without violation, budget-limited; U1 holds within all bounds; U2/U3 violated = MC-1; controls as expected).

## Result (run incr-8c80add29fe2)
Validation converged on the final artifacts (5/5 fresh traces; final regression after the last repair).
Model checking: 1 bug (MC-1) with budget-limited coverage elsewhere. Code review: CR-1..CR-3. All four
findings REPRODUCED (`confirmation-*.md`).
- Note: prior-run helper scripts `spec/run-validation-suite.sh`, `spec/check-verification-suite.sh` and
  `spec/verification-suite-manifest.json` reference the prior run's paths and are superseded for this run by
  `harness/run.sh`, `spec/run-tlc.sh`, `spec/output/incr/command-results.ndjson` and `spec/model-checking-summary.md`.
