# Brief coverage (revision `update`)

Filled from the actual spec/cfg files.

## Scenarios -> artifacts

| Scenario | Actions | Properties | Cfgs | Trace scenario |
|---|---|---|---|---|
| S1 election/epochs (V0) | BeginElection, CastVote, WinElection, FollowLeader, AcceptEpoch, FinishDiscovery | ElectionSafety, OneActiveLeaderPerEpoch, EpochHistoryConsistency | MC.cfg, MC-hunt-election.cfg, Update-*.cfg | all cluster traces (observed projection) |
| S2 DIFF/TRUNC/SNAP (V0, changed) | EnterSyncPhase, SelectSync, CompleteSync, PersistCurrentEpoch, ClearSyncMode, LogSyncProposal, AckNewLeader, CountNewLeaderAck, LeaderBroadcast, ReceiveUpToDate, EnterBroadcast | SyncCompletionJustified, NoIllegalRollback, Upd* | MC.cfg, MC-hunt-sync.cfg, Update-full/focused/open.cfg, Update-hunt-diff-ack*.cfg | follower-diff*, follower-snap, diff-sync-uncommitted-log (TRUNC not exercised) |
| S3 pipeline (V0) | Propose, ReceiveProposal, AppendOne, FsyncOne, DeliverAck, Commit, ReceiveCommit, ObserveCommit, ApplyOne | CommittedHistoriesPrefix, ApplyRequiresCommitCertificate, PipelinePrefix | MC.cfg, MC-hunt-mutation.cfg | quorum-startup-mutation-shutdown, leader-abandon-restart-recovery |
| S4 snapshot/crash/restart (V0) | TakeSnapshot, Crash, Restart | NoIllegalRollback, PipelinePrefix | MC.cfg, MC-hunt-recovery.cfg, Update-hunt-lost-commit.cfg | in-JVM restarts (PeerDatabaseLoaded) |
| U1 NEWLEADER ACK vs durability | CompleteSync(DIFF), ClearSyncMode, LogSyncProposal, AckNewLeader, CountNewLeaderAck, LeaderBroadcast, FsyncOne, Crash | UpdNewLeaderAckAfterDurable, UpdEstablishedHistoryDurableOnQuorum, UpdLeaderCompleteness | Update-hunt-diff-ack.cfg, Update-hunt-diff-ack-followup.cfg, Update-hunt-lost-commit.cfg, Update-full.cfg | follower-diff*, diff-sync-uncommitted-log |
| U2 failure in INITIAL window | ClearSyncMode, AckNewLeader, BeginElection (no drain/fast-forward), CastVote/WinElection on `recovered`, LeaderBroadcast | UpdLeaderCompleteness, CommittedHistoriesPrefix | Update-hunt-lost-commit.cfg, evidence/E3prefix-focus.cfg | diff-sync-uncommitted-log |
| U3 proposal ACK vs NEWLEADER ACK | not modeled (packet order, liveness) | n/a (CR-1) | n/a | probe NewLeaderAckMismatch (0 hits) |

## Properties -> cfg wiring

| Property | Enabled in |
|---|---|
| TypeOK, ElectionSafety, CommittedHistoriesPrefix, ApplyRequiresCommitCertificate, PipelinePrefix, EpochHistoryConsistency, SyncCompletionJustified | base.cfg, MC.cfg, MC-small.cfg, MC-hunt-*.cfg, Update-*.cfg (not canaries), Trace.cfg |
| OneActiveLeaderPerEpoch | base.cfg, MC*.cfg, Update-*.cfg (not Trace.cfg; rationale in Trace.cfg) |
| HistoryPositionsMonotonicExceptRecovery | base.cfg, MC.cfg, MC-small.cfg, Update-full/focused/open/hunt cfgs |
| UpdNewLeaderAckAfterDurable | Update-full.cfg, Update-focused.cfg, Update-open.cfg, Update-hunt-diff-ack.cfg |
| UpdEstablishedHistoryDurableOnQuorum | Update-full/focused/open.cfg, Update-hunt-diff-ack*.cfg |
| UpdLeaderCompleteness | Update-full/focused/open.cfg, Update-hunt-diff-ack*.cfg, Update-hunt-lost-commit.cfg |
| UpdDischarge | Update-discharge.cfg |
| reachability canaries (Not*/UpdNot*) | MC-hunt-*.cfg, Update-canary-*.cfg |

Liveness: none in the brief (prior or update); CR-1 is a liveness concern recorded for code review.
