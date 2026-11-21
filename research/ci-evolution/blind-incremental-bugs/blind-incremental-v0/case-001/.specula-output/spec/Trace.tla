------------------------------ MODULE Trace ------------------------------
\* Linear Category-A replay of NDJSON emitted by the exact-old Rust code.

EXTENDS base, Json, IOUtils, Sequences, TLC

JsonFile ==
    IF "JSON" \in DOMAIN IOEnv THEN IOEnv.JSON
    ELSE "../traces/initialization.ndjson"

TraceLog == TLCEval(
    LET all == ndJsonDeserialize(JsonFile)
    IN SelectSeq(all, LAMBDA x:
        /\ "tag" \in DOMAIN x
        /\ x.tag = "trace"
        /\ "event" \in DOMAIN x))

ASSUME Len(TraceLog) > 0

VARIABLE l
traceVars == <<l>>
logline == TraceLog[l]

FirstEvent == TraceLog[1].event
FirstNode == FirstEvent.nid
FirstBefore == FirstEvent.before

InitialGrantSet ==
    IF FirstBefore.grants = 0 THEN {}
    ELSE CHOOSE S \in SUBSET Nodes:
        /\ Cardinality(S) = FirstBefore.grants
        /\ (FirstEvent.name = "HandleVoteResponse" => FirstEvent.args.target \notin S)

TraceInit ==
    /\ FirstNode \in Nodes
    /\ FirstBefore.grants <= Cardinality(Nodes)
    /\ l = 1
    /\ term = [n \in Nodes |-> IF n = FirstNode THEN FirstBefore.term ELSE 0]
    /\ voteNode = [n \in Nodes |-> IF n = FirstNode THEN FirstBefore.voteNode ELSE Nil]
    /\ voteCommitted = [n \in Nodes |-> IF n = FirstNode THEN FirstBefore.voteCommitted ELSE FALSE]
    /\ role = [n \in Nodes |-> IF n = FirstNode THEN FirstBefore.role ELSE "Learner"]
    /\ logLen = [n \in Nodes |-> IF n = FirstNode THEN FirstBefore.logLen ELSE 0]
    /\ commitLen = [n \in Nodes |-> IF n = FirstNode THEN FirstBefore.commitLen ELSE 0]
    /\ candidate = [n \in Nodes |-> IF n = FirstNode THEN FirstBefore.candidate ELSE FALSE]
    /\ grantSet = [n \in Nodes |-> IF n = FirstNode THEN InitialGrantSet ELSE {}]
    /\ voters = [n \in Nodes |-> IF n = FirstNode THEN FirstBefore.voters ELSE 0]
    /\ selfVoter = [n \in Nodes |-> IF n = FirstNode THEN FirstBefore.selfVoter ELSE FALSE]
    /\ ioAccepted = [n \in Nodes |-> IF n = FirstNode THEN FirstBefore.ioAccepted ELSE 0]
    /\ ioSubmitted = [n \in Nodes |-> IF n = FirstNode THEN FirstBefore.ioSubmitted ELSE 0]
    /\ ioFlushed = [n \in Nodes |-> IF n = FirstNode THEN FirstBefore.ioFlushed ELSE 0]
    /\ ioAcceptedTerm = [n \in Nodes |-> IF n = FirstNode THEN FirstBefore.ioAcceptedTerm ELSE 0]
    /\ ioSubmittedTerm = [n \in Nodes |-> IF n = FirstNode THEN FirstBefore.ioSubmittedTerm ELSE 0]
    /\ ioFlushedTerm = [n \in Nodes |-> IF n = FirstNode THEN FirstBefore.ioFlushedTerm ELSE 0]
    /\ matchLen = [i \in Nodes |-> [j \in Nodes |-> 0]]
    /\ messages = {}
    /\ alive = [n \in Nodes |-> TRUE]

IsEvent(name) ==
    /\ l <= Len(TraceLog)
    /\ logline.event.name = name

