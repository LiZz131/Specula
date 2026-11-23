# Update coverage: output/spec

## Checks never run while an action happens

None: every enabled check runs in a config that reaches every action some config reaches.

## Actions

| # | Group | Action |
|---:|---|---|
| 1 | PreElectAction | MCTickPreElect |
| 2 | PreElectAction | MCExternalPreElect |
| 3 | TickElectAction | MCTickElect |
| 4 | TickElectAction | MCExternalElect |
| 5 | HandlePreVoteRequestAction | DeliverPreVoteRequest |
| 6 | HandlePreVoteResponseAction | DeliverPreVoteResponse |

## What each config reached

`x` taken, `e` enabled but not taken, `.` never enabled. Retried configs ran a second, longer pass.

| Config | Status | Traces | Seconds | 1 | 2 | 3 | 4 | 5 | 6 |
|---|---|---:|---:|---|---|---|---|---|---|
| `MC-membership.cfg` | budget used | 2308 | 120.4 | . | x | x | x | x | x |
| `MC.cfg` | budget used | 1460 | 120.3 | x | x | x | x | x | x |
| `MC_hunt_U2_prevote_leader.cfg` | budget used | 1180 | 120.3 | x | x | . | x | x | x |
| `MC_hunt_U4_prevote_stale_round.cfg` | budget used | 1283 | 120.3 | x | x | . | x | x | x |
| `MC_hunt_U4b_prevote_panic.cfg` | budget used | 1171 | 120.4 | x | x | . | x | x | x |
| `MC_hunt_U4c_prevote_panic_operator.cfg` | budget used | 1208 | 120.4 | . | x | x | x | x | x |
| `MC_hunt_U5_prevote_fallback.cfg` | budget used | 1544 | 120.4 | x | x | x | x | x | x |
| `Update-discharge.cfg` | budget used | 1329 | 120.4 | x | x | x | x | x | x |
| `Update-focused-residual.cfg` | budget used | 4592 | 120.4 | x | x | . | x | x | x |
| `Update-focused.cfg` | budget used | 4364 | 120.3 | x | x | . | x | x | x |
| `Update-full-U2.cfg` | budget used | 1096 | 120.3 | x | x | x | x | x | x |
| `Update-open-residual.cfg` | budget used | 2479 | 120.4 | x | x | . | x | x | x |
| `Update-open.cfg` | budget used | 2951 | 120.4 | x | x | . | x | x | x |
| `Update-residual.cfg` | budget used | 1468 | 120.4 | x | x | x | x | x | x |
| `Update.cfg` | budget used | 1312 | 120.3 | x | x | x | x | x | x |
