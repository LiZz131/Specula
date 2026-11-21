------------------------------- MODULE base -------------------------------
(***************************************************************************
CometBFT state execution and recovery model -- updated-revision reference.

V0 represented a complete consensus-parameter record by one symbolic
identity and parameter validity by a fixed set.  The updated source
(types/params.go:208-262, ConsensusParams.ValidateUpdate) decides acceptance
from the current ABCI.VoteExtensionsEnableHeight, the proposed one, and the
block height.  A fixed set cannot express that relation, so this revision
splits a parameter record into

    rest : symbolic identity of all non-ABCI fields (Block, Evidence,
           Validator, Version); ValidateBasic on these fields stays symbolic
    ve   : ABCI.VoteExtensionsEnableHeight (an integer)

and a FinalizeBlock parameter update into a record carrying its presence,
the resulting non-ABCI identity, and whether/which Abci subrecord was sent.
The change keeps the V0 durable boundaries, crash windows, and replay
height matrix unchanged.

UPDATE-MAP
code:   types/params.go:208-262 (ConsensusParams.ValidateUpdate)
update: Update!AffectedActions, Update!VE* properties
***************************************************************************)
EXTENDS Integers, FiniteSets, Sequences, TLC

CONSTANTS
    MaxHeight,      \* bound on block heights explored
    Rest,           \* symbolic identities of complete non-ABCI parameter parts
    ValidRest,      \* Rest values accepted by ValidateBasic's non-ABCI checks
    VEValues,       \* VoteExtensionsEnableHeight values an app may send (may be < 0)
    InitialParams,  \* genesis parameter records (already ValidateBasic-valid)
    NoRest          \* placeholder for the absent update

ASSUME /\ MaxHeight \in Nat \ {0}
       /\ Rest /= {}
       /\ ValidRest \subseteq Rest
       /\ VEValues \subseteq Int
       /\ NoRest \notin Rest
       /\ InitialParams /= {}

(***************************************************************************
Parameter records and updates.
***************************************************************************)
\* types/params.go:35-41,68-71: ConsensusParams with ABCIParams.VoteExtensionsEnableHeight.
ParamRecs == [rest : Rest, ve : Int]

\* abci FinalizeBlockResponse.ConsensusParamUpdates (a *cmtproto.ConsensusParams).
\*   present     : ConsensusParamUpdates != nil
\*   rest        : identity of the non-ABCI part after ConsensusParams.Update
\*   abciPresent : ConsensusParamUpdates.Abci != nil
\*   abci        : ConsensusParamUpdates.Abci.VoteExtensionsEnableHeight
NoUpdate == [present |-> FALSE, rest |-> NoRest, abciPresent |-> FALSE, abci |-> 0]
Updates ==
    {NoUpdate}
    \cup [present : {TRUE}, rest : Rest, abciPresent : {FALSE}, abci : {0}]
    \cup [present : {TRUE}, rest : Rest, abciPresent : {TRUE}, abci : VEValues]

\* types/params.go:287-318 ConsensusParams.Update: copy, then replace each
\* non-nil subrecord in full; params.go:314-316 replaces VoteExtensionsEnableHeight
\* only when params2.Abci != nil.
ApplyUpdate(p, u) ==
    IF ~u.present THEN p
    ELSE [rest |-> u.rest,
          ve   |-> IF u.abciPresent THEN u.abci ELSE p.ve]

\* types/params.go:143-205 ValidateBasic.  Non-ABCI checks are symbolic
\* (ValidRest); params.go:188-190 rejects a negative enable height.
ValidateBasic(p) ==
    /\ p.rest \in ValidRest
    /\ p.ve >= 0

\* types/params.go:73-83 ABCIParams.VoteExtensionsEnabled (h >= 1).
VEEnabled(ve, h) == ve /= 0 /\ ve <= h

