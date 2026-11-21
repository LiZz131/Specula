------------------------------- MODULE Update ------------------------------
(***************************************************************************
Update-focused checking lens for the V1 source update
(artifact 9dd6e50 -> 401753b: ConsensusParams.ValidateUpdate rewrite).

All behavior is owned by base.tla / MC.tla.  This module only selects
actions, defines an evidence-based environment for omitted context, and
states update-specific properties.  See analysis-report.md section 4 and
spec/invariant-evidence.json.
***************************************************************************)
EXTENDS MC

(***************************************************************************
Affected Actions: reference actions whose guard calls the changed
ValidateUpdate.
***************************************************************************)
\* reference: base!UpdateStateAccepted, base!UpdateStateRejectedVE
\* code: types/params.go:208-261 via internal/state/execution.go:622-625
AffectedActions ==
    \/ MCUpdateStateAccepted
    \/ MCUpdateStateRejectedVE

(***************************************************************************
Interaction Actions (kept concrete): producers of ValidateUpdate's inputs,
consumers of its result, and the crash/recovery paths that re-run it.
***************************************************************************)
InteractionActions ==
    \* establishes h = header.Height: consensus/state.go:1781-1817
    \/ MCSaveBlock
    \/ MCApplyBlockStart
    \* producer of updates, Abci presence and VEH: execution.go:218-234
    \/ \E p \in ParamOrNone, a \in BOOLEAN : MCFinalizeBlock(p, a)
    \* response durable before validation: execution.go:253-256
    \/ MCSaveFinalizeBlockResponse
    \* sibling validation path (masks ValidateUpdate row 2): execution.go:617-620
    \/ MCUpdateStateRejectedBasic
    \* consumers of acceptance: execution.go:284-299
    \/ MCCommitApp
    \/ MCSaveState
    \* consumer of rejection (panic / failed startup): consensus/state.go:1834-1836
    \/ MCAbortRejectedApply
    \* crash windows around the changed boundary
    \/ MCCrash
    \* recovery re-runs the changed validation: replay.go:399-433
    \/ MCBeginHandshake
    \/ MCSelectRealReplay
    \/ MCSelectMockReplay
    \/ MCCompleteHandshake
    \* bounded endpoint (no behavior)
    \/ MCEnvironmentStutter

(***************************************************************************
Omitted context and its environment summary.
AppReportsOlderHeight (replay.go:388-406) and ReplayAppBlock
(replay.go:441-489) only move the application's height while the node is
down or handshaking; app-only replay uses ExecCommitBlock and never calls
ValidateUpdate or touches CometBFT state, parameters or responses.
***************************************************************************)
OmittedContextActions ==
    \/ \E h \in 0..MaxHeight : MCAppReportsOlderHeight(h)
    \/ MCReplayAppBlock

EnvMarkers == {"appReportedOlder", "appOnlyReplay"}

EnvUpdate ==
    /\ phase \in {"down", "handshake"}
    /\ appHeight' \in 0..MaxHeight
    /\ appHeight' /= appHeight
    \* never above what the stores justify (replay.go:388-406,441-489)
    /\ appHeight' <= IF appHeight > stateStoreHeight
                     THEN appHeight ELSE stateStoreHeight
    /\ coverage' \in {coverage \cup X : X \in SUBSET EnvMarkers}
    /\ UNCHANGED <<blockStoreHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    responseAbciPresent, phase, replayMutatesState,
                    pendingBlockHeight, pendingParam, pendingAbciPresent,
                    updatePresent, validationOutcome>>

\* MC-private frame: the omitted context never consumes block or crash budget.
EnvCounterFrame ==
    /\ counters'.blocks = counters.blocks
    /\ counters'.crashes = counters.crashes
    /\ counters'.appRollbacks \in {counters.appRollbacks,
                                   counters.appRollbacks + 1}

\* Discharge obligation, checked over the full MCSpec.
DischargeContext ==
    [][OmittedContextActions => (EnvUpdate /\ EnvCounterFrame)]_mcVars

\* Falsifiability control for the discharge run: a rely that forbids the
\* app-height moves must be violated by the real omitted actions.
DischargeStrictControl ==
    [][OmittedContextActions => UNCHANGED appHeight]_mcVars

FocusedNext == AffectedActions \/ InteractionActions
OpenUpdateNext ==
    \/ FocusedNext
    \/ (EnvUpdate /\ UNCHANGED counters)

FocusedSpec == MCInit /\ [][FocusedNext]_mcVars
OpenUpdateSpec == MCInit /\ [][OpenUpdateNext]_mcVars

(***************************************************************************
Update-specific properties.
While phase is updated/committed, persistedParam still holds the receiver
of ValidateUpdate (base!ValidationInputStable + UpdateStateAccepted leaves
persistedParam unchanged); while phase is rejected, activeParam is the
receiver as well.
***************************************************************************)
PreUpdateVEH == persistedParam.veh
AcceptedUpdateHeld == phase \in {"updated", "committed"} /\ updatePresent
VERejectionHeld ==
    /\ phase = "rejected"
    /\ updatePresent
    /\ ValidateBasicOK(pendingParam)

