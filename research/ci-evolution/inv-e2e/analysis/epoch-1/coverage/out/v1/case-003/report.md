# Update coverage: output/spec

## Checks never run while an action happens

None: every enabled check runs in a config that reaches every action some config reaches.

Ignored as requested: `NeverReachedAcceptedUpdate`, `NeverReachedAppOnlyReplay`, `NeverReachedBasicRejection`, `NeverReachedCrash`, `NeverReachedEnableAttemptRejected`, `NeverReachedFutureVEChangeAccepted`, `NeverReachedHaltPersists`, `NeverReachedHandshakeComplete`, `NeverReachedMockReplay`, `NeverReachedMockReplayOfVEChange`, `NeverReachedOpenEnv`, `NeverReachedReachedVEAccepted`, `NeverReachedRealReplay`, `NeverReachedRejectedUpdate`, `NeverReachedReplayRejectionOfUnchanged`, `NeverReachedReplayVERejection`, `NeverReachedRow1`, `NeverReachedRow3`, `NeverReachedRow4`, `NeverReachedRow5`, `NeverReachedRow6`, `NeverReachedRow7`, `NeverReachedRow8`, `NeverReachedRow9`, `NeverReachedSavedEnable`.

## Actions

| # | Group | Action |
|---:|---|---|
| 1 | AffectedActions | MCUpdateStateAccepted |
| 2 | AffectedActions | MCUpdateStateRejectedVE |

## What each config reached

`x` taken, `e` enabled but not taken, `.` never enabled. Retried configs ran a second, longer pass.

| Config | Status | Traces | Seconds | 1 | 2 |
|---|---|---:|---:|---|---|
| `MC.cfg` | budget used | 73172 | 120.6 | x | x |
| `MC_hunt_scenario1_params.cfg` | budget used | 72916 | 120.7 | x | x |
| `MC_hunt_scenario2_durability.cfg` | budget used | 92775 | 120.7 | x | x |
| `MC_hunt_scenario3_recovery.cfg` | budget used | 85977 | 120.5 | x | x |
| `MC_reach_accepted.cfg` | budget used | 84913 | 120.6 | x | x |
| `MC_reach_app_replay.cfg` | budget used | 93076 | 120.3 | x | x |
| `MC_reach_basic_rejection.cfg` | budget used | 97191 | 120.4 | x | x |
| `MC_reach_crash.cfg` | budget used | 111512 | 120.3 | x | x |
| `MC_reach_handshake_complete.cfg` | budget used | 87738 | 120.5 | x | x |
| `MC_reach_mock_replay.cfg` | budget used | 90326 | 120.6 | x | x |
| `MC_reach_real_replay.cfg` | budget used | 95615 | 120.7 | x | x |
| `MC_reach_rejected.cfg` | budget used | 90347 | 120.4 | x | x |
| `MC_reach_replay_ve_rejection.cfg` | budget used | 79881 | 120.8 | x | x |
| `MC_reach_row1.cfg` | budget used | 84412 | 120.4 | x | x |
| `MC_reach_row3.cfg` | budget used | 86834 | 120.7 | x | x |
| `MC_reach_row4.cfg` | budget used | 109592 | 120.3 | x | x |
| `MC_reach_row5.cfg` | budget used | 68911 | 120.2 | x | x |
| `MC_reach_row6.cfg` | budget used | 94238 | 120.2 | x | x |
| `MC_reach_row7.cfg` | budget used | 79320 | 120.2 | x | x |
| `MC_reach_row8.cfg` | budget used | 76658 | 120.2 | x | x |
| `MC_reach_row9.cfg` | budget used | 67678 | 120.2 | x | x |
| `Update_deep_bfs.cfg` | budget used | 49794 | 120.2 | x | x |
| `Update_discharge.cfg` | budget used | 46166 | 120.2 | x | x |
| `Update_discharge_control.cfg` | budget used | 61431 | 120.2 | x | x |
| `Update_focused.cfg` | budget used | 50936 | 120.2 | x | x |
| `Update_focused_safety.cfg` | budget used | 45721 | 120.2 | x | x |
| `Update_full.cfg` | budget used | 50932 | 120.2 | x | x |
| `Update_full_safety.cfg` | budget used | 61826 | 120.2 | x | x |
| `Update_hunt_enable.cfg` | budget used | 60782 | 120.3 | x | x |
| `Update_hunt_recovery.cfg` | budget used | 72019 | 120.2 | x | x |
| `Update_hunt_unchanged.cfg` | budget used | 81982 | 120.2 | x | x |
| `Update_hunt_unchanged_from_disabled.cfg` | budget used | 69493 | 120.2 | x | x |
| `Update_open.cfg` | budget used | 93420 | 120.3 | x | x |
| `Update_open_safety.cfg` | budget used | 92679 | 120.5 | x | x |
| `Update_reach_enable_attempt_rejected.cfg` | budget used | 130188 | 120.6 | x | x |
| `Update_reach_future_change_accepted.cfg` | budget used | 126348 | 120.4 | x | x |
| `Update_reach_halt_persists.cfg` | budget used | 127198 | 120.4 | x | x |
| `Update_reach_mock_replay_ve_change.cfg` | budget used | 130488 | 120.3 | x | x |
| `Update_reach_open_env.cfg` | budget used | 126366 | 120.4 | x | x |
| `Update_reach_reached_ve_accepted.cfg` | budget used | 131621 | 120.5 | x | x |
| `Update_reach_replay_rejection_unchanged.cfg` | budget used | 131406 | 120.5 | x | x |
| `Update_reach_saved_enable.cfg` | budget used | 137518 | 120.5 | x | x |
| `Update_sim_deep.cfg` | budget used | 69023 | 120.3 | x | x |
| `Update_sim_unchanged.cfg` | budget used | 96529 | 120.4 | x | x |
