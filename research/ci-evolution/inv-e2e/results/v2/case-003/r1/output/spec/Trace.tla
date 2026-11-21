------------------------------- MODULE Trace -------------------------------
(***************************************************************************
Trace validation for the updated reference.  Every event carries a full
post-action snapshot; ValidatePostState compares every captured field,
including the structured parameter records, the update record, the
rejection rule and the per-height enable-height history.
***************************************************************************)
EXTENDS base, UpdateProps, Json, IOUtils, Sequences, TLC

JsonFile ==
    IF "JSON" \in DOMAIN IOEnv THEN IOEnv.JSON
    ELSE "../traces/apply_valid.ndjson"

TraceLog == TLCEval(
    LET all == ndJsonDeserialize(JsonFile)
    IN SelectSeq(all, LAMBDA x :
        /\ "tag" \in DOMAIN x
        /\ x.tag = "trace"
        /\ "event" \in DOMAIN x))

ASSUME Len(TraceLog) > 0
ASSUME TraceLog[1].event.name \in {"BlockStored", "HandshakeStart"}

Idx == 1..Len(TraceLog)

\* Update records proposed by FinalizeBlock events (msg.proposedParam).
ProposalIdx == {k \in Idx : "proposedParam" \in DOMAIN TraceLog[k].event.msg}
TraceProposals == {TraceLog[k].event.msg.proposedParam : k \in ProposalIdx}
\* Every update record that appears in a state snapshot.
TraceStateUpdates ==
    {TraceLog[k].event.state.pendingParam : k \in Idx}
    \cup {TraceLog[k].event.state.responseParam : k \in Idx}
TraceUpdates == TraceProposals \cup TraceStateUpdates

TraceStateParams ==
    {TraceLog[k].event.state.activeParam : k \in Idx}
    \cup {TraceLog[k].event.state.persistedParam : k \in Idx}

TraceRest == TLCEval(
    {p.rest : p \in TraceStateParams}
    \cup {u.rest : u \in {v \in TraceUpdates : v.present}})

\* Non-ABCI validity is symbolic: a rest identity is valid when it appears in
\* a CometBFT state, in an accepted update, or in an update rejected by a
\* ValidateUpdate row (ValidateBasic passed before ValidateUpdate ran,
\* execution.go:617-625).
AcceptedOrRowRejectedIdx ==
    {k \in Idx :
        \/ TraceLog[k].event.name = "UpdateStateAccepted"
        \/ /\ TraceLog[k].event.name = "UpdateStateRejected"
           /\ TraceLog[k].event.state.rejectRule /= "basic"}
TraceValidRest == TLCEval(
    {p.rest : p \in TraceStateParams}
    \cup {TraceLog[k].event.state.pendingParam.rest :
              k \in {j \in AcceptedOrRowRejectedIdx :
                        TraceLog[j].event.state.pendingParam.present}})

TraceVEValues == TLCEval(
    {u.abci : u \in TraceUpdates} \cup {p.ve : p \in TraceStateParams})

TraceInitialParams == {TraceLog[1].event.state.persistedParam}

VARIABLE l
traceVars == <<vars, l>>

logline == TraceLog[l]

TraceInit ==
    LET s == TraceLog[1].event.state IN
    /\ l = 1
    /\ IF TraceLog[1].event.name = "BlockStored"
       THEN
         \* Reconstruct the pre-save state from the first post-save event.
         \* SaveBlock is at internal/consensus/state.go:1781-1792.
         /\ blockStoreHeight = s.blockStoreHeight - 1
         /\ appHeight = s.appHeight
         /\ stateStoreHeight = s.stateStoreHeight
         /\ stateHeight = s.stateStoreHeight
         /\ activeParam = s.persistedParam
         /\ persistedParam = s.persistedParam
         /\ lastParamChange = s.persistedLastParamChange
         /\ persistedLastParamChange = s.persistedLastParamChange
         /\ responseHeight = s.responseHeight
         /\ responseParam = s.responseParam
         /\ phase = "normal"
         /\ replayMutatesState = FALSE
         /\ pendingBlockHeight = 0
         /\ pendingParam = NoUpdate
         /\ updatePresent = FALSE
         /\ validationOutcome = "none"
         /\ rejectRule = "none"
         /\ veHist = SubSeq(s.veHist, 1, Len(s.veHist) - 1)
         /\ coverage = {}
       ELSE
         \* Handshake trace starts after Info; reconstruct the down state.
         \* internal/consensus/replay.go:241-267.
         /\ blockStoreHeight = s.blockStoreHeight
         /\ appHeight = s.appHeight
         /\ stateStoreHeight = s.stateStoreHeight
         /\ stateHeight = s.stateHeight
         /\ activeParam = s.activeParam
         /\ persistedParam = s.persistedParam
         /\ lastParamChange = s.lastParamChange
         /\ persistedLastParamChange = s.persistedLastParamChange
         /\ responseHeight = s.responseHeight
         /\ responseParam = s.responseParam
         /\ phase = "down"
         /\ replayMutatesState = FALSE
         /\ pendingBlockHeight = 0
         /\ pendingParam = NoUpdate
         /\ updatePresent = FALSE
         /\ validationOutcome = "none"
         /\ rejectRule = "none"
         /\ veHist = s.veHist
         /\ coverage = {}

