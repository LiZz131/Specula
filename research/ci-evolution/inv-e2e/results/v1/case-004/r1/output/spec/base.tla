---- MODULE base ----
(***************************************************************************)
(* Openraft Engine/RaftCore consensus model for the updated source          *)
(* revision `update` d7176ef916c7d2e3f2a0eed612875d7ce3e646b1, which adds  *)
(* RaftMsg::TransferLeader.  The exact-old V0 model is kept verbatim in    *)
(* spec/prior-snapshot/base.tla.  Every logic block cites the source.      *)
(*                                                                         *)
(* Structure                                                               *)
(*  - Handler actions (StartElection, HandleTransferLeader,                *)
(*    ReceiveVoteRequest, ...) are the synchronous Engine/RaftCore steps.  *)
(*    They take message contents as parameters and frame only node state, *)
(*    so Trace.tla can replay them with contents taken from real traces.  *)
(*  - The closed-world network (Do* wrappers, Next) links every handler   *)
(*    input to a message actually produced by another node.  Messages may *)
(*    be delayed, reordered, duplicated or dropped but are never forged.  *)
(***************************************************************************)

EXTENDS Integers, Sequences, FiniteSets, TLC

CONSTANTS Server, NoNode, InitialVoters, MaxTerm, MaxIndex

ASSUME Server # {}
ASSUME NoNode \notin Server
ASSUME InitialVoters \subseteq Server
ASSUME InitialVoters # {}
ASSUME MaxTerm \in Nat \ {0}
ASSUME MaxIndex \in Nat \ {0}

Roles == {"Learner", "Follower", "Candidate", "Leader"}
EntryKinds == {"blank", "data", "learner", "joint", "uniform"}
MembershipKinds == {"learner", "joint", "uniform"}
CommandKinds == {"SaveVote", "SendVote", "AppendInputEntries", "Replicate",
                 "RebuildReplicationStreams", "ReplicateCommitted",
                 "SaveCommitted", "Apply", "Respond"}

VARIABLES
    up,
    voteTerm, voteNode, voteCommitted,
    lastSeenTerm, lastSeenNode, lastSeenCommitted,
    role,
    logs, commitIndex,
    acceptedIndex, submittedIndex, flushedIndex, appliedIndex,
    durableLogs, durableCommit,
    durableVoteTerm, durableVoteNode, durableVoteCommitted,
    effectiveIndex, committedMembershipIndex, configs, committedConfigs, learners,
    candidate, candidateTerm, candidateNode, candidateConfigs, candidateLast, granters,
    leader, leaderConfigs, leaderGrants,
    match,
    pendingVoteSave, pendingVoteSend,
    commands,
    staleResponseSeen,
    \* History flag: RaftCore task panicked (Fatal::Panicked, raft_inner.rs:205-214).
    corePanic,
    \* Closed-world network (repair R2/R4, see analysis-report.md).
    voteReqs, voteResps, appendResps

voteVars == <<voteTerm, voteNode, voteCommitted,
              lastSeenTerm, lastSeenNode, lastSeenCommitted,
              durableVoteTerm, durableVoteNode, durableVoteCommitted,
              pendingVoteSave, pendingVoteSend>>
logVars == <<logs, commitIndex, acceptedIndex, submittedIndex, flushedIndex,
             appliedIndex, durableLogs, durableCommit>>
membershipVars == <<effectiveIndex, committedMembershipIndex, configs,
                    committedConfigs, learners>>
electionVars == <<role, candidate, candidateTerm, candidateNode,
                  candidateConfigs, candidateLast, granters, leader,
                  leaderConfigs, leaderGrants>>
netVars == <<voteReqs, voteResps, appendResps>>
nodeVars == <<up, voteVars, logVars, membershipVars, electionVars,
              match, commands, staleResponseSeen, corePanic>>
allVars == <<nodeVars, netVars>>

(***************************************************************************)
(* Helpers. Vote order is exact default-feature LeaderId then committed.   *)
(* Source: vote/vote.rs:21-41; vote/leader_id/leader_id_adv.rs:14-22.       *)
(***************************************************************************)

BoolToInt(b) == IF b THEN 1 ELSE 0

VoteLE(t1, n1, c1, t2, n2, c2) ==
    \/ t1 < t2
    \/ /\ t1 = t2
       /\ (n1 < n2 \/ /\ n1 = n2 /\ BoolToInt(c1) <= BoolToInt(c2))

VoteLT(t1, n1, c1, t2, n2, c2) ==
    VoteLE(t1, n1, c1, t2, n2, c2)
    /\ \/ t1 # t2 \/ n1 # n2 \/ c1 # c2

\* LogId derives Ord over (leader_id(term,node_id), index).
\* Source: log_id/mod.rs:22-31; vote/leader_id/leader_id_adv.rs:14-16,68.
LogIdLE(t1, n1, i1, t2, n2, i2) ==
    \/ t1 < t2
    \/ /\ t1 = t2 /\ n1 < n2
    \/ /\ t1 = t2 /\ n1 = n2 /\ i1 <= i2

StrictMajority(voters, ids) ==
    2 * Cardinality(voters \cap ids) > Cardinality(voters)

Quorum(cfg, ids) ==
    /\ cfg # {}
    /\ \A child \in cfg : child # {} /\ StrictMajority(child, ids)

Voters(cfg) == UNION cfg
IsVoter(n, id) == id \in Voters(configs[n])
\* MembershipState::contains: voter or learner of the effective config.
\* Source: raft_state/membership_state/mod.rs:73-75.
IsMember(n, id) == id \in Voters(configs[n]) \cup learners[n]

MaxElem(s) == CHOOSE x \in s : \A y \in s : x >= y
Min2(a, b) == IF a <= b THEN a ELSE b
LastIndex(n) == Len(logs[n]) - 1

InitEntry == [term |-> 0, node |-> NoNode, kind |-> "uniform",
              cfg |-> {InitialVoters}, learners |-> Server \ InitialVoters]

NewEntry(t, n, k, cfg, lrn) ==
    [term |-> t, node |-> n, kind |-> k, cfg |-> cfg, learners |-> lrn]

EntryAt(n, i) == logs[n][i + 1]
LastTerm(n) == EntryAt(n, LastIndex(n)).term
LastNode(n) == EntryAt(n, LastIndex(n)).node
LastLogId(n) == [term |-> LastTerm(n), node |-> LastNode(n), index |-> LastIndex(n)]
NoLogId == [term |-> 0, node |-> NoNode, index |-> 0]

MembershipPositions(s) ==
    {i \in 1..Len(s) : s[i].kind \in MembershipKinds}

EffectiveEntry(s) ==
    LET ps == MembershipPositions(s)
    IN  s[MaxElem(ps)]

ValidConfigs(cfg) ==
    /\ cfg \subseteq SUBSET Server
    /\ cfg # {}
    /\ \A child \in cfg : child # {}

OtherMembers(n, cfg, lrn) == (Voters(cfg) \cup lrn) \ {n}

HasRemote(n, cfg, lrn) == OtherMembers(n, cfg, lrn) # {}

LeaderAppendCommands(n, kind, cfg, lrn) ==
    {"AppendInputEntries"}
    \cup (IF kind \in MembershipKinds
          THEN {"RebuildReplicationStreams"} ELSE {})
    \cup (IF HasRemote(n, cfg, lrn) THEN {"Replicate"} ELSE {})