ValidatePostState(n) ==
    /\ term'[n] = logline.event.state.term
    /\ voteNode'[n] = logline.event.state.voteNode
    /\ voteCommitted'[n] = logline.event.state.voteCommitted
    /\ role'[n] = logline.event.state.role
    /\ logLen'[n] = logline.event.state.logLen
    /\ commitLen'[n] = logline.event.state.commitLen
    /\ candidate'[n] = logline.event.state.candidate
    /\ Cardinality(grantSet'[n]) = logline.event.state.grants
    /\ voters'[n] = logline.event.state.voters
    /\ selfVoter'[n] = logline.event.state.selfVoter
    /\ ioAccepted'[n] = logline.event.state.ioAccepted
    /\ ioSubmitted'[n] = logline.event.state.ioSubmitted
    /\ ioFlushed'[n] = logline.event.state.ioFlushed
    /\ ioAcceptedTerm'[n] = logline.event.state.ioAcceptedTerm
    /\ ioSubmittedTerm'[n] = logline.event.state.ioSubmittedTerm
    /\ ioFlushedTerm'[n] = logline.event.state.ioFlushedTerm

EngineInitializeLogged ==
    /\ IsEvent("EngineInitialize")
    /\ LET n == logline.event.nid
       IN /\ EngineInitialize(n, logline.event.state.voters)
          /\ ValidatePostState(n)
    /\ l' = l + 1

EngineElectLogged ==
    /\ IsEvent("EngineElect")
    /\ LET n == logline.event.nid
       IN /\ EngineElect(n)
          /\ ValidatePostState(n)
    /\ l' = l + 1

HandleVoteResponseLogged ==
    /\ IsEvent("HandleVoteResponse")
    /\ LET n == logline.event.nid
       IN /\ TraceHandleVoteResponse(n,
                   logline.event.args.target,
                   logline.event.args.granted)
          /\ ValidatePostState(n)
    /\ l' = l + 1

EngineAppendEntriesLogged ==
    /\ IsEvent("EngineAppendEntries")
    /\ LET n == logline.event.nid
       IN /\ TraceEngineAppendEntries(
                   n,
                   logline.event.args.incomingTerm,
                   logline.event.args.incomingNode,
                   logline.event.args.entryCount,
                   logline.event.args.prevLen,
                   logline.event.state.voters,
                   logline.event.state.selfVoter)
          /\ ValidatePostState(n)
    /\ l' = l + 1

IOAcceptLogged ==
    /\ IsEvent("IOAccept")
    /\ LET n == logline.event.nid
       IN /\ IOAccept(n, logline.event.state.ioAccepted)
          /\ ValidatePostState(n)
    /\ l' = l + 1

IOSubmitLogged ==
    /\ IsEvent("IOSubmit")
    /\ LET n == logline.event.nid
       IN /\ IOSubmit(n, logline.event.state.ioSubmitted)
          /\ ValidatePostState(n)
    /\ l' = l + 1

IOFlushLogged ==
    /\ IsEvent("IOFlush")
    /\ LET n == logline.event.nid
       IN /\ IOFlush(n, logline.event.state.ioFlushed)
          /\ ValidatePostState(n)
    /\ l' = l + 1

TraceNext ==
    \/ EngineInitializeLogged
    \/ EngineElectLogged
    \/ HandleVoteResponseLogged
    \/ EngineAppendEntriesLogged
    \/ IOAcceptLogged
    \/ IOSubmitLogged
    \/ IOFlushLogged
    \/ /\ l > Len(TraceLog)
       /\ UNCHANGED <<vars, l>>

TraceSpec == TraceInit /\ [][TraceNext]_<<vars, l>> /\ WF_<<vars, l>>(TraceNext)
TraceMatched == <>(l > Len(TraceLog))
TraceView == <<vars, l>>

TraceAlias ==
    [cursor |-> l,
     length |-> Len(TraceLog),
     event |-> IF l <= Len(TraceLog) THEN logline.event.name ELSE "DONE",
     term |-> term, role |-> role, logLen |-> logLen,
     commitLen |-> commitLen, ioAccepted |-> ioAccepted,
     ioSubmitted |-> ioSubmitted, ioFlushed |-> ioFlushed]

=============================================================================
