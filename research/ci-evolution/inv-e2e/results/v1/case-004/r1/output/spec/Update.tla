---- MODULE Update ----
(***************************************************************************)
(* Update-focused checking lens over the updated reference/MC suite.       *)
(* Update: RaftMsg::TransferLeader (source revision d7176ef9).             *)
(* This module defines no behaviour of its own: it selects MC actions,    *)
(* adds an environment rely for omitted context, and states update        *)
(* properties and reachability canaries.                                   *)
(***************************************************************************)

EXTENDS MC

(***************************************************************************)
(* Affected actions                                                        *)
(* reference: base!HandleTransferLeader (TransferLeaderElect branch) and   *)
(*            base!Elect, reached through base!StartElection (unchanged    *)
(*            voter guard) and the new transfer path (no voter guard).     *)
(* code: core/raft_core.rs:1190-1202; core/raft_msg/mod.rs:98-107;         *)
(*       raft/mod.rs:635-703; engine/engine_impl.rs:223-249.               *)
(* The lease-only and ignored branches of HandleTransferLeader are no-ops  *)
(* on modeled state except for the per-step `commands` observer; they are  *)
(* validated by real traces (Trace!TraceTransferLeader) and omitted here.  *)
(***************************************************************************)

AffectedActions ==
    \/ \E n \in Server : MCTransferLeader(n)
    \/ \E n \in Server : MCElect(n)

