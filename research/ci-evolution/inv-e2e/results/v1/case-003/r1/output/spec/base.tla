------------------------------- MODULE base -------------------------------
(***************************************************************************
V1 CometBFT state execution and recovery model (updated source revision,
artifact commit 401753b).

A complete consensus-parameter record is represented by
  [other |-> symbolic identity of the Block/Evidence/Validator/Version
             sub-records, veh |-> integer ABCI.VoteExtensionsEnableHeight].
The vote-extension height is explicit because the updated
ConsensusParams.ValidateUpdate decides acceptance from the current height,
the current enable height, the presence of the Abci sub-record, and the
updated enable height (types/params.go:208-261).  All other parameter fields
stay symbolic: ValidOthers is the result of the non-ABCI ValidateBasic checks
(types/params.go:145-187,192-205).

V0 used a static ValidParams set; it could not express the height- and
current-value-dependent decision.  See analysis-report.md section 3.
***************************************************************************)
EXTENDS Integers, FiniteSets, TLC

CONSTANTS MaxHeight,       \* bound on block heights explored
          Others,          \* symbolic non-ABCI parameter identities
          ValidOthers,     \* identities passing the non-ABCI ValidateBasic checks
          VEHeights,       \* finite domain of VoteExtensionsEnableHeight values
          InitialOthers,   \* genesis non-ABCI identities
          InitialVEHs      \* genesis VoteExtensionsEnableHeight values

\* UPDATE-MAP
\* code: types/params.go:35-41,68-71 (ConsensusParams / ABCIParams shape)
\* update: Update!AffectedActions (record shape feeds ValidateUpdateRow)
NoOther == "NoOther"
Params == [other : Others, veh : VEHeights]
\* Distinguished "no ConsensusParamUpdates" value; same record type as Params
\* so that TLC can compare it with real records.
NoParam == [other |-> NoOther, veh |-> 0]
ParamOrNone == Params \cup {NoParam}

\* ValidateBasic on a complete record: types/params.go:145-205.
\* Non-ABCI checks (:146-187,192-203) are summarized by ValidOthers; the ABCI
\* check is explicit: VoteExtensionsEnableHeight must not be negative (:188-190).
ValidateBasicOK(p) ==
    /\ p.other \in ValidOthers
    /\ p.veh >= 0

ValidParams == {p \in Params : ValidateBasicOK(p)}

InitialParams == [other : InitialOthers, veh : InitialVEHs]

ASSUME /\ MaxHeight \in Nat \ {0}
       /\ Others /= {}
       /\ NoOther \notin Others
       /\ ValidOthers \subseteq Others
       /\ VEHeights \subseteq Int
       /\ 0 \in VEHeights
       /\ InitialOthers \subseteq ValidOthers
       /\ InitialOthers /= {}
       /\ InitialVEHs \subseteq VEHeights
       /\ InitialVEHs /= {}
       \* Genesis parameters pass ValidateBasic: types/genesis.go ValidateAndComplete.
       /\ InitialParams \subseteq ValidParams

(***************************************************************************
ValidateUpdate, updated revision, transcribed row by row.
cur = params.ABCI.VoteExtensionsEnableHeight (current in-memory state),
abci = (updated.Abci /= nil), upd = updated.Abci.VoteExtensionsEnableHeight,
h = header.Height of the block being finalized (execution.go:622).
Returns the row number of the comment table at types/params.go:208-218.
***************************************************************************)
\* UPDATE-MAP
\* code: types/params.go:208-261 (ValidateUpdate, rows 1-9)
\* update: Update!AffectedActions, Update!VEReachedImmutable,
\*         Update!VEChangeOnlyToFuture, Update!EnableFromDisabledNotRejected,
\*         Update!UnchangedVENotRejected
ValidateUpdateRow(cur, abci, upd, h) ==
    \* row 1: updated == nil || updated.Abci == nil -> nil  (:220-223)
    IF ~abci THEN 1
    \* row 2: updated VEH < 0 -> error                       (:224-227)
    ELSE IF upd < 0 THEN 2
    \* row 3: cur <= 0 && upd == 0 -> nil                    (:228-231)
    ELSE IF cur <= 0 /\ upd = 0 THEN 3
    \* rows 4/5: cur > 0 && upd == 0                         (:232-242)
    ELSE IF cur > 0 /\ upd = 0
         THEN IF cur <= h THEN 4   \* error: disabled once enabled (:234-239)
              ELSE 5               \* nil: disable a future proposal (:240-241)
    \* row 6: upd <= h -> error (implicit upd > 0)          (:243-248)
    ELSE IF upd <= h THEN 6
    \* row 7: cur <= 0 -> nil (implicit upd > h)             (:249-252)
    ELSE IF cur <= 0 THEN 7
    \* row 8: cur <= h -> error (implicit cur > 0, upd > h)  (:253-258)
    ELSE IF cur <= h THEN 8
    \* row 9: nil (cur > h, upd > h)                         (:259-260)
    ELSE 9

