# Update coverage: output/spec

## Checks never run while an action happens

None: every enabled check runs in a config that reaches every action some config reaches.

Ignored as requested: `ApplyUnreachable`, `CommitUnreachable`, `ElectionUnreachable`, `RecoveryUnreachable`, `SnapshotUnreachable`, `SyncUnreachable`, `UpdLeakUnreachable`, `UpdRejoinUnreachable`, `UpdSnapAbortUnreachable`, `UpdSnapClearUnreachable`, `UpdTruncAbortUnreachable`.

## Actions

| # | Group | Action |
|---:|---|---|
| 1 | AffectedActions | MCLearnerExit |
| 2 | AffectedActions | MCReload |

## What each config reached

`x` taken, `e` enabled but not taken, `.` never enabled. Retried configs ran a second, longer pass.

| Config | Status | Traces | Seconds | 1 | 2 |
|---|---|---:|---:|---|---|
| `MC-apply-hunt.cfg` | budget used | 31834 | 120.5 | e | . |
| `MC-commit-hunt.cfg` | budget used | 33509 | 120.5 | e | . |
| `MC-complete-candidate.cfg` | budget used | 18616 | 120.7 | x | x |
| `MC-core-diagnostic.cfg` | budget used | 2797 | 120.6 | e | . |
| `MC-election-hunt.cfg` | budget used | 16830 | 120.4 | x | x |
| `MC-full.cfg` | budget used | 17643 | 120.5 | x | x |
| `MC-recovery-complete.cfg` | budget used | 26501 | 120.4 | e | . |
| `MC-recovery-hunt.cfg` | budget used | 29636 | 120.6 | e | . |
| `MC-snapshot-complete.cfg` | budget used | 30810 | 120.6 | e | . |
| `MC-snapshot-hunt.cfg` | budget used | 31181 | 120.5 | e | . |
| `MC-sync-hunt.cfg` | budget used | 18668 | 120.4 | x | x |
| `MC-wide.cfg` | budget used | 12977 | 120.4 | x | x |
| `MC.cfg` | budget used | 2532 | 120.5 | e | . |
| `Update-canary-Leak.cfg` | budget used | 9818 | 120.6 | x | x |
| `Update-canary-Rejoin.cfg` | budget used | 20457 | 120.4 | x | x |
| `Update-canary-SnapAbort.cfg` | budget used | 20403 | 120.5 | x | x |
| `Update-canary-SnapClear.cfg` | budget used | 14668 | 120.6 | x | x |
| `Update-canary-TruncAbort.cfg` | budget used | 12667 | 120.5 | x | x |
| `Update-discharge.cfg` | budget used | 11720 | 120.5 | x | x |
| `Update-e2e-snap-new.cfg` | budget used | 1918 | 120.5 | x | x |
| `Update-e2e-snap-old.cfg` | budget used | 1570 | 120.3 | x | . |
| `Update-e2e-trunc-new.cfg` | budget used | 1613 | 120.4 | x | . |
| `Update-focused-old.cfg` | budget used | 5364 | 120.5 | x | . |
| `Update-focused-txn1.cfg` | budget used | 13921 | 120.4 | x | x |
| `Update-focused.cfg` | budget used | 9025 | 120.5 | x | x |
| `Update-full-txn2.cfg` | budget used | 9027 | 120.3 | x | x |
| `Update-full.cfg` | budget used | 11383 | 120.4 | x | x |
| `Update-leak-new.cfg` | budget used | 354 | 120.4 | x | . |
| `Update-leak-old.cfg` | budget used | 335 | 120.4 | x | . |
| `Update-open.cfg` | budget used | 9171 | 120.4 | x | x |
| `Update-snapfix-new.cfg` | budget used | 1553 | 120.3 | x | x |
| `Update-snapfix-old.cfg` | budget used | 1665 | 120.3 | x | . |
