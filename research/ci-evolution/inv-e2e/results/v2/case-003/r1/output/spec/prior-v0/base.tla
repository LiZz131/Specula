------------------------------- MODULE base -------------------------------
(***************************************************************************
Exact-old CometBFT state execution and recovery model.

Consensus parameter records are represented by symbolic identities. Params
denotes complete records and ValidParams is the result of the old-tree
ValidateBasic + ValidateUpdate checks for the current bounded model.
***************************************************************************)
EXTENDS Integers, FiniteSets, TLC

CONSTANTS MaxHeight, Params, ValidParams, InitialParam, NoParam

ASSUME /\ MaxHeight \in Nat \ {0}
       /\ Params /= {}
       /\ ValidParams \subseteq Params
       /\ InitialParam \in ValidParams
       /\ NoParam \notin Params

VARIABLES
    blockStoreHeight,             \* internal/store/store.go:84-88
    appHeight,                    \* internal/consensus/replay.go:248-252
    stateStoreHeight,             \* internal/state/state.go:54-79
    stateHeight,                  \* in-memory State.LastBlockHeight
    activeParam,                  \* in-memory State.ConsensusParams
    persistedParam,               \* state-store parameter identity
    lastParamChange,              \* State.LastHeightConsensusParamsChanged
    persistedLastParamChange,
    responseHeight,               \* durable latest FinalizeBlockResponse
    responseParam,
    phase,
    replayMutatesState,
    pendingBlockHeight,
    pendingParam,
    updatePresent,
    validationOutcome,
    coverage                      \* observer-only non-vacuity markers

vars == <<blockStoreHeight, appHeight, stateStoreHeight, stateHeight,
          activeParam, persistedParam, lastParamChange,
          persistedLastParamChange, responseHeight, responseParam, phase,
          replayMutatesState, pendingBlockHeight, pendingParam,
          updatePresent, validationOutcome, coverage>>

Phases == {"normal", "blockStored", "applying", "finalized",
           "responseSaved", "updated", "committed", "rejected",
           "down", "handshake"}
ValidationOutcomes == {"none", "accepted", "rejected"}
ParamOrNone == Params \cup {NoParam}

Init ==
    \* Genesis state: internal/state/state.go:334-352.
    /\ blockStoreHeight = 0
    /\ appHeight = 0
    /\ stateStoreHeight = 0
    /\ stateHeight = 0
    /\ activeParam = InitialParam
    /\ persistedParam = InitialParam
    /\ lastParamChange = 1
    /\ persistedLastParamChange = 1
    /\ responseHeight = 0
    /\ responseParam = NoParam
    /\ phase = "normal"
    /\ replayMutatesState = FALSE
    /\ pendingBlockHeight = 0
    /\ pendingParam = NoParam
    /\ updatePresent = FALSE
    /\ validationOutcome = "none"
    /\ coverage = {}

SaveBlock ==
    \* Consensus persists H before ApplyBlock: internal/consensus/state.go:1781-1817.
    /\ phase = "normal"
    /\ blockStoreHeight = stateStoreHeight
    /\ blockStoreHeight < MaxHeight
    /\ blockStoreHeight' = blockStoreHeight + 1
    /\ pendingBlockHeight' = blockStoreHeight + 1
    /\ phase' = "blockStored"
    /\ coverage' = coverage \cup {"blockStored"}
    /\ UNCHANGED <<appHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    replayMutatesState, pendingParam, updatePresent,
                    validationOutcome>>

ApplyBlockStart ==
    \* ApplyBlock entry and non-mutating validation: execution.go:205-216.
    /\ phase = "blockStored"
    /\ pendingBlockHeight = blockStoreHeight
    /\ stateHeight = stateStoreHeight
    /\ phase' = "applying"
    /\ coverage' = coverage \cup {"applyStarted"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    replayMutatesState, pendingBlockHeight, pendingParam,
                    updatePresent, validationOutcome>>

