# Changelog — incremental run case-010 (V0 suite -> updated source `update` b16ba71)

Disposition of the source delta: **MODEL_CHANGE_REQUIRED** (modeling-brief.md section 8.1).
Entries are tagged `[source]` (driven by the source delta), `[repair]` (implementation-backed
defect of the reused V0 abstraction, needed for the update or its interactions), `[fix]`
(trace/MC-loop correction of this run's draft) or `[inv]` (property correction, Case A).

## Generation (draft of the complete updated reference)

- [source] `LearnerShutdown` added with the updated branch `fullyShutDown = (syncMode == SNAP)`; full shutdown of a non-running server clears the ZKDatabase (`memDb := <<>>`, `memInit := FALSE`); running server drains + fast-forwards. Constant `UpdateFullShutdownOnSnap` (TRUE = updated source) selects the branch; FALSE only in differential controls.
- [source] `ReloadDatabase` (in-process `getLastLoggedZxid -> loadDataBase` after the clear) and `FollowerExitToLooking`.
- [repair] `memDb`/`memInit` split from `durable`; election and registration read `LastLoggedHist` (V0 compared `durable`, which hid the reported in-memory image). `recoveryVisible` subsumed by `memDb`.
- [repair] Learner sync split at packet/persistence boundaries; follower `currentEpoch` now persisted at NEWLEADER (V0 required it before SYNCHRONIZATION, contrary to Learner.java:743).
- [repair] Late joiners can sync with an established leader (V0 MC required the leader in SYNCHRONIZATION).
- [repair] Histories ordered with gaps (V0 dense prefixes could not represent divergent records or TRUNC).
- [repair] FLE vote rule (voter adopts a candidate at least as up to date) and out-of-election join rule replace the V0 global up-to-date oracle.
- [inv] `OrderedHistories` revised to ordered histories; `DurableHistoryConsistent` and `LeaderCompleteness` added (general recovery / Zab properties now expressible).

## Round 1 — model smoke (simulation; local feedback, not campaigns)

- [fix] Follower commit knowledge was set only at sync completion while UPTODATE commits precede it -> moved to `LearnerUpToDate` (smoke-sim-1).
- [fix] Leader could start SYNCHRONIZATION without proposing an epoch when all epochs were equal -> epoch must be proposed in this leadership (smoke-sim-1).
- [inv] `SyncEntryJustified`: exempt the Learner.shutdown -> updateServerState window (smoke-sim-2) and the setPeerState(LOOKING) -> setZabState(ELECTION) window (smoke-sim-6). Case A: neither window serves clients.
- [inv] `ActiveLeaderUniqueness` -> `LeaderUniquenessPerEpoch` (smoke-sim-3). Case A: a deposed leader stays BROADCAST until its next quorum check (Leader.java:739-780); scope promises per-epoch uniqueness. `LeaderShutdown` (quorum loss) added; proposals require a quorum ensemble (abstraction keeps id order = zxid order).
- [fix] `ReportedHistoryDurable` antecedent excluded synced followers (smoke-sim-4; Case A on the new property: a synced follower's data tree may run ahead of its own flush).
- [fix] Follower logRequest is atomic (pendingTxns.add + enqueue): commit requires the record to be queued; exit drains not-yet-enqueued records.

## Round 2 — trace validation (fresh v3 traces)

- [fix] `snap-abort-rejoin-v3` line 19: LearnerHandler leaves waitForEpochAck at quorum, before the leader thread's setCurrentEpoch/SYNCHRONIZATION (Leader.java:1442-1475). Follower sync now requires `LeaderEpochAgreed`; leader history/epoch base fixed at getEpochToPropose (`LeaderPersistEpoch`), `LeaderStartSync` keeps earlier NEWLEADER ACKs. Case B.
- [fix] `snap-abort-rejoin-v3` line 43: setPeerState(LOOKING) and setZabState(ELECTION) are separate writes -> `EnterElectionPhase`. Case B.
- [fix] `restart-catchup-v3` line 84: a restarted process has a fresh Leader object / election receive set -> `RestartLoadDatabase` clears the peer's epochAcks/newLeaderAcks/electionVotes. Case B.
- [fix] base refactor: phase-entry guards moved from MC into base (`EnterDiscovery`, `LeaderEnterBroadcast`, `FollowerEnterBroadcast`, `FollowerPersistAcceptedEpoch`); base `Next` added; definition order fixed.
- Gate: all three fresh traces pass on the stable candidate (`gate2-trace-*.log`).
- [fix] Trace-only: racing duplicate `Learner.shutdown` callers (QuorumPeer.shutdown vs run-loop finally); the effect is applied at the first emitted event, a later duplicate from a stopped peer is a stutter; `zkWasRunning` read is unsynchronized, so only RUNNING => syncComplete is required (`snap-complete-restart-v3b` line 113).
- Gate (final harness set v3b, 4 traces): PASS (`final-gate-trace-*-v3b.log`); non-vacuity: old-semantics model and 4 field mutants rejected at the expected lines.

## Round 3 — model checking (campaign entry after the v3b gate)

- Standard `MC.cfg` and `Update-full.cfg` (30 min BFS each): no violation, 22.2M / 22.1M distinct states, depth 35, queue non-empty -> LIMITED_COVERAGE. Unsteered old-semantics control and in-memory-commit canary did not reach their depth (~40+) within 30 min.
- [fix] Canary `DiffAbortAfterNewLeader` tested `syncMode = DIFF` after NEWLEADER, where the code has reset the mode (Learner.java:750); canary-only, run stopped and replaced.
- [fix-spec] `ApplyTxn` was enabled on a follower whose learner had shut down (TypeOK caught `memInit=FALSE` with a non-empty tree in `update-hunt-snap-steered-bfs-premodelfix.log`). Case B: FinalRequestProcessor runs only inside a serving server's processor chain. Guard added (serving leader / learner after startServing).
- [fix-spec] TRUNC removed snapshot-covered records (`update-hunt-snap-steered-named-bfs-pretruncfix.log`: SNAP sync -> in-memory COMMIT -> NEWLEADER snapshot -> exit -> TRUNC -> exit). Case B: `FileTxnSnapLog.truncateLog` cuts only txn-log files (FileTxnSnapLog.java:502-524, FileTxnLog.java:455-475) and the learner forces lastProcessedZxid to the cut (Learner.java:597). Added `snapZ` (newest snapshot frontier); TRUNC keeps snapshot-covered records on disk and reports the cut. Not a finding.
- Steering expressed as `ACTION_CONSTRAINT` over `FocusNext` (semantically equal to the conjunction forms; named actions in counterexamples).
- [fix-spec] NEWLEADER FIFO cut: a proposal created after the leader's sync decision was readable before NEWLEADER (`U3-leadercompleteness-prefifo-fix.log`). Case B: NEWLEADER is queued right after `syncFollower` (LearnerHandler.java:551-600); before NEWLEADER only proposals up to `lastProposed` at the decision are read. Trace gate re-run (`final5-gate-trace-*-v3b.log`, PASS).
- [fix] Discharge/open rely `EnvUpdate` rewritten in enumerable form (the element-wise version could not bind primed variables in the open spec; `final-update-open-bfs-envbinding-error.log`).
- [ops] An operator cleanup of `/dev/shm/specula-e2e-case-010` at 22:55 removed the state directories of two running jobs (`final-base-bfs`, `final-update-canary-truncabort-bfs`, exit 1); both re-run as `final5-*`.

## Round 4 — final campaigns on the final artifacts

- [bug] **MC-1** (Case C candidate, model checking): TRUNC-mode learner exit keeps a non-durable in-memory commit; the update's full shutdown covers SNAP only. Witness `final4-update-hunt-mc1-deterministic-bfs.log` (55 states); consequence `final4-update-continue-mc1-consequence-bfs.log` (durable hole). Pre-existing on the TRUNC branch, not fixed by the update.
- [bug] **MC-2** (Case C candidate, model checking): DIFF learner exiting between NEWLEADER and UPTODATE under-reports its log; a logged record escapes the next epoch (`final4-update-hunt-trunc-steered2-sim.log`, 89 states). Pre-existing; unrelated to the update's condition.
- Differential controls on the final model: exact-old exit violates `ReportedHistoryDurable` (depth 39) and `DurableHistoryConsistent` (depth 57) under the steered U1 schedule; the updated exit restricted to SNAP/DIFF syncs shows no violation through depth 58.
- No property was weakened to remove MC-1 or MC-2.

## Result

Validation converged (final gate PASS on 4 fresh traces). Model checking budget-limited (LIMITED_COVERAGE); 2 findings (MC-1, MC-2) recorded in `bug-report.md` / `findings.json`.