\* types/params.go:208-262 ConsensusParams.ValidateUpdate(updated, h), following
\* the code's branch order.  Returns the decision-table row reached.
\* UPDATE-MAP
\* code: types/params.go:219-262
\* update: Update!AffectedActions (UpdateStateAccepted/Rejected guards)
ValidateUpdateRow(E, u, h) ==
    \* row 1: params.go:220-223 updated == nil || updated.Abci == nil
    IF ~u.present \/ ~u.abciPresent THEN 1
    \* row 2: params.go:224-227 updated enable height < 0
    ELSE IF u.abci < 0 THEN 2
    \* row 3: params.go:228-231 params <= 0 && updated == 0
    ELSE IF E <= 0 /\ u.abci = 0 THEN 3
    \* rows 4/5: params.go:232-242 params > 0 && updated == 0
    ELSE IF E > 0 /\ u.abci = 0 THEN (IF E <= h THEN 4 ELSE 5)
    \* row 6: params.go:243-248 updated <= h
    ELSE IF u.abci <= h THEN 6
    \* row 7: params.go:249-252 params <= 0
    ELSE IF E <= 0 THEN 7
    \* row 8: params.go:253-258 params <= h
    ELSE IF E <= h THEN 8
    \* row 9: params.go:259-261
    ELSE 9

AcceptRows == {1, 3, 5, 7, 9}
ValidateUpdateOK(E, u, h) == ValidateUpdateRow(E, u, h) \in AcceptRows

RowName(r) == "r" \o ToString(r)
RejectRules == {"none", "basic", "r2", "r4", "r6", "r8"}

VARIABLES
    blockStoreHeight,             \* internal/store/store.go BlockStore.Height
    appHeight,                    \* internal/consensus/replay.go:248-252 Info height
    stateStoreHeight,             \* internal/state/state.go:54-79 saved LastBlockHeight
    stateHeight,                  \* in-memory State.LastBlockHeight
    activeParam,                  \* in-memory State.ConsensusParams  [rest, ve]
    persistedParam,               \* state-store ConsensusParams       [rest, ve]
    lastParamChange,              \* State.LastHeightConsensusParamsChanged
    persistedLastParamChange,
    responseHeight,               \* durable latest FinalizeBlockResponse height
    responseParam,                \* its ConsensusParamUpdates (update record)
    phase,
    replayMutatesState,
    pendingBlockHeight,
    pendingParam,                 \* update record returned by FinalizeBlock
    updatePresent,
    validationOutcome,
    rejectRule,                   \* which validation step rejected (ValidateBasic or a ValidateUpdate row)
    veHist,                       \* veHist[m] = enable height of the params in effect at stored height m
    coverage                      \* observer-only non-vacuity markers

vars == <<blockStoreHeight, appHeight, stateStoreHeight, stateHeight,
          activeParam, persistedParam, lastParamChange,
          persistedLastParamChange, responseHeight, responseParam, phase,
          replayMutatesState, pendingBlockHeight, pendingParam,
          updatePresent, validationOutcome, rejectRule, veHist, coverage>>

Phases == {"normal", "blockStored", "applying", "finalized",
           "responseSaved", "updated", "committed", "rejected",
           "down", "handshake"}
ValidationOutcomes == {"none", "accepted", "rejected"}

CoverageMarkers ==
    {"blockStored", "applyStarted", "finalized", "responseSaved",
     "acceptedUpdate", "rejectedUpdate", "appCommitted", "stateSaved",
     "rejectedAbort", "crashed", "appReportedOlder", "handshakeStarted",
     "appOnlyReplay", "realReplaySelected", "mockReplaySelected",
     "handshakeComplete", "veEnabledBlockStored", "veUpdateMockReplay",
     "veUpdateRealReplay"}
    \cup {"veAccRow" \o ToString(r) : r \in AcceptRows}
    \cup {"veRej" \o x : x \in {"basic", "r2", "r4", "r6", "r8"}}
    \cup {"veRejIdentity"}

\* Default genesis choices for base.cfg (cfg files cannot hold records).
BaseInitialParams == [rest : {"r0"}, ve : {0, 2}]
BaseVEValues == {-1, 0, 1, 2, 3}

Init ==
    \* Genesis state: internal/state/state.go:334-352; genesis params pass
    \* ValidateBasic (types/genesis.go ValidateAndComplete).
    /\ blockStoreHeight = 0
    /\ appHeight = 0
    /\ stateStoreHeight = 0
    /\ stateHeight = 0
    /\ activeParam \in InitialParams
    /\ persistedParam = activeParam
    /\ lastParamChange = 1
    /\ persistedLastParamChange = 1
    /\ responseHeight = 0
    /\ responseParam = NoUpdate
    /\ phase = "normal"
    /\ replayMutatesState = FALSE
    /\ pendingBlockHeight = 0
    /\ pendingParam = NoUpdate
    /\ updatePresent = FALSE
    /\ validationOutcome = "none"
    /\ rejectRule = "none"
    /\ veHist = <<>>
    /\ coverage = {}

