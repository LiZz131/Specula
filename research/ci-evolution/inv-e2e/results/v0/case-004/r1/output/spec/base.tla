---- MODULE base ----
(***************************************************************************)
(* Openraft Engine/RaftCore consensus model, updated for the source        *)
(* revision `update` (artifact commit d7176ef) on top of the V0 prior      *)
(* `baseline` (d86101c).  Every logic block cites the source that defines  *)
(* the modeled behavior (paths relative to the openraft crate root         *)
(* `openraft/src/`).                                                       *)
(*                                                                         *)
(* Incremental update (UPDATE-MAP comments mark every changed location):   *)
(*  - RaftMsg::TransferLeader handler (core/raft_core.rs:1190-1202):       *)
(*    vote-match guard, Leased::disable_lease, and Engine::elect for `to`  *)
(*    without the voter/leader guards used by the other elect() callers.   *)
(*  - Leased::lease_enabled (utime.rs:17,127-161): update() re-enables,    *)
(*    touch() keeps a disabled lease at zero.                              *)
(* Model repairs required to check the update's interactions (see          *)
(* spec/changelog.md, "Generation repairs"):                               *)
(*  - R1 vote exchange: requests carry the real candidate vote/last log id *)
(*    and grants are produced only by an accepting voter;                  *)
(*  - R2 replication linkage (MC layer + general ReceiveAppend);           *)
(*  - R3 Candidate::grant_by panics for a non-quorum target;               *)
(*  - R4 restart/startup leadership requires membership containment;       *)
(*  - R5 handle_vote_req saves only a strictly greater vote and updates    *)
(*    last_seen_vote monotonically.                                        *)
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
                 "SaveCommitted", "Apply", "Respond", "UpdateIOProgress"}

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
    candidate, candidateTerm, candidateNode, candidateConfigs, granters,
    leader, leaderConfigs, leaderGrants,
    match,
    pendingVoteSave, pendingVoteSend,
    commands,
    staleResponseSeen,
    \* UPDATE-MAP
    \* code: utime.rs:17 (Leased::lease_enabled), utime.rs:127-161
    \* update: Update!LeaseReenabledOnVoteChange, Update!DisabledLeaseOnlyByTransfer
    leaseEnabled,
    \* R1: payload of the pending Command::SendVote (engine_impl.rs:243-245)
    sendVoteReq,
    \* R1: in-flight RequestVote messages (core/raft_core.rs:1049-1100)
    voteReqs,
    \* R1: granted votes; a response is delivered only after the responder's
    \* vote I/O is flushed (core/raft_core.rs:1112-1123).
    voteGrants,
    \* R8: the self VoteResponse that Command::SaveVote enqueues on the FIFO
    \* notification channel (core/raft_core.rs:1669-1681) before SendVote runs;
    \* remote vote responses use the same channel (core/raft_core.rs:1065,
    \* 1093) and therefore cannot overtake it.
    selfRespPending,
    \* R3: RaftCore task panicked (Fatal::Panicked); sticky.
    \* update: Update!NoCorePanic
    panicked,
    \* Observation of RaftState::accepted_io kind: TRUE when the last accepted
    \* I/O is a non-committed vote I/O (IOId::Vote, no log id), FALSE for a log
    \* I/O.  Source: raft_state/io_state/io_id.rs:71-98; vote_handler/mod.rs:155.
    \* No guard reads it (MC VIEW excludes it).
    acceptedVoteIO

voteVars == <<voteTerm, voteNode, voteCommitted,
              lastSeenTerm, lastSeenNode, lastSeenCommitted,
              durableVoteTerm, durableVoteNode, durableVoteCommitted,
              pendingVoteSave, pendingVoteSend>>
logVars == <<logs, commitIndex, acceptedIndex, submittedIndex, flushedIndex,
             appliedIndex, durableLogs, durableCommit>>
membershipVars == <<effectiveIndex, committedMembershipIndex, configs,
                    committedConfigs, learners>>
electionVars == <<role, candidate, candidateTerm, candidateNode,
                  candidateConfigs, granters, leader, leaderConfigs, leaderGrants>>
netVars == <<sendVoteReq, voteReqs, voteGrants, selfRespPending>>
allVars == <<up, voteVars, logVars, membershipVars, electionVars,
             match, commands, staleResponseSeen, leaseEnabled, netVars, panicked,
             acceptedVoteIO>>

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

\* LogId = (CommittedLeaderId(term,node), index), derived lexicographic
\* order. Source: log_id/mod.rs (derive PartialOrd), leader_id_adv.rs:14-22.
LogIdLE(t1, n1, i1, t2, n2, i2) ==
    \/ t1 < t2
    \/ t1 = t2 /\ n1 < n2
    \/ t1 = t2 /\ n1 = n2 /\ i1 <= i2

StrictMajority(voters, ids) ==
    2 * Cardinality(voters \cap ids) > Cardinality(voters)

Quorum(cfg, ids) ==
    /\ cfg # {}
    /\ \A child \in cfg : child # {} /\ StrictMajority(child, ids)

Voters(cfg) == UNION cfg
IsVoter(n, id) == id \in Voters(configs[n])
\* MembershipState::contains: voter or learner of the effective membership.
\* Source: raft_state/membership_state/mod.rs:73-75.
Contains(n, id) == id \in (Voters(configs[n]) \cup learners[n])

MaxElem(s) == CHOOSE x \in s : \A y \in s : x >= y
Min2(a, b) == IF a <= b THEN a ELSE b
LastIndex(n) == Len(logs[n]) - 1

