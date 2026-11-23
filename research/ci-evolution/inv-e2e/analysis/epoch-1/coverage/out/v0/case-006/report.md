# Update coverage: output/spec

## Checks never run while an action happens

None: every enabled check runs in a config that reaches every action some config reaches.

## Actions

| # | Group | Action |
|---:|---|---|
| 1 | AffectedHeartbeatResponse | MCHandleHeartbeatResponse |
| 2 | AffectedReadEnqueue | MCClientReadIndex |
| 3 | AffectedReadEnqueue | MCHandleReadIndexRequest |

## What each config reached

`x` taken, `e` enabled but not taken, `.` never enabled. Retried configs ran a second, longer pass.

| Config | Status | Traces | Seconds | 1 | 2 | 3 |
|---|---|---:|---:|---|---|---|
| `MC.cfg` | budget used | 4204 | 120.3 | x | x | x |
| `MC_complete_core.cfg` | budget used | 5218 | 120.3 | . | . | . |
| `MC_hunt_s1_election.cfg` | budget used | 10940 | 120.3 | . | . | . |
| `MC_hunt_s2_replication.cfg` | budget used | 3154 | 120.3 | x | . | . |
| `MC_hunt_s3_quorum.cfg` | budget used | 34376 | 120.3 | x | . | . |
| `MC_hunt_s4_readindex.cfg` | budget used | 20246 | 120.2 | x | x | x |
| `MC_hunt_s5_forwarded_read.cfg` | budget used | 4460 | 120.3 | x | x | x |
| `MC_hunt_s6_linearizable.cfg` | budget used | 3468 | 120.3 | x | x | x |
| `MC_hunt_s6_linearizable_guided.cfg` | budget used | 2980 | 120.3 | x | x | . |
| `MC_hunt_s6_linearizable_guided_noview.cfg` | budget used | 3118 | 120.3 | x | x | . |
| `MC_hunt_s6_linearizable_guided_v2.cfg` | budget used | 2662 | 120.3 | x | x | . |
| `MC_hunt_s6_stale_ack.cfg` | budget used | 6161 | 120.3 | x | x | x |
| `Update_discharge.cfg` | budget used | 6972 | 120.3 | x | x | x |
| `Update_discharge_reach.cfg` | budget used | 6531 | 120.3 | x | x | x |
| `Update_focused.cfg` | budget used | 2158 | 120.3 | x | x | . |
| `Update_focused_nk.cfg` | budget used | 2182 | 120.2 | x | x | . |
| `Update_full.cfg` | budget used | 5233 | 120.6 | x | x | x |
| `Update_full_nk.cfg` | budget used | 5233 | 120.6 | x | x | x |
| `Update_open.cfg` | budget used | 211 | 120.6 | x | . | . |
| `Update_open_nk.cfg` | budget used | 203 | 120.4 | x | . | . |