LeaderEstablishedCommands(n) ==
    {"RebuildReplicationStreams", "SaveVote", "AppendInputEntries"}
    \cup (IF HasRemote(n, configs[n], learners[n]) THEN {"Replicate"} ELSE {})

IdsMatchingAfter(n, peer, idx, at) ==
    {id \in Voters(configs[n]) :
        IF id = peer THEN idx >= at
        ELSE match[n][id] >= at}

GrantedAfter(n, peer, idx) ==
    {i \in (commitIndex[n] + 1)..LastIndex(n) :
        Quorum(configs[n], IdsMatchingAfter(n, peer, idx, i))}

NewCommitAfter(n, peer, idx) ==
    LET granted == GrantedAfter(n, peer, idx)
    IN IF granted = {} THEN commitIndex[n]
       ELSE LET g == MaxElem(granted)
            IN IF EntryAt(n, g).term = voteTerm[n]
                  /\ EntryAt(n, g).node = voteNode[n]
               THEN g ELSE commitIndex[n]

\* update_last_seen only raises last_seen_vote.
\* Source: engine/handler/vote_handler/mod.rs:96-111.
SeenTermAfter(n, t, o, c) ==
    IF VoteLE(lastSeenTerm[n], lastSeenNode[n], lastSeenCommitted[n], t, o, c)
    THEN t ELSE lastSeenTerm[n]
SeenNodeAfter(n, t, o, c) ==
    IF VoteLE(lastSeenTerm[n], lastSeenNode[n], lastSeenCommitted[n], t, o, c)
    THEN o ELSE lastSeenNode[n]
SeenCommittedAfter(n, t, o, c) ==
    IF VoteLE(lastSeenTerm[n], lastSeenNode[n], lastSeenCommitted[n], t, o, c)
    THEN c ELSE lastSeenCommitted[n]

Init ==
    /\ up = [n \in Server |-> TRUE]
    /\ voteTerm = [n \in Server |-> 0]
    /\ voteNode = [n \in Server |-> NoNode]
    /\ voteCommitted = [n \in Server |-> FALSE]
    /\ lastSeenTerm = voteTerm
    /\ lastSeenNode = voteNode
    /\ lastSeenCommitted = voteCommitted
    /\ durableVoteTerm = voteTerm
    /\ durableVoteNode = voteNode
    /\ durableVoteCommitted = voteCommitted
    /\ role = [n \in Server |-> IF n \in InitialVoters THEN "Follower" ELSE "Learner"]
    /\ logs = [n \in Server |-> <<InitEntry>>]
    /\ commitIndex = [n \in Server |-> 0]
    /\ acceptedIndex = [n \in Server |-> 0]
    /\ submittedIndex = [n \in Server |-> 0]
    /\ flushedIndex = [n \in Server |-> 0]
    /\ appliedIndex = [n \in Server |-> 0]
    /\ durableLogs = logs
    /\ durableCommit = commitIndex
    /\ effectiveIndex = [n \in Server |-> 0]
    /\ committedMembershipIndex = [n \in Server |-> 0]
    /\ configs = [n \in Server |-> {InitialVoters}]
    /\ committedConfigs = configs
    /\ learners = [n \in Server |-> Server \ InitialVoters]
    /\ candidate = [n \in Server |-> FALSE]
    /\ candidateTerm = [n \in Server |-> 0]
    /\ candidateNode = [n \in Server |-> NoNode]
    /\ candidateConfigs = configs
    /\ candidateLast = [n \in Server |-> NoLogId]
    /\ granters = [n \in Server |-> {}]
    /\ leader = [n \in Server |-> FALSE]
    /\ leaderConfigs = configs
    /\ leaderGrants = [n \in Server |-> {}]
    /\ match = [n \in Server |-> [p \in Server |-> IF p = n THEN 0 ELSE -1]]
    /\ pendingVoteSave = [n \in Server |-> FALSE]
    /\ pendingVoteSend = [n \in Server |-> FALSE]
    /\ commands = [n \in Server |-> {}]
    /\ staleResponseSeen = FALSE
    /\ corePanic = [n \in Server |-> FALSE]
    /\ voteReqs = {}
    /\ voteResps = {}
    /\ appendResps = {}

(***************************************************************************)
(* Engine::elect.  Synchronously changes the shadow vote and emits SaveVote*)
(* then SendVote.  Candidate quorum/learners/last_log_id are snapshotted.  *)
(* Engine::elect has NO membership guard: the candidate survives only if   *)
(* the node is a member (voter or learner) of its effective config,        *)
(* otherwise update_vote -> become_following drops candidate and leader.   *)
(* Source: engine/engine_impl.rs:126-141,223-249;                          *)
(*         vote_handler/mod.rs:124-163,166-175,241-252;                    *)
(*         raft_state/mod.rs:332-356,369-385.                              *)
(* UPDATE-MAP                                                              *)
(* code: core/raft_core.rs:1190-1202 (new caller without is_voter)        *)
(* update: Update!AffectedActions, Update!ElectionInitiatorIsVoter         *)
(***************************************************************************)

Elect(n) ==
    /\ up[n]
    /\ lastSeenTerm[n] < MaxTerm
    /\ LET t == lastSeenTerm[n] + 1
           keep == IsMember(n, n)
       IN
       /\ voteTerm' = [voteTerm EXCEPT ![n] = t]
       /\ voteNode' = [voteNode EXCEPT ![n] = n]
       /\ voteCommitted' = [voteCommitted EXCEPT ![n] = FALSE]
       /\ lastSeenTerm' = [lastSeenTerm EXCEPT ![n] = t]
       /\ lastSeenNode' = [lastSeenNode EXCEPT ![n] = n]
       /\ lastSeenCommitted' = [lastSeenCommitted EXCEPT ![n] = FALSE]
       /\ candidateTerm' = [candidateTerm EXCEPT ![n] = t]
       /\ candidateNode' = [candidateNode EXCEPT ![n] = n]
       /\ candidateConfigs' = [candidateConfigs EXCEPT ![n] = configs[n]]
       /\ candidateLast' = [candidateLast EXCEPT ![n] = LastLogId(n)]
       /\ granters' = [granters EXCEPT ![n] = {}]
       \* is_leading(id) requires membership_state.contains(id): raft_state/mod.rs:369-371
       /\ candidate' = [candidate EXCEPT ![n] = keep]
       /\ role' = [role EXCEPT ![n] = IF keep THEN "Candidate" ELSE "Learner"]
       \* become_following clears the leader: vote_handler/mod.rs:241-252
       /\ leader' = [leader EXCEPT ![n] = IF keep THEN @ ELSE FALSE]
    /\ pendingVoteSave' = [pendingVoteSave EXCEPT ![n] = TRUE]
    /\ pendingVoteSend' = [pendingVoteSend EXCEPT ![n] = TRUE]
    /\ commands' = [commands EXCEPT ![n] = {"SaveVote", "SendVote"}]
    /\ UNCHANGED <<up, logVars, membershipVars, leaderConfigs,
                    leaderGrants, match, durableVoteTerm, durableVoteNode,
                    durableVoteCommitted, staleResponseSeen, corePanic>>

