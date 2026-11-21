# Modeling Brief Coverage — V1 incremental (source 401753b)

Filled from the actual cfg files (`grep -n INVARIANT` / `PROPERTY`), not from
intent. V0 sections are retained at the end for history; where they conflict,
this V1 section governs.

## Scenarios (brief §2 and §V1-2)

| Scenario | Hunt / campaign cfg | Reachability witness | Trace |
|---|---|---|---|
| V0-1 Parameter validation and installation | `MC_hunt_scenario1_params.cfg` | `MC_reach_accepted`, `MC_reach_rejected`, `MC_reach_basic_rejection` | `apply_valid`, `apply_rejected` |
| V0-2 Ordered durable boundaries | `MC_hunt_scenario2_durability.cfg` | `MC_reach_crash` | `apply_valid` |
| V0-3 Height-matrix startup replay | `MC_hunt_scenario3_recovery.cfg` | `MC_reach_app_replay`, `MC_reach_real_replay`, `MC_reach_mock_replay`, `MC_reach_handshake_complete` | `replay_*` |
| U1 Enable from disabled (row 7) | `Update_hunt_enable.cfg`, `Update_full*.cfg` | `MC_reach_row7`, `Update_reach_saved_enable`, `Update_reach_enable_attempt_rejected` | `ve_enable_future` |
| U2 Unchanged re-send after reached (row 6) | `Update_hunt_unchanged.cfg`, `Update_full.cfg`, `Update_focused.cfg`, `Update_open.cfg`, `Update_sim_unchanged.cfg` | `MC_reach_row6`, `Update_reach_replay_rejection_unchanged`, `Update_reach_halt_persists` | `ve_echo_reached`, `ve_echo_restart_apply`, `ve_echo_restart_handshake` |
| U3 Cancel a future height (row 5) | `Update_hunt_enable.cfg` | `MC_reach_row5` | `ve_disable_future` |
| U4 Reached height frozen (rows 4, 8) | `Update_hunt_enable.cfg`, `Update_full_safety.cfg` | `MC_reach_row4`, `MC_reach_row8`, `Update_reach_reached_ve_accepted` | `ve_disable_reached`, `ve_move_reached` |
| U5 Future-only targets (rows 3, 6, 7, 9; row 2 masked) | `Update_hunt_enable.cfg`, `Update_full_safety.cfg` | `MC_reach_row3`, `MC_reach_row9`, `Update_reach_future_change_accepted`, `MC_reach_basic_rejection` | `ve_enable_current`, `ve_move_future`, `ve_echo_future`, `ve_echo_disabled`, `ve_negative` |
| U6 Changed decision across crash/replay | `Update_hunt_recovery.cfg` | `Update_reach_mock_replay_ve_change`, `MC_reach_replay_ve_rejection` | `ve_echo_restart_handshake`, `replay_real`, `replay_mock` |
| U7 Changed → changed | `Update_hunt_unchanged_from_disabled.cfg`, `Update_hunt_unchanged.cfg` | (counterexample itself) | `ve_enable_then_echo` |

## Invariants (brief §5 / §V1-5) — enabled where

| Invariant | Defined in | Enabled in (actual cfgs) |
|---|---|---|
| `TypeOK` / `MCTypeOK` | base / MC | `base.cfg`, `Trace.cfg`, `MC.cfg`, all hunts and Update cfgs |
| `PersistedHeightRelationships` | base | `MC.cfg`, `base.cfg`, `Trace.cfg`, scenario2/3 hunts, `Update_deep_bfs`, `Update_sim_deep` |
| `SuccessfulApplyAdvancesExactlyOne` | base | `MC.cfg`, `base.cfg`, `Trace.cfg`, scenario2 hunt, deep cfgs |
| `RejectedUpdateDoesNotInstall` | base | `MC.cfg`, `base.cfg`, `Trace.cfg`, scenario1 hunt, all `Update_full/focused/open*` (control), deep cfgs |
| `ParameterUpdateReflected` | base | `MC.cfg`, `base.cfg`, `Trace.cfg`, scenario1 hunt, `Update_hunt_enable`, `Update_hunt_recovery`, deep cfgs |
| `NormalPhaseIsSynchronized` | base | `MC.cfg`, `base.cfg`, `Trace.cfg`, scenario2/3 hunts, all `Update_full/focused/open*` (control), `Update_hunt_enable/recovery`, deep cfgs |
| `RecoveryNormalOnlySupported` | base | `MC.cfg`, `base.cfg`, `Trace.cfg`, scenario3 hunt, `Update_hunt_recovery`, deep cfgs |
| `InstalledParamsBasicValid` | base | `MC.cfg`, `base.cfg`, `Trace.cfg`, scenario1 hunt, deep cfgs |
| `ValidationInputStable` | base | `MC.cfg`, `base.cfg`, `Trace.cfg`, deep cfgs |
| `VEReachedImmutable` | Update | `Update_full*`, `Update_focused*`, `Update_open*`, `Update_hunt_enable`, `Update_hunt_recovery`, deep cfgs |
| `VEChangeOnlyToFuture` | Update | same as above |
| `EnableFromDisabledNotRejected` | Update | same as above |
| `UnchangedVENotRejected` | Update | `Update_full`, `Update_focused`, `Update_open`, `Update_hunt_unchanged`, `Update_hunt_unchanged_from_disabled`, `Update_sim_unchanged` (violated: MC-1) |
| `DischargeContext` (action property) | Update | `Update_discharge.cfg` |