FinalizeBlock(p) ==
    \* Synchronous app transition: internal/state/execution.go:219-234.
    /\ phase = "applying"
    /\ p \in ParamOrNone
    \* A previously saved response for H must replay deterministically.
    \* internal/consensus/replay.go:417-432.
    /\ (responseHeight = pendingBlockHeight => p = responseParam)
    /\ pendingParam' = p
    /\ updatePresent' = (p /= NoParam)
    /\ phase' = "finalized"
    /\ coverage' = coverage \cup {"finalized"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    replayMutatesState, pendingBlockHeight,
                    validationOutcome>>

SaveFinalizeBlockResponse ==
    \* Sync-save response before validation: execution.go:253-256 and
    \* internal/state/store.go:562-601.
    /\ phase = "finalized"
    /\ responseHeight' = pendingBlockHeight
    /\ responseParam' = pendingParam
    /\ phase' = "responseSaved"
    /\ coverage' = coverage \cup {"responseSaved"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, replayMutatesState,
                    pendingBlockHeight, pendingParam, updatePresent,
                    validationOutcome>>

UpdateStateAccepted ==
    \* Update copy, validate, then construct H state: execution.go:611-652.
    /\ phase = "responseSaved"
    /\ (pendingParam = NoParam \/ pendingParam \in ValidParams)
    /\ stateHeight' = pendingBlockHeight
    /\ activeParam' = IF updatePresent THEN pendingParam ELSE activeParam
    /\ lastParamChange' = IF updatePresent
                           THEN pendingBlockHeight + 1
                           ELSE lastParamChange
    /\ validationOutcome' = "accepted"
    /\ phase' = "updated"
    /\ coverage' = coverage \cup {"acceptedUpdate"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight,
                    persistedParam, persistedLastParamChange, responseHeight,
                    responseParam, replayMutatesState, pendingBlockHeight,
                    pendingParam, updatePresent>>

UpdateStateRejected ==
    \* Both validation failures return the input State: execution.go:617-625.
    /\ phase = "responseSaved"
    /\ updatePresent
    /\ pendingParam \in Params \ ValidParams
    /\ validationOutcome' = "rejected"
    /\ phase' = "rejected"
    /\ coverage' = coverage \cup {"rejectedUpdate"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    replayMutatesState, pendingBlockHeight, pendingParam,
                    updatePresent>>

CommitApp ==
    \* App persists H before state save: execution.go:370-418.
    /\ phase = "updated"
    /\ appHeight <= pendingBlockHeight
    /\ appHeight' = pendingBlockHeight
    /\ phase' = "committed"
    /\ coverage' = coverage \cup {"appCommitted"}
    /\ UNCHANGED <<blockStoreHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    replayMutatesState, pendingBlockHeight, pendingParam,
                    updatePresent, validationOutcome>>

SaveState ==
    \* Sync state/parameter batch: execution.go:295-299; store.go:204-243.
    /\ phase = "committed"
    /\ stateStoreHeight' = stateHeight
    /\ persistedParam' = activeParam
    /\ persistedLastParamChange' = lastParamChange
    /\ phase' = IF replayMutatesState THEN "handshake" ELSE "normal"
    /\ pendingBlockHeight' = 0
    /\ pendingParam' = NoParam
    /\ updatePresent' = FALSE
    /\ validationOutcome' = "none"
    /\ coverage' = coverage \cup {"stateSaved"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateHeight, activeParam,
                    lastParamChange, responseHeight, responseParam,
                    replayMutatesState>>

AbortRejectedApply ==
    \* Production consensus treats ApplyBlock error as fatal: consensus/state.go:1834-1836.
    /\ phase = "rejected"
    /\ stateHeight' = stateStoreHeight
    /\ activeParam' = persistedParam
    /\ lastParamChange' = persistedLastParamChange
    /\ phase' = "down"
    /\ replayMutatesState' = FALSE
    /\ pendingBlockHeight' = 0
    /\ pendingParam' = NoParam
    /\ updatePresent' = FALSE
    /\ validationOutcome' = "none"
    /\ coverage' = coverage \cup {"rejectedAbort"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight,
                    persistedParam, persistedLastParamChange, responseHeight,
                    responseParam>>