IsEvent(name) ==
    /\ l <= Len(TraceLog)
    /\ logline.event.name = name

StepTrace == l' = l + 1

ValidatePostState ==
    LET s == logline.event.state IN
    /\ blockStoreHeight' = s.blockStoreHeight
    /\ appHeight' = s.appHeight
    /\ stateStoreHeight' = s.stateStoreHeight
    /\ stateHeight' = s.stateHeight
    /\ activeParam' = s.activeParam
    /\ persistedParam' = s.persistedParam
    /\ lastParamChange' = s.lastParamChange
    /\ persistedLastParamChange' = s.persistedLastParamChange
    /\ responseHeight' = s.responseHeight
    /\ responseParam' = s.responseParam
    /\ phase' = s.phase
    /\ replayMutatesState' = s.replayMutatesState
    /\ pendingBlockHeight' = s.pendingBlockHeight
    /\ pendingParam' = s.pendingParam
    /\ updatePresent' = s.pendingParam.present
    /\ validationOutcome' = s.validationOutcome
    /\ rejectRule' = s.rejectRule
    /\ veHist' = s.veHist

BlockStoredIfLogged ==
    /\ IsEvent("BlockStored")
    /\ SaveBlock
    /\ ValidatePostState
    /\ StepTrace

ApplyBlockStartIfLogged ==
    /\ IsEvent("ApplyBlockStart")
    /\ ApplyBlockStart
    /\ ValidatePostState
    /\ StepTrace

FinalizeBlockIfLogged ==
    /\ IsEvent("FinalizeBlock")
    /\ FinalizeBlock(logline.event.msg.proposedParam)
    /\ ValidatePostState
    /\ StepTrace

SaveFinalizeBlockResponseIfLogged ==
    /\ IsEvent("SaveFinalizeBlockResponse")
    /\ SaveFinalizeBlockResponse
    /\ ValidatePostState
    /\ StepTrace

UpdateStateAcceptedIfLogged ==
    /\ IsEvent("UpdateStateAccepted")
    /\ UpdateStateAccepted
    /\ ValidatePostState
    /\ StepTrace

UpdateStateRejectedIfLogged ==
    /\ IsEvent("UpdateStateRejected")
    /\ UpdateStateRejected
    /\ ValidatePostState
    /\ StepTrace

CommitAppIfLogged ==
    /\ IsEvent("CommitApp")
    /\ CommitApp
    /\ ValidatePostState
    /\ StepTrace

SaveStateIfLogged ==
    /\ IsEvent("SaveState")
    /\ SaveState
    /\ ValidatePostState
    /\ StepTrace

HandshakeStartIfLogged ==
    /\ IsEvent("HandshakeStart")
    /\ BeginHandshake
    /\ ValidatePostState
    /\ StepTrace

ReplayAppBlockIfLogged ==
    /\ IsEvent("ReplayAppBlock")
    /\ ReplayAppBlock
    /\ ValidatePostState
    /\ StepTrace

ReplayStateBlockStartIfLogged ==
    /\ IsEvent("ReplayStateBlockStart")
    /\ IF logline.event.msg.mode = "real"
       THEN SelectRealReplay
       ELSE /\ logline.event.msg.mode = "mock"
            /\ SelectMockReplay
    /\ ValidatePostState
    /\ StepTrace

HandshakeCompleteIfLogged ==
    /\ IsEvent("HandshakeComplete")
    /\ CompleteHandshake
    /\ ValidatePostState
    /\ StepTrace

TraceStep ==
    \/ BlockStoredIfLogged
    \/ ApplyBlockStartIfLogged
    \/ FinalizeBlockIfLogged
    \/ SaveFinalizeBlockResponseIfLogged
    \/ UpdateStateAcceptedIfLogged
    \/ UpdateStateRejectedIfLogged
    \/ CommitAppIfLogged
    \/ SaveStateIfLogged
    \/ HandshakeStartIfLogged
    \/ ReplayAppBlockIfLogged
    \/ ReplayStateBlockStartIfLogged
    \/ HandshakeCompleteIfLogged

TraceNext ==
    \/ TraceStep
    \/ /\ l > Len(TraceLog)
       /\ UNCHANGED traceVars

TraceSpec ==
    /\ TraceInit
    /\ [][TraceNext]_traceVars
    /\ WF_traceVars(TraceStep)

\* REQ-EVIDENCE TraceMatched
\* intent:   Every event of the recorded trace is eventually consumed by the trace-validation behaviour.
\* status:   model-internal
\* watch:    none
\* verified: update (case-003 neutral "update" commit)
\* note:     no source evidence searched or expected for a trace-completeness check.
\* review:   ok
TraceMatched == <>(l > Len(TraceLog))

=============================================================================
