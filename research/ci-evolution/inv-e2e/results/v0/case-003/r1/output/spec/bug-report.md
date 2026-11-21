# Bug Report — CometBFT state execution and recovery (V1, incremental)

## Summary

- Source: updated tree (artifact commit `update`, `401753b0…`); delta in
  `types/params.go:208-261` (`ConsensusParams.ValidateUpdate`).
- Scenarios tested: U1 (first enablement), U2 (unchanged re-send after
  enablement), U3 (VE safety of the relaxed rule / consumers of decided
  heights), U4 (crash cuts, real and mock replay re-validation), plus the
  inherited V0 Scenarios 1-3.
- Bugs found: **1** (MC-1, actual model-checking counterexample, confirmed by
  Level-0 reproduction on the real implementation with an old-tree control).
- Configs run: `MC.cfg`, `Update_full.cfg`, `Update_full_safety.cfg`,
  `Update_focused*.cfg`, `Update_open*.cfg`, `Update_discharge*.cfg`,
  `Update_hunt_U1..U5*.cfg`, `Update_sim_deep_safety.cfg`,
  `MC_hunt_scenario1..3*.cfg`, 7 `MC_reach_*` and 11 `Update_reach_*`
  canaries. Outcomes: `validation-report.md` and `spec/output/mc-v1-*.log`.

## Bug 1: Updated ValidateUpdate rejects an unchanged VoteExtensionsEnableHeight once vote extensions are enabled, halting the chain

- **ID**: MC-1
- **Scenario**: U2 (unchanged re-send after enablement); consequence via U4
  (restart/real replay)
- **Severity**: High
- **Invariant violated**: `ContractLegalUpdateAccepted` (P-U1, `Update.tla`)
- **Config**: `Update_full.cfg` (full `MCNext`); also `Update_focused.cfg`,
  `Update_open.cfg`, `Update_hunt_U1_enable_from_zero.cfg`,
  `Update_hunt_U2_unchanged_after_enable.cfg`, `Update_hunt_U4_recovery.cfg`
- **Counterexample**: 6 states, `spec/output/mc-v1-MC-1-cex.log`,
  `spec/output/MC-1-counterexample.json`; upgrade-path variant (13 states,
  VE disabled at genesis): `spec/output/mc-v1-hunt-U1_enable_from_zero.log`,
  `spec/output/cex-hunt-U1_enable_from_zero.json`; consequence witness
  (9 states, rejected again on replay):
  `spec/output/mc-v1-reach_LegalUpdateRejectedOnReplay.log`.

### Trace Summary

Full-model counterexample (`Update_full.cfg`):