EmptyEntry == [term |-> 0, node |-> NoNode, kind |-> "data",
               cfg |-> {InitialVoters}, learners |-> Server \ InitialVoters]

InitEntry == [term |-> 0, node |-> NoNode, kind |-> "uniform",
              cfg |-> {InitialVoters}, learners |-> Server \ InitialVoters]

NewEntry(t, n, k, cfg, lrn) ==
    [term |-> t, node |-> n, kind |-> k, cfg |-> cfg, learners |-> lrn]

EntryAt(n, i) == logs[n][i + 1]
LastTerm(n) == EntryAt(n, LastIndex(n)).term
LastNode(n) == EntryAt(n, LastIndex(n)).node

\* Log-id prefix agreement of two nodes up to index i (Log Matching).
LogIdsAgree(a, b, i) ==
    /\ i <= LastIndex(a)
    /\ i <= LastIndex(b)
    /\ \A k \in 0..i : EntryAt(a, k).term = EntryAt(b, k).term
                       /\ EntryAt(a, k).node = EntryAt(b, k).node

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

NoReq == [term |-> 0, node |-> NoNode, lastTerm |-> 0, lastNode |-> NoNode,
          lastIndex |-> 0, dsts |-> {}]

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
    /\ granters = [n \in Server |-> {}]
    /\ leader = [n \in Server |-> FALSE]
    /\ leaderConfigs = configs
    /\ leaderGrants = [n \in Server |-> {}]
    /\ match = [n \in Server |-> [p \in Server |-> IF p = n THEN 0 ELSE -1]]
    /\ pendingVoteSave = [n \in Server |-> FALSE]
    /\ pendingVoteSend = [n \in Server |-> FALSE]
    /\ commands = [n \in Server |-> {}]
    /\ staleResponseSeen = FALSE
    \* Leased::default/new/without_last_update set lease_enabled = true.
    \* Source: utime.rs:31-38,58-76.
    /\ leaseEnabled = [n \in Server |-> TRUE]
    /\ sendVoteReq = [n \in Server |-> NoReq]
    /\ voteReqs = {}
    /\ voteGrants = {}
    /\ selfRespPending = [n \in Server |-> FALSE]
    /\ panicked = [n \in Server |-> FALSE]
    /\ acceptedVoteIO = [n \in Server |-> FALSE]

(***************************************************************************)
(* Engine::elect body, shared by every caller.                             *)
(* Source: engine/engine_impl.rs:223-249 (elect), :117-135 (new_candidate),*)
(* engine/handler/vote_handler/mod.rs:125-171 (update_vote: vote > current *)
(* -> Leased::update re-enables the lease, SaveVote; then                  *)
(* update_internal_server_state), :174-182 (candidate kept only when       *)
(* is_leading, i.e. the node is *contained* in the effective membership;    *)
(* otherwise become_following clears candidate and leader, :234-244).       *)
(* SendVote is pushed after the vote change; its targets are the voters of *)
(* the effective membership when RaftCore executes it immediately          *)
(* (core/raft_core.rs:1049-1062; command.rs:246 has no condition).          *)
(* UPDATE-MAP                                                              *)
(* code: core/raft_core.rs:1190-1202 (TransferLeader now calls elect())    *)
(* update: Update!AffectedActions (MCTransferElect), Update!ElectOnlyByVoter*)
(***************************************************************************)

ElectCore(n) ==
    LET t == lastSeenTerm[n] + 1
        contained == Contains(n, n)
    IN
    /\ voteTerm' = [voteTerm EXCEPT ![n] = t]
    /\ voteNode' = [voteNode EXCEPT ![n] = n]
    /\ voteCommitted' = [voteCommitted EXCEPT ![n] = FALSE]
    /\ lastSeenTerm' = [lastSeenTerm EXCEPT ![n] = t]
    /\ lastSeenNode' = [lastSeenNode EXCEPT ![n] = n]
    /\ lastSeenCommitted' = [lastSeenCommitted EXCEPT ![n] = FALSE]
    \* Leased::update: utime.rs:126-131 (lease_enabled = true).
    /\ leaseEnabled' = [leaseEnabled EXCEPT ![n] = TRUE]
    /\ candidateTerm' = [candidateTerm EXCEPT ![n] = t]
    /\ candidateNode' = [candidateNode EXCEPT ![n] = n]
    \* Candidate quorum is the effective membership's quorum set, its
    \* progress has NO learner entries: proposer/candidate.rs:62-75.
    /\ candidateConfigs' = [candidateConfigs EXCEPT ![n] = configs[n]]
    /\ granters' = [granters EXCEPT ![n] = {}]
    /\ IF contained
       THEN /\ candidate' = [candidate EXCEPT ![n] = TRUE]
            /\ role' = [role EXCEPT ![n] = "Candidate"]
            /\ UNCHANGED leader
       ELSE \* vote_handler/mod.rs:234-244 become_following
            /\ candidate' = [candidate EXCEPT ![n] = FALSE]
            /\ leader' = [leader EXCEPT ![n] = FALSE]
            /\ role' = [role EXCEPT ![n] = "Learner"]
    /\ pendingVoteSave' = [pendingVoteSave EXCEPT ![n] = TRUE]
    /\ pendingVoteSend' = [pendingVoteSend EXCEPT ![n] = TRUE]
    /\ sendVoteReq' = [sendVoteReq EXCEPT
                         ![n] = [term |-> t, node |-> n,
                                 lastTerm |-> LastTerm(n), lastNode |-> LastNode(n),
                                 lastIndex |-> LastIndex(n),
                                 dsts |-> Voters(configs[n]) \ {n}]]
    /\ commands' = [commands EXCEPT ![n] = {"SaveVote", "SendVote"}]
    \* update_vote: accept_io(IOId::new(non-committed vote)) -> vote I/O
    /\ acceptedVoteIO' = [acceptedVoteIO EXCEPT ![n] = TRUE]
    /\ UNCHANGED <<up, logVars, membershipVars, leaderConfigs,
                    leaderGrants, match, durableVoteTerm, durableVoteNode,
                    durableVoteCommitted, staleResponseSeen, voteReqs,
                    voteGrants, selfRespPending, panicked>>

