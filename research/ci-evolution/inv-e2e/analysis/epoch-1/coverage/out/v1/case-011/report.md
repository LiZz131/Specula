# Update coverage: output/spec

## Checks never run while an action happens

None: every enabled check runs in a config that reaches every action some config reaches.

## Actions

| # | Group | Action |
|---:|---|---|
| 1 | AffectedActions | AffectedStart \/ AffectedDispatch \/ AffectedHandlers |

## What each config reached

`x` taken, `e` enabled but not taken, `.` never enabled. Retried configs ran a second, longer pass.

| Config | Status | Traces | Seconds | 1 |
|---|---|---:|---:|---|
| `MC-membership.cfg` | budget used | 3104 | 120.3 | x |
| `MC.cfg` | budget used | 2238 | 120.3 | x |
| `Update-discharge-membership.cfg` | budget used | 2862 | 120.3 | x |
| `Update-discharge.cfg` | budget used | 2230 | 120.3 | x |
| `Update-focus-noU4.cfg` | budget used | 8832 | 120.3 | x |
| `Update-focus.cfg` | budget used | 7975 | 120.3 | x |
| `Update-full-U4.cfg` | budget used | 2205 | 120.3 | x |
| `Update-full-noU4.cfg` | budget used | 1922 | 120.3 | x |
| `Update-full.cfg` | budget used | 2114 | 120.3 | x |
| `Update-hunt-next-term.cfg` | budget used | 1973 | 120.3 | x |
| `Update-hunt-stale-precandidate.cfg` | budget used | 2073 | 120.3 | x |
| `Update-open-noU4.cfg` | budget used | 8833 | 120.3 | x |
| `Update-open.cfg` | budget used | 9907 | 120.3 | x |
