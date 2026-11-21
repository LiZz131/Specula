------------------------------- MODULE Update -------------------------------
(***************************************************************************
Update-focused checking lens for the case-003 source update
(types/params.go ConsensusParams.ValidateUpdate rewrite).

Reference behavior is owned by base.tla / MC.tla.  This module only selects
Actions, defines the environment summary for omitted context, and (via its
property section UpdateProps.tla) states the update properties.  No Action
body is copied here.
***************************************************************************)
EXTENDS MC, UpdateProps

(***************************************************************************
Affected Actions: the two outcomes of updateState whose guards call the
rewritten ValidateUpdate.
  reference: base!UpdateStateAccepted, base!UpdateStateRejected
  code:      internal/state/execution.go:614-631 -> types/params.go:219-262
***************************************************************************)
AffectedActions ==
    \/ MCUpdateStateAccepted
    \/ MCUpdateStateRejected

(***************************************************************************
Interaction Actions (concrete):
  producer   FinalizeBlock (app returns ConsensusParamUpdates)    execution.go:218-234
  durable    SaveFinalizeBlockResponse (update survives a crash)   execution.go:252-256
  consumer   SaveBlock (extended-commit decision uses the enable
             height in effect, recorded in veHist)                 consensus/state.go:1781-1792
  persist    CommitApp, SaveState (accepted params become durable) execution.go:284-299
  halt       AbortRejectedApply (ApplyBlock error panics)          consensus/state.go:1834-1836
  fault      Crash
  recovery   BeginHandshake, SelectRealReplay, SelectMockReplay
             (saved/re-executed update re-validated), CompleteHandshake
                                                                   consensus/replay.go:241-438
***************************************************************************)
InteractionActions ==
    \/ MCSaveBlock
    \/ MCApplyBlockStart
    \/ \E p \in Updates : MCFinalizeBlock(p)
    \/ MCSaveFinalizeBlockResponse
    \/ MCCommitApp
    \/ MCSaveState
    \/ MCAbortRejectedApply
    \/ MCCrash
    \/ MCBeginHandshake
    \/ MCSelectRealReplay
    \/ MCSelectMockReplay
    \/ MCCompleteHandshake
    \/ MCEnvironmentStutter

(***************************************************************************
Omitted context: ReplayAppBlock (ExecCommitBlock app-only catch-up,
replay.go:441-489) and AppReportsOlderHeight (Info reports an older app
height, replay.go:388-406).  Neither reads or writes consensus parameters,
the saved response, veHist, or the CometBFT state; both only move the
application height while the node is down or handshaking.  EnvUpdate
over-approximates them: any application height up to the saved state
height, with every update-visible variable framed.
***************************************************************************)
OmittedContextActions ==
    \/ MCReplayAppBlock
    \/ \E h \in 0..MaxHeight : MCAppReportsOlderHeight(h)

EnvUpdate ==
    /\ phase \in {"down", "handshake"}
    /\ appHeight' \in 0..stateStoreHeight
    /\ appHeight' /= appHeight
    /\ replayMutatesState' \in {replayMutatesState, FALSE}
    /\ coverage' \in {coverage \cup X : X \in SUBSET {"appOnlyReplay", "appReportedOlder"}}
    /\ \E r \in {counters.appRollbacks, counters.appRollbacks + 1} \cap 0..MaxAppRollbacks :
          counters' = [counters EXCEPT !.appRollbacks = r]
    /\ UNCHANGED <<blockStoreHeight, stateStoreHeight, stateHeight,
                    activeParam, persistedParam, lastParamChange,
                    persistedLastParamChange, responseHeight, responseParam,
                    phase, pendingBlockHeight, pendingParam, updatePresent,
                    validationOutcome, rejectRule, veHist>>

\* Negative control for the discharge check (expected to FAIL): a rely that
\* forbids the handshake-phase app catch-up must be violated by ReplayAppBlock.
EnvUpdateTooStrong == EnvUpdate /\ phase = "down"
DischargeControlTooStrong == [][OmittedContextActions => EnvUpdateTooStrong]_mcVars

FocusedNext == AffectedActions \/ InteractionActions
FocusedSpec == MCInit /\ [][FocusedNext]_mcVars

OpenUpdateNext == AffectedActions \/ InteractionActions \/ EnvUpdate
OpenSpec == MCInit /\ [][OpenUpdateNext]_mcVars

\* Discharge: every omitted real context step satisfies the rely (checked as
\* an action property over the full MCSpec reachable state space).
DischargeContext == [][OmittedContextActions => EnvUpdate]_mcVars

=============================================================================
