---- MODULE MC ----
(***************************************************************************)
(* Bounded exploration wrapper for the updated reference model.            *)
(* Counters bound initiating/fault actions (elections, transfers, client   *)
(* and membership proposals, crashes, stale responses); reactive network  *)
(* delivery, persistence and acknowledgement are unbounded.  Node roles   *)
(* are canonical: ElectNodes start ordinary elections, TransferTargets    *)
(* receive TransferLeader(to=self) with `from` = their current committed   *)
(* (leader) vote.  Initial voters {1,2}; node 3 starts as a learner.       *)
(***************************************************************************)

EXTENDS base

CONSTANTS ElectionLimit, TransferLimit, AppendLimit, MembershipLimit,
          CrashLimit, StaleLimit,
          ElectNodes, TransferTargets, CrashNodes

ASSUME ElectNodes \subseteq Server
ASSUME TransferTargets \subseteq Server
ASSUME CrashNodes \subseteq Server

VARIABLES electionCount, transferCount, appendCount, membershipCount,
          crashCount, staleCount

mcVars == <<electionCount, transferCount, appendCount, membershipCount,
            crashCount, staleCount>>

vars == <<allVars, mcVars>>

MCInit ==
    /\ Init
    /\ electionCount = 0
    /\ transferCount = 0
    /\ appendCount = 0
    /\ membershipCount = 0
    /\ crashCount = 0
    /\ staleCount = 0

MCElect(n) ==
    /\ n \in ElectNodes
    /\ electionCount < ElectionLimit
    /\ DoStartElection(n)
    /\ electionCount' = electionCount + 1
    /\ UNCHANGED <<transferCount, appendCount, membershipCount, crashCount, staleCount>>

\* UPDATE-MAP code: core/raft_core.rs:1190-1202; raft/mod.rs:635-703
\*            update: Update!AffectedActions
\* The application calls transfer_leader(from = leader vote, to) on every node;
\* the target's RaftCore handles it once its vote equals `from`.
MCTransferLeader(n) ==
    /\ n \in TransferTargets
    /\ transferCount < TransferLimit
    /\ voteCommitted[n]
    /\ DoTransferLeader(n, voteTerm[n], voteNode[n], TRUE, n)
    /\ transferCount' = transferCount + 1
    /\ UNCHANGED <<electionCount, appendCount, membershipCount, crashCount, staleCount>>

MCPersistVote(n) == DoPersistVote(n) /\ UNCHANGED mcVars
MCSendVote(n) == DoSendVote(n) /\ UNCHANGED mcVars
MCVoteRequest(n, m) == DoVoteRequest(n, m) /\ UNCHANGED mcVars
\* Exploration bound (not behaviour): a winning response appends the leader's blank
\* entry (base!ReceiveVoteResponse); it is explored only while that entry fits MaxIndex.
MCVoteResponse(n, r) ==
    /\ DoVoteResponse(n, r)
    /\ Len(logs'[n]) <= MaxIndex + 1
    /\ UNCHANGED mcVars

MCDataAppend(n) ==
    /\ appendCount < AppendLimit
    /\ DoLeaderAppend(n, "data", configs[n], learners[n])
    /\ appendCount' = appendCount + 1
    /\ UNCHANGED <<electionCount, transferCount, membershipCount, crashCount, staleCount>>

MCAddLearner(n) ==
    /\ membershipCount < MembershipLimit
    /\ 3 \in Server
    /\ 3 \notin Voters(configs[n]) \cup learners[n]
    /\ DoLeaderAppend(n, "learner", configs[n], learners[n] \cup {3})
    /\ membershipCount' = membershipCount + 1
    /\ UNCHANGED <<electionCount, transferCount, appendCount, crashCount, staleCount>>

MCJoint(n) ==
    /\ membershipCount < MembershipLimit
    /\ {1,2,3} \subseteq Server
    /\ Cardinality(configs[n]) = 1
    /\ {2,3} \notin configs[n]
    /\ DoLeaderAppend(n, "joint", {Voters(configs[n]), {2,3}},
                      learners[n] \ {2,3})
    /\ membershipCount' = membershipCount + 1
    /\ UNCHANGED <<electionCount, transferCount, appendCount, crashCount, staleCount>>

MCUniform(n) ==
    /\ membershipCount < MembershipLimit
    /\ Cardinality(configs[n]) = 2
    /\ {2,3} \in configs[n]
    /\ DoLeaderAppend(n, "uniform", {{2,3}}, learners[n] \ {2,3})
    /\ membershipCount' = membershipCount + 1
    /\ UNCHANGED <<electionCount, transferCount, appendCount, crashCount, staleCount>>

MCFollowerAppend(n, o, c) == DoAppend(n, o, c) /\ UNCHANGED mcVars
MCSubmit(n) == NoNet(SubmitLog(n)) /\ UNCHANGED mcVars
MCFlush(n) == NoNet(FlushLog(n)) /\ UNCHANGED mcVars
MCRespond(n) == DoRespond(n) /\ UNCHANGED mcVars
MCSaveCommit(n) == NoNet(SaveCommit(n)) /\ UNCHANGED mcVars
MCApply(n) == NoNet(ApplyCommitted(n)) /\ UNCHANGED mcVars
MCAck(n, r) == DoAck(n, r) /\ UNCHANGED mcVars

MCStale(n, peer) ==
    /\ staleCount < StaleLimit
    /\ NoNet(DropStaleResponse(n, peer, effectiveIndex[n] - 1))
    /\ staleCount' = staleCount + 1
    /\ UNCHANGED <<electionCount, transferCount, appendCount, membershipCount, crashCount>>

MCCrash(n) ==
    /\ n \in CrashNodes
    /\ crashCount < CrashLimit
    /\ DoCrash(n)
    /\ crashCount' = crashCount + 1
    /\ UNCHANGED <<electionCount, transferCount, appendCount, membershipCount, staleCount>>

MCRestart(n) == NoNet(Restart(n)) /\ UNCHANGED mcVars

MCNext ==
    \/ \E n \in Server : MCElect(n) \/ MCTransferLeader(n)
    \/ \E n \in Server : MCPersistVote(n) \/ MCSendVote(n)
    \/ \E n \in Server, m \in voteReqs : MCVoteRequest(n, m)
    \/ \E n \in Server, r \in voteResps : MCVoteResponse(n, r)
    \/ \E n \in Server : MCDataAppend(n) \/ MCAddLearner(n) \/ MCJoint(n) \/ MCUniform(n)
    \/ \E n, o \in Server, c \in 1..MaxIndex : MCFollowerAppend(n, o, c)
    \/ \E n \in Server : MCSubmit(n) \/ MCFlush(n) \/ MCRespond(n)
    \/ \E n \in Server : MCSaveCommit(n) \/ MCApply(n)
    \/ \E n \in Server, r \in appendResps : MCAck(n, r)
    \/ \E n, peer \in Server : MCStale(n, peer)
    \/ \E n \in Server : MCCrash(n) \/ MCRestart(n)

MCSpec == MCInit /\ [][MCNext]_vars

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