AcceptingRows == {1, 3, 5, 7, 9}

ValidateUpdateOK(cur, abci, upd, h) ==
    ValidateUpdateRow(cur, abci, upd, h) \in AcceptingRows

VARIABLES
    blockStoreHeight,             \* BlockStore.Height(): internal/store/store.go
    appHeight,                    \* app durable height via Info: replay.go:243-251
    stateStoreHeight,             \* saved State.LastBlockHeight: internal/state/store.go
    stateHeight,                  \* in-memory State.LastBlockHeight
    activeParam,                  \* in-memory State.ConsensusParams
    persistedParam,               \* state-store State.ConsensusParams
    lastParamChange,              \* State.LastHeightConsensusParamsChanged
    persistedLastParamChange,
    responseHeight,               \* durable latest FinalizeBlockResponse height
    responseParam,                \* resulting params of that response (or NoParam)
    responseAbciPresent,          \* that response carried a non-nil Abci sub-record
    phase,
    replayMutatesState,
    pendingBlockHeight,
    pendingParam,                 \* current.Update(updates) or NoParam
    pendingAbciPresent,           \* updates.Abci /= nil
    updatePresent,                \* updates /= nil
    validationOutcome,
    coverage                      \* observer-only non-vacuity markers

vars == <<blockStoreHeight, appHeight, stateStoreHeight, stateHeight,
          activeParam, persistedParam, lastParamChange,
          persistedLastParamChange, responseHeight, responseParam,
          responseAbciPresent, phase, replayMutatesState, pendingBlockHeight,
          pendingParam, pendingAbciPresent, updatePresent, validationOutcome,
          coverage>>

Phases == {"normal", "blockStored", "applying", "finalized",
           "responseSaved", "updated", "committed", "rejected",
           "down", "handshake"}
ValidationOutcomes == {"none", "accepted", "rejected"}

CoverageMarkers ==
    {"blockStored", "applyStarted", "finalized", "responseSaved",
     "acceptedUpdate", "rejectedUpdate", "appCommitted", "stateSaved",
     "rejectedAbort", "crashed", "appReportedOlder", "handshakeStarted",
     "appOnlyReplay", "realReplaySelected", "mockReplaySelected",
     "handshakeComplete"}

Init ==
    \* Genesis state: internal/state/state.go:334-352 (ConsensusParams from the
    \* genesis doc, LastHeightConsensusParamsChanged = InitialHeight = 1).
    /\ blockStoreHeight = 0
    /\ appHeight = 0
    /\ stateStoreHeight = 0
    /\ stateHeight = 0
    /\ activeParam \in InitialParams
    /\ persistedParam = activeParam
    /\ lastParamChange = 1
    /\ persistedLastParamChange = 1
    /\ responseHeight = 0
    /\ responseParam = NoParam
    /\ responseAbciPresent = FALSE
    /\ phase = "normal"
    /\ replayMutatesState = FALSE
    /\ pendingBlockHeight = 0
    /\ pendingParam = NoParam
    /\ pendingAbciPresent = FALSE
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
                    responseAbciPresent, replayMutatesState, pendingParam,
                    pendingAbciPresent, updatePresent, validationOutcome>>

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
                    responseAbciPresent, replayMutatesState,
                    pendingBlockHeight, pendingParam, pendingAbciPresent,
                    updatePresent, validationOutcome>>

