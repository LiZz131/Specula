# Modeling brief coverage

This is the standard-path semantic copy of the compatible legacy artifact at
`../brief-coverage.md`, updated for the repaired canonical suite.

## Scenarios

| Brief scenario | Spec actions/state | Canonical bounded evidence | Implementation trace |
|---|---|---|---|
| 1 Election/epoch | `BeginElection` through `LeaderBroadcast` | `base.cfg`, `MC.cfg`, and `MC-hunt-election.cfg` | quorum and restart/recovery traces |
| 2 DIFF/TRUNC/SNAP | `EnterSyncPhase`, `SelectSync`, `CompleteSync` | canonical configs plus `MC-hunt-sync.cfg` | SNAP, DIFF, and restart/recovery traces |
| 3 Proposal/commit/apply | proposal, append, fsync, ACK, commit, apply actions | canonical configs plus `MC-hunt-mutation.cfg` | all retained scenarios with pipeline events |
| 4 Crash/restart/recovery | `TakeSnapshot`, `Crash`, `Restart`, sync repair | canonical configs plus `MC-hunt-recovery.cfg` | abandonment/restart/recovery trace |

## Invariants

| Safety property | Defined | Enabled |
|---|---|---|
| `TypeOK` | `base.tla` | base, MC, trace cfgs |
| `ElectionSafety` | `base.tla` | base, MC, trace cfgs |
| `OneActiveLeaderPerEpoch` | `base.tla` | base, MC, trace cfgs |
| `CommittedHistoriesPrefix` | `base.tla` | base, MC, trace cfgs |
| `ApplyRequiresCommitCertificate` | `base.tla` | base, MC, trace cfgs |
| `PipelinePrefix` | `base.tla` | base, MC, trace cfgs |
| `EpochHistoryConsistency` | `base.tla` | base, MC, trace cfgs |
| `SyncCompletionJustified` | `base.tla` | base, MC, trace cfgs |
| `HistoryPositionsMonotonicExceptRecovery` | `base.tla` | base and MC cfgs |

The canonical base and MC bounds retain three voting servers, majority quorum,
two epochs (including re-election), one complete transaction, one bounded
crash, drop, and snapshot in MC, and exhaustive BFS through TLC level 23. The
fresh terminal suite exhausted 6,354,157 distinct base states and 21,701,056
distinct MC states with zero states left on either queue. That depth exceeds the
preserved depth-22 mutation/apply reachability witness. Pre-existing broader
runs remain preserved as timeout/open-frontier evidence and are not represented
as proof.

## Trace-validation coverage

`Trace.tla` accepts no scenario-name filter. Every retained NDJSON file is run
separately with `TraceMatched` enabled. The trace input assumption checks the
complete event schema; each step checks all five captured state fields (using
documented unknown sentinels) and the event-specific zxid/pipeline position.

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
