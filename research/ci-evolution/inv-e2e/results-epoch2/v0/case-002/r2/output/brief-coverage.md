# Brief coverage (updated suite, run incr-13b3a238967b)

Prior V0 coverage table preserved in `spec/brief-coverage.md` history; this
table maps the updated scope, update Scenarios and properties to artifacts.

## Scope / baseline behavior -> spec

| Scope item | Reference Actions (base.tla) | Configs |
|---|---|---|
| Election, epoch proposal, discovery | CastVote, ElectLeader, ElectFollow, LeaderProposeEpoch, AcceptEpoch, FinishDiscovery, EnterSyncPhase | MC.cfg, Update-full.cfg, Canary-NotLeaderReached/NotReelectReached |
| DIFF/TRUNC/SNAP sync stream | LeaderSyncFollower, LeaderSendNewLeader, LearnerReadMode, LearnerSyncProposal, LearnerSyncCommit | Canary-NotDiff/NotTrunc/NotSnapReached, Update-focused.cfg |
| NEWLEADER / UPTODATE (updated) | LearnerNewLeader, LearnerAckNewLeader, LeaderReadNewLeaderAck, LeaderBroadcast, LeaderSendUpToDate, LearnerUpToDate, EnterBroadcast | Update-*.cfg |
| Broadcast pipeline | Propose, ReceiveProposal, AppendOne, FsyncOne, LeaderProcessAck, Commit, ReceiveCommit, ApplyOne | MC.cfg, Canary-NotMutationReached |
| Crash / restart / role exit | Crash, Restart, BeginElection (RoleExit incl. INITIAL leak) | MC.cfg, Update-hunt-durability.cfg, Canary-NotRecoveryReached |

## Properties -> enabled configs

| Property | Kind | Enabled in |
|---|---|---|
| TypeOK, MCTypeOK | structural | all MC/Update cfgs, Trace.cfg |
| ElectionSafety, OneActiveLeaderPerEpoch (revised) | safety | MC.cfg, Update-*.cfg, Trace.cfg |
| CommittedHistoriesPrefix | safety | MC.cfg, Update-*.cfg, Trace.cfg |
| CommittedAgreement (new, reference) | safety | MC.cfg, Update-*.cfg, Trace.cfg |
| ApplyRequiresCommitCertificate, PipelinePrefix, EpochHistoryConsistency, SyncCompletionJustified | safety | MC.cfg, Update-*.cfg, Trace.cfg |
| HistoryPositionsMonotonicExceptRecovery | action property | MC.cfg, base.cfg |
| CommittedQuorumDurable (U1) | update safety | Update-full/focused/open.cfg, Update-hunt-durability.cfg |
| NewLeaderAckFirst (U2) | update interaction | Update-full/focused/open.cfg, Update-hunt-ackorder.cfg |
| SyncCommitHasPendingProposal (U3) | update interaction | Update-full/focused/open.cfg, Update-hunt-npe.cfg |
| DeferredCommitMatchesPending (U4) | update interaction | Update-full/focused/open.cfg, Update-hunt-split.cfg |
| DischargeContext | rely/frame obligation | Update-discharge.cfg |

## Update Scenarios -> hunts and witnesses

| Scenario | Hunt cfg | Reachability canary |
|---|---|---|
| U-DUR | Update-hunt-durability.cfg, Update-hunt-agreement.cfg | Canary-NotNlLoggedReached, Canary-NotUpdateDurabilityGap |
| U-ACK | Update-hunt-ackorder.cfg | Canary-NotAckBeforeNlAckReached |
| U-NPE | Update-hunt-npe.cfg | Canary-NotCommitAfterNlReached |
| U-SPLIT | Update-hunt-split.cfg | Canary-NotFollowerBroadcastReached |
| U-LEAK | CR only (D-5); modeled history effect only | trace evidence |

Excluded (unchanged from V0): observers, dynamic reconfiguration, sessions/ACL
payloads, wire framing, metrics; additionally the pre-Zab1.0 UPTODATE-only
path (D-4, legacy protocol).
