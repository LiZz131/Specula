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

\* REQ-EVIDENCE TypeOK
\* intent:   Each node's up flag, vote, last-seen vote, role, candidate and leader flags, configs, learners, commands and log length stay in their declared domains, and its commit, accepted, submitted, flushed, applied, effective-membership and match pointers stay within its log, with the committed-membership pointer at or before the effective one.
\* status:   model-internal
\* watch:    source/openraft/src/core/server_state.rs:ServerState; source/openraft/src/engine/command.rs:Command
\* verified: base
\* note:     type invariant; no requirement evidence was sought. Evidence for the conjuncts that also appear in MembershipWellFormed, LearnersExcluded, MembershipOrder and MatchWithinLeaderLog is recorded in those blocks.
\* review:   intent rewritten to what the formula checks: "every model variable" overstated it (the durable, candidate-term/node/config, granter, leader-config/grant, committed-config, pending-vote and stale-response variables are not constrained) and omitted the log-pointer bounds; note gained a pointer to where evidence for the shared conjuncts lives.
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

\* REQ-EVIDENCE IOOrder
\* intent:   On every node, the applied index never exceeds the saved committed index, and flushed <= submitted <= accepted <= last log index.
\* status:   requirement
\* evidence: doc source/openraft/src/docs/data/log_pointers.md:27 "`flushed` ≤ `submitted` ≤ `accepted`;" -> flushed <= submitted <= accepted
\* evidence: comment source/openraft/src/raft_state/io_state/io_progress.rs:25 "flushed <= submitted <= accepted" -> flushed <= submitted <= accepted (stated IOProgress invariant)
\* evidence: doc source/openraft/src/docs/data/log_pointers.md:24 "`accepted` is also known as `last_log` in Openraft codebase." -> accepted <= last log index
\* evidence: doc source/openraft/src/docs/data/log_pointers.md:15 "In raft only committed log entry can be applied." -> applied <= committed
\* evidence: history 942ec78b (message) "Save the committed log id to storage before Raft apply log entries." -> applied <= saved committed
\* evidence: comment source/openraft/src/engine/command.rs:76 "To `commit` logs, [`RaftLogStorage::save_committed()`] is called. And then committed logs" -> applied <= saved committed (save_committed precedes apply)
\* evidence: test source/openraft/src/engine/handler/following_handler/commit_entries_test.rs:81 test_following_handler_commit_entries_ge_accepted "Command::SaveCommitted {" -> SaveCommitted is emitted before Apply
\* evidence: impl source/openraft/src/raft_state/io_state/io_progress.rs:41 "less_equal!(&self.flushed, &self.submitted);"
\* evidence: impl source/openraft/src/core/raft_core.rs:1706 "self.log_store.save_committed(Some(committed)).await?;"
\* watch:    source/openraft/src/raft_state/io_state/io_progress.rs:IOProgress::validate; source/openraft/src/core/raft_core.rs:run_command; source/openraft/src/engine/command.rs:Command::Apply; source/openraft/src/storage/v2.rs:RaftLogStorage::save_committed
\* verified: base
\* review:   ok
IOOrder ==
    \A n \in Server :
      appliedIndex[n] <= durableCommit[n]
      /\ flushedIndex[n] <= submittedIndex[n]
      /\ submittedIndex[n] <= acceptedIndex[n]
      /\ acceptedIndex[n] <= LastIndex(n)

