------------------------------- MODULE base -------------------------------
(***************************************************************************
CometBFT state execution and recovery model -- updated reference (V1).

V0 (exact-old) represented a complete consensus-parameter record by an opaque
identity and validation by a static set ValidParams.  The updated source
(types/params.go:208-261, ConsensusParams.ValidateUpdate) decides acceptance
from the *current* ABCI.VoteExtensionsEnableHeight, the *proposed* one, and the
height of the block being executed.  A static set cannot express that, so V1
refines the representation:

  * a complete parameter record is [body |-> B, veh |-> V] where B is a
    symbolic identity of the non-ABCI sub-records (Block, Evidence,
    Validator, Version) and V is ABCI.VoteExtensionsEnableHeight;
  * a FinalizeBlock consensus_param_updates value is NoParam (nil) or
    [body |-> B', abci |-> A] where B' is the body that results from applying
    the non-ABCI sub-records and A is NoAbci (Abci sub-record nil) or the
    proposed VoteExtensionsEnableHeight;
  * ValidateBasic and ValidateUpdate are code-faithful operators.

UPDATE-MAP
  code:   types/params.go:208-261 (ValidateUpdate rows 1-9)
  update: Update!AffectedActions, Update!ContractLegalUpdateAccepted,
          Update!VEEnableHeightImmutableOnceEnabled,
          Update!VEStatusOfDecidedHeightsPreserved
***************************************************************************)
EXTENDS Integers, FiniteSets, TLC

CONSTANTS
    MaxHeight,
    Bodies,          \* symbolic non-ABCI sub-record identities
    ValidBodies,     \* bodies passing the non-ABCI checks of ValidateBasic
    VEHValues,       \* candidate VoteExtensionsEnableHeight values in updates
    InitialBody,
    InitialVEHs,     \* genesis VoteExtensionsEnableHeight choices
    NoParam,         \* FinalizeBlockResponse.ConsensusParamUpdates == nil
    NoAbci           \* ConsensusParamUpdates.Abci == nil

ASSUME /\ MaxHeight \in Nat \ {0}
       /\ Bodies /= {}
       /\ ValidBodies \subseteq Bodies
       /\ InitialBody \in ValidBodies
       /\ VEHValues \subseteq Int
       /\ InitialVEHs \subseteq Nat /\ InitialVEHs /= {}
       /\ NoAbci \notin Int

VARIABLES
    blockStoreHeight,             \* internal/store/store.go:84-88
    appHeight,                    \* internal/consensus/replay.go:248-252
    stateStoreHeight,             \* internal/state/state.go:54-79
    stateHeight,                  \* in-memory State.LastBlockHeight
    activeParam,                  \* in-memory State.ConsensusParams
    persistedParam,               \* state-store State.ConsensusParams
    lastParamChange,              \* State.LastHeightConsensusParamsChanged
    persistedLastParamChange,
    responseHeight,               \* durable latest FinalizeBlockResponse
    responseParam,                \* its ConsensusParamUpdates descriptor
    phase,
    replayMutatesState,
    pendingBlockHeight,
    pendingParam,                 \* in-flight ConsensusParamUpdates descriptor
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
RejectStages == {"basic", "update"}

VEHDomain == VEHValues \cup InitialVEHs
ParamRecords == [body : Bodies, veh : VEHDomain]
UpdateRecords == [body : Bodies, abci : VEHValues \cup {NoAbci}]
UpdateOrNone == UpdateRecords \cup {NoParam}

-----------------------------------------------------------------------------
(* Parameter helpers -- code-faithful.                                      *)

\* ConsensusParams.Update, types/params.go:289-318: copy, then replace every
\* non-nil sub-record in full.  The non-ABCI replacement is summarized by the
\* resulting body; Abci (types/params.go:314-316) replaces the enable height.
ApplyParamUpdate(cur, upd) ==
    [body |-> upd.body,
     veh  |-> IF upd.abci = NoAbci THEN cur.veh ELSE upd.abci]

\* ConsensusParams.ValidateBasic, types/params.go:145-206.  The only ABCI
\* check is types/params.go:188-190 (enable height cannot be negative).
ValidateBasicOK(p) ==
    /\ p.body \in ValidBodies
    /\ p.veh >= 0

\* ConsensusParams.ValidateUpdate, types/params.go:219-261 (updated revision).
\* updateState calls it only for a non-nil update (execution.go:614,622) with
\* h = header.Height, the height of the block being executed.
\* UPDATE-MAP code: types/params.go:219-261  update: Update!AffectedActions
ValidateUpdateOK(cur, upd, h) ==
    LET c == cur.veh
        u == upd.abci
    IN  IF u = NoAbci THEN TRUE                   \* row 1: params.go:221-223
        ELSE IF u < 0 THEN FALSE                  \* row 2: params.go:225-227
        ELSE IF c <= 0 /\ u = 0 THEN TRUE         \* row 3: params.go:229-231
        ELSE IF c > 0 /\ u = 0                    \* rows 4/5: params.go:233-242
             THEN ~(c <= h)                       \*   4: reject if c <= h; 5: nil
        ELSE IF u <= h THEN FALSE                 \* row 6: params.go:244-248
        ELSE IF c <= 0 THEN TRUE                  \* row 7: params.go:250-252
        ELSE IF c <= h THEN FALSE                 \* row 8: params.go:254-258
        ELSE TRUE                                 \* row 9: params.go:260

\* ABCIParams.VoteExtensionsEnabled, types/params.go:75-83 (h >= 1).
VEEnabled(veh, h) == veh /= 0 /\ veh <= h

\* updateState acceptance predicate, internal/state/execution.go:611-631.
UpdateAccepted(cur, upd, h) ==
    \/ upd = NoParam                                         \* :614
    \/ /\ upd /= NoParam
       /\ ValidateBasicOK(ApplyParamUpdate(cur, upd))        \* :616-620
       /\ ValidateUpdateOK(cur, upd, h)                      \* :622-625

-----------------------------------------------------------------------------

Init ==
    \* Genesis state: internal/state/state.go:334-352.
    /\ blockStoreHeight = 0
    /\ appHeight = 0
    /\ stateStoreHeight = 0
    /\ stateHeight = 0
    /\ \E v \in InitialVEHs :
         /\ activeParam = [body |-> InitialBody, veh |-> v]
         /\ persistedParam = activeParam
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
                    updatePresent, validationOutcome>>

FinalizeBlock(p) ==
    \* Synchronous app transition: internal/state/execution.go:218-234.
    \* p is the response's ConsensusParamUpdates descriptor (or NoParam).
    /\ phase = "applying"
    /\ p \in UpdateOrNone
    \* A previously saved response for H must replay deterministically
    \* (ABCI determinism; mock replay reuses it: replay.go:417-433).
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
    \* updateState: copy+Update, ValidateBasic, ValidateUpdate, then build the
    \* H state: internal/state/execution.go:611-652.
    \* UPDATE-MAP code: types/params.go:219-261 via execution.go:622
    \*            update: Update!AffectedActions (MCUpdateStateAccepted)
    /\ phase = "responseSaved"
    /\ UpdateAccepted(activeParam, pendingParam, pendingBlockHeight)
    /\ stateHeight' = pendingBlockHeight                        \* :641
    /\ activeParam' = IF updatePresent                          \* :612-616,648
                      THEN ApplyParamUpdate(activeParam, pendingParam)
                      ELSE activeParam
    /\ lastParamChange' = IF updatePresent                      \* :613,630,649
                           THEN pendingBlockHeight + 1
                           ELSE lastParamChange
    /\ validationOutcome' = "accepted"
    /\ phase' = "updated"
    /\ coverage' = coverage \cup {"acceptedUpdate"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight,
                    persistedParam, persistedLastParamChange, responseHeight,
                    responseParam, replayMutatesState, pendingBlockHeight,
                    pendingParam, updatePresent>>

UpdateStateRejected(stage) ==
    \* Both validation failures return the input State: execution.go:617-625;
    \* ApplyBlock returns the error before Commit: execution.go:279-282.
    \* stage "basic"  : ValidateBasic failed  (execution.go:617-620)
    \* stage "update" : ValidateUpdate failed (execution.go:622-625)
    \* UPDATE-MAP code: types/params.go:219-261 via execution.go:622
    \*            update: Update!AffectedActions (MCUpdateStateRejected)
    /\ phase = "responseSaved"
    /\ updatePresent
    /\ stage \in RejectStages
    /\ LET next == ApplyParamUpdate(activeParam, pendingParam) IN
         \/ /\ stage = "basic"
            /\ ~ValidateBasicOK(next)
         \/ /\ stage = "update"
            /\ ValidateBasicOK(next)
            /\ ~ValidateUpdateOK(activeParam, pendingParam, pendingBlockHeight)
    /\ validationOutcome' = "rejected"
    /\ phase' = "rejected"
    /\ coverage' = coverage \cup {"rejectedUpdate"}
    /\ UNCHANGED <<blockStoreHeight, appHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    replayMutatesState, pendingBlockHeight, pendingParam,
                    updatePresent>>

CommitApp ==
    \* App persists H before state save: execution.go:284-288,379-418.
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
    \* Production consensus treats ApplyBlock error as fatal:
    \* internal/consensus/state.go:1826-1836 (panic); a replayed ApplyBlock
    \* error fails Handshake: replay.go:513-516, 266-270; node.go:351.
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
    \* internal/consensus/replay.go:399-415,491-498.  The replayed ApplyBlock
    \* re-runs updateState, hence ValidateUpdate (execution.go:279,622).
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
    \* internal/consensus/replay.go:417-433.  The mock app returns the saved
    \* response, which updateState validates again (execution.go:279,622).
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
    \/ \E p \in UpdateOrNone : FinalizeBlock(p)
    \/ SaveFinalizeBlockResponse
    \/ UpdateStateAccepted
    \/ \E s \in RejectStages : UpdateStateRejected(s)
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

-----------------------------------------------------------------------------
(* Reference properties (V0 properties, re-expressed for V1 representation) *)

TypeOK ==
    /\ blockStoreHeight \in 0..MaxHeight
    /\ appHeight \in 0..MaxHeight
    /\ stateStoreHeight \in 0..MaxHeight
    /\ stateHeight \in 0..MaxHeight
    /\ activeParam \in ParamRecords
    /\ persistedParam \in ParamRecords
    /\ lastParamChange \in Nat
    /\ persistedLastParamChange \in Nat
    /\ responseHeight \in 0..MaxHeight
    /\ responseParam \in UpdateOrNone
    /\ phase \in Phases
    /\ replayMutatesState \in BOOLEAN
    /\ pendingBlockHeight \in 0..MaxHeight
    /\ pendingParam \in UpdateOrNone
    /\ updatePresent \in BOOLEAN
    /\ validationOutcome \in ValidationOutcomes
    /\ coverage \subseteq {"blockStored", "applyStarted", "finalized",
                            "responseSaved", "acceptedUpdate",
                            "rejectedUpdate", "appCommitted", "stateSaved",
                            "rejectedAbort", "crashed", "appReportedOlder",
                            "handshakeStarted", "appOnlyReplay",
                            "realReplaySelected", "mockReplaySelected",
                            "handshakeComplete"}

\* Structural: every installed or persisted record passed ValidateBasic.
InstalledParamsBasicValid ==
    /\ ValidateBasicOK(activeParam)
    /\ ValidateBasicOK(persistedParam)

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

\* V0 property, re-expressed: the accepted update is the record produced by
\* ConsensusParams.Update from the pre-update (persisted) record, it is
\* basic-valid, and its change height is H+1 (execution.go:612-630).
ParameterUpdateReflected ==
    (phase \in {"updated", "committed"} /\ updatePresent) =>
        /\ activeParam = ApplyParamUpdate(persistedParam, pendingParam)
        /\ ValidateBasicOK(activeParam)
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

=============================================================================
