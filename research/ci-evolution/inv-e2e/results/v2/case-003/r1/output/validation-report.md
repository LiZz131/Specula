# Validation report — case-003 incremental run (updated revision `401753b`)

## Outcome

- Decision: **MODEL_CHANGE_REQUIRED** (final schema: `MODEL_UPDATED`).
- Trace validation: 16/16 fresh traces from the updated implementation match the
  updated reference (`Trace.cfg`, `TraceMatched` + all reference and non-contested
  update invariants); graph depth = events + 1 in every run; 8/8 field mutations rejected.
- Model checking: the standard round, full/focused/open update checks, discharge,
  five scenario hunts, 20 canaries and four simulations ran on the final artifacts.
  One finding, **MC-1** (`UnchangedVEUpdateNotRejected`): the updated
  `ValidateUpdate` rejects an unchanged, already reached enable height and halts
  the chain; reproduced on `401753b`, absent on `9dd6e50`. All other properties hold
  within bounds.
- Status: **COMPLETED_WITH_LIMITED_COVERAGE** (bounded BFS + budgeted simulation).

## Validation handoff

Source `401753b`; harness command `bash harness/run.sh`; fresh traces `traces/*.ndjson` (16); affected actions `UpdateStateAccepted` (rows 1,5,7,9) and `UpdateStateRejected` (basic, r4, r6, r8) observed; interactions FinalizeBlock→durable response→validation, mock/real replay re-validation, rejected re-execution observed; archived V0 traces superseded. Validation changed no semantic spec file (the only harness repair was the probe-effect fix); the MC entry gate was met before any campaign ran.

## Harness provenance

| Item | Value |
|---|---|
| Source under test | `artifact/` at `401753b` (update), instrumentation applied by `harness/apply.sh` |
| Prior patch | applied cleanly to `401753b` (`spec/output/harness-rebase-check.log`); archived `harness/patches/prior-v0/` |
| Current patch | `harness/patches/instrumentation.patch` (V0 hooks + structured fields; see `harness/INSTRUMENTATION.md`) |
| One command | `bash harness/run.sh` (16 scenarios, `timeout 10m` each; `spec/output/harness-run.log`, per-scenario logs in `spec/output/harness/`) |
| Build deps | `timeout 15m go mod download` (`spec/output/build-status.log`, exit 0) |
| Harness repair | `veHist` probe recovers from a mocked-store panic in a test fixture (probe effect only) |

## Trace inventory and results

| Trace | Kind | Path | Affected/interaction action | Events | TLC (`Trace.cfg`) | Depth |
|---|---|---|---|---:|---|---:|
| `apply_valid` | V0 regression | FinalizeBlock(Version update) → accepted → commit → save | UpdateStateAccepted (row 1) | 7 | matched | 8 |
| `apply_rejected` | V0 regression | invalid Block.MaxBytes=0 → ValidateBasic rejection | UpdateStateRejected (basic) | 5 | matched | 6 |
| `replay_app_only` | V0 regression | B=S=6, A=2 app-only catch-up | ReplayAppBlock | 6 | matched | 7 |
| `replay_real` | V0 regression | B=S+1, A=S real-app last block | SelectRealReplay + pipeline | 9 | matched | 10 |
| `replay_mock` | V0 regression | B=S+1, A=B saved-response mock | SelectMockReplay + pipeline | 9 | matched | 10 |
| `replay_none` | V0 regression | synchronized handshake | CompleteHandshake | 2 | matched | 3 |
| `ve_enable_future` | update | E=0 → U=2 at h=1 (row 7, changed), height 2 reached, Block-only update at h=3 (row 1) | UpdateStateAccepted rows 7,1; veHist enabled | 21 | matched | 22 |
| `ve_cancel_scheduled` | update | E=5 → 0 (row 5, changed) → 4 (row 7) → 6 (row 9) | UpdateStateAccepted rows 5,7,9 | 21 | matched | 22 |
| `ve_unchanged_after_enable` | update | E=1: Block-only update at h=1 (row 1), complete params (unchanged Abci{1}) at h=2 → row 6 (changed) | UpdateStateRejected r6 (MC-1) | 12 | matched | 13 |
| `ve_disable_after_enable` | update | E=1 → 0 at h=1 | UpdateStateRejected r4 | 5 | matched | 6 |
| `ve_modify_after_enable` | update | E=1 → 5 at h=1 | UpdateStateRejected r8 | 5 | matched | 6 |
| `ve_past_height` | update | E=0 → 2 at h=2 | UpdateStateRejected r6 | 12 | matched | 13 |
| `ve_negative` | update | U=-1 | UpdateStateRejected basic | 5 | matched | 6 |
| `replay_mock_ve_update` | update × recovery | Abci{3} committed by app, state save lost → mock replay re-validates | SelectMockReplay → UpdateStateAccepted row 7 | 9 | matched | 10 |
| `replay_real_ve_update` | update × recovery | Abci{2}, app Commit lost → real replay re-executes + re-validates | SelectRealReplay → UpdateStateAccepted row 7 | 9 | matched | 10 |
| `replay_real_ve_unchanged_rejected` | update × recovery | rejected unchanged Abci{1} → restart → real replay → rejected again, handshake error | SelectRealReplay → UpdateStateRejected r6 (MC-1 consequence) | 6 | matched | 7 |

