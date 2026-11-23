# Update coverage: output/spec

## Checks never run while an action happens

An action marked *never possible* was never enabled in any state visited by the configs that
enable those checks; *possible* means it was enabled there but not taken within the budget.

| Never checked while | Checks | Names |
|---|---:|---|
| 1 MCLearnerExit (possible); 2 MCLearnerExitLeaderGone (never possible); 3 MCReloadDatabase (never possible) | 2 | `MonotoneUnlessRecoveryV1`, `OrderedHistories` |

Ignored as requested: `ApplyUnreachable`, `CommitUnreachable`, `DiffAfterSnapReloadUnreachable`, `ElectionUnreachable`, `LeakedFlushAfterResyncUnreachable`, `RecoveryUnreachable`, `ReloadAfterSnapExitUnreachable`, `ServingExitUnreachable`, `SnapExitThenCommittedRecoverableUnreachable`, `SnapExitUnpersistedUnreachable`, `SnapshotUnreachable`, `SteadyStateUnreachable`, `SyncUnreachable`, `TruncExitUnpersistedUnreachable`.

## Actions

| # | Group | Action |
|---:|---|---|
| 1 | AffectedActions | MCLearnerExit |
| 2 | AffectedActions | MCLearnerExitLeaderGone |
| 3 | AffectedActions | MCReloadDatabase |

## What each config reached

`x` taken, `e` enabled but not taken, `.` never enabled. Retried configs ran a second, longer pass.

| Config | Status | Traces | Seconds | 1 | 2 | 3 |
|---|---|---:|---:|---|---|---|
| `MC-apply-hunt.cfg` | budget used | 21165 | 120.2 | e | . | . |
| `MC-commit-hunt.cfg` | budget used | 25359 | 120.2 | e | . | . |
| `MC-election-hunt.cfg` | budget used | 12023 | 120.2 | x | x | x |
| `MC-full.cfg` | budget used | 16563 | 120.2 | x | x | x |
| `MC-recovery-complete.cfg` | budget used | 15878 | 120.2 | e | x | . |
| `MC-recovery-hunt.cfg` | budget used | 21413 | 120.2 | e | x | . |
| `MC-snapshot-complete.cfg` | budget used | 23995 | 120.3 | e | . | . |
| `MC-snapshot-hunt.cfg` | budget used | 21042 | 120.2 | e | . | . |
| `MC-sync-hunt.cfg` | budget used | 15795 | 120.2 | x | x | x |
| `MC.cfg` | budget used, retried | 11927 | 360.3 | e | . | . |
| `Update-canary-diffreload.cfg` | budget used | 10703 | 120.3 | x | . | x |
| `Update-canary-leakedflush.cfg` | budget used | 15849 | 120.2 | x | . | . |
| `Update-canary-reload.cfg` | budget used | 10077 | 120.2 | x | . | x |
| `Update-canary-servingexit.cfg` | budget used | 14840 | 120.2 | x | . | . |
| `Update-canary-snapcommit.cfg` | budget used | 10405 | 120.2 | x | . | x |
| `Update-canary-snapexit.cfg` | budget used | 9981 | 120.2 | x | . | x |
| `Update-canary-steady.cfg` | budget used | 6085 | 120.2 | . | . | . |
| `Update-canary-truncexit.cfg` | budget used | 14808 | 120.3 | x | . | x |
| `Update-control-prior-gap.cfg` | budget used | 21594 | 120.3 | x | . | . |
| `Update-control-prior-leak-gap.cfg` | budget used | 23757 | 120.2 | x | . | . |
| `Update-control-prior-leak-prefix.cfg` | budget used | 24444 | 120.3 | x | . | . |
| `Update-control-prior-leak.cfg` | budget used | 23616 | 120.3 | x | . | . |
| `Update-control-prior-trunc-noleak-gap.cfg` | budget used | 20966 | 120.3 | x | . | . |
| `Update-control-prior-trunc.cfg` | budget used | 20972 | 120.3 | x | . | . |
| `Update-control-prior.cfg` | budget used | 17217 | 120.3 | x | . | . |
| `Update-discharge.cfg` | budget used | 15439 | 120.2 | x | x | x |
| `Update-focused-residual.cfg` | budget used | 34442 | 120.3 | x | x | x |
| `Update-focused.cfg` | budget used | 22290 | 120.2 | x | x | x |
| `Update-full-residual.cfg` | budget used | 14739 | 120.3 | x | x | x |
| `Update-full.cfg` | budget used | 15605 | 120.3 | x | x | x |
| `Update-hunt-leak-gap.cfg` | budget used | 15417 | 120.3 | x | . | . |
| `Update-hunt-leak-order.cfg` | budget used | 17949 | 120.3 | x | . | . |
| `Update-hunt-leak-prefix.cfg` | budget used | 19989 | 120.4 | x | . | . |
| `Update-hunt-leak.cfg` | budget used | 22066 | 120.3 | x | . | . |
| `Update-hunt-snap.cfg` | budget used | 22384 | 120.3 | x | . | x |
| `Update-hunt-trunc-gap.cfg` | budget used | 21488 | 120.3 | x | . | x |
| `Update-hunt-trunc-noleak-gap.cfg` | budget used | 20796 | 120.3 | x | . | x |
| `Update-hunt-trunc-noleak.cfg` | budget used | 20891 | 120.3 | x | . | x |
| `Update-hunt-trunc.cfg` | budget used | 21260 | 120.3 | x | . | x |
| `Update-open-residual.cfg` | budget used | 9109 | 120.3 | x | x | x |
| `Update-open.cfg` | budget used | 9971 | 120.2 | x | x | x |