(***************************************************************************)
(* Pre-existing election triggers: tick election and                       *)
(* ExternalCommand::Elect both require the node to be an effective voter.  *)
(* Source: core/raft_core.rs:1449-1457 (tick: not leader, is_voter),       *)
(*         core/raft_core.rs:1206-1214 (ExternalCommand::Elect: is_voter). *)
(***************************************************************************)

StartElection(n) ==
    /\ IsVoter(n, n)
    /\ Elect(n)

(***************************************************************************)
(* NEW: RaftMsg::TransferLeader{from,to} handled in RaftCore::handle_api_msg*)
(* If the local (in-memory) vote equals `from`: disable the vote lease     *)
(* (lease is abstract here, so this is a no-op on modeled state) and, if   *)
(* this node is `to`, call Engine::elect() with no further guard.          *)
(* Otherwise the message is ignored.  The step is atomic in the RaftCore   *)
(* event loop; emitted commands run afterwards (raft_core.rs:995-1001).    *)
(* Source: core/raft_core.rs:1190-1202; core/raft_msg/mod.rs:98-107;       *)
(*         utime.rs:133-138 (disable_lease).                               *)
(* UPDATE-MAP                                                              *)
(* code: core/raft_core.rs:1190-1202; raft/mod.rs:635-703                 *)
(* update: Update!AffectedActions (MCTransferLeader)                       *)
(***************************************************************************)

TransferFromMatches(n, fT, fN, fC) ==
    voteTerm[n] = fT /\ voteNode[n] = fN /\ voteCommitted[n] = fC

\* raft_core.rs:1197-1200: vote matches and self.id == to -> engine.elect()
TransferLeaderElect(n, fT, fN, fC, to) ==
    /\ to = n
    /\ TransferFromMatches(n, fT, fN, fC)
    /\ Elect(n)

\* raft_core.rs:1194-1197: vote matches, self.id != to -> disable_lease() only
TransferLeaderLeaseOnly(n, fT, fN, fC, to) ==
    /\ up[n]
    /\ to \in Server \ {n}
    /\ TransferFromMatches(n, fT, fN, fC)
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<up, voteVars, logVars, membershipVars, electionVars,
                    match, staleResponseSeen, corePanic>>

\* raft_core.rs:1194: vote does not match `from` -> message ignored
TransferLeaderIgnored(n, fT, fN, fC, to) ==
    /\ up[n]
    /\ to \in Server
    /\ ~TransferFromMatches(n, fT, fN, fC)
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<up, voteVars, logVars, membershipVars, electionVars,
                    match, staleResponseSeen, corePanic>>

HandleTransferLeader(n, fT, fN, fC, to) ==
    \/ TransferLeaderElect(n, fT, fN, fC, to)
    \/ TransferLeaderLeaseOnly(n, fT, fN, fC, to)
    \/ TransferLeaderIgnored(n, fT, fN, fC, to)

(***************************************************************************)
(* Runtime persistence is separate. Send becomes eligible only afterward. *)
(* Source: core/raft_core.rs:1670-1682; storage/v2.rs:62-67.                *)
(***************************************************************************)

PersistVote(n) ==
    /\ up[n]
    /\ pendingVoteSave[n]
    /\ durableVoteTerm' = [durableVoteTerm EXCEPT ![n] = voteTerm[n]]
    /\ durableVoteNode' = [durableVoteNode EXCEPT ![n] = voteNode[n]]
    /\ durableVoteCommitted' = [durableVoteCommitted EXCEPT ![n] = voteCommitted[n]]
    /\ pendingVoteSave' = [pendingVoteSave EXCEPT ![n] = FALSE]
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<up, voteTerm, voteNode, voteCommitted, lastSeenTerm,
                    lastSeenNode, lastSeenCommitted, pendingVoteSend,
                    logVars, membershipVars, electionVars, match,
                    staleResponseSeen, corePanic>>

SendVoteRequests(n) ==
    /\ up[n]
    /\ pendingVoteSend[n]
    /\ ~pendingVoteSave[n]
    /\ pendingVoteSend' = [pendingVoteSend EXCEPT ![n] = FALSE]
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<up, voteTerm, voteNode, voteCommitted, lastSeenTerm,
                    lastSeenNode, lastSeenCommitted, durableVoteTerm,
                    durableVoteNode, durableVoteCommitted, pendingVoteSave,
                    logVars, membershipVars, electionVars, match,
                    staleResponseSeen, corePanic>>

(***************************************************************************)
(* A fresh-enough request can grant only a nondecreasing vote; a strictly  *)
(* greater vote queues persistence.  Lease arithmetic is abstracted: a    *)
(* committed local vote may reject at any time (RejectVoteRequest).        *)
(* Freshness compares full LogId (repair R1).                              *)
(* Source: engine/engine_impl.rs:293-343; vote_handler/mod.rs:124-163.      *)
(***************************************************************************)

ReceiveVoteRequest(n, cand, t, c, lt, ln, li) ==
    /\ up[n]
    /\ cand \in Server
    /\ t <= MaxTerm
    \* engine_impl.rs:317: req.last_log_id >= self.state.last_log_id()
    /\ LogIdLE(LastTerm(n), LastNode(n), LastIndex(n), lt, ln, li)
    \* vote_handler/mod.rs:131-137: vote >= state.vote
    /\ VoteLE(voteTerm[n], voteNode[n], voteCommitted[n], t, cand, c)
    /\ LET needsSave == VoteLT(voteTerm[n], voteNode[n], voteCommitted[n], t, cand, c)
       IN
       /\ voteTerm' = [voteTerm EXCEPT ![n] = t]
       /\ voteNode' = [voteNode EXCEPT ![n] = cand]
       /\ voteCommitted' = [voteCommitted EXCEPT ![n] = c]
       /\ lastSeenTerm' = [lastSeenTerm EXCEPT ![n] = SeenTermAfter(n, t, cand, c)]
       /\ lastSeenNode' = [lastSeenNode EXCEPT ![n] = SeenNodeAfter(n, t, cand, c)]
       /\ lastSeenCommitted' = [lastSeenCommitted EXCEPT ![n] = SeenCommittedAfter(n, t, cand, c)]
       \* vote_handler/mod.rs:152-160: only a greater vote is saved
       /\ pendingVoteSave' = [pendingVoteSave EXCEPT ![n] = IF needsSave THEN TRUE ELSE @]
       /\ commands' = [commands EXCEPT ![n] = IF needsSave THEN {"SaveVote"} ELSE {}]
    /\ candidate' = [candidate EXCEPT ![n] = FALSE]
    /\ leader' = [leader EXCEPT ![n] = FALSE]
    /\ role' = [role EXCEPT ![n] = IF IsVoter(n,n) THEN "Follower" ELSE "Learner"]
    /\ UNCHANGED <<up, durableVoteTerm, durableVoteNode, durableVoteCommitted,
                    pendingVoteSend, logVars, membershipVars, candidateTerm,
                    candidateNode, candidateConfigs, candidateLast, granters,
                    leaderConfigs, leaderGrants, match, staleResponseSeen, corePanic>>