Archived V0 traces (`traces/archived-v0/*.ndjson`): **superseded** — the same six
scenarios were rerun on `401753b` (first six rows); the archived files use V0's
fingerprint-only encoding and cannot carry the enable height required by the
updated Trace.tla. They stay immutable as old-version evidence.

Coverage gaps: decision-table row 3 (E = 0 → U = 0) is covered by MC (canary
`ve_acc_row3`) and code observation O10, not by a trace; row 2 is unreachable via
`updateState` (ValidateBasic rejects first; trace `ve_negative`).

### Field consumption (negative controls)

`spec/output/trace-mutation-controls.log`: mutating `rejectRule`, `veHist`,
`proposedParam.abci`, `activeParam.ve`, replacing the 0→2 acceptance by a rejection
(the V0 behavior), `lastParamChange`, `responseParam.abci`, or the cancelled
`activeParam.ve` makes TLC fail (no enabled trace step) in every case.

### Code observation, old vs new (same test on both trees)

`harness/observe/specula_observe_test.go`, logs `spec/output/observe-old.log`
(baseline tree from `git archive HEAD~1`) and `spec/output/observe-new.log`:
O1 (0→h+1) and O2 (cancel scheduled) old REJECTED → new ACCEPTED; O3 and O11
(unchanged reached height) old ACCEPTED → new REJECTED; O12 old fails at the enable,
new fails later at the unchanged re-send; O4-O10, O13 unchanged.

### Regression tests (scope list) on the updated, instrumented tree

types 41/41, internal/state 4/4, internal/consensus replay 36/36 PASS
(`spec/output/regression-{types,state,consensus-replay}.log`).

## Model checking (final artifacts)

| Campaign | Config | Mode | Distinct states | Depth | Result |
|---|---|---|---:|---:|---|
| standard convergence | `MC.cfg` | BFS | 1,460,638 | 46 | no violation (exhausted) |
| plain reference | `base.cfg` | BFS | 174,936 | 39 | no violation (exhausted) |
| full update | `Update_full.cfg` | BFS | 3,578 at stop | 14 | **MC-1** `UnchangedVEUpdateNotRejected` (13-state CE) |
| full update, core | `Update_full_core.cfg` | BFS | 1,460,638 | 46 | no violation (exhausted) |
| concrete focused | `Update_focused.cfg` | BFS | 1,146 at stop | 12 | MC-1 (6-state CE, admitted by full MCNext) |
| concrete focused, core | `Update_focused_core.cfg` | BFS | 399,798 | 45 | no violation (exhausted) |
| open focused | `Update_open.cfg` | BFS | 4,934 at stop | 14 | MC-1 |
| open focused, core | `Update_open_core.cfg` | BFS | 2,289,011 | 45 | no violation (exhausted) |
| discharge | `Update_discharge.cfg` | BFS | 129,636 | 46 | `DischargeContext` holds |
| discharge negative control | `Update_discharge_control.cfg` | BFS | — | 12 | fails as expected (non-vacuous) |
| Scenario 1 params | `MC_hunt_scenario1_params.cfg` | BFS | 4,491 | 22 | no violation (exhausted) |
| Scenario 2 durability | `MC_hunt_scenario2_durability.cfg` | BFS | 23,072 | 43 | no violation (exhausted) |
| Scenario 3 recovery | `MC_hunt_scenario3_recovery.cfg` | BFS | 65,161 | 46 | no violation (exhausted) |
| Scenario 4 VE lifecycle | `Update_hunt_scenario4_ve_lifecycle.cfg` | BFS | 1,660 at stop | 14 | MC-1 |
| Scenario 4 core | `..._core.cfg` | BFS | 502,328 | 43 | no violation (exhausted) |
| Scenario 5 VE × recovery | `Update_hunt_scenario5_ve_recovery.cfg` | BFS | 3,511 at stop | 13 | MC-1 |
| Scenario 5 core | `..._core.cfg` | BFS | 1,005,521 | 49 | no violation (exhausted) |