FinalizeBlock(p, abci) ==
    \* Synchronous app transition: internal/state/execution.go:218-234.
    \* p is the resulting record state.ConsensusParams.Update(updates)
    \* (types/params.go:289-318) or NoParam when updates == nil.
    /\ phase = "applying"
    /\ p \in ParamOrNone
    /\ abci \in BOOLEAN
    \* No updates at all: no Abci sub-record either.
    /\ (p = NoParam => ~abci)
    \* Update copies the current VEH unless params2.Abci /= nil:
    \* types/params.go:290,314-316.
    /\ ((p /= NoParam /\ ~abci) => p.veh = activeParam.veh)
    \* A previously saved response for H must replay deterministically.
    \* internal/consensus/replay.go:399-433; ABCI determinism contract.
    /\ (responseHeight = pendingBlockHeight =>
            /\ p = responseParam
            /\ abci = responseAbciPresent)
    /\ pendingParam' = p
    /\ pendingAbciPresent' = abci
    /\ updatePresent' = (p /= NoParam)
    /\ phase' = "finalized"
    /\ coverage' = coverage \cup {"finalized"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    responseAbciPresent, replayMutatesState,
                    pendingBlockHeight, validationOutcome>>

SaveFinalizeBlockResponse ==
    \* Sync-save response before validation: execution.go:253-256 and
    \* internal/state/store.go:562-601.
    /\ phase = "finalized"
    /\ responseHeight' = pendingBlockHeight
    /\ responseParam' = pendingParam
    /\ responseAbciPresent' = pendingAbciPresent
    /\ phase' = "responseSaved"
    /\ coverage' = coverage \cup {"responseSaved"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, replayMutatesState,
                    pendingBlockHeight, pendingParam, pendingAbciPresent,
                    updatePresent, validationOutcome>>

\* UPDATE-MAP
\* code: internal/state/execution.go:612-631 calling types/params.go:219-261
\* update: Update!AffectedActions (MCUpdateStateAccepted)
UpdateStateAccepted ==
    \* Update copy, validate, then construct H state: execution.go:611-652.
    /\ phase = "responseSaved"
    \* execution.go:615: no ConsensusParamUpdates -> params unchanged.
    /\ \/ ~updatePresent
       \/ /\ updatePresent
          \* nextParams.ValidateBasic() succeeds: execution.go:617-620.
          /\ ValidateBasicOK(pendingParam)
          \* state.ConsensusParams.ValidateUpdate(updates, header.Height)
          \* succeeds: execution.go:622-625; types/params.go:219-261.
          /\ ValidateUpdateOK(activeParam.veh, pendingAbciPresent,
                              pendingParam.veh, pendingBlockHeight)
    /\ stateHeight' = pendingBlockHeight
    \* ConsensusParams: nextParams (execution.go:613,646).
    /\ activeParam' = IF updatePresent THEN pendingParam ELSE activeParam
    \* LastHeightConsensusParamsChanged = header.Height + 1 (execution.go:630).
    /\ lastParamChange' = IF updatePresent
                           THEN pendingBlockHeight + 1
                           ELSE lastParamChange
    /\ validationOutcome' = "accepted"
    /\ phase' = "updated"
    /\ coverage' = coverage \cup {"acceptedUpdate"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight,
                    persistedParam, persistedLastParamChange, responseHeight,
                    responseParam, responseAbciPresent, replayMutatesState,
                    pendingBlockHeight, pendingParam, pendingAbciPresent,
                    updatePresent>>

UpdateStateRejectedBasic ==
    \* nextParams.ValidateBasic() error returns the input State:
    \* execution.go:617-620 (types/params.go:145-205).  Unchanged by the update;
    \* it also masks ValidateUpdate row 2 (negative VEH, params.go:188-190).
    /\ phase = "responseSaved"
    /\ updatePresent
    /\ ~ValidateBasicOK(pendingParam)
    /\ validationOutcome' = "rejected"
    /\ phase' = "rejected"
    /\ coverage' = coverage \cup {"rejectedUpdate"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    responseAbciPresent, replayMutatesState,
                    pendingBlockHeight, pendingParam, pendingAbciPresent,
                    updatePresent>>