Crash ==
    \* Crash keeps durable stores/app and loses staged State.
    \* Recovery contract: spec/abci/abci++_app_requirements.md:899-950.
    /\ phase /= "down"
    /\ stateHeight' = stateStoreHeight
    /\ activeParam' = persistedParam
    /\ lastParamChange' = persistedLastParamChange
    /\ phase' = "down"
    /\ replayMutatesState' = FALSE
    /\ pendingBlockHeight' = 0
    /\ pendingParam' = NoParam
    /\ updatePresent' = FALSE
    /\ validationOutcome' = "none"
    /\ coverage' = coverage \cup {"crashed"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight,
                    persistedParam, persistedLastParamChange, responseHeight,
                    responseParam>>

AppReportsOlderHeight(h) ==
    \* Replay explicitly accepts an app behind the store: replay.go:388-406.
    /\ phase = "down"
    /\ h \in 0..appHeight
    /\ h < appHeight
    /\ appHeight' = h
    /\ coverage' = coverage \cup {"appReportedOlder"}
    /\ UNCHANGED <<blockStoreHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    phase, replayMutatesState, pendingBlockHeight,
                    pendingParam, updatePresent, validationOutcome>>

BeginHandshake ==
    \* Info height and old-tree admissibility guards: replay.go:240-267,358-383.
    /\ phase = "down"
    /\ appHeight <= blockStoreHeight
    /\ stateStoreHeight <= blockStoreHeight
    /\ blockStoreHeight <= stateStoreHeight + 1
    /\ phase' = "handshake"
    /\ coverage' = coverage \cup {"handshakeStarted"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    replayMutatesState, pendingBlockHeight, pendingParam,
                    updatePresent, validationOutcome>>

ReplayAppBlock ==
    \* Historical blocks use ExecCommitBlock without State mutation:
    \* internal/consensus/replay.go:441-489.
    /\ phase = "handshake"
    /\ appHeight < stateStoreHeight
    /\ appHeight' = appHeight + 1
    /\ replayMutatesState' = FALSE
    /\ coverage' = coverage \cup {"appOnlyReplay"}
    /\ UNCHANGED <<blockStoreHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    phase, pendingBlockHeight, pendingParam, updatePresent,
                    validationOutcome>>

SelectRealReplay ==
    \* App and state at S; use real app for stored block S+1:
    \* internal/consensus/replay.go:399-415,491-498.
    /\ phase = "handshake"
    /\ blockStoreHeight = stateStoreHeight + 1
    /\ appHeight = stateStoreHeight
    /\ pendingBlockHeight' = blockStoreHeight
    /\ phase' = "blockStored"
    /\ replayMutatesState' = TRUE
    /\ coverage' = coverage \cup {"realReplaySelected"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    pendingParam, updatePresent, validationOutcome>>

SelectMockReplay ==
    \* App already at B; load saved response and mutate State with mock app:
    \* internal/consensus/replay.go:417-433.
    /\ phase = "handshake"
    /\ blockStoreHeight = stateStoreHeight + 1
    /\ appHeight = blockStoreHeight
    /\ responseHeight = blockStoreHeight
    /\ pendingBlockHeight' = blockStoreHeight
    /\ phase' = "blockStored"
    /\ replayMutatesState' = TRUE
    /\ coverage' = coverage \cup {"mockReplaySelected"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    pendingParam, updatePresent, validationOutcome>>

CompleteHandshake ==
    \* Normal startup follows equality/replay cases: replay.go:385-438.
    /\ phase = "handshake"
    /\ appHeight = blockStoreHeight
    /\ stateStoreHeight = blockStoreHeight
    /\ stateHeight = stateStoreHeight
    /\ phase' = "normal"
    /\ replayMutatesState' = FALSE
    /\ coverage' = coverage \cup {"handshakeComplete"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    pendingBlockHeight, pendingParam, updatePresent,
                    validationOutcome>>

EnvironmentStutter ==
    \* Bounded model endpoint; unrelated next-height consensus is out of scope.
    /\ phase = "normal"
    /\ blockStoreHeight = MaxHeight
    /\ UNCHANGED vars

Next ==
    \/ SaveBlock
    \/ ApplyBlockStart
    \/ \E p \in ParamOrNone : FinalizeBlock(p)
    \/ SaveFinalizeBlockResponse
    \/ UpdateStateAccepted
    \/ UpdateStateRejected
    \/ CommitApp
    \/ SaveState
    \/ AbortRejectedApply
    \/ Crash
    \/ \E h \in 0..MaxHeight : AppReportsOlderHeight(h)
    \/ BeginHandshake
    \/ ReplayAppBlock
    \/ SelectRealReplay
    \/ SelectMockReplay
    \/ CompleteHandshake
    \/ EnvironmentStutter

