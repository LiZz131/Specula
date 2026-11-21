---- MODULE E1 ----
(* Divergence evidence for P-U1 ElectionInitiatorIsVoter / CandidateIsVoterOfSnapshot.
   Pre-state S0 (constructed, mirrors the validated transfer scenario): node 1 is leader
   with committed vote (1,1); node 2 (voter) and node 3 (learner) accepted that vote and
   the blank entry (1,1)@1.  One step: TransferLeader(from=(1,1,committed), to=Target)
   handled at Target.  Target=3 is the separating transition, Target=2 the control. *)
EXTENDS Update
CONSTANT Target
Ent1 == NewEntry(1, 1, "blank", {{1,2}}, {3})
S0Logs == [n \in Server |-> <<InitEntry, Ent1>>]
E1Init ==
    /\ up = [n \in Server |-> TRUE]
    /\ voteTerm = [n \in Server |-> 1]
    /\ voteNode = [n \in Server |-> 1]
    /\ voteCommitted = [n \in Server |-> TRUE]
    /\ lastSeenTerm = voteTerm /\ lastSeenNode = voteNode /\ lastSeenCommitted = voteCommitted
    /\ durableVoteTerm = voteTerm /\ durableVoteNode = voteNode /\ durableVoteCommitted = voteCommitted
    /\ role = [n \in Server |-> IF n = 1 THEN "Leader" ELSE IF n = 2 THEN "Follower" ELSE "Learner"]
    /\ logs = S0Logs
    /\ commitIndex = [n \in Server |-> IF n = 1 THEN 1 ELSE 0]
    /\ acceptedIndex = [n \in Server |-> 1] /\ submittedIndex = acceptedIndex /\ flushedIndex = acceptedIndex
    /\ appliedIndex = [n \in Server |-> 0]
    /\ durableLogs = logs /\ durableCommit = [n \in Server |-> 0]
    /\ effectiveIndex = [n \in Server |-> 0] /\ committedMembershipIndex = effectiveIndex
    /\ configs = [n \in Server |-> {{1,2}}] /\ committedConfigs = configs
    /\ learners = [n \in Server |-> {3}]
    /\ candidate = [n \in Server |-> FALSE]
    /\ candidateTerm = [n \in Server |-> IF n = 1 THEN 1 ELSE 0]
    /\ candidateNode = [n \in Server |-> IF n = 1 THEN 1 ELSE NoNode]
    /\ candidateConfigs = configs
    /\ candidateLast = [n \in Server |-> NoLogId]
    /\ granters = [n \in Server |-> {}]
    /\ leader = [n \in Server |-> n = 1]
    /\ leaderConfigs = configs
    /\ leaderGrants = [n \in Server |-> IF n = 1 THEN {1,2} ELSE {}]
    /\ match = [n \in Server |-> [p \in Server |-> IF n = 1 THEN 1 ELSE IF p = n THEN 0 ELSE -1]]
    /\ pendingVoteSave = [n \in Server |-> FALSE] /\ pendingVoteSend = pendingVoteSave
    /\ commands = [n \in Server |-> {}]
    /\ staleResponseSeen = FALSE
    /\ voteReqs = {} /\ voteResps = {} /\ appendResps = {}
    /\ electionCount = 1 /\ transferCount = 0 /\ appendCount = 0
    /\ membershipCount = 0 /\ crashCount = 0 /\ staleCount = 0
E1Next == MCTransferLeader(Target)
E1Spec == E1Init /\ [][E1Next]_vars
\* State-level evaluation of the old and new candidate-related properties on S0 and S1.
Old == INSTANCE OldBase
StateReport ==
    PrintT(<<"E1-state", "Target", Target,
             "candidate", candidate, "role", role,
             "Old!CandidateGrantSound", Old!CandidateGrantSound,
             "New!CandidateGrantSound", CandidateGrantSound,
             "New!CandidateIsVoterOfSnapshot", CandidateIsVoterOfSnapshot>>)
ReportInv == StateReport
====