\* Rejection leaves state unchanged: lease (abstract), stale log, or lower vote.
\* Source: engine_impl.rs:305-314 (lease), :317-330 (log), vote_handler/mod.rs:131-137.
RejectVoteRequest(n, cand, t, c, lt, ln, li) ==
    /\ up[n]
    /\ cand \in Server
    /\ \/ voteCommitted[n]
       \/ ~LogIdLE(LastTerm(n), LastNode(n), LastIndex(n), lt, ln, li)
       \/ VoteLT(t, cand, c, voteTerm[n], voteNode[n], voteCommitted[n])
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<up, voteVars, logVars, membershipVars, electionVars,
                    match, staleResponseSeen, corePanic>>

(***************************************************************************)
(* Exact returned vote grants. Quorum establishment commits the vote and  *)
(* appends the current leader's blank entry.                               *)
(* Source: engine/engine_impl.rs:347-401,644-669; candidate.rs:90-116.      *)
(***************************************************************************)

ReceiveVoteResponse(n, peer, t, owner, c) ==
    /\ up[n]
    /\ peer \in Server
    /\ candidate[n]
    /\ t = candidateTerm[n]
    /\ owner = candidateNode[n]
    /\ ~c
    \* Candidate::grant_by updates progress over the candidate quorum set only
    \* (voters, no learners): proposer/candidate.rs:57-71,86-90; progress/mod.rs:216-230,320-331.
    /\ peer \in Voters(candidateConfigs[n])
    /\ LET gs == granters[n] \cup {peer}
           won == Quorum(candidateConfigs[n], gs)
           e == NewEntry(t, owner, "blank", configs[n], learners[n])
       IN
       /\ granters' = [granters EXCEPT ![n] = IF won THEN {} ELSE gs]
       /\ IF won
          THEN /\ candidate' = [candidate EXCEPT ![n] = FALSE]
               /\ leader' = [leader EXCEPT ![n] = TRUE]
               /\ role' = [role EXCEPT ![n] = "Leader"]
               /\ voteTerm' = [voteTerm EXCEPT ![n] = t]
               /\ voteNode' = [voteNode EXCEPT ![n] = owner]
               /\ voteCommitted' = [voteCommitted EXCEPT ![n] = TRUE]
               /\ lastSeenTerm' = [lastSeenTerm EXCEPT ![n] = t]
               /\ lastSeenNode' = [lastSeenNode EXCEPT ![n] = owner]
               /\ lastSeenCommitted' = [lastSeenCommitted EXCEPT ![n] = TRUE]
               /\ logs' = [logs EXCEPT ![n] = Append(@, e)]
               /\ acceptedIndex' = [acceptedIndex EXCEPT ![n] = LastIndex(n) + 1]
               /\ leaderConfigs' = [leaderConfigs EXCEPT ![n] = candidateConfigs[n]]
               /\ leaderGrants' = [leaderGrants EXCEPT ![n] = gs]
               \* Leader::new builds fresh progress: peers empty, self matching the
               \* candidate's elect-time last_log_id; the new blank is only accepted and
               \* self-match waits for LocalIO. Source: proposer/candidate.rs:105-116;
               \* proposer/leader.rs:112-128; core/raft_core.rs:1233-1269.
               \* (Repair: V0 kept stale peer progress from an earlier leadership.)
               /\ match' = [match EXCEPT ![n] = [p \in Server |->
                                IF p = n THEN candidateLast[n].index ELSE -1]]
               /\ pendingVoteSave' = [pendingVoteSave EXCEPT ![n] = TRUE]
               /\ commands' = [commands EXCEPT ![n] = LeaderEstablishedCommands(n)]
          ELSE /\ UNCHANGED <<candidate, leader, role, voteTerm, voteNode,
                               voteCommitted, lastSeenTerm, lastSeenNode,
                               lastSeenCommitted, logs, acceptedIndex,
                               leaderConfigs, leaderGrants, match, pendingVoteSave>>
               /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<up, pendingVoteSend, submittedIndex, flushedIndex,
                    appliedIndex, durableLogs, durableCommit, commitIndex,
                    durableVoteTerm, durableVoteNode, durableVoteCommitted,
                    membershipVars, candidateTerm, candidateNode,
                    candidateConfigs, candidateLast, staleResponseSeen, corePanic>>

\* A granting response from a node outside the candidate quorum set makes
\* `grant_by` hit `.expect("target not in quorum set")`: the RaftCore task
\* panics and Raft shuts down (Fatal::Panicked, error.rs:122-132).  Remote
\* requests only go to voters, so the trigger is the local self-grant that
\* SaveVote completion sends (raft_core.rs:1670-1682) when the candidate is
\* not a voter -- reachable only through the new TransferLeader path.
\* The panic loses all volatile state like a crash; corePanic records it.
\* UPDATE-MAP code: core/raft_core.rs:1197-1200 -> engine_impl.rs:374-376
\*            update: Update!NoCorePanic
CoreVoteResponsePanic(n, peer, t, owner, c) ==
    /\ up[n]
    /\ peer \in Server
    /\ candidate[n]
    /\ t = candidateTerm[n]
    /\ owner = candidateNode[n]
    /\ ~c
    /\ peer \notin Voters(candidateConfigs[n])
    /\ corePanic' = [corePanic EXCEPT ![n] = TRUE]
    /\ up' = [up EXCEPT ![n] = FALSE]
    /\ candidate' = [candidate EXCEPT ![n] = FALSE]
    /\ leader' = [leader EXCEPT ![n] = FALSE]
    /\ role' = [role EXCEPT ![n] = "Learner"]
    /\ granters' = [granters EXCEPT ![n] = {}]
    /\ pendingVoteSave' = [pendingVoteSave EXCEPT ![n] = FALSE]
    /\ pendingVoteSend' = [pendingVoteSend EXCEPT ![n] = FALSE]
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<voteTerm, voteNode, voteCommitted, lastSeenTerm,
                    lastSeenNode, lastSeenCommitted, durableVoteTerm,
                    durableVoteNode, durableVoteCommitted, logVars,
                    membershipVars, candidateTerm, candidateNode,
                    candidateConfigs, candidateLast, leaderConfigs,
                    leaderGrants, match, staleResponseSeen>>

\* A delivered response that does not grant the current candidate -- its vote
\* differs from the candidate's vote, or there is no candidate any more (e.g.
\* the leader's own committed-vote SaveVote self-response after establishment,
\* which passes does_vote_match, raft_core.rs:1524-1549) -- only raises
\* last_seen_vote (greater-log bookkeeping is not modeled).
\* Source: engine_impl.rs:347-401.  MC never produces such responses (they are
\* treated as dropped); this action replays real ones.
ReceiveVoteReject(n, peer, t, owner, c) ==
    /\ up[n]
    /\ peer \in Server
    /\ ~(candidate[n] /\ t = candidateTerm[n] /\ owner = candidateNode[n] /\ ~c)
    /\ lastSeenTerm' = [lastSeenTerm EXCEPT ![n] = SeenTermAfter(n, t, owner, c)]
    /\ lastSeenNode' = [lastSeenNode EXCEPT ![n] = SeenNodeAfter(n, t, owner, c)]
    /\ lastSeenCommitted' = [lastSeenCommitted EXCEPT ![n] = SeenCommittedAfter(n, t, owner, c)]
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<up, voteTerm, voteNode, voteCommitted, durableVoteTerm,
                    durableVoteNode, durableVoteCommitted, pendingVoteSave,
                    pendingVoteSend, logVars, membershipVars, electionVars,
                    match, staleResponseSeen, corePanic>>

