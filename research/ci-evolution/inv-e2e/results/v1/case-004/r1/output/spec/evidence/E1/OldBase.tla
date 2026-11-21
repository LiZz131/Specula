---- MODULE OldBase ----
(***************************************************************************)
(* Exact-old Openraft Engine/RaftCore consensus model.                     *)
(* Baseline 955ebf13f9c4acf88240775db2b51832c9cbb6a9.                     *)
(* Every logic block cites the source that defines the modeled behavior.   *)
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
    candidate, candidateTerm, candidateNode, candidateConfigs, granters,
    leader, leaderConfigs, leaderGrants,
    match,
    pendingVoteSave, pendingVoteSend,
    commands,
    staleResponseSeen

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
allVars == <<up, voteVars, logVars, membershipVars, electionVars,
             match, commands, staleResponseSeen>>

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

StrictMajority(voters, ids) ==
    2 * Cardinality(voters \cap ids) > Cardinality(voters)


Quorum(cfg, ids) ==
    /\ cfg # {}
    /\ \A child \in cfg : child # {} /\ StrictMajority(child, ids)

Voters(cfg) == UNION cfg
IsVoter(n, id) == id \in Voters(configs[n])

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

MembershipPositions(s) ==
    {i \in 1..Len(s) : s[i].kind \in {"learner", "joint", "uniform"}}

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
    \cup (IF kind \in {"learner", "joint", "uniform"}
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

(***************************************************************************)
(* Election synchronously changes the shadow vote and emits SaveVote then  *)
(* SendVote. Candidate quorum/learners are snapshotted.                    *)
(* Source: engine/engine_impl.rs:122-140,221-249.                          *)
(***************************************************************************)

StartElection(n) ==
    /\ up[n]
    /\ IsVoter(n, n)
    /\ lastSeenTerm[n] < MaxTerm
    /\ LET t == lastSeenTerm[n] + 1 IN
       /\ voteTerm' = [voteTerm EXCEPT ![n] = t]
       /\ voteNode' = [voteNode EXCEPT ![n] = n]
       /\ voteCommitted' = [voteCommitted EXCEPT ![n] = FALSE]
       /\ lastSeenTerm' = [lastSeenTerm EXCEPT ![n] = t]
       /\ lastSeenNode' = [lastSeenNode EXCEPT ![n] = n]
       /\ lastSeenCommitted' = [lastSeenCommitted EXCEPT ![n] = FALSE]
       /\ candidateTerm' = [candidateTerm EXCEPT ![n] = t]
       /\ candidateNode' = [candidateNode EXCEPT ![n] = n]
    /\ role' = [role EXCEPT ![n] = "Candidate"]
    /\ candidate' = [candidate EXCEPT ![n] = TRUE]
    /\ candidateConfigs' = [candidateConfigs EXCEPT ![n] = configs[n]]
    /\ granters' = [granters EXCEPT ![n] = {}]
    /\ pendingVoteSave' = [pendingVoteSave EXCEPT ![n] = TRUE]
    /\ pendingVoteSend' = [pendingVoteSend EXCEPT ![n] = TRUE]
    /\ commands' = [commands EXCEPT ![n] = {"SaveVote", "SendVote"}]
    /\ UNCHANGED <<up, logVars, membershipVars, leader, leaderConfigs,
                    leaderGrants, match, durableVoteTerm, durableVoteNode,
                    durableVoteCommitted, staleResponseSeen>>

(***************************************************************************)
(* Runtime persistence is separate. Send becomes eligible only afterward. *)
(* Source: core/raft_core.rs:1625-1681; storage/v2.rs:62-67.                *)
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
                    staleResponseSeen>>

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
                    staleResponseSeen>>

(***************************************************************************)
(* A fresh-enough request can grant only a nondecreasing vote and queues   *)
(* persistence. Lease arithmetic is abstracted by choosing this action.   *)
(* Source: engine/engine_impl.rs:293-343; vote_handler/mod.rs:92-166.       *)
(***************************************************************************)

ReceiveVoteRequest(n, cand, t, c, reqLast) ==
    /\ up[n]
    /\ cand \in Server
    /\ reqLast >= LastIndex(n)
    /\ VoteLE(voteTerm[n], voteNode[n], voteCommitted[n], t, cand, c)
    /\ t <= MaxTerm
    /\ voteTerm' = [voteTerm EXCEPT ![n] = t]
    /\ voteNode' = [voteNode EXCEPT ![n] = cand]
    /\ voteCommitted' = [voteCommitted EXCEPT ![n] = c]
    /\ lastSeenTerm' = [lastSeenTerm EXCEPT ![n] = t]
    /\ lastSeenNode' = [lastSeenNode EXCEPT ![n] = cand]
    /\ lastSeenCommitted' = [lastSeenCommitted EXCEPT ![n] = c]
    /\ candidate' = [candidate EXCEPT ![n] = FALSE]
    /\ leader' = [leader EXCEPT ![n] = FALSE]
    /\ role' = [role EXCEPT ![n] = IF IsVoter(n,n) THEN "Follower" ELSE "Learner"]
    /\ pendingVoteSave' = [pendingVoteSave EXCEPT ![n] = TRUE]
    /\ commands' = [commands EXCEPT ![n] = {"SaveVote"}]
    /\ UNCHANGED <<up, durableVoteTerm, durableVoteNode, durableVoteCommitted,
                    pendingVoteSend, logVars, membershipVars, candidateTerm,
                    candidateNode, candidateConfigs, granters, leaderConfigs,
                    leaderGrants, match, staleResponseSeen>>

(***************************************************************************)
(* Exact returned vote grants. Quorum establishment commits the vote and  *)
(* appends the current leader's blank entry.                               *)
(* Source: engine/engine_impl.rs:347-401,642-669; candidate.rs:90-116.      *)
(***************************************************************************)

ReceiveVoteResponse(n, peer, t, owner, c) ==
    /\ up[n]
    /\ peer \in Server
    /\ candidate[n]
    /\ t = candidateTerm[n]
    /\ owner = candidateNode[n]
    /\ ~c
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
               \* The new blank is only accepted; self-match remains the old local log
               \* until the later LocalIO callback. Source: core/raft_core.rs:1233-1269.
               /\ match' = [match EXCEPT ![n][n] = LastIndex(n)]
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
                    candidateConfigs, staleResponseSeen>>

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
    /\ IF kind \in {"learner", "joint", "uniform"}
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
                                ![n] = IF kind \in {"learner", "joint", "uniform"}
                                       THEN i ELSE @]
       /\ configs' = [configs EXCEPT
                        ![n] = IF kind \in {"learner", "joint", "uniform"}
                               THEN newCfg ELSE @]
       /\ learners' = [learners EXCEPT
                         ![n] = IF kind \in {"learner", "joint", "uniform"}
                                THEN newLearners ELSE @]
    /\ commands' = [commands EXCEPT ![n] = LeaderAppendCommands(n, kind, newCfg, newLearners)]
    /\ UNCHANGED <<up, voteVars, commitIndex, submittedIndex, flushedIndex,
                    appliedIndex, durableLogs, durableCommit,
                    committedMembershipIndex, committedConfigs,
                    electionVars, staleResponseSeen>>