SaveBlock ==
    \* Consensus persists H before ApplyBlock: internal/consensus/state.go:1781-1792.
    \* The extended-commit decision at state.go:1786 uses the params in effect
    \* for H (cs.state.ConsensusParams); veHist records that enable height.
    \* UPDATE-MAP
    \* code: internal/consensus/state.go:1786 (consumer of the enable height)
    \* update: Update!VEHistoryStable
    /\ phase = "normal"
    /\ blockStoreHeight = stateStoreHeight
    /\ blockStoreHeight < MaxHeight
    /\ blockStoreHeight' = blockStoreHeight + 1
    /\ pendingBlockHeight' = blockStoreHeight + 1
    /\ veHist' = Append(veHist, activeParam.ve)
    /\ phase' = "blockStored"
    /\ coverage' = coverage \cup {"blockStored"}
                   \cup (IF VEEnabled(activeParam.ve, blockStoreHeight + 1)
                         THEN {"veEnabledBlockStored"} ELSE {})
    /\ UNCHANGED <<appHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    replayMutatesState, pendingParam, updatePresent,
                    validationOutcome, rejectRule>>

ApplyBlockStart ==
    \* ApplyBlock entry and non-mutating validation: execution.go:211-216.
    /\ phase = "blockStored"
    /\ pendingBlockHeight = blockStoreHeight
    /\ stateHeight = stateStoreHeight
    /\ phase' = "applying"
    /\ coverage' = coverage \cup {"applyStarted"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    replayMutatesState, pendingBlockHeight, pendingParam,
                    updatePresent, validationOutcome, rejectRule, veHist>>

FinalizeBlock(p) ==
    \* Synchronous app transition: internal/state/execution.go:218-234.
    /\ phase = "applying"
    /\ p \in Updates
    \* A previously saved response for H must replay deterministically
    \* (real app re-execution or saved-response mock app):
    \* internal/consensus/replay.go:403-433.
    /\ (responseHeight = pendingBlockHeight => p = responseParam)
    /\ pendingParam' = p
    /\ updatePresent' = p.present
    /\ phase' = "finalized"
    /\ coverage' = coverage \cup {"finalized"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    replayMutatesState, pendingBlockHeight,
                    validationOutcome, rejectRule, veHist>>

SaveFinalizeBlockResponse ==
    \* Sync-save response before validation: execution.go:252-256 and
    \* internal/state/store.go SaveFinalizeBlockResponse.
    /\ phase = "finalized"
    /\ responseHeight' = pendingBlockHeight
    /\ responseParam' = pendingParam
    /\ phase' = "responseSaved"
    /\ coverage' = coverage \cup {"responseSaved"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, replayMutatesState,
                    pendingBlockHeight, pendingParam, updatePresent,
                    validationOutcome, rejectRule, veHist>>

\* Candidate next params: execution.go:612-616 (copy, then Update on non-nil).
NextParams == ApplyUpdate(activeParam, pendingParam)

UpdateStateAccepted ==
    \* updateState: execution.go:586-652.  With a non-nil update, the candidate
    \* must pass ValidateBasic (execution.go:617-620) and then ValidateUpdate
    \* against the current params and header height (execution.go:622-625).
    \* UPDATE-MAP
    \* code: internal/state/execution.go:614-631; types/params.go:219-262
    \* update: Update!AffectedActions
    /\ phase = "responseSaved"
    /\ \/ ~updatePresent
       \/ /\ ValidateBasic(NextParams)
          /\ ValidateUpdateOK(activeParam.ve, pendingParam, pendingBlockHeight)
    /\ stateHeight' = pendingBlockHeight
    /\ activeParam' = NextParams
    \* execution.go:629-630: change recorded for H+1 on any non-nil update.
    /\ lastParamChange' = IF updatePresent
                           THEN pendingBlockHeight + 1
                           ELSE lastParamChange
    /\ validationOutcome' = "accepted"
    /\ rejectRule' = "none"
    /\ phase' = "updated"
    /\ coverage' = coverage \cup {"acceptedUpdate"}
                   \cup (IF updatePresent
                         THEN {"veAccRow" \o ToString(ValidateUpdateRow(
                                   activeParam.ve, pendingParam, pendingBlockHeight))}
                         ELSE {})
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight,
                    persistedParam, persistedLastParamChange, responseHeight,
                    responseParam, replayMutatesState, pendingBlockHeight,
                    pendingParam, updatePresent, veHist>>

