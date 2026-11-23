# Update coverage: output/spec

## Checks never run while an action happens

An action marked *never possible* was never enabled in any state visited by the configs that
enable those checks; *possible* means it was enabled there but not taken within the budget.

| Never checked while | Checks | Names |
|---|---:|---|
| 4 MCLogSyncProposal (never possible); 6 MCStartServing (never possible) | 11 | `CommittedHistoriesPrefix`, `DischargeContext`, `ElectionSafety`, `EpochHistoryConsistency`, `HistoryPositionsMonotonicExceptRecovery`, `MCTypeOK`, `OneActiveLeaderPerEpoch`, `PipelinePrefix`, `ServingApplyCommitted`, `StructuralInvariants`, `SyncCompletionJustified` |

Ignored as requested: `CanaryActivationCommitsOldEpoch`, `CanaryCommittedApplied`, `CanaryDiffAckBeforeFsync`, `CanaryFocusInitExact`, `CanaryFocusInitShape`, `CanaryFollowerBroadcast`, `CanaryLeaderActive`, `CanaryLeaderEstablished`, `CanaryRecovery`, `CanarySnap`, `CanarySync`, `CanaryTrunc`.

## Actions

| # | Group | Action |
|---:|---|---|
| 1 | AffectedActions | MCPersistCurrentEpoch |
| 2 | AffectedActions | MCClearSyncMode |
| 3 | AffectedActions | MCStartupWithoutServing |
| 4 | AffectedActions | MCLogSyncProposal |
| 5 | AffectedActions | MCSendNewLeaderAck |
| 6 | AffectedActions | MCStartServing |

## What each config reached

`x` taken, `e` enabled but not taken, `.` never enabled. Retried configs ran a second, longer pass.

| Config | Status | Traces | Seconds | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---:|---:|---|---|---|---|---|---|
| `MC-canary-CanaryActivationCommitsOldEpoch.cfg` | budget used | 14805 | 120.3 | x | x | x | . | x | . |
| `MC-canary-CanaryCommittedApplied.cfg` | budget used | 12472 | 120.3 | x | x | x | . | x | . |
| `MC-canary-CanaryDiffAckBeforeFsync.cfg` | budget used | 12890 | 120.4 | x | x | x | . | x | . |
| `MC-canary-CanaryFollowerBroadcast.cfg` | budget used | 14895 | 120.4 | x | x | x | . | x | . |
| `MC-canary-CanaryLeaderActive.cfg` | budget used | 14254 | 120.4 | x | x | x | . | x | . |
| `MC-canary-CanaryLeaderEstablished.cfg` | budget used | 16454 | 120.4 | x | x | x | . | x | . |
| `MC-canary-CanaryRecovery.cfg` | budget used | 15162 | 120.4 | x | x | x | . | x | . |
| `MC-canary-CanarySnap.cfg` | budget used | 14035 | 120.3 | x | x | x | . | x | . |
| `MC-canary-CanarySync.cfg` | budget used | 13526 | 120.3 | x | x | x | . | x | . |
| `MC-canary-CanaryTrunc-tight.cfg` | budget used | 13922 | 120.4 | x | x | x | . | x | . |
| `MC-canary-CanaryTrunc.cfg` | budget used | 15897 | 120.4 | x | x | x | . | x | . |
| `MC-hunt-election.cfg` | budget used, retried | 56315 | 360.5 | x | x | x | . | x | . |
| `MC-hunt-mutation.cfg` | budget used, retried | 57742 | 360.7 | x | x | x | . | x | . |
| `MC-hunt-recovery.cfg` | budget used, retried | 55184 | 360.6 | x | x | x | . | x | . |
| `MC-hunt-sync.cfg` | budget used, retried | 55391 | 360.6 | x | x | x | . | x | . |
| `MC.cfg` | budget used, retried | 84525 | 360.6 | x | x | x | . | x | . |
| `Update-concrete-A2.cfg` | budget used | 22519 | 120.2 | x | x | x | x | x | e |
| `Update-concrete.cfg` | budget used, retried | 67067 | 360.5 | x | x | x | x | x | e |
| `Update-concrete2-A2-crash.cfg` | budget used | 22719 | 120.2 | x | x | x | x | x | x |
| `Update-concrete2-A2.cfg` | budget used | 26771 | 120.2 | x | x | x | x | x | x |
| `Update-discharge.cfg` | budget used, retried | 96304 | 360.5 | x | x | x | . | x | . |
| `Update-full-focusinit.cfg` | budget used, retried | 68093 | 360.5 | x | x | x | x | x | x |
| `Update-full.cfg` | budget used, retried | 62597 | 360.6 | x | x | x | . | x | . |
| `Update-open.cfg` | budget used, retried | 65729 | 360.4 | x | x | x | x | x | e |
| `Update-reach-focusinit-exact.cfg` | budget used | 21569 | 120.2 | x | x | x | . | x | . |
| `Update-reach-focusinit.cfg` | budget used | 21873 | 120.2 | x | x | x | . | x | . |