\* REQ-EVIDENCE TypeOK
\* intent:   Every model variable stays inside the value domain the model declares for it.
\* status:   model-internal
\* watch:    none
\* verified: base
\* note:     no source evidence searched or expected for a type invariant.
\* review:   ok
TypeOK ==
    /\ blockStoreHeight \in 0..MaxHeight
    /\ appHeight \in 0..MaxHeight
    /\ stateStoreHeight \in 0..MaxHeight
    /\ stateHeight \in 0..MaxHeight
    /\ activeParam \in Params
    /\ persistedParam \in Params
    /\ lastParamChange \in Nat
    /\ persistedLastParamChange \in Nat
    /\ responseHeight \in 0..MaxHeight
    /\ responseParam \in ParamOrNone
    /\ phase \in Phases
    /\ replayMutatesState \in BOOLEAN
    /\ pendingBlockHeight \in 0..MaxHeight
    /\ pendingParam \in ParamOrNone
    /\ updatePresent \in BOOLEAN
    /\ validationOutcome \in ValidationOutcomes
    /\ coverage \subseteq {"blockStored", "applyStarted", "finalized",
                            "responseSaved", "acceptedUpdate",
                            "rejectedUpdate", "appCommitted", "stateSaved",
                            "rejectedAbort", "crashed", "appReportedOlder",
                            "handshakeStarted", "appOnlyReplay",
                            "realReplaySelected", "mockReplaySelected",
                            "handshakeComplete"}

\* REQ-EVIDENCE PersistedHeightRelationships
\* intent:   The saved state is never ahead of the block store, the block store is at most one block ahead of the saved state, and the app's committed height is never ahead of the block store.
\* status:   requirement
\* evidence: comment source/internal/consensus/replay.go:377 "the state should never be ahead of the store (this is under CometBFT's control)" -> saved state height <= block store height
\* evidence: comment source/internal/consensus/replay.go:381 "store should be at most one ahead of the state (this is under CometBFT's control)" -> block store height <= saved state height + 1
\* evidence: comment source/internal/consensus/replay.go:373 "the app should never be ahead of the store (but this is under app's control)" -> app committed height <= block store height
\* evidence: history f74f056a5:spec/abci/abci++_app_requirements.md:831 "Note we always have `storeBlockHeight >= stateBlockHeight` and `storeBlockHeight >= appBlockHeight`" -> saved state height <= block store height and app height <= block store height
\* evidence: history f74f056a5:spec/abci/abci++_app_requirements.md:846 "If `storeBlockHeight > stateBlockHeight+1`, panic" -> block store height <= saved state height + 1
\* evidence: comment source/internal/state/rollback.go:38 "If the state store isn't one below nor equal to the blockstore height" -> block store height is the saved state height or one above it
\* evidence: protocol spec/abci/abci++_app_requirements.md §Crash Recovery "exist a scenario where the application has persisted state of a height greater than the" -> app committed height never exceeds what CometBFT has persisted
\* evidence: impl source/internal/consensus/replay.go:372 "case storeBlockHeight < appBlockHeight:"
\* evidence: impl source/internal/consensus/replay.go:376 "case storeBlockHeight < stateBlockHeight:"
\* evidence: impl source/internal/consensus/replay.go:380 "case storeBlockHeight > stateBlockHeight+1:"
\* evidence: impl source/internal/store/store.go:484 "BlockStore can only save contiguous blocks. Wanted %v, got %v"
\* watch:    source/internal/consensus/replay.go:Handshaker.ReplayBlocks; source/internal/consensus/state.go:State.finalizeCommit; source/internal/state/execution.go:BlockExecutor.ApplyBlock; source/internal/state/rollback.go:Rollback; source/internal/store/store.go:BlockStore.saveBlockToBatch; source/spec/abci/abci++_app_requirements.md:Crash Recovery
\* verified: base
\* note:     the explicit inequalities were spec text until 19700acc2 (spec:abci2.0 - clarify crash recovery mechanism) rewrote the section; the current spec names the persisted steps block_stored/state_stored without saying which store "state_stored" is; replay.go:373 says the app clause is under the app's control; searched replay_test.go for tests of the three height checks and found none.
\* review:   ok
PersistedHeightRelationships ==
    /\ stateStoreHeight <= blockStoreHeight
    /\ blockStoreHeight <= stateStoreHeight + 1
    /\ appHeight <= blockStoreHeight