(***************************************************************************)
(* Pre-existing elect() callers: tick election (core/raft_core.rs:1441-     *)
(* 1488: not Leader, is_voter, enable_elect) and ExternalCommand::Elect     *)
(* (core/raft_core.rs:1207-1213: is_voter only).  Their union is enabled   *)
(* exactly when the node is a voter.                                       *)
(***************************************************************************)

StartElection(n) ==
    /\ up[n]
    /\ IsVoter(n, n)
    /\ lastSeenTerm[n] < MaxTerm
    /\ ElectCore(n)

(***************************************************************************)
(* RaftMsg::TransferLeader handler.                                        *)
(* UPDATE-MAP                                                              *)
(* code: core/raft_core.rs:1190-1202; core/raft_msg/mod.rs:98-107;         *)
(*       raft/mod.rs:645-703 (public transfer_leader API: any caller,      *)
(*       non-target sends at once, target sends after metrics wait or     *)
(*       timeout); utime.rs:133-138 (disable_lease)                        *)
(* update: Update!AffectedActions (MCTransferElect, MCTransferLease)       *)
(* The handler's only guard is vote equality; for `to == self.id` it calls *)
(* Engine::elect() WITHOUT the is_voter / not-Leader / enable_elect guards  *)
(* of the two pre-existing callers.  disable_lease precedes elect(), whose *)
(* Leased::update re-enables the lease for the new vote.                   *)
(***************************************************************************)

TransferLeader(n, ft, fo, fc, to) ==
    /\ up[n]
    /\ to \in Server
    \* raft_core.rs:1194: self.engine.state.vote_ref() == &current_leader_vote
    /\ voteTerm[n] = ft /\ voteNode[n] = fo /\ voteCommitted[n] = fc
    /\ IF to = n
       THEN \* raft_core.rs:1197-1199: disable_lease(); elect()
            /\ lastSeenTerm[n] < MaxTerm
            /\ ElectCore(n)
       ELSE \* raft_core.rs:1197: disable_lease() only
            /\ leaseEnabled' = [leaseEnabled EXCEPT ![n] = FALSE]
            /\ commands' = [commands EXCEPT ![n] = {}]
            /\ UNCHANGED <<up, voteVars, logVars, membershipVars, electionVars,
                            match, staleResponseSeen, netVars, panicked, acceptedVoteIO>>

\* Vote mismatch: the handler does nothing (raft_core.rs:1194).
TransferLeaderIgnored(n, ft, fo, fc, to) ==
    /\ up[n]
    /\ to \in Server
    /\ ~(voteTerm[n] = ft /\ voteNode[n] = fo /\ voteCommitted[n] = fc)
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<up, voteVars, logVars, membershipVars, electionVars,
                    match, staleResponseSeen, leaseEnabled, netVars, panicked, acceptedVoteIO>>

(***************************************************************************)
(* Runtime persistence is separate. Send becomes eligible only afterward. *)
(* Source: core/raft_core.rs:1669-1681 (SaveVote), :1710-1712 (SendVote),  *)
(* :1049-1100 (targets = effective voters except self).                     *)
(***************************************************************************)

PersistVote(n) ==
    /\ up[n]
    /\ pendingVoteSave[n]
    /\ durableVoteTerm' = [durableVoteTerm EXCEPT ![n] = voteTerm[n]]
    /\ durableVoteNode' = [durableVoteNode EXCEPT ![n] = voteNode[n]]
    /\ durableVoteCommitted' = [durableVoteCommitted EXCEPT ![n] = voteCommitted[n]]
    /\ pendingVoteSave' = [pendingVoteSave EXCEPT ![n] = FALSE]
    \* R8: a saved non-committed self vote is answered to itself first.
    /\ selfRespPending' = [selfRespPending EXCEPT
                             ![n] = IF voteNode[n] = n /\ ~voteCommitted[n] THEN TRUE ELSE @]
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<up, voteTerm, voteNode, voteCommitted, lastSeenTerm,
                    lastSeenNode, lastSeenCommitted, pendingVoteSend,
                    logVars, membershipVars, electionVars, match,
                    staleResponseSeen, leaseEnabled, sendVoteReq, voteReqs,
                    voteGrants, panicked, acceptedVoteIO>>

SendVoteRequests(n) ==
    /\ up[n]
    /\ pendingVoteSend[n]
    /\ ~pendingVoteSave[n]
    /\ pendingVoteSend' = [pendingVoteSend EXCEPT ![n] = FALSE]
    /\ voteReqs' = voteReqs \cup
                   {[src |-> n, dst |-> d, term |-> sendVoteReq[n].term,
                     node |-> sendVoteReq[n].node,
                     lastTerm |-> sendVoteReq[n].lastTerm,
                     lastNode |-> sendVoteReq[n].lastNode,
                     lastIndex |-> sendVoteReq[n].lastIndex] :
                       d \in sendVoteReq[n].dsts}
    /\ sendVoteReq' = [sendVoteReq EXCEPT ![n] = NoReq]
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<up, voteTerm, voteNode, voteCommitted, lastSeenTerm,
                    lastSeenNode, lastSeenCommitted, durableVoteTerm,
                    durableVoteNode, durableVoteCommitted, pendingVoteSave,
                    logVars, membershipVars, electionVars, match,
                    staleResponseSeen, leaseEnabled, voteGrants, selfRespPending,
                    panicked, acceptedVoteIO>>

