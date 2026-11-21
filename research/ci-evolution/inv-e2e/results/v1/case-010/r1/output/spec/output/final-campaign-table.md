| Log (spec/output/) | Config, module/mode | Result | Distinct states | Depth |
|---|---|---|---:|---:|
| `f2-ev-oldSPV-full.log` | `Evidence-oldSPV-full.cfg Update` | no violation, LIMITED_COVERAGE (time limit) | 3,600,387 | 32 (BFS level) |
| `f2-mc-full.log` | `MC-full.cfg Update` | no violation, LIMITED_COVERAGE (time limit) | 11,674,665 | 38 (BFS level) |
| `f2-mc-standard.log` | `MC.cfg MC` | complete, no violation | 65206 | 46 |
| `f2-sim-upd-full-residual.log` | `Update-full-residual.cfg -simulate -depth 100 Update` | no violation, LIMITED_COVERAGE (time limit) | 190471 traces (simulation) | - |
| `f2-sim-upd-open-residual.log` | `Update-open-residual.cfg -simulate -depth 100 Update` | no violation, LIMITED_COVERAGE (time limit) | 117503 traces (simulation) | - |
| `f2-upd-discharge.log` | `Update-discharge.cfg Update` | no violation, LIMITED_COVERAGE (time limit) | 5,553,006 | 33 (BFS level) |
| `f2-upd-focused-residual.log` | `Update-focused-residual.cfg Update` | no violation, LIMITED_COVERAGE (time limit) | 7,399,348 | 26 (BFS level) |
| `f2-upd-focused.log` | `Update-focused.cfg Update` | VIOLATION: Invariant OrderedHistoriesV1 is violated | 90852 | 16 |
| `f2-upd-full-residual.log` | `Update-full-residual.cfg Update` | no violation, LIMITED_COVERAGE (time limit) | 11,127,361 | 34 (BFS level) |
| `f2-upd-full.log` | `Update-full.cfg Update` | no violation, LIMITED_COVERAGE (time limit) | 5,482,771 | 34 (BFS level) |
| `f2-upd-open-residual.log` | `Update-open-residual.cfg Update` | no violation, LIMITED_COVERAGE (time limit) | 7,266,199 | 21 (BFS level) |
| `f2-upd-open.log` | `Update-open.cfg Update` | VIOLATION: Invariant OrderedHistoriesV1 is violated | 416737 | 16 |
| `final-evidence-oldmon.log` | `Evidence-oldMON.cfg Update` | VIOLATION: Action property MonotoneUnlessRecovery is violated | 7337 | 16 |
| `final-evidence-oldoh.log` | `Evidence-oldOH.cfg Update` | VIOLATION: Invariant OrderedHistories is violated | 12389 | 11 |
| `final-evidence-oldspv.log` | `Evidence-oldSPV.cfg Update` | complete, no violation | 144904 | 46 |
| `final-evidence-v1mon.log` | `Evidence-V1MON.cfg Update` | VIOLATION: Action property MonotoneUnlessRecoveryV1 is violated | 9971 | 17 |
| `final-mc-apply-hunt.log` | `MC-apply-hunt.cfg Update` | VIOLATION: Invariant ApplyUnreachable is violated | 271 | 26 |
| `final-mc-commit-hunt.log` | `MC-commit-hunt.cfg Update` | VIOLATION: Invariant CommitUnreachable is violated | 256 | 25 |
| `final-mc-election-hunt.log` | `MC-election-hunt.cfg Update` | VIOLATION: Invariant ElectionUnreachable is violated | 23 | 4 |
| `final-mc-recovery-complete.log` | `MC-recovery-complete.cfg Update` | complete, no violation | 25240 | 49 |
| `final-mc-recovery-hunt.log` | `MC-recovery-hunt.cfg Update` | VIOLATION: Invariant RecoveryUnreachable is violated | 247 | 20 |
| `final-mc-snapshot-complete.log` | `MC-snapshot-complete.cfg Update` | complete, no violation | 744 | 31 |
| `final-mc-snapshot-hunt.log` | `MC-snapshot-hunt.cfg Update` | VIOLATION: Invariant SnapshotUnreachable is violated | 136 | 20 |
| `final-mc-sync-hunt.log` | `MC-sync-hunt.cfg Update` | VIOLATION: Invariant SyncUnreachable is violated | 4029 | 18 |
| `final-update-canary-diffreload.log` | `Update-canary-diffreload.cfg Update` | VIOLATION: Invariant DiffAfterSnapReloadUnreachable is violated | 2731 | 13 |
| `final-update-canary-leakedflush.log` | `Update-canary-leakedflush.cfg Update` | VIOLATION: Invariant LeakedFlushAfterResyncUnreachable is violated | 600 | 9 |
| `final-update-canary-reload.log` | `Update-canary-reload.cfg Update` | VIOLATION: Invariant ReloadAfterSnapExitUnreachable is violated | 497 | 9 |
| `final-update-canary-servingexit.log` | `Update-canary-servingexit.cfg Update` | VIOLATION: Invariant ServingExitUnreachable is violated | 3 | 2 |
| `final-update-canary-snapcommit.log` | `Update-canary-snapcommit.cfg Update` | VIOLATION: Invariant SnapExitThenCommittedRecoverableUnreachable is violated | 17341 | 19 |
| `final-update-canary-snapexit.log` | `Update-canary-snapexit.cfg Update` | VIOLATION: Invariant SnapExitUnpersistedUnreachable is violated | 10880 | 17 |
| `final-update-canary-steady.log` | `Update-canary-steady.cfg Update` | VIOLATION: Invariant SteadyStateUnreachable is violated | 23757 | 31 |
| `final-update-canary-truncexit.log` | `Update-canary-truncexit.cfg Update` | VIOLATION: Invariant TruncExitUnpersistedUnreachable is violated | 27037 | 16 |
| `final-update-control-prior-gap.log` | `Update-control-prior-gap.cfg Update` | VIOLATION: Invariant RecoverableHistoryComplete is violated | 51909 | 25 |
| `final-update-control-prior-leak-gap.log` | `Update-control-prior-leak-gap.cfg Update` | complete, no violation | 238362 | 45 |
| `final-update-control-prior-leak-prefix.log` | `Update-control-prior-leak-prefix.cfg Update` | VIOLATION: Invariant RecoverableCommittedPrefix is violated | 14928 | 18 |
| `final-update-control-prior-leak.log` | `Update-control-prior-leak.cfg Update` | VIOLATION: Invariant DurableReplayOrdered is violated | 5286 | 15 |
| `final-update-control-prior-trunc-noleak-gap.log` | `Update-control-prior-trunc-noleak-gap.cfg Update` | VIOLATION: Invariant RecoverableHistoryComplete is violated | 78728 | 25 |
| `final-update-control-prior-trunc.log` | `Update-control-prior-trunc.cfg Update` | VIOLATION: Invariant ExitedLearnerMemoryBackedByLog is violated | 19759 | 16 |
| `final-update-control-prior.log` | `Update-control-prior.cfg Update` | VIOLATION: Invariant ExitedLearnerMemoryBackedByLog is violated | 9979 | 17 |
| `final-update-hunt-leak-gap.log` | `Update-hunt-leak-gap.cfg Update` | VIOLATION: Invariant RecoverableHistoryComplete is violated | 16264 | 17 |
| `final-update-hunt-leak-order.log` | `Update-hunt-leak-order.cfg Update` | VIOLATION: Invariant DurableReplayOrdered is violated | 7725 | 15 |
| `final-update-hunt-leak-prefix.log` | `Update-hunt-leak-prefix.cfg Update` | VIOLATION: Invariant RecoverableCommittedPrefix is violated | 31273 | 19 |
| `final-update-hunt-snap.log` | `Update-hunt-snap.cfg Update` | complete, no violation | 144904 | 46 |
| `final-update-hunt-trunc-gap.log` | `Update-hunt-trunc-gap.cfg Update` | VIOLATION: Invariant RecoverableHistoryComplete is violated | 129555 | 21 |
| `final-update-hunt-trunc-noleak-gap.log` | `Update-hunt-trunc-noleak-gap.cfg Update` | VIOLATION: Invariant RecoverableHistoryComplete is violated | 96195 | 26 |
| `final-update-hunt-trunc-noleak.log` | `Update-hunt-trunc-noleak.cfg Update` | VIOLATION: Invariant ExitedLearnerMemoryBackedByLog is violated | 10656 | 17 |
| `final-update-hunt-trunc.log` | `Update-hunt-trunc.cfg Update` | VIOLATION: Invariant ExitedLearnerMemoryBackedByLog is violated | 23624 | 16 |
