---- MODULE Trace ----
(***************************************************************************)
(* Replay real exact-old Engine traces against base actions.               *)
(***************************************************************************)

EXTENDS base, Json, IOUtils, Sequences, FiniteSets, TLC

JsonFile ==
    IF "JSON" \in DOMAIN IOEnv THEN IOEnv.JSON
    ELSE "../traces/election.ndjson"

TraceLog == ndJsonDeserialize(JsonFile)

VARIABLE l
traceVars == <<l>>

Line == TraceLog[l].event
IsEvent(name) == l <= Len(TraceLog) /\ Line.name = name

ToSet(seq) == {seq[i] : i \in 1..Len(seq)}
ConfigsOf(seq) == {ToSet(seq[i]) : i \in 1..Len(seq)}

TraceKind(st, i) ==
    IF st.logs[i].index = st.effective_index
    THEN IF Len(st.effective_configs) > 1 THEN "joint"
         ELSE IF Len(st.learners) > 0 THEN "learner" ELSE "uniform"
    ELSE "data"

LogsOf(st) ==
    [i \in 1..Len(st.logs) |->
       NewEntry(st.logs[i].term, st.logs[i].node, TraceKind(st,i),
                ConfigsOf(st.effective_configs), ToSet(st.learners))]

LogIdsOf(seq) ==
    [i \in 1..Len(seq) |->
       [term |-> seq[i].term, node |-> seq[i].node, index |-> i - 1]]

MatchIndexOf(st, peer) ==
    IF \E i \in 1..Len(st.matches) : st.matches[i].peer = peer
    THEN (CHOOSE x \in {st.matches[i] : i \in 1..Len(st.matches)} : x.peer = peer).index
    ELSE -1

MatchFunctionOf(st) == [peer \in Server |-> MatchIndexOf(st,peer)]

