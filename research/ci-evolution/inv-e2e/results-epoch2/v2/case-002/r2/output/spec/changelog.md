# Validation and repair changelog

The V0 history (rounds below "V0 history") is preserved unchanged at the end
of this file. Incremental work for update 2efbdfc starts here.

## Incremental round 1 - Generation (update 2efbdfc)

Source-driven changes (MODEL_CHANGE_REQUIRED):
- [update] `SyncWithLeaderNewLeader` (new; replaces `PersistCurrentEpoch`): NEWLEADER persists the epoch, resets the sync mode, starts the learner pipeline and moves every buffered sync proposal into `queued`/`proposed` before the NEWLEADER ACK is counted (Learner.java:726-761).
- [update] `SyncWithLeaderUpToDate` (new; replaces `EnterBroadcast`/`ClearSyncMode`): UPTODATE only commits the buffered commit target and enters BROADCAST (Learner.java:764-785); requires the leader to have activated.
- [update] `Update.tla`: Affected/Interaction actions, `EnvUpdate` for TakeSnapshot/DropMessage, discharge, properties `CommittedQuorumDurable`, `CommittedNeverLostByLeader`, `NewLeaderAckAfterLogging`, canaries.

Repairs of V0 model defects needed to check the update (implementation unchanged):
- [repair] `CompleteSync`: the sync payload is buffered (`syncBuf`, `syncCommit`) instead of being copied into the learner's durable log; TRUNC truncates durably, SNAP becomes durable at the NEWLEADER snapshot (Learner.java:561-598, 739-741).
- [repair] `LeaderBroadcast`: guard is a NEWLEADER-ACK quorum (`nlAcks`, Leader.java:1547-1573) instead of followers already in BROADCAST; activation commits and serves the leader's loaded history (Leader.java:663-712, ZooKeeperServer.java:845).
- [repair] `FinishDiscovery` counts the leader's own NEWLEADER ack; `WinElection` resets the ack set and requires a drained pipeline (previous role's shutdown flush, SyncRequestProcessor.java:254-260).
- [repair] removed `QueueLearnerProposal` and `ObserveCommit` from `Next` (a learner fabricated proposals/commit certificates without a leader; not source-backed; not used by Trace.tla or MCNext).
- [repair] `ReceiveProposal`/`ReceiveCommit` consume proposals/commits already transferred by a sync session without effect (LearnerHandler.startForwarding forwards only after the sync point); `ReceiveCommit` requires BROADCAST (pre-UPTODATE commits belong to the sync payload).
- [repair] `FsyncOne` no longer blocks for a learner without a leader (leaked SyncThread still fsyncs; ACK not modeled).

## Incremental round 1 - Validation

Harness: V0 patch rebased (one hunk re-anchored: `zk.startup()` removed by the update), Specula→Specular rename, `event.peer`, five update probes. Fresh traces from all four V0 scenarios plus `diff-sync-uncommitted-log` (DIFFSyncConsistencyTest, added by the update).
- [fix-trace] r1: `ElectionWon` zxid is the elected vote's zxid (FastLeaderElection.java:898-901), not the emitter's tail (Trace: diff-sync-uncommitted-log.ndjson, event 58). Pre-existing interpretation defect exposed by the new scenario.
- [fix-trace] r2-r3: `PeerRoleChanged`/`PhaseChanged`/`ElectionWon` zxids are data-tree zxids that can lag the durable log after a learner failure between NEWLEADER and UPTODATE (shutdown skipped in INITIAL state; finding CR-2) (event 102).
- [fix-trace] r4: a reported LEADING peer is projected to the model's `looking` until it persists its proposed epoch (base WinElection is atomic; the implementation is LEADING earlier while the previous epoch's leader can still be LEADING) (event 102).
- [fix-trace] r5: `BroadcastReady` zxid may be the restored data tree's tail after an unobserved process restart (event 131).
- [fix-trace] r7: the NEWLEADER ack set resets when a peer re-enters LEADING (new Leader object), found by negative mutation M4 which r6 wrongly accepted.
- [check] r7: all five fresh traces pass (TraceMatched, events+1 states, 0 queue). Negative mutations M1-M4 rejected at the expected events.
- [evidence] `TraceUpdate.cfg`: `CommittedQuorumDurable` is FALSE on the real replayed state after event 90 of diff-sync-uncommitted-log (leader serves (1,2) durable only on itself). The Zab1_0Test fixture traces also report it because their scripted leader has no durable history in the trace; those are not evidence.