\* REQ-EVIDENCE CommitWithinAccepted
\* intent:   On every node, the committed log index never exceeds the node's accepted log index.
\* status:   requirement
\* evidence: doc source/openraft/src/docs/data/log_pointers.md:28 "`applied` ≤ `committed` ≤ `submitted`" -> committed <= submitted
\* evidence: doc source/openraft/src/docs/data/log_pointers.md:27 "`flushed` ≤ `submitted` ≤ `accepted`;" -> submitted <= accepted, hence committed <= accepted
\* evidence: doc source/openraft/src/docs/protocol/log_replication.md:111 "commit-index must not advance beyond the last known consistent log" -> commit never runs ahead of the log accepted from the current leader
\* evidence: history 90c29ccb (message) "allow followers to commit only those logs that have been replicated by their current leader" -> a follower commits only up to what it accepted
\* evidence: history 5a8b6758:openraft/src/engine/handler/following_handler/mod.rs:113 "A follower can only commit the entries that are replicated by the leader." -> follower commit is bounded by the entries it received
\* evidence: test source/openraft/src/engine/handler/following_handler/commit_entries_test.rs:71 test_following_handler_commit_entries_ge_accepted "assert_eq!(Some(&log_id(1, 1, 2)), eng.state.committed());" -> a leader commit beyond accepted is clamped to accepted
\* evidence: impl source/openraft/src/engine/handler/following_handler/mod.rs:164 "let committed = std::cmp::min(accepted, leader_committed);"
\* evidence: impl source/openraft/src/raft_state/mod.rs:177 "validit::less_equal!(self.committed(), self.last_log_id());"
\* watch:    source/openraft/src/engine/handler/following_handler/mod.rs:FollowingHandler::commit_entries; source/openraft/src/engine/handler/replication_handler/mod.rs:ReplicationHandler::try_commit_quorum_accepted; source/openraft/src/raft_state/mod.rs:RaftState::update_committed; source/openraft/src/raft_state/mod.rs:RaftState::validate; source/openraft/src/storage/helper.rs:StorageHelper::get_initial_state
\* verified: base
\* note:     the min(accepted, leader_committed) clamp was traced with log -S to 90c29ccb, whose message gives the reason; the comment it removed is quoted from its parent 5a8b6758.
\* review:   ok
CommitWithinAccepted ==
    \A n \in Server : commitIndex[n] <= acceptedIndex[n]

\* REQ-EVIDENCE MembershipOrder
\* intent:   On every node, the committed membership config is never later in the log than the effective membership config.
\* status:   requirement
\* evidence: comment source/openraft/src/raft_state/membership_state/mod.rs:29 "the second last one must have been committed." -> the committed config is at or before the effective one
\* evidence: comment source/openraft/src/raft_state/membership_state/mod.rs:23 "The first(committed) one must have been committed" -> two configs are kept: committed first, effective second
\* evidence: doc source/openraft/src/docs/data/effective-membership.md:16 "The second to last membership log has to be committed." -> the committed config is at or before the effective one
\* evidence: doc source/openraft/src/docs/data/extended-membership.md:89 "A leader can propose new membership only after the previous one has been" -> at most one uncommitted config, placed after the committed one
\* evidence: comment source/openraft/src/storage/helper.rs:176 "The first one must be committed, because raft allows to propose new membership only when" -> restart rebuilds the committed-then-effective order
\* evidence: test source/openraft/src/raft_state/membership_state/membership_state_test.rs:133 test_membership_state_commit "assert_eq!(&Some(log_id(2, 1, 2)), ms.committed().log_id());" -> committed config does not move while commit is below the effective config
\* evidence: impl source/openraft/src/raft_state/membership_state/mod.rs:222 "validit::less_equal!(self.committed.log_id(), self.effective.log_id());"
\* watch:    source/openraft/src/raft_state/membership_state/mod.rs:MembershipState::commit; source/openraft/src/raft_state/membership_state/mod.rs:MembershipState::append; source/openraft/src/raft_state/membership_state/mod.rs:MembershipState::truncate; source/openraft/src/raft_state/membership_state/mod.rs:MembershipState::validate; source/openraft/src/raft_state/membership_state/change_handler.rs:ChangeHandler::ensure_committed; source/openraft/src/storage/helper.rs:StorageHelper::get_membership
\* verified: base
\* review:   ok
MembershipOrder ==
    \A n \in Server : committedMembershipIndex[n] <= effectiveIndex[n]