MatchRecords(n) ==
    IF leader'[n]
    THEN {[peer |-> p, index |-> match'[n][p]] :
             p \in (Voters(configs'[n]) \cup learners'[n])}
    ELSE {}

CapturedMatchRecords(st) == ToSet(st.matches)

TraceInit ==
    /\ Len(TraceLog) >= 1
    /\ TraceLog[1].tag = "trace"
    /\ TraceLog[1].event.name = "Bootstrap"
    /\ LET st == TraceLog[1].event.state
           n == TraceLog[1].event.node
           cfg == ConfigsOf(st.effective_configs)
           lrn == ToSet(st.learners)
           ls == LogsOf(st)
       IN
       /\ n \in Server
       /\ up = [x \in Server |-> TRUE]
       /\ voteTerm = [x \in Server |-> IF x=n THEN st.vote_term ELSE 0]
       /\ voteNode = [x \in Server |-> IF x=n THEN st.vote_node ELSE NoNode]
       /\ voteCommitted = [x \in Server |-> IF x=n THEN st.vote_committed ELSE FALSE]
       /\ lastSeenTerm = [x \in Server |-> IF x=n THEN st.last_seen_term ELSE 0]
       /\ lastSeenNode = [x \in Server |-> IF x=n THEN st.last_seen_node ELSE NoNode]
       /\ lastSeenCommitted = [x \in Server |-> IF x=n THEN st.last_seen_committed ELSE FALSE]
       /\ durableVoteTerm = voteTerm
       /\ durableVoteNode = voteNode
       /\ durableVoteCommitted = voteCommitted
       /\ role = [x \in Server |-> IF x=n THEN st.role
                                  ELSE IF x \in InitialVoters THEN "Follower" ELSE "Learner"]
       /\ logs = [x \in Server |-> IF x=n THEN ls ELSE <<InitEntry>>]
       /\ commitIndex = [x \in Server |-> IF x=n THEN st.commit_index ELSE 0]
       /\ acceptedIndex = [x \in Server |-> IF x=n THEN st.accepted_index ELSE 0]
       /\ submittedIndex = acceptedIndex
       /\ flushedIndex = acceptedIndex
       /\ appliedIndex = commitIndex
       /\ durableLogs = logs
       /\ durableCommit = commitIndex
       /\ effectiveIndex = [x \in Server |-> IF x=n THEN st.effective_index ELSE 0]
       /\ committedMembershipIndex = [x \in Server |->
                                        IF x=n THEN st.committed_membership_index ELSE 0]
       /\ configs = [x \in Server |-> IF x=n THEN cfg ELSE {InitialVoters}]
       /\ committedConfigs = configs
       /\ learners = [x \in Server |-> IF x=n THEN lrn ELSE Server \ InitialVoters]
       /\ candidate = [x \in Server |-> x=n /\ st.candidate]
       /\ candidateTerm = [x \in Server |-> IF x=n /\ st.candidate THEN st.vote_term ELSE 0]
       /\ candidateNode = [x \in Server |-> IF x=n /\ st.candidate THEN st.vote_node ELSE NoNode]
       /\ candidateConfigs = configs
       /\ granters = [x \in Server |-> IF x=n THEN ToSet(st.granters) ELSE {}]
       /\ leader = [x \in Server |-> x=n /\ st.leader]
       /\ leaderConfigs = configs
       /\ leaderGrants = [x \in Server |-> IF x=n /\ st.leader THEN Voters(cfg) ELSE {}]
       /\ match = [x \in Server |-> IF x=n THEN MatchFunctionOf(st)
                                      ELSE [p \in Server |-> IF p=x THEN 0 ELSE -1]]
       /\ pendingVoteSave = [x \in Server |-> FALSE]
       /\ pendingVoteSend = [x \in Server |-> FALSE]
       /\ commands = [x \in Server |-> IF x=n THEN ToSet(st.commands) ELSE {}]
       /\ staleResponseSeen = FALSE
    /\ l = 2

(***************************************************************************)
(* Strong post-state validation: every field emitted by capture() is       *)
(* checked unconditionally. This is deliberately not a TRUE stub.          *)
(***************************************************************************)

ValidatePostState(n, st) ==
    /\ n = st.node_id
    /\ voteTerm'[n] = st.vote_term
    /\ voteNode'[n] = st.vote_node
    /\ voteCommitted'[n] = st.vote_committed
    /\ lastSeenTerm'[n] = st.last_seen_term
    /\ lastSeenNode'[n] = st.last_seen_node
    /\ lastSeenCommitted'[n] = st.last_seen_committed
    /\ role'[n] = st.role
    /\ LogIdsOf(logs'[n]) = st.logs
    /\ Len(logs'[n]) - 1 = st.last_index
    /\ commitIndex'[n] = st.commit_index
    /\ effectiveIndex'[n] = st.effective_index
    /\ committedMembershipIndex'[n] = st.committed_membership_index
    /\ configs'[n] = ConfigsOf(st.effective_configs)
    /\ learners'[n] = ToSet(st.learners)
    /\ candidate'[n] = st.candidate
    /\ granters'[n] = ToSet(st.granters)
    /\ leader'[n] = st.leader
    /\ MatchRecords(n) = CapturedMatchRecords(st)
    /\ acceptedIndex'[n] = st.accepted_index
    /\ commands'[n] = ToSet(st.commands)

TraceElect ==
    /\ IsEvent("Elect")
    /\ LET n == Line.node IN
       /\ StartElection(n)
       /\ ValidatePostState(n, Line.state)
    /\ l' = l + 1

TraceVoteResponse ==
    /\ IsEvent("VoteResponse")
    /\ LET n == Line.node
           a == Line.args
       IN /\ ReceiveVoteResponse(n, a.peer, a.term, a.owner, a.committed)
          /\ ValidatePostState(n, Line.state)
    /\ l' = l + 1

TraceVoteRequest ==
    /\ IsEvent("VoteRequest")
    /\ LET n == Line.node
           a == Line.args
       IN /\ ReceiveVoteRequest(n, a.candidate, a.term, a.committed, a.last_index)
          /\ ValidatePostState(n, Line.state)
    /\ l' = l + 1

TraceFollowerAppend ==
    /\ IsEvent("FollowerAppend")
    /\ LET n == Line.node
           a == Line.args
       IN /\ ReceiveAppendDirect(n, a.owner, a.term, a.prev, a.count)
          /\ ValidatePostState(n, Line.state)
    /\ l' = l + 1

TraceLeaderAppend ==
    /\ IsEvent("LeaderAppend")
    /\ LET n == Line.node
           a == Line.args
       IN /\ LeaderAppend(n, a.kind, ConfigsOf(a.configs), ToSet(a.learners))
          /\ ValidatePostState(n, Line.state)
    /\ l' = l + 1

TraceAckReplication ==
    /\ IsEvent("AckReplication")
    /\ LET n == Line.node
           a == Line.args
       IN /\ AcknowledgeReplication(n, a.peer, a.index)
          /\ ValidatePostState(n, Line.state)
    /\ l' = l + 1

TraceStartup ==
    /\ IsEvent("Startup")
    /\ LET n == Line.node IN
       /\ RestartFromRecovered(n)
       /\ ValidatePostState(n, Line.state)
    /\ l' = l + 1

TraceNext ==
    /\ l <= Len(TraceLog)
    /\ TraceLog[l].tag = "trace"
    /\ \/ TraceElect
       \/ TraceVoteResponse
       \/ TraceVoteRequest
       \/ TraceFollowerAppend
       \/ TraceLeaderAppend
       \/ TraceAckReplication
       \/ TraceStartup

TraceSpec ==
    TraceInit
    /\ [][TraceNext]_<<allVars,traceVars>>
    /\ WF_<<allVars,traceVars>>(TraceNext)

\* REQ-EVIDENCE TraceMatched
\* intent:   Trace replay eventually consumes every line of the recorded Engine trace, i.e. trace validation runs to completion.
\* status:   model-internal
\* watch:    none in source/ (the trace capture code and the traces/ directory are not part of /work)
\* verified: base
\* note:     trace-validation completeness check; no requirement evidence was sought. Searched source/ for "ndjson" and "TraceLog": no trace emitter found.
\* review:   ok
TraceMatched == <>(l > Len(TraceLog))

====
