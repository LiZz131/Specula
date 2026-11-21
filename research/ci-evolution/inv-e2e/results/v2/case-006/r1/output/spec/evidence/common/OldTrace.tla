----------------------------- MODULE OldTrace -----------------------------
(***************************************************************************
 * Deterministic replay adapter for the fresh exact-old NDJSON trace.
 * Each trace record names an implementation transition and records the
 * relevant implementation state immediately after that transition.  The
 * ReadyPublish probe is the sole exception: newReady observes the state at
 * the publication boundary before node.run clears the delivered readStates;
 * its wrapper therefore checks both the observed pre-state and model post-state.
 *************************************************************************)
EXTENDS OldBase, Json

CONSTANT TraceFile

VARIABLE traceLine
traceVars == <<vars, traceLine>>

TraceLog == ndJsonDeserialize(TraceFile)

ASSUME Len(TraceLog) > 0

TraceValue(v) == IF v = "" \/ v = Nil THEN Nil ELSE v

TraceMsg(x) ==
    Msg(x.type, x.from, x.to, x.term, x.index, x.logTerm, x.commit,
        x.entryTerm, TraceValue(x.value), TraceValue(x.ctx), x.reject)

ActivePendingCount(i) ==
    Cardinality({c \in ReadContexts : pendingReads[i][c].active})

ValidateCorePost(i, s) ==
    /\ term'[i] = s.term
    /\ vote'[i] = s.vote
    /\ role'[i] = s.role
    /\ leader'[i] = s.leader
    /\ commitIndex'[i] = s.commit
    /\ appliedIndex'[i] = s.applied
    /\ LogTerms(logs'[i]) = s.logTerms
    /\ readQueue'[i] = s.readQueue
    /\ Cardinality({c \in ReadContexts : pendingReads'[i][c].active}) =
         s.pendingCount

ValidatePost(i, s) ==
    /\ ValidateCorePost(i, s)
    /\ Len(producedReads'[i]) = s.readCount
    /\ s.readyReadCount = 0

ConsumeStandard(action, i, s) ==
    /\ action
    /\ ValidatePost(i, s)
    /\ traceLine' = traceLine + 1

ConsumeReady(i, s) ==
    /\ Len(producedReads[i]) = s.readCount
    /\ s.readyReadCount = Len(producedReads[i])
    /\ ReadyPublish(i)
    /\ ValidateCorePost(i, s)
    /\ Len(producedReads'[i]) = 0
    /\ traceLine' = traceLine + 1

ConsumeCurrent ==
    LET rec == TraceLog[traceLine]
        e == rec.event
        i == e.nid
        s == e.state
    IN CASE e.name = "Campaign" ->
              ConsumeStandard(Campaign(i), i, s)
         [] e.name = "HandleVoteRequest" ->
              ConsumeStandard(HandleVoteRequest(i, TraceMsg(e.msg)), i, s)
         [] e.name = "HandleVoteResponse" ->
              ConsumeStandard(HandleVoteResponse(i, TraceMsg(e.msg)), i, s)
         [] e.name = "BecomeLeader" ->
              ConsumeStandard(BecomeLeader(i), i, s)
         [] e.name = "ClientProposal" ->
              ConsumeStandard(ClientProposal(i, TraceValue(e.msg.value)), i, s)
         [] e.name = "HandleAppendEntries" ->
              ConsumeStandard(HandleAppendEntries(i, TraceMsg(e.msg)), i, s)
         [] e.name = "HandleAppendResponse" ->
              ConsumeStandard(HandleAppendResponse(i, TraceMsg(e.msg)), i, s)
         [] e.name = "BroadcastHeartbeat" ->
              ConsumeStandard(BroadcastHeartbeat(i), i, s)
         [] e.name = "HandleHeartbeat" ->
              ConsumeStandard(HandleHeartbeat(i, TraceMsg(e.msg)), i, s)
         [] e.name = "ClientReadIndex" ->
              ConsumeStandard(ClientReadIndex(i, e.msg.ctx, e.msg.from), i, s)
         [] e.name = "HandleHeartbeatResponse" ->
              ConsumeStandard(HandleHeartbeatResponse(i, TraceMsg(e.msg)), i, s)
         [] e.name = "ReadyPublish" -> ConsumeReady(i, s)
         [] e.name = "ReadyAdvance" ->
              ConsumeStandard(ReadyAdvance(i), i, s)
         [] e.name = "CheckQuorum" ->
              ConsumeStandard(CheckQuorum(i), i, s)
         [] OTHER -> FALSE

TraceInit ==
    /\ Init
    /\ traceLine = 1

TraceNext ==
    /\ traceLine <= Len(TraceLog)
    /\ ConsumeCurrent

TraceSpec ==
    /\ TraceInit
    /\ [][TraceNext]_traceVars
    /\ WF_traceVars(TraceNext)

\* REQ-EVIDENCE TraceCanProgress
\* intent:   trace-replay check: while trace records remain, the next recorded transition can be replayed from the current model state.
\* status:   model-internal
\* verified: base
\* review:   ok
TraceCanProgress ==
    traceLine <= Len(TraceLog) => ENABLED TraceNext

\* REQ-EVIDENCE TraceMatched
\* intent:   trace-replay check: replay eventually consumes every record of the trace file.
\* status:   model-internal
\* verified: base
\* review:   ok
TraceMatched == <>(traceLine = Len(TraceLog) + 1)

\* REQ-EVIDENCE TraceTypeOK
\* intent:   the base type invariant holds and the trace cursor stays within the trace bounds.
\* status:   model-internal
\* verified: base
\* review:   ok
TraceTypeOK ==
    /\ TypeOK
    /\ traceLine \in 1..(Len(TraceLog) + 1)

=============================================================================