UpdateStateRejected ==
    \* Either validation failure returns the input State: execution.go:617-625.
    \* ValidateBasic runs first; ValidateUpdate only when it passed.
    \* UPDATE-MAP
    \* code: internal/state/execution.go:617-625; types/params.go:219-262
    \* update: Update!AffectedActions
    /\ phase = "responseSaved"
    /\ updatePresent
    /\ \/ ~ValidateBasic(NextParams)
       \/ ~ValidateUpdateOK(activeParam.ve, pendingParam, pendingBlockHeight)
    /\ rejectRule' =
          IF ~ValidateBasic(NextParams) THEN "basic"
          ELSE RowName(ValidateUpdateRow(activeParam.ve, pendingParam,
                                         pendingBlockHeight))
    /\ validationOutcome' = "rejected"
    /\ phase' = "rejected"
    /\ coverage' = coverage \cup {"rejectedUpdate", "veRej" \o rejectRule'}
                   \cup (IF /\ ValidateBasic(NextParams)
                            /\ pendingParam.abciPresent
                            /\ pendingParam.abci = activeParam.ve
                         THEN {"veRejIdentity"} ELSE {})
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    replayMutatesState, pendingBlockHeight, pendingParam,
                    updatePresent, veHist>>

CommitApp ==
    \* App persists H before state save: execution.go:284-288,370-418.
    /\ phase = "updated"
    /\ appHeight <= pendingBlockHeight
    /\ appHeight' = pendingBlockHeight
    /\ phase' = "committed"
    /\ coverage' = coverage \cup {"appCommitted"}
    /\ UNCHANGED <<blockStoreHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    replayMutatesState, pendingBlockHeight, pendingParam,
                    updatePresent, validationOutcome, rejectRule, veHist>>

SaveState ==
    \* Sync state/parameter batch: execution.go:295-299; store.go:210-250,852-870.
    /\ phase = "committed"
    /\ stateStoreHeight' = stateHeight
    /\ persistedParam' = activeParam
    /\ persistedLastParamChange' = lastParamChange
    /\ phase' = IF replayMutatesState THEN "handshake" ELSE "normal"
    /\ pendingBlockHeight' = 0
    /\ pendingParam' = NoUpdate
    /\ updatePresent' = FALSE
    /\ validationOutcome' = "none"
    /\ rejectRule' = "none"
    /\ coverage' = coverage \cup {"stateSaved"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateHeight, activeParam,
                    lastParamChange, responseHeight, responseParam,
                    replayMutatesState, veHist>>

AbortRejectedApply ==
    \* Production consensus treats ApplyBlock error as fatal: consensus/state.go:1834-1836.
    /\ phase = "rejected"
    /\ stateHeight' = stateStoreHeight
    /\ activeParam' = persistedParam
    /\ lastParamChange' = persistedLastParamChange
    /\ phase' = "down"
    /\ replayMutatesState' = FALSE
    /\ pendingBlockHeight' = 0
    /\ pendingParam' = NoUpdate
    /\ updatePresent' = FALSE
    /\ validationOutcome' = "none"
    /\ rejectRule' = "none"
    /\ coverage' = coverage \cup {"rejectedAbort"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight,
                    persistedParam, persistedLastParamChange, responseHeight,
                    responseParam, veHist>>

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
    /\ pendingParam' = NoUpdate
    /\ updatePresent' = FALSE
    /\ validationOutcome' = "none"
    /\ rejectRule' = "none"
    /\ coverage' = coverage \cup {"crashed"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight,
                    persistedParam, persistedLastParamChange, responseHeight,
                    responseParam, veHist>>

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
                    pendingParam, updatePresent, validationOutcome,
                    rejectRule, veHist>>

BeginHandshake ==
    \* Info height and admissibility guards: replay.go:241-267,358-383.
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
                    updatePresent, validationOutcome, rejectRule, veHist>>

ReplayAppBlock ==
    \* Historical blocks use ExecCommitBlock without State mutation or
    \* parameter validation: internal/consensus/replay.go:441-489.
    /\ phase = "handshake"
    /\ appHeight < stateStoreHeight
    /\ appHeight' = appHeight + 1
    /\ replayMutatesState' = FALSE
    /\ coverage' = coverage \cup {"appOnlyReplay"}
    /\ UNCHANGED <<blockStoreHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    phase, pendingBlockHeight, pendingParam, updatePresent,
                    validationOutcome, rejectRule, veHist>>