\* UPDATE-MAP
\* code: internal/state/execution.go:622-625 calling types/params.go:219-261
\* update: Update!AffectedActions (MCUpdateStateRejectedVE)
UpdateStateRejectedVE ==
    \* ValidateUpdate error returns the input State: execution.go:622-625.
    /\ phase = "responseSaved"
    /\ updatePresent
    /\ ValidateBasicOK(pendingParam)
    /\ ~ValidateUpdateOK(activeParam.veh, pendingAbciPresent,
                         pendingParam.veh, pendingBlockHeight)
    /\ validationOutcome' = "rejected"
    /\ phase' = "rejected"
    /\ coverage' = coverage \cup {"rejectedUpdate"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    responseAbciPresent, replayMutatesState,
                    pendingBlockHeight, pendingParam, pendingAbciPresent,
                    updatePresent>>

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
                    responseAbciPresent, replayMutatesState,
                    pendingBlockHeight, pendingParam, pendingAbciPresent,
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
    /\ pendingAbciPresent' = FALSE
    /\ updatePresent' = FALSE
    /\ validationOutcome' = "none"
    /\ coverage' = coverage \cup {"stateSaved"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateHeight, activeParam,
                    lastParamChange, responseHeight, responseParam,
                    responseAbciPresent, replayMutatesState>>

AbortRejectedApply ==
    \* Production consensus and block sync treat an ApplyBlock error as fatal:
    \* internal/consensus/state.go:1834-1836; internal/blocksync/reactor.go:530-533.
    \* During handshake replay the error aborts startup: replay.go:268-271,
    \* node/setup.go:200.  Durable state is kept; volatile state is lost.
    /\ phase = "rejected"
    /\ stateHeight' = stateStoreHeight
    /\ activeParam' = persistedParam
    /\ lastParamChange' = persistedLastParamChange
    /\ phase' = "down"
    /\ replayMutatesState' = FALSE
    /\ pendingBlockHeight' = 0
    /\ pendingParam' = NoParam
    /\ pendingAbciPresent' = FALSE
    /\ updatePresent' = FALSE
    /\ validationOutcome' = "none"
    /\ coverage' = coverage \cup {"rejectedAbort"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight,
                    persistedParam, persistedLastParamChange, responseHeight,
                    responseParam, responseAbciPresent>>

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
    /\ pendingAbciPresent' = FALSE
    /\ updatePresent' = FALSE
    /\ validationOutcome' = "none"
    /\ coverage' = coverage \cup {"crashed"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight,
                    persistedParam, persistedLastParamChange, responseHeight,
                    responseParam, responseAbciPresent>>

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
                    responseAbciPresent, phase, replayMutatesState,
                    pendingBlockHeight, pendingParam, pendingAbciPresent,
                    updatePresent, validationOutcome>>

BeginHandshake ==
    \* Info height and admissibility guards: replay.go:241-277,358-383.
    /\ phase = "down"
    /\ appHeight <= blockStoreHeight
    /\ stateStoreHeight <= blockStoreHeight
    /\ blockStoreHeight <= stateStoreHeight + 1
    /\ phase' = "handshake"
    /\ coverage' = coverage \cup {"handshakeStarted"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    responseAbciPresent, replayMutatesState,
                    pendingBlockHeight, pendingParam, pendingAbciPresent,
                    updatePresent, validationOutcome>>

ReplayAppBlock ==
    \* Historical blocks use ExecCommitBlock without State mutation and without
    \* parameter validation: internal/consensus/replay.go:441-489.
    /\ phase = "handshake"
    /\ appHeight < stateStoreHeight
    /\ appHeight' = appHeight + 1
    /\ replayMutatesState' = FALSE
    /\ coverage' = coverage \cup {"appOnlyReplay"}
    /\ UNCHANGED <<blockStoreHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    responseAbciPresent, phase, pendingBlockHeight,
                    pendingParam, pendingAbciPresent, updatePresent,
                    validationOutcome>>