`*_safety.cfg`, `Update_deep_bfs.cfg` and `Update_sim_deep.cfg` omit only
`UnchangedVENotRejected`, whose violation is recorded as MC-1; this isolates
the remaining properties and is not a weakening.

## Model-checkable findings (brief §V1-6.1)

| Finding | Targeting cfg | Outcome |
|---|---|---|
| V1-MC-1 unchanged VEH rejected | `Update_full.cfg`, `Update_hunt_unchanged*.cfg` | **violated → MC-1** (Case C; reproduced) |
| V1-MC-2 enable from 0 rejected | `Update_full_safety.cfg`, `Update_hunt_enable.cfg` | holds (bounded); old-code control trace shows the old behaviour is detected |
| V1-MC-3 reached VEH moved / past VEH set | `Update_full_safety.cfg`, `Update_hunt_enable.cfg` | holds (bounded) |
| V1-MC-4 replay consistency | `Update_hunt_recovery.cfg`, canaries | holds (bounded); mock replay of accepted VE change reached |

## Trace field consumption (Trace.tla)

| Field | Consumed by |
|---|---|
| `state.*` heights, phase, replay, pending, response, validation | `ValidatePostState` (every event) |
| `activeParam`, `persistedParam`, `pendingParam`, `responseParam` (`other`, `veh`) | `ValidatePostState` record equality; `TraceInit` |
| `pendingAbciPresent`, `responseAbciPresent` | `ValidatePostState`; `TraceInit` |
| `activeOtherValid` | `TraceValidOthers` and a `ValidatePostState` equality |
| `msg.proposedParam`, `msg.abciPresent` | `FinalizeBlock(p, abci)` arguments; equality with pending state at Update* events |
| `msg.proposedOtherValid` | `TraceValidOthers` |
| `msg.reason` | dispatch to `UpdateStateRejectedBasic` / `UpdateStateRejectedVE` |
| `msg.updatePresent` | consistency check at `FinalizeBlock` |
| `msg.mode` | real vs mock replay selection |

Consumption is demonstrated by mutation controls (reason, abciPresent,
proposed VEH, lastParamChange, persisted VEH) that each fail at the mutated
event (`output/mutation-*.log`) and by the old-code control traces failing on
exactly the changed rows (`output/control-old-vs-v1-summary.log`). Fields
`ts`, `nid`, `msg.height`, `msg.error`, handshake `msg.*Height` are
informational and not consumed.

---

# V0 coverage (retained)


## Coverage summary

The base, model-checking, trace, instrumentation, and harness artifacts cover
all three scenarios in `modeling-brief.md`. The abstraction deliberately models
one node's scoped durability/recovery lifecycle, not consensus networking or a
Byzantine peer model.

## State-variable mapping