\* REQ-EVIDENCE SuccessfulApplyAdvancesExactlyOne
\* intent:   Between an accepted state update for a block and the save of that state, the new state's height equals the height of that block.
\* status:   mixed
\* evidence: protocol spec/core/data_structures.md §Execution "state(h+1) <- Execute(state(h), ABCIApp, block(h))" -> executing a block yields a state exactly one height above the state it was executed on
\* evidence: protocol spec/core/data_structures.md §Header "Must be > 0, >= initialHeight, and == previous Height+1" -> the executed block's height is one above the previous height
\* evidence: test source/internal/state/validation_test.go:77 TestValidateBlockHeader "Height wrong" -> block validation rejects a block whose height is not the state's next height (case asserted: height + 10)
\* evidence: impl source/internal/state/execution.go:641 "LastBlockHeight:                  header.Height,"
\* evidence: impl source/internal/state/validation.go:39 "if state.LastBlockHeight > 0 && block.Height != state.LastBlockHeight+1 {"
\* evidence: impl source/internal/state/execution.go:214 "if err := validateBlock(state, block); err != nil {"
\* watch:    source/internal/state/execution.go:updateState; source/internal/state/execution.go:BlockExecutor.ApplyBlock; source/internal/state/validation.go:validateBlock; source/internal/consensus/state.go:State.finalizeCommit
\* verified: base
\* clause block-height: requirement — stateHeight = pendingBlockHeight: §Execution (the new state is one above the state the block ran on), §Header (block height == previous + 1) and TestValidateBlockHeader (a block at the wrong height fails validation).
\* clause saved-base: unknown — stateHeight = stateStoreHeight + 1: §Execution gives "one above the state the block was executed on", but only impl (consensus/state.go:1822) makes that state the last saved one; the history search found no stated rule.
\* note:     the protocol text relates the new state to the state the block was executed on; no non-impl quote says that input state is the saved one (only impl: consensus/state.go:1822 copies cs.state); searched execution_test.go and state_test.go for an assertion on LastBlockHeight after ApplyBlock and found none; hist.sh log -S'stateCopy := cs.state.Copy()' and -S'updateToState(stateCopy)' on consensus/state.go found 8e452aa0d ("fixed algorithm") and 3e3c0083c, neither of which states that the executed-on state must be the saved one.
\* review:   status requirement -> mixed and intent narrowed to the block-height conjunct, because no cited non-impl source links the state the block runs on to the saved state (the old note already said so) and the test arrow claimed more than the assertion.
SuccessfulApplyAdvancesExactlyOne ==
    phase \in {"updated", "committed"} =>
        /\ stateHeight = stateStoreHeight + 1
        /\ stateHeight = pendingBlockHeight