(***************************************************************************)
(* Engine::handle_vote_req.  Source: engine/engine_impl.rs:292-343;        *)
(* vote_handler/mod.rs:96-171.  Accept path: full LogId freshness (R1),    *)
(* nondecreasing vote; SaveVote and Leased::update only when strictly      *)
(* greater, otherwise Leased::touch keeps lease_enabled (R5).  The granted *)
(* vote is recorded for a response gated by vote I/O flush                 *)
(* (core/raft_core.rs:1112-1123).                                           *)
(* Lease rejection (engine_impl.rs:305-315) is time based: with a committed*)
(* vote and an enabled lease the lease may or may not have expired, so both*)
(* outcomes are admitted; a disabled lease (lease = 0) is expired at once  *)
(* (utime.rs:141-147).                                                      *)
(***************************************************************************)

ReceiveVoteRequest(n, cand, t, c, lt, lo, li) ==
    /\ up[n]
    /\ cand \in Server
    /\ cand # n
    \* VoteRequest votes are created by elect() and are never committed
    \* (engine_impl.rs:243-245).
    /\ ~c
    /\ t <= MaxTerm
    /\ LogIdLE(LastTerm(n), LastNode(n), LastIndex(n), lt, lo, li)
    /\ VoteLE(voteTerm[n], voteNode[n], voteCommitted[n], t, cand, c)
    /\ LET greater == VoteLT(voteTerm[n], voteNode[n], voteCommitted[n], t, cand, c)
           seenUp == VoteLE(lastSeenTerm[n], lastSeenNode[n], lastSeenCommitted[n], t, cand, c)
       IN
       /\ voteTerm' = [voteTerm EXCEPT ![n] = t]
       /\ voteNode' = [voteNode EXCEPT ![n] = cand]
       /\ voteCommitted' = [voteCommitted EXCEPT ![n] = c]
       /\ lastSeenTerm' = [lastSeenTerm EXCEPT ![n] = IF seenUp THEN t ELSE @]
       /\ lastSeenNode' = [lastSeenNode EXCEPT ![n] = IF seenUp THEN cand ELSE @]
       /\ lastSeenCommitted' = [lastSeenCommitted EXCEPT ![n] = IF seenUp THEN c ELSE @]
       /\ leaseEnabled' = [leaseEnabled EXCEPT ![n] = IF greater THEN TRUE ELSE @]
       /\ pendingVoteSave' = [pendingVoteSave EXCEPT ![n] = IF greater THEN TRUE ELSE @]
       /\ commands' = [commands EXCEPT ![n] = IF greater THEN {"SaveVote"} ELSE {}]
       /\ acceptedVoteIO' = [acceptedVoteIO EXCEPT ![n] = IF greater THEN TRUE ELSE @]
    \* update_internal_server_state -> become_following (vote is not mine)
    /\ candidate' = [candidate EXCEPT ![n] = FALSE]
    /\ leader' = [leader EXCEPT ![n] = FALSE]
    /\ role' = [role EXCEPT ![n] = IF IsVoter(n,n) THEN "Follower" ELSE "Learner"]
    /\ voteGrants' = voteGrants \cup {[voter |-> n, term |-> t, node |-> cand, committed |-> c]}
    /\ UNCHANGED <<up, durableVoteTerm, durableVoteNode, durableVoteCommitted,
                    pendingVoteSend, logVars, membershipVars, candidateTerm,
                    candidateNode, candidateConfigs, granters, leaderConfigs,
                    leaderGrants, match, staleResponseSeen, sendVoteReq,
                    voteReqs, selfRespPending, panicked>>

\* Rejection paths return before any state change (engine_impl.rs:305-339;
\* vote rejection's update_last_seen cannot raise last_seen because
\* req.vote < vote <= last_seen).  Only the response is sent.
RejectVoteRequest(n, cand, t, c, lt, lo, li) ==
    /\ up[n]
    /\ cand \in Server
    /\ cand # n
    /\ \/ voteCommitted[n] /\ leaseEnabled[n]
       \/ ~LogIdLE(LastTerm(n), LastNode(n), LastIndex(n), lt, lo, li)
       \/ ~VoteLE(voteTerm[n], voteNode[n], voteCommitted[n], t, cand, c)
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<up, voteVars, logVars, membershipVars, electionVars,
                    match, staleResponseSeen, leaseEnabled, netVars, panicked, acceptedVoteIO>>

