----------------------------- MODULE Trace -----------------------------
(***************************************************************************
 * Deterministic replay adapter for fresh NDJSON traces of the updated
 * implementation (artifact c780d355).  Each trace record names an
 * implementation transition and records the relevant implementation state
 * immediately after that transition.  The ReadyPublish probe is the sole
 * exception: newReady observes the state at the publication boundary before
 * node.run clears the delivered readStates; its wrapper therefore checks both
 * the observed pre-state and model post-state.
 *
 * Update-mandatory state fields (instrumentation-spec.md):
 *   pending    - every pendingReadIndex entry: ctx, captured index, requester
 *                (req.From) and acknowledgement set.  This observes the
 *                update directly: released contexts must leave the map.
 *   readStates - every r.readStates element (index, ctx): the read index and
 *                context actually produced for the application.
 *************************************************************************)
EXTENDS base, Json, IOUtils

CONSTANT TraceFile

VARIABLE traceLine
traceVars == <<vars, traceLine>>

JsonFile ==
    IF "JSON" \in DOMAIN IOEnv THEN IOEnv.JSON ELSE TraceFile

TraceLog == ndJsonDeserialize(JsonFile)

ASSUME Len(TraceLog) > 0

TraceValue(v) == IF v = "" \/ v = Nil THEN Nil ELSE v

TraceMsg(x) ==
    Msg(x.type, x.from, x.to, x.term, x.index, x.logTerm, x.commit,
        x.entryTerm, TraceValue(x.value), TraceValue(x.ctx), x.reject)

\* In-flight model messages whose behavioral fields equal the traced message.
\* Only the ghost gstamp may differ.  When the model never sent such a
\* message (raw raft.Step injection by a test), fall back to the traced
\* projection, as V0 did.
BagMsgs(x) ==
    LET tm == TraceMsg(x)
        cand == {m \in messages : [m EXCEPT !.gstamp = 0] = tm}
    IN IF cand = {} THEN {tm} ELSE cand

SeqToSet(s) == {s[k] : k \in 1..Len(s)}

