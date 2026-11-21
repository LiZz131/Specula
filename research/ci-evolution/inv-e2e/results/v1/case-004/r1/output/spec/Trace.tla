---- MODULE Trace ----
(***************************************************************************)
(* Replay real Engine/RaftCore traces of the updated implementation        *)
(* against the reference handler actions.  A file starts with `Bootstrap` *)
(* (captured pre-state of the traced node); each later line is the        *)
(* post-state after one real synchronous Engine/RaftCore step.  Message    *)
(* contents (vote requests/responses, append entries) are the arguments   *)
(* observed on the real path; the closed-world network variables are not   *)
(* used in replay and stay empty.                                          *)
(***************************************************************************)

EXTENDS base, Json, IOUtils, Sequences, FiniteSets, TLC

JsonFile ==
    IF "JSON" \in DOMAIN IOEnv THEN IOEnv.JSON
    ELSE "../traces/election.ndjson"

TraceLog == ndJsonDeserialize(JsonFile)

VARIABLE l
\* Observer of the real accepted IOId kind (trace-only mapping, not behaviour):
\* update_vote to a greater vote accepts IOId::new(vote), which carries no log id
\* (raft_state/mod.rs:224-247; raft_state/io_state/io_id.rs:69-77,93-98), so the
\* captured accepted log index is -1 until the next log IO is accepted.  The
\* model's acceptedIndex keeps the last accepted log index.
VARIABLE accVoteIO
traceVars == <<l, accVoteIO>>

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

\* Entries carried by a real AppendEntries request (FollowerAppend args).
EntryKindOf(e) ==
    IF e.kind = "membership"
    THEN IF Len(e.configs) > 1 THEN "joint" ELSE "uniform"
    ELSE IF e.kind = "blank" THEN "blank" ELSE "data"

EntriesOf(es) ==
    [i \in 1..Len(es) |->
       NewEntry(es[i].term, es[i].node, EntryKindOf(es[i]),
                ConfigsOf(es[i].configs), ToSet(es[i].learners))]

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

CandLastOf(st) ==
    [term |-> st.candidate_last_term, node |-> st.candidate_last_node,
     index |-> st.candidate_last_index]

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
       /\ candidateLast = [x \in Server |-> IF x=n /\ st.candidate THEN CandLastOf(st) ELSE NoLogId]
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
       /\ corePanic = [x \in Server |-> FALSE]
       /\ voteReqs = {}
       /\ voteResps = {}
       /\ appendResps = {}
    /\ accVoteIO = [x \in Server |-> TraceLog[1].event.state.accepted_index = -1]
    /\ l = 2

VoteChanged(n) ==
    \/ voteTerm'[n] # voteTerm[n] \/ voteNode'[n] # voteNode[n]
    \/ voteCommitted'[n] # voteCommitted[n]

(***************************************************************************)
(* Strong post-state validation: every field emitted by capture() is       *)
(* checked.  candidate_last_* is meaningful only while a candidate exists. *)
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
    /\ (st.candidate => candidateLast'[n] = CandLastOf(st))
    /\ granters'[n] = ToSet(st.granters)
    /\ leader'[n] = st.leader
    /\ MatchRecords(n) = CapturedMatchRecords(st)
    /\ IF accVoteIO'[n] THEN st.accepted_index = -1
       ELSE acceptedIndex'[n] = st.accepted_index
    /\ commands'[n] = ToSet(st.commands)

\* Engine::elect (no guard at the Engine boundary).
TraceElect ==
    /\ IsEvent("Elect")
    /\ LET n == Line.node IN
       /\ Elect(n)
       /\ accVoteIO' = [accVoteIO EXCEPT ![n] = TRUE]
       /\ ValidatePostState(n, Line.state)
    /\ UNCHANGED netVars
    /\ l' = l + 1

\* RaftCore::handle_api_msg(RaftMsg::TransferLeader) -- update action.
TraceTransferLeader ==
    /\ IsEvent("TransferLeader")
    /\ LET n == Line.node
           a == Line.args
       IN /\ HandleTransferLeader(n, a.from_term, a.from_node, a.from_committed, a.to)
          /\ accVoteIO' = [accVoteIO EXCEPT ![n] = IF VoteChanged(n) THEN TRUE ELSE @]
          /\ ValidatePostState(n, Line.state)
    /\ UNCHANGED netVars
    /\ l' = l + 1

TraceVoteResponse ==
    /\ IsEvent("VoteResponse")
    /\ LET n == Line.node
           a == Line.args
       IN /\ \/ ReceiveVoteResponse(n, a.peer, a.term, a.owner, a.committed)
                \/ ReceiveVoteReject(n, a.peer, a.term, a.owner, a.committed)
          /\ accVoteIO' = [accVoteIO EXCEPT ![n] = IF leader'[n] /\ ~leader[n] THEN FALSE ELSE @]
          /\ ValidatePostState(n, Line.state)
    /\ UNCHANGED netVars
    /\ l' = l + 1

