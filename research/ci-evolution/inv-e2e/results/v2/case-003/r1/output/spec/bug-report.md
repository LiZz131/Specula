# Bug Report — CometBFT state execution and recovery (case-003 updated revision)

## Summary

- Source under test: artifact commit `401753b` ("update") over `9dd6e50` ("baseline");
  only `ConsensusParams.ValidateUpdate` (types/params.go:208-262) changed.
- Scenarios tested: 5 (V0 Scenarios 1-3 rechecked, update Scenarios 4-5 new).
- Model-checking findings: 1 (MC-1, update-attributable, requirement contested).
- Configs run: `MC.cfg`, `Update_full.cfg`, `Update_full_core.cfg`,
  `Update_focused(.cfg|_core.cfg)`, `Update_open(.cfg|_core.cfg)`,
  `Update_discharge.cfg` (+ negative control), `MC_hunt_scenario1..3`,
  `Update_hunt_scenario4/5 (+_core)`, 20 `MC_reach_*` canaries, simulations
  (see the table at the end).
- Coverage status: bounded BFS (exhausted within each configuration's bounds) plus
  budget-limited simulation — LIMITED_COVERAGE, not a proof.

## Bug 1: Re-sending an unchanged, already reached VoteExtensionsEnableHeight is rejected and halts the chain

- **ID**: MC-1
- **Scenario**: 4 (enable-height lifecycle); also reached by Scenario 5, `Update_focused`, `Update_open`
- **Severity**: High (deterministic halt of every node at the block; persists across restarts) — trigger requires an application that includes the unchanged `Abci` subrecord
- **Invariant violated**: `UnchangedVEUpdateNotRejected` (`spec/UpdateProps.tla`)
- **Config**: `Update_full.cfg` (complete `MCNext`, module `Update`)
- **Counterexample**: 13 states, `spec/output/mc/MC-1_Update_full_counterexample.log`
  (also `output/mc/Update_full.cex.json`, `output/mc/Update_full.cex.tla`,
  TLC trace-explorer files in `output/ttrace/mc_Update_full/`)
- **Update attribution**: introduced by the update — the path crosses the affected
  action `UpdateStateRejected` and the changed row-6 cell (U = E, 0 < E <= h), which
  the old revision accepted.

### Trace Summary

1. Init: genesis params `[rest |-> "r0", ve |-> 2]` (vote extensions enabled from height 2).
2. States 2-8: block 1 is saved, finalized with an update that carries no Abci
   subrecord, accepted (row 1), the app commits, the state is saved.
3. State 9: block 2 is saved; `veHist = <<2, 2>>` (height 2 requires extensions,
   so consensus stored an extended commit for it).
4. State 11: `FinalizeBlock` for height 2 returns `ConsensusParamUpdates` with
   `Abci{VoteExtensionsEnableHeight: 2}` — the current value, unchanged.
5. State 12: the response is saved (durable).
6. State 13: `UpdateStateRejected` with `rejectRule = "r6"`: `ValidateUpdate(E=2, U=2, h=2)`
   reaches row 6 (`U <= h`). The candidate parameters equal the current ones.

The model then continues with `AbortRejectedApply` (consensus panic) and, after a
restart, `SelectRealReplay` → `FinalizeBlock(p = responseParam)` →
`UpdateStateRejected` again: the node never passes height 2.

### Real-implementation evidence

| Evidence | Result |
|---|---|
| `traces/ve_unchanged_after_enable.ndjson` (validated by `Trace.cfg`) | genesis E=1; height 1 Block-only update accepted; height 2 complete params (`ToProto`, unchanged values) → `UpdateStateRejected`, `rejectRule=r6` |
| `traces/replay_real_ve_unchanged_rejected.ndjson` (validated) | after the rejection, restart → real replay → same response → rejected again; `Handshake` returns "error on replay" |
| `spec/output/trace-update-props-summary.log` | only these two real traces violate `UnchangedVEUpdateNotRejected` |
| `spec/output/observe-old.log` vs `observe-new.log` (same test, both trees) | O3 (Abci-only, unchanged after enable), O11 (complete params every block, enable height 1), O12 (enable 0→3 at h=1, complete params at h=4): **old ACCEPTED (O3, O11) / new REJECTED (O3, O11, O12 at h=4)**; O12 on the old tree fails earlier at the enable itself (the defect the update fixes) |

### Root Cause

The rewrite removed the old first branch
`if params.ABCI.VoteExtensionsEnableHeight == updated.Abci.VoteExtensionsEnableHeight { return nil }`
(old types/params.go:212-214). In the new branch order an unchanged value is
handled like any other value: row 3 covers only `E <= 0, U == 0`, rows 4/5 only
`U == 0`, so a positive `U == E` falls to row 6 (types/params.go:243-248), which
rejects every `U <= h`. Once the enable height is reached (`E <= h`), re-stating it
is therefore an error. `updateState` (internal/state/execution.go:622-625) returns
that error; `ApplyBlock` fails before `Commit` (execution.go:279-282); consensus
panics (internal/consensus/state.go:1834-1836); handshake replay re-executes the
block and fails the same way (internal/consensus/replay.go:266-270, 408-415).

### Requirement assessment (contested)

For treating the rejection as a defect:
- spec/abci/abci++_app_requirements.md:776-777 — "Once set to a value different from 0,
  its value must not be changed." Re-sending the same value does not change it.
- :785-786 — "Each field that is not empty will be applied in full." and :803 —
  "If `ConsensusParams` is not `nil`, CometBFT will use it."
- internal/state/state_test.go:1044 — `TestConsensusParamsChangesSaveLoad` sends
  `cp.ToProto()` (always includes `Abci`, types/params.go:320-342) as the update
  at every height: complete-record updates are an in-tree producer pattern. With
  any reached enable height this pattern now halts (observe O11).
- /work/old-source/types/params_test.go:196-204 — V0 test "no error when unchanged"
  (100 → 100 at height 500, `NoError`), removed by the update.
- .changelog/unreleased/bug-fixes/0000-asa-2024-001-fix-validate.md — the update is
  a fix for validation-caused chain halts.

Against (the update's own intent):
- types/params_test.go:168-169 (updated) expects an error for
  "current: 100, 100 -> 100" and "current: 300, 100 -> 100".
- types/params.go:215 (updated table comment) row 6: any value `<= height` is rejected.
- spec :776 "Must always be set to a future height." if repeating a value counts as setting it.

Per the incremental property rules the `after-reached` clause is `unknown`, so the
property was **not** weakened toward the implementation; the counterexample is
reported with this conflict. The model, the traces, and both code observations
agree on the behavior; only the requirement is disputed.

### Affected Code

- `types/params.go:219-262` — `ValidateUpdate`; specifically rows 3-6 (228-248).
- `internal/state/execution.go:614-631` — `updateState` calls `ValidateUpdate` for every non-nil update.
- `internal/consensus/state.go:1834-1836` — `ApplyBlock` error is fatal.
- `internal/consensus/replay.go:403-433` — restart replays the same block and re-validates.

### Recommendation

Accept an unchanged value before the height checks, e.g. after row 2:
`if updated.Abci.VoteExtensionsEnableHeight == params.ABCI.VoteExtensionsEnableHeight { return nil }`.
This keeps every safety rule the new table enforces (no retroactive enable,
no disable/modify after the height is reached) — the model's `VEHistoryStable`,
`VEEnableMonotone`, `StartupLastCommitConsistent` and
`AcceptedVEUpdateRespectsRules` do not depend on rejecting `U = E` — and
restores the V0 acceptance of complete-record updates. Alternatively, document
that applications must omit the `Abci` subrecord unless they change it.

---

## Not Reproduced

| Scenario / check | Config | States explored | Result |
|---|---|---|---|
| Reference safety (standard round) | `MC.cfg` | BFS 1,460,638 distinct, diameter 46, exhausted | No violation |
| Update properties except MC-1, full `MCNext` | `Update_full_core.cfg` | BFS 1,460,638 distinct, diameter 46, exhausted | No violation |
| Concrete focused (Affected ∪ Interaction), 4 heights | `Update_focused_core.cfg` | BFS 399,798 distinct, diameter 45, exhausted | No violation |
| Open focused with `EnvUpdate` | `Update_open_core.cfg` | BFS 2,289,011 distinct, diameter 45, exhausted | No violation (discharged) |
| Discharge of omitted context | `Update_discharge.cfg` | BFS 129,636 distinct, diameter 46 | `DischargeContext` holds; negative control `Update_discharge_control.cfg` fails as expected |
| Scenario 1 (params) | `MC_hunt_scenario1_params.cfg` | BFS 4,491 distinct, diameter 22, exhausted | No violation |
| Scenario 2 (durability) | `MC_hunt_scenario2_durability.cfg` | BFS 23,072 distinct, diameter 43 | No violation |
| Scenario 3 (recovery) | `MC_hunt_scenario3_recovery.cfg` | BFS 65,161 distinct, diameter 46 | No violation |
| Scenario 4 core (enable-height lifecycle, 5 heights) | `Update_hunt_scenario4_ve_lifecycle_core.cfg` | BFS 502,328 distinct, diameter 43 | No violation |
| Scenario 5 core (enable height × crash/replay) | `Update_hunt_scenario5_ve_recovery_core.cfg` | BFS 1,005,521 distinct, diameter 49 | No violation |
| Retroactive enable/disable of a decided height (U-MC-1) | all of the above | — | Not reproduced (`VEHistoryStable`, `VEEnableMonotone`, `StartupLastCommitConsistent`) |
| Rejection of a protocol-permitted enable/cancel/reschedule (U-MC-2) | all of the above | — | Not reproduced (`PermittedVEUpdateNotRejected`); the V0 behavior violates it (evidence E9) |

Configurations that include `UnchangedVEUpdateNotRejected` (`Update_full`,
`Update_focused`, `Update_open`, `Update_hunt_scenario4/5`) all stop at the MC-1
counterexample (6–13 states); their `_core` variants carry the rest of the search.

## Spec changes during hunting

None. Trace validation and every campaign ran on the same final artifacts.
