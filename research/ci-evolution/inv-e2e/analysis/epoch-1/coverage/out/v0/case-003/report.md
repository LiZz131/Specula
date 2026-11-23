# Update coverage: output/spec

## Checks never run while an action happens

None: every enabled check runs in a config that reaches every action some config reaches.

Ignored as requested: `DischargeCanaryOmittedNeverFires`, `NeverReachedAcceptedUpdate`, `NeverReachedAppOnlyReplay`, `NeverReachedCrash`, `NeverReachedHandshakeComplete`, `NeverReachedMockReplay`, `NeverReachedRealReplay`, `NeverReachedRejectedUpdate`.

## Actions

| # | Group | Action |
|---:|---|---|
| 1 | AffectedActions | MCUpdateStateAccepted |
| 2 | AffectedActions | MCUpdateStateRejected |

## What each config reached

`x` taken, `e` enabled but not taken, `.` never enabled. Retried configs ran a second, longer pass.

| Config | Status | Traces | Seconds | 1 | 2 |
|---|---|---:|---:|---|---|
| `MC.cfg` | budget used | 61833 | 120.5 | x | x |
| `MC_hunt_scenario1_params.cfg` | budget used | 77989 | 120.5 | x | x |
| `MC_hunt_scenario2_durability.cfg` | budget used | 99777 | 120.5 | x | x |
| `MC_hunt_scenario3_recovery.cfg` | budget used | 97853 | 120.5 | x | x |
| `MC_reach_accepted.cfg` | budget used | 67015 | 120.5 | x | x |
| `MC_reach_app_replay.cfg` | budget used | 91518 | 120.5 | x | x |
| `MC_reach_crash.cfg` | budget used, retried | 385126 | 360.7 | x | . |
| `MC_reach_handshake_complete.cfg` | budget used, retried | 386555 | 360.7 | x | . |
| `MC_reach_mock_replay.cfg` | budget used, retried | 394866 | 360.7 | x | . |
| `MC_reach_real_replay.cfg` | budget used, retried | 405884 | 360.7 | x | . |
| `MC_reach_rejected.cfg` | budget used | 69332 | 120.5 | x | x |
| `Update_discharge.cfg` | budget used | 70780 | 120.5 | x | x |
| `Update_discharge_canary.cfg` | budget used | 66291 | 120.5 | x | x |
| `Update_focused.cfg` | budget used | 84676 | 120.4 | x | x |
| `Update_focused_safety.cfg` | budget used | 83223 | 120.5 | x | x |
| `Update_full.cfg` | budget used | 58577 | 120.5 | x | x |
| `Update_full_safety.cfg` | budget used | 57188 | 120.3 | x | x |
| `Update_hunt_U1_enable_from_zero.cfg` | budget used | 82630 | 120.4 | x | x |
| `Update_hunt_U1_enable_from_zero_safety.cfg` | budget used | 81380 | 120.4 | x | x |
| `Update_hunt_U2_unchanged_after_enable.cfg` | budget used | 77124 | 120.4 | x | x |
| `Update_hunt_U2_unchanged_after_enable_safety.cfg` | budget used | 63849 | 120.4 | x | x |
| `Update_hunt_U3_ve_safety.cfg` | budget used | 72849 | 120.3 | x | x |
| `Update_hunt_U4_recovery.cfg` | budget used | 85300 | 120.3 | x | x |
| `Update_hunt_U4_recovery_safety.cfg` | budget used | 88886 | 120.3 | x | x |
| `Update_hunt_U5_deep_safety.cfg` | budget used | 68010 | 120.4 | x | x |
| `Update_open.cfg` | budget used | 72933 | 120.3 | x | x |
| `Update_open_safety.cfg` | budget used | 70506 | 120.3 | x | x |
| `Update_reach_CancelFutureAccepted.cfg` | budget used | 86169 | 120.4 | x | x |
| `Update_reach_DisableAfterEnableRejected.cfg` | budget used | 90087 | 120.3 | x | x |
| `Update_reach_EnableFromZeroAccepted.cfg` | budget used | 82210 | 120.3 | x | x |
| `Update_reach_LegalUpdateRejectedOnReplay.cfg` | budget used | 80542 | 120.3 | x | x |
| `Update_reach_MockReplayRevalidatedVE.cfg` | budget used | 79478 | 120.4 | x | x |
| `Update_reach_ModifyAfterEnableRejected.cfg` | budget used | 149867 | 120.2 | x | x |
| `Update_reach_ModifyFutureAccepted.cfg` | budget used | 148173 | 120.2 | x | x |
| `Update_reach_PastHeightRejected.cfg` | budget used | 150266 | 120.2 | x | x |
| `Update_reach_RealReplayRejected.cfg` | budget used | 150177 | 120.2 | x | x |
| `Update_reach_UnchangedAfterEnableRejected.cfg` | budget used | 149208 | 120.2 | x | x |
| `Update_reach_ZeroToZeroAccepted.cfg` | budget used | 150130 | 120.2 | x | x |
| `Update_sim_deep_safety.cfg` | budget used | 89286 | 120.2 | x | x |