(***************************************************************************)
(* Leader logical append, including immediate effective membership.        *)
(* Source: leader_handler/mod.rs:50-93; replication_handler/mod.rs:62-119. *)
(***************************************************************************)

CoherentMembership(kind, oldCfg, newCfg) ==
    \/ /\ kind = "learner" /\ newCfg = oldCfg
    \/ /\ kind = "joint" /\ Cardinality(newCfg) = 2
       /\ \E child \in oldCfg : child \in newCfg
    \/ /\ kind = "uniform" /\ Cardinality(newCfg) = 1
       /\ \E child \in newCfg : child \in oldCfg

LeaderAppend(n, kind, newCfg, newLearners) ==
    /\ up[n]
    /\ leader[n]
    /\ voteCommitted[n]
    /\ LastIndex(n) < MaxIndex
    /\ kind \in EntryKinds
    /\ ValidConfigs(newCfg)
    /\ newLearners \subseteq (Server \ Voters(newCfg))
    /\ IF kind \in MembershipKinds
       THEN /\ effectiveIndex[n] = committedMembershipIndex[n]
            /\ CoherentMembership(kind, configs[n], newCfg)
       ELSE /\ newCfg = configs[n] /\ newLearners = learners[n]
    /\ LET i == LastIndex(n) + 1
           e == NewEntry(voteTerm[n], n, kind, newCfg, newLearners)
       IN
       /\ logs' = [logs EXCEPT ![n] = Append(@, e)]
       /\ acceptedIndex' = [acceptedIndex EXCEPT ![n] = i]
       \* The Engine accepts the log here; leader self-match waits for LocalIO.
       /\ UNCHANGED match
       /\ effectiveIndex' = [effectiveIndex EXCEPT
                                ![n] = IF kind \in MembershipKinds
                                       THEN i ELSE @]
       /\ configs' = [configs EXCEPT
                        ![n] = IF kind \in MembershipKinds
                               THEN newCfg ELSE @]
       /\ learners' = [learners EXCEPT
                         ![n] = IF kind \in MembershipKinds
                                THEN newLearners ELSE @]
    /\ commands' = [commands EXCEPT ![n] = LeaderAppendCommands(n, kind, newCfg, newLearners)]
    /\ UNCHANGED <<up, voteVars, commitIndex, submittedIndex, flushedIndex,
                    appliedIndex, durableLogs, durableCommit,
                    committedMembershipIndex, committedConfigs,
                    electionVars, staleResponseSeen, corePanic>>

(***************************************************************************)
(* Follower/learner accepts the leader vote and a consecutive suffix of    *)
(* the leader's actual entries in one synchronous Engine call (repair R3). *)
(* Membership entries become effective at once: the last two membership   *)
(* entries are appended to MembershipState, whose `committed` becomes the  *)
(* previous effective.  The server state is recomputed with the new       *)
(* effective config.                                                       *)
(* Source: engine_impl.rs:445-461; following_handler/mod.rs:58-157,217-240;*)
(*         raft_state/membership_state/mod.rs:137-151;                      *)
(*         server_state_handler/mod.rs:20-46.                               *)
(***************************************************************************)

MembershipIdx(ents) == {i \in 1..Len(ents) : ents[i].kind \in MembershipKinds}

ReceiveAppend(n, owner, t, prev, ents) ==
    /\ up[n]
    /\ owner \in Server \ {n}
    /\ t <= MaxTerm
    /\ Len(ents) >= 1
    /\ prev = LastIndex(n)
    /\ prev + Len(ents) <= MaxIndex
    /\ VoteLE(voteTerm[n], voteNode[n], voteCommitted[n], t, owner, TRUE)
    /\ LET ms == MembershipIdx(ents)
           hasM == ms # {}
           lastM == IF hasM THEN MaxElem(ms) ELSE 0
           twoM == hasM /\ Cardinality(ms) >= 2
           prevM == IF twoM THEN MaxElem(ms \ {lastM}) ELSE 0
           newCfg == IF hasM THEN ents[lastM].cfg ELSE configs[n]
           newLrn == IF hasM THEN ents[lastM].learners ELSE learners[n]
           needsSave == VoteLT(voteTerm[n], voteNode[n], voteCommitted[n],
                               t, owner, TRUE)
       IN
       /\ voteTerm' = [voteTerm EXCEPT ![n] = t]
       /\ voteNode' = [voteNode EXCEPT ![n] = owner]
       /\ voteCommitted' = [voteCommitted EXCEPT ![n] = TRUE]
       /\ lastSeenTerm' = [lastSeenTerm EXCEPT ![n] = SeenTermAfter(n, t, owner, TRUE)]
       /\ lastSeenNode' = [lastSeenNode EXCEPT ![n] = SeenNodeAfter(n, t, owner, TRUE)]
       /\ lastSeenCommitted' = [lastSeenCommitted EXCEPT ![n] = SeenCommittedAfter(n, t, owner, TRUE)]
       /\ logs' = [logs EXCEPT ![n] = @ \o ents]
       /\ acceptedIndex' = [acceptedIndex EXCEPT ![n] = prev + Len(ents)]
       /\ effectiveIndex' = [effectiveIndex EXCEPT ![n] = IF hasM THEN prev + lastM ELSE @]
       /\ configs' = [configs EXCEPT ![n] = newCfg]
       /\ learners' = [learners EXCEPT ![n] = newLrn]
       /\ committedMembershipIndex' = [committedMembershipIndex EXCEPT
                ![n] = IF ~hasM THEN @
                       ELSE IF twoM THEN prev + prevM ELSE effectiveIndex[n]]
       /\ committedConfigs' = [committedConfigs EXCEPT
                ![n] = IF ~hasM THEN @
                       ELSE IF twoM THEN ents[prevM].cfg ELSE configs[n]]
       /\ role' = [role EXCEPT ![n] = IF n \in Voters(newCfg) THEN "Follower" ELSE "Learner"]
       /\ pendingVoteSave' = [pendingVoteSave EXCEPT
                                ![n] = IF needsSave THEN TRUE ELSE @]
       /\ commands' = [commands EXCEPT
                         ![n] = {"AppendInputEntries"}
                                \cup (IF needsSave THEN {"SaveVote"} ELSE {})]
    /\ candidate' = [candidate EXCEPT ![n] = FALSE]
    /\ leader' = [leader EXCEPT ![n] = FALSE]
    /\ UNCHANGED <<up, pendingVoteSend, durableVoteTerm, durableVoteNode,
                    durableVoteCommitted, commitIndex, submittedIndex,
                    flushedIndex, appliedIndex, durableLogs, durableCommit,
                    candidateTerm, candidateNode, candidateConfigs,
                    candidateLast, granters, leaderConfigs, leaderGrants,
                    match, staleResponseSeen, corePanic>>

(***************************************************************************)
(* Log submission, flush, follower response, durable commit, and apply are *)
(* distinct Runtime effects. Source: storage/v2.rs:93-105;                 *)
(* core/raft_core.rs:1633-1655,1718-1727.                                  *)
(***************************************************************************)

