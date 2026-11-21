---- MODULE MC ----
(***************************************************************************)
(* Bounded exploration wrapper for the updated base model (artifact commit *)
(* d7176ef "update": RaftMsg::TransferLeader).                             *)
(*                                                                         *)
(* Counters limit initiating/fault actions (elections, transfers, client   *)
(* writes, membership proposals, crashes, stale responses), not reactive   *)
(* message handling or persistence.                                        *)
(*                                                                         *)
(* REPAIR of the prior (V0) MC framing. The V0 wrappers delivered vote     *)
(* responses from peers that never granted, vote requests with a fixed    *)
(* term 1 / candidate 1, follower appends from a fixed leader (1,1), and   *)
(* replication acks for entries a follower never received. That was       *)
(* harmless with a single election (V0 ElectionLimit = 1) but makes every  *)
(* multi-election check -- exactly what TransferLeader adds -- meaningless. *)
(* The framing below derives every inbound message from a real producer:   *)
(*  - VoteRequest: published by SendVote to the candidate's effective      *)
(*    voters except itself (core/raft_core.rs:1049-1108), carrying the     *)
(*    candidate vote and last LogId (engine_impl.rs:236-242).               *)
(*  - VoteResponse(grant): only after the granter has flushed exactly that *)
(*    vote (Respond{IOFlushed(vote)}, core/raft_core.rs:1112-1122); the    *)
(*    self grant is sent after SaveVote (core/raft_core.rs:1670-1682).     *)
(*  - AppendEntries: copied from a live leader's submitted log             *)
(*    (AppendInputEntries precedes Replicate in the FIFO command queue).   *)
(*  - Replication ack: only for a prefix the follower has flushed and that *)
(*    matches the leader log (flush-gated success, engine_impl.rs:431-439).*)
(*  - RaftCore handles the next input only after its queued SaveVote /     *)
(*    SendVote commands ran (run_engine_commands executes them inline,     *)
(*    core/raft_core.rs:1670-1712): wrapper guard Drained(n).              *)
(***************************************************************************)

EXTENDS base

CONSTANTS ElectionLimit, TransferLimit, AppendLimit, MembershipLimit,
          CrashLimit, StaleLimit,
          ElectNodes    \* nodes whose tick/ExternalCommand election is explored
                        \* (V0 used the canonical node 1 only)

VARIABLES electionCount, transferCount, appendCount, membershipCount,
          crashCount, staleCount,
          grantLog,     \* <<node, term, votedFor, committed>> votes a node has flushed
          voteReqs,     \* <<cand, term, lastTerm, lastNode, lastIndex, targets>>
          transferLog   \* <<node, term>> elections started by TransferLeader

counterVars == <<electionCount, transferCount, appendCount, membershipCount,
                 crashCount, staleCount>>
mcVars == <<counterVars, grantLog, voteReqs, transferLog>>

MCInit ==
    /\ Init
    /\ electionCount = 0
    /\ transferCount = 0
    /\ appendCount = 0
    /\ membershipCount = 0
    /\ crashCount = 0
    /\ staleCount = 0
    /\ grantLog = {}
    /\ voteReqs = {}
    /\ transferLog = {}

\* RaftCore processes the next input only after the previous batch of vote
\* commands executed (core/raft_core.rs:1670-1712).
Drained(n) == ~pendingVoteSave[n] /\ ~pendingVoteSend[n]

\* Leader l and follower n agree on the LogId of every entry up to idx.
PrefixAgree(n, l, idx) ==
    /\ idx <= LastIndex(n)
    /\ idx <= LastIndex(l)
    /\ \A i \in 0..idx : /\ EntryAt(n, i).term = EntryAt(l, i).term
                         /\ EntryAt(n, i).node = EntryAt(l, i).node

(***************************************************************************)
(* Elections                                                               *)
(***************************************************************************)

\* Tick / ExternalCommand::Elect: voter-guarded (base!StartElection).
MCElect(n) ==
    /\ electionCount < ElectionLimit
    /\ Drained(n)
    /\ StartElection(n)
    /\ electionCount' = electionCount + 1
    /\ UNCHANGED <<transferCount, appendCount, membershipCount, crashCount,
                   staleCount, grantLog, voteReqs, transferLog>>

\* UPDATE-MAP
\* code: openraft/src/core/raft_core.rs:1190-1202; openraft/src/raft/mod.rs:635-703
\* update: Update!AffectedActions
\* Environment: Raft::transfer_leader(from, to) is called on node `to` with
\* `from` = a Leader's committed vote (raft/mod.rs:635-650, t14 test uses
\* metrics.vote of the leader). Only the matching target branch changes
\* modeled state; the non-target / mismatching branch is a stutter on all
\* modeled variables (validated by trace, not enumerated here).
MCTransferLeader(n) ==
    /\ transferCount < TransferLimit
    /\ Drained(n)
    /\ voteCommitted[n]
    /\ TransferLeader(n, voteTerm[n], voteNode[n], voteCommitted[n], n)
    /\ transferCount' = transferCount + 1
    /\ transferLog' = transferLog \cup {<<n, voteTerm'[n]>>}
    /\ UNCHANGED <<electionCount, appendCount, membershipCount, crashCount,
                   staleCount, grantLog, voteReqs>>