| Brief concept | Base model | Trace evidence |
|---|---|---|
| durable block height | `blockStoreHeight` | every event's `blockStoreHeight` |
| application committed height | `appHeight` | `Info`, commit, and app-only replay shadow |
| durable core state height | `stateStoreHeight` | state store load |
| in-flight in-memory state | `stateHeight` | current `sm.State` |
| active/durable complete parameters | `activeParam`, `persistedParam` | complete-value fingerprints |
| change-height bookkeeping | `lastParamChange`, `persistedLastParamChange` | exact state fields |
| durable Finalize response | `responseHeight`, `responseParam` | post-save shadow/recovery load |
| atomicity/recovery control | `phase`, `replayMutatesState` | explicit phase and replay hooks |
| in-flight update | `pendingBlockHeight`, `pendingParam`, `updatePresent`, `validationOutcome` | block/update event data |
| non-vacuity | `coverage` in `MC.tla` | reachability witness configurations |

## Transition mapping

| Brief operation or environment step | TLA+ action | Trace status |
|---|---|---|
| caller saves block | `SaveBlock` | `BlockStored` |
| begin execution | `ApplyBlockStart` | same-named event |
| receive application result | `FinalizeBlock(p)` | `FinalizeBlock` |
| save result | `SaveFinalizeBlockResponse` | same-named event |
| validate/install valid update | `UpdateStateAccepted` | same-named event |
| reject invalid update | `UpdateStateRejected`, `AbortRejectedApply` | rejection event followed by end of trace |
| commit application | `CommitApp` | same-named event |
| save core state | `SaveState` | same-named event |
| crash/restart | `Crash`, `BeginHandshake` | only handshake entry is observable; crash is an MC environment step |
| app-only catch-up | `AppReportsOlderHeight`, `ReplayAppBlock` | report is handshake input; each replay is observed |
| final real replay | `SelectRealReplay` plus apply pipeline | mode-tagged selection and full pipeline |
| final mock replay | `SelectMockReplay` plus apply pipeline | mode-tagged selection and full pipeline |
| synchronized recovery | `CompleteHandshake` | `HandshakeComplete` |
| scheduler/environment idle | `EnvironmentStutter` | model-only |

## Property mapping

| Brief property/question | Checked invariant or evidence | Result artifact |
|---|---|---|
| height/type domains remain coherent | `MCTypeOK`, `TypeOK` | `output/mc-main.log`; every trace log |
| persisted heights reflect operation ordering | `PersistedHeightRelationships` | main and scenario 2/3 logs |
| accepted apply advances exactly one height | `SuccessfulApplyAdvancesExactlyOne` | main/scenario 2 plus valid and recovery traces |
| invalid parameters are not installed | `RejectedUpdateDoesNotInstall` | main/scenario 1 plus rejected trace |
| accepted parameter update and change height agree | `ParameterUpdateReflected` | main/scenario 1 plus valid trace |
| normal phase is fully synchronized | `NormalPhaseIsSynchronized` | main/scenario 2/3 plus completion traces |
| only exact-old supported recovery tuples return normal | `RecoveryNormalOnlySupported` | main/scenario 3 plus four recovery traces |
| important branches are reachable | seven intentionally negated reachability invariants | `output/reach-*.log` |

## Scenario coverage

1. **Parameter validation and installation.** Both a valid application result
   and an invalid `MaxBytes = 0` result are generated by the real `BlockExecutor`
   harness. TLC explores valid/no-update/invalid parameter choices.
2. **Durability pipeline and crash boundaries.** TLC can crash at every modeled
   phase and explores up to two blocks/two crashes. The implementation traces
   cover the complete successful pipeline and its pre-commit rejection prefix.
3. **Recovery height matrix.** Fresh traces cover already synchronized,
   app-only replay, final real replay, and final mock replay. TLC also explores
   bounded app rollback and repeats crash/recovery interleavings.

## Intentional exclusions and coverage limits

- Peer messages, proposer selection, voting, evidence, mempool behavior,
  validator updates, application hash contents, block bytes, pruning mechanics,
  InitChain details, and multi-node Byzantine behavior are outside the binding
  subsystem boundary or abstracted away.
- Store/application I/O errors and panics for core-corruption height relations
  are not nondeterministically injected. They are documented assumptions, not
  silently treated as successful recovery.
- TLC bounds are `MaxHeight = 2`, two saved blocks, two crashes, one app-height
  rollback, and a three-value parameter domain in the main configuration.
- Runtime evidence consists of six deterministic single-process scenarios, not
  all test seeds, storage backends, platforms, or parameter values.

Therefore successful runs establish bounded consistency only and are reported
as `LIMITED_COVERAGE`, never as proof.