SubmitLog(n) ==
    /\ up[n]
    /\ submittedIndex[n] < acceptedIndex[n]
    /\ submittedIndex' = [submittedIndex EXCEPT ![n] = acceptedIndex[n]]
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<up, voteVars, logs, commitIndex, acceptedIndex,
                    flushedIndex, appliedIndex, durableLogs, durableCommit,
                    membershipVars, electionVars, match, staleResponseSeen, corePanic>>

FlushLog(n) ==
    /\ up[n]
    /\ flushedIndex[n] < submittedIndex[n]
    /\ flushedIndex' = [flushedIndex EXCEPT ![n] = submittedIndex[n]]
    /\ durableLogs' = [durableLogs EXCEPT ![n] = logs[n]]
    /\ match' = [match EXCEPT
                   ![n][n] = IF leader[n] THEN submittedIndex[n] ELSE @]
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<up, voteVars, logs, commitIndex, acceptedIndex,
                    submittedIndex, appliedIndex, durableCommit,
                    membershipVars, electionVars, staleResponseSeen, corePanic>>

SendAppendSuccess(n) ==
    /\ up[n]
    /\ flushedIndex[n] = acceptedIndex[n]
    /\ commands' = [commands EXCEPT ![n] = {"Respond"}]
    /\ UNCHANGED <<up, voteVars, logVars, membershipVars, electionVars,
                    match, staleResponseSeen, corePanic>>

(***************************************************************************)
(* A matching prefix update is session-valid here. Quorum uses only voter  *)
(* children; commit is restricted to the current leader's term/identity.   *)
(* Source: replication_handler/mod.rs:186-248; progress/mod.rs:127-135.    *)
(***************************************************************************)

AcknowledgeReplication(n, peer, idx) ==
    /\ up[n]
    /\ leader[n]
    /\ peer # n
    /\ peer \in (Voters(configs[n]) \cup learners[n])
    /\ idx \in match[n][peer]..LastIndex(n)
    /\ LET nc == NewCommitAfter(n, peer, idx) IN
       /\ match' = [match EXCEPT ![n][peer] = idx]
       /\ commitIndex' = [commitIndex EXCEPT ![n] = nc]
       /\ committedMembershipIndex' = [committedMembershipIndex EXCEPT
                                          ![n] = IF nc >= effectiveIndex[n]
                                                 THEN effectiveIndex[n] ELSE @]
       /\ committedConfigs' = [committedConfigs EXCEPT
                                 ![n] = IF nc >= effectiveIndex[n]
                                        THEN configs[n] ELSE @]
       /\ commands' = [commands EXCEPT
                         ![n] = IF nc > commitIndex[n]
                                THEN {"ReplicateCommitted", "SaveCommitted", "Apply"}
                                ELSE {}]
    /\ UNCHANGED <<up, voteVars, logs, acceptedIndex, submittedIndex,
                    flushedIndex, appliedIndex, durableLogs, durableCommit,
                    effectiveIndex, configs, learners, electionVars,
                    staleResponseSeen, corePanic>>

DropStaleResponse(n, peer, oldSession) ==
    /\ up[n]
    /\ leader[n]
    /\ peer \in Server
    /\ oldSession # effectiveIndex[n]
    /\ staleResponseSeen' = TRUE
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<up, voteVars, logVars, membershipVars, electionVars, match, corePanic>>

SaveCommit(n) ==
    /\ up[n]
    /\ durableCommit[n] < commitIndex[n]
    /\ durableCommit' = [durableCommit EXCEPT ![n] = commitIndex[n]]
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<up, voteVars, logs, commitIndex, acceptedIndex,
                    submittedIndex, flushedIndex, appliedIndex, durableLogs,
                    membershipVars, electionVars, match, staleResponseSeen, corePanic>>

ApplyCommitted(n) ==
    /\ up[n]
    /\ appliedIndex[n] < durableCommit[n]
    /\ appliedIndex' = [appliedIndex EXCEPT ![n] = durableCommit[n]]
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<up, voteVars, logs, commitIndex, acceptedIndex,
                    submittedIndex, flushedIndex, durableLogs, durableCommit,
                    membershipVars, electionVars, match, staleResponseSeen, corePanic>>

(***************************************************************************)
(* Crash loses volatile Engine/Core state. Restart reads only completed     *)
(* durable state and derives membership/role.  A recovered committed self- *)
(* vote restores leadership iff the node is a member (voter or learner) of *)
(* the recovered effective config (Engine::startup uses is_leader, which  *)
(* requires membership_state.contains; repair of V0, which ignored it).   *)
(* Source: storage/helper.rs:59-91,173-217; engine_impl.rs:151-180;         *)
(*         raft_state/mod.rs:369-385.                                       *)
(***************************************************************************)

Crash(n) ==
    /\ up[n]
    /\ up' = [up EXCEPT ![n] = FALSE]
    /\ candidate' = [candidate EXCEPT ![n] = FALSE]
    /\ leader' = [leader EXCEPT ![n] = FALSE]
    /\ role' = [role EXCEPT ![n] = "Learner"]
    /\ granters' = [granters EXCEPT ![n] = {}]
    /\ pendingVoteSave' = [pendingVoteSave EXCEPT ![n] = FALSE]
    /\ pendingVoteSend' = [pendingVoteSend EXCEPT ![n] = FALSE]
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<voteTerm, voteNode, voteCommitted, lastSeenTerm,
                    lastSeenNode, lastSeenCommitted, durableVoteTerm,
                    durableVoteNode, durableVoteCommitted, logVars,
                    membershipVars, candidateTerm, candidateNode,
                    candidateConfigs, candidateLast, leaderConfigs,
                    leaderGrants, match, staleResponseSeen, corePanic>>