SelectRealReplay ==
    \* App and state at S; use real app for stored block S+1:
    \* internal/consensus/replay.go:403-415,491-498.  The real app re-executes
    \* the block; FinalizeBlock's determinism guard reproduces the saved update.
    /\ phase = "handshake"
    /\ blockStoreHeight = stateStoreHeight + 1
    /\ appHeight = stateStoreHeight
    /\ pendingBlockHeight' = blockStoreHeight
    /\ phase' = "blockStored"
    /\ replayMutatesState' = TRUE
    /\ coverage' = coverage \cup {"realReplaySelected"}
                   \cup (IF responseHeight = blockStoreHeight /\ responseParam.abciPresent
                         THEN {"veUpdateRealReplay"} ELSE {})
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    pendingParam, updatePresent, validationOutcome, rejectRule,
                    veHist>>

SelectMockReplay ==
    \* App already at B; load saved response and mutate State with mock app:
    \* internal/consensus/replay.go:417-433.  The saved ConsensusParamUpdates
    \* are re-validated by the same updateState path (UPDATE interaction).
    \* UPDATE-MAP
    \* code: internal/consensus/replay.go:417-433 -> execution.go:279
    \* update: Update!InteractionActions
    /\ phase = "handshake"
    /\ blockStoreHeight = stateStoreHeight + 1
    /\ appHeight = blockStoreHeight
    /\ responseHeight = blockStoreHeight
    /\ pendingBlockHeight' = blockStoreHeight
    /\ phase' = "blockStored"
    /\ replayMutatesState' = TRUE
    /\ coverage' = coverage \cup {"mockReplaySelected"}
                   \cup (IF responseParam.abciPresent
                         THEN {"veUpdateMockReplay"} ELSE {})
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    pendingParam, updatePresent, validationOutcome, rejectRule,
                    veHist>>

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
                    validationOutcome, rejectRule, veHist>>

EnvironmentStutter ==
    \* Bounded model endpoint; unrelated next-height consensus is out of scope.
    /\ phase = "normal"
    /\ blockStoreHeight = MaxHeight
    /\ UNCHANGED vars

Next ==
    \/ SaveBlock
    \/ ApplyBlockStart
    \/ \E p \in Updates : FinalizeBlock(p)
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
\* verified: update (case-003 neutral "update" commit)
\* note:     representation revised: parameters are [rest, ve] records and updates are update records; no source evidence searched or expected for a type invariant.
\* review:   ok
TypeOK ==
    /\ blockStoreHeight \in 0..MaxHeight
    /\ appHeight \in 0..MaxHeight
    /\ stateStoreHeight \in 0..MaxHeight
    /\ stateHeight \in 0..MaxHeight
    /\ activeParam \in [rest : Rest, ve : Nat]
    /\ persistedParam \in [rest : Rest, ve : Nat]
    /\ lastParamChange \in Nat
    /\ persistedLastParamChange \in Nat
    /\ responseHeight \in 0..MaxHeight
    /\ responseParam \in Updates
    /\ phase \in Phases
    /\ replayMutatesState \in BOOLEAN
    /\ pendingBlockHeight \in 0..MaxHeight
    /\ pendingParam \in Updates
    /\ updatePresent = pendingParam.present
    /\ validationOutcome \in ValidationOutcomes
    /\ rejectRule \in RejectRules
    /\ DOMAIN veHist = 1..blockStoreHeight
    /\ \A m \in DOMAIN veHist : veHist[m] \in Nat
    /\ coverage \subseteq CoverageMarkers

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
\* verified: update (case-003 neutral "update" commit); watch locations untouched by the update
\* note:     unaffected by the update (no watch location changed); kept as the unaffected core-safety control.
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
\* verified: update (case-003 neutral "update" commit)
\* clause block-height: requirement — stateHeight = pendingBlockHeight: §Execution (the new state is one above the state the block ran on), §Header (block height == previous + 1) and TestValidateBlockHeader (a block at the wrong height fails validation).
\* clause saved-base: unknown — stateHeight = stateStoreHeight + 1: §Execution gives "one above the state the block was executed on", but only impl (consensus/state.go:1822) makes that state the last saved one; the history search found no stated rule.
\* note:     the update changes only the guard of UpdateStateAccepted (which (state, update, height) triples reach "updated"); the height assignments read by this property are unchanged; keep evidence in spec/invariant-evidence.json.
\* review:   ok
SuccessfulApplyAdvancesExactlyOne ==
    phase \in {"updated", "committed"} =>
        /\ stateHeight = stateStoreHeight + 1
        /\ stateHeight = pendingBlockHeight

