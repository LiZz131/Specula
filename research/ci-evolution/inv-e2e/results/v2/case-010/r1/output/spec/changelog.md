# Incremental changelog — case-010 (baseline -> update)

## Generation
- [update] base: added dbInitialized, learnerStage, sessionMode, logCursor, leakedQueued; CodeVersion constant (old/new) selects exact-old vs updated Learner.shutdown semantics.
- [update] base: split atomic CompleteLearnerSync into ReceiveSyncMode, SyncApplyCommitted, PersistSyncSnapshot, LearnerAckNewLeader, CompleteLearnerSync (Learner.java:546-792).
- [update] base: new LearnerShutdownEffects/LearnerShutdown/LearnerExit (Learner.java:850-866, ZooKeeperServer.java:803-859, LearnerZooKeeperServer.java:155-173), ReloadDatabase (QuorumPeer.java:1257-1262), LeakedFlush (SyncRequestProcessor run loop of an unstopped processor), JoinEstablishedLeader (FLE established-leader path).
- [repair] base: QueueForSync/FlushTxnLog follow the sync-processor FIFO and a per-session log cursor instead of assuming disk==memory contiguity (FileTxnLog.append accepts any zxid, FileTxnLog.java:274-282); FollowerCommit requires the proposal already handed to the sync processor (logRequest order).
- [repair] base: ElectionUpToDate compares getLastLoggedZxid (DbView) of LOOKING peers; BeginElectionRound no longer resets the stale QuorumPeer syncMode and requires followers to have exited.
- [fix-inv] MonotoneUnlessRecovery: exemption migrated from the syncComplete flip to the split learner-sync steps (impl-abstraction clause).
- [add] Update.tla: AffectedActions, InteractionActions, EnvUpdate/DischargeContext, UpdIdleDbBackedByDisk, UpdDurableCoversCommitted, canaries.

## Round 1 - Trace Validation
- [fix] ReceiveSyncMode: removed guard requiring the leader's phase to be SYNCHRONIZATION/BROADCAST; LearnerHandler syncs after its own waitForEpochAck while the leader thread's setZabState lags (Trace: election-ordered-new.ndjson line 19).
- [fix] (generation-time refinement after first focused counterexample) ReceiveSyncMode/SyncApplyCommitted: added syncCommitCut — for TRUNC/DIFF only commits already made when the learner is registered for forwarding (toBeApplied) can precede NEWLEADER; for SNAP live commits during snapshot serialization can (LearnerHandler.java:549-600). The microsecond window between startForwarding and a TRUNC/DIFF NEWLEADER enqueue is not modeled.

## Round 1 - Model Checking (provisional; superseded)
- Standard MC.cfg (MCCoreNext) exhausted 285,706 states, no violation; focused/full update checks reported UpdIdleDbBackedByDisk (TRUNC sibling path) and OrderedHistories (leaked sync processor after TRUNC). Results archived in spec/output/mc/provisional-r1/ because Round 2 repaired the reference.

## Round 2 - Trace Validation (real reproduction trace traces/superseded-r1/repro-trunc-abort-new.ndjson)
- [fix] LearnerShutdown (trace form) no longer clears syncComplete: between Learner.shutdown and updateServerState the peer is still FOLLOWING/BROADCAST (SyncEntryJustified false positive at line 47). syncComplete is cleared by the observed SetPeerState(LOOKING) (QuorumPeer.java:1525-1530), by LearnerExit (MC form), and at the next ReceiveSyncMode; LearnerZkRunning additionally requires learnerStage = NEWLEADER.
- [fix] New LeaderDecideSync + syncPlan: the DIFF/TRUNC/SNAP decision, truncation point and pre-NEWLEADER commit cut are taken on the leader inside syncFollower under the committed-log read lock (LearnerHandler.java:775-935), not at the learner's later receive; the leader may apply the forwarded commit in between (ReceiveSyncMode at line 59 rejected TRUNC because the leader had already applied tx 1).
- [harness] New probe LeaderSyncDecision in LearnerHandler.syncFollower after startForwarding (mode, maxCommittedTx, committedTx). All traces re-collected (round-1 traces moved to traces/superseded-r1/).
- [fix] LeaderDecisionIfLogged: committedTx (Leader.lastCommitted of the current Leader object) is checked as <= the model's retained commit history instead of equality (restart-catchup-new line 85, fresh leader after restart).
- [fix] ObserveSetPeerState(LOOKING) now also sets phase ELECTION (setPeerState performs the role write and the nested setZabState(ELECTION) in one synchronized method, QuorumPeer.java:853-861); the Trace wrapper skips only the V0 probe's pre-nested-update phase sample for LOOKING (capture timing), validating the phase at the following SetZabState event. SyncEntryJustified unchanged (repro-trunc-abort traces line 49-50: LOOKING+BROADCAST transient with running=true, never exercised by prior traces).

## Round 2 - Model Checking (final model)
- [bug] MC-1 LearnerExit/ReceiveSyncMode(TRUNC)/SyncApplyCommitted: unfinished TRUNC sync keeps unlogged committed txns in the reused DB (UpdIdleDbBackedByDisk; full MCNext depth 38; focused depth 38). Reproduced on new and old implementation (harness/repro).
- [bug] MC-2 LearnerShutdownEffects (CodeVersion new): serving learner sync processor not drained/stopped -> LeakedFlush after TRUNC (OrderedHistories, depth 35). Old-code control reaches a pre-existing pre-UPTODATE variant (depth 42).
- [control] Old code: SNAP abort keeps the image (UpdIdleDbBackedByDisk, depth 37) = the update's target bug; new code SNAP-only view: no violation (11.67M states, depth 44, LIMITED).
- No Case A/B counterexamples in round 2.

## Result
Converged after 2 trace-validation repair rounds; final full trace regression passed on the final model; all applicable campaigns executed (bounded, LIMITED_COVERAGE). Bug hunting: 2 findings (MC-1 reproduced; MC-2 mechanism observed, consequence model-only).
