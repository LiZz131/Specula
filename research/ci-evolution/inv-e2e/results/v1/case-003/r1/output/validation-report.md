# V1 incremental validation and model-checking report (case 003)

## Identity

| Item | Value |
|---|---|
| Updated source | `artifact/` at commit `401753b` (`update`); `types/params.go` byte-identical to `/work/new-source/types/params.go` |
| Old control source | commit `9dd6e50` (`baseline`), exported to `controls/` for the control runs only (removed after use) |
| Disposition | `MODEL_CHANGE_REQUIRED` (reported as `MODEL_UPDATED`) |
| Harness command | `bash harness/run.sh` (applies `harness/patches/instrumentation.patch`, runs 6 prior + 13 update scenarios, 10-minute outer timeout per `go test`) |
| Reproduction command | `harness/repro_MC-1.sh [source-tree]` (instrumentation-free) |
| TLC | `/work/lib/tla2tools.jar` 2026.11.06; states under `/dev/shm/specula-e2e-case-003/` (removed after each run), logs in `spec/output/` |
| Status | `COMPLETED_WITH_LIMITED_COVERAGE`, one reproduced finding (MC-1) |

## Harness reuse (Validation 1)

- The V0 patch applied to `401753b` without drift (`spec/output/harness-rebase-check.log`)
  and is kept as `harness/patches/v0-instrumentation.patch`.
- Minimal V1 changes: the parameter encoding (`{other, veh}`), Abci-presence
  fields, `activeOtherValid`/`proposedOtherValid`, and the rejection `reason`.
  Event names, trigger points, writer, and reset strategy are unchanged.
- Scope regression tests on the instrumented tree pass:
  `spec/output/regression-types.log`, `regression-state.log`,
  `regression-consensus-replay.log`.

## Fresh traces (Validation 2)

All traces were produced by executing the real updated code (no hand-written or
simulated events). Trace validation is real TLC replay of `Trace.tla`/`Trace.cfg`
with `PROPERTIES TraceMatched` and all reference invariants enabled; every run
ended with "Model checking completed. No error has been found." at depth =
events + 1 (`spec/output/trace-full-*.log`, summary `spec/output/trace-full-summary.log`).

| Trace | Events | Kind | Path / row | TLC |
|---|---:|---|---|---|
| `apply_valid` | 7 | prior | row 1 (Abci absent) accept → commit → save | matched |
| `apply_rejected` | 5 | prior | basic rejection (`MaxBytes = 0`) | matched |
| `replay_app_only` | 6 | prior | app-only replay | matched |
| `replay_real` | 9 | prior | real final-block replay | matched |
| `replay_mock` | 9 | prior | mock final-block replay | matched |
| `replay_none` | 2 | prior | synced handshake | matched |
| `ve_enable_future` | 7 | update U1 | row 7 accept, `lastParamChange = 2`, saved | matched |
| `ve_enable_current` | 5 | update U5 | row 6 reject (enable at current height) | matched |
| `ve_echo_disabled` | 7 | update U5 | row 3 accept (full-set echo, VEH 0) | matched |
| `ve_echo_reached` | 5 | update U2 | **row 6 reject of unchanged VEH 1 at h 1** | matched |
| `ve_echo_future` | 7 | update U5 | row 9 accept (unchanged VEH 5 at h 1) | matched |
| `ve_disable_reached` | 5 | update U4 | row 4 reject | matched |
| `ve_disable_future` | 7 | update U3 | row 5 accept | matched |
| `ve_move_reached` | 5 | update U4 | row 8 reject | matched |
| `ve_move_future` | 7 | update U5 | row 9 accept | matched |
| `ve_negative` | 5 | update U5 | basic rejection masks row 2 | matched |
| `ve_enable_then_echo` | 12 | update U7 | row 7 accept at h 1, row 6 reject at h 2 | matched |
| `ve_echo_restart_apply` | 5 | update U2 | row 6 reject before restart | matched |
| `ve_echo_restart_handshake` | 6 | update U2/U6 | restart: real replay re-rejects | matched |

Archived V0 traces (`traces/archive-v0/`) use string fingerprints and are
superseded by the representation change; every V0 scenario was re-run fresh.

### Coverage gate

- Affected actions observed: `UpdateStateAccepted` (rows 1, 3, 5, 7, 9),
  `UpdateStateRejectedVE` (rows 4, 6, 8), `UpdateStateRejectedBasic` (basic,
  including the masked row 2). Interaction actions observed: `SaveBlock`,
  `ApplyBlockStart`, `FinalizeBlock`, `SaveFinalizeBlockResponse`, `CommitApp`,
  `SaveState`, `BeginHandshake`, `SelectRealReplay`, `SelectMockReplay`,
  `ReplayAppBlock`, `CompleteHandshake`.
- Not observable at runtime (model-only, as in V0): `Crash`,
  `AppReportsOlderHeight`, `AbortRejectedApply` (represented by trace end plus
  a restart trace), `EnvironmentStutter`. A mock replay *of a changed VE value*
  was not traced (only reached in MC: `Update_reach_mock_replay_ve_change`).
  This is a recorded gap.

### Non-vacuity controls