SelectRealReplay ==
    \* App and state at S; use real app for stored block S+1, re-running the
    \* ApplyBlock path including ValidateUpdate:
    \* internal/consensus/replay.go:399-415,491-498,504-521.
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
                    responseAbciPresent, pendingParam, pendingAbciPresent,
                    updatePresent, validationOutcome>>

SelectMockReplay ==
    \* App already at B; load saved response and mutate State with mock app,
    \* re-running ValidateUpdate on the saved updates:
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
                    responseAbciPresent, pendingParam, pendingAbciPresent,
                    updatePresent, validationOutcome>>

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
                    responseAbciPresent, pendingBlockHeight, pendingParam,
                    pendingAbciPresent, updatePresent, validationOutcome>>

EnvironmentStutter ==
    \* Bounded model endpoint; unrelated next-height consensus is out of scope.
    /\ phase = "normal"
    /\ blockStoreHeight = MaxHeight
    /\ UNCHANGED vars

Next ==
    \/ SaveBlock
    \/ ApplyBlockStart
    \/ \E p \in ParamOrNone, a \in BOOLEAN : FinalizeBlock(p, a)
    \/ SaveFinalizeBlockResponse
    \/ UpdateStateAccepted
    \/ UpdateStateRejectedBasic
    \/ UpdateStateRejectedVE
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

(***************************************************************************
Reference properties (unchanged meaning from V0 unless stated).
***************************************************************************)
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
    /\ responseAbciPresent \in BOOLEAN
    /\ phase \in Phases
    /\ replayMutatesState \in BOOLEAN
    /\ pendingBlockHeight \in 0..MaxHeight
    /\ pendingParam \in ParamOrNone
    /\ pendingAbciPresent \in BOOLEAN
    /\ updatePresent \in BOOLEAN
    /\ validationOutcome \in ValidationOutcomes
    /\ coverage \subseteq CoverageMarkers

PersistedHeightRelationships ==
    /\ stateStoreHeight <= blockStoreHeight
    /\ blockStoreHeight <= stateStoreHeight + 1
    /\ appHeight <= blockStoreHeight

SuccessfulApplyAdvancesExactlyOne ==
    phase \in {"updated", "committed"} =>
        /\ stateHeight = stateStoreHeight + 1
        /\ stateHeight = pendingBlockHeight

RejectedUpdateDoesNotInstall ==
    phase = "rejected" =>
        /\ stateHeight = stateStoreHeight
        /\ activeParam = persistedParam
        /\ lastParamChange = persistedLastParamChange

ParameterUpdateReflected ==
    (phase \in {"updated", "committed"} /\ updatePresent) =>
        /\ pendingParam \in ValidParams
        /\ activeParam = pendingParam
        /\ lastParamChange = pendingBlockHeight + 1

NormalPhaseIsSynchronized ==
    phase = "normal" =>
        /\ appHeight = blockStoreHeight
        /\ stateStoreHeight = blockStoreHeight
        /\ stateHeight = stateStoreHeight
        /\ activeParam = persistedParam
        /\ lastParamChange = persistedLastParamChange

RecoveryNormalOnlySupported ==
    (phase = "normal" /\ "handshakeStarted" \in coverage) =>
        /\ "handshakeComplete" \in coverage
        /\ appHeight = blockStoreHeight
        /\ stateStoreHeight = blockStoreHeight

\* V1 structural (repair of the V0 abstraction): CometBFT never holds or
\* persists a parameter record that fails ValidateBasic (genesis validation
\* plus execution.go:617-620).
InstalledParamsBasicValid ==
    /\ activeParam \in ValidParams
    /\ persistedParam \in ValidParams

\* V1 structural: until UpdateStateAccepted replaces it, the in-memory
\* parameter record used as ValidateUpdate's receiver equals the persisted
\* one.  Update.tla reads the pre-update value from persistedParam.
ValidationInputStable ==
    phase \in {"blockStored", "applying", "finalized", "responseSaved",
               "rejected"} =>
        /\ activeParam = persistedParam
        /\ lastParamChange = persistedLastParamChange
        /\ stateHeight = stateStoreHeight

=============================================================================