## Incremental round 1 - Model Checking

- [check] `MC-small.cfg` exhausted (99,064 distinct, no violation); `base.cfg` exhausted at the level-23 bound (5,288,478 distinct); `MC.cfg` exhausted at the level-23 bound (21,702,968 distinct, no violation) — standard round passed before update campaigns.
- [check] canaries: NotElection/Mutation/Sync/Recovery/UpToDate/NewLeaderLogged (MaxEpoch 2), NotAckBeforeDurable, NotSyncedHistoryCommitted all violated as intended (reachability witnesses). `MC-hunt-newleader.cfg` first used MaxEpoch 1 where the path is unreachable (no leader history before the first sync); raised to 2.
- [bug] `SyncWithLeaderNewLeader` → `LeaderBroadcast`: `CommittedQuorumDurable` violated (Update-hunt-durable.cfg, 27 states). Case C, reproduced on the implementation (MC-1).
- [fix-spec] `ReceiveProposal`: Update-hunt-loss simulation (2 txns) produced a `CommittedHistoriesPrefix` counterexample in which a learner received t2 before t1 from the same leader. Case B: the leader→learner channel is a TCP stream, proposals are delivered in leader order. Added `pos` to messages and FIFO delivery; stale positions are consumed without effect. Pre-existing V0 abstraction (unobservable with V0's single transaction).
- [fix-spec] `SelectSync`: one directive per learner session (`syncMode = "NONE"` guard); the counterexample above re-selected DIFF/TRUNC/SNAP repeatedly.
- [rerun] after the two Case-B repairs: SANY (`output/sany/`), trace regression r8 (all five fresh traces pass), MC-small r2, and all standard/update campaigns restarted; the in-flight first update runs were stopped and archived in `output/mc/aborted-r1/` (not counted).

- [bug] consequence hunt `Update-hunt-loss-witness.cfg` (BFS continuation from the reachable final state of the CommittedQuorumDurable counterexample, `UpdateLossFromWitness.tla`): `CommittedNeverLostByLeader` violated — the acking learner crashes before its fsync, a new leader is elected without the old leader, the old leader's only durable copy is truncated (TRUNC). Case C, consistent with the reproduction (MC-1).
- [fix-spec] `FollowLeader`: only a LOOKING peer follows (QuorumPeer.run after lookForLeader); the first consequence counterexample let the serving leader become a follower directly. `Crash`: the crashed peer's FLE votes are volatile (reset). Both are pre-existing V0 over-approximations; they only remove transitions, so earlier no-violation results within the same bounds remain sound for the final model. Re-run on the final model: SANY, trace regression r9 (5/5 pass), `Update-hunt-durable-2s.cfg` (CQD violated again), witness hunt r3 (CommittedNeverLostByLeader violated again), `MC.cfg`/`base.cfg` r3, update simulations.
- [note] `update-hunt-loss-sim` (Update-hunt-loss.cfg, simulation, full spec, 2 txns, MaxEpoch 3, 1 crash) found no violation in its budget after the FIFO repair; the consequence needs a ~42-step specific path, found instead by the witness continuation hunt.

## Incremental result

Final artifacts: `base.tla`/`MC.tla`/`Trace.tla`/`Update.tla` after the
FIFO, SelectSync, FollowLeader and volatile-vote repairs. Trace regression r9:
5/5 fresh traces pass. Final model checking: `MC.cfg` (4,014,474 distinct) and
`base.cfg` (1,070,724 distinct) exhausted within the level-23 bound without
violation; `Update-full.cfg` BFS (final model) violates `CommittedQuorumDurable`
at depth 27, as do the focused and two-server hunts and the full-spec
simulation; the witness continuation violates `CommittedNeverLostByLeader`;
continuation simulations of full/focused/open specs and the discharge
simulation found no further violation within 30 minutes each
(LIMITED_COVERAGE). Bug hunting: 1 MC finding (MC-1) and 2 code-review
findings (CR-2, CR-3), all REPRODUCED. Summary: `output/mc/campaign-summary.md`.

## V0 history

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