1. Init: `persistedParam = activeParam = [body |-> "b0", veh |-> 1]`
   (vote extensions enabled from height 1, as `internal/test/params.go` and the
   ABCI spec's "enable at genesis" path allow).
2. `MCSaveBlock`: block 1 stored.
3. `MCApplyBlockStart`.
4. `MCFinalizeBlock([body |-> "b0", abci |-> 1])`: the application returns a
   consensus-parameter update whose Abci sub-record carries the **unchanged**
   enable height 1 (here even the body is unchanged: an exact no-op update).
5. `MCSaveFinalizeBlockResponse`: the response is durable.
6. `MCUpdateStateRejected("update")`: `ValidateUpdateOK` row 6 (`u <= h`,
   1 <= 1) rejects. `ContractLegalUpdateAccepted` is violated.

U1 hunt variant: genesis `veh = 0`; block 1 enables at height 2 (row 7,
accepted, committed, saved); block 2's response re-sends `abci = 2`; row 6
(2 <= 2) rejects at height 2.

Consequence witness: after the rejection, `AbortRejectedApply` (consensus
panic) → `BeginHandshake` → `SelectRealReplay` (app did not commit) →
`FinalizeBlock` must return the same response (determinism) → rejected again.

### Root Cause

`types/params.go:219-261` (updated). Its own table states row 6
`| * | <=height | vote extensions cannot be updated to a past height` without
an exception for `updated == params`. The old code returned `nil` whenever
`params.ABCI.VoteExtensionsEnableHeight == updated.Abci.VoteExtensionsEnableHeight`
(old `types/params.go:211-213`); the update removed that short-circuit
(new row 3 only keeps the `0 -> 0` case). The resulting rule is
`accept <=> u >= 0 /\ ~Enabled(c,h) /\ ~Enabled(u,h)`, so every update that
carries a non-nil Abci sub-record is rejected once vote extensions are
enabled — including one that leaves the value unchanged.

The ABCI application contract permits (and the update procedure invites)
re-sending unchanged values: `spec/abci/abci++_app_requirements.md:779-789`
("Each field that is not empty will be applied in full … applications must
also set the other … fields … even if they are unchanged"); `:776-777`
("Once set to a value different from 0, its value must not be changed" — an
unchanged value is not a change). `ConsensusParams.ToProto()`
(`types/params.go:320-341`) always fills `Abci`, and the repository's own tests
construct updates from complete parameter values
(`internal/state/state_test.go:1044`).

Consequence path: `updateState` error (`internal/state/execution.go:622-625`)
→ `ApplyBlock` returns before `Commit` (`:279-282`) → consensus
`finalizeCommit` panics (`internal/consensus/state.go:1834-1836`) → receive
routine logs `CONSENSUS FAILURE!!!` and stops (`:791-803`). On restart the
handshake replays the stored block through the real application
(`internal/consensus/replay.go:408-415`), which deterministically returns the
same update; validation rejects again and `Handshake` fails
(`replay.go:266-270`), so the node cannot start. Every honest node rejects
deterministically: the chain halts at that height.

### Affected Code

- `types/params.go:243-248`: row 6 rejects `u <= h` without `u == c` exception.
- `types/params.go:229-231`: row 3 keeps only the `0 -> 0` unchanged case.
- `internal/state/execution.go:622-625`: caller turns the error into an
  `ApplyBlock` failure.
- `internal/consensus/state.go:1834-1836`, `internal/consensus/replay.go:408-415,513-516`:
  fatal consequence and non-recovering replay.

### Recommendation

Accept an update whose Abci enable height equals the current one before the
past/current-height checks (e.g. reinstate
`if updated.Abci.VoteExtensionsEnableHeight == params.ABCI.VoteExtensionsEnableHeight { return nil }`
after the nil/negative checks), keeping the update's new acceptance of first
enablement and cancellation of a not-yet-reached height. Re-run P-U1..P-U4
(`Update_full.cfg`) and the harness after the change.

### Confirmation

`spec/confirmation-MC-1.md` — REPRODUCED (Level 0, real consensus node);
old-tree control shows the behavior is introduced by the update.

---

## Not Reproduced (no violation within bounds)

| Scenario / property | Config | States explored (distinct) / depth | Result |
|---|---|---|---|
| Reference invariants (standard convergence) | `MC.cfg` | 75,944 / 34 (exhausted) | No violation |
| P-U2..P-U4 over full `MCNext` | `Update_full_safety.cfg` | 75,944 / 34 (exhausted) | No violation |
| P-U2..P-U4, concrete focus | `Update_focused_safety.cfg` | 32,634 / 34 (exhausted) | No violation |
| P-U2..P-U4, open focus + discharge | `Update_open_safety.cfg`, `Update_discharge.cfg` | 306,868 / 34; 75,944 / 34 | No violation; rely discharged |
| U1 safety variant | `Update_hunt_U1_enable_from_zero_safety.cfg` | 5,498 / 38 | No violation |
| U2 safety variant | `Update_hunt_U2_unchanged_after_enable_safety.cfg` | 2,373 / 31 | No violation |
| U3 VE safety | `Update_hunt_U3_ve_safety.cfg` | 7,625 / 38 | No violation |
| U4 recovery safety | `Update_hunt_U4_recovery_safety.cfg` | 29,037 / 36 | No violation |
| U5 deep (height 4) | `Update_hunt_U5_deep_safety.cfg` | 289,761 / 48 | No violation |
| Deep simulation (height 6) | `Update_sim_deep_safety.cfg` | see `validation-report.md` | No violation (budget-limited) |
| V0 Scenario 1-3 | `MC_hunt_scenario1..3*.cfg` | 1,728 / 18; 6,201 / 31; 14,570 / 33 | No violation |
| V0 Scenario 1 simulation | `MC_hunt_scenario1_params.cfg` (sim) | see `validation-report.md` | No violation (budget-limited) |

All results are bounded (`LIMITED_COVERAGE`), not proofs.