\* REQ-EVIDENCE MembershipWellFormed
\* intent:   Every node's effective membership is a joint of one or more voter configs, none of them empty, over known node ids.
\* status:   mixed
\* evidence: comment source/openraft/src/membership/membership.rs:198 "- No empty sub-config in it." -> no voter config is empty
\* evidence: contract source/openraft/src/membership/membership.rs:124 "The returned `Vec` contains one or more configs(currently it is two)." -> at least one config
\* evidence: contract source/openraft/src/error.rs:610 "new membership can not be empty" -> a proposed membership must not be empty
\* evidence: test source/openraft/src/membership/membership.rs:419 test_membership_change "assert_eq!(Err(ChangeMembershipError::EmptyMembership(EmptyMembership {})), res);" -> a change that empties the voters is rejected
\* evidence: comment source/openraft/src/raft_state/membership_state/change_handler.rs:29 "ensures that the cluster will have at least one voter in the new membership" -> a changed membership keeps at least one voter
\* evidence: impl source/openraft/src/membership/membership.rs:207 "pub(crate) fn ensure_non_empty_config(&self) -> Result<(), EmptyMembership> {"
\* watch:    source/openraft/src/membership/membership.rs:Membership::ensure_valid; source/openraft/src/membership/membership.rs:Membership::ensure_non_empty_config; source/openraft/src/membership/membership.rs:Membership::change; source/openraft/src/raft_state/membership_state/change_handler.rs:ChangeHandler::apply; source/openraft/src/error.rs:EmptyMembership
\* verified: base
\* clause non-empty: requirement — conjuncts cfg # {} and child # {}; membership.rs:198, membership.rs:124, error.rs:610 and test_membership_change state or check that configs are non-empty
\* clause node-domain: model-internal — conjunct cfg \subseteq SUBSET Server; node ids range over the model constant Server, no source counterpart
\* note:     membership.rs:20 derives Default for Membership (an empty joint config), so the "one or more configs" statement at membership.rs:124 is the only source found for "at least one config".
\* review:   narrowed the arrows of error.rs:610 and change_handler.rs:29, which state that a new membership is non-empty (has a voter), not that every voter config in it is non-empty; status and clauses unchanged.
MembershipWellFormed ==
    \A n \in Server : ValidConfigs(configs[n])

\* REQ-EVIDENCE LearnersExcluded
\* intent:   On every node, no node is both a learner and a voter of the effective membership.
\* status:   requirement
\* evidence: contract source/openraft/src/membership/membership.rs:145 "Returns an Iterator of all learner node ids. Voters are not included." -> learners exclude voters
\* evidence: comment source/openraft/src/membership/membership.rs:32 "A node-id key that is in `nodes` but is not in `configs` is a **learner**." -> a learner is by definition in no voter config
\* evidence: contract source/openraft/src/membership/membership.rs:102 "A node id that is in `nodes` but is not in `config` is a **learner**." -> same definition on the public constructor
\* evidence: impl source/openraft/src/membership/membership.rs:147 "self.nodes.keys().filter(|x| !self.is_voter(x)).copied()"
\* watch:    source/openraft/src/membership/membership.rs:Membership::learner_ids; source/openraft/src/membership/membership.rs:Membership::is_voter; source/openraft/src/membership/membership.rs:Membership::change; source/openraft/src/engine/engine_impl.rs:Engine::new_candidate
\* verified: base
\* review:   ok
LearnersExcluded ==
    \A n \in Server : learners[n] \cap Voters(configs[n]) = {}

