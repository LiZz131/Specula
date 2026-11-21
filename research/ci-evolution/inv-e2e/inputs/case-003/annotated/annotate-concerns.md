# Concerns about the model and contradictory evidence

These are observations only. The model itself was not changed: only comment lines were added. Each concern has a severity: **H** (could hide a real code bug or give false confidence), **M** (narrows what the model can find), or **L** (cosmetic or bookkeeping).

---

## C1 (H): FinalizeBlock re-execution is forced to be deterministic, and the cited code does not check it

- Model: `base.tla` `FinalizeBlock(p)` has the guard `(responseHeight = pendingBlockHeight => p = responseParam)` with the comment "A previously saved response for H must replay deterministically. internal/consensus/replay.go:417-432."
- Code: `replay.go:417-433` is the **mock-app** path. It loads the saved response and never calls the real app's FinalizeBlock. The path where the real app re-executes a block whose response was already saved is `replay.go:408-415` (`appBlockHeight == stateBlockHeight`, store = state + 1). That path calls `replayBlock` → `ApplyBlock`, which calls the app's `FinalizeBlock` and then **overwrites** the saved response (`execution.go:254`). It does not compare the new response with the saved one. `LoadLastFinalizeBlockResponse` is called only at `replay.go:419`.
- Spec: `spec/abci/abci++_app_requirements.md:939-941` says that in this case CometBFT re-executes `FinalizeBlock` "to retrieve the results and compare them to the state stored by CometBFT … otherwise CometBFT panics". No such comparison exists at this revision. The app's determinism is required (`abci++_methods.md:660` "The implementation of `FinalizeBlock` MUST be deterministic"), but CometBFT does not check it on this path.
- Effect: the model only explores runs where the app returns the same parameter update on re-execution. A non-deterministic app could return a different (valid or invalid) update during real-app replay. The code would install the new update without noticing, while the spec text promises a panic. No property can see this, because the guard removes those runs. The spec-vs-code mismatch is itself evidence that contradicts the spec text, though not any checked property.

## C2 (M): `ValidParams` is a fixed set, but validity in the code depends on height and on the current parameters

- Code: `updateState` validates the **merged** record (`nextParams.ValidateBasic()`, `execution.go:616-620`) and also the **delta against the current params at height H** (`state.ConsensusParams.ValidateUpdate(updates, header.Height)`, `execution.go:622-625`; `types/params.go:208-230`). Whether an update to `VoteExtensionsEnableHeight` is accepted depends on the current value and on `h` (`params_test.go:157-213`).
- Model: `ValidParams` is a constant. A parameter identity is valid or invalid forever, from any current parameter and at any height.
- Effect: the model cannot express "the same update is accepted at height 1 and rejected at height 2", or "valid from p0, invalid from p1". `RejectedUpdateDoesNotInstall` and `ParameterUpdateReflected` are only checked for this static split.

## C3 (M): Trace validation makes the validity clause hold by construction and may produce false mismatches

- `Trace.tla`: `TraceValidParams` = every parameter seen in any `state` record, plus every `proposedParam` of an `UpdateStateAccepted` event.
- So under `Trace.cfg`, the conjunct `pendingParam \in ValidParams` of `ParameterUpdateReflected` holds by construction. The trace check cannot detect the implementation accepting an invalid update.
- Conversely, if a parameter is accepted at one event and rejected at another (possible in the code, see C2), `UpdateStateRejected` requires `pendingParam \in Params \ ValidParams` and cannot match the rejected event. The trace would fail to match without any code bug.
- `TraceInit` (BlockStored branch) also builds the initial state with `activeParam = s.persistedParam` and `stateHeight = s.stateStoreHeight`. It assumes `NormalPhaseIsSynchronized` at the start of the trace instead of checking it.
- The default trace path `../traces/apply_valid.ndjson` does not exist under `/work`, so trace validation cannot be rerun here.

## C4 (M): `RecoveryNormalOnlySupported` is mostly implied by other properties and by the action structure

- `coverage` only grows. Once one handshake has completed, `"handshakeComplete" \in coverage` stays true for every later recovery (`MC.cfg` and `MC_hunt_scenario3_recovery.cfg` allow `MaxCrashes = 2`). The first conjunct therefore says nothing about the second and later recoveries.
- Its height conjuncts (`appHeight = blockStoreHeight`, `stateStoreHeight = blockStoreHeight`) are already implied by `NormalPhaseIsSynchronized`, and both are checked in the same configurations.
- From the actions: once a handshake has started, `phase = "normal"` can only be reached through `CompleteHandshake`. `SaveState` goes to `"handshake"` when `replayMutatesState` is TRUE; `ReplayAppBlock` stays in `"handshake"`.
- Net effect: the property cannot fail unless the action definitions change. It cannot catch a later recovery that skips the handshake. A per-recovery marker (reset on `Crash`) would make it meaningful.

## C5 (M): The app-height clause of `PersistedHeightRelationships` is an assumption about the app, and the model never tests it

