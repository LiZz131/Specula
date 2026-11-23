# Update coverage: output/spec

## Checks never run while an action happens

An action marked *never possible* was never enabled in any state visited by the configs that
enable those checks; *possible* means it was enabled there but not taken within the budget.

| Never checked while | Checks | Names |
|---|---:|---|
| 4 MCEnterBroadcast (never possible) | 1 | `DischargeContext` |

## Actions

| # | Group | Action |
|---:|---|---|
| 1 | AffectedActions | MCReceiveSyncPayload |
| 2 | AffectedActions | MCClearSyncMode |
| 3 | AffectedActions | MCAckNewLeader |
| 4 | AffectedActions | MCEnterBroadcast |

## What each config reached

`x` taken, `e` enabled but not taken, `.` never enabled. Retried configs ran a second, longer pass.

| Config | Status | Traces | Seconds | 1 | 2 | 3 | 4 |
|---|---|---:|---:|---|---|---|---|
| `MC-hunt-election.cfg` | budget used | 29898 | 120.3 | x | x | x | x |
| `MC-hunt-mutation.cfg` | budget used | 30723 | 120.3 | x | x | x | x |
| `MC-hunt-recovery.cfg` | budget used | 28335 | 120.3 | x | x | x | x |
| `MC-hunt-sync.cfg` | budget used | 30685 | 120.2 | x | x | x | x |
| `MC-sim.cfg` | budget used | 15509 | 120.3 | x | x | x | x |
| `MC-small.cfg` | budget used | 31849 | 120.3 | x | x | x | x |
| `MC.cfg` | budget used | 53496 | 120.3 | x | x | x | . |
| `Update-discharge.cfg` | budget used, retried | 169969 | 360.4 | x | x | x | . |
| `Update-focused-ackdurable.cfg` | budget used | 18314 | 120.3 | x | x | x | x |
| `Update-focused-completeness.cfg` | budget used | 17900 | 120.3 | x | x | x | x |
| `Update-focused-quorumdurable.cfg` | budget used | 18573 | 120.2 | x | x | x | x |
| `Update-focused-syncedlog.cfg` | budget used | 18208 | 120.2 | x | x | x | x |
| `Update-focused.cfg` | budget used | 18537 | 120.3 | x | x | x | x |
| `Update-full-sim-completeness.cfg` | budget used | 17721 | 120.2 | x | x | x | x |
| `Update-full-sim-quorum.cfg` | budget used | 15904 | 120.3 | x | x | x | x |
| `Update-full.cfg` | budget used | 15797 | 120.2 | x | x | x | x |
| `Update-hunt-ghost-full.cfg` | budget used | 15492 | 120.3 | x | x | x | x |
| `Update-hunt-ghost.cfg` | budget used | 16537 | 120.3 | x | x | x | x |
| `Update-hunt-postact-crash.cfg` | budget used | 20168 | 120.3 | x | x | x | x |
| `Update-hunt-postact-full.cfg` | budget used | 20108 | 120.3 | x | x | x | x |
| `Update-hunt-postact-leak.cfg` | budget used | 20491 | 120.3 | x | x | x | x |
| `Update-hunt-postact-syncedlog.cfg` | budget used | 20307 | 120.3 | x | x | x | x |
| `Update-open.cfg` | budget used | 17271 | 120.3 | x | x | x | x |
| `Update-reach-activate.cfg` | budget used | 18426 | 120.3 | x | x | x | x |
| `Update-reach-bothacked.cfg` | budget used | 23321 | 120.3 | x | x | x | x |
| `Update-reach-nlack-logged.cfg` | budget used | 18812 | 120.3 | x | x | x | x |
| `Update-reach-recovery-shape.cfg` | budget used | 15361 | 120.3 | x | x | x | x |
| `Update-reach-uptodate.cfg` | budget used | 18154 | 120.3 | x | x | x | x |
| `Update-recovery-full.cfg` | budget used | 17636 | 120.3 | x | x | x | x |