\* REQ-EVIDENCE RejectedUpdateDoesNotInstall
\* intent:   When a block's consensus-parameter update fails validation, the state is not advanced past that block and its consensus parameters are those of the state the block was applied to.
\* status:   mixed
\* evidence: comment source/internal/state/execution.go:615 "NOTE: must not mutate state.ConsensusParams" -> computing and validating the candidate update leaves the input state's consensus parameters untouched
\* evidence: contract source/types/params.go:287-288 "NOTE: note: must not modify the original." -> computing the candidate parameters does not modify the current ones
\* evidence: comment source/internal/consensus/state.go:1808 "Either way, the State should not be resumed until we" -> the state does not move past a block until ApplyBlock has succeeded
\* evidence: impl source/internal/state/execution.go:619 "validating new consensus params: %w"
\* evidence: impl source/internal/state/execution.go:624 "updating consensus params: %w"
\* evidence: impl source/internal/consensus/state.go:1835 "failed to apply block; error %v"
\* watch:    source/internal/state/execution.go:updateState; source/internal/state/execution.go:BlockExecutor.ApplyBlock; source/types/params.go:ConsensusParams.Update; source/types/params.go:ConsensusParams.ValidateBasic; source/types/params.go:ConsensusParams.ValidateUpdate; source/internal/consensus/state.go:State.finalizeCommit
\* verified: update (case-003 neutral "update" commit)
\* clause not-installed: requirement — stateHeight and activeParam stay those of the state the block was applied to.
\* clause change-height: unknown — lastParamChange = persistedLastParamChange: only impl (execution.go:624 returns before lastHeightParamsChanged is assigned).
\* clause saved-copy: unknown — the conjuncts compare against the saved state; only impl relates the input State to the saved copy.
\* note:     watch location ValidateUpdate touched by the update; the formula is unchanged and now compares [rest, ve] records (representation-only change); decision keep, evidence in spec/invariant-evidence.json.
\* review:   ok
RejectedUpdateDoesNotInstall ==
    phase = "rejected" =>
        /\ stateHeight = stateStoreHeight
        /\ activeParam = persistedParam
        /\ lastParamChange = persistedLastParamChange

\* REQ-EVIDENCE ParameterUpdateReflected
\* intent:   Once a block's consensus-parameter update has been accepted and until the resulting state is saved, the parameter set that results from applying the update to the pre-block parameters is the state's consensus parameters, it satisfies the basic parameter constraints, and the recorded change height is the block height plus one.
\* status:   requirement
\* evidence: protocol spec/abci/abci++_methods.md §FinalizeBlock "returned for block `H` apply to the consensus params for block `H+1`" -> the update is applied to the consensus parameters, effective from H+1
\* evidence: protocol spec/abci/abci++_app_requirements.md §`FinalizeBlock`, `PrepareProposal`/`ProcessProposal` "If `ConsensusParams` is not `nil`, CometBFT will use it." -> a present update is installed as the consensus parameters
\* evidence: protocol spec/abci/abci++_app_requirements.md §Updating Consensus Parameters "Each field that is not empty will be applied in full." -> the installed parameters are the pre-block parameters with each present subrecord replaced
\* evidence: protocol spec/abci/abci++_app_requirements.md §Updating Consensus Parameters "The updates returned in block `H` will take effect right away for block `H+1`." -> recorded change height is H+1
\* evidence: comment source/internal/state/execution.go:629 "Change results from this height but only applies to the next height." -> recorded change height is H+1
\* evidence: test source/internal/state/state_test.go:1071 TestConsensusParamsChangesSaveLoad "assert.EqualValues(t, testCase.params, p," -> parameters returned at a change height are the ones in effect from the next height
\* evidence: protocol spec/abci/abci++_app_requirements.md §ABCIParams.VoteExtensionsEnableHeight "This parameter is either 0 or a positive height" -> an installed enable height is never negative
\* evidence: protocol spec/abci/abci++_app_requirements.md §BlockParams.MaxBytes "Must have `MaxBytes == -1` OR `0 < MaxBytes <= 100 MB`." -> consensus parameters must satisfy value constraints
\* evidence: impl source/internal/state/execution.go:616 "nextParams = state.ConsensusParams.Update(abciResponse.ConsensusParamUpdates)"
\* evidence: impl source/internal/state/execution.go:630 "lastHeightParamsChanged = header.Height + 1"
\* watch:    source/internal/state/execution.go:updateState; source/types/params.go:ConsensusParams.Update; source/types/params.go:ConsensusParams.ValidateBasic; source/types/params.go:ConsensusParams.ValidateUpdate; source/internal/state/store.go:dbStore.save; source/spec/abci/abci++_methods.md:FinalizeBlock
\* verified: update (case-003 neutral "update" commit)
\* note:     modified: V0's validity clause "pendingParam \in ValidParams" referred to a fixed relation that the update replaced by a height-dependent ValidateUpdate; the basic-validity part is kept here as ValidateBasic(activeParam) and the enable-height transition rules moved to Update!AcceptedVEUpdateRespectsRules, which states them from the protocol text rather than from the implementation table.  The installed-value clause now states the Update semantics (apply to the pre-block, persisted params).
\* review:   ok
ParameterUpdateReflected ==
    (phase \in {"updated", "committed"} /\ updatePresent) =>
        /\ activeParam = ApplyUpdate(persistedParam, pendingParam)
        /\ ValidateBasic(activeParam)
        /\ lastParamChange = pendingBlockHeight + 1

