# Brief coverage (incremental, case-002)

Audited against the actual cfg files in `spec/` (final artifacts).

## Scenarios

| Brief scenario | Spec actions/state | Targeting configs | Implementation trace |
|---|---|---|---|
| V0-1 Election/epoch | BeginElection, CastVote, WinElection, FollowLeader, AcceptEpoch, FinishDiscovery, LeaderBroadcast | MC.cfg, MC-hunt-election.cfg | quorum, leader-abandon, diff-sync |
| V0-2 DIFF/TRUNC/SNAP | SelectSync, LeaderQueueNewLeader, Learner* sync actions, EnterBroadcast | MC.cfg, MC-hunt-sync.cfg | follower-snap, follower-diff, diff-sync |
| V0-3 Pipeline/commit/apply | Propose, ReceiveProposal, AppendOne, FsyncOne, DeliverAck, Commit, ReceiveCommit, ApplyOne | MC.cfg, MC-hunt-mutation.cfg | quorum, leader-abandon |
| V0-4 Crash/restart | TakeSnapshot, Crash, Restart, ExitHist | MC.cfg, MC-hunt-recovery.cfg | leader-abandon (DatabaseLoaded), diff-sync |
| U-NPE | LearnerCommit (NPE branch), LearnerLogPending, LearnerAckNewLeader, Outstanding/startForwarding routing | Update-hunt-npe.cfg, Update-hunt-npe-strict.cfg, Update-canary-npe.cfg | update-commit-after-newleader |
| U-DUR | LearnerAckNewLeader vs FsyncOne | Update-hunt-dur.cfg | follower-diff, update-newleader-ack-durability, diff-sync |
| U-EPOCH | LearnerNewLeader, Crash, BeginElection/ExitHist from INITIAL | Update-hunt-epoch.cfg, Update-hunt-epoch-nocrash.cfg | diff-sync |
| U-LOSS | the above + election + LeaderBroadcast | Update-hunt-loss-tight.cfg, Update-hunt-loss-crash-tight.cfg, Update-hunt-loss-sim.cfg | diff-sync (epoch 3 established with stale tree) |

## Properties

| Property | Defined | Enabled in |
|---|---|---|
| TypeOK | base.tla | base.cfg, MC.cfg, Trace.cfg, all Update cfgs |
| MCTypeOK | MC.tla | MC.cfg, Update-full/focused/open.cfg |
| ElectionSafety | base.tla | base.cfg, MC.cfg, Trace.cfg, Update-full/focused/open.cfg |
| OneActiveLeaderPerEpoch | base.tla | base.cfg, MC.cfg, Update-full/focused/open.cfg (Trace.cfg uses TraceOneActiveLeaderPerEpoch projection) |
| CommittedHistoriesPrefix | base.tla | base.cfg, MC.cfg, Trace.cfg, Update-full/focused/open.cfg, Update-hunt-loss-*.cfg |
| ApplyRequiresCommitCertificate | base.tla | base.cfg, MC.cfg, Trace.cfg, Update-full/focused/open.cfg |
| PipelinePrefix (revised clause) | base.tla | base.cfg, MC.cfg, Trace.cfg, Update-full/focused/open.cfg |
| EpochHistoryConsistency | base.tla | base.cfg, MC.cfg, Trace.cfg, Update-full/focused/open.cfg |
| SyncCompletionJustified | base.tla | base.cfg, MC.cfg, Trace.cfg, Update-full/focused/open.cfg |
| HistoryPositionsMonotonicExceptRecovery | base.tla | base.cfg, MC.cfg, Update-full/focused/open.cfg, hunts npe/epoch |
| NoSyncException (new) | Update.tla | Update-full/focused/open.cfg, Update-hunt-npe*.cfg |
| NewLeaderAckDurable (new, update intent) | Update.tla | Update-full/focused/open.cfg, Update-hunt-dur.cfg |
| EpochHistoryRecoverable (revised epoch/history consistency) | Update.tla | Update-full/focused/open.cfg, Update-hunt-epoch*.cfg |
| CommittedNeverLost (interaction) | Update.tla | Update-full/focused/open.cfg, Update-hunt-loss-*.cfg |
| LeaderCompleteness (interaction) | Update.tla | Update-full/focused/open.cfg, Update-hunt-loss-*.cfg |
| DischargeContext | Update.tla | Update-discharge.cfg |
| TraceMatched / TraceOneActiveLeaderPerEpoch | Trace.tla | Trace.cfg |

Reachability canaries (`MC.tla`): NotElectionReached, NotMutationReached, NotRecoveryReached,
NotSyncReached (MC-hunt-*.cfg), NotCommitAfterNewLeaderReached (Update-canary-npe.cfg) — all
violated as expected (witnesses). NoSyncException, NewLeaderAckDurable, EpochHistoryRecoverable
(both clauses) and LeaderCompleteness were violated by actual counterexamples in their targeting
configs (non-vacuous). CommittedNeverLost was not violated within budget: in the found U-LOSS path
LeaderCompleteness fires first (at the establishing step); it remains enabled in the full/focused/
open/loss configs.

## Questions / disposition

| Question | Result |
|---|---|
| V0 Q1-Q4 | re-checked in MC.cfg within budget (see `spec/output/mc-summary.md`) |
| U-NPE | violated (MC-1, REPRODUCED) |
| U-DUR / U-EPOCH | violated (MC-2, ENV_LIMITED) |
| U-LOSS | violated (MC-3, REPRODUCED) |
