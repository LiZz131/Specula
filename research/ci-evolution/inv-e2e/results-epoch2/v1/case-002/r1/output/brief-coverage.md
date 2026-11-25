# Modeling brief coverage

## Scenarios

| Brief scenario | Spec actions/state | Canonical bounded evidence | Implementation trace |
|---|---|---|---|
| 1 Election/epoch | `BeginElection` through `LeaderBroadcast` | `base.cfg`, `MC.cfg`, and election reachability logs | quorum and restart/recovery traces |
| 2 DIFF/TRUNC/SNAP | `EnterSyncPhase`, `SelectSync`, `CompleteSync` | canonical configs plus sync reachability logs | SNAP, DIFF, and restart/recovery traces |
| 3 Proposal/commit/apply | proposal, append, fsync, ACK, commit, apply actions | canonical configs plus mutation reachability logs | all retained scenarios with pipeline events |
| 4 Crash/restart/recovery | `TakeSnapshot`, `Crash`, `Restart`, sync repair | canonical configs plus recovery reachability logs | abandonment/restart/recovery trace |

## Invariants

| Safety property | Defined | Wired | Enabled |
|---|---|---|---|
| `TypeOK` | `base.tla` | inherited by `MC.tla` | `base.cfg`, `MC.cfg`, `Trace.cfg` |
| `ElectionSafety` | `base.tla` | inherited | base, MC, trace cfgs |
| `OneActiveLeaderPerEpoch` | `base.tla` | inherited | base, MC, trace cfgs |
| `CommittedHistoriesPrefix` | `base.tla` | inherited | base, MC, trace cfgs |
| `ApplyRequiresCommitCertificate` | `base.tla` | inherited | base, MC, trace cfgs |
| `PipelinePrefix` | `base.tla` | inherited | base, MC, trace cfgs |
| `EpochHistoryConsistency` | `base.tla` | inherited | base, MC, trace cfgs |
| `SyncCompletionJustified` | `base.tla` | inherited | base, MC, trace cfgs |
| `HistoryPositionsMonotonicExceptRecovery` | `base.tla` | inherited | base and MC cfgs |

## Questions and disposition

| Brief question | Trigger | Expected property | Target/result |
|---|---|---|---|
| Q1 split-brain same epoch | concurrent votes/election | election invariants | checked, no violation in completed bound |
| Q2 unjustified broadcast | split sync actions/modes | sync justification | checked, no violation in completed bound |
| Q3 apply without certificate | processor/message reorderings | apply certificate | checked, no violation in completed bound |
| Q4 illegal rollback | crash/restart/sync replacement | rollback temporal property | checked, no violation in completed bound |

Negative invariants (`NotElectionReached`, `NotSyncReached`,
`NotMutationReached`, `NotRecoveryReached`) were intentionally violated by their
hunt configs. Those counterexamples are reachability evidence, not bugs.

Coverage remains limited by explicit finite constants. The fresh canonical base
and MC models both use three servers, one transaction, two epochs, and level 23;
MC additionally retains one crash, one message drop, and one snapshot. They
naturally exhausted 6,354,157 and 21,701,056 distinct states respectively, with
zero states left on either queue. Broader timeout/open-frontier outputs remain
preserved only as limited evidence.

---

## V1 update coverage (source revision `update`)

### Update Scenarios → artifacts

| Scenario | Reference actions | Update properties | Configs (hunt / full / focused) | Fresh traces | Result |
|---|---|---|---|---|---|
| U1 ACK before durability | `SelectSync`, `FollowerProcessNewLeader`, `FollowerSendNewLeaderAck`, `LeaderProcessNewLeaderAck`, `LeaderBroadcast`, `AppendOne`, `FsyncOne` | P1, P2, P3 | `Update-hunt2s-CertifiedDurableOnQuorum.cfg`, `Update-full-P1/P2.cfg`, `Update-focused-P1/P2.cfg`, `HuntU1-P3-crash.cfg` | follower-diff, follower-diff-bulk-r1..r3, diff-sync-uptodate-failure, repro-u4-*, control-* | MC-1 (counterexamples + reproduction) |
| U2 crash after `setCurrentEpoch` | `FollowerProcessNewLeader`, `Crash`, `Restart`, `CastVote`, `WinElection` | P2, P3 | `HuntU1-P3-crash.cfg` | (crash not in conformance traces; stalled-disk reproduction) | covered by MC-1 |
| U3 txn ACK before NEWLEADER ACK | `FsyncOne` (ackShadowed), `LeaderProcessNewLeaderAck` | P4 | `Update-hunt2s-NewLeaderAckIsFirstAck.cfg`, `Update-full-P4.cfg`, `Update-focused-P4.cfg` | follower-diff-bulk-r1..r3 (not observed) | MC-3 (model only) |
| U4 INITIAL-state exit | `BeginElection` INITIAL branch, `WinElection`, `CastVote` | P5, P3, `PipelinePrefix` | `Update-hunt2s-VotingHistoryCoversDurable.cfg`, `HuntU1-P3.cfg`, `Update-full-P5.cfg`, `MC.cfg` | diff-sync-uptodate-failure, repro-u4-no-restart-r1..r3 | MC-2 (counterexamples + reproduction) |

### Properties (V1)

| Property | Defined | Enabled in |
|---|---|---|
| `NewLeaderAckImpliesDurableSync` (P1) | `UpdateProps.tla` | `Update-full-P1.cfg`, `Update-focused-P1.cfg`, `Update-open.cfg`, `TraceEvidence-*.cfg` |
| `CertifiedDurableOnQuorum` (P2) | `UpdateProps.tla` | `Update-full-P2*.cfg`, `Update-focused-P2*.cfg`, `Update-hunt2s-CertifiedDurableOnQuorum.cfg`, `Update-open.cfg` |
| `CertifiedRetainedByLaterLeaders` (P3) | `UpdateProps.tla` | `Update-full-P3*.cfg`, `Update-focused-P3*.cfg`, `HuntU1-P3*.cfg`, `Update-open.cfg` |
| `NewLeaderAckIsFirstAck` (P4) | `UpdateProps.tla` | `Update-full-P4.cfg`, `Update-focused-P4.cfg`, `Update-hunt2s-NewLeaderAckIsFirstAck.cfg`, `Update-open.cfg` |
| `VotingHistoryCoversDurable` (P5) | `UpdateProps.tla` | `Update-full-P5.cfg`, `Update-focused-P5.cfg`, `Update-hunt2s-VotingHistoryCoversDurable.cfg`, `Update-open.cfg` |
| Reference properties (unchanged text) | `base.tla` | `MC.cfg`, `base.cfg`, `Trace.cfg`, every `Update-*` cfg as controls |

Reachability canaries: `NotUpToDateReached`, `NotNonDurableNewLeaderAckReached`,
`NotAckShadowReached`, `NotInitialExitFlushedReached` (`Update-canary-*.cfg`),
`NotCertifiedLossReached` (`HuntU1-canary-certloss.cfg`), inherited
`MC-hunt-*.cfg`. Open/discharge: `Update-open.cfg`, `Update-discharge.cfg`.
Coverage is finite-bound and budget-limited (see campaign summary).
