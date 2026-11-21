------------------------------- MODULE Trace -------------------------------
(***************************************************************************
V1 trace validation over the updated reference base.tla.

Parameter records are captured as {"body": <fingerprint of the non-ABCI
sub-records>, "veh": <ABCI.VoteExtensionsEnableHeight>}.  Update descriptors
(ConsensusParamUpdates) are captured as {"present": bool, "body": ...,
"abciPresent": bool, "veh": ...}; ToUpdate maps them to base's NoParam /
[body, abci] representation, with NoParam/NoAbci as TLC model values so that
records, integers and markers are never compared as mixed TLC value types.

UPDATE-MAP
  code:   types/params.go:219-261 via internal/state/execution.go:622
  update: Update!AffectedActions (UpdateStateAccepted/UpdateStateRejected)
          -- the model's ValidateUpdateOK decides which wrapper is enabled and
          is compared with the implementation's observed accept/reject event
          and rejection stage.
***************************************************************************)
EXTENDS base, Json, IOUtils, Sequences, TLC

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

\* JSON -> model conversions -------------------------------------------------
ToParam(x) == [body |-> x.body, veh |-> x.veh]
ToUpdate(x) ==
    IF x.present
    THEN [body |-> x.body, abci |-> IF x.abciPresent THEN x.veh ELSE NoAbci]
    ELSE NoParam

Idx == 1..Len(TraceLog)
St(k) == TraceLog[k].event.state

StateParamObjs ==
    {St(k).activeParam : k \in Idx} \cup {St(k).persistedParam : k \in Idx}

UpdateObjs ==
    {St(k).pendingParam : k \in Idx} \cup {St(k).responseParam : k \in Idx}
    \cup {TraceLog[k].event.msg.proposedParam :
            k \in {j \in Idx : "proposedParam" \in DOMAIN TraceLog[j].event.msg}}

PresentUpdateObjs == {x \in UpdateObjs : x.present}

\* Body validity is the non-ABCI part of ValidateBasic.  The harness evaluates
\* it with the real ValidateBasic on the resulting record with the enable
\* height neutralized (instrumentation-spec.md); installed bodies are valid.
ValidProposedBodyIdx ==
    {k \in Idx : /\ TraceLog[k].event.name = "FinalizeBlock"
                 /\ TraceLog[k].event.msg.proposedParam.present
                 /\ TraceLog[k].event.msg.proposedBodyValid}

TraceBodies == TLCEval(
    {x.body : x \in StateParamObjs} \cup {x.body : x \in PresentUpdateObjs})

\* Only independent evidence: the bodies of the first (pre-trace, durable)
\* state and proposed bodies flagged valid by the real ValidateBasic.  Bodies
\* observed only in later post-states are NOT assumed valid (that would make
\* the acceptance of an invalid body and InstalledParamsBasicValid vacuous;
\* negative control M5, spec/output/negative-controls/).
TraceValidBodies == TLCEval(
    {St(1).activeParam.body, St(1).persistedParam.body}
    \cup {TraceLog[k].event.msg.proposedParam.body : k \in ValidProposedBodyIdx})

TraceVEHValues == TLCEval(
    {x.veh : x \in StateParamObjs}
    \cup {x.veh : x \in {y \in PresentUpdateObjs : y.abciPresent}})

TraceInitialBody == St(1).persistedParam.body
TraceInitialVEHs == {St(1).persistedParam.veh}

VARIABLE l
traceVars == <<vars, l>>

logline == TraceLog[l]

TraceInit ==
    LET s == St(1) IN
    /\ l = 1
    /\ IF TraceLog[1].event.name = "BlockStored"
       THEN
         \* Reconstruct the pre-save state from the first post-save event.
         \* SaveBlock is at internal/consensus/state.go:1781-1790.
         /\ blockStoreHeight = s.blockStoreHeight - 1
         /\ appHeight = s.appHeight
         /\ stateStoreHeight = s.stateStoreHeight
         /\ stateHeight = s.stateStoreHeight
         /\ activeParam = ToParam(s.persistedParam)
         /\ persistedParam = ToParam(s.persistedParam)
         /\ lastParamChange = s.persistedLastParamChange
         /\ persistedLastParamChange = s.persistedLastParamChange
         /\ responseHeight = s.responseHeight
         /\ responseParam = ToUpdate(s.responseParam)
         /\ phase = "normal"
         /\ replayMutatesState = FALSE
         /\ pendingBlockHeight = 0
         /\ pendingParam = NoParam
         /\ updatePresent = FALSE
         /\ validationOutcome = "none"
         /\ coverage = {}
       ELSE
         \* Handshake trace starts after Info; reconstruct the down state.
         \* internal/consensus/replay.go:241-267.
         /\ blockStoreHeight = s.blockStoreHeight
         /\ appHeight = s.appHeight
         /\ stateStoreHeight = s.stateStoreHeight
         /\ stateHeight = s.stateHeight
         /\ activeParam = ToParam(s.activeParam)
         /\ persistedParam = ToParam(s.persistedParam)
         /\ lastParamChange = s.lastParamChange
         /\ persistedLastParamChange = s.persistedLastParamChange
         /\ responseHeight = s.responseHeight
         /\ responseParam = ToUpdate(s.responseParam)
         /\ phase = "down"
         /\ replayMutatesState = FALSE
         /\ pendingBlockHeight = 0
         /\ pendingParam = NoParam
         /\ updatePresent = FALSE
         /\ validationOutcome = "none"
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
    /\ activeParam' = ToParam(s.activeParam)
    /\ persistedParam' = ToParam(s.persistedParam)
    /\ lastParamChange' = s.lastParamChange
    /\ persistedLastParamChange' = s.persistedLastParamChange
    /\ responseHeight' = s.responseHeight
    /\ responseParam' = ToUpdate(s.responseParam)
    /\ phase' = s.phase
    /\ replayMutatesState' = s.replayMutatesState
    /\ pendingBlockHeight' = s.pendingBlockHeight
    /\ pendingParam' = ToUpdate(s.pendingParam)
    /\ updatePresent' = s.pendingParam.present
    /\ validationOutcome' = s.validationOutcome

\* The update descriptor named by a validation event is the in-flight one.
ProposedMatchesPending ==
    ToUpdate(logline.event.msg.proposedParam) = pendingParam

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
    /\ FinalizeBlock(ToUpdate(logline.event.msg.proposedParam))
    /\ ValidatePostState
    /\ StepTrace

SaveFinalizeBlockResponseIfLogged ==
    /\ IsEvent("SaveFinalizeBlockResponse")
    /\ SaveFinalizeBlockResponse
    /\ ValidatePostState
    /\ StepTrace

UpdateStateAcceptedIfLogged ==
    /\ IsEvent("UpdateStateAccepted")
    /\ ProposedMatchesPending
    /\ UpdateStateAccepted
    /\ ValidatePostState
    /\ StepTrace

UpdateStateRejectedIfLogged ==
    /\ IsEvent("UpdateStateRejected")
    /\ ProposedMatchesPending
    /\ UpdateStateRejected(logline.event.msg.stage)
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

TraceMatched == <>(l > Len(TraceLog))

=============================================================================