\* Exact pendingReadIndex comparison (read_only.go:35-39).
PendingMatches(i, s) ==
    /\ {c \in ReadContexts : pendingReads'[i][c].active} =
         {s.pending[k].ctx : k \in 1..Len(s.pending)}
    /\ \A k \in 1..Len(s.pending) :
         LET e == s.pending[k] IN
         /\ e.ctx \in ReadContexts
         /\ pendingReads'[i][e.ctx].index = e.index
         /\ pendingReads'[i][e.ctx].requester = e.from
         /\ pendingReads'[i][e.ctx].acks = SeqToSet(e.acks)
    /\ Cardinality({c \in ReadContexts : pendingReads'[i][c].active}) =
         s.pendingCount

\* Exact r.readStates comparison (raft.go:215, read_only.go:24-27).
ReadStatesMatch(pr, s) ==
    /\ Len(pr) = s.readCount
    /\ Len(pr) = Len(s.readStates)
    /\ \A k \in 1..Len(pr) :
         /\ pr[k].index = s.readStates[k].index
         /\ pr[k].ctx = s.readStates[k].ctx

ValidateCorePost(i, s) ==
    /\ term'[i] = s.term
    /\ vote'[i] = s.vote
    /\ role'[i] = s.role
    /\ leader'[i] = s.leader
    /\ commitIndex'[i] = s.commit
    /\ appliedIndex'[i] = s.applied
    /\ LogTerms(logs'[i]) = s.logTerms
    /\ readQueue'[i] = s.readQueue
    /\ PendingMatches(i, s)

ValidatePost(i, s) ==
    /\ ValidateCorePost(i, s)
    /\ ReadStatesMatch(producedReads'[i], s)
    /\ s.readyReadCount = 0

ConsumeStandard(action, i, s) ==
    /\ action
    /\ ValidatePost(i, s)
    /\ traceLine' = traceLine + 1

ConsumeReady(i, s) ==
    /\ ReadStatesMatch(producedReads[i], s)
    /\ s.readyReadCount = Len(producedReads[i])
    /\ ReadyPublish(i)
    /\ ValidateCorePost(i, s)
    /\ Len(producedReads'[i]) = 0
    /\ traceLine' = traceLine + 1

\* stepLeader MsgReadIndex is one implementation branch for both local and
\* forwarded requests; the model separates the forwarded message consumer.
IsForwardedRead(i, x) ==
    \E m \in messages :
        /\ m.mtype = MsgReadIndex /\ m.to = i
        /\ m.from = x.from /\ m.ctx = x.ctx

ConsumeCurrent ==
    LET rec == TraceLog[traceLine]
        e == rec.event
        i == e.nid
        s == e.state
    IN CASE e.name = "Campaign" ->
              ConsumeStandard(Campaign(i), i, s)
         [] e.name = "HandleVoteRequest" ->
              \E m \in BagMsgs(e.msg) :
                 ConsumeStandard(HandleVoteRequest(i, m), i, s)
         [] e.name = "HandleVoteResponse" ->
              \E m \in BagMsgs(e.msg) :
                 ConsumeStandard(HandleVoteResponse(i, m), i, s)
         [] e.name = "BecomeLeader" ->
              ConsumeStandard(BecomeLeader(i), i, s)
         [] e.name = "ClientProposal" ->
              ConsumeStandard(ClientProposal(i, TraceValue(e.msg.value)), i, s)
         [] e.name = "HandleAppendEntries" ->
              \E m \in BagMsgs(e.msg) :
                 ConsumeStandard(HandleAppendEntries(i, m), i, s)
         [] e.name = "HandleAppendResponse" ->
              \E m \in BagMsgs(e.msg) :
                 ConsumeStandard(HandleAppendResponse(i, m), i, s)
         [] e.name = "BroadcastHeartbeat" ->
              ConsumeStandard(BroadcastHeartbeat(i), i, s)
         [] e.name = "HandleHeartbeat" ->
              \E m \in BagMsgs(e.msg) :
                 ConsumeStandard(HandleHeartbeat(i, m), i, s)
         [] e.name = "ClientReadIndex" ->
              IF e.msg.from /= i /\ IsForwardedRead(i, e.msg)
              THEN \E m \in BagMsgs(e.msg) :
                     ConsumeStandard(HandleReadIndexRequest(i, m), i, s)
              ELSE ConsumeStandard(ClientReadIndex(i, e.msg.ctx, e.msg.from),
                                   i, s)
         [] e.name = "ForwardReadIndex" ->
              ConsumeStandard(ForwardReadIndex(i, e.msg.ctx), i, s)
         [] e.name = "HandleHeartbeatResponse" ->
              \E m \in BagMsgs(e.msg) :
                 ConsumeStandard(HandleHeartbeatResponse(i, m), i, s)
         [] e.name = "HandleReadIndexResponse" ->
              \E m \in BagMsgs(e.msg) :
                 ConsumeStandard(HandleReadIndexResponse(i, m), i, s)
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
\* verified: update (c780d355)
\* review:   ok
TraceCanProgress ==
    traceLine <= Len(TraceLog) => ENABLED TraceNext

\* REQ-EVIDENCE TraceMatched
\* intent:   trace-replay check: replay eventually consumes every record of the trace file.
\* status:   model-internal
\* verified: update (c780d355)
\* review:   ok
TraceMatched == <>(traceLine = Len(TraceLog) + 1)

\* REQ-EVIDENCE TraceTypeOK
\* intent:   the base type invariant holds and the trace cursor stays within the trace bounds.
\* status:   model-internal
\* verified: update (c780d355)
\* review:   ok
TraceTypeOK ==
    /\ TypeOK
    /\ traceLine \in 1..(Len(TraceLog) + 1)

\* Replay-complete marker used by evidence configs that evaluate update
\* properties on the final replayed state of a fully consumed trace.
TraceDone == traceLine = Len(TraceLog) + 1

=============================================================================