- `replay.go:373` says "the app should never be ahead of the store (but this is under app's control)". CometBFT only detects a violation, returning `ErrAppBlockHeightTooHigh` (`replay.go:372-374`).
- In the model the app can only move down (`AppReportsOlderHeight`) or be committed up to the pending block (`CommitApp`, `ReplayAppBlock`). No action lets the app report a height above the block store. So `appHeight <= blockStoreHeight` holds by construction, and the error path in `replay.go:372-374` is never exercised.
- Similarly, `BeginHandshake` simply blocks when the code would panic or return an error (`replay.go:372-382`). The panic and error paths are not modelled.

## C6 (L/M): The current crash-recovery spec is ambiguous about which height "state_stored" means

- `abci++_app_requirements.md:912-915` defines the second step (`state_stored`) as "CometBFT has stored the state returned by the application through `FinalizeBlockResponse`", i.e. the saved **response**. The diagram puts it before `Commit`.
- The panic list at `:944-950` then uses `state_stored` the way the code uses `State.LastBlockHeight` (`replay.go:376-382`). Its first item says CometBFT "will panic" if the app persisted a block above `state_stored`. In the code, an app ahead of the **block store** returns an error, not a panic (`replay.go:372-374`). If `state_stored` meant the saved State height, the legitimate mock-replay case (app = store = state + 1, `replay.go:417`) would count as such a panic case.
- Because of this, the evidence for `PersistedHeightRelationships` relies mainly on the code comments and on the pre-19700acc2 spec text (`f74f056a5:spec/abci/abci++_app_requirements.md:831,844-846`), which name the three stores unambiguously.

## C7 (L): The comment on `State.ConsensusParams` says params are "updated after Commit"

- `internal/state/state.go:70-71` says "Changes returned by FinalizeBlock and updated after Commit." The proto files say the same with "EndBlock" (`proto/cometbft/state/v1/types.proto:98-99`).
- In the code, the in-memory new State gets the new params in `updateState`, **before** `Commit` (`execution.go:279` vs `:285`). `ParameterUpdateReflected` asserts `activeParam = pendingParam` already in phase `"updated"`, before `CommitApp`. The comment agrees with the code (and the property) only if "updated" means "persisted" (`Save` at `execution.go:297` runs after `Commit`). The wording is stale or ambiguous. It does not contradict the H+1 effect, which is stated elsewhere.

## C8 (L/M): Only parameter rejection is modelled; other `ApplyBlock` failures are not

- `ApplyBlock` also returns the input state on block-validation failure (`execution.go:214-216`), a tx-result count mismatch (`:245-247`), and validator-update validation or conversion failures (`:261-269`). The validator-update failures happen **after** the response has been saved, just like parameter rejection.
- The model only has `UpdateStateRejected` for invalid consensus params. `RejectedUpdateDoesNotInstall` therefore covers only that path. The other paths share the same "response durably saved, then fatal error" shape and are not covered.

## C9 (L): A rejected update makes recovery impossible, and no property or canary records it

- The response that contains the invalid update is saved durably before validation (`execution.go:254` before `:279`). On restart, block store = state + 1 and app = state, so the code re-executes the block with the real app (`replay.go:408-415`). A deterministic app returns the same invalid update, and the handshake fails again (`setup.go:200-201`).
- In the model: `AbortRejectedApply` → `"down"` → `BeginHandshake` → `SelectRealReplay` → … → `UpdateStateRejected` again. Because of C1, `p` must equal the saved invalid parameter. `"normal"` is never reached again.
- This matches the code, which treats the error as fatal. No liveness or reachability property states it, so a future change that let the node resume after a rejected update would go unnoticed.

## C10 (L): Abstractions worth recording

- **Merge vs replace.** The model treats an update as a complete parameter record that replaces the active one (`activeParam' = pendingParam`). The code merges non-nil sub-structures (`types/params.go:258-287`), and the spec describes a field-by-field update (`abci++_app_requirements.md:785-789`). `pendingParam` must therefore be read as "the merged result", and `pendingParam \in ValidParams` as "ValidateBasic(merged) ∧ ValidateUpdate(delta, H)".
- **App height 0.** `AppReportsOlderHeight` may set `appHeight` to 0. In the code, `appBlockHeight == 0` makes the handshake call `InitChain` again (`replay.go:303-356`), and with a pruned block store it returns `ErrAppBlockHeightTooLow` (`replay.go:364-366`). Neither is modelled (no block-store base).
- **Mock commit.** In mock replay the model's `CommitApp` runs with `appHeight = pendingBlockHeight`. In the code this is the mock app's no-op `Commit` (`replay_stubs.go:58-61`: "we don't want to call Commit() twice for the same block on the real app"). This is harmless, but `appCommitted` coverage does not mean the real app committed.
- **Structural invariants.** `SuccessfulApplyAdvancesExactlyOne` and `ParameterUpdateReflected` follow almost directly from the guards and updates in `ApplyBlockStart` / `UpdateStateAccepted`. Under `MC*.cfg` they mainly protect against future edits to the actions; they have real power only in trace validation, and C3 weakens that.
- **Initial change height.** `Init` sets `lastParamChange = 1`. The code uses `genDoc.InitialHeight` (`state.go:349`), so the model assumes `InitialHeight = 1`.