\* REQ-EVIDENCE NormalPhaseIsSynchronized
\* intent:   Whenever the node is between heights in normal operation, the app, the block store and the saved state are at the same height, and the in-memory state (height, consensus parameters, parameter-change height) equals the saved state.
\* status:   requirement
\* evidence: protocol spec/abci/abci++_app_requirements.md §Crash Recovery "`block_stored`, `state_stored`, `app_persisted_state`: we move on to the next height." -> the next height starts only when block, state and app are all persisted for the current one
\* evidence: test source/internal/consensus/replay_test.go:745 testHandshakeReplay "require.Equal(t, store.Height(), res.LastBlockHeight)" -> after startup the app height equals the block store height
\* evidence: test source/internal/consensus/replay_test.go:750 testHandshakeReplay "require.Equal(t, state.LastBlockHeight, res.LastBlockHeight)" -> after startup the saved state height equals the app height
\* evidence: contract source/internal/state/execution.go:206 "commits the app, and saves the new state and responses." -> the state handed back after a block is the state that was saved
\* evidence: contract source/internal/state/store.go:77 "Save overwrites the previous state with the updated one" -> after a save the saved state equals the in-memory state
\* evidence: impl source/node/node.go:355 "Reload the state. It will have the Version.Consensus.App set by the"
\* evidence: impl source/internal/consensus/replay.go:395 "// We're good!"
\* evidence: impl source/internal/state/execution.go:297 "if err := blockExec.store.Save(state); err != nil {"
\* watch:    source/internal/state/execution.go:BlockExecutor.ApplyBlock; source/internal/state/store.go:dbStore.Save; source/internal/consensus/state.go:State.finalizeCommit; source/internal/consensus/replay.go:Handshaker.ReplayBlocks; source/node/node.go:NewNode
\* verified: update (case-003 neutral "update" commit); watch locations untouched
\* note:     representation-only change (parameter equality now compares [rest, ve] records); kept.
\* review:   ok
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
\* evidence: test source/internal/consensus/replay_test.go:745 testHandshakeReplay "require.Equal(t, store.Height(), res.LastBlockHeight)" -> after the handshake app height equals block store height
\* evidence: impl source/internal/consensus/replay.go:272 "Completed ABCI Handshake - CometBFT and App are synced"
\* watch:    source/internal/consensus/replay.go:Handshaker.Handshake; source/internal/consensus/replay.go:Handshaker.ReplayBlocks; source/internal/consensus/replay.go:Handshaker.replayBlocks; source/node/setup.go:doHandshake; source/node/node.go:NewNode; source/internal/consensus/state.go:State.finalizeCommit
\* verified: update (case-003 neutral "update" commit); watch locations untouched
\* note:     unaffected by the update; kept.
\* review:   ok
RecoveryNormalOnlySupported ==
    (phase = "normal" /\ "handshakeStarted" \in coverage) =>
        /\ "handshakeComplete" \in coverage
        /\ appHeight = blockStoreHeight
        /\ stateStoreHeight = blockStoreHeight

=============================================================================