(***************************************************************************)
(* Follower accepts a consecutive suffix in one synchronous Engine call.  *)
(* Source: engine_impl.rs:408-477; following_handler/mod.rs:58-157.         *)
(***************************************************************************)

RECURSIVE AppendSameTerm(_, _, _, _, _, _)
AppendSameTerm(s, count, t, owner, cfg, lrn) ==
    IF count = 0 THEN s
    ELSE AppendSameTerm(Append(s, NewEntry(t, owner, "data", cfg, lrn)),
                        count - 1, t, owner, cfg, lrn)

ReceiveAppendDirect(n, owner, t, prev, count) ==
    /\ up[n]
    /\ owner \in Server
    /\ t <= MaxTerm
    /\ count \in 1..MaxIndex
    /\ prev = LastIndex(n)
    /\ prev + count <= MaxIndex
    /\ VoteLE(voteTerm[n], voteNode[n], voteCommitted[n], t, owner, TRUE)
    /\ voteTerm' = [voteTerm EXCEPT ![n] = t]
    /\ voteNode' = [voteNode EXCEPT ![n] = owner]
    /\ voteCommitted' = [voteCommitted EXCEPT ![n] = TRUE]
    /\ lastSeenTerm' = [lastSeenTerm EXCEPT ![n] = t]
    /\ lastSeenNode' = [lastSeenNode EXCEPT ![n] = owner]
    /\ lastSeenCommitted' = [lastSeenCommitted EXCEPT ![n] = TRUE]
    /\ logs' = [logs EXCEPT
                   ![n] = AppendSameTerm(@, count, t, owner, configs[n], learners[n])]
    /\ acceptedIndex' = [acceptedIndex EXCEPT ![n] = prev + count]
    /\ role' = [role EXCEPT ![n] = IF IsVoter(n,n) THEN "Follower" ELSE "Learner"]
    /\ candidate' = [candidate EXCEPT ![n] = FALSE]
    /\ leader' = [leader EXCEPT ![n] = FALSE]
    /\ LET needsSave == VoteLT(voteTerm[n], voteNode[n], voteCommitted[n],
                               t, owner, TRUE)
       IN /\ pendingVoteSave' = [pendingVoteSave EXCEPT
                                   ![n] = IF needsSave THEN TRUE ELSE @]
          /\ commands' = [commands EXCEPT
                            ![n] = {"AppendInputEntries"}
                                   \cup (IF needsSave THEN {"SaveVote"} ELSE {})]
    /\ UNCHANGED <<up, pendingVoteSend, durableVoteTerm, durableVoteNode,
                    durableVoteCommitted, commitIndex, submittedIndex,
                    flushedIndex, appliedIndex, durableLogs, durableCommit,
                    membershipVars, candidateTerm, candidateNode,
                    candidateConfigs, granters, leaderConfigs, leaderGrants,
                    match, staleResponseSeen>>