\* U4. Once the enable height is reached (P > 0, P <= h), no accepted update
\* may change it (neither disable nor move).
\* req: spec/abci/abci++_app_requirements.md:760-777
\* code: types/params.go:232-239 (row 4), :253-258 (row 8)
VEReachedImmutable ==
    (AcceptedUpdateHeld /\ PreUpdateVEH > 0
                        /\ PreUpdateVEH <= pendingBlockHeight)
        => activeParam.veh = PreUpdateVEH

\* U5. An accepted change to a non-zero enable height targets a future height.
\* req: spec/abci/abci++_app_requirements.md:776,1126-1129
\* code: types/params.go:243-248 (row 6)
VEChangeOnlyToFuture ==
    (AcceptedUpdateHeld /\ activeParam.veh /= PreUpdateVEH
                        /\ activeParam.veh /= 0)
        => activeParam.veh > pendingBlockHeight

\* U1. Enabling vote extensions from the disabled state to a future height is
\* contract-compliant and must not be rejected (a rejection halts the chain).
\* req: spec/abci/abci++_app_requirements.md:1118-1131,800-807
\* code: types/params.go:249-252 (row 7); old 9dd6e50:types/params.go:223-228
EnableFromDisabledNotRejected ==
    (VERejectionHeld /\ pendingAbciPresent /\ activeParam.veh = 0)
        => ~(pendingParam.veh > pendingBlockHeight)

\* U2/U7. An update that leaves VoteExtensionsEnableHeight unchanged is
\* contract-compliant and must not be rejected (a rejection halts the chain
\* and recurs on every replay).
\* req: spec/abci/abci++_app_requirements.md:776-777,783-790,800-807;
\*      old-source/types/params_test.go:196-204 ("no error when unchanged")
\* contested by: new-source/types/params_test.go:168-169 test data and the
\*      row-6 comment at types/params.go:214 (see invariant-evidence.json)
\* code: types/params.go:243-248 (row 6); old 9dd6e50:types/params.go:212-214
UnchangedVENotRejected ==
    VERejectionHeld => pendingParam.veh /= activeParam.veh

CompliantVEUpdateNotRejected ==
    EnableFromDisabledNotRejected /\ UnchangedVENotRejected

(***************************************************************************
Update reachability canaries (expected violations = witnesses).
***************************************************************************)
ReachedReachedVEAccepted ==
    AcceptedUpdateHeld /\ PreUpdateVEH > 0 /\ PreUpdateVEH <= pendingBlockHeight
ReachedFutureVEChangeAccepted ==
    AcceptedUpdateHeld /\ activeParam.veh /= PreUpdateVEH /\ activeParam.veh /= 0
ReachedEnableAttemptRejected ==
    VERejectionHeld /\ pendingAbciPresent /\ activeParam.veh = 0
\* With InitialVEHs = {0}: row 7 accepted, committed and saved, so a later
\* block runs with vote extensions scheduled.
ReachedSavedEnable ==
    /\ phase = "normal"
    /\ persistedParam.veh > 0
    /\ persistedLastParamChange > 1
ReachedMockReplayOfVEChange ==
    /\ replayMutatesState
    /\ phase \in {"updated", "committed"}
    /\ "mockReplaySelected" \in coverage
    /\ pendingAbciPresent
    /\ activeParam.veh /= PreUpdateVEH

\* Consequence witness for UnchangedVENotRejected: the unchanged-VEH update is
\* rejected again while the stored block is replayed at startup.
ReachedReplayRejectionOfUnchanged ==
    VERejectionHeld /\ replayMutatesState /\ pendingParam.veh = activeParam.veh

NeverReachedReachedVEAccepted == ~ReachedReachedVEAccepted
NeverReachedReplayRejectionOfUnchanged == ~ReachedReplayRejectionOfUnchanged
\* ... after an earlier rejection already aborted the node (AbortRejectedApply):
\* the halt survives restart and real/mock final-block replay.
ReachedHaltPersists ==
    ReachedReplayRejectionOfUnchanged /\ "rejectedAbort" \in coverage
NeverReachedHaltPersists == ~ReachedHaltPersists
NeverReachedFutureVEChangeAccepted == ~ReachedFutureVEChangeAccepted
NeverReachedEnableAttemptRejected == ~ReachedEnableAttemptRejected
NeverReachedMockReplayOfVEChange == ~ReachedMockReplayOfVEChange
NeverReachedSavedEnable == ~ReachedSavedEnable
NeverReachedOpenEnv ==
    ~("appReportedOlder" \in coverage /\ "appOnlyReplay" \in coverage)

=============================================================================