Restart(n) ==
    /\ ~up[n]
    /\ LET ds == durableLogs[n]
           em == EffectiveEntry(ds)
           li == Len(ds) - 1
           cmPos == MaxElem({p \in MembershipPositions(ds) : p - 1 <= durableCommit[n]})
           member == n \in Voters(em.cfg) \cup em.learners
           selfLeader == durableVoteCommitted[n] /\ durableVoteNode[n] = n /\ member
       IN
       /\ up' = [up EXCEPT ![n] = TRUE]
       /\ voteTerm' = [voteTerm EXCEPT ![n] = durableVoteTerm[n]]
       /\ voteNode' = [voteNode EXCEPT ![n] = durableVoteNode[n]]
       /\ voteCommitted' = [voteCommitted EXCEPT ![n] = durableVoteCommitted[n]]
       /\ lastSeenTerm' = [lastSeenTerm EXCEPT ![n] = durableVoteTerm[n]]
       /\ lastSeenNode' = [lastSeenNode EXCEPT ![n] = durableVoteNode[n]]
       /\ lastSeenCommitted' = [lastSeenCommitted EXCEPT ![n] = durableVoteCommitted[n]]
       /\ logs' = [logs EXCEPT ![n] = ds]
       /\ acceptedIndex' = [acceptedIndex EXCEPT ![n] = li]
       /\ submittedIndex' = [submittedIndex EXCEPT ![n] = li]
       /\ flushedIndex' = [flushedIndex EXCEPT ![n] = li]
       /\ commitIndex' = [commitIndex EXCEPT ![n] = durableCommit[n]]
       /\ effectiveIndex' = [effectiveIndex EXCEPT ![n] = MaxElem(MembershipPositions(ds)) - 1]
       /\ committedMembershipIndex' = [committedMembershipIndex EXCEPT ![n] = cmPos - 1]
       /\ configs' = [configs EXCEPT ![n] = em.cfg]
       /\ committedConfigs' = [committedConfigs EXCEPT ![n] = ds[cmPos].cfg]
       /\ learners' = [learners EXCEPT ![n] = em.learners]
       /\ candidate' = [candidate EXCEPT ![n] = FALSE]
       /\ granters' = [granters EXCEPT ![n] = {}]
       /\ leader' = [leader EXCEPT ![n] = selfLeader]
       /\ role' = [role EXCEPT ![n] = IF selfLeader THEN "Leader"
                                           ELSE IF n \in Voters(em.cfg) THEN "Follower"
                                           ELSE "Learner"]
       /\ leaderConfigs' = [leaderConfigs EXCEPT ![n] = em.cfg]
       /\ leaderGrants' = [leaderGrants EXCEPT
                             ![n] = IF selfLeader THEN Voters(em.cfg) ELSE {}]
       /\ match' = [match EXCEPT
                      ![n] = [p \in Server |-> IF p = n THEN li ELSE -1]]
       /\ pendingVoteSave' = [pendingVoteSave EXCEPT ![n] = FALSE]
       /\ pendingVoteSend' = [pendingVoteSend EXCEPT ![n] = FALSE]
       /\ commands' = [commands EXCEPT
                         ![n] = IF selfLeader
                                THEN {"RebuildReplicationStreams"}
                                     \cup (IF HasRemote(n, em.cfg, em.learners)
                                           THEN {"Replicate"} ELSE {})
                                ELSE {}]
    /\ UNCHANGED <<appliedIndex, durableLogs, durableCommit,
                    durableVoteTerm, durableVoteNode, durableVoteCommitted,
                    candidateTerm, candidateNode, candidateConfigs,
                    candidateLast, staleResponseSeen, corePanic>>

(***************************************************************************)
(* Startup from a state already reconstructed by StorageHelper. This is    *)
(* the Engine::startup boundary used by trace validation.                  *)
(* Source: engine_impl.rs:151-166; vote_handler/mod.rs:166-239.            *)
(***************************************************************************)

RestartFromRecovered(n) ==
    /\ up[n]
    /\ voteCommitted[n]
    /\ voteNode[n] = n
    /\ IsMember(n, n)
    /\ leader' = [leader EXCEPT ![n] = TRUE]
    /\ candidate' = [candidate EXCEPT ![n] = FALSE]
    /\ role' = [role EXCEPT ![n] = "Leader"]
    /\ acceptedIndex' = [acceptedIndex EXCEPT ![n] = LastIndex(n)]
    /\ match' = [match EXCEPT ![n] = [p \in Server |-> IF p = n THEN LastIndex(n) ELSE -1]]
    /\ leaderConfigs' = [leaderConfigs EXCEPT ![n] = configs[n]]
    /\ leaderGrants' = [leaderGrants EXCEPT ![n] = Voters(configs[n])]
    /\ granters' = [granters EXCEPT ![n] = {}]
    /\ commands' = [commands EXCEPT
                      ![n] = {"RebuildReplicationStreams"}
                             \cup (IF HasRemote(n, configs[n], learners[n])
                                   THEN {"Replicate"} ELSE {})]
    /\ UNCHANGED <<up, voteVars, logs, commitIndex, submittedIndex,
                    flushedIndex, appliedIndex, durableLogs, durableCommit,
                    membershipVars, candidateTerm, candidateNode,
                    candidateConfigs, candidateLast, staleResponseSeen, corePanic>>

(***************************************************************************)
(* Closed-world network (repairs R2/R4).                                   *)
(* - SaveVote completion sends the local node its own vote response        *)
(*   (core/raft_core.rs:1670-1682); only an uncommitted self vote can pass *)
(*   does_vote_match (raft_core.rs:1524-1549), so only those are kept.     *)
(* - SendVote targets the effective voters at send time, excluding self,   *)
(*   and carries the elect-time vote and last_log_id                       *)
(*   (raft_core.rs:1049-1057, engine_impl.rs:238-246).                      *)
(* - A vote response carries the responder's vote after handling and is    *)
(*   released only after that vote is flushed (raft_core.rs:1110-1121).    *)
(* - AppendEntries carries the leader's actual entries to a member of the  *)
(*   leader's effective config; the prev log id must match                 *)
(*   (following_handler/mod.rs:107-128).                                   *)
(* - A successful append response is flush-gated (engine_impl.rs:425-439) *)
(*   and carries the accepted index and the leader vote it accepted.       *)
(* - Crash loses responses addressed to the crashed process.               *)
(***************************************************************************)

LeaderEntries(o, prev, c) == SubSeq(logs[o], prev + 2, prev + 1 + c)

DoStartElection(n) == StartElection(n) /\ UNCHANGED netVars

DoTransferLeader(n, fT, fN, fC, to) ==
    HandleTransferLeader(n, fT, fN, fC, to) /\ UNCHANGED netVars

DoPersistVote(n) ==
    /\ PersistVote(n)
    /\ voteResps' = IF voteNode[n] = n /\ ~voteCommitted[n]
                    THEN voteResps \cup {[src |-> n, dst |-> n, term |-> voteTerm[n],
                                          node |-> n, committed |-> FALSE]}
                    ELSE voteResps
    /\ UNCHANGED <<voteReqs, appendResps>>

DoSendVote(n) ==
    /\ SendVoteRequests(n)
    /\ voteReqs' = voteReqs \cup
          {[cand |-> n, term |-> candidateTerm[n],
            lt |-> candidateLast[n].term, ln |-> candidateLast[n].node,
            li |-> candidateLast[n].index,
            targets |-> Voters(configs[n]) \ {n}]}
    /\ UNCHANGED <<voteResps, appendResps>>

DoVoteRequest(n, m) ==
    /\ m \in voteReqs
    /\ n \in m.targets
    /\ ReceiveVoteRequest(n, m.cand, m.term, FALSE, m.lt, m.ln, m.li)
    /\ voteResps' = voteResps \cup {[src |-> n, dst |-> m.cand, term |-> m.term,
                                      node |-> m.cand, committed |-> FALSE]}
    /\ UNCHANGED <<voteReqs, appendResps>>

DoVoteResponse(n, r) ==
    /\ r \in voteResps
    /\ r.dst = n
    \* The local self-response is queued on the FIFO notification channel while
    \* SaveVote completes, before SendVote spawns any RPC (raft_core.rs:1670-1682,
    \* 1049-1100), so a candidate handles its own grant before any remote one.
    /\ (r.src # n => n \in granters[n])
    /\ VoteLE(r.term, r.node, r.committed,
              durableVoteTerm[r.src], durableVoteNode[r.src], durableVoteCommitted[r.src])
    /\ \/ /\ ReceiveVoteResponse(n, r.src, r.term, r.node, r.committed)
          /\ UNCHANGED netVars
       \/ /\ CoreVoteResponsePanic(n, r.src, r.term, r.node, r.committed)
          /\ appendResps' = {x \in appendResps : x.dst # n}
          /\ voteResps' = {x \in voteResps : x.dst # n}
          /\ UNCHANGED voteReqs

DoLeaderAppend(n, kind, cfg, lrn) == LeaderAppend(n, kind, cfg, lrn) /\ UNCHANGED netVars

DoAppend(n, o, c) ==
    /\ o # n
    /\ up[o]
    /\ leader[o] /\ voteCommitted[o] /\ voteNode[o] = o
    /\ IsMember(o, n)
    /\ c >= 1
    /\ LastIndex(n) + c <= LastIndex(o)
    /\ EntryAt(n, LastIndex(n)).term = EntryAt(o, LastIndex(n)).term
    /\ EntryAt(n, LastIndex(n)).node = EntryAt(o, LastIndex(n)).node
    /\ ReceiveAppend(n, o, voteTerm[o], LastIndex(n), LeaderEntries(o, LastIndex(n), c))
    /\ UNCHANGED netVars

DoRespond(n) ==
    /\ SendAppendSuccess(n)
    /\ voteCommitted[n]
    /\ voteNode[n] # n
    /\ voteNode[n] \in Server
    /\ appendResps' = appendResps \cup {[src |-> n, dst |-> voteNode[n],
                                          term |-> voteTerm[n], idx |-> acceptedIndex[n]]}
    /\ UNCHANGED <<voteReqs, voteResps>>

