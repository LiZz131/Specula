---- MODULE Update ----
(***************************************************************************)
(* Update-focused checking lens over the complete updated reference/MC.    *)
(* No behavior is defined here; every Action is an MC wrapper of base.     *)
(*                                                                         *)
(* Source update (baseline d86101c -> update d7176ef):                     *)
(*   core/raft_msg/mod.rs:98-107     RaftMsg::TransferLeader{from,to}      *)
(*   core/raft_core.rs:1190-1202     handler: vote==from -> disable_lease; *)
(*                                   to==self -> Engine::elect()           *)
(*   raft/mod.rs:645-703             Raft::transfer_leader public API      *)
(*   utime.rs:17,127-161             Leased::lease_enabled/disable_lease/  *)
(*                                   touch keeps a disabled lease          *)
(*   metrics/*, tests/*              no model effect (metrics excluded)     *)
(***************************************************************************)

EXTENDS MC

(***************************************************************************)
(* Affected Actions.                                                       *)
(* reference: base!TransferLeader, base!ElectCore (shared with             *)
(*   base!StartElection), base!ReceiveVoteResponse (R3 panic branch,       *)
(*   newly reachable through a non-voter transfer target).                 *)
(* code: core/raft_core.rs:1190-1202; engine/engine_impl.rs:223-249;       *)
(*   proposer/candidate.rs:62-96                                           *)
(***************************************************************************)

MCTransferLease(n, to) == n # to /\ MCTransfer(n, to)   \* disable_lease only
MCTransferElect(n) == MCTransfer(n, n)                  \* disable_lease; elect()

AffectedActions ==
    \/ \E n \in TransferSources, to \in TransferTargets : MCTransfer(n, to)
    \/ \E n \in ElectNodes : MCElect(n)
    \/ \E n, peer \in Server : MCVoteResponse(n, peer)

(***************************************************************************)
(* Interaction Actions: producers/consumers of the changed vote, lease,    *)
(* candidate and membership state, and the crash/recovery boundary.        *)
(*  - MCPersistVote/MCSendVote/MCVoteRequest: SaveVote->self grant,        *)
(*    SendVote->remote grants; vote request acceptance after the lease is  *)
(*    disabled (engine_impl.rs:292-343).                                   *)
(*  - MCFollowerAppend: same-vote heartbeat/append -> Leased::touch keeps  *)
(*    the lease disabled; replicated membership makes a node a learner.    *)
(*  - MCAddLearner/MCJoint/MCUniform/MCDataAppend: create learner/absent   *)
(*    targets and committed entries a transferred leader must hold.        *)
(*  - MCAck/MCSubmit/MCFlush: commit by a transfer-elected leader.         *)
(*  - MCCrash/MCRestart: lease reset and R4 startup containment.           *)
(***************************************************************************)

InteractionActions ==
    \/ \E n \in Server : MCPersistVote(n) \/ MCSendVote(n) \/ MCVoteRequest(n)
    \/ \E n \in Server : MCDropSelfResp(n)
    \/ \E n \in Server : MCDataAppend(n) \/ MCAddLearner(n) \/ MCJoint(n) \/ MCUniform(n)
    \/ \E n, ldr \in Server : MCFollowerAppend(n, ldr)
    \/ \E n \in Server : MCSubmit(n) \/ MCFlush(n)
    \/ \E n, peer \in Server : MCAck(n, peer)
    \/ \E n \in Server : MCCrash(n) \/ MCRestart(n)

(***************************************************************************)
(* Omitted context and its environment summary (modular-verification.md).  *)
(* MCSaveCommit, MCApply, MCRespond and MCStale change only durable commit,*)
(* applied index, the observation-only `commands`, and the stale-session   *)
(* witness.  None of them reads or writes vote, lease, candidate, leader,  *)
(* membership, logs, match, network, or panic state.                       *)
(***************************************************************************)

OmittedContext ==
    \/ \E n \in Server : MCSaveCommit(n) \/ MCApply(n) \/ MCRespond(n)
    \/ \E n, peer \in Server : MCStale(n, peer)

EnvFrame ==
    UNCHANGED <<up, voteVars, logs, commitIndex, acceptedIndex, submittedIndex,
                flushedIndex, durableLogs, membershipVars, electionVars, match,
                leaseEnabled, netVars, panicked, acceptedVoteIO,
                electionCount, transferCount, appendCount, replicateCount,
                membershipCount, ackCount, crashCount>>

EnvUpdate ==
    /\ EnvFrame
    /\ \E n \in Server, dc \in 0..MaxIndex, ap \in 0..MaxIndex,
          cm \in {{}, {"Respond"}}, st \in BOOLEAN :
          /\ durableCommit[n] <= dc /\ dc <= commitIndex[n]
          /\ appliedIndex[n] <= ap /\ ap <= dc
          /\ (staleResponseSeen => st)
          /\ durableCommit' = [durableCommit EXCEPT ![n] = dc]
          /\ appliedIndex' = [appliedIndex EXCEPT ![n] = ap]
          /\ commands' = [commands EXCEPT ![n] = cm]
          /\ staleResponseSeen' = st
          /\ staleCount' \in {staleCount, staleCount + 1}
          /\ staleCount' <= StaleLimit

FocusedNext == AffectedActions \/ InteractionActions
FocusedSpec == MCInit /\ [][FocusedNext]_<<allVars, mcVars>>

OpenNext == AffectedActions \/ InteractionActions \/ EnvUpdate
OpenSpec == MCInit /\ [][OpenNext]_<<allVars, mcVars>>

\* Discharge: every omitted real context step satisfies the rely.
DischargeContext == [][OmittedContext => EnvUpdate]_<<allVars, mcVars>>

(***************************************************************************)
(* Update-specific properties.                                             *)
(***************************************************************************)

VoteChanged(n) ==
    <<voteTerm'[n], voteNode'[n], voteCommitted'[n]>>
        # <<voteTerm[n], voteNode[n], voteCommitted[n]>>

\* An Engine::elect() step on a live node: its vote becomes a new,
\* greater, non-committed self vote (no other modeled action does this:
\* ReceiveVoteRequest requires cand # n, Restart requires ~up).
ElectStep(n) ==
    /\ up[n] /\ up'[n]
    /\ voteNode'[n] = n
    /\ ~voteCommitted'[n]
    /\ VoteLT(voteTerm[n], voteNode[n], voteCommitted[n],
              voteTerm'[n], voteNode'[n], voteCommitted'[n])

\* U1 (Scenario U-S1).  Documented contract: "follower and learner in
\* Openraft is almost the same. The only difference is a learner does not
\* try to elect itself" (docs/data/vote.md:50-51); enforced by both
\* pre-existing elect() callers (core/raft_core.rs:1207-1213, 1452-1455).
ElectOnlyByVoter ==
    [][\A n \in Server : ElectStep(n) => IsVoter(n, n)]_<<allVars, mcVars>>

\* U2 (Scenario U-S1).  RaftCore must not panic on a protocol input.
\* candidate.rs:94 `expect("target not in quorum set")` asserts that every
\* processed grant comes from a member of the candidate quorum set.
NoCorePanic == \A n \in Server : ~panicked[n]

\* U3 (Scenario U-S2).  utime.rs:126-131,150-161: a vote change goes through
\* Leased::update and re-enables the lease; only an equal vote is touch()ed.
LeaseReenabledOnVoteChange ==
    [][\A n \in Server : (up[n] /\ up'[n] /\ VoteChanged(n)) => leaseEnabled'[n]]_<<allVars, mcVars>>

\* U4 (Scenario U-S2).  The lease is disabled only by the TransferLeader
\* non-target branch, which never changes the vote (raft_core.rs:1194-1197).
DisabledLeaseOnlyByTransfer ==
    [][\A n \in Server : (leaseEnabled[n] /\ ~leaseEnabled'[n]) => (up'[n] /\ ~VoteChanged(n))]_<<allVars, mcVars>>

\* U5 (Scenario U-S1 consequence).  A leader established by its own
\* candidacy was a voter of the quorum it was elected by (learners never
\* elect themselves, docs/data/vote.md:50-51).
ElectedLeaderWasVoter ==
    \A n \in Server :
      ( /\ leader[n] /\ voteCommitted[n] /\ voteNode[n] = n
        /\ candidateTerm[n] = voteTerm[n] /\ candidateNode[n] = n )
      => n \in Voters(candidateConfigs[n])

\* U7 (Scenario U-S4, leader self-transfer).  Engine::leader_handler()
\* debug-asserts leader.committed_vote >= state.vote (engine_impl.rs:765-770)
\* and RaftCore calls it on every runtime-loop iteration (raft_core.rs:967).
\* While a Leader object exists, accepting another node's vote clears it
\* (become_following), so the assertion fails exactly when the Leader's own
\* state vote moves to a non-committed self vote, i.e. elect() on a Leader.
\* Guards a pre-existing implementation assertion; the update adds a new
\* public trigger (transfer_leader with `to` = current leader).
LeaderVoteNotSuperseded == \A n \in Server : (up[n] /\ leader[n]) => voteCommitted[n]

\* U6 (Scenarios U-S3/U-S4).  Preserved safety through a transfer-triggered
\* election, step-down and new-leader commit (reference properties).
TransferSafety == CommittedLogAgreement /\ LeaderCompleteness /\ CandidateGrantSound

(***************************************************************************)
(* Reachability canaries (expected to be VIOLATED in Update_canary_*.cfg). *)
(***************************************************************************)

\* TransferLeader non-target branch disabled a lease.
CanaryLeaseDisabled == \A n \in Server : leaseEnabled[n]
\* A transfer-triggered election produced a new leader (ElectNodes = {1}
\* and ElectionLimit = 1, so any other established leader came from a transfer).
CanaryTransferElectedLeader == ~\E n \in Server : n # 1 /\ leader[n] /\ voteCommitted[n] /\ voteNode[n] = n
\* The transfer-elected leader committed an entry of its own term.
CanaryCommitAfterTransfer ==
    ~\E n \in Server : n # 1 /\ leader[n] /\ commitIndex[n] >= 1
                       /\ EntryAt(n, commitIndex[n]).node = n
\* The old leader stepped down after a transfer (accepted the new vote).
CanaryOldLeaderDeposed ==
    ~(~leader[1] /\ up[1] /\ voteTerm[1] >= 2 /\ voteNode[1] # 1)
\* A non-voter became a candidate through TransferLeader.
CanaryNonVoterCandidate == ~\E n \in Server : candidate[n] /\ n \notin Voters(candidateConfigs[n])
\* A node absent from its membership ran elect() and fell back to following.
CanaryAbsentElect ==
    ~\E n \in Server : up[n] /\ ~Contains(n, n) /\ voteNode[n] = n /\ ~voteCommitted[n]
                       /\ voteTerm[n] >= 1
\* Discharge non-vacuity: the omitted context actions actually fire.
CanaryOmittedApply == \A n \in Server : appliedIndex[n] = 0
CanaryOmittedStale == ~staleResponseSeen
\* A voter granted a transfer candidate's vote request.
CanaryTransferGrant == ~\E g \in voteGrants : g.node # 1

====