(***************************************************************************)
(* Log submission, flush, follower response, durable commit, and apply are *)
(* distinct Runtime effects. Source: storage/v2.rs:93-105;                 *)
(* core/raft_core.rs:1633-1655,1708-1713.                                  *)
(***************************************************************************)

SubmitLog(n) ==
    /\ up[n]
    /\ submittedIndex[n] < acceptedIndex[n]
    /\ submittedIndex' = [submittedIndex EXCEPT ![n] = acceptedIndex[n]]
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<up, voteVars, logs, commitIndex, acceptedIndex,
                    flushedIndex, appliedIndex, durableLogs, durableCommit,
                    membershipVars, electionVars, match, staleResponseSeen>>

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
                    membershipVars, electionVars, staleResponseSeen>>

SendAppendSuccess(n) ==
    /\ up[n]
    /\ flushedIndex[n] = acceptedIndex[n]
    /\ commands' = [commands EXCEPT ![n] = {"Respond"}]
    /\ UNCHANGED <<up, voteVars, logVars, membershipVars, electionVars,
                    match, staleResponseSeen>>

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
                    staleResponseSeen>>

DropStaleResponse(n, peer, oldSession) ==
    /\ up[n]
    /\ leader[n]
    /\ peer \in Server
    /\ oldSession # effectiveIndex[n]
    /\ staleResponseSeen' = TRUE
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<up, voteVars, logVars, membershipVars, electionVars, match>>