(***************************************************************************)
(* Engine::handle_vote_resp for an exact grant.  Quorum establishment      *)
(* commits the vote and appends the current leader's blank entry.          *)
(* Source: engine/engine_impl.rs:345-402,642-669; candidate.rs:90-96.       *)
(* R3: Candidate::grant_by calls progress.update(target).expect("target not*)
(* in quorum set"); the progress holds only the voters of the quorum set   *)
(* (candidate.rs:62-75), so a grant by a non-voter target panics the       *)
(* RaftCore task.  The self grant is always delivered after SaveVote       *)
(* (core/raft_core.rs:1669-1681).                                           *)
(***************************************************************************)

ReceiveVoteResponse(n, peer, t, owner, c) ==
    /\ up[n]
    /\ peer \in Server
    /\ candidate[n]
    /\ t = candidateTerm[n]
    /\ owner = candidateNode[n]
    /\ ~c
    /\ IF peer \in Voters(candidateConfigs[n])
       THEN
       LET gs == granters[n] \cup {peer}
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
               \* establish_leader: update_vote(committed) -> Leased::update
               /\ leaseEnabled' = [leaseEnabled EXCEPT ![n] = TRUE]
               /\ logs' = [logs EXCEPT ![n] = Append(@, e)]
               /\ acceptedIndex' = [acceptedIndex EXCEPT ![n] = LastIndex(n) + 1]
               /\ leaderConfigs' = [leaderConfigs EXCEPT ![n] = candidateConfigs[n]]
               /\ leaderGrants' = [leaderGrants EXCEPT ![n] = gs]
               \* The new blank is only accepted; self-match remains the old local log
               \* until the later LocalIO callback. Source: core/raft_core.rs:1338-1360.
               /\ match' = [match EXCEPT ![n] = [p \in Server |-> IF p = n THEN LastIndex(n) ELSE -1]]
               /\ pendingVoteSave' = [pendingVoteSave EXCEPT ![n] = TRUE]
               /\ commands' = [commands EXCEPT ![n] = LeaderEstablishedCommands(n)]
               \* establish_leader: accept_io(new_log_io(..)) then blank append
               /\ acceptedVoteIO' = [acceptedVoteIO EXCEPT ![n] = FALSE]
          ELSE /\ UNCHANGED <<candidate, leader, role, voteTerm, voteNode,
                               voteCommitted, lastSeenTerm, lastSeenNode,
                               lastSeenCommitted, logs, acceptedIndex,
                               leaderConfigs, leaderGrants, match, pendingVoteSave,
                               leaseEnabled, acceptedVoteIO>>
               /\ commands' = [commands EXCEPT ![n] = {}]
       /\ UNCHANGED <<up, panicked>>
       ELSE
       \* R3 panic: RaftCore stops; volatile state is lost like a crash.
       /\ panicked' = [panicked EXCEPT ![n] = TRUE]
       /\ up' = [up EXCEPT ![n] = FALSE]
       /\ candidate' = [candidate EXCEPT ![n] = FALSE]
       /\ leader' = [leader EXCEPT ![n] = FALSE]
       /\ role' = [role EXCEPT ![n] = "Learner"]
       /\ granters' = [granters EXCEPT ![n] = {}]
       /\ pendingVoteSave' = [pendingVoteSave EXCEPT ![n] = FALSE]
       /\ commands' = [commands EXCEPT ![n] = {}]
       /\ UNCHANGED <<voteTerm, voteNode, voteCommitted, lastSeenTerm,
                       lastSeenNode, lastSeenCommitted, logs, acceptedIndex,
                       leaderConfigs, leaderGrants, match, leaseEnabled,
                       acceptedVoteIO>>
    /\ UNCHANGED <<pendingVoteSend, submittedIndex, flushedIndex,
                    appliedIndex, durableLogs, durableCommit, commitIndex,
                    durableVoteTerm, durableVoteNode, durableVoteCommitted,
                    membershipVars, candidateTerm, candidateNode,
                    candidateConfigs, staleResponseSeen, sendVoteReq, voteReqs,
                    voteGrants>>
    /\ selfRespPending' = [selfRespPending EXCEPT ![n] = IF peer = n THEN FALSE ELSE @]

\* A response whose vote is not the candidate's (rejection, stale response,
\* or no candidate): only update_last_seen (engine_impl.rs:357-380).
ReceiveVoteResponseOther(n, t, owner, c) ==
    /\ up[n]
    /\ ~(candidate[n] /\ t = candidateTerm[n] /\ owner = candidateNode[n] /\ ~c)
    /\ LET seenUp == VoteLE(lastSeenTerm[n], lastSeenNode[n], lastSeenCommitted[n], t, owner, c)
       IN /\ lastSeenTerm' = [lastSeenTerm EXCEPT ![n] = IF seenUp THEN t ELSE @]
          /\ lastSeenNode' = [lastSeenNode EXCEPT ![n] = IF seenUp THEN owner ELSE @]
          /\ lastSeenCommitted' = [lastSeenCommitted EXCEPT ![n] = IF seenUp THEN c ELSE @]
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<up, voteTerm, voteNode, voteCommitted, durableVoteTerm,
                    durableVoteNode, durableVoteCommitted, pendingVoteSave,
                    pendingVoteSend, logVars, membershipVars, electionVars,
                    match, staleResponseSeen, leaseEnabled, netVars, panicked, acceptedVoteIO>>

\* R8: the queued self VoteResponse is ignored by does_vote_match when the
\* candidate it was sent for no longer exists (core/raft_core.rs:1260,
\* 1524-1549).
DropSelfVoteResponse(n) ==
    /\ up[n]
    /\ selfRespPending[n]
    /\ ~(candidate[n] /\ durableVoteTerm[n] = candidateTerm[n]
         /\ durableVoteNode[n] = candidateNode[n] /\ ~durableVoteCommitted[n])
    /\ selfRespPending' = [selfRespPending EXCEPT ![n] = FALSE]
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<up, voteVars, logVars, membershipVars, electionVars, match,
                    staleResponseSeen, leaseEnabled, sendVoteReq, voteReqs,
                    voteGrants, panicked, acceptedVoteIO>>

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
    /\ acceptedVoteIO' = [acceptedVoteIO EXCEPT ![n] = FALSE]
    /\ UNCHANGED <<up, voteVars, commitIndex, submittedIndex, flushedIndex,
                    appliedIndex, durableLogs, durableCommit,
                    committedMembershipIndex, committedConfigs,
                    electionVars, staleResponseSeen, leaseEnabled, netVars,
                    panicked>>

(***************************************************************************)
(* Follower accepts a consecutive suffix in one synchronous Engine call.  *)
(* Source: engine_impl.rs:408-477 (handle_append_entries: update_vote,     *)
(* ensure_log_consecutive, append_entries); following_handler/mod.rs:58-157*)
(* (do_append_entries -> append_membership: the last membership entry in   *)
(* the suffix becomes effective; server state recomputed).                  *)
(* R2: generalized from a same-term data suffix to the leader's entries so *)
(* replicated membership entries take effect on the follower.  Conflict    *)
(* truncation is not modeled (appends extend the local log).               *)
(* Leased lease handling: vote > current -> update (re-enable), equal ->    *)
(* touch, which keeps a disabled lease disabled (utime.rs:150-161).         *)
(***************************************************************************)

ReceiveAppend(n, vt, vo, ents) ==
    /\ up[n]
    /\ vo \in Server
    /\ vt <= MaxTerm
    /\ Len(ents) >= 1
    /\ LastIndex(n) + Len(ents) <= MaxIndex
    /\ VoteLE(voteTerm[n], voteNode[n], voteCommitted[n], vt, vo, TRUE)
    /\ LET greater == VoteLT(voteTerm[n], voteNode[n], voteCommitted[n], vt, vo, TRUE)
           seenUp == VoteLE(lastSeenTerm[n], lastSeenNode[n], lastSeenCommitted[n], vt, vo, TRUE)
           mps == {i \in 1..Len(ents) : ents[i].kind \in MembershipKinds}
           hasM == mps # {}
           lastM == IF hasM THEN MaxElem(mps) ELSE 0
           newCfg == IF hasM THEN ents[lastM].cfg ELSE configs[n]
           newLrn == IF hasM THEN ents[lastM].learners ELSE learners[n]
       IN
       /\ voteTerm' = [voteTerm EXCEPT ![n] = vt]
       /\ voteNode' = [voteNode EXCEPT ![n] = vo]
       /\ voteCommitted' = [voteCommitted EXCEPT ![n] = TRUE]
       /\ lastSeenTerm' = [lastSeenTerm EXCEPT ![n] = IF seenUp THEN vt ELSE @]
       /\ lastSeenNode' = [lastSeenNode EXCEPT ![n] = IF seenUp THEN vo ELSE @]
       /\ lastSeenCommitted' = [lastSeenCommitted EXCEPT ![n] = IF seenUp THEN TRUE ELSE @]
       /\ leaseEnabled' = [leaseEnabled EXCEPT ![n] = IF greater THEN TRUE ELSE @]
       /\ logs' = [logs EXCEPT ![n] = @ \o ents]
       /\ acceptedIndex' = [acceptedIndex EXCEPT ![n] = LastIndex(n) + Len(ents)]
       /\ effectiveIndex' = [effectiveIndex EXCEPT
                                ![n] = IF hasM THEN LastIndex(n) + lastM ELSE @]
       /\ configs' = [configs EXCEPT ![n] = newCfg]
       /\ learners' = [learners EXCEPT ![n] = newLrn]
       /\ role' = [role EXCEPT ![n] = IF n \in Voters(newCfg) THEN "Follower" ELSE "Learner"]
       /\ pendingVoteSave' = [pendingVoteSave EXCEPT
                                   ![n] = IF greater THEN TRUE ELSE @]
       /\ commands' = [commands EXCEPT
                         ![n] = {"AppendInputEntries"}
                                \cup (IF greater THEN {"SaveVote"} ELSE {})]
    /\ candidate' = [candidate EXCEPT ![n] = FALSE]
    /\ leader' = [leader EXCEPT ![n] = FALSE]
    /\ acceptedVoteIO' = [acceptedVoteIO EXCEPT ![n] = FALSE]
    /\ UNCHANGED <<up, pendingVoteSend, durableVoteTerm, durableVoteNode,
                    durableVoteCommitted, commitIndex, submittedIndex,
                    flushedIndex, appliedIndex, durableLogs, durableCommit,
                    committedMembershipIndex, committedConfigs,
                    candidateTerm, candidateNode,
                    candidateConfigs, granters, leaderConfigs, leaderGrants,
                    match, staleResponseSeen, netVars, panicked>>

RECURSIVE AppendSameTerm(_, _, _, _, _, _)
AppendSameTerm(s, count, t, owner, cfg, lrn) ==
    IF count = 0 THEN s
    ELSE AppendSameTerm(Append(s, NewEntry(t, owner, "data", cfg, lrn)),
                        count - 1, t, owner, cfg, lrn)

\* Same-term non-membership suffix (exact V0 trace boundary).
ReceiveAppendDirect(n, owner, t, prev, count) ==
    /\ count \in 1..MaxIndex
    /\ prev = LastIndex(n)
    /\ ReceiveAppend(n, t, owner,
                     AppendSameTerm(<<>>, count, t, owner, configs[n], learners[n]))

(***************************************************************************)
(* Log submission, flush, follower response, durable commit, and apply are *)
(* distinct Runtime effects. Source: storage/v2.rs:93-105;                 *)
(* core/raft_core.rs:1646-1668,1718-1720.                                  *)
(***************************************************************************)

SubmitLog(n) ==
    /\ up[n]
    /\ submittedIndex[n] < acceptedIndex[n]
    /\ submittedIndex' = [submittedIndex EXCEPT ![n] = acceptedIndex[n]]
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<up, voteVars, logs, commitIndex, acceptedIndex,
                    flushedIndex, appliedIndex, durableLogs, durableCommit,
                    membershipVars, electionVars, match, staleResponseSeen,
                    leaseEnabled, netVars, panicked, acceptedVoteIO>>

FlushLog(n) ==
    /\ up[n]
    /\ flushedIndex[n] < submittedIndex[n]
    /\ flushedIndex' = [flushedIndex EXCEPT ![n] = submittedIndex[n]]
    /\ durableLogs' = [durableLogs EXCEPT ![n] = SubSeq(logs[n], 1, submittedIndex[n] + 1)]
    /\ match' = [match EXCEPT
                   ![n][n] = IF leader[n] THEN submittedIndex[n] ELSE @]
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<up, voteVars, logs, commitIndex, acceptedIndex,
                    submittedIndex, appliedIndex, durableCommit,
                    membershipVars, electionVars, staleResponseSeen,
                    leaseEnabled, netVars, panicked, acceptedVoteIO>>

