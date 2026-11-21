---- MODULE MC ----
(***************************************************************************)
(* Bounded exploration wrapper for the updated base model.                 *)
(* Counters limit initiating/fault/API inputs; reactive persistence and    *)
(* message handling are unbounded (finite through the bounded inputs).     *)
(* R1/R2 network linkage lives here: vote requests come from voteReqs,     *)
(* remote grants from voteGrants after the responder's vote is durable,    *)
(* follower appends copy the next entry of a current leader whose log the  *)
(* follower prefixes, and acknowledgements require the peer to hold and    *)
(* have flushed the acknowledged prefix.                                   *)
(***************************************************************************)

EXTENDS base

CONSTANTS ElectionLimit, TransferLimit, AppendLimit, ReplicateLimit,
          MembershipLimit, AckLimit, CrashLimit, StaleLimit,
          ElectNodes, TransferSources, TransferTargets

VARIABLES electionCount, transferCount, appendCount, replicateCount,
          membershipCount, ackCount, crashCount, staleCount

mcVars == <<electionCount, transferCount, appendCount, replicateCount,
            membershipCount, ackCount, crashCount, staleCount>>

MCInit ==
    /\ Init
    /\ electionCount = 0
    /\ transferCount = 0
    /\ appendCount = 0
    /\ replicateCount = 0
    /\ membershipCount = 0
    /\ ackCount = 0
    /\ crashCount = 0
    /\ staleCount = 0

\* Tick / ExternalCommand election (pre-existing elect() callers).
MCElect(n) ==
    /\ electionCount < ElectionLimit
    /\ StartElection(n)
    /\ electionCount' = electionCount + 1
    /\ UNCHANGED <<transferCount, appendCount, replicateCount, membershipCount,
                   ackCount, crashCount, staleCount>>

\* UPDATE-MAP
\* code: raft/mod.rs:645-703 (Raft::transfer_leader), core/raft_core.rs:1190-1202
\* update: Update!AffectedActions
\* The public API forwards (from, to) to every node it is called on; `from`
\* is the transferring Leader's (committed) vote.  Only the receiving node's
\* own vote matters to the handler, so a delivered message has an effect iff
\* the receiver still holds that committed vote; the ignored branch is a
\* stutter and is omitted here (it is replayed by Trace.tla).
MCTransfer(n, to) ==
    /\ transferCount < TransferLimit
    /\ voteCommitted[n]
    /\ TransferLeader(n, voteTerm[n], voteNode[n], TRUE, to)
    /\ transferCount' = transferCount + 1
    /\ UNCHANGED <<electionCount, appendCount, replicateCount, membershipCount,
                   ackCount, crashCount, staleCount>>

MCPersistVote(n) == PersistVote(n) /\ UNCHANGED mcVars
MCSendVote(n) == SendVoteRequests(n) /\ UNCHANGED mcVars

\* R1: deliver an in-flight RequestVote to its destination.
MCVoteRequest(n) ==
    /\ \E m \in voteReqs :
          /\ m.dst = n
          /\ ReceiveVoteRequest(n, m.src, m.term, FALSE,
                                m.lastTerm, m.lastNode, m.lastIndex)
    /\ UNCHANGED mcVars

\* Self grant after SaveVote (raft_core.rs:1669-1681); remote grant only if
\* the peer accepted that vote and its vote I/O is flushed
\* (raft_core.rs:1112-1123).
MCVoteResponse(n, peer) ==
    /\ candidate[n]
    /\ IF peer = n
       THEN /\ selfRespPending[n]
            /\ durableVoteTerm[n] = candidateTerm[n]
            /\ durableVoteNode[n] = candidateNode[n]
            /\ ~durableVoteCommitted[n]
       ELSE \* R8: FIFO notification channel, the self response comes first.
            /\ ~selfRespPending[n]
            /\ [voter |-> peer, term |-> candidateTerm[n],
                node |-> candidateNode[n], committed |-> FALSE] \in voteGrants
            /\ VoteLE(candidateTerm[n], candidateNode[n], FALSE,
                      durableVoteTerm[peer], durableVoteNode[peer],
                      durableVoteCommitted[peer])
    \* Model bound only: the winning grant appends the leader blank entry
    \* (engine_impl.rs:247-249); keep it within MaxIndex (Case B, round 1).
    /\ (peer \in Voters(candidateConfigs[n])
        /\ Quorum(candidateConfigs[n], granters[n] \cup {peer})) => LastIndex(n) < MaxIndex
    /\ ReceiveVoteResponse(n, peer, candidateTerm[n], candidateNode[n], FALSE)
    /\ UNCHANGED mcVars

MCDataAppend(n) ==
    /\ appendCount < AppendLimit
    /\ LeaderAppend(n, "data", configs[n], learners[n])
    /\ appendCount' = appendCount + 1
    /\ UNCHANGED <<electionCount, transferCount, replicateCount, membershipCount,
                   ackCount, crashCount, staleCount>>

MCAddLearner(n) ==
    /\ membershipCount < MembershipLimit
    /\ 3 \in Server
    /\ 3 \notin Voters(configs[n])
    /\ LeaderAppend(n, "learner", configs[n], learners[n] \cup {3})
    /\ membershipCount' = membershipCount + 1
    /\ UNCHANGED <<electionCount, transferCount, appendCount, replicateCount,
                   ackCount, crashCount, staleCount>>

MCJoint(n) ==
    /\ membershipCount < MembershipLimit
    /\ {1,2,3} \subseteq Server
    /\ LeaderAppend(n, "joint", {Voters(configs[n]), {2,3}},
                    learners[n] \ {2,3})
    /\ membershipCount' = membershipCount + 1
    /\ UNCHANGED <<electionCount, transferCount, appendCount, replicateCount,
                   ackCount, crashCount, staleCount>>

MCUniform(n) ==
    /\ membershipCount < MembershipLimit
    /\ {2,3} \in configs[n]
    /\ LeaderAppend(n, "uniform", {{2,3}}, learners[n] \ {2,3})
    /\ membershipCount' = membershipCount + 1
    /\ UNCHANGED <<electionCount, transferCount, appendCount, replicateCount,
                   ackCount, crashCount, staleCount>>

\* R2: replicate the next entry of a current leader to a follower/learner.
MCFollowerAppend(n, ldr) ==
    /\ replicateCount < ReplicateLimit
    /\ n # ldr
    /\ leader[ldr] /\ voteCommitted[ldr]
    /\ LastIndex(n) < LastIndex(ldr)
    /\ LogIdsAgree(n, ldr, LastIndex(n))
    /\ ReceiveAppend(n, voteTerm[ldr], ldr, <<EntryAt(ldr, LastIndex(n) + 1)>>)
    /\ replicateCount' = replicateCount + 1
    /\ UNCHANGED <<electionCount, transferCount, appendCount, membershipCount,
                   ackCount, crashCount, staleCount>>

MCDropSelfResp(n) == DropSelfVoteResponse(n) /\ UNCHANGED mcVars
MCSubmit(n) == SubmitLog(n) /\ UNCHANGED mcVars
MCFlush(n) == FlushLog(n) /\ UNCHANGED mcVars
MCRespond(n) == SendAppendSuccess(n) /\ UNCHANGED mcVars
MCSaveCommit(n) == SaveCommit(n) /\ UNCHANGED mcVars
MCApply(n) == ApplyCommitted(n) /\ UNCHANGED mcVars

\* R2: an acknowledgement covers a prefix the peer holds and has flushed.
MCAck(n, peer) ==
    /\ ackCount < AckLimit
    /\ \E idx \in (match[n][peer] + 1)..LastIndex(n) :
          /\ flushedIndex[peer] >= idx
          /\ LogIdsAgree(n, peer, idx)
          /\ AcknowledgeReplication(n, peer, idx)
    /\ ackCount' = ackCount + 1
    /\ UNCHANGED <<electionCount, transferCount, appendCount, replicateCount,
                   membershipCount, crashCount, staleCount>>

MCStale(n, peer) ==
    /\ staleCount < StaleLimit
    /\ DropStaleResponse(n, peer, effectiveIndex[n] - 1)
    /\ staleCount' = staleCount + 1
    /\ UNCHANGED <<electionCount, transferCount, appendCount, replicateCount,
                   membershipCount, ackCount, crashCount>>

MCCrash(n) ==
    /\ crashCount < CrashLimit
    /\ Crash(n)
    /\ crashCount' = crashCount + 1
    /\ UNCHANGED <<electionCount, transferCount, appendCount, replicateCount,
                   membershipCount, ackCount, staleCount>>

MCRestart(n) == Restart(n) /\ UNCHANGED mcVars

MCNext ==
    \/ \E n \in ElectNodes : MCElect(n)
    \/ \E n \in TransferSources, to \in TransferTargets : MCTransfer(n, to)
    \/ \E n \in Server : MCPersistVote(n) \/ MCSendVote(n) \/ MCVoteRequest(n)
    \/ \E n, peer \in Server : MCVoteResponse(n, peer)
    \/ \E n \in Server : MCDropSelfResp(n)
    \/ \E n \in Server : MCDataAppend(n) \/ MCAddLearner(n) \/ MCJoint(n) \/ MCUniform(n)
    \/ \E n, ldr \in Server : MCFollowerAppend(n, ldr)
    \/ \E n \in Server : MCSubmit(n) \/ MCFlush(n) \/ MCRespond(n)
                         \/ MCSaveCommit(n) \/ MCApply(n)
    \/ \E n, peer \in Server : MCAck(n, peer) \/ MCStale(n, peer)
    \/ \E n \in Server : MCCrash(n) \/ MCRestart(n)

MCSpec == MCInit /\ [][MCNext]_<<allVars,mcVars>>

\* `commands` records the kinds emitted by the last Engine step for trace
\* validation; no guard or other assignment reads it, so excluding it from
\* fingerprints is sound for every property below that does not mention it.
MCView == <<up, voteVars, logVars, membershipVars, electionVars, match,
            staleResponseSeen, leaseEnabled, netVars, panicked, mcVars>>

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
MCLeaderCompleteness == LeaderCompleteness

====
