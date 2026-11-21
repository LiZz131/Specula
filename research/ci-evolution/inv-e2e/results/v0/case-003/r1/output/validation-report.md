# Specula V1 validation report (incremental, case 003)

## Outcome

- Source delta: `types/params.go:208-261` (`ConsensusParams.ValidateUpdate`),
  artifact commit `update` (`401753b0…`) vs `baseline` (`9dd6e508…`).
- Disposition: **MODEL_CHANGE_REQUIRED** — the update changes the enablement of
  the modeled `UpdateStateAccepted`/`UpdateStateRejected` Actions as a function
  of (current enable height, proposed enable height, block height), which V0's
  static `ValidParams` could not express. Reference refined; `Update.tla` added.
- Trace validation: **20/20 fresh new-version traces pass** real TLC trace
  validation with `TraceMatched` (Category A completion property) and full
  post-state checks; 6 mutation negative controls are all rejected.
- Model checking: standard convergence clean; **one actual counterexample,
  MC-1** (`ContractLegalUpdateAccepted`): the updated rule rejects an unchanged
  `VoteExtensionsEnableHeight` once vote extensions are enabled → chain halt.
  Confirmed **REPRODUCED** at Level 0 on a real consensus node; the old tree
  (control) accepts the same input.
- Overall status: `COMPLETED_WITH_LIMITED_COVERAGE` (bounded exploration and
  selected runtime scenarios; nothing here is a proof).

## Harness and provenance

- Prior harness reused and minimally rebased: the V0 patch applied cleanly
  (`spec/output/harness-rebase-apply-check.log`); only the parameter
  projection and two message fields were added
  (`harness/INSTRUMENTATION.md`, `spec/instrumentation-spec.md` §2b).
- One command: `bash harness/run.sh` (apply → build → 18 test processes → 20
  traces → structural checks → reverse patch). Log:
  `spec/output/harness-run-v1.log`; per-scenario logs `spec/output/harness-*.log`.
- Build deps: `go mod download` (`spec/output/go-mod-download-v1.log`).
- Scope baseline tests on the clean updated tree: pass
  (`spec/output/regression-types-v1.log`, `regression-state-v1.log`,
  `regression-consensus-replay-v1.log`).

## Fresh trace inventory (sha256 in `spec/output/trace-sha256-v1.txt`)

```
apply_rejected.ndjson                    5  BS > ABS > FinalizeBlock > SaveResp > UpdateStateRejected(basic)
apply_valid.ndjson                       7  BS > ABS > FinalizeBlock > SaveResp > UpdateStateAccepted > CommitApp > SaveState
apply_ve_cancel_future.ndjson            7  BS > ABS > FinalizeBlock > SaveResp > UpdateStateAccepted > CommitApp > SaveState
apply_ve_disable_after_enable.ndjson     5  BS > ABS > FinalizeBlock > SaveResp > UpdateStateRejected(update)
apply_ve_enable_from_zero.ndjson         7  BS > ABS > FinalizeBlock > SaveResp > UpdateStateAccepted > CommitApp > SaveState
apply_ve_modify_after_enable.ndjson      5  BS > ABS > FinalizeBlock > SaveResp > UpdateStateRejected(update)
apply_ve_modify_future.ndjson            7  BS > ABS > FinalizeBlock > SaveResp > UpdateStateAccepted > CommitApp > SaveState
apply_ve_negative.ndjson                 5  BS > ABS > FinalizeBlock > SaveResp > UpdateStateRejected(basic)
apply_ve_past_height.ndjson              5  BS > ABS > FinalizeBlock > SaveResp > UpdateStateRejected(update)
apply_ve_unchanged_after_enable.ndjson  12  BS > ABS > FinalizeBlock > SaveResp > UpdateStateAccepted > CommitApp > SaveState > BS > ABS > FinalizeBlock > SaveResp > UpdateStateRejected(update)
apply_ve_unchanged_echo.ndjson           5  BS > ABS > FinalizeBlock > SaveResp > UpdateStateRejected(update)
apply_ve_zero_to_zero.ndjson             7  BS > ABS > FinalizeBlock > SaveResp > UpdateStateAccepted > CommitApp > SaveState
replay_app_only.ndjson                   6  HandshakeStart > ReplayAppBlock > ReplayAppBlock > ReplayAppBlock > ReplayAppBlock > HandshakeComplete
replay_mock.ndjson                       9  HandshakeStart > ReplayStateBlockStart(mock) > ABS > FinalizeBlock > SaveResp > UpdateStateAccepted > CommitApp > SaveState > HandshakeComplete
replay_mock_ve_enable_prefix.ndjson      8  HandshakeStart > HandshakeComplete > BS > ABS > FinalizeBlock > SaveResp > UpdateStateAccepted > CommitApp
replay_mock_ve_enable_restart.ndjson     9  HandshakeStart > ReplayStateBlockStart(mock) > ABS > FinalizeBlock > SaveResp > UpdateStateAccepted > CommitApp > SaveState > HandshakeComplete
replay_none.ndjson                       2  HandshakeStart > HandshakeComplete
replay_real.ndjson                       9  HandshakeStart > ReplayStateBlockStart(real) > ABS > FinalizeBlock > SaveResp > UpdateStateAccepted > CommitApp > SaveState > HandshakeComplete
replay_ve_unchanged_prefix.ndjson        7  HandshakeStart > HandshakeComplete > BS > ABS > FinalizeBlock > SaveResp > UpdateStateRejected(update)
replay_ve_unchanged_restart.ndjson       6  HandshakeStart > ReplayStateBlockStart(real) > ABS > FinalizeBlock > SaveResp > UpdateStateRejected(update)
```