SendAppendSuccess(n) ==
    /\ up[n]
    /\ flushedIndex[n] = acceptedIndex[n]
    /\ commands' = [commands EXCEPT ![n] = {"Respond"}]
    /\ UNCHANGED <<up, voteVars, logVars, membershipVars, electionVars,
                    match, staleResponseSeen, leaseEnabled, netVars, panicked, acceptedVoteIO>>

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
                    staleResponseSeen, leaseEnabled, netVars, panicked, acceptedVoteIO>>

DropStaleResponse(n, peer, oldSession) ==
    /\ up[n]
    /\ leader[n]
    /\ peer \in Server
    /\ oldSession # effectiveIndex[n]
    /\ staleResponseSeen' = TRUE
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<up, voteVars, logVars, membershipVars, electionVars, match,
                    leaseEnabled, netVars, panicked, acceptedVoteIO>>

SaveCommit(n) ==
    /\ up[n]
    /\ durableCommit[n] < commitIndex[n]
    /\ durableCommit' = [durableCommit EXCEPT ![n] = commitIndex[n]]
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<up, voteVars, logs, commitIndex, acceptedIndex,
                    submittedIndex, flushedIndex, appliedIndex, durableLogs,
                    membershipVars, electionVars, match, staleResponseSeen,
                    leaseEnabled, netVars, panicked, acceptedVoteIO>>

