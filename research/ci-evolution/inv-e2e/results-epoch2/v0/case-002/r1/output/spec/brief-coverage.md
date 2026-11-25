# Brief coverage (incremental)

Read from the actual spec/cfg files of this run.

## Update scenarios → artifacts
| Scenario | Model actions (base/MC) | Properties | Configs (where enabled) | Reachability evidence |
|---|---|---|---|---|
| U-1 ACK vs durability | `SyncWithLeader`, `LearnerNewLeaderPersist`, `LearnerNewLeaderStartup`, `LearnerLogPendingOne`, `LearnerSendNewLeaderAck`, `AppendOne`, `FsyncOne`, `Crash`, `Restart`, `LeaderStartZkServer` | U3 `NewLeaderAckImpliesDurable`, U4, U1 | `Update-full.cfg`, `Update-focus.cfg`, `Update-open.cfg`, `Update-hunt-crash-window.cfg` | canary `NotPendingLoggedAcked` (`mc-final-canary-ack-window`); cex MC-1 |
| U-2 skipped shutdown | `ServerShutdown`, `CastVote`, `WinElection`, `SyncWithLeader` | U4 `AckedHistoryRetained`, U1, U2 | `Update-*-consequence.cfg`, `Update-*-completeness.cfg`, `Update-hunt-reelection.cfg` | canary `NotSkippedShutdownAfterAck` (`mc-final-canary-skipped-shutdown`); cex MC-2 |
| U-3 UPTODATE path | `LearnerUptodateStartServing`, `LearnerUptodateLogOne`, `LearnerUptodateCommitOne`, `LearnerEnterBroadcast`, `ReceiveProposal`/`ReceiveCommit` (sync), `ApplyOne` | `ServingApplyRequiresCommitCertificate`, `SyncCompletionJustified`, `CommittedHistoriesPrefix`, U2 | `MC.cfg`, all Update cfgs | canary `NotUptodateAfterLogging` (`mc-final-canary-uptodate`) |
| U-4 restart path (test) | `Crash`, `Restart`, elections | U1 | `Update-full*.cfg` | trace `diff-sync-uptodate-failure` (U1 holds along it) |

## Inherited V0 scenarios
| Scenario | Configs | Canary |
|---|---|---|
| 1 Election/epochs | `MC.cfg`, `MC-hunt-election.cfg` | `NotElectionReached` reached |
| 2 DIFF/TRUNC/SNAP | `MC.cfg`, `MC-hunt-sync.cfg`, `Update-focus-trunc.cfg` | `NotSyncReached` reached; cex MC-3 |
| 3 Pipeline | `MC.cfg`, `MC-hunt-mutation.cfg` | `NotMutationReached` reached (simulation) |
| 4 Recovery | `MC.cfg`, `MC-hunt-recovery.cfg` | `NotRecoveryReached` reached |

## Properties → cfgs
| Property | Defined in | Enabled in |
|---|---|---|
| TypeOK, ElectionSafety, OneActiveLeaderPerEpoch (refined), CommittedHistoriesPrefix, ServingApplyRequiresCommitCertificate (revised), PipelinePrefix (revised), EpochHistoryConsistency, SyncCompletionJustified | base.tla | base.cfg, MC.cfg, MC-hunt-*.cfg, Update-*.cfg (ServingApply... disabled only in hunts that filter MC-3), Trace.cfg |
| HistoryPositionsMonotonicExceptRecovery | base.tla | base.cfg, MC.cfg, Update-full*.cfg |
| U1 LeaderCompleteness | Update.tla | Update-full/-focus/-open(-consequence/-completeness), Update-hunt-reelection/-crash-window, TraceUpdateCheck-LeaderCompleteness.cfg |
| U2 CommittedAgreesWithQuorumHistory | Update.tla | same as U1 |
| U3 NewLeaderAckImpliesDurable | Update.tla | Update-full.cfg, Update-focus.cfg, Update-open.cfg, Update-full-checkpoint.cfg, TraceUpdateCheck-… |
| U4 AckedHistoryRetained | Update.tla | Update-*.cfg and Update-*-consequence.cfg, TraceUpdateCheck-… |
| UpdateStructural | Update.tla | all Update cfgs except canaries |
| DischargeContext | Update.tla | Update-discharge.cfg |

## Scope guidance
Required scope items (roles/phases, epochs, quorum, DIFF/TRUNC/SNAP, durable/committed/applied,
snapshots, crash/restart/re-election, independently scheduled SyncRequestProcessor/
CommitProcessor) are represented in base.tla; Observers/reconfig remain excluded
(modeling-brief.md "Exclusions").
