# Modeling brief coverage (incremental revision, update 2efbdfc)

## Scenarios

| Brief scenario | Spec actions/state | Bounded MC evidence | Implementation trace (fresh, updated source) |
|---|---|---|---|
| 1 Election/epoch | `BeginElection` … `WinElection`, `FinishDiscovery`, `LeaderBroadcast` | `base.cfg`, `MC.cfg`, `MC-hunt-election.cfg` | quorum, restart/recovery, diff-sync traces |
| 2 DIFF/TRUNC/SNAP | `EnterSyncPhase`, `SelectSync`, `CompleteSync` (buffered payload), `SyncWithLeaderNewLeader`, `SyncWithLeaderUpToDate` | `MC.cfg`, `MC-hunt-sync.cfg`, `MC-hunt-newleader.cfg`, `MC-hunt-uptodate.cfg` | follower-snap, follower-diff, diff-sync |
| 3 Proposal/commit/apply | `Propose`…`ApplyOne` | `MC.cfg`, `MC-hunt-mutation.cfg` | all traces with pipeline events |
| 4 Crash/restart/recovery | `TakeSnapshot`, `Crash`, `Restart` | `MC.cfg`, `MC-hunt-recovery.cfg`, `Update-hunt-loss.cfg` | restart/recovery, diff-sync |
| U1 NEWLEADER logging before ACK | `SyncWithLeaderNewLeader`, `syncBuf`, `nlAcks` | `Update-full/focused/open.cfg`, `MC-hunt-newleader.cfg` canary | follower-diff, diff-sync (`NewLeaderAck`, `ProposalQueued`) |
| U2 ACK-before-fsync window | `SyncWithLeaderNewLeader` → `LeaderBroadcast` → `FsyncOne`/`Crash` | `Update-hunt-durable.cfg`, `Update-hunt-durable-2s.cfg`, `Update-hunt-loss.cfg`, `Update-hunt-loss-witness.cfg` (`UpdateLossFromWitness.tla`), `Update-canary-ackbeforedurable.cfg` | diff-sync events 84-93 |
| U3 learner failure between NEWLEADER and UPTODATE | `BeginElection` keeps the pipeline running | covered for durability only; stale data-tree vote not modeled (CR-2) | diff-sync events 91-103 |
| U4 proposal ACK vs NEWLEADER ACK | not modeled (unordered messages; liveness) | — (CR-3, code review) | probe `NewLeaderAckRejected` (not observed) |

## Properties

| Property | Defined | Enabled |
|---|---|---|
| `TypeOK`, `ElectionSafety`, `OneActiveLeaderPerEpoch`, `CommittedHistoriesPrefix`, `ApplyRequiresCommitCertificate`, `PipelinePrefix`, `EpochHistoryConsistency`, `SyncCompletionJustified` | `base.tla` | `base.cfg`, `MC.cfg`, `MC-small.cfg`, `Trace.cfg`, all `Update-*` safety cfgs |
| `HistoryPositionsMonotonicExceptRecovery` | `base.tla` | `base.cfg`, `MC.cfg`, `MC-small.cfg`, `Update-full/focused/open/hunt-*` |
| `CommittedQuorumDurable` | `Update.tla` | `Update-full.cfg`, `Update-focused.cfg`, `Update-open.cfg`, `Update-hunt-durable.cfg`, `TraceUpdate.cfg` |
| `CommittedNeverLostByLeader` | `Update.tla` | `Update-full/focused/open(-continue).cfg`, `Update-hunt-durable(-2s).cfg`, `Update-hunt-loss.cfg`, `Update-hunt-loss-witness.cfg` |
| `NewLeaderAckAfterLogging` | `Update.tla` | same as above; implementation check in `Trace.tla` (`NewLeaderAck`) |
| `DischargeContext` | `Update.tla` | `Update-discharge.cfg` |
| canaries `Not*Reached` | `MC.tla`, `Update.tla` | `MC-hunt-*.cfg`, `Update-canary-*.cfg` (expected violations) |

Campaign outcomes and coverage limits: `spec/output/mc/campaigns.ndjson`,
`spec/bug-report.md`.