\* REQ-EVIDENCE RejectedUpdateDoesNotInstall
\* intent:   When a block's consensus-parameter update fails validation, the state is not advanced past that block and its consensus parameters are those of the state the block was applied to.
\* status:   mixed
\* evidence: comment source/internal/state/execution.go:615 "NOTE: must not mutate state.ConsensusParams" -> computing and validating the candidate update leaves the input state's consensus parameters untouched
\* evidence: contract source/types/params.go:257 "NOTE: note: must not modify the original." -> computing the candidate parameters does not modify the current ones
\* evidence: comment source/internal/consensus/state.go:1808 "Either way, the State should not be resumed until we" -> the state does not move past a block until ApplyBlock has succeeded
\* evidence: history 70a744558:state/state.go:276 "NOTE: must not mutate s.ConsensusParams" -> the current consensus parameters stay untouched while the update is computed (rule present since params.Update was introduced)
\* evidence: history 0bc539924 (message) "This PR also adds validation of the consensus param updates." -> consensus-parameter updates are validated
\* evidence: impl source/internal/state/execution.go:619 "validating new consensus params: %w"
\* evidence: impl source/internal/state/execution.go:624 "updating consensus params: %w"
\* evidence: impl source/internal/consensus/state.go:1835 "failed to apply block; error %v"
\* watch:    source/internal/state/execution.go:updateState; source/internal/state/execution.go:BlockExecutor.ApplyBlock; source/types/params.go:ConsensusParams.Update; source/types/params.go:ConsensusParams.ValidateBasic; source/types/params.go:ConsensusParams.ValidateUpdate; source/internal/consensus/state.go:State.finalizeCommit
\* verified: base
\* clause not-installed: requirement — stateHeight and activeParam stay those of the state the block was applied to: consensus/state.go:1808 (State not resumed until ApplyBlock succeeds); execution.go:615, params.go:257, 70a744558 (computing the candidate must not mutate the current parameters).
\* clause change-height: unknown — lastParamChange = persistedLastParamChange: only impl (execution.go:624 returns before lastHeightParamsChanged is assigned); the "must not mutate" comments name ConsensusParams only; the history search found no stated rule.
\* clause saved-copy: unknown — the three conjuncts compare against the saved state; the cited comments speak of the State passed into updateState, and only impl relates that State to the saved copy.
\* note:     the comments speak of the State passed into updateState, not of the saved copy; in 70a744558 a failed validation fell back to the old params ("TODO: err or carry on?"), and 35521b553 (save historical consensus params) changed this to returning an error (code change only, no stated reason; f82b7e2a1 only moved that code); searched execution_test.go and state_test.go for a test feeding an invalid ConsensusParamUpdates into ApplyBlock/updateState and found none; hist.sh log -S'lastHeightParamsChanged' found c915719f8 and f82b7e2a1, which introduce and move the variable without a stated rule.
\* review:   status requirement -> mixed and intent narrowed: the "must not mutate state.ConsensusParams" rules cover only the parameters of the input State, not the parameter-change height or the saved copy the formula compares against; also corrected the note's commit for the error-return change (35521b553, not f82b7e2a1).
RejectedUpdateDoesNotInstall ==
    phase = "rejected" =>
        /\ stateHeight = stateStoreHeight
        /\ activeParam = persistedParam
        /\ lastParamChange = persistedLastParamChange