SaveCommit(n) ==
    /\ up[n]
    /\ durableCommit[n] < commitIndex[n]
    /\ durableCommit' = [durableCommit EXCEPT ![n] = commitIndex[n]]
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<up, voteVars, logs, commitIndex, acceptedIndex,
                    submittedIndex, flushedIndex, appliedIndex, durableLogs,
                    membershipVars, electionVars, match, staleResponseSeen>>

ApplyCommitted(n) ==
    /\ up[n]
    /\ appliedIndex[n] < durableCommit[n]
    /\ appliedIndex' = [appliedIndex EXCEPT ![n] = durableCommit[n]]
    /\ commands' = [commands EXCEPT ![n] = {}]
    /\ UNCHANGED <<up, voteVars, logs, commitIndex, acceptedIndex,
                    submittedIndex, flushedIndex, durableLogs, durableCommit,
                    membershipVars, electionVars, match, staleResponseSeen>>

(***************************************************************************)
(* Crash loses volatile Engine/Core state. Restart reads only completed     *)
(* durable state and derives membership/role.                              *)
(* Source: storage/helper.rs:59-91,173-217; engine_impl.rs:145-174.         *)
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
                    candidateConfigs, leaderConfigs, leaderGrants, match,
                    staleResponseSeen>>

Restart(n) ==
    /\ ~up[n]
    /\ LET ds == durableLogs[n]
           em == EffectiveEntry(ds)
           li == Len(ds) - 1
           selfLeader == durableVoteCommitted[n] /\ durableVoteNode[n] = n
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
    /\ UNCHANGED <<appliedIndex, durableLogs, durableCommit,
                    durableVoteTerm, durableVoteNode, durableVoteCommitted,
                    candidateTerm, candidateNode, candidateConfigs,
                    staleResponseSeen>>

(***************************************************************************)
(* Startup from a state already reconstructed by StorageHelper. This is    *)
(* the Engine::startup boundary used by trace validation.                  *)
(* Source: engine_impl.rs:145-174; vote_handler/mod.rs:168-239.            *)
(***************************************************************************)

RestartFromRecovered(n) ==
    /\ up[n]
    /\ voteCommitted[n]
    /\ voteNode[n] = n
    /\ n \in Voters(configs[n])
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
                    candidateConfigs, staleResponseSeen>>

Next ==
    \/ \E n \in Server : StartElection(n)
    \/ \E n \in Server : PersistVote(n)
    \/ \E n \in Server : SendVoteRequests(n)
    \/ \E n,cand \in Server, t \in 0..MaxTerm, c \in BOOLEAN,
          li \in -1..MaxIndex : ReceiveVoteRequest(n,cand,t,c,li)
    \/ \E n,peer \in Server, t \in 0..MaxTerm, owner \in Server :
          ReceiveVoteResponse(n,peer,t,owner,FALSE)
    \/ \E n \in Server, kind \in EntryKinds,
          cfg \in SUBSET (SUBSET Server), lrn \in SUBSET Server :
          LeaderAppend(n,kind,cfg,lrn)
    \/ \E n,owner \in Server, t \in 0..MaxTerm,
          prev \in -1..MaxIndex, count \in 1..MaxIndex :
          ReceiveAppendDirect(n,owner,t,prev,count)
    \/ \E n \in Server : SubmitLog(n) \/ FlushLog(n) \/ SendAppendSuccess(n)
    \/ \E n,peer \in Server, idx \in -1..MaxIndex :
          AcknowledgeReplication(n,peer,idx)
    \/ \E n,peer \in Server, sess \in -1..MaxIndex :
          DropStaleResponse(n,peer,sess)
    \/ \E n \in Server : SaveCommit(n) \/ ApplyCommitted(n) \/ Crash(n) \/ Restart(n)

Spec == Init /\ [][Next]_allVars

(***************************************************************************)
(* Invariants.                                                             *)
(***************************************************************************)

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

====
