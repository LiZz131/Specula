# Bug Report — CometBFT state execution and recovery (V1 incremental, source 401753b)

## Summary

- Scenarios tested: 3 inherited (V0 Scenarios 1-3) + 7 update Scenarios (U1-U7)
- Bugs found: 1 (MC-1)
- Configs run: `MC.cfg`, `Update_full.cfg`, `Update_full_safety.cfg`,
  `Update_focused.cfg`, `Update_focused_safety.cfg`, `Update_open.cfg`,
  `Update_open_safety.cfg`, `Update_discharge.cfg`,
  `Update_discharge_control.cfg`, `MC_hunt_scenario1_params.cfg`,
  `MC_hunt_scenario2_durability.cfg`, `MC_hunt_scenario3_recovery.cfg`,
  `Update_hunt_unchanged.cfg`, `Update_hunt_unchanged_from_disabled.cfg`,
  `Update_hunt_enable.cfg`, `Update_hunt_recovery.cfg`, `Update_deep_bfs.cfg`,
  `Update_sim_deep.cfg`, `Update_sim_unchanged.cfg`, 17 `MC_reach_*.cfg` and
  8 `Update_reach_*.cfg` canaries.
- All runs are bounded; results are `LIMITED_COVERAGE`, not proofs.

## Bug 1: Unchanged, already-reached VoteExtensionsEnableHeight update is rejected — permanent chain halt

- **ID**: MC-1
- **Scenario**: U2 (re-sent unchanged enable height after it is reached); U7 (enable, then re-send)
- **Severity**: High
- **Invariant violated**: `UnchangedVENotRejected` (`spec/Update.tla`)
- **Config**: `Update_full.cfg` (full `MCNext`); also `Update_focused.cfg`,
  `Update_open.cfg`, `Update_hunt_unchanged.cfg`,
  `Update_hunt_unchanged_from_disabled.cfg`, `Update_sim_unchanged.cfg`
- **Counterexample**: 6 states, `spec/output/MC-1_counterexample_Update_full.log`
  / `.cex.json`; 13-state changed→changed path
  `spec/output/MC-1_counterexample_enable_then_echo.log` / `.cex.json`;
  13-state persistence witness `spec/output/MC-1_consequence_halt_persists.log` / `.cex.json`
- **Update attribution**: introduced by the update. The old code accepted the
  same input through its equality short-cut (`9dd6e50:types/params.go:212-214`),
  which the update removed; old-code control traces and the old-code
  reproduction run pass.

### Trace Summary

`Update_full.cfg` (initial VE height 1, i.e. enabled at the initial height):

1. `Init`: `activeParam = persistedParam = [other |-> "o0", veh |-> 1]`, all heights 0.
2. `MCSaveBlock`: block 1 stored (`h = 1`).
3. `MCApplyBlockStart`.
4. `MCFinalizeBlock([veh |-> 1, other |-> "o0"], TRUE)`: the application returns
   a parameter update whose `Abci` sub-record carries the *unchanged* value 1;
   the resulting record equals the current one.
5. `MCSaveFinalizeBlockResponse`: the response is durable.
6. `MCUpdateStateRejectedVE`: `ValidateUpdateRow(1, TRUE, 1, 1) = 6`
   (`upd <= h`) → rejection; `UnchangedVENotRejected` is violated.

Persistence (`MC-1_consequence_halt_persists`): states 7-13 continue with
`AbortRejectedApply` (production panic), `BeginHandshake`, `SelectRealReplay`
(app height = state height = 0, block store = 1), the deterministic
`FinalizeBlock` with the same response, and `UpdateStateRejectedVE` again —
recovery can never complete.

Changed→changed (`MC-1_counterexample_enable_then_echo`, initial VE height 0):
block 1 enables VE at height 2 (row 7, accepted, committed, saved); block 2 at
`h = 2` returns the unchanged value 2 → row 6 rejection.

### Root Cause

`updateState` validates every non-nil FinalizeBlock parameter update after the
response is saved (`internal/state/execution.go:253-256,612-625`). The updated
`ValidateUpdate` (`types/params.go:219-261`) removed the old "unchanged value →
nil" short-cut (`9dd6e50:types/params.go:212-214`). For `P = U > 0` it now
falls through rows 3-5 to row 6 (`types/params.go:243-248`): `U <= h` →
"vote extensions cannot be updated to a past or current height". Rows 3 and 9
still accept unchanged values (`P = U = 0`, and `P = U > h`), so the same
"no change" input is accepted before the enable height and rejected from the
enable height on.

The error makes `ApplyBlock` fail (`execution.go:279-282`), which consensus
and block sync treat as fatal (`internal/consensus/state.go:1834-1836`,
`internal/blocksync/reactor.go:530-533`). Because the block and the response
are already durable and the application did not commit, every restart takes
the real-app final-block replay path (`internal/consensus/replay.go:409-415`),
re-executes the deterministic FinalizeBlock and is rejected again; the
handshake fails (`replay.go:268-271`, `node/setup.go:200`). All honest nodes
run the same deterministic code, so the chain halts at that height.