ApplyCommitted(n) ==
    /\ up[n]
    /\ appliedIndex[n] < durableCommit[n]
    /\ appliedIndex' = [appliedIndex EXCEPT ![n] = durableCommit[n]]
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<up, voteVars, logs, commitIndex, acceptedIndex,
                    submittedIndex, flushedIndex, durableLogs, durableCommit,
                    membershipVars, electionVars, match, staleResponseSeen,
                    leaseEnabled, netVars, panicked, acceptedVoteIO>>

(***************************************************************************)
(* Crash loses volatile Engine/Core state. Restart reads only completed     *)
(* durable state and derives membership/role.                              *)
(* Source: storage/helper.rs:59-91,173-217; engine_impl.rs:145-174.         *)
(* R4: startup restores leadership only when RaftState::is_leader holds,   *)
(* which requires the node to be contained in the effective membership     *)
(* (raft_state/mod.rs:369-383).                                            *)
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
    /\ sendVoteReq' = [sendVoteReq EXCEPT ![n] = NoReq]
    /\ selfRespPending' = [selfRespPending EXCEPT ![n] = FALSE]
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<voteTerm, voteNode, voteCommitted, lastSeenTerm,
                    lastSeenNode, lastSeenCommitted, durableVoteTerm,
                    durableVoteNode, durableVoteCommitted, logVars,
                    membershipVars, candidateTerm, candidateNode,
                    candidateConfigs, leaderConfigs, leaderGrants, match,
                    staleResponseSeen, leaseEnabled, voteReqs, voteGrants,
                    panicked, acceptedVoteIO>>

Restart(n) ==
    /\ ~up[n]
    /\ ~panicked[n]
    /\ LET ds == durableLogs[n]
           em == EffectiveEntry(ds)
           li == Len(ds) - 1
           contained == n \in (Voters(em.cfg) \cup em.learners)
           selfLeader == durableVoteCommitted[n] /\ durableVoteNode[n] = n /\ contained
       IN
       /\ up' = [up EXCEPT ![n] = TRUE]
       /\ voteTerm' = [voteTerm EXCEPT ![n] = durableVoteTerm[n]]
       /\ voteNode' = [voteNode EXCEPT ![n] = durableVoteNode[n]]
       /\ voteCommitted' = [voteCommitted EXCEPT ![n] = durableVoteCommitted[n]]
       /\ lastSeenTerm' = [lastSeenTerm EXCEPT ![n] = durableVoteTerm[n]]
       /\ lastSeenNode' = [lastSeenNode EXCEPT ![n] = durableVoteNode[n]]
       /\ lastSeenCommitted' = [lastSeenCommitted EXCEPT ![n] = durableVoteCommitted[n]]
       \* Fresh RaftState: Leased::new/without_last_update -> enabled.
       /\ leaseEnabled' = [leaseEnabled EXCEPT ![n] = TRUE]
       /\ logs' = [logs EXCEPT ![n] = ds]
       /\ acceptedIndex' = [acceptedIndex EXCEPT ![n] = li]
       /\ submittedIndex' = [submittedIndex EXCEPT ![n] = li]
       /\ flushedIndex' = [flushedIndex EXCEPT ![n] = li]
       /\ commitIndex' = [commitIndex EXCEPT ![n] = durableCommit[n]]
       /\ effectiveIndex' = [effectiveIndex EXCEPT ![n] = MaxElem(MembershipPositions(ds)) - 1]
       /\ committedMembershipIndex' = [committedMembershipIndex EXCEPT
                                          ![n] = MaxElem({p \in MembershipPositions(ds) : p - 1 <= durableCommit[n]}) - 1]
       /\ configs' = [configs EXCEPT ![n] = em.cfg]
       /\ committedConfigs' = [committedConfigs EXCEPT ![n] = em.cfg]
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
    /\ acceptedVoteIO' = [acceptedVoteIO EXCEPT ![n] = FALSE]
    /\ UNCHANGED <<appliedIndex, durableLogs, durableCommit,
                    durableVoteTerm, durableVoteNode, durableVoteCommitted,
                    candidateTerm, candidateNode, candidateConfigs,
                    staleResponseSeen, netVars, panicked>>