\* REQ-EVIDENCE ParameterUpdateReflected
\* intent:   Once a block's consensus-parameter update has been accepted and until the resulting state is saved, the parameter set that results from applying the update is valid, it is the state's consensus parameters, and the recorded change height is the block height plus one.
\* status:   requirement
\* evidence: protocol spec/abci/abci++_methods.md §FinalizeBlock "returned for block `H` apply to the consensus params for block `H+1`" -> the update is applied to the consensus parameters, effective from H+1
\* evidence: protocol spec/abci/abci++_app_requirements.md §`FinalizeBlock`, `PrepareProposal`/`ProcessProposal` "If `ConsensusParams` is not `nil`, CometBFT will use it." -> a present update is installed as the consensus parameters
\* evidence: protocol spec/abci/abci++_app_requirements.md §Updating Consensus Parameters "The updates returned in block `H` will take effect right away for block `H+1`." -> recorded change height is H+1
\* evidence: protocol spec/core/data_structures.md §Execution "nextConsensusParams := UpdateConsensusParams(state.ConsensusParams, ConsensusParamChanges)" -> the new state's parameters are the updated parameters
\* evidence: comment source/internal/state/execution.go:629 "Change results from this height but only applies to the next height." -> recorded change height is H+1
\* evidence: test source/internal/state/state_test.go:1071 TestConsensusParamsChangesSaveLoad "assert.EqualValues(t, testCase.params, p," -> parameters returned at a change height are the ones in effect from the next height
\* evidence: test source/internal/state/execution_test.go:78 TestApplyBlock "App version wasn't updated" -> the App version carried by an update returned from FinalizeBlock is reflected in the state ApplyBlock returns
\* evidence: protocol spec/abci/abci++_app_requirements.md §BlockParams.MaxBytes "Must have `MaxBytes == -1` OR `0 < MaxBytes <= 100 MB`." -> consensus parameters must satisfy value constraints
\* evidence: history 0bc539924 (message) "This PR also adds validation of the consensus param updates." -> consensus-parameter updates are validated
\* evidence: protocol spec/abci/abci++_app_requirements.md §ABCIParams.VoteExtensionsEnableHeight "Once set to a value different from 0, its value must not be changed." -> some updates are invalid and must not take effect
\* evidence: test source/types/params_test.go:164 TestConsensusParamsUpdate_VoteExtensionsEnableHeight "require.Error(t, initialParams.ValidateUpdate(update, 1))" -> ValidateUpdate rejects an update that changes VoteExtensionsEnableHeight once that height has been reached
\* evidence: impl source/internal/state/execution.go:616 "nextParams = state.ConsensusParams.Update(abciResponse.ConsensusParamUpdates)"
\* evidence: impl source/internal/state/execution.go:630 "lastHeightParamsChanged = header.Height + 1"
\* watch:    source/internal/state/execution.go:updateState; source/types/params.go:ConsensusParams.Update; source/types/params.go:ConsensusParams.ValidateBasic; source/types/params.go:ConsensusParams.ValidateUpdate; source/internal/state/store.go:dbStore.save; source/spec/abci/abci++_methods.md:FinalizeBlock
\* verified: base
\* note:     the validity clause rests on per-parameter "Must have" constraints in the spec, the 0bc539924 commit message and unit tests of ValidateUpdate; no text states what CometBFT must do when an app returns a value violating them, and no test feeds an invalid update through updateState; the spec text describes an update as applied field by field ("Each field that is not empty will be applied in full").
\* review:   intent reworded from "the update is ... the state's consensus parameters" to the parameter set that results from applying it, as data_structures.md §Execution and the spec state; narrowed four arrows (methods.md §FinalizeBlock, TestApplyBlock, 0bc539924, params_test.go:164) to what each quote or assertion says; status unchanged.
ParameterUpdateReflected ==
    (phase \in {"updated", "committed"} /\ updatePresent) =>
        /\ pendingParam \in ValidParams
        /\ activeParam = pendingParam
        /\ lastParamChange = pendingBlockHeight + 1

\* REQ-EVIDENCE NormalPhaseIsSynchronized
\* intent:   Whenever the node is between heights in normal operation, the app, the block store and the saved state are at the same height, and the in-memory state (height, consensus parameters, parameter-change height) equals the saved state.
\* status:   requirement
\* evidence: protocol spec/abci/abci++_app_requirements.md §Crash Recovery "`block_stored`, `state_stored`, `app_persisted_state`: we move on to the next height." -> the next height starts only when block, state and app are all persisted for the current one
\* evidence: test source/internal/consensus/replay_test.go:745 testHandshakeReplay "require.Equal(t, store.Height(), res.LastBlockHeight)" -> after startup the app height equals the block store height
\* evidence: test source/internal/consensus/replay_test.go:750 testHandshakeReplay "require.Equal(t, state.LastBlockHeight, res.LastBlockHeight)" -> after startup the saved state height equals the app height
\* evidence: history f74f056a5:spec/abci/abci++_app_requirements.md:854 "If `storeBlockHeight == stateBlockHeight && appBlockHeight == storeBlockHeight`, we're done." -> all three heights equal is the synchronized condition
\* evidence: comment source/internal/consensus/state.go:1808 "Either way, the State should not be resumed until we" -> consensus does not resume until ApplyBlock for the block has succeeded
\* evidence: contract source/internal/state/execution.go:206 "commits the app, and saves the new state and responses." -> the state handed back after a block is the state that was saved
\* evidence: contract source/internal/state/store.go:77 "Save overwrites the previous state with the updated one" -> after a save the saved state equals the in-memory state
\* evidence: impl source/node/node.go:355 "Reload the state. It will have the Version.Consensus.App set by the"
\* evidence: impl source/internal/consensus/replay.go:395 "// We're good!"
\* evidence: impl source/internal/state/execution.go:297 "if err := blockExec.store.Save(state); err != nil {"
\* evidence: impl source/internal/consensus/state.go:1844 "cs.updateToState(stateCopy)"
\* watch:    source/internal/state/execution.go:BlockExecutor.ApplyBlock; source/internal/state/store.go:dbStore.Save; source/internal/consensus/state.go:State.finalizeCommit; source/internal/consensus/replay.go:Handshaker.ReplayBlocks; source/node/node.go:NewNode
\* verified: base
\* note:     the height part has spec and test evidence; the in-memory-equals-saved part rests on API doc comments (ApplyBlock, Store.Save), not on spec text; the node.go:355 reload comment narrates the stateStore.Load call that follows it and is counted as impl; testHandshakeReplay is run by TestHandshakeReplayAll/Some/One/None.
\* review:   retyped node.go:355 from comment to impl because it narrates the reload that follows it, and narrowed the state.go:1808 arrow, which claimed "and its state saved" although the quote names only ApplyBlock; intent and status unchanged.
NormalPhaseIsSynchronized ==
    phase = "normal" =>
        /\ appHeight = blockStoreHeight
        /\ stateStoreHeight = blockStoreHeight
        /\ stateHeight = stateStoreHeight
        /\ activeParam = persistedParam
        /\ lastParamChange = persistedLastParamChange

