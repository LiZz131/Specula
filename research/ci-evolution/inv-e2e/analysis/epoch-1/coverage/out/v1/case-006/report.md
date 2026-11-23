# Update coverage: output/spec

## Checks never run while an action happens

None: every enabled check runs in a config that reaches every action some config reaches.

## Actions

| # | Group | Action |
|---:|---|---|
| 1 | AffectedActions | MCHandleHeartbeatResponse |

## What each config reached

`x` taken, `e` enabled but not taken, `.` never enabled. Retried configs ran a second, longer pass.

| Config | Status | Traces | Seconds | 1 |
|---|---|---:|---:|---|
| `MC.cfg` | budget used | 7505 | 120.3 | x |
| `MC_complete_core.cfg` | budget used | 4018 | 120.4 | . |
| `MC_hunt_s1_election.cfg` | budget used | 8897 | 120.4 | . |
| `MC_hunt_s2_replication.cfg` | budget used | 3570 | 120.3 | x |
| `MC_hunt_s3_quorum.cfg` | budget used | 32669 | 120.4 | x |
| `MC_hunt_s4_readindex.cfg` | budget used | 12905 | 120.4 | x |
| `MC_hunt_s5_forwarded_read.cfg` | budget used | 2700 | 120.4 | x |
| `Update_discharge.cfg` | budget used | 4710 | 120.4 | x |
| `Update_discharge_negcontrol.cfg` | budget used | 4382 | 120.4 | x |
| `Update_focused.cfg` | budget used | 2140 | 120.4 | x |
| `Update_focused_reset.cfg` | budget used | 2351 | 120.4 | x |
| `Update_full.cfg` | budget used | 2941 | 120.4 | x |
| `Update_hunt_us4_focused.cfg` | budget used | 2130 | 120.3 | x |
| `Update_hunt_us4_guided.cfg` | budget used | 2323 | 120.4 | x |
| `Update_hunt_us4_sim.cfg` | budget used | 3075 | 120.4 | x |
| `Update_open.cfg` | budget used | 6372 | 120.4 | x |
| `Update_reach_freed.cfg` | budget used | 6984 | 120.2 | x |
| `Update_reach_reenqueue.cfg` | budget used | 6006 | 120.2 | x |
| `Update_reach_reset_drop.cfg` | budget used | 8652 | 120.2 | x |
| `Update_reach_reuse_release.cfg` | budget used | 6134 | 120.2 | x |
