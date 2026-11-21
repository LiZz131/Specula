# Validation changelog

## Prior (V0, exact-old) history — inherited, unchanged

- V0 converged trace-first in one round with no fixes and no model-checking
  findings (six traces, bounded BFS, three scenario hunts, seven reachability
  witnesses). Archived traces: `traces/archived-v0/`; archived logs:
  `spec/output/prior-v0/`; archived specs: `spec/prior-v0/`.

## Incremental update (case-003, update commit 401753b over baseline 9dd6e50)

### Generation (source-driven model change)

- [model-change] Chapter 1 decision `MODEL_CHANGE_REQUIRED`: the rewritten
  `ConsensusParams.ValidateUpdate` (types/params.go:208-262) flips three
  (current enable height E, proposed U, block height h) cells: E=0,U>h
  reject→accept; E>h,U=0 reject→accept; 0<E<=h,U=E accept→reject. V0's fixed
  `ValidParams` set could not express any height-dependent validity.
- [fix-spec] Representation: parameter record = `[rest, ve]`; FinalizeBlock
  update = `[present, rest, abciPresent, abci]`; `ApplyUpdate` follows
  `ConsensusParams.Update` (params.go:287-318); `ValidateBasic` keeps the
  non-ABCI checks symbolic and adds the negative-height check
  (params.go:188-190); `ValidateUpdateRow` follows the new branch order.
- [fix-spec] `UpdateStateAccepted`/`UpdateStateRejected` guards: ValidateBasic
  then ValidateUpdate (execution.go:614-625); new `rejectRule` records which
  step rejected.
- [fix-spec] New durable `veHist` (enable height in effect at each stored
  height), appended by `SaveBlock` — the extended-commit decision at
  consensus/state.go:1786 is its consumer.
- [fix-inv] `ParameterUpdateReflected` modified (validity clause now
  `ValidateBasic(activeParam)`; installed value is `ApplyUpdate(persisted,
  pending)`); enable-height rules moved to `Update!AcceptedVEUpdateRespectsRules`.
  Evidence E1/E1c/E2 in `invariant-evidence.json`.
- [add] `Update.tla` lens (Affected/Interaction actions, `EnvUpdate`,
  `DischargeContext`) and `UpdateProps.tla` properties: `VEHistoryStable`,
  `VEEnableMonotone`, `StartupLastCommitConsistent`,
  `AcceptedVEUpdateRespectsRules`, `PermittedVEUpdateNotRejected`,
  `UnchangedVEUpdateNotRejected` (after-reached clause contested; not weakened).
- [preflight] SANY on all modules, static cfg/operator resolution and per-action
  variable coverage: `spec/output/sany-*.log`, `spec/output/static-preflight.log`.

### Round 1 — Trace validation (harness rebased, fresh new-version traces)

- [harness] Prior patch applied cleanly to the updated tree
  (`spec/output/harness-rebase-check.log`); instrumentation minimally extended:
  structured `{rest, ve}` params, update records, `rejectRule`, `veHist`
  (state-store params history). Prior V0 patch archived at
  `harness/patches/prior-v0/instrumentation.v0.patch`.
- [harness-fix] Probe effect: the new `veHist` probe called
  `LoadConsensusParams` on a testify-mocked state store inside the replay test
  fixture (pre-handshake setup) and panicked. The probe now recovers and emits an
  empty history (which Trace.tla would reject); fixture events are discarded by
  the handshake reset. No production path changed.
- [result] 16/16 fresh traces (6 prior regression scenarios + 7 update-focused
  ApplyBlock scenarios + 3 update×crash/recovery scenarios) matched `Trace.cfg`
  with `TraceMatched` and all reference + update invariants (except the
  contested `UnchangedVEUpdateNotRejected`, which is checked separately);
  every graph depth = events + 1. No spec repair was needed.
  Logs: `spec/output/trace/*.log`.
- [non-vacuity] 8 single-field trace mutations (rejectRule, veHist,
  proposed abci, active ve, enable-rejected outcome, lastParamChange,
  responseParam, cancel not installed) were all rejected by TLC
  (`spec/output/trace-mutation-controls.log`).
- [observation] `Trace_update_props.cfg`: only `ve_unchanged_after_enable` and
  `replay_real_ve_unchanged_rejected` violate `UnchangedVEUpdateNotRejected`
  (`spec/output/trace-update-props-summary.log`). Old/new code observation
  (`spec/output/observe-old.log`, `observe-new.log`) confirms the three changed
  cells on the real implementation.
- [regression] Scope regression tests pass on the instrumented updated tree:
  types 41/41, state 4/4, consensus replay 36/36
  (`spec/output/regression-*.log`).

### Round 1 — Model checking (entered after the full fresh-trace gate)

- [fix-config] TLC's cfg parser rejects negative literals: negative proposals are
  modeled by `MCVEValues == {-1} \cup VEProposals` (MC.tla) and `BaseVEValues`
  (base.tla). No behavior change.
- [result] `MC.cfg` BFS exhausted: 1,460,638 distinct states, diameter 46, no violation;
  `base.cfg` 174,936 / 39, no violation.
- [bug] UpdateStateRejected: `UnchangedVEUpdateNotRejected` violated in `Update_full.cfg`
  (13-state counterexample, MC-1): an Abci subrecord repeating a reached enable
  height is rejected by ValidateUpdate row 6 → chain halt. Case C candidate
  (spec faithful per traces; property requirement contested; not weakened).
  Also reached by focused/open/Scenario 4/5 configs and deep simulation.
- [result] Core variants (contested property removed) exhausted with no violation:
  full 1,460,638; focused 399,798; open 2,289,011; Scenario 4 502,328; Scenario 5
  1,005,521 distinct states. Discharge holds (129,636); its negative control fails as
  expected. Scenarios 1-3 exhausted with no violation; 4 simulations (30 min each)
  no violation; 20/20 canaries produced witnesses.
- [add] `Update.tla`: `EnvUpdateTooStrong`/`DischargeControlTooStrong` (negative
  control only). Quick campaigns re-run afterwards on the frozen artifacts.
- [repro] `spec/repro/MC-1/`: FAIL on 401753b, PASS on 9dd6e50; model remedy sketch
  satisfies all properties.

### Final regression gate

- 16/16 traces re-validated and all BFS campaigns re-run on the frozen artifacts
  with identical outcomes (`spec/output/final/`); spec checksums unchanged.

## Result

Converged in one trace round and one model-checking round with no semantic spec
repair after validation. Bug hunting: 1 finding (MC-1, update-attributable,
requirement contested). All other properties hold within the checked bounds
(LIMITED_COVERAGE).
