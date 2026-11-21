# Incremental changelog — case-002 (Zab V0 prior -> artifact commit `update`)

Prior (V0) changelog is preserved verbatim in `/work/previous/.specula-output/spec/changelog.md`
and its logs/scripts under `spec/output/prior-v0/` and `spec/prior-v0/`.

## Round 0 - Generation (decision gate: MODEL_CHANGE_REQUIRED)

Source-driven updates (diff of `quorum/Learner.java`, `ZooKeeperServer.java`):
- [update] `CompleteSync`/`PersistCurrentEpoch`/`ClearSyncMode` replaced by the packet-level
  learner loop: `LearnerProposal`, `LearnerCommit`, `LearnerNewLeader` (snapshot + setCurrentEpoch),
  `LearnerStartupWithoutServing` (setSyncMode(NONE) + startupWithoutServing -> INITIAL),
  `LearnerLogPending` (logRequest of packetsNotCommitted before the ACK), `LearnerAckNewLeader`
  (clear + ACK without waiting for fsync), `LearnerUpToDate` (startServing -> RUNNING),
  `LearnerLogAfterUpToDate`, `LearnerCommitAfterUpToDate`, `EnterBroadcast`.
- [update] Role exit (`BeginElection`, new `LearnerAbort`) uses `ExitHist`: drain+fast-forward only
  from RUNNING (ZooKeeperServer/LearnerZooKeeperServer.shutdown are no-ops in INITIAL).
- [update] New state: `lq` (LearnerHandler packet stream), `pnc`/`pcm`/`toLog` (syncWithLeader
  buffers), `syncStage`, `hstage`, `nlAcked`, `zkState`, ghosts `syncTarget`, `epochTarget`,
  `syncError`.

Repairs of V0 model defects exposed while projecting the update (implementation-backed):
- [repair] V0 `CompleteSync` made the leader's history durable at the learner atomically
  before NEWLEADER ACK; neither the old nor the new code does that (logRequest is asynchronous;
  old code logged only after UPTODATE). Split as above.
- [repair] V0 leader establishment required followers in BROADCAST; `Leader.waitForNewLeaderAck`
  counts NEWLEADER ACKs (LearnerHandler.java:614-623). `LeaderBroadcast` now counts `nlAcked`
  and commits/serves the leader's loaded tree (Leader.startZkServer).
- [repair] V0 `EnterSyncPhase`/`SelectSync` required the leader in phase sync, so a learner
  could never join an established leader; LearnerHandler serves late joiners
  (startForwarding forwards outstanding proposals). Now allowed with `Outstanding(l)`.
- [repair] V0 `Propose`/`Commit` sent to every server; Leader.sendPacket only reaches
  forwarding followers (stream `lq` before UPTODATE, `messages` after).
- [repair] V0 election compared durable log length; FLE uses getLastLoggedZxid = in-memory
  tree (QuorumPeer.java:1257-1262). `HistoryAtLeast` now uses `DbPos` and zxid order.
- [repair] V0 `FsyncOne` blocked without a leader; SyncRequestProcessor forces regardless.
- [repair] Removed dead V0 actions `QueueLearnerProposal`, `ObserveCommit` (not in V0 Next).
- [fix-inv] `PipelinePrefix` snapshot clause also admits the NEWLEADER snapshot of the
  in-sync tree before it is served; `SyncCompletionJustified` additionally requires RUNNING.
- [fix-inv] `Crash` retains only the certified prefix of the snapshot as visible state.

## Round 1 - Trace Validation (fresh new-version traces)

- [fix] Harness: the V0 `BroadcastReady` hunk no longer applied (source drift); re-anchored
  after `zk.startServing()`. Added update probes `SyncProposalBuffered`, `SyncCommitReceived`,
  `NewLeaderAcked` (with pending/committed/toLog buffer fields) and `FollowerException`.
- [fix] Harness: invocation used `-o surefire:test` (offline provider missing) -> `test`.
- [fix] Harness: added `DatabaseLoaded` (QuorumPeer.loadDataBase) so in-JVM QuorumPeer
  restarts are observed instead of inferred (Trace: update-diff-sync-consistency).
- [fix] Trace: `DbPos(Node)'` primed the trace cursor; replaced by `DbPosNext(Node)`.
- [fix] Trace: ElectionWon reports the winner's zxid (FastLeaderElection.setPeerState), not
  the local one.
- [fix] Trace: leader establishment in the observer applies `LeaderBroadcast` semantics
  (committed/applied := loaded tree).
- [fix] Trace replay configuration: MaxEpoch 4 (update-diff-sync-consistency reaches epoch 4).
- [fix] Trace projection: a stale LEADING server may coexist with a newly elected one before
  the new epoch is proposed; `TraceOneActiveLeaderPerEpoch` attributes a leader to an epoch
  from SYNCHRONIZATION on, and followers follow the most recently elected leader.
- [fix] Trace: Zab1_0Test fixture leader history seeded consistently with the fixture's
  packets; fixture DIFF zxid not validated (fixture-chosen).
- Negative checks: three mutated traces (NEWLEADER ACK with pending buffer, INITIAL-exit
  fast-forwarded tree, non-empty buffer at the post-NEWLEADER COMMIT) are rejected
  (`spec/output/trace-validation/negative-*.log`).
- Archived V0 traces: superseded (old ordering logs after UPTODATE and starts the server
  after UPTODATE); replay of two archived traces stops exactly at that ordering
  (`spec/output/trace-validation/archived/`).

Final full regression (stable candidate): all 7 fresh traces pass `TraceMatched` with natural
completion and zero queued states (`spec/output/trace-validation/final-*.log`).

## Round 2 - Model Checking

- [fix-inv] `PipelinePrefix` (Case A, `spec/output/mc/MC-standard-bfs-r1-caseA.log`, depth 28):
  a learner in SNAP mode persists the leader's not-yet-established tree as its NEWLEADER snapshot
  (Learner.java:739-741 `zk.takeSnapshot`), then crashes; `Crash` retains only the certified
  prefix as visible state, so `snapshot ⊑ applied` fails although nothing is served. The clause
  now constrains RUNNING (serving) servers only; durable/appended/queued/proposed clauses are
  unchanged. Update-full/focused runs started before the revision were stopped and restarted
  (`*-r1-stale-invariant.log`); hunts that do not enable `PipelinePrefix` are unaffected.
- [bug] `LearnerCommit` NPE (MC-1): `Update!NoSyncException` violated
  (`Update-hunt-npe.cfg` depth 34, `Update-hunt-npe-strict.cfg` depth 38).
- [bug] NEWLEADER ACK / currentEpoch before durability (MC-2): `Update!EpochHistoryRecoverable`
  (`Update-hunt-epoch.cfg` depth 30, crash clause) and `Update!NewLeaderAckDurable`
  (`Update-hunt-dur.cfg` depth 38).

## Result

Converged in 2 model-checking rounds (round 1 Case A invariant revision; round 2 standard MC.cfg
no violation within budget) with the full fresh trace suite re-validated on the final artifacts
(`spec/output/trace-validation/regression-final-*.log`). Bug hunting: 3 findings with actual
counterexamples — MC-1 REPRODUCED (update-introduced), MC-2 ENV_LIMITED (pre-existing, narrowed),
MC-3 REPRODUCED (pre-existing class, not fixed by the update). All exploration is budget-limited
(LIMITED_COVERAGE); see `spec/output/mc-summary.md`. Comment-only line-number corrections were
applied to base/Update after the final runs (no semantic change).