\* SaveVote completes; the flushed vote is recorded, which is what enables
\* the (self or remote) vote response for it.
MCPersistVote(n) ==
    /\ PersistVote(n)
    /\ grantLog' = grantLog \cup
                   {<<n, voteTerm[n], voteNode[n], voteCommitted[n]>>}
    /\ UNCHANGED <<counterVars, voteReqs, transferLog>>

\* SendVote: one request per effective voter except self
\* (core/raft_core.rs:1049-1058). Drained() on inbound wrappers ensures the
\* log/vote here are those snapshotted by elect().
MCSendVote(n) ==
    /\ SendVoteRequests(n)
    /\ voteReqs' = voteReqs \cup
          {<<n, voteTerm[n], LastTerm(n), LastNode(n), LastIndex(n),
             Voters(configs[n]) \ {n}>>}
    /\ UNCHANGED <<counterVars, grantLog, transferLog>>

\* Peer n handles a published VoteRequest (engine_impl.rs:293-343). Only the
\* granting outcome changes modeled state; rejection is a no-op.
MCVoteRequest(n, cand) ==
    /\ Drained(n)
    /\ \E r \in voteReqs :
          /\ r[1] = cand
          /\ n \in r[6]
          /\ ReceiveVoteRequest(n, cand, r[2], FALSE, r[3], r[4], r[5])
    /\ UNCHANGED mcVars

\* Candidate n handles a granting VoteResponse from peer (self or remote).
\* The granter must have flushed exactly the candidate vote. The bound
\* LastIndex(n) < MaxIndex keeps the leader blank entry inside MaxIndex.
\* FIFO notifications: SaveVote sends the self VoteResponse into the
\* notification channel (core/raft_core.rs:1670-1682) before the queued
\* SendVote spawns the remote requests (engine_impl.rs:236-246 queues SaveVote
\* then SendVote; core/raft_core.rs:1049-1108), so the self grant is always
\* handled before any remote grant of the same candidacy. (REPAIR after the
\* CanaryLearnerLeader witness: without this order the model let a learner
\* candidate win on remote grants before its self-grant panics.)
MCVoteResponse(n, peer) ==
    /\ Drained(n)
    /\ LastIndex(n) < MaxIndex
    /\ peer = n \/ n \in granters[n]
    /\ <<peer, candidateTerm[n], candidateNode[n], FALSE>> \in grantLog
    /\ \/ ReceiveVoteResponse(n, peer, candidateTerm[n], candidateNode[n], FALSE)
       \/ CandidateGrantPanic(n, peer, candidateTerm[n], candidateNode[n], FALSE)
    /\ UNCHANGED mcVars

(***************************************************************************)
(* Client writes and membership proposals (bounded initiating actions)    *)
(***************************************************************************)

MCDataAppend(n) ==
    /\ appendCount < AppendLimit
    /\ Drained(n)
    /\ LeaderAppend(n, "data", configs[n], learners[n])
    /\ appendCount' = appendCount + 1
    /\ UNCHANGED <<electionCount, transferCount, membershipCount, crashCount,
                   staleCount, grantLog, voteReqs, transferLog>>