(***************************************************************************)
(* Startup from a state already reconstructed by StorageHelper. This is    *)
(* the Engine::startup boundary used by trace validation.                  *)
(* Source: engine_impl.rs:145-174; vote_handler/mod.rs:174-226.            *)
(* R4: is_leader requires containment, not voter membership.               *)
(***************************************************************************)

RestartFromRecovered(n) ==
    /\ up[n]
    /\ voteCommitted[n]
    /\ voteNode[n] = n
    /\ Contains(n, n)
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
                    candidateConfigs, staleResponseSeen, leaseEnabled,
                    netVars, panicked>>
    /\ acceptedVoteIO' = [acceptedVoteIO EXCEPT ![n] = FALSE]

(***************************************************************************)
(* Open-environment reference Next (unbounded message parameters).  The    *)
(* MC module supplies the network-linked bounded instance.                 *)
(***************************************************************************)

Next ==
    \/ \E n \in Server : StartElection(n)
    \/ \E n, to \in Server, t \in 0..MaxTerm, o \in Server \cup {NoNode}, c \in BOOLEAN :
          TransferLeader(n, t, o, c, to)
    \/ \E n \in Server : PersistVote(n)
    \/ \E n \in Server : SendVoteRequests(n)
    \/ \E n \in Server, m \in voteReqs :
          m.dst = n /\ ReceiveVoteRequest(n, m.src, m.term, FALSE,
                                          m.lastTerm, m.lastNode, m.lastIndex)
    \/ \E n,peer \in Server, g \in voteGrants :
          /\ peer # n /\ ~selfRespPending[n]
          /\ g.voter = peer /\ g.term = candidateTerm[n] /\ g.node = candidateNode[n]
          /\ ReceiveVoteResponse(n, peer, g.term, g.node, FALSE)
    \/ \E n \in Server :
          /\ selfRespPending[n]
          /\ durableVoteTerm[n] = candidateTerm[n] /\ durableVoteNode[n] = n
          /\ ~durableVoteCommitted[n]
          /\ ReceiveVoteResponse(n, n, candidateTerm[n], n, FALSE)
    \/ \E n \in Server : DropSelfVoteResponse(n)
    \/ \E n \in Server, kind \in EntryKinds,
          cfg \in SUBSET (SUBSET Server), lrn \in SUBSET Server :
          LeaderAppend(n,kind,cfg,lrn)
    \/ \E n, ldr \in Server :
          /\ n # ldr /\ leader[ldr] /\ voteCommitted[ldr]
          /\ LastIndex(n) < LastIndex(ldr)
          /\ LogIdsAgree(n, ldr, LastIndex(n))
          /\ ReceiveAppend(n, voteTerm[ldr], ldr, <<EntryAt(ldr, LastIndex(n) + 1)>>)
    \/ \E n \in Server : SubmitLog(n) \/ FlushLog(n) \/ SendAppendSuccess(n)
    \/ \E n,peer \in Server, idx \in 0..MaxIndex :
          /\ flushedIndex[peer] >= idx /\ LogIdsAgree(n, peer, idx)
          /\ AcknowledgeReplication(n,peer,idx)
    \/ \E n,peer \in Server, sess \in -1..MaxIndex :
          DropStaleResponse(n,peer,sess)
    \/ \E n \in Server : SaveCommit(n) \/ ApplyCommitted(n) \/ Crash(n) \/ Restart(n)

Spec == Init /\ [][Next]_allVars

(***************************************************************************)
(* Invariants.                                                             *)
(***************************************************************************)

ReqRecords == [term : 0..MaxTerm, node : Server \cup {NoNode},
               lastTerm : 0..MaxTerm, lastNode : Server \cup {NoNode},
               lastIndex : 0..MaxIndex, dsts : SUBSET Server]

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
    /\ leaseEnabled \in [Server -> BOOLEAN]
    /\ panicked \in [Server -> BOOLEAN]
    /\ acceptedVoteIO \in [Server -> BOOLEAN]
    /\ selfRespPending \in [Server -> BOOLEAN]
    /\ sendVoteReq \in [Server -> ReqRecords]
    /\ \A m \in voteReqs : m.src \in Server /\ m.dst \in Server /\ m.term \in 0..MaxTerm
    /\ \A g \in voteGrants : g.voter \in Server /\ g.node \in Server /\ g.term \in 0..MaxTerm
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

\* Raft leader completeness in Openraft's vote order: an established leader
\* whose committed vote is greater than another node's committed leader vote
\* holds every entry that node's leader has committed.
LeaderCompleteness ==
    \A a,b \in Server :
      ( /\ leader[a] /\ voteCommitted[a] /\ voteNode[a] = a
        /\ leader[b] /\ voteCommitted[b] /\ voteNode[b] = b
        /\ VoteLT(voteTerm[a], a, TRUE, voteTerm[b], b, TRUE) )
      => LogIdsAgree(a, b, commitIndex[a])

====
