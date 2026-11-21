| Run | Config | Mode | Distinct / generated | Depth | Outcome |
|---|---|---|---|---|---|
| MC-1-cex | `Update_full.cfg` | BFS | 838 / 1026 | 11 | VIOLATION: Invariant ContractLegalUpdateAccepted is violated |
| final-std-MC | `MC.cfg` | BFS | 75944 / 107820 | 34 | completed, no violation (bounded space exhausted) |
| final-upd-full-safety | `Update_full_safety.cfg` | BFS | 75944 / 107820 | 34 | completed, no violation (bounded space exhausted) |
| final-upd-full | `Update_full.cfg` | BFS | 489 / 588 | 10 | VIOLATION: Invariant ContractLegalUpdateAccepted is violated |
| hunt-U1_enable_from_zero-safety | `Update_hunt_U1_enable_from_zero_safety.cfg` | BFS | 5498 / 6877 | 38 | completed, no violation (bounded space exhausted) |
| hunt-U1_enable_from_zero | `Update_hunt_U1_enable_from_zero.cfg` | BFS | 989 / 1140 | 18 | VIOLATION: Invariant ContractLegalUpdateAccepted is violated |
| hunt-U2_unchanged_after_enable-safety | `Update_hunt_U2_unchanged_after_enable_safety.cfg` | BFS | 2373 / 2949 | 31 | completed, no violation (bounded space exhausted) |
| hunt-U2_unchanged_after_enable | `Update_hunt_U2_unchanged_after_enable.cfg` | BFS | 411 / 464 | 15 | VIOLATION: Invariant ContractLegalUpdateAccepted is violated |
| hunt-U3_ve_safety | `Update_hunt_U3_ve_safety.cfg` | BFS | 7625 / 9556 | 38 | completed, no violation (bounded space exhausted) |
| hunt-U4_recovery-safety | `Update_hunt_U4_recovery_safety.cfg` | BFS | 29037 / 45761 | 36 | completed, no violation (bounded space exhausted) |
| hunt-U4_recovery | `Update_hunt_U4_recovery.cfg` | BFS | 778 / 940 | 12 | VIOLATION: Invariant ContractLegalUpdateAccepted is violated |
| hunt-U5_deep_safety | `Update_hunt_U5_deep_safety.cfg` | BFS | 289761 / 419047 | 48 | completed, no violation (bounded space exhausted) |
| hunt-scenario1_params | `MC_hunt_scenario1_params.cfg` | BFS | 1728 / 2200 | 18 | completed, no violation (bounded space exhausted) |
| hunt-scenario2_durability | `MC_hunt_scenario2_durability.cfg` | BFS | 6201 / 8623 | 31 | completed, no violation (bounded space exhausted) |
| hunt-scenario3_recovery | `MC_hunt_scenario3_recovery.cfg` | BFS | 14570 / 20213 | 33 | completed, no violation (bounded space exhausted) |
| reach-accepted | `MC_reach_accepted.cfg` | BFS | 98 / 98 | 7 | VIOLATION: Invariant NeverReachedAcceptedUpdate is violated |
| reach-app_replay | `MC_reach_app_replay.cfg` | BFS | 516 / 613 | 15 | VIOLATION: Invariant NeverReachedAppOnlyReplay is violated |
| reach-crash | `MC_reach_crash.cfg` | BFS | 26 / 29 | 8 | VIOLATION: Invariant NeverReachedCrash is violated |
| reach-handshake_complete | `MC_reach_handshake_complete.cfg` | BFS | 169 / 189 | 12 | VIOLATION: Invariant NeverReachedHandshakeComplete is violated |
| reach-mock_replay | `MC_reach_mock_replay.cfg` | BFS | 243 / 299 | 12 | VIOLATION: Invariant NeverReachedMockReplay is violated |
| reach-real_replay | `MC_reach_real_replay.cfg` | BFS | 103 / 111 | 10 | VIOLATION: Invariant NeverReachedRealReplay is violated |
| reach-rejected | `MC_reach_rejected.cfg` | BFS | 102 / 102 | 8 | VIOLATION: Invariant NeverReachedRejectedUpdate is violated |
| reach_CancelFutureAccepted | `Update_reach_CancelFutureAccepted.cfg` | BFS | 315 / 345 | 9 | VIOLATION: Invariant NeverCancelFutureAccepted is violated |
| reach_DisableAfterEnableRejected | `Update_reach_DisableAfterEnableRejected.cfg` | BFS | 329 / 368 | 10 | VIOLATION: Invariant NeverDisableAfterEnableRejected is violated |
| reach_EnableFromZeroAccepted | `Update_reach_EnableFromZeroAccepted.cfg` | BFS | 430 / 467 | 10 | VIOLATION: Invariant NeverEnableFromZeroAccepted is violated |
| reach_LegalUpdateRejectedOnReplay | `Update_reach_LegalUpdateRejectedOnReplay.cfg` | BFS | 795 / 940 | 13 | VIOLATION: Invariant NeverLegalUpdateRejectedOnReplay is violated |
| reach_MockReplayRevalidatedVE | `Update_reach_MockReplayRevalidatedVE.cfg` | BFS | 1595 / 1860 | 16 | VIOLATION: Invariant NeverMockReplayRevalidatedVE is violated |
| reach_ModifyAfterEnableRejected | `Update_reach_ModifyAfterEnableRejected.cfg` | BFS | 438 / 479 | 11 | VIOLATION: Invariant NeverModifyAfterEnableRejected is violated |
| reach_ModifyFutureAccepted | `Update_reach_ModifyFutureAccepted.cfg` | BFS | 362 / 400 | 9 | VIOLATION: Invariant NeverModifyFutureAccepted is violated |
| reach_PastHeightRejected | `Update_reach_PastHeightRejected.cfg` | BFS | 420 / 459 | 10 | VIOLATION: Invariant NeverPastHeightRejected is violated |
| reach_RealReplayRejected | `Update_reach_RealReplayRejected.cfg` | BFS | 549 / 593 | 11 | VIOLATION: Invariant NeverRealReplayRejected is violated |
| reach_UnchangedAfterEnableRejected | `Update_reach_UnchangedAfterEnableRejected.cfg` | BFS | 486 / 528 | 11 | VIOLATION: Invariant NeverUnchangedAfterEnableRejected is violated |
| reach_ZeroToZeroAccepted | `Update_reach_ZeroToZeroAccepted.cfg` | BFS | 487 / 527 | 11 | VIOLATION: Invariant NeverZeroToZeroAccepted is violated |
| sim-deep-safety | `Update_sim_deep_safety.cfg` | simulation | - / 1406389302 (14063898 traces) | - | budget-limited simulation, no violation |
| sim-scenario1_params | `MC_hunt_scenario1_params.cfg` | simulation | - / 725627224 (7256277 traces) | - | budget-limited simulation, no violation |
| std-MC | `MC.cfg` | BFS | 75944 / 107820 | 34 | completed, no violation (bounded space exhausted) |
| upd-discharge-canary | `Update_discharge_canary.cfg` | BFS | 610 / 760 | 10 | VIOLATION: Action property DischargeCanaryOmittedNeverFires is violated |
| upd-discharge | `Update_discharge.cfg` | BFS | 75944 / 107820 | 34 | completed, no violation (bounded space exhausted) |
| upd-focused-safety | `Update_focused_safety.cfg` | BFS | 32634 / 46146 | 34 | completed, no violation (bounded space exhausted) |
| upd-focused | `Update_focused.cfg` | BFS | 822 / 1013 | 12 | VIOLATION: Invariant ContractLegalUpdateAccepted is violated |
| upd-full-safety | `Update_full_safety.cfg` | BFS | 75944 / 107820 | 34 | completed, no violation (bounded space exhausted) |
| upd-full | `Update_full.cfg` | BFS | 805 / 969 | 11 | VIOLATION: Invariant ContractLegalUpdateAccepted is violated |
| upd-open-safety | `Update_open_safety.cfg` | BFS | 306868 / 976302 | 34 | completed, no violation (bounded space exhausted) |
| upd-open | `Update_open.cfg` | BFS | 787 / 966 | 11 | VIOLATION: Invariant ContractLegalUpdateAccepted is violated |