\* RaftCore task panicked inside Engine::handle_vote_resp (grant_by .expect).
\* No post-state exists; the event carries the pre-state and the model must
\* predict exactly the panic transition for this response.
TraceVoteResponsePanic ==
    /\ IsEvent("VoteResponsePanic")
    /\ LET n == Line.node
           a == Line.args
       IN /\ CoreVoteResponsePanic(n, a.peer, a.term, a.owner, a.committed)
          /\ corePanic'[n]
          /\ ~up'[n]
          /\ UNCHANGED accVoteIO
    /\ UNCHANGED netVars
    /\ l' = l + 1

TraceVoteRequest ==
    /\ IsEvent("VoteRequest")
    /\ LET n == Line.node
           a == Line.args
       IN /\ \/ ReceiveVoteRequest(n, a.candidate, a.term, a.committed,
                                   a.last_term, a.last_node, a.last_index)
                \/ RejectVoteRequest(n, a.candidate, a.term, a.committed,
                                     a.last_term, a.last_node, a.last_index)
          /\ accVoteIO' = [accVoteIO EXCEPT ![n] = IF VoteChanged(n) THEN TRUE ELSE @]
          /\ ValidatePostState(n, Line.state)
    /\ UNCHANGED netVars
    /\ l' = l + 1

TraceFollowerAppend ==
    /\ IsEvent("FollowerAppend")
    /\ LET n == Line.node
           a == Line.args
       IN /\ ReceiveAppend(n, a.owner, a.term, a.prev, EntriesOf(a.entries))
          /\ accVoteIO' = [accVoteIO EXCEPT ![n] = FALSE]
          /\ ValidatePostState(n, Line.state)
    /\ UNCHANGED netVars
    /\ l' = l + 1

TraceLeaderAppend ==
    /\ IsEvent("LeaderAppend")
    /\ LET n == Line.node
           a == Line.args
       IN /\ LeaderAppend(n, a.kind, ConfigsOf(a.configs), ToSet(a.learners))
          /\ accVoteIO' = [accVoteIO EXCEPT ![n] = FALSE]
          /\ ValidatePostState(n, Line.state)
    /\ UNCHANGED netVars
    /\ l' = l + 1

TraceAckReplication ==
    /\ IsEvent("AckReplication")
    /\ LET n == Line.node
           a == Line.args
       IN /\ AcknowledgeReplication(n, a.peer, a.index)
          /\ UNCHANGED accVoteIO
          /\ ValidatePostState(n, Line.state)
    /\ UNCHANGED netVars
    /\ l' = l + 1

TraceStartup ==
    /\ IsEvent("Startup")
    /\ LET n == Line.node IN
       /\ RestartFromRecovered(n)
       /\ accVoteIO' = [accVoteIO EXCEPT ![n] = FALSE]
       /\ ValidatePostState(n, Line.state)
    /\ UNCHANGED netVars
    /\ l' = l + 1

TraceNext ==
    /\ l <= Len(TraceLog)
    /\ TraceLog[l].tag = "trace"
    /\ \/ TraceElect
       \/ TraceTransferLeader
       \/ TraceVoteResponse
       \/ TraceVoteResponsePanic
       \/ TraceVoteRequest
       \/ TraceFollowerAppend
       \/ TraceLeaderAppend
       \/ TraceAckReplication
       \/ TraceStartup

TraceSpec ==
    TraceInit
    /\ [][TraceNext]_<<allVars,traceVars>>
    /\ WF_<<allVars,traceVars>>(TraceNext)

TraceMatched == <>(l > Len(TraceLog))

====