\* REQ-EVIDENCE RecoveryNormalOnlySupported
\* intent:   Once a restart has begun a handshake, the node is in normal operation only after a handshake has completed and with the app and the saved state caught up with the block store.
\* status:   requirement
\* evidence: protocol spec/abci/abci++_comet_expected_behavior.md §Valid method call sequences "first in replay mode, if there are blocks to replay, and then in normal mode." -> on recovery, normal mode follows replay
\* evidence: contract source/internal/consensus/replay.go:280 "ReplayBlocks replays all blocks since appBlockHeight and ensures the result" -> the handshake brings the app forward to the stored blocks and checks the result against the state
\* evidence: comment source/internal/consensus/state.go:1808 "Either way, the State should not be resumed until we" -> after a restart consensus resumes only once the handshake has applied the pending block
\* evidence: test source/internal/consensus/replay_test.go:745 testHandshakeReplay "require.Equal(t, store.Height(), res.LastBlockHeight)" -> after the handshake app height equals block store height
\* evidence: test source/internal/consensus/replay_test.go:750 testHandshakeReplay "require.Equal(t, state.LastBlockHeight, res.LastBlockHeight)" -> after the handshake the saved state has caught up with the app
\* evidence: protocol spec/abci/abci++_app_requirements.md §Crash Recovery "`block_stored`, `state_stored`, `app_persisted_state`: we move on to the next height." -> recovery moves on only when all three steps are persisted
\* evidence: impl source/internal/consensus/replay.go:272 "Completed ABCI Handshake - CometBFT and App are synced"
\* evidence: impl source/node/node.go:348 "and replays any blocks as necessary to sync CometBFT with the app."
\* evidence: impl source/node/setup.go:201 "error during handshake: %v"
\* watch:    source/internal/consensus/replay.go:Handshaker.Handshake; source/internal/consensus/replay.go:Handshaker.ReplayBlocks; source/internal/consensus/replay.go:Handshaker.replayBlocks; source/node/setup.go:doHandshake; source/node/node.go:NewNode; source/internal/consensus/state.go:State.finalizeCommit
\* verified: base
\* note:     testHandshakeReplay covers crash points via modes 0-3 (replay_test.go:806-828) and is run by TestHandshakeReplayAll/Some/One/None; the spec grammar line is "recovery = info [init-chain] consensus-exec"; no text found on repeated recoveries; the node.go:348 comment ("Create the handshaker, which calls RequestInfo, ...") narrates the doHandshake call that follows it and is counted as impl.
\* review:   retyped node.go:348 from comment to impl because it narrates the doHandshake call that follows it (its arrow also added "before consensus starts", which the quote does not say); intent reworded from "the handshake has completed" to "a handshake has completed" because the formula tests the cumulative handshakeStarted/handshakeComplete markers; status unchanged.
RecoveryNormalOnlySupported ==
    (phase = "normal" /\ "handshakeStarted" \in coverage) =>
        /\ "handshakeComplete" \in coverage
        /\ appHeight = blockStoreHeight
        /\ stateStoreHeight = blockStoreHeight

=============================================================================
