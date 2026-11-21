------------------------------- MODULE Trace -------------------------------
(***************************************************************************
V1 trace validation wrapper.  Every event calls the reference action and
validates the complete post-state snapshot.  Parameter records arrive as
JSON objects {"other": <fingerprint of the non-ABCI fields>, "veh": <int>};
NoParam is {"other": "NoOther", "veh": 0}.

The ValidateUpdate decision is NOT read from the trace: UpdateStateAccepted /
UpdateStateRejectedVE compute it from activeParam.veh, the logged
abciPresent flag, the logged proposed VEH and the block height, and the
logged event name/reason must agree with the model's decision.
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

TraceStates == {TraceLog[k].event.state : k \in 1..Len(TraceLog)}

ProposedIndexes ==
    {k \in 1..Len(TraceLog) :
        /\ "proposedParam" \in DOMAIN TraceLog[k].event.msg
        /\ TraceLog[k].event.msg.proposedParam /= NoParam}

StateParamRecords ==
    UNION {{s.activeParam, s.persistedParam, s.pendingParam, s.responseParam}
           : s \in TraceStates}

AllTraceParams == TLCEval(
    StateParamRecords
    \cup {TraceLog[k].event.msg.proposedParam : k \in ProposedIndexes})

\* Symbolic domains reconstructed from the observed records.
TraceOthers == TLCEval({p.other : p \in AllTraceParams} \ {NoOther})

\* Non-ABCI ValidateBasic outcome reported by the harness for the opaque part
\* (ValidateBasic on the record with VEH forced to 0).  The VEH part of
\* ValidateBasic and the whole ValidateUpdate decision are computed by base.
TraceValidOthers == TLCEval(
    {s.activeParam.other : s \in {t \in TraceStates : t.activeOtherValid}}
    \cup {TraceLog[k].event.msg.proposedParam.other :
            k \in {j \in ProposedIndexes :
                      /\ "proposedOtherValid" \in DOMAIN TraceLog[j].event.msg
                      /\ TraceLog[j].event.msg.proposedOtherValid}})

TraceVEHeights == TLCEval({0} \cup {p.veh : p \in AllTraceParams})

TraceInitialOthers == {TraceLog[1].event.state.persistedParam.other}
TraceInitialVEHs == {TraceLog[1].event.state.persistedParam.veh}

VARIABLE l
traceVars == <<vars, l>>

logline == TraceLog[l]

TraceInit ==
    LET s == TraceLog[1].event.state IN
    /\ l = 1
    /\ IF TraceLog[1].event.name = "BlockStored"
       THEN
         \* Reconstruct the pre-save state from the first post-save event.
         \* SaveBlock is at internal/consensus/state.go:1781-1790.
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
         /\ responseAbciPresent = s.responseAbciPresent
         /\ phase = "normal"
         /\ replayMutatesState = FALSE
         /\ pendingBlockHeight = 0
         /\ pendingParam = NoParam
         /\ pendingAbciPresent = FALSE
         /\ updatePresent = FALSE
         /\ validationOutcome = "none"
         /\ coverage = {}
       ELSE
         \* Handshake trace starts after Info; reconstruct the down state.
         \* internal/consensus/replay.go:241-277.
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
         /\ responseAbciPresent = s.responseAbciPresent
         /\ phase = "down"
         /\ replayMutatesState = FALSE
         /\ pendingBlockHeight = 0
         /\ pendingParam = NoParam
         /\ pendingAbciPresent = FALSE
         /\ updatePresent = FALSE
         /\ validationOutcome = "none"
         /\ coverage = {}

IsEvent(name) ==
    /\ l <= Len(TraceLog)
    /\ logline.event.name = name

StepTrace == l' = l + 1

\* Full post-state comparison; every captured field is checked.
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
    /\ responseAbciPresent' = s.responseAbciPresent
    /\ phase' = s.phase
    /\ replayMutatesState' = s.replayMutatesState
    /\ pendingBlockHeight' = s.pendingBlockHeight
    /\ pendingParam' = s.pendingParam
    /\ pendingAbciPresent' = s.pendingAbciPresent
    /\ updatePresent' = (s.pendingParam /= NoParam)
    /\ validationOutcome' = s.validationOutcome
    \* Harness-observed non-ABCI validity of the active record agrees with
    \* the model's ValidOthers classification.
    /\ (activeParam'.other \in ValidOthers) = s.activeOtherValid

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
    /\ logline.event.msg.updatePresent = (logline.event.msg.proposedParam /= NoParam)
    /\ FinalizeBlock(logline.event.msg.proposedParam,
                     logline.event.msg.abciPresent)
    /\ ValidatePostState
    /\ StepTrace

SaveFinalizeBlockResponseIfLogged ==
    /\ IsEvent("SaveFinalizeBlockResponse")
    /\ SaveFinalizeBlockResponse
    /\ ValidatePostState
    /\ StepTrace

UpdateStateAcceptedIfLogged ==
    /\ IsEvent("UpdateStateAccepted")
    /\ logline.event.msg.proposedParam = pendingParam
    /\ logline.event.msg.abciPresent = pendingAbciPresent
    /\ UpdateStateAccepted
    /\ ValidatePostState
    /\ StepTrace

UpdateStateRejectedIfLogged ==
    /\ IsEvent("UpdateStateRejected")
    /\ logline.event.msg.proposedParam = pendingParam
    /\ logline.event.msg.abciPresent = pendingAbciPresent
    \* execution.go:617-620 vs :622-625, classified by the wrapped error.
    /\ \/ /\ logline.event.msg.reason = "basic"
          /\ UpdateStateRejectedBasic
       \/ /\ logline.event.msg.reason = "update"
          /\ UpdateStateRejectedVE
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

\* Diagnostic alias: which row the model decided at each state.
TraceAlias ==
    [l |-> l, phase |-> phase, active |-> activeParam,
     pending |-> pendingParam, abci |-> pendingAbciPresent,
     h |-> pendingBlockHeight,
     row |-> IF updatePresent
             THEN ValidateUpdateRow(persistedParam.veh, pendingAbciPresent,
                                    pendingParam.veh, pendingBlockHeight)
             ELSE 0]

=============================================================================