(***************************************************************************)
(* Interaction actions (Scenarios U1-U4, analysis-report.md).              *)
(*  - producer of `vote == from`: follower/learner append adopts the       *)
(*    leader's committed vote (vote_handler/mod.rs:124-163);               *)
(*  - producers of non-voter targets: learner/joint/uniform membership;    *)
(*  - consumers: SaveVote, SendVote, peer vote handling, vote responses,   *)
(*    leader establishment;                                                *)
(*  - commit after the leadership change: submit/flush/respond/ack;        *)
(*  - faults across the transfer boundary: crash/restart.                  *)
(***************************************************************************)

InteractionActions ==
    \/ \E n, o \in Server, c \in 1..MaxIndex : MCFollowerAppend(n, o, c)
    \/ \E n \in Server : MCAddLearner(n) \/ MCJoint(n) \/ MCUniform(n) \/ MCDataAppend(n)
    \/ \E n \in Server : MCPersistVote(n) \/ MCSendVote(n)
    \/ \E n \in Server, m \in voteReqs : MCVoteRequest(n, m)
    \/ \E n \in Server, r \in voteResps : MCVoteResponse(n, r)
    \/ \E n \in Server : MCSubmit(n) \/ MCFlush(n) \/ MCRespond(n)
    \/ \E n \in Server, r \in appendResps : MCAck(n, r)
    \/ \E n \in Server : MCCrash(n) \/ MCRestart(n)

(***************************************************************************)
(* Omitted context and its environment rely.                               *)
(* SaveCommit/Apply/DropStaleResponse never change vote, role, candidate,  *)
(* leader, membership, logs, progress, the network or the update counters.*)
(* They may raise durableCommit up to commitIndex, applied up to the new   *)
(* durable commit, clear the acting node's command observer, and record a *)
(* stale-session response (bounded by StaleLimit).                         *)
(***************************************************************************)

OmittedContext ==
    \/ \E n \in Server : MCSaveCommit(n) \/ MCApply(n)
    \/ \E n, peer \in Server : MCStale(n, peer)

EnvUpdate ==
    /\ UNCHANGED <<up, corePanic, voteVars, logs, commitIndex, acceptedIndex,
                    submittedIndex, flushedIndex, durableLogs,
                    membershipVars, electionVars, match, netVars,
                    electionCount, transferCount, appendCount,
                    membershipCount, crashCount>>
    /\ \E n \in Server :
         /\ up[n]
         /\ \E d \in durableCommit[n]..commitIndex[n] :
              \E a \in appliedIndex[n]..d :
                 /\ durableCommit' = [durableCommit EXCEPT ![n] = d]
                 /\ appliedIndex' = [appliedIndex EXCEPT ![n] = a]
         /\ commands' = [commands EXCEPT ![n] = {}]
    /\ \/ /\ staleResponseSeen' = staleResponseSeen
          /\ staleCount' = staleCount
       \/ /\ staleCount < StaleLimit
          /\ staleResponseSeen' = TRUE
          /\ staleCount' = staleCount + 1

FocusedNext == AffectedActions \/ InteractionActions
FocusedSpec == MCInit /\ [][FocusedNext]_vars

OpenNext == FocusedNext \/ EnvUpdate
OpenSpec == MCInit /\ [][OpenNext]_vars

\* Discharge: every omitted real context step satisfies the rely (frames included).
DischargeContext == [][OmittedContext => EnvUpdate]_vars
\* Partition sanity: the full MC relation is focused actions plus omitted context.
PartitionComplete == [][MCNext => (FocusedNext \/ OmittedContext)]_vars

(***************************************************************************)
(* Update properties                                                       *)
(*                                                                         *)
(* P-U1 ElectionInitiatorIsVoter (added).  Scenario U1.                    *)
(*   Requirement: docs/data/vote.md:50-51 "follower and learner in        *)
(*   Openraft is almost the same. The only difference is a learner does   *)
(*   not try to elect itself."; raft_state/mod.rs:341-343 (a learner      *)
(*   leader is "currently ... not supported"); every pre-update election  *)
(*   trigger checks is_voter (raft_core.rs:1449-1457, 1206-1214;          *)
(*   engine_impl.rs:694-704).  An election step is the only step that     *)
(*   emits SendVote with a fresh self vote of term last_seen+1             *)
(*   (engine_impl.rs:231-246).                                             *)
(* P-U1s CandidateIsVoterOfSnapshot (added, state form of P-U1 for present *)
(*   members whose candidate survives).                                    *)
(***************************************************************************)

ElectStep(n) ==
    /\ "SendVote" \in commands'[n]
    /\ voteNode'[n] = n
    /\ ~voteCommitted'[n]
    /\ voteTerm'[n] = lastSeenTerm[n] + 1

ElectionInitiatorIsVoter ==
    [][\A n \in Server : ElectStep(n) => IsVoter(n, n)]_vars

CandidateIsVoterOfSnapshot ==
    \A n \in Server : candidate[n] => n \in Voters(candidateConfigs[n])

(***************************************************************************)
(* P-U2 NoCorePanic (added).  Scenario U1 consequence.                     *)
(*   Requirement: "Fatal is unrecoverable and shuts down raft at once"     *)
(*   (error.rs:122-132); Candidate::grant_by states the internal contract  *)
(*   `expect("target not in quorum set")` (proposer/candidate.rs:86-90).   *)
(*   A RaftCore panic is never an allowed outcome of a public API call.    *)
(***************************************************************************)

NoCorePanic == \A n \in Server : ~corePanic[n]

(***************************************************************************)
(* Reachability canaries (expected to be VIOLATED; each violation is a     *)
(* witness that the Scenario is reachable in the checked configuration).   *)
(***************************************************************************)

\* U3: a transfer target that is a voter wins with real grants.
CanaryTransferVoterLeader ==
    ~(\E n \in TransferTargets : role[n] = "Leader" /\ voteTerm[n] > 1 /\ IsVoter(n, n))

\* U3: the new leader commits an entry of its own term.
CanaryTransferLeaderCommits ==
    ~(\E n \in TransferTargets :
        /\ leader[n] /\ voteTerm[n] > 1 /\ commitIndex[n] > 0
        /\ EntryAt(n, commitIndex[n]).term = voteTerm[n])

\* U3: the previous leader adopts the transfer target's higher vote.
CanaryOldLeaderSuperseded ==
    ~(\E a \in ElectNodes, b \in TransferTargets :
        /\ voteTerm[b] > 1 /\ voteNode[b] = b
        /\ voteTerm[a] = voteTerm[b] /\ voteNode[a] = b)

\* U1: a learner holding the leader vote becomes a candidate.
CanaryNonVoterCandidate ==
    ~(\E n \in Server : candidate[n] /\ ~IsVoter(n, n))

\* U1 consequence: the non-voter's RaftCore panics on its own vote grant.
\* (A non-voter cannot win first: its self-grant is handled before any remote
\* grant, see base!DoVoteResponse.)  Witness = violation of NoCorePanic.

\* U1 (absent target): a node absent from its effective config started an
\* election (candidate dropped, SendVote still pending).
CanaryAbsentElect ==
    ~(\E n \in Server :
        /\ voteNode[n] = n /\ ~voteCommitted[n] /\ voteTerm[n] > 1
        /\ ~IsMember(n, n) /\ pendingVoteSend[n])

\* U4: the transfer target crashes after Elect but before persisting the vote.
CanaryCrashBeforeSaveVote ==
    ~(\E n \in TransferTargets :
        /\ ~up[n] /\ voteTerm[n] > 1 /\ voteNode[n] = n
        /\ durableVoteTerm[n] < voteTerm[n])

====