MCAddLearner(n) ==
    /\ membershipCount < MembershipLimit
    /\ Drained(n)
    /\ 3 \in Server
    /\ LeaderAppend(n, "learner", configs[n], learners[n] \cup {3})
    /\ membershipCount' = membershipCount + 1
    /\ UNCHANGED <<electionCount, transferCount, appendCount, crashCount,
                   staleCount, grantLog, voteReqs, transferLog>>

MCJoint(n) ==
    /\ membershipCount < MembershipLimit
    /\ Drained(n)
    /\ {1,2,3} \subseteq Server
    /\ LeaderAppend(n, "joint", {Voters(configs[n]), {2,3}},
                    learners[n] \ {2,3})
    /\ membershipCount' = membershipCount + 1
    /\ UNCHANGED <<electionCount, transferCount, appendCount, crashCount,
                   staleCount, grantLog, voteReqs, transferLog>>

MCUniform(n) ==
    /\ membershipCount < MembershipLimit
    /\ Drained(n)
    /\ {2,3} \in configs[n]
    /\ LeaderAppend(n, "uniform", {{2,3}}, learners[n] \ {2,3})
    /\ membershipCount' = membershipCount + 1
    /\ UNCHANGED <<electionCount, transferCount, appendCount, crashCount,
                   staleCount, grantLog, voteReqs, transferLog>>

(***************************************************************************)
(* Replication (reactive)                                                  *)
(***************************************************************************)

\* Follower/learner n accepts the next entry of live leader l. The base
\* action appends entries of the leader's own term (no truncation), so the
\* wrapper only offers that shape: follower log is a matching prefix and the
\* leader's next entry is its own-term entry already submitted to storage.
MCFollowerAppend(n, l) ==
    /\ n # l
    /\ up[l]
    /\ leader[l]
    /\ voteCommitted[l]
    /\ voteNode[l] = l
    /\ n \in (Voters(configs[l]) \cup learners[l])
    /\ Drained(n)
    /\ LET prev == LastIndex(n) IN
       /\ prev < LastIndex(l)
       /\ prev + 1 <= submittedIndex[l]
       /\ PrefixAgree(n, l, prev)
       /\ EntryAt(l, prev + 1).term = voteTerm[l]
       /\ EntryAt(l, prev + 1).node = l
       /\ ReceiveAppendDirect(n, l, voteTerm[l], prev, 1)
    /\ UNCHANGED mcVars

MCSubmit(n) == SubmitLog(n) /\ UNCHANGED mcVars
MCFlush(n) == FlushLog(n) /\ UNCHANGED mcVars
MCRespond(n) == SendAppendSuccess(n) /\ UNCHANGED mcVars
MCSaveCommit(n) == SaveCommit(n) /\ UNCHANGED mcVars
MCApply(n) == ApplyCommitted(n) /\ UNCHANGED mcVars

\* Leader n receives a successful (possibly partial) append response from
\* peer: the peer flushed a prefix matching the leader log and had accepted
\* the leader's vote (or a later one, for a delayed response).
MCAck(n, peer) ==
    /\ peer # n
    /\ Drained(n)
    /\ VoteLE(voteTerm[n], n, TRUE,
              voteTerm[peer], voteNode[peer], voteCommitted[peer])
    /\ \E idx \in (match[n][peer] + 1)..Min2(flushedIndex[peer], LastIndex(n)) :
          /\ PrefixAgree(peer, n, idx)
          /\ AcknowledgeReplication(n, peer, idx)
    /\ UNCHANGED mcVars

MCStale(n, peer) ==
    /\ staleCount < StaleLimit
    /\ DropStaleResponse(n, peer, effectiveIndex[n] - 1)
    /\ staleCount' = staleCount + 1
    /\ UNCHANGED <<electionCount, transferCount, appendCount, membershipCount,
                   crashCount, grantLog, voteReqs, transferLog>>

(***************************************************************************)
(* Faults                                                                  *)
(***************************************************************************)

MCCrash(n) ==
    /\ crashCount < CrashLimit
    /\ Crash(n)
    /\ crashCount' = crashCount + 1
    /\ UNCHANGED <<electionCount, transferCount, appendCount, membershipCount,
                   staleCount, grantLog, voteReqs, transferLog>>

MCRestart(n) == Restart(n) /\ UNCHANGED mcVars

