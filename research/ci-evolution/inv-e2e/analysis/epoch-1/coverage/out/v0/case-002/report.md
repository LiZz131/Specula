# Update coverage: output/spec

## Checks never run while an action happens

An action marked *never possible* was never enabled in any state visited by the configs that
enable those checks; *possible* means it was enabled there but not taken within the budget.

| Never checked while | Checks | Names |
|---|---:|---|
| 3 MCLearnerLogPending (never possible); 7 MCLearnerCommitAfterUpToDate (never possible); 8 MCLearnerAbort (never possible) | 4 | `NotElectionReached`, `NotMutationReached`, `NotRecoveryReached`, `NotSyncReached` |

## Actions

| # | Group | Action |
|---:|---|---|
| 1 | AffectedActions | MCLearnerNewLeader |
| 2 | AffectedActions | MCLearnerStartupWithoutServing |
| 3 | AffectedActions | MCLearnerLogPending |
| 4 | AffectedActions | MCLearnerAckNewLeader |
| 5 | AffectedActions | MCLearnerUpToDate |
| 6 | AffectedActions | MCLearnerLogAfterUpToDate |
| 7 | AffectedActions | MCLearnerCommitAfterUpToDate |
| 8 | AffectedActions | MCLearnerAbort |
| 9 | AffectedActions | MCBeginElection |

## What each config reached

`x` taken, `e` enabled but not taken, `.` never enabled. Retried configs ran a second, longer pass.

| Config | Status | Traces | Seconds | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 |
|---|---|---:|---:|---|---|---|---|---|---|---|---|---|
| `MC-hunt-election.cfg` | budget used, retried | 15760 | 360.4 | x | x | . | x | x | x | . | . | x |
| `MC-hunt-mutation.cfg` | budget used, retried | 15811 | 360.4 | x | x | . | x | x | x | . | . | x |
| `MC-hunt-recovery.cfg` | budget used, retried | 13553 | 360.4 | x | x | . | x | x | x | . | . | x |
| `MC-hunt-sync.cfg` | budget used, retried | 15895 | 360.4 | x | x | . | x | x | x | . | . | x |
| `MC.cfg` | budget used | 1592 | 120.2 | x | x | x | x | x | x | x | x | x |
| `Update-canary-npe.cfg` | budget used | 1369 | 120.3 | x | x | x | x | x | x | x | x | x |
| `Update-discharge.cfg` | budget used | 1502 | 120.3 | x | x | x | x | x | x | x | x | x |
| `Update-focused.cfg` | budget used | 1474 | 120.3 | x | x | x | x | x | x | x | x | x |
| `Update-full.cfg` | budget used | 1504 | 120.3 | x | x | x | x | x | x | x | x | x |
| `Update-hunt-dur.cfg` | budget used | 1352 | 120.3 | x | x | x | x | x | x | x | x | x |
| `Update-hunt-epoch-nocrash.cfg` | budget used | 716 | 120.3 | x | x | . | x | x | x | . | . | x |
| `Update-hunt-epoch.cfg` | budget used | 779 | 120.3 | x | x | . | x | x | x | . | . | x |
| `Update-hunt-loss-crash-tight.cfg` | budget used | 710 | 120.3 | x | x | . | x | x | . | . | . | x |
| `Update-hunt-loss-crash.cfg` | budget used | 743 | 120.3 | x | x | x | x | x | x | . | . | x |
| `Update-hunt-loss-nocrash.cfg` | budget used | 712 | 120.3 | x | x | . | x | x | x | . | . | x |
| `Update-hunt-loss-sim.cfg` | budget used | 686 | 120.3 | x | x | . | x | x | . | . | . | x |
| `Update-hunt-loss-tight.cfg` | budget used | 764 | 120.3 | x | x | . | x | x | x | . | . | x |
| `Update-hunt-npe-strict.cfg` | budget used | 1310 | 120.3 | x | x | x | x | x | x | x | x | x |
| `Update-hunt-npe.cfg` | budget used | 1345 | 120.3 | x | x | x | x | x | x | x | x | x |
| `Update-open.cfg` | budget used | 1121 | 120.3 | x | x | x | x | x | x | . | . | x |
