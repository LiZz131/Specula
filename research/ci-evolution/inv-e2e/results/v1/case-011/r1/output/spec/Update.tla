------------------------------ MODULE Update ------------------------------
(***************************************************************************
 * Update-focused checking lens for the Pre-Vote revision.                  *
 *                                                                          *
 * All behaviour is owned by base.tla/MC.tla.  This module only selects MC  *
 * actions, defines update properties, the open environment for omitted     *
 * membership evolution, and its discharge obligation.                       *
 *                                                                          *
 * Changed source (synthetic `baseline` -> `update`):                        *
 *   engine/engine_impl.rs   pre_elect, new_pre_candidate,                  *
 *                           handle_pre_vote_req, handle_pre_vote_resp,     *
 *                           do_elect clears pre_candidate                  *
 *   engine/handler/vote_handler/mod.rs  become_following clears it         *
 *   core/raft_core.rs       tick pre-vote branch, Elect{pre_vote},         *
 *                           RequestPreVote, PreVoteResponse correlation,   *
 *                           SendPreVote dispatch                            *
 *   config/*, raft/runtime_config_handle.rs  enable_pre_vote switch         *
 *************************************************************************)
EXTENDS MC

(***************************************************************************
 * PreVoteState: variables introduced in base.tla (preVoteVars).            *
 * TickPreVoteContext: PreVoteSetting/MultiVoter decide whether a tick      *
 * reaches PreElect (core/raft_core.rs:1981-2035).                          *
 * PreVoteClearingContext: DoElect, become_following callers, and Restart  *
 * clear the pre-candidate; establish_leader does not.                      *
 *************************************************************************)
PreVoteState == preVoteVars
TickPreVoteContext == PreVoteSetting
PreVoteClearingContext == TRUE

Reactive(A) == A /\ UNCHANGED faultCounters

\* cfg helper: runtime flag permanently enabled (Config::enable_pre_vote = Some(true)).
PreVoteAlwaysOn == {TRUE}

(***************************************************************************
 * Affected Actions: MC forms of every reference action whose code changed. *
 *************************************************************************)
\* reference: base!PreElect, base!TickPreElect, base!ExternalPreElect, base!DoElect
\* code: engine/engine_impl.rs:262-322, core/raft_core.rs:1683-1697,1981-2035
AffectedStart ==
    \E i \in Server :
        \/ MCTickPreElect(i) \/ MCExternalPreElect(i)
        \/ MCTickElect(i) \/ MCExternalElect(i) \/ MCStartTransferElection(i)

\* reference: base!SendPreVoteRequest, base!FinishPreVoteBroadcast
\* code: core/raft_core.rs:1385-1478,2342-2344
AffectedDispatch ==
    \/ \E i \in Server, j \in Server : Reactive(Old!SendPreVoteRequest(i, j))
    \/ \E i \in Server : Reactive(Old!FinishPreVoteBroadcast(i))

\* reference: base!HandlePreVoteRequest, base!HandlePreVoteResponse
\* code: engine/engine_impl.rs:414-447,516-554, core/raft_core.rs:1551-1562,1803-1820
AffectedHandlers ==
    \E m \in messages :
        Reactive(Old!DeliverPreVoteRequest(m) \/ Old!DeliverPreVoteResponse(m))

AffectedActions == AffectedStart \/ AffectedDispatch \/ AffectedHandlers

(***************************************************************************
 * Interaction Actions: unchanged or clearing-only reference actions that   *
 * establish, consume, cancel, or crash across the pre-vote state.          *
 *   - real election completion (PersistVote, vote dispatch, VoteResp ->     *
 *     establish_leader) can make a pre-candidate's node a Leader;           *
 *   - VoteReq/Append/Refresh reach become_following (clears pre-candidate); *
 *   - lease expiry enables pre-vote grants; crash/restart drops the round;  *
 *   - message loss models RPC errors/timeouts (not grants).                 *
 *************************************************************************)
\* reference: base!PersistVote, SendVoteRequest, FinishVoteBroadcast,
\*            HandleVoteRequest, HandleVoteResponse, HandleAppendEntries,
\*            SendAppendEntries, FlushLog, ExpireLease, RefreshServerState,
\*            Crash, Restart, DropMessage
InteractionActions ==
    \/ \E i \in Server :
          Reactive(Old!PersistVote(i) \/ Old!FinishVoteBroadcast(i) \/ Old!FlushLog(i)
                   \/ Old!ExpireLease(i) \/ Old!Restart(i) \/ Old!RefreshServerState(i))
    \/ \E i \in Server : MCCrash(i)
    \/ \E i \in Server, j \in Server :
          Reactive(Old!SendVoteRequest(i, j) \/ Old!SendAppendEntries(i, j))
    \/ \E m \in messages :
          Reactive(Old!DeliverVoteRequest(m) \/ Old!DeliverVoteResponse(m)
                   \/ Old!DeliverAppendEntries(m))
    \/ \E m \in messages : MCDropMessage(m)

(***************************************************************************
 * Omitted context: ordinary membership evolution.  It changes only         *
 * membership/log state of one node.  EnvUpdate is the rely: the same       *
 * coherent evolution shapes without the leader-only guards, so any node   *
 * may evolve membership (weaker than the reference, stronger than chaos). *
 * It must preserve every vote, candidate, leader, pre-vote and message    *
 * variable.                                                                *
 *************************************************************************)
OmittedContext ==
    \/ \E i \in Server, target \in SUBSET Server : MCAppendJointConfig(i, target)
    \/ \E i \in Server : MCAppendUniformConfig(i)
    \/ \E i \in Server : Reactive(Old!CommitMembership(i))

EnvFrame ==
    UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, durableLastLog,
                durableConfig, durableConfigIndex, messages, preVoteVars>>

EnvJoint(i, target) ==
    /\ faultCounters.membership < MaxMembershipCount
    /\ ~crashed[i]
    /\ committedConfigIndex[i] = effectiveConfigIndex[i]
    /\ Len(effectiveConfig[i]) = 1
    /\ target \subseteq Server /\ target /= {} /\ target /= effectiveConfig[i][1]
    /\ effectiveConfigIndex[i] < MaxLogIndex
    /\ lastLog[i].index < MaxLogIndex
    /\ committedConfig' = [committedConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ committedConfigIndex' = [committedConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
    /\ effectiveConfig' = [effectiveConfig EXCEPT ![i] = <<effectiveConfig[i][1], target>>]
    /\ effectiveConfigIndex' = [effectiveConfigIndex EXCEPT ![i] = @ + 1]
    /\ lastLog' = [lastLog EXCEPT ![i] = Log(vote[i].term, vote[i].node, lastLog[i].index + 1)]
    /\ logFlushPending' = [logFlushPending EXCEPT ![i] = TRUE]
    /\ faultCounters' = [faultCounters EXCEPT !.membership = @ + 1]
    /\ EnvFrame

EnvUniform(i) ==
    /\ faultCounters.membership < MaxMembershipCount
    /\ ~crashed[i]
    /\ committedConfigIndex[i] = effectiveConfigIndex[i]
    /\ Len(effectiveConfig[i]) = 2
    /\ effectiveConfigIndex[i] < MaxLogIndex
    /\ lastLog[i].index < MaxLogIndex
    /\ committedConfig' = [committedConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ committedConfigIndex' = [committedConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
    /\ effectiveConfig' = [effectiveConfig EXCEPT ![i] = <<effectiveConfig[i][2]>>]
    /\ effectiveConfigIndex' = [effectiveConfigIndex EXCEPT ![i] = @ + 1]
    /\ lastLog' = [lastLog EXCEPT ![i] = Log(vote[i].term, vote[i].node, lastLog[i].index + 1)]
    /\ logFlushPending' = [logFlushPending EXCEPT ![i] = TRUE]
    /\ faultCounters' = [faultCounters EXCEPT !.membership = @ + 1]
    /\ EnvFrame

EnvCommit(i) ==
    /\ ~crashed[i]
    /\ committedConfigIndex[i] < effectiveConfigIndex[i]
    /\ committedConfig' = [committedConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ committedConfigIndex' = [committedConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
    /\ UNCHANGED <<effectiveConfig, effectiveConfigIndex, lastLog, logFlushPending, faultCounters>>
    /\ EnvFrame

EnvUpdate ==
    \/ \E i \in Server, target \in SUBSET Server : EnvJoint(i, target)
    \/ \E i \in Server : EnvUniform(i) \/ EnvCommit(i)

(***************************************************************************
 * Focused specs.                                                           *
 *************************************************************************)
ConcreteFocusNext == AffectedActions \/ InteractionActions
OpenUpdateNext == AffectedActions \/ InteractionActions \/ EnvUpdate

ConcreteFocusSpec == MCInit /\ [][ConcreteFocusNext]_mcVars
OpenUpdateSpec == MCInit /\ [][OpenUpdateNext]_mcVars

\* Discharge: every omitted real context step satisfies the rely with its frame.
DischargeContext == [][OmittedContext => EnvUpdate]_mcVars

(***************************************************************************
 * Update properties.                                                       *
 *************************************************************************)

\* Step-identification helpers (state-only, no ghost).
ConsumedPreVoteResp(i) ==
    \E m \in messages : m.kind = "PreVoteResp" /\ m.dest = i /\ m \notin messages'

PreVoteElectStep(i) ==
    /\ ConsumedPreVoteResp(i)
    /\ vote'[i] /= vote[i]

(* U1 (new, structural/interaction).  A live pre-candidate always probes   *
 * exactly the vote a real election would use next: (term + 1, self,       *
 * uncommitted).  Scenario U-S3/U-S4.  Requirement: pre_vote.md:22-27       *
 * ("would you grant me a vote at term + 1"), engine_impl.rs:291-297.       *)
\* reference: base!PreElect, base!DoElect, base!HandleVoteResponse
PreCandidateVoteIsNextTerm ==
    \A i \in Server :
        preCandidateActive[i] =>
            preCandidateVote[i] = Vote(vote[i].term + 1, i, FALSE)

(* U2 (new, action).  The election started by a pre-vote quorum installs   *
 * exactly the probed vote.  Scenario U-S2.  Requirement: pre_vote.md:31-41 *)
\* reference: base!HandlePreVoteResponse
PreVoteElectsProbedVoteStep ==
    \A i \in Server : PreVoteElectStep(i) => vote'[i] = preCandidateVote[i]
PreVoteElectsProbedVote == [][PreVoteElectsProbedVoteStep]_mcVars

(* U3 (new, action).  Handling a Pre-Vote request changes no local state;   *
 * only the response is emitted.  Scenario U-S1.  Requirement:              *
 * pre_vote.md:35-38, raft/mod.rs:936-948, engine_impl.rs:406-413.          *)
\* reference: base!HandlePreVoteRequest
PreVoteRequestPureStep ==
    \A m \in messages :
          (/\ m.kind = "PreVoteReq" /\ m \notin messages'
           /\ \E r \in messages' \ messages : r.kind = "PreVoteResp" /\ r.dest = m.source)
          => UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                         configVars, preVoteVars>>
PreVoteRequestPure == [][PreVoteRequestPureStep]_mcVars

(* U4 (new, action) -- interaction of the pre-vote round with leader       *
 * establishment.  A Pre-Vote round that a node started while it was not   *
 * Leader (tick or a cautious manual trigger) must never make that node,   *
 * once it is Leader, abandon its leadership by starting a real election. *
 * Scenario U-S4.  Requirements: pre_vote.md:3-5 (a round a follower runs   *
 * *before* it starts a real election), pre_vote.md:14-20 and              *
 * trigger.rs:47-56 (Pre-Vote must not disrupt a healthy leader),          *
 * raft_core.rs:1964-1969 (an automatic election never starts on a Leader),*
 * engine_impl.rs:977-982 (debug_assert leader.committed_vote >= vote).     *
 * Rounds started by an administrator on a node that was already Leader    *
 * are excluded (pre-existing TODO at raft_core.rs:1685).                   *)
\* reference: base!HandlePreVoteResponse, base!HandleVoteResponse (establish)
PreVoteNeverDemotesLeaderStep ==
    \A i \in Server :
          (/\ role[i] = "Leader"
           /\ preStartRole[i] /= "Leader"
           /\ PreVoteElectStep(i)) => FALSE
PreVoteNeverDemotesLeader == [][PreVoteNeverDemotesLeaderStep]_mcVars

(* U5 (new, state; precursor of U4).  A node that has become Leader holds  *
 * no Pre-Vote round that it started before becoming Leader.               *)
\* reference: base!HandleVoteResponse, base!PreVoteCleared callers
NoStalePreCandidateAtLeader ==
    \A i \in Server :
        (preCandidateActive[i] /\ preStartRole[i] /= "Leader") => role[i] /= "Leader"

(***************************************************************************
 * Reachability canaries (expected to be VIOLATED; each violation is a      *
 * witness that the Scenario is reachable in the checked configuration).    *
 *************************************************************************)
CanaryNoPreCandidate == \A i \in Server : ~preCandidateActive[i]
CanaryNoGrantedPreVoteResp == \A m \in messages : ~(m.kind = "PreVoteResp" /\ m.granted)
CanaryNoRejectedPreVoteResp == \A m \in messages : ~(m.kind = "PreVoteResp" /\ ~m.granted)
CanaryNoPreGrantCounted == \A i \in Server : preGrants[i] \subseteq {i}
CanaryNoPreVoteElection == [][\A i \in Server : ~PreVoteElectStep(i)]_mcVars
CanaryNoCandidateWithPreCandidate ==
    \A i \in Server : ~(preCandidateActive[i] /\ candidateActive[i] /\ role[i] = "Candidate")
CanaryNoLeaderWithPreCandidate ==
    \A i \in Server : ~(preCandidateActive[i] /\ role[i] = "Leader")
CanaryNoPreVoteCleared ==
    [][\A i \in Server : ~(preCandidateActive[i] /\ ~preCandidateActive'[i]
                           /\ vote'[i].node /= i)]_mcVars

=============================================================================