The application behavior is contract-compliant: the ABCI application
requirements forbid only *changing* a non-zero value
(`spec/abci/abci++_app_requirements.md:776-777`), state that every non-empty
parameter field is applied in full and that applications re-send unchanged
fields (`:783-790`), and that a non-nil `ConsensusParams` is used (`:800-807`).
`ConsensusParams.ToProto()` always populates `Abci` (`types/params.go:320-341`),
and the in-tree pattern `state_test.go:TestConsensusParamsChangesSaveLoad`
forwards complete parameter sets with `cp.ToProto()`. The old unit test
`old-source/types/params_test.go:196-204` ("no error when unchanged") asserted
acceptance.

Requirement caveat: the updated unit-test table
(`new-source/types/params_test.go:168-169`) and the row-6 comment
(`types/params.go:214`) expect `ValidateUpdate` to return an error for this
input at unit level. Those tests do not cover the system consequence (a
permanent halt). The property was not edited toward the implementation; see
`spec/invariant-evidence.json` (E1, T1, T1r, T6).

### Real-implementation evidence

- Instrumented traces on 401753b, validated by TLC against the reference:
  `traces/ve_echo_reached.ndjson`, `traces/ve_enable_then_echo.ndjson`,
  `traces/ve_echo_restart_apply.ndjson`,
  `traces/ve_echo_restart_handshake.ndjson` (`spec/output/trace-full-*.log`).
- Old-code control on 9dd6e50: the same scenarios are accepted
  (`spec/output/control-old-ve-echo-reached.log`,
  `spec/output/control-old-ve-echo-restart-apply.log`).
- Instrumentation-free reproduction: `harness/repro_MC-1.sh`
  (`harness/repro/specula_mc1_repro_test.go`):
  - updated 401753b (instrumented): FAIL — `spec/output/repro-MC-1-updated-401753b.log`;
  - updated 401753b (clean export): FAIL — `spec/output/repro-MC-1-updated-clean-401753b.log`;
  - baseline 9dd6e50: PASS — `spec/output/repro-MC-1-control-baseline-9dd6e50.log`.

### Affected Code

- `types/params.go:243-248`: row 6 rejects `U <= h` even when `U == P` (unchanged).
- `types/params.go:219-261`: removed equality short-cut (old `9dd6e50:types/params.go:212-214`).
- `internal/state/execution.go:612-625`: validation after the durable response save.
- `internal/consensus/state.go:1834-1836`, `internal/blocksync/reactor.go:530-533`: fatal handling.
- `internal/consensus/replay.go:409-415`: real-app replay re-runs the rejection.

### Recommendation

Accept updates that leave `VoteExtensionsEnableHeight` unchanged before the
row-6 check (e.g. `if updated.Abci.VoteExtensionsEnableHeight ==
params.ABCI.VoteExtensionsEnableHeight { return nil }` after row 2), keeping
rows 4/6/8 for actual changes. Re-check with `Update_full.cfg` and
`harness/repro_MC-1.sh`.

---

## Not Reproduced

| Scenario | Config | States explored | Result |
|---|---|---|---|
| Standard convergence | `MC.cfg` | 40,119 distinct, depth 34, queue empty | No violation |
| U1/U4/U5 on full `MCNext` | `Update_full_safety.cfg` | 40,119 distinct, depth 34, queue empty | No violation |
| U1/U4/U5 concrete focus (h≤3) | `Update_focused_safety.cfg` | 59,267 distinct, depth 39, queue empty | No violation |
| U1/U4/U5 open focus | `Update_open_safety.cfg` | 80,837 distinct, depth 34, queue empty | No violation (discharged) |
| Discharge of omitted context | `Update_discharge.cfg` | 53,799 distinct, depth 41, queue empty | Holds; strict control violated as expected |
| Scenario 1 params | `MC_hunt_scenario1_params.cfg` | 7,174 distinct, depth 31 | No violation |
| Scenario 2 durability | `MC_hunt_scenario2_durability.cfg` | 8,643 distinct, depth 31 | No violation |
| Scenario 3 recovery | `MC_hunt_scenario3_recovery.cfg` | 19,161 distinct, depth 33 | No violation |
| U1/U3/U4/U5 (h≤3) | `Update_hunt_enable.cfg` | 7,567 distinct, depth 38 | No violation |
| U6 crash/replay | `Update_hunt_recovery.cfg` | 35,363 distinct, depth 36 | No violation |
| Reference + update safety (h≤3) | `Update_deep_bfs.cfg` | 158,158 distinct, depth 41, queue empty | No violation |
| Reference + update safety (h≤5) | `Update_sim_deep.cfg` | simulation, see `spec/output/update-sim-deep.log` | No violation (budget-limited) |

Reachability: all 25 canaries (`spec/output/reach-summary.log`) produced their
expected witnesses, including every accepting/rejecting `ValidateUpdate` row
(1, 3-9), basic rejection (row 2 masked), real/mock replay, mock replay of an
accepted VE change, and the halt-persists path.

## Spec fixes during checking

None. One cfg-syntax fix (negative literals moved to `VEHRangeNeg*` operators)
and one Trace-wrapper field guard (`proposedOtherValid` only on
`FinalizeBlock`) were made before campaign entry; see `spec/changelog.md`.