MCNext ==
    \/ \E n \in ElectNodes : MCElect(n)
    \/ \E n \in Server : MCTransferLeader(n)
    \/ \E n \in Server : MCPersistVote(n) \/ MCSendVote(n)
    \/ \E n, c \in Server : MCVoteRequest(n, c)
    \/ \E n, p \in Server : MCVoteResponse(n, p)
    \/ \E n \in Server : MCDataAppend(n) \/ MCAddLearner(n) \/ MCJoint(n)
                         \/ MCUniform(n)
    \/ \E n, l \in Server : MCFollowerAppend(n, l)
    \/ \E n \in Server : MCSubmit(n) \/ MCFlush(n) \/ MCRespond(n)
                         \/ MCSaveCommit(n) \/ MCApply(n)
    \/ \E n, p \in Server : MCAck(n, p) \/ MCStale(n, p)
    \/ \E n \in Server : MCCrash(n) \/ MCRestart(n)

MCVars == <<allVars, mcVars>>
MCSpec == MCInit /\ [][MCNext]_MCVars

\* `commands` records the kinds queued by the last Engine call; no guard and
\* no invariant other than its TypeOK domain reads it, so it is excluded from
\* state fingerprints (successors and properties do not depend on it).
MCView == <<up, voteVars, logVars, membershipVars, electionVars, match,
            staleResponseSeen, panicked, mcVars>>

\* REQ-EVIDENCE MCTypeOK  (alias of TypeOK in base.tla; its evidence block is attached to TypeOK there)
\* review:   ok
MCTypeOK == TypeOK
\* REQ-EVIDENCE MCIOOrder  (alias of IOOrder in base.tla; its evidence block is attached to IOOrder there)
\* review:   ok
MCIOOrder == IOOrder
\* REQ-EVIDENCE MCCommitWithinAccepted  (alias of CommitWithinAccepted in base.tla; its evidence block is attached to CommitWithinAccepted there)
\* review:   ok
MCCommitWithinAccepted == CommitWithinAccepted
\* REQ-EVIDENCE MCMembershipOrder  (alias of MembershipOrder in base.tla; its evidence block is attached to MembershipOrder there)
\* review:   ok
MCMembershipOrder == MembershipOrder
\* REQ-EVIDENCE MCMembershipWellFormed  (alias of MembershipWellFormed in base.tla; its evidence block is attached to MembershipWellFormed there)
\* review:   ok
MCMembershipWellFormed == MembershipWellFormed
\* REQ-EVIDENCE MCLearnersExcluded  (alias of LearnersExcluded in base.tla; its evidence block is attached to LearnersExcluded there)
\* review:   ok
MCLearnersExcluded == LearnersExcluded
\* REQ-EVIDENCE MCCandidateGrantSound  (alias of CandidateGrantSound in base.tla; its evidence block is attached to CandidateGrantSound there)
\* review:   ok
MCCandidateGrantSound == CandidateGrantSound
\* REQ-EVIDENCE MCLeaderVoteCommitted  (alias of LeaderVoteCommitted in base.tla; its evidence block is attached to LeaderVoteCommitted there)
\* review:   ok
MCLeaderVoteCommitted == LeaderVoteCommitted
\* REQ-EVIDENCE MCMatchWithinLeaderLog  (alias of MatchWithinLeaderLog in base.tla; its evidence block is attached to MatchWithinLeaderLog there)
\* review:   ok
MCMatchWithinLeaderLog == MatchWithinLeaderLog
\* REQ-EVIDENCE MCDurableStateBounded  (alias of DurableStateBounded in base.tla; its evidence block is attached to DurableStateBounded there)
\* review:   ok
MCDurableStateBounded == DurableStateBounded
\* REQ-EVIDENCE MCCurrentTermCommit  (alias of CurrentTermCommit in base.tla; its evidence block is attached to CurrentTermCommit there)
\* review:   ok
MCCurrentTermCommit == CurrentTermCommit
\* REQ-EVIDENCE MCCommittedLogAgreement  (alias of CommittedLogAgreement in base.tla; its evidence block is attached to CommittedLogAgreement there)
\* review:   ok
MCCommittedLogAgreement == CommittedLogAgreement

====
