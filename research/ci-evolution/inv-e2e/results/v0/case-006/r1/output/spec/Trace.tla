----------------------------- MODULE Trace -----------------------------
(***************************************************************************
 * Deterministic replay adapter for fresh NDJSON traces of the updated
 * source.  Each trace record names an implementation transition and records
 * the relevant implementation state immediately after that transition.  The
 * ReadyPublish probe is the sole exception: newReady observes the state at
 * the publication boundary before delivery clears readStates; its wrapper
 * checks both the observed pre-state and the model post-state.
 *
 * V1 changes:
 *   - ValidateCorePost compares the exact set of pending contexts
 *     (state.pendingCtxs, keys of readOnly.pendingReadIndex) in addition to
 *     the count, so the updated delete (read_only.go:100-105) and context
 *     re-enqueue are compared, not just observed.
 *   - ValidatePost/ConsumeReady compare every produced ReadState's index and
 *     context (state.readStates), so released read indexes are compared.
 *   - Heartbeat, heartbeat-response and forwarded read messages carry a ghost
 *     incarnation tag in the model; their wrappers consume the in-flight
 *     model message whose observable fields equal the traced message.
 *   - Forwarded reads: ForwardReadIndex, HandleReadIndexRequest and
 *     HandleReadIndexResponse events.
 *************************************************************************)
EXTENDS base, Json, UpdateProps

CONSTANT TraceFile

VARIABLE traceLine
traceVars == <<vars, traceLine>>

TraceLog == ndJsonDeserialize(TraceFile)

ASSUME Len(TraceLog) > 0

TraceValue(v) == IF v = "" \/ v = Nil THEN Nil ELSE v

TraceMsg(x) ==
    Msg(x.type, x.from, x.to, x.term, x.index, x.logTerm, x.commit,
        x.entryTerm, TraceValue(x.value), TraceValue(x.ctx), x.reject)

\* Observable projection of a model message (drops the ghost tag).
Observable(m) == [m EXCEPT !.rinc = 0]

\* In-flight model messages that match the traced message exactly.
BagMatches(x) == {m \in messages : Observable(m) = TraceMsg(x)}

SeqToSet(s) == {s[k] : k \in 1..Len(s)}

ReadStateView(seq) ==
    [k \in 1..Len(seq) |-> [index |-> seq[k].index, ctx |-> seq[k].ctx]]

TraceReadStates(s) ==
    [k \in 1..Len(s.readStates) |->
        [index |-> s.readStates[k].index, ctx |-> s.readStates[k].ctx]]

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
    \* UPDATE: exact pending key set (read_only.go:52-58, 100-105)
    /\ {c \in ReadContexts : pendingReads'[i][c].active} =
         SeqToSet(s.pendingCtxs)

ValidatePost(i, s) ==
    /\ ValidateCorePost(i, s)
    /\ Len(producedReads'[i]) = s.readCount
    /\ ReadStateView(producedReads'[i]) = TraceReadStates(s)
    /\ s.readyReadCount = 0

ConsumeStandard(action, i, s) ==
    /\ action
    /\ ValidatePost(i, s)
    /\ traceLine' = traceLine + 1

ConsumeBag(e, i, s, Act(_, _)) ==
    /\ \E m \in BagMatches(e.msg) : Act(i, m)
    /\ ValidatePost(i, s)
    /\ traceLine' = traceLine + 1

ConsumeReady(i, s) ==
    /\ Len(producedReads[i]) = s.readCount
    /\ s.readyReadCount = Len(producedReads[i])
    /\ ReadStateView(producedReads[i]) = TraceReadStates(s)
    /\ ReadyPublish(i)
    /\ ValidateCorePost(i, s)
    /\ Len(producedReads'[i]) = 0
    /\ traceLine' = traceLine + 1

ConsumeForward(e, i, s) ==
    /\ ForwardReadIndex(i, TraceValue(e.msg.ctx))
    /\ e.msg.to = leader[i]
    /\ TraceMsg(e.msg) \in {Observable(m) : m \in messages'}
    /\ ValidatePost(i, s)
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
              ConsumeBag(e, i, s, HandleHeartbeat)
         [] e.name = "ClientReadIndex" ->
              ConsumeStandard(ClientReadIndex(i, e.msg.ctx, e.msg.from), i, s)
         [] e.name = "ForwardReadIndex" ->
              ConsumeForward(e, i, s)
         [] e.name = "HandleReadIndexRequest" ->
              ConsumeBag(e, i, s, HandleReadIndexRequest)
         [] e.name = "HandleHeartbeatResponse" ->
              ConsumeBag(e, i, s, HandleHeartbeatResponse)
         [] e.name = "HandleReadIndexResponse" ->
              ConsumeBag(e, i, s, HandleReadIndexResponse)
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

TraceCanProgress ==
    traceLine <= Len(TraceLog) => ENABLED TraceNext

TraceMatched == <>(traceLine = Len(TraceLog) + 1)

TraceTypeOK ==
    /\ TypeOK
    /\ traceLine \in 1..(Len(TraceLog) + 1)

=============================================================================
