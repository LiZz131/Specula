# Update coverage: output/spec

## Checks never run while an action happens

None: every enabled check runs in a config that reaches every action some config reaches.

Ignored as requested: `CanaryNoInMemorySyncCommitSnap`, `CanaryNoReloadAfterClear`, `CanaryNoSnapAbort`, `CanaryNoTruncAbortMemoryOnly`.

## Actions

| # | Group | Action |
|---:|---|---|
| 1 | AffectedActions | MCLearnerShutdown |

## What each config reached

`x` taken, `e` enabled but not taken, `.` never enabled. Retried configs ran a second, longer pass.

| Config | Status | Traces | Seconds | 1 |
|---|---|---:|---:|---|
| `MC-apply-hunt.cfg` | budget used | 18840 | 120.4 | x |
| `MC-commit-hunt.cfg` | budget used | 17331 | 120.4 | x |
| `MC-election-hunt.cfg` | budget used | 21734 | 120.4 | x |
| `MC-full.cfg` | budget used | 11453 | 120.4 | x |
| `MC-recovery-hunt.cfg` | budget used | 17204 | 120.4 | x |
| `MC-snapshot-hunt.cfg` | budget used | 19466 | 120.4 | x |
| `MC-sync-hunt.cfg` | budget used | 19039 | 120.4 | x |
| `MC-wide.cfg` | budget used | 9940 | 120.4 | x |
| `MC.cfg` | budget used | 11992 | 120.4 | x |
| `Update-canary-diffabort.cfg` | budget used | 18438 | 120.4 | x |
| `Update-canary-diffwindow-steered2.cfg` | budget used | 5562 | 120.3 | x |
| `Update-canary-reload.cfg` | budget used | 19541 | 120.3 | x |
| `Update-canary-snapabort.cfg` | budget used | 20192 | 120.4 | x |
| `Update-canary-snapcommit.cfg` | budget used | 14104 | 120.4 | x |
| `Update-canary-snaponly-steered-reload.cfg` | budget used | 19804 | 120.4 | x |
| `Update-canary-snaponly-steered-snapcommit.cfg` | budget used | 17776 | 120.4 | x |
| `Update-canary-trunc-steered2.cfg` | budget used | 5114 | 120.3 | x |
| `Update-canary-truncabort.cfg` | budget used | 15679 | 120.2 | x |
| `Update-continue-mc1-consequence.cfg` | budget used | 7842 | 120.3 | . |
| `Update-discharge.cfg` | budget used | 13417 | 120.3 | x |
| `Update-focused.cfg` | budget used | 16630 | 120.3 | x |
| `Update-full.cfg` | budget used | 14683 | 120.3 | x |
| `Update-hunt-diffwindow-steered.cfg` | budget used | 8520 | 120.3 | x |
| `Update-hunt-diffwindow-steered2.cfg` | budget used | 8042 | 120.3 | x |
| `Update-hunt-diffwindow.cfg` | budget used | 15087 | 120.4 | x |
| `Update-hunt-mc1-deterministic.cfg` | budget used | 24096 | 120.3 | x |
| `Update-hunt-mc2-leadercompleteness.cfg` | budget used | 4985 | 120.3 | x |
| `Update-hunt-snap-oldcontrol.cfg` | budget used | 24022 | 120.3 | x |
| `Update-hunt-snap-only-steered-consequence.cfg` | budget used | 14942 | 120.3 | x |
| `Update-hunt-snap-only-steered.cfg` | budget used | 25370 | 120.3 | x |
| `Update-hunt-snap-steered-oldcontrol-consequence.cfg` | budget used | 23707 | 120.3 | x |
| `Update-hunt-snap-steered-oldcontrol.cfg` | budget used | 21423 | 120.3 | x |
| `Update-hunt-snap-steered.cfg` | budget used | 18760 | 120.2 | x |
| `Update-hunt-snap.cfg` | budget used | 25252 | 120.3 | x |
| `Update-hunt-trunc-steered.cfg` | budget used | 4546 | 120.3 | x |
| `Update-hunt-trunc-steered2.cfg` | budget used | 3881 | 120.3 | x |
| `Update-hunt-trunc.cfg` | budget used | 13691 | 120.2 | x |
| `Update-hunt-trunclog-consequence-steered.cfg` | budget used | 8249 | 120.3 | x |
| `Update-hunt-trunclog-steered.cfg` | budget used | 13860 | 120.3 | x |
| `Update-open.cfg` | budget used | 307 | 120.2 | x |
| `Update-smoke.cfg` | budget used | 13891 | 120.2 | x |