- Field consumption: 5 mutated copies of fresh traces (`traces/mutation-controls/`)
  each fail at the mutated event: reason flip, Abci-presence flip, proposed VEH
  3→1, `lastParamChange` not advanced, persisted VEH mismatch
  (`spec/output/mutation-*.log`).
- Decision discrimination: the same 13 update scenarios executed on the
  exact-old code (`traces/controls-old-code/`) fail against the V1 model on
  exactly the rows the update changed (`ve_enable_future`, `ve_disable_future`,
  `ve_echo_reached`, `ve_echo_restart_apply`, `ve_enable_then_echo`) and match
  on the 8 unchanged ones (`spec/output/control-old-vs-v1-summary.log`).

## Property evidence

`spec/invariant-evidence.json`: 10 affected properties, each with a decision,
separating/keep states evaluated by TLC (`spec/evidence/*/tlc.log`), and
controls. Trace-sourced states from both revisions back the update properties.
Bug candidate E1/T1/T1r/T6 (`UnchangedVENotRejected`) became MC-1.

## Model checking

| Campaign | Config | Distinct states | Depth | Result |
|---|---|---:|---:|---|
| Standard convergence | `MC.cfg` | 40,119 | 34 | no violation, exhaustive |
| 1. Full update | `Update_full.cfg` | (stopped) | — | **`UnchangedVENotRejected` violated (MC-1)** |
| 1. Full update, rest | `Update_full_safety.cfg` | 40,119 | 34 | no violation, exhaustive |
| 2. Concrete focused | `Update_focused.cfg` | (stopped) | — | MC-1 again |
| 2. Concrete focused, rest | `Update_focused_safety.cfg` | 59,267 | 39 | no violation, exhaustive |
| 3. Open focused | `Update_open.cfg` | (stopped) | — | MC-1 again |
| 3. Open focused, rest | `Update_open_safety.cfg` | 80,837 | 34 | no violation, exhaustive |
| 3. Discharge | `Update_discharge.cfg` | 53,799 | 41 | `DischargeContext` holds |
| 3. Discharge control | `Update_discharge_control.cfg` | — | — | strict rely violated as expected |
| 4. Hunt V0-1 | `MC_hunt_scenario1_params.cfg` | 7,174 | 31 | no violation |
| 4. Hunt V0-2 | `MC_hunt_scenario2_durability.cfg` | 8,643 | 31 | no violation |
| 4. Hunt V0-3 | `MC_hunt_scenario3_recovery.cfg` | 19,161 | 33 | no violation |
| 4. Hunt U2 | `Update_hunt_unchanged.cfg` | (stopped) | — | MC-1 |
| 4. Hunt U7 | `Update_hunt_unchanged_from_disabled.cfg` | (stopped) | — | MC-1 via row-7 enable then echo |
| 4. Hunt U1/U3/U4/U5 | `Update_hunt_enable.cfg` | 7,567 | 38 | no violation |
| 4. Hunt U6 | `Update_hunt_recovery.cfg` | 35,363 | 36 | no violation |
| 5. Deeper BFS (h≤3) | `Update_deep_bfs.cfg` | 158,158 | 41 | no violation, exhaustive |
| 5. Simulation (h≤5) | `Update_sim_deep.cfg` | see log | 100 | no violation (budget-limited) |
| 5. Simulation U2 (h≤5) | `Update_sim_unchanged.cfg` | — | — | MC-1 again |
| Canaries | 17 `MC_reach_*`, 8 `Update_reach_*` | — | — | all 25 witnessed (`spec/output/reach-summary.log`) |

All BFS hunts exceeded diameter 25 and exhausted their bounds. Simulation runs
were the planned follow-up beyond BFS-feasible bounds. All results are bounded
model-checking evidence (`LIMITED_COVERAGE`), not proofs.

## Finding

**MC-1** (High, introduced by the update): an unchanged, already reached
`VoteExtensionsEnableHeight` in a FinalizeBlock parameter update is rejected by
`ValidateUpdate` row 6. The node panics, and every restart re-rejects the stored
block, which is a permanent halt. Evidence: TLC counterexamples in
`spec/output/MC-1_*`, real traces `ve_echo_reached`/`ve_echo_restart_*`/
`ve_enable_then_echo`, reproduction FAIL on 401753b (instrumented and clean)
and PASS on 9dd6e50 (`spec/output/repro-MC-1-*.log`). Details:
`spec/bug-report.md`, `spec/findings.json`.

## Limits

- Bounded domains: heights ≤ 2–3 for BFS (≤ 5 in simulation), ≤ 3 crashes, ≤ 2
  app rollbacks, symbolic non-ABCI parameters (2 identities), VEH ∈ −1..6.
- One node, single code version (rolling binary upgrades across a restart are
  not modeled), no validator-set changes, no Byzantine behaviour, no I/O fault
  injection, app hash not modeled.
- Mock replay of a changed VE value was reached in the model only, not traced.
- The requirement behind `UnchangedVENotRejected` is contested at unit-test
  level (see `spec/invariant-evidence.json` E1). The system-level consequence
  (permanent halt) is reproduced.
- `specula ci-result` and the bug-confirmation controller tool are not
  available here. `spec/final-result.json` is written by hand in the documented
  format and has not been validated by the CLI.