DoAck(n, r) ==
    /\ r \in appendResps
    /\ r.dst = n
    /\ r.term = voteTerm[n]
    /\ voteNode[n] = n
    /\ voteCommitted[n]
    /\ AcknowledgeReplication(n, r.src, r.idx)
    /\ UNCHANGED netVars

DoCrash(n) ==
    /\ Crash(n)
    /\ appendResps' = {r \in appendResps : r.dst # n}
    /\ voteResps' = {r \in voteResps : r.dst # n}
    /\ UNCHANGED voteReqs

NoNet(A) == A /\ UNCHANGED netVars

Next ==
    \/ \E n \in Server : DoStartElection(n)
    \* `from` is the vote of a leader known to the cluster (raft_msg/mod.rs:103-104)
    \/ \E n, to, x \in Server :
          /\ voteCommitted[x]
          /\ DoTransferLeader(n, voteTerm[x], voteNode[x], TRUE, to)
    \/ \E n \in Server : DoPersistVote(n) \/ DoSendVote(n)
    \/ \E n \in Server, m \in voteReqs : DoVoteRequest(n, m)
    \/ \E n \in Server, r \in voteResps : DoVoteResponse(n, r)
    \/ \E n \in Server, kind \in EntryKinds,
          cfg \in SUBSET (SUBSET Server), lrn \in SUBSET Server :
          DoLeaderAppend(n, kind, cfg, lrn)
    \/ \E n, o \in Server, c \in 1..MaxIndex : DoAppend(n, o, c)
    \/ \E n \in Server : NoNet(SubmitLog(n)) \/ NoNet(FlushLog(n)) \/ DoRespond(n)
    \/ \E n \in Server, r \in appendResps : DoAck(n, r)
    \/ \E n,peer \in Server, sess \in -1..MaxIndex :
          NoNet(DropStaleResponse(n,peer,sess))
    \/ \E n \in Server : NoNet(SaveCommit(n)) \/ NoNet(ApplyCommitted(n))
                          \/ DoCrash(n) \/ NoNet(Restart(n))

Spec == Init /\ [][Next]_allVars

(***************************************************************************)
(* Invariants.                                                             *)
(***************************************************************************)

LogIdRec == [term : 0..MaxTerm, node : Server \cup {NoNode}, index : 0..MaxIndex]

TypeOK ==
    /\ up \in [Server -> BOOLEAN]
    /\ voteTerm \in [Server -> 0..MaxTerm]
    /\ voteNode \in [Server -> (Server \cup {NoNode})]
    /\ voteCommitted \in [Server -> BOOLEAN]
    /\ lastSeenTerm \in [Server -> 0..MaxTerm]
    /\ lastSeenNode \in [Server -> (Server \cup {NoNode})]
    /\ lastSeenCommitted \in [Server -> BOOLEAN]
    /\ role \in [Server -> Roles]
    /\ candidate \in [Server -> BOOLEAN]
    /\ leader \in [Server -> BOOLEAN]
    /\ candidateLast \in [Server -> LogIdRec]
    /\ corePanic \in [Server -> BOOLEAN]
    /\ \A n \in Server :
         /\ ValidConfigs(configs[n])
         /\ learners[n] \subseteq Server \ Voters(configs[n])
         /\ commands[n] \subseteq CommandKinds
         /\ Len(logs[n]) \in 1..(MaxIndex + 1)
         /\ commitIndex[n] \in 0..LastIndex(n)
         /\ acceptedIndex[n] \in 0..LastIndex(n)
         /\ submittedIndex[n] \in 0..LastIndex(n)
         /\ flushedIndex[n] \in 0..LastIndex(n)
         /\ appliedIndex[n] \in 0..LastIndex(n)
         /\ effectiveIndex[n] \in 0..LastIndex(n)
         /\ committedMembershipIndex[n] \in 0..effectiveIndex[n]
         /\ \A p \in Server : match[n][p] \in -1..LastIndex(n)
    /\ \A m \in voteReqs : m.cand \in Server /\ m.targets \subseteq Server
    /\ \A r \in voteResps : r.src \in Server /\ r.dst \in Server
    /\ \A r \in appendResps : r.src \in Server /\ r.dst \in Server

IOOrder ==
    \A n \in Server :
      appliedIndex[n] <= durableCommit[n]
      /\ flushedIndex[n] <= submittedIndex[n]
      /\ submittedIndex[n] <= acceptedIndex[n]
      /\ acceptedIndex[n] <= LastIndex(n)

CommitWithinAccepted ==
    \A n \in Server : commitIndex[n] <= acceptedIndex[n]

MembershipOrder ==
    \A n \in Server : committedMembershipIndex[n] <= effectiveIndex[n]

MembershipWellFormed ==
    \A n \in Server : ValidConfigs(configs[n])

LearnersExcluded ==
    \A n \in Server : learners[n] \cap Voters(configs[n]) = {}

CandidateGrantSound ==
    \A n \in Server :
      role[n] = "Leader" => voteCommitted[n]
                            /\ voteNode[n] = n
                            /\ Quorum(leaderConfigs[n], leaderGrants[n])

LeaderVoteCommitted ==
    \A n \in Server : role[n] = "Leader" => leader[n] /\ voteCommitted[n]

MatchWithinLeaderLog ==
    \A n,p \in Server : match[n][p] <= LastIndex(n)

DurableStateBounded ==
    \A n \in Server :
       durableCommit[n] <= Len(durableLogs[n]) - 1
       /\ VoteLE(durableVoteTerm[n], durableVoteNode[n], durableVoteCommitted[n],
                 voteTerm[n], voteNode[n], voteCommitted[n])

CurrentTermCommit ==
    \A n \in Server :
      commitIndex[n] > 0 /\ leader[n]
      => EntryAt(n, commitIndex[n]).term <= voteTerm[n]

CommittedLogAgreement ==
    \A a,b \in Server :
      \A i \in 0..Min2(commitIndex[a], commitIndex[b]) :
        EntryAt(a,i).term = EntryAt(b,i).term /\ EntryAt(a,i).node = EntryAt(b,i).node

====
