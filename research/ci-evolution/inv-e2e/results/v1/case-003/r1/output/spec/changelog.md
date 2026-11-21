# Spec changelog

## V1 incremental run (source 9dd6e50 -> 401753b)

### Generation (Chapters 1-5)
- [update] Disposition MODEL_CHANGE_REQUIRED: `ValidateUpdate` (types/params.go:208-261) moves three input classes between accept and reject (analysis-report.md §2-3).
- [repair] Parameter representation: V0 symbolic `Params`/static `ValidParams` replaced by `[other, veh]` records with `ValidateBasicOK` (types/params.go:145-205) — V0 could not express a height/current-value dependent decision, and V0 Trace.cfg derived `ValidParams` from observed acceptances (decision never independently checked).
- [update] `ValidateUpdateRow` transcribes rows 1-9 of the new table; `UpdateStateAccepted` guard uses it (execution.go:612-631).
- [update] `UpdateStateRejected` split into `UpdateStateRejectedBasic` (execution.go:617-620) and `UpdateStateRejectedVE` (execution.go:622-625).
- [update] `FinalizeBlock(p, abci)`, `pendingAbciPresent`, `responseAbciPresent`: Abci presence (row 1; `Update` keeps VEH when absent, types/params.go:314-316); replay determinism extended to the flag.
- [add] Structural invariants `InstalledParamsBasicValid`, `ValidationInputStable` (base.tla).
- [add] Update.tla: Affected/Interaction actions, `EnvUpdate` for `AppReportsOlderHeight`/`ReplayAppBlock`, `DischargeContext`, properties `VEReachedImmutable`, `VEChangeOnlyToFuture`, `EnableFromDisabledNotRejected`, `UnchangedVENotRejected`; canaries.
- [cfg] MC.cfg/hunts/canaries re-parameterized (`Others`, `ValidOthers`, `VEHeights`, `InitialOthers`, `InitialVEHs`).
- [preflight] SANY OK for base/MC/Trace/Update; static cfg-name and variable-assignment check OK (output/generation-preflight.log); property separating/control states evaluated by TLC (spec/evidence/E*, output/evidence-constructed.log).

### Round 1 - Trace Validation
- [harness] Prior V0 patch applied cleanly to 401753b (output/harness-rebase-check.log); preserved as harness/patches/v0-instrumentation.patch.
- [harness] V1 fields added: parameter records `{other, veh}`, `activeOtherValid`, `pendingAbciPresent`, `responseAbciPresent`, FinalizeBlock `abciPresent`/`proposedOtherValid`, UpdateStateRejected `reason`/`error`.
- [harness] 13 update-focused scenarios added (internal/state/specula_trace_test.go: TestSpeculaTraceVE/*, TestSpeculaTraceVEEnableThenEcho, TestSpeculaTraceVEEchoRestart).
- [fix] Trace.tla `TraceValidOthers`: read `proposedOtherValid` only where emitted (FinalizeBlock); first replay failed in an ASSUME with "nonexistent field" (output/trace-ve_echo_reached.log, rerun MATCHED). Replay-configuration/interpretation fix; no base change.
- [result] Full fresh suite (19 traces) MATCHED with TraceMatched: output/trace-full-summary.log.
- [control] 5 field mutations rejected at the mutated event (output/mutation-*.log); old-code (9dd6e50) traces fail against V1 exactly on the changed rows and match on unchanged rows (output/control-old-vs-v1-summary.log).

### Round 1 - Model Checking
- [cfg] Negative VEH literals moved to `VEHRangeNeg*` operators in MC.tla (TLC cfg cannot spell -1; output/mc-standard.log first attempt exit 151). No semantic change.
- [result] MC.cfg: 40,119 distinct states, depth 34, no violation. No spec modification -> converged (trace suite unaffected: base.tla/Trace.tla unchanged after the full replay).
- [bug] UpdateStateRejectedVE: `UnchangedVENotRejected` violated (Case C, MC-1) on full MCNext, focused, open and hunt configs; reproduced on the implementation (harness/repro_MC-1.sh). Saved: output/MC-1_counterexample_Update_full.*, output/MC-1_counterexample_enable_then_echo.*, output/MC-1_consequence_halt_persists.*.
- [result] Remaining update properties hold on full/focused/open configs; discharge holds; discharge falsifiability control violated as expected.
- [add] Update.tla canaries `ReachedReplayRejectionOfUnchanged`, `ReachedHaltPersists`; control `DischargeStrictControl`; cfgs Update_hunt_unchanged_from_disabled, Update_reach_replay_rejection_unchanged, Update_reach_halt_persists, Update_discharge_control, Update_deep_bfs, Update_sim_deep, Update_sim_unchanged. Observers/configs only; no behavior change.

### Final trace inventory (fresh, new-version, all MATCHED)
apply_valid, apply_rejected, replay_app_only, replay_real, replay_mock, replay_none,
ve_enable_future, ve_enable_current, ve_echo_disabled, ve_echo_reached, ve_echo_future,
ve_disable_reached, ve_disable_future, ve_move_reached, ve_move_future, ve_negative,
ve_enable_then_echo, ve_echo_restart_apply, ve_echo_restart_handshake.
Archived V0 traces (traces/archive-v0/) are superseded by representation change (string fingerprints vs V1 records); their scenarios were re-run fresh.

### Result
Converged in 1 round (trace + MC). Bug hunting: 1 bug found (MC-1). All MC results are bounded (LIMITED_COVERAGE).

---

## V0 (prior run, retained)


## Round 1 — Trace validation

- [result] Six fresh, nonempty implementation traces matched every event and
  post-state field in `Trace.tla`; `TraceMatched` was satisfied in all runs.
- [classification] No implementation/spec/trace mismatch was encountered, so
  no property, action, or capture point was weakened or changed.

## Round 1 — Model checking

- [result] `MC.cfg` completed its bounded BFS with 5,126 distinct states and no
  invariant violation.
- [result] The three scenario hunting configurations completed bounded BFS with
  no invariant violation. Scenario 1's diameter was 18, so a depth-100 random
  simulation followed and checked 80,000,001 states across 800,000 traces with
  no violation. Scenario 2 and 3 BFS diameters were 27 and 33.
- [non-vacuity] Seven deliberately negated reachability invariants each failed
  as expected, preserving witnesses for accepted/rejected updates, crash,
  app-only replay, real replay, mock replay, and handshake completion.

## Result

Converged in one trace-first round with no fixes and no model-checking findings.
All conclusions remain limited by the documented model and environment bounds.

