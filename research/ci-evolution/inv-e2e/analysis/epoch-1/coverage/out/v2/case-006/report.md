# Update coverage: output/spec

## Checks never run while an action happens

None: every enabled check runs in a config that reaches every action some config reaches.

## Actions

| # | Group | Action |
|---:|---|---|
| 1 | AffectedActions | MCHandleHeartbeatResponse |
| 2 | AffectedActions | MCClientReadIndex |
| 3 | AffectedActions | MCHandleReadIndexRequest |
| 4 | AffectedActions | MCHandleReadIndexResponse |

## What each config reached

`x` taken, `e` enabled but not taken, `.` never enabled. Retried configs ran a second, longer pass.

| Config | Status | Traces | Seconds | 1 | 2 | 3 | 4 |
|---|---|---:|---:|---|---|---|---|
| `MC.cfg` | budget used | 4194 | 120.3 | x | . | . | . |
| `MC_complete_core.cfg` | budget used | 4166 | 120.3 | . | . | . | . |
| `MC_hunt_s1_election.cfg` | budget used | 8307 | 120.3 | . | . | . | . |
| `MC_hunt_s2_replication.cfg` | budget used | 2260 | 120.3 | x | . | . | . |
| `MC_hunt_s3_quorum.cfg` | budget used | 26675 | 120.3 | x | . | . | . |
| `MC_hunt_s4_readindex.cfg` | budget used | 19733 | 120.3 | x | x | x | x |
| `MC_hunt_s5_forwarded_read.cfg` | budget used | 4535 | 120.3 | x | x | x | x |
| `Update_discharge.cfg` | budget used | 3605 | 120.3 | x | x | x | x |
| `Update_focused.cfg` | budget used | 4479 | 120.3 | x | x | x | x |
| `Update_focused_rest.cfg` | budget used | 4681 | 120.3 | x | x | x | x |
| `Update_full.cfg` | budget used | 3467 | 120.3 | x | x | x | x |
| `Update_full_rest.cfg` | budget used | 3628 | 120.3 | x | x | x | x |
| `Update_hunt_forwarded.cfg` | budget used | 5960 | 120.3 | x | x | x | x |
| `Update_hunt_forwarded_rest.cfg` | budget used | 5850 | 120.3 | x | x | x | x |
| `Update_hunt_linearizable.cfg` | budget used | 3381 | 120.3 | x | x | x | x |
| `Update_hunt_linearizable_directed.cfg` | budget used | 2439 | 120.3 | x | x | . | . |
| `Update_hunt_stale_ack.cfg` | budget used | 5798 | 120.2 | x | x | x | x |
| `Update_open.cfg` | budget used | 4743 | 120.2 | x | x | x | x |
| `Update_open_rest.cfg` | budget used | 4617 | 120.2 | x | x | x | x |