Simulation follow-ups (depth 100, 30-minute budget, `-Dtlc2.TLC.stopAfter=1800`;
budget-terminated, not exhaustive):

| Run | Config | States checked | Traces | Result |
|---|---|---:|---:|---|
| Scenario 1 (BFS diameter 22 ≤ 25) | `MC_hunt_scenario1_params.cfg` | 761,632,096 | 7,238,915 | no violation |
| Scenario 4 core | `Update_hunt_scenario4_ve_lifecycle_core.cfg` | 508,444,935 | 4,856,850 | no violation |
| Scenario 5 core | `Update_hunt_scenario5_ve_recovery_core.cfg` | 534,199,444 | 5,101,012 | no violation |
| Deep bounds (8 heights, 3 crashes, 10 proposal values) core | `Update_sim_deep_core.cfg` | 395,989,462 | 3,815,288 | no violation |
| Deep bounds incl. contested property (5-min budget) | `Update_sim_deep.cfg` | — | — | MC-1 at depth 39 |

Reachability canaries: 20/20 produced witnesses (`spec/output/reachability-summary.log`,
logs `spec/output/reach/`): the 7 V0 markers; accepted rows 1/3/5/7/9; rejected
basic/rows 4/6/8; unchanged-value rejection; enabled stored block; enable-height
update re-validated by mock and by real replay.

Final gate on the frozen artifacts (`spec/output/final-artifact-checksums.{before,after}`
identical): 16/16 traces re-validated (`spec/output/final/trace-regression-summary.log`)
and every BFS campaign above re-run with identical outcomes
(`spec/output/final/mc-summary.log`).

## Finding

**MC-1 — unchanged, already reached `VoteExtensionsEnableHeight` is rejected
(chain halt).** Counterexample `spec/output/mc/MC-1_Update_full_counterexample.log`;
real traces `traces/ve_unchanged_after_enable.ndjson`,
`traces/replay_real_ve_unchanged_rejected.ndjson`; reproduction
`spec/repro/MC-1/` (FAIL on `401753b`, PASS on `9dd6e50`); details and the
requirement conflict in `spec/bug-report.md` and `spec/confirmation-MC-1.md`.
A model-only remedy sketch (accept `U = E`) satisfies every property
(`spec/repro/MC-1/fix-sketch-tlc.log`).

## Property decisions

`spec/invariant-evidence.json` (15 TLC-evaluated states in `spec/evidence/`):
TypeOK and ParameterUpdateReflected modified; RejectedUpdateDoesNotInstall,
SuccessfulApplyAdvancesExactlyOne, NormalPhaseIsSynchronized kept with trace
evidence; PersistedHeightRelationships / RecoveryNormalOnlySupported unaffected
(control); six update properties added. The only `unknown` requirement clause is
the after-reached clause of `UnchangedVEUpdateNotRejected` (not weakened).

## Limits (LIMITED_COVERAGE)

- BFS bounds: heights ≤ 3 (standard/full/open), ≤ 4 (focused), ≤ 5 (Scenario 4);
  ≤ 3 crashes; ≤ 1 app rollback; finite enable-height proposal domains; symbolic
  non-ABCI parameter identities. Simulations are budget-terminated samples.
- Traces come from in-memory stores, scripted ABCI apps and injected Save/Commit
  failures, not process kills or real networks; extended-commit storage is not
  observed (veHist reads the state-store params history).
- Out of scope as in V0: Byzantine behavior, peers/voting, validator updates,
  pruning, state sync, InitChain parameter validation, I/O faults.
- The bug-confirmation controller (Part 4) was not run; MC-1's status rests on the
  in-run reproduction and controls.
