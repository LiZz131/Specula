---- MODULE MC ----
(***************************************************************************)
(* Neutral bounded exploration wrapper for the exact-old base model.       *)
(* Counters limit initiating/fault actions, not reactive persistence.       *)
(***************************************************************************)

EXTENDS base

CONSTANTS ElectionLimit, AppendLimit, MembershipLimit, AckLimit, CrashLimit,
          StaleLimit

VARIABLES electionCount, appendCount, membershipCount, ackCount,
          crashCount, staleCount

mcVars == <<electionCount, appendCount, membershipCount, ackCount,
            crashCount, staleCount>>

MCInit ==
    /\ Init
    /\ electionCount = 0
    /\ appendCount = 0
    /\ membershipCount = 0
    /\ ackCount = 0
    /\ crashCount = 0
    /\ staleCount = 0

MCElect(n) ==
    /\ electionCount < ElectionLimit
    /\ StartElection(n)
    /\ electionCount' = electionCount + 1
    /\ UNCHANGED <<appendCount, membershipCount, ackCount, crashCount, staleCount>>

MCPersistVote(n) == PersistVote(n) /\ UNCHANGED mcVars
MCSendVote(n) == SendVoteRequests(n) /\ UNCHANGED mcVars

MCVoteResponse(n, peer) ==
    /\ IF peer = n
       THEN /\ durableVoteTerm[n] = candidateTerm[n]
            /\ durableVoteNode[n] = candidateNode[n]
            /\ ~durableVoteCommitted[n]
       ELSE TRUE
    /\ ReceiveVoteResponse(n, peer, candidateTerm[n], candidateNode[n], FALSE)
    /\ UNCHANGED mcVars

MCVoteRequest(n, cand) ==
    /\ ReceiveVoteRequest(n, cand, 1, FALSE, LastIndex(n))
    /\ UNCHANGED mcVars

MCDataAppend(n) ==
    /\ appendCount < AppendLimit
    /\ LeaderAppend(n, "data", configs[n], learners[n])
    /\ appendCount' = appendCount + 1
    /\ UNCHANGED <<electionCount, membershipCount, ackCount, crashCount, staleCount>>

MCAddLearner(n) ==
    /\ membershipCount < MembershipLimit
    /\ 3 \in Server
    /\ LeaderAppend(n, "learner", configs[n], learners[n] \cup {3})
    /\ membershipCount' = membershipCount + 1
    /\ UNCHANGED <<electionCount, appendCount, ackCount, crashCount, staleCount>>

MCJoint(n) ==
    /\ membershipCount < MembershipLimit
    /\ {1,2,3} \subseteq Server
    /\ LeaderAppend(n, "joint", {Voters(configs[n]), {2,3}},
                    learners[n] \ {2,3})
    /\ membershipCount' = membershipCount + 1
    /\ UNCHANGED <<electionCount, appendCount, ackCount, crashCount, staleCount>>

MCUniform(n) ==
    /\ membershipCount < MembershipLimit
    /\ {2,3} \in configs[n]
    /\ LeaderAppend(n, "uniform", {{2,3}}, learners[n] \ {2,3})
    /\ membershipCount' = membershipCount + 1
    /\ UNCHANGED <<electionCount, appendCount, ackCount, crashCount, staleCount>>

MCFollowerAppend(n, owner) ==
    /\ appendCount < AppendLimit
    /\ ReceiveAppendDirect(n, owner, 1, LastIndex(n), 1)
    /\ appendCount' = appendCount + 1
    /\ UNCHANGED <<electionCount, membershipCount, ackCount, crashCount, staleCount>>

MCSubmit(n) == SubmitLog(n) /\ UNCHANGED mcVars
MCFlush(n) == FlushLog(n) /\ UNCHANGED mcVars
MCRespond(n) == SendAppendSuccess(n) /\ UNCHANGED mcVars
MCSaveCommit(n) == SaveCommit(n) /\ UNCHANGED mcVars
MCApply(n) == ApplyCommitted(n) /\ UNCHANGED mcVars

MCAck(n, peer) ==
    /\ ackCount < AckLimit
    /\ AcknowledgeReplication(n, peer, LastIndex(n))
    /\ ackCount' = ackCount + 1
    /\ UNCHANGED <<electionCount, appendCount, membershipCount, crashCount, staleCount>>

MCStale(n, peer) ==
    /\ staleCount < StaleLimit
    /\ DropStaleResponse(n, peer, effectiveIndex[n] - 1)
    /\ staleCount' = staleCount + 1
    /\ UNCHANGED <<electionCount, appendCount, membershipCount, ackCount, crashCount>>

MCCrash(n) ==
    /\ crashCount < CrashLimit
    /\ Crash(n)
    /\ crashCount' = crashCount + 1
    /\ UNCHANGED <<electionCount, appendCount, membershipCount, ackCount, staleCount>>

MCRestart(n) == Restart(n) /\ UNCHANGED mcVars

MCNext ==
    \* Canonical node identities remove symmetric schedules without changing
    \* the roles exercised by this three-node bound.
    \/ MCElect(1) \/ MCPersistVote(1) \/ MCPersistVote(2) \/ MCSendVote(1)
    \/ MCVoteResponse(1,1) \/ MCVoteResponse(1,2) \/ MCVoteRequest(2,1)
    \/ MCDataAppend(1) \/ MCAddLearner(1) \/ MCJoint(1) \/ MCUniform(1)
    \/ MCFollowerAppend(2,1)
    \/ MCSubmit(1) \/ MCSubmit(2) \/ MCFlush(1) \/ MCFlush(2)
    \/ MCRespond(2) \/ MCSaveCommit(1) \/ MCApply(1)
    \/ MCAck(1,2) \/ MCAck(1,3) \/ MCStale(1,2)
    \/ MCCrash(1) \/ MCRestart(1)

MCSpec == MCInit /\ [][MCNext]_<<allVars,mcVars>>

MCTypeOK == TypeOK
MCIOOrder == IOOrder
MCCommitWithinAccepted == CommitWithinAccepted
MCMembershipOrder == MembershipOrder
MCMembershipWellFormed == MembershipWellFormed
MCLearnersExcluded == LearnersExcluded
MCCandidateGrantSound == CandidateGrantSound
MCLeaderVoteCommitted == LeaderVoteCommitted
MCMatchWithinLeaderLog == MatchWithinLeaderLog
MCDurableStateBounded == DurableStateBounded
MCCurrentTermCommit == CurrentTermCommit
MCCommittedLogAgreement == CommittedLogAgreement

====
