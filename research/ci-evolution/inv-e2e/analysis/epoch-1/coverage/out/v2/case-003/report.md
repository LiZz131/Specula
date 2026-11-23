# Update coverage: output/spec

## Checks never run while an action happens

None: every enabled check runs in a config that reaches every action some config reaches.

Ignored as requested: `NeverReachedAcceptedUpdate`, `NeverReachedAppOnlyReplay`, `NeverReachedCrash`, `NeverReachedHandshakeComplete`, `NeverReachedMockReplay`, `NeverReachedRealReplay`, `NeverReachedRejectedUpdate`, `NeverReachedVEAcceptRow1`, `NeverReachedVEAcceptRow3`, `NeverReachedVEAcceptRow5`, `NeverReachedVEAcceptRow7`, `NeverReachedVEAcceptRow9`, `NeverReachedVEEnabledBlock`, `NeverReachedVERejectBasic`, `NeverReachedVERejectIdentity`, `NeverReachedVERejectRow4`, `NeverReachedVERejectRow6`, `NeverReachedVERejectRow8`, `NeverReachedVEUpdateMockReplay`, `NeverReachedVEUpdateRealReplay`.

## Actions

| # | Group | Action |
|---:|---|---|
| 1 | AffectedActions | MCUpdateStateAccepted |
| 2 | AffectedActions | MCUpdateStateRejected |

## What each config reached

`x` taken, `e` enabled but not taken, `.` never enabled. Retried configs ran a second, longer pass.

| Config | Status | Traces | Seconds | 1 | 2 |
|---|---|---:|---:|---|---|
| `MC.cfg` | budget used | 92392 | 120.3 | x | x |
| `MC_hunt_scenario1_params.cfg` | budget used | 98871 | 120.3 | x | x |
| `MC_hunt_scenario2_durability.cfg` | budget used | 121584 | 120.3 | x | x |
| `MC_hunt_scenario3_recovery.cfg` | budget used | 115560 | 120.3 | x | x |
| `MC_reach_accepted.cfg` | budget used | 131330 | 120.2 | x | x |
| `MC_reach_app_replay.cfg` | budget used | 106304 | 120.3 | x | x |
| `MC_reach_crash.cfg` | budget used | 117751 | 120.3 | x | x |
| `MC_reach_handshake_complete.cfg` | budget used | 111579 | 120.3 | x | x |
| `MC_reach_mock_replay.cfg` | budget used | 110883 | 120.2 | x | x |
| `MC_reach_real_replay.cfg` | budget used | 110629 | 120.3 | x | x |
| `MC_reach_rejected.cfg` | budget used | 135303 | 120.3 | x | x |
| `MC_reach_ve_acc_row1.cfg` | budget used | 112680 | 120.3 | x | x |
| `MC_reach_ve_acc_row3.cfg` | budget used | 112912 | 120.3 | x | x |
| `MC_reach_ve_acc_row5.cfg` | budget used | 108971 | 120.2 | x | x |
| `MC_reach_ve_acc_row7.cfg` | budget used | 112294 | 120.3 | x | x |
| `MC_reach_ve_acc_row9.cfg` | budget used | 115201 | 120.2 | x | x |
| `MC_reach_ve_enabled_block.cfg` | budget used | 103655 | 120.2 | x | x |
| `MC_reach_ve_rej_basic.cfg` | budget used | 114550 | 120.3 | x | x |
| `MC_reach_ve_rej_identity.cfg` | budget used | 112342 | 120.2 | x | x |
| `MC_reach_ve_rej_row4.cfg` | budget used | 116778 | 120.2 | x | x |
| `MC_reach_ve_rej_row6.cfg` | budget used | 110770 | 120.2 | x | x |
| `MC_reach_ve_rej_row8.cfg` | budget used | 102499 | 120.2 | x | x |
| `MC_reach_ve_update_mock_replay.cfg` | budget used | 105804 | 120.2 | x | x |
| `MC_reach_ve_update_real_replay.cfg` | budget used | 106846 | 120.2 | x | x |
| `Update_discharge.cfg` | budget used | 114247 | 120.2 | x | x |
| `Update_discharge_control.cfg` | budget used | 110495 | 120.2 | x | x |
| `Update_focused.cfg` | budget used | 100485 | 120.2 | x | x |
| `Update_focused_core.cfg` | budget used | 102939 | 120.2 | x | x |
| `Update_full.cfg` | budget used | 90195 | 120.2 | x | x |
| `Update_full_core.cfg` | budget used | 91327 | 120.2 | x | x |
| `Update_hunt_scenario4_ve_lifecycle.cfg` | budget used | 95548 | 120.2 | x | x |
| `Update_hunt_scenario4_ve_lifecycle_core.cfg` | budget used | 95874 | 120.2 | x | x |
| `Update_hunt_scenario5_ve_recovery.cfg` | budget used | 94895 | 120.2 | x | x |
| `Update_hunt_scenario5_ve_recovery_core.cfg` | budget used | 92739 | 120.2 | x | x |
| `Update_open.cfg` | budget used | 87443 | 120.2 | x | x |
| `Update_open_core.cfg` | budget used | 99055 | 120.3 | x | x |
| `Update_sim_deep.cfg` | budget used | 62102 | 120.2 | x | x |
| `Update_sim_deep_core.cfg` | budget used | 61269 | 120.2 | x | x |