\* REQ-EVIDENCE CandidateGrantSound
\* intent:   A node in the Leader role holds a committed vote for itself, and its leadership was granted by a quorum.
\* status:   requirement
\* evidence: comment source/openraft/src/raft_state/mod.rs:375 "Leadership is granted by a quorum and the vote is committed." -> leader = quorum-granted, committed vote
\* evidence: comment source/openraft/src/proposer/leader.rs:25 "When the leader's vote is committed, i.e., granted by a quorum," -> a committed vote means a quorum grant
\* evidence: doc source/openraft/src/docs/data/vote.md:59 "is a leader if it is **present** in config" -> the Leader role goes with a committed vote naming the node itself (vote.md:58)
\* evidence: doc source/raft-essentials.md:53 "a candidate wins an election if it receives votes from a majority" -> leadership needs a majority grant
\* evidence: test source/openraft/src/engine/tests/handle_vote_resp_test.rs:167 test_handle_vote_resp "assert_eq!(ServerState::Candidate, eng.state.server_state);" -> grants short of a quorum leave the node Candidate
\* evidence: test source/openraft/src/engine/tests/handle_vote_resp_test.rs:193 test_handle_vote_resp_equal_vote "assert_eq!(Vote::new_committed(2, 1), *eng.state.vote_ref(),);" -> a quorum grant commits the node's own vote
\* evidence: test source/openraft/src/engine/tests/handle_vote_resp_test.rs:213 test_handle_vote_resp_equal_vote "assert_eq!(ServerState::Leader, eng.state.server_state);" -> only then is the node Leader
\* evidence: impl source/openraft/src/raft_state/mod.rs:382 "self.is_leading(id) && self.vote.is_committed()"
\* evidence: impl source/openraft/src/engine/engine_impl.rs:375 "let quorum_granted = candidate.grant_by(&target);"
\* evidence: impl source/openraft/src/engine/engine_impl.rs:136 "membership.to_quorum_set(),"
\* evidence: impl source/openraft/src/engine/engine_impl.rs:642 "Vote is granted by a quorum, leader established."
\* evidence: impl source/openraft/src/proposer/candidate.rs:106 "Mark the vote as committed, i.e., being granted and saved by a quorum."
\* watch:    source/openraft/src/engine/engine_impl.rs:Engine::handle_vote_resp; source/openraft/src/engine/engine_impl.rs:Engine::establish_leader; source/openraft/src/engine/engine_impl.rs:Engine::new_candidate; source/openraft/src/proposer/candidate.rs:Candidate::grant_by; source/openraft/src/proposer/candidate.rs:Candidate::into_leader; source/openraft/src/raft_state/mod.rs:RaftState::is_leader; source/openraft/src/raft_state/mod.rs:RaftState::calc_server_state; source/openraft/src/engine/handler/vote_handler/mod.rs:VoteHandler::become_leader; source/openraft/src/quorum/joint.rs:is_quorum
\* verified: base
\* note:     which voter configs the quorum is counted in is found only in impl (engine_impl.rs:130-137 copies the effective membership's quorum set into the candidate). vote_handler/mod.rs:184-185 says a node may also become leader through a vote committed by another node's election, and 36d2c115 (message) says a Leader can be re-created upon startup; no source names the granters in those cases.
\* review:   retyped engine_impl.rs:642 (doc line summarising establish_leader) and candidate.rs:106 (narrates the into_committed() call below it) from comment to impl; raft_state/mod.rs:375, leader.rs:25, vote.md:59, raft-essentials.md:53 and the tests still support the whole intent, so status is unchanged.
CandidateGrantSound ==
    \A n \in Server :
      role[n] = "Leader" => voteCommitted[n]
                            /\ voteNode[n] = n
                            /\ Quorum(leaderConfigs[n], leaderGrants[n])

\* REQ-EVIDENCE LeaderVoteCommitted
\* intent:   A node in the Leader role has leader state and a committed vote.
\* status:   requirement
\* evidence: comment source/openraft/src/proposer/leader.rs:27 "Then such a leader is the Leader in original raft." -> leading state plus committed vote is the Raft Leader (leader.rs:18-27)
\* evidence: comment source/openraft/src/proposer/leader.rs:25 "When the leader's vote is committed, i.e., granted by a quorum," -> the Leader has a committed vote
\* evidence: comment source/openraft/src/raft_state/mod.rs:375 "Leadership is granted by a quorum and the vote is committed." -> the Leader has a committed vote
\* evidence: history 36d2c115 (message) "Upon election completion, `Engine.candidate` is cleared, and a new `Leader` is assigned to `Engine.leader`." -> leader state is created when the node becomes Leader
\* evidence: test source/openraft/src/engine/tests/handle_vote_resp_test.rs:196 test_handle_vote_resp_equal_vote "eng.leader.as_ref().unwrap().noop_log_id" -> leader state exists once the node is Leader
\* evidence: test source/openraft/src/engine/tests/handle_vote_resp_test.rs:213 test_handle_vote_resp_equal_vote "assert_eq!(ServerState::Leader, eng.state.server_state);" -> server state is Leader together with the committed vote asserted at line 193
\* evidence: impl source/openraft/src/raft_state/mod.rs:345 "if self.is_leader(id) {"
\* evidence: impl source/openraft/src/engine/handler/vote_handler/mod.rs:217 "*self.leader = Some(Box::new(leader));"
\* evidence: impl source/openraft/src/engine/handler/vote_handler/mod.rs:178 "Enter Leader state(vote.node_id == self.id && vote.committed == true) ."
\* watch:    source/openraft/src/raft_state/mod.rs:RaftState::calc_server_state; source/openraft/src/raft_state/mod.rs:RaftState::is_leader; source/openraft/src/engine/handler/vote_handler/mod.rs:VoteHandler::update_internal_server_state; source/openraft/src/engine/handler/vote_handler/mod.rs:VoteHandler::become_leader; source/openraft/src/engine/handler/vote_handler/mod.rs:VoteHandler::become_following; source/openraft/src/engine/handler/server_state_handler/mod.rs:ServerStateHandler::update_server_state_if_changed; source/openraft/src/engine/engine_impl.rs:Engine::establish_leader; source/openraft/src/engine/engine_impl.rs:Engine::startup
\* verified: base
\* note:     the leader-state part rests on 36d2c115 (message, found with log -S'pub(crate) type LeaderState<C>'), leader.rs:18-27 and test_handle_vote_resp_equal_vote (lines 196 and 213); no code comment states it.
\* review:   retyped vote_handler/mod.rs:178 from comment to impl because it is the summary line of become_leader (lines 179-181 say it is not the election path), so it does not support the "only" its arrow claimed; leader.rs:25-27, raft_state/mod.rs:375, 36d2c115 and the tests still support the intent.
LeaderVoteCommitted ==
    \A n \in Server : role[n] = "Leader" => leader[n] /\ voteCommitted[n]

\* REQ-EVIDENCE MatchWithinLeaderLog
\* intent:   A leader never records any replication target, or itself, as matching beyond the leader's own last log index.
\* status:   mixed
\* evidence: doc source/openraft/src/docs/protocol/log_replication.md:156 "The Leader initializes the span as `[None, leader_last_log_index + 1]`." -> the matching search is bounded by the leader's last log index
\* evidence: doc source/openraft/src/docs/data/log_pointers.md:53 "The log indexes of a follower are always behind or equal the leader's `last_log`." -> a follower's matching log is <= the leader's last log
\* evidence: comment source/openraft/src/progress/entry/mod.rs:33 "max log index on the following node that might match the leader log." -> the matching search covers only target indexes that might match the leader log
\* evidence: doc source/openraft/src/docs/data/log_pointers.md:31 "because `committed` means a quorum flushed the log entry," -> a node, the leader included, counts as holding an entry only once it has flushed it
\* evidence: doc source/openraft/src/docs/data/log_pointers.md:27 "`flushed` ≤ `submitted` ≤ `accepted`;" -> the leader's flushed log, and so its own recorded match, is within its accepted log (= last_log, log_pointers.md:24)
\* evidence: impl source/openraft/src/progress/entry/mod.rs:275 "validit::less_equal!(self.matching.next_index(), self.searching_end);"
\* evidence: impl source/openraft/src/replication/mod.rs:856 "matching ({}) should be <= last_log_id ({})"
\* watch:    source/openraft/src/progress/entry/mod.rs:ProgressEntry::update_matching; source/openraft/src/progress/entry/mod.rs:ProgressEntry::validate; source/openraft/src/engine/handler/replication_handler/mod.rs:ReplicationHandler::update_matching; source/openraft/src/engine/handler/replication_handler/mod.rs:ReplicationHandler::rebuild_progresses; source/openraft/src/replication/mod.rs:debug_assert_partial_success; source/openraft/src/core/raft_core.rs:run_command
\* verified: base
\* clause target-progress: requirement — log_replication.md:156, log_pointers.md:53 and progress/entry/mod.rs:33 bound a leader's recorded matching for its replication targets by its last log index
\* clause self-progress: requirement — log_pointers.md:31 counts a node toward an entry only once flushed, and log_pointers.md:27 and :24 keep the flushed log within the accepted (= last) log
\* clause non-leader-records: model-internal — the quantifier also covers nodes that are not leaders; the source keeps replication progress only inside the Leader state (proposer/leader.rs), so there is no source counterpart
\* review:   the intent includes the leader's own entry but no cited non-impl line covered it, so I added log_pointers.md:31 and :27 (same file as the cited :53) and split the requirement clause into target-progress and self-progress; also narrowed the progress/entry/mod.rs:33 arrow, which defines searching_end, not matching.
MatchWithinLeaderLog ==
    \A n,p \in Server : match[n][p] <= LastIndex(n)

\* REQ-EVIDENCE DurableStateBounded
\* intent:   On every node, the saved committed index never points past the persisted log, and the persisted vote is never greater than the current vote.
\* status:   requirement
\* evidence: history 942ec78b (message) "re-apply log entries from the next index of last applied log id to the" -> on restart, entries up to the saved committed id are read back from the log
\* evidence: contract source/openraft/src/storage/v2.rs:34 "must **NOT** apply a latter" -> a later save_committed takes effect only after earlier appends complete
\* evidence: doc source/openraft/src/docs/data/log_pointers.md:34 "`committed` ≤ `submitted` always hold" -> entries up to committed are already submitted when SaveCommitted is issued
\* evidence: doc source/openraft/src/docs/data/vote.md:16 "grant a `Vote` only if it is greater than or equal to the last `Vote`" -> the vote never decreases
\* evidence: contract source/openraft/src/storage/v2.rs:35 "write request before a former write request is completed. This rule applies to both" -> vote writes take effect in order, so the persisted vote lags the current one
\* evidence: impl source/openraft/src/storage/helper.rs:98 "let entries = log_reader.try_get_log_entries(start..end).await?;"
\* evidence: impl source/openraft/src/engine/handler/vote_handler/mod.rs:157 "self.output.push_command(Command::SaveVote { vote: *vote });"
\* evidence: impl source/openraft/src/engine/handler/vote_handler/mod.rs:119 "It grants the input vote and persists it if `input_vote >= my_vote`."
\* watch:    source/openraft/src/storage/helper.rs:StorageHelper::get_initial_state; source/openraft/src/storage/v2.rs:RaftLogStorage::save_committed; source/openraft/src/storage/v2.rs:RaftLogStorage::save_vote; source/openraft/src/storage/v2.rs:RaftLogStorage::append; source/openraft/src/core/raft_core.rs:run_command; source/openraft/src/engine/handler/vote_handler/mod.rs:VoteHandler::update_vote; source/openraft/src/engine/handler/replication_handler/mod.rs:ReplicationHandler::try_commit_quorum_accepted
\* verified: base
\* note:     no single source states the saved-committed bound; it is inferred from 942ec78b, storage/v2.rs:34-35 and log_pointers.md:34 together. log_pointers.md:30 says "`committed` ≤ `flushed` does not have to hold"; that sentence is about the in-memory committed and was not counted against this bound.
\* review:   retyped vote_handler/mod.rs:119 from comment to impl because it only describes what update_vote does (grant, then persist, when input_vote >= my_vote); vote.md:16 (with its save_vote pseudocode at vote.md:21-27) and storage/v2.rs:35 still support the vote part, so status is unchanged.
DurableStateBounded ==
    \A n \in Server :
       durableCommit[n] <= Len(durableLogs[n]) - 1
       /\ VoteLE(durableVoteTerm[n], durableVoteNode[n], durableVoteCommitted[n],
                 voteTerm[n], voteNode[n], voteCommitted[n])

\* REQ-EVIDENCE CurrentTermCommit
\* intent:   On a leader, the entry at the commit index never has a term greater than the leader's current vote term.
\* status:   requirement
\* evidence: comment source/openraft/src/engine/handler/replication_handler/mod.rs:221 "In raft a log that is granted and in the leader term is committed." -> a leader commits only entries of its own term
\* evidence: comment source/openraft/src/engine/handler/replication_handler/mod.rs:224 "Only when the log id is proposed by current leader, it is committed." -> the committed entry carries the current leader id
\* evidence: comment source/openraft/src/engine/handler/replication_handler/mod.rs:198 "A committed is **granted** and also is in current term." -> the committed entry is in the current term
\* evidence: comment source/openraft/src/raft_state/mod.rs:56 "replicated to a quorum of the cluster and it is of the term" -> committed log is of the leader's term (with line 57)
\* evidence: doc source/openraft/src/docs/data/log_pointers.md:17 "granted by a quorum and at the leader's term" -> committed is at the leader's term
\* evidence: doc source/openraft/src/docs/data/vote.md:16 "grant a `Vote` only if it is greater than or equal to the last `Vote`" -> the leader's vote term does not decrease after the commit
\* evidence: test source/openraft/src/engine/handler/replication_handler/update_matching_test.rs:91 test_update_matching "quorum-ed: (1,2), not at leader vote, not committed" -> a quorum-accepted entry of an older leader is not committed
\* evidence: impl source/openraft/src/engine/handler/replication_handler/mod.rs:226 "if !self.state.vote_ref().is_same_leader(c.committed_leader_id()) {"
\* watch:    source/openraft/src/engine/handler/replication_handler/mod.rs:ReplicationHandler::try_commit_quorum_accepted; source/openraft/src/engine/handler/replication_handler/mod.rs:ReplicationHandler::update_matching; source/openraft/src/vote/vote.rs:Vote::is_same_leader; source/openraft/src/raft_state/mod.rs:RaftState::update_committed
\* verified: base
\* note:     the sources state the commit-time rule (a newly committed entry is of the leader's own term and leader id); the intent keeps only the term upper bound, which that rule together with vote.md:16 implies.
\* review:   ok
CurrentTermCommit ==
    \A n \in Server :
      commitIndex[n] > 0 /\ leader[n]
      => EntryAt(n, commitIndex[n]).term <= voteTerm[n]

\* REQ-EVIDENCE CommittedLogAgreement
\* intent:   Any two nodes hold the same entry (same term and leader node) at every log index up to the smaller of their commit indexes.
\* status:   requirement
\* evidence: doc source/raft-essentials.md:84 "which will only ever happen to uncommitted log entries" -> committed entries are never overwritten
\* evidence: doc source/openraft/src/docs/data/extended-membership.md:154 "It's impossible for two leaders to both commit a log entry." -> two diverged leaders cannot both commit
\* evidence: doc source/openraft/src/docs/protocol/log_replication.md:5 "This ensures that committed logs are always visible to the next leader." -> later leaders carry earlier committed entries
\* evidence: doc source/openraft/src/docs/protocol/log_replication.md:114 "log entry that is **consistent** with the **current** leader." -> a node's commit index points only into the leader-consistent prefix
\* evidence: doc source/openraft/src/docs/data/leader_id.md:48 "only the last is valid and can commit logs" -> within one term only one leader id commits
\* evidence: doc source/raft-essentials.md:82 "creates at most one entry with a given log index in a given term" -> term, leader and index identify one entry
\* evidence: comment source/openraft/src/vote/leader_id/leader_id_adv.rs:11 "a `Leader` is actually identified by `(term," -> entries are compared by term and leader node
\* evidence: impl source/openraft/src/engine/handler/replication_handler/mod.rs:226 "if !self.state.vote_ref().is_same_leader(c.committed_leader_id()) {"
\* evidence: impl source/openraft/src/engine/handler/following_handler/mod.rs:164 "let committed = std::cmp::min(accepted, leader_committed);"
\* watch:    source/openraft/src/engine/handler/replication_handler/mod.rs:ReplicationHandler::try_commit_quorum_accepted; source/openraft/src/engine/handler/following_handler/mod.rs:FollowingHandler::append_entries; source/openraft/src/engine/handler/following_handler/mod.rs:FollowingHandler::ensure_log_consecutive; source/openraft/src/engine/handler/following_handler/mod.rs:FollowingHandler::truncate_logs; source/openraft/src/engine/handler/following_handler/mod.rs:FollowingHandler::commit_entries; source/openraft/src/engine/engine_impl.rs:Engine::handle_vote_req; source/openraft/src/engine/engine_impl.rs:Engine::handle_vote_resp; source/openraft/src/vote/vote.rs:PartialOrd for Vote; source/openraft/src/quorum/joint.rs:is_quorum
\* verified: base
\* review:   ok
CommittedLogAgreement ==
    \A a,b \in Server :
      \A i \in 0..Min2(commitIndex[a], commitIndex[b]) :
        EntryAt(a,i).term = EntryAt(b,i).term /\ EntryAt(a,i).node = EntryAt(b,i).node

====
