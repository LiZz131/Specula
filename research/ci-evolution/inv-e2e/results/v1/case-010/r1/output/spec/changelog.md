# Incremental changelog (case-010, `baseline` -> `update`)

Prior V0 suite: `/work/previous/.specula-output` (immutable; copies of its specs in `spec/prior-v0/`).

## Round 0 - Generation (MODEL_CHANGE_REQUIRED)
- [update] `LearnerShutdownCore`/`LearnerShutdown`/`LearnerExit`: new per-follower learner exit with UPDATED semantics (SNAP -> `zkDb.clear()`; serving exit fast-forwards and leaks the log processor queue) and a PRIOR control mode (Learner.java:860-865; ZooKeeperServer.java:803-858; LearnerZooKeeperServer.java:154-173).
- [update] `ReloadDatabase`, `dbCleared`: reload after clear (QuorumPeer.java:1257-1262).
- [repair] SNAP/TRUNC reconciliation split out of `CompleteLearnerSync`: `ChooseSyncMode`, `LoadSyncSnapshot`, `TruncateLog`, `ApplySyncCommit`, `FinishSyncSnapshot`, `LearnerNewLeader`, `CompleteLearnerSync` (Learner.java:546-812).
- [repair] `syncMode` no longer reset by `BeginElectionRound` (only Learner.java:563,566,589,750 write it).
- [repair] FIFO `syncQueued` and non-contiguous `durable` (no contiguity guard); `leakedQueued` + `FlushLeakedTxnLog`.
- [repair] `SyncModeAllowed` (LearnerHandler.java:841-932); late joiner may sync with a BROADCAST leader; follower current epoch persisted at NEWLEADER.
- [repair] `CommitProposal` commits in the leader's outstanding order instead of dense ids (Leader.java:890-905); `FollowerCommit` matches the pending head (FollowerZooKeeperServer.java:97-110).
- [property] `OrderedHistoriesV1`, `MonotoneUnlessRecoveryV1` (old forms kept for evidence); update properties in `UpdateProps.tla`.
- Preflight: `spec/output/gen-sany.log`, `spec/output/gen-cfg-preflight.log`.

## Round 1 - Trace validation (fresh new-version traces)
- [harness] Prior patch applied cleanly to the new source; probes densified around the update (LearnerShutdown, ReloadDatabase, LoadSyncSnapshot, TruncateLog, ApplySyncCommit, real queues/pending/ack sets/recovered history). Prior stateful (v2) emitter was not preserved in the prior run; v3 emitter rebuilt (see harness/INSTRUMENTATION.md).
- [fix-inv] `ExitedLearnerMemoryBackedByLog`: scope restricted to non-leaders. Evidence: leader state between `Leader.propose` and `SyncRequestProcessor.processRequest` (trace upd-snap-exit-diff-v3 event 39). (Trace: upd-snap-exit-diff-v3.ndjson, attempt1)
- [fix] `LearnerShutdownCore`: a full clear reduces `committed`/`applied` to their durable part (DataTree discarded). (Trace: upd-snap-exit-diff-v3.ndjson event 201, attempt2)
- [fix] `syncComplete` reset moved from the trace-form shutdown to `LearnerExit`/`ChooseSyncMode` (zab state is still BROADCAST between Learner.shutdown and updateServerState). (Trace: upd-serving-exit-v3.ndjson event 54)
- [fix] Trace: `SetPeerState(LOOKING)`+`SetZabState(ELECTION)` from one synchronized `QuorumPeer.setPeerState` replayed as one composite step (`ObserveSetPeerStateLooking`). (Trace: upd-serving-exit-v3.ndjson event 55)
- [fix] `LearnerShutdown` trace form accepts a late duplicate call after LOOKING (QuorumPeer.shutdown races the peer thread). (Trace: upd-serving-exit-v3.ndjson event 120)
- Final full regression on the stable candidate: 5/5 fresh traces PASS with TraceMatched (spec/output/trace-*-v3.log); archived V0 traces (4) replay on common fields (spec/output/archived-trace-*.log).

## Round 2 - Model checking (repair loop)
- [fix-spec] `leakedQueued`: one FIFO per leaked processor (two leaked lifecycles produced a false `<<1,1>>` single-queue order). (MC: upd-hunt-snap/trunc, OrderedHistoriesV1)
- [fix-inv] `MonotoneUnlessRecoveryUpd` (UpdateProps): the update's SNAP-exit clear is an authorized retraction of in-memory commit/apply histories (E_MON2); base `MonotoneUnlessRecoveryV1` authorizes the split reconciliation steps (E_MON).
- [fix-spec] `TruncateLog`: reload restores the newest snapshot, which may be newer than the truncation target (FileTxnSnapLog.truncateLog cuts only the WAL). (MC-full, SnapshotPublishedValid)
- [fix-spec] `SyncModeAllowed`: DIFF only when the peer's last zxid is in the leader's committed (applied) log; TRUNC otherwise; `ChooseSyncMode(DIFF)` re-aligns client-visible histories with the confirmed baseline. (MC: upd-hunt-snap, PRIOR-style DIFF beyond committed log)
- [fix-inv] `SnapshotPublishedValidV1` drafted (published snapshot prefix of committed order); after later repairs the prior property shows no separating state (oracles `final-evidence-oldspv.log` complete, `f2-ev-oldSPV-full.log` limited) -> decision keep, V1 kept as an additional check.
- [fix-spec] WAL flushes append duplicates (`Append`, was `AppendOnce`), replay-order property non-decreasing; probe `recovered` no longer deduplicated. (MC: duplicate re-append hidden)
- [fix-spec] `SyncModeAllowed` SNAP: not for a peer ahead of the leader's committed log (TRUNC first; forceSnapSync test-only). (MC: upd-hunt-snap)
- [fix-spec] `NextFrom`/`TruncTarget` zxid-based (LearnerHandler compares zxids only). (Old-revision trace replay at the DIFF re-join, event 205)
- [fix-spec] `ReplayHistory`: restart/reload/truncate in-memory history = sorted distinct replayed txns (DataTree.lastProcessedZxid is the max). (MC: focused-residual)
- [fix-spec] `NewLeaderCommit` in `FormNewLeaderQuorum`/`ObserveNewLeaderQuorum` and `CommitProposal` only for an established BROADCAST leader (prior model defect: a new leader committed old-epoch records by ACK before establishment). `MCFormNewLeaderQuorum` moved from the omitted context to `InteractionActions`. (MC: open-residual)
- [harness] probe ordering races fixed: traced state writes atomic with emission; `setPeerState` emission atomic with nested `setZabState`; role cached in probe (removes a lock-order hazard inherited from the prior emitter). Traces regenerated as v3b/v3c/v3d.
- [bug] MC-1 (update-introduced): learner exit no longer drains/stops the follower SyncRequestProcessor (UPD-3).
- [bug] MC-2 (pre-existing): TRUNC-mode exit keeps an unpersisted in-memory image; update guard covers SNAP only (UPD-2).
- [bug] MC-3 (pre-existing): fast-forward before drain leaves re-sent/stale records before committed history.

## Result
Final trace regression: 5/5 fresh v3d traces PASS on the final model; old-revision control traces behave as expected under PRIOR. Final MC: see spec/output/verification-summary-update.md. UPD-1 (the update's fix) verified within bounds; 3 findings (1 introduced by the update, 2 pre-existing); budget-limited campaigns recorded as LIMITED_COVERAGE.