Prior V0 scenarios (`apply_valid`, `apply_rejected`, `replay_*`) were rerun on
the new implementation. Archived V0 traces (`traces/archived-v0/`) are
superseded (old schema without the enable height; same scenarios re-collected).

## Trace validation

- Runner: `spec/run_trace_validation.sh <names>` (TLC, `Trace.cfg`,
  `PROPERTIES TraceMatched`, states under `/dev/shm/specula-e2e-case-003/`,
  removed after each run).
- Order: affected trace first (`apply_ve_enable_from_zero`), then interaction
  traces, then prior regression traces, then the full suite on the final
  candidate (`spec/output/trace-v1-full-regression.txt`): every trace
  `PASS`, depth = events + 1, "Model checking completed. No error has been
  found." with temporal property checking.
- Field consumption (non-vacuity): `spec/output/negative-controls/summary.txt`
  — mutants M1 (proposed height rewritten to h with logged acceptance), M2
  (rejection stage relabelled), M3 (rejection relabelled as acceptance), M4
  (installed height altered), M5 (body validity flipped), M6 (saved response
  mismatch at restart) are each rejected at the intended event. M5 initially
  passed and exposed a circular `TraceValidBodies` derivation, repaired before
  the final regression (`spec/changelog.md`).

## Model checking (all runs; logs `spec/output/mc-v1-*.log`)

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

Notes:
- Expected violations: every `reach*` canary (non-vacuity witnesses) and
  `upd-discharge-canary` (omitted context actions really fire). All 7 V0 and 11
  update canaries were reached, including `LegalUpdateRejectedOnReplay`
  (consequence of MC-1 across restart) and `MockReplayRevalidatedVE`.
- P-U1 (`ContractLegalUpdateAccepted`) violation = MC-1. `*_safety` variants
  exclude only P-U1 so the remaining space is explored past it.
- Open lens: `EnvUpdate` rely discharged against the omitted
  `AppReportsOlderHeight`, `ReplayAppBlock`, `EnvironmentStutter` over the full
  reachable space (`upd-discharge`); open results are therefore not provisional.
- BFS runs marked "exhausted" completed their bounded state space; simulations
  stopped at their configured time budget (`-Dtlc2.TLC.stopAfter`) and are
  budget-limited.
- Final full checks on the final artifacts: `final-std-MC`,
  `final-upd-full-safety`, `final-upd-full`.

## Bounds / limits (LIMITED_COVERAGE)

- Standard/full checks: height ≤ 2, ≤ 2 blocks, ≤ 2 crashes, ≤ 1 app
  rollback, 3 symbolic bodies, enable heights {-1..3}, genesis enable height
  {0, 1}. Deep BFS: height ≤ 4; deep simulation: height ≤ 6, depth 100,
  30 minutes.
- Runtime evidence: 20 deterministic single-process scenarios with in-memory
  stores; crash cuts emulated by restart on durable stores and one injected
  state-save failure; no multi-node network, no real process kill.
- Not modeled: validator updates, InitChain parameter installation, vote
  extension contents, consumers of the enable height outside the scoped
  subsystem (checked abstractly by P-U3 only), binary upgrades across a crash.
- `specula ci-result` CLI and the `request_bug_confirmation` controller were not
  available in this environment; confirmation was performed directly per the
  bug-confirmation skill (`spec/confirmation-MC-1.md`) and `spec/final-result.json`
  was written but not post-processed.
