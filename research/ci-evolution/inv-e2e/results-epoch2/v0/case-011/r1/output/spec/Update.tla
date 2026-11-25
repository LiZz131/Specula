------------------------------ MODULE Update ------------------------------
(***************************************************************************
 * Update-focused checking lens for the Pre-Vote source update.             *
 *                                                                         *
 * All behavior is owned by base.tla / MC.tla. This module only selects    *
 * reference Actions, defines an explicit environment for omitted context, *
 * and states update-specific properties and reachability canaries.        *
 *                                                                         *
 * Scenarios (modeling-brief.md section 2, U1-U5):                         *
 *  U1 Timer Pre-Vote gates term increase (no term inflation without a     *
 *     would-grant quorum).                                                 *
 *  U2 Pre-Vote round lifecycle across real election, leader establishment,*
 *     and delayed responses.                                               *
 *  U3 Responder guards: lease, last-log, would-grant; read-only handling. *
 *  U4 Cancellation by become_following, do_elect, and crash/restart.      *
 *  U5 Frozen (joint) membership of the Pre-Vote quorum vs membership      *
 *     evolution.                                                          *
 *************************************************************************)
EXTENDS MC

(***************************************************************************
 * Affected Actions: MC forms of the reference Actions the source update   *
 * changed directly.                                                        *
 *  reference: base!TickElect, base!TickPreElect (raft_core.rs:1959-2036)  *
 *  reference: base!ExternalElect, base!ExternalPreElect,                   *
 *             base!StartTransferElection -> base!DoElectCore               *
 *             (engine_impl.rs:262-322, raft_core.rs:1683-1695)             *
 *  reference: base!HandlePreVoteRequest (engine_impl.rs:406-447)           *
 *  reference: base!HandlePreVoteResponse (engine_impl.rs:511-554,          *
 *             raft_core.rs:1803-1820)                                      *
 *************************************************************************)
AffectedActions ==
    \/ \E i \in Server : MCTickElect(i) \/ MCTickPreElect(i) \/ MCExternalElect(i)
                           \/ MCExternalPreElect(i) \/ MCStartTransferElection(i)
    \/ \E m \in messages : MCDeliverPreVoteRequest(m) \/ MCDeliverPreVoteResponse(m)

(***************************************************************************
 * Interaction Actions: unchanged or minimally changed reference Actions    *
 * that establish, consume, cancel, or recover Pre-Vote state.              *
 *  - DeliverVoteRequest / DeliverAppendEntries / RefreshServerState:       *
 *    become_following drops the tracker (vote_handler/mod.rs:234-249).    *
 *  - DeliverVoteResponse: establish_leader keeps the tracker               *
 *    (engine_impl.rs:855-881); adopt drops it.                             *
 *  - PersistVote / SendVoteRequest / FinishVoteBroadcast: the real         *
 *    election that a Pre-Vote quorum starts, and its in-flight responses.  *
 *  - ExpireLease: enables lease-guarded grants and timer ticks.            *
 *  - Crash / Restart: the tracker is volatile (Engine::new).               *
 *  - SendAppendEntries: leader contact that cancels a follower's round.    *
 *  - DropMessage: lost Pre-Vote requests/responses.                        *
 *************************************************************************)
InteractionActions ==
    \/ \E i \in Server : MCPersistVote(i) \/ MCFinishVoteBroadcast(i)
                           \/ MCExpireLease(i) \/ MCRestart(i) \/ MCCrash(i)
                           \/ MCRefreshServerState(i)
    \/ \E i \in Server, j \in Server : MCSendVoteRequest(i, j) \/ MCSendAppendEntries(i, j)
    \/ \E m \in messages : MCDeliverVoteRequest(m) \/ MCDeliverVoteResponse(m)
                              \/ MCDeliverAppendEntries(m) \/ MCDropMessage(m)

(***************************************************************************
 * Omitted context: membership append/commit and log flush. They change     *
 * only one live node's committed/effective/durable config and log state.   *
 * They never touch vote, role, candidate, Pre-Vote, leader, or messages.   *
 * Their effect on the update is through the effective config (Pre-Vote     *
 * targets and the frozen quorum) and the last log (would-grant log check). *
 *************************************************************************)
OmittedContextActions ==
    \/ \E i \in Server, target \in SUBSET Server : MCAppendJointConfig(i, target)
    \/ \E i \in Server : MCAppendUniformConfig(i) \/ MCCommitMembership(i) \/ MCFlushLog(i)

NonEmptySubsets == (SUBSET Server) \ {{}}
\* Any valid one- or two-component next config. Weaker than the coherent
\* uniform -> joint -> uniform protocol on purpose: Pre-Vote must not depend
\* on the shape of the leader's own next configuration.
NextConfigs(c) == {<<x>> : x \in NonEmptySubsets} \cup {<<c[1], x>> : x \in NonEmptySubsets}

EnvFrame ==
    UNCHANGED <<runtimeVars, voteVars, candidateVars, preVars, leaderVars, messages>>

\* Rely for the omitted context (see modular-verification.md).
EnvUpdate ==
    /\ EnvFrame
    /\ \E i \in Server :
        /\ ~crashed[i]
        /\ \/ \* A live, established self-leader appends one config entry.
              /\ leaderActive[i]
              /\ vote[i].committed /\ vote[i].node = i
              /\ faultCounters.membership < MaxMembershipCount
              /\ committedConfigIndex[i] = effectiveConfigIndex[i]
              /\ effectiveConfigIndex[i] < MaxLogIndex
              /\ lastLog[i].index < MaxLogIndex
              /\ \E nc \in NextConfigs(effectiveConfig[i]) :
                    effectiveConfig' = [effectiveConfig EXCEPT ![i] = nc]
              /\ committedConfig' = [committedConfig EXCEPT ![i] = effectiveConfig[i]]
              /\ committedConfigIndex' = [committedConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
              /\ effectiveConfigIndex' = [effectiveConfigIndex EXCEPT ![i] = @ + 1]
              /\ lastLog' = [lastLog EXCEPT ![i] = Log(vote[i].term, i, lastLog[i].index + 1)]
              /\ logFlushPending' = [logFlushPending EXCEPT ![i] = TRUE]
              /\ faultCounters' = [faultCounters EXCEPT !.membership = @ + 1]
              /\ UNCHANGED <<durableLastLog, durableConfig, durableConfigIndex>>
           \/ \* The outstanding effective config becomes committed.
              /\ committedConfigIndex[i] < effectiveConfigIndex[i]
              /\ committedConfig' = [committedConfig EXCEPT ![i] = effectiveConfig[i]]
              /\ committedConfigIndex' = [committedConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
              /\ UNCHANGED <<effectiveConfig, effectiveConfigIndex, logVars,
                              durableConfig, durableConfigIndex, faultCounters>>
           \/ \* Readable log and config become durable.
              /\ logFlushPending[i]
              /\ durableLastLog' = [durableLastLog EXCEPT ![i] = lastLog[i]]
              /\ logFlushPending' = [logFlushPending EXCEPT ![i] = FALSE]
              /\ durableConfig' = [durableConfig EXCEPT ![i] = effectiveConfig[i]]
              /\ durableConfigIndex' = [durableConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
              /\ UNCHANGED <<lastLog, committedConfig, committedConfigIndex,
                              effectiveConfig, effectiveConfigIndex, faultCounters>>

FocusedNext == AffectedActions \/ InteractionActions
OpenUpdateNext == AffectedActions \/ InteractionActions \/ EnvUpdate

FocusedSpec == MCInit /\ [][FocusedNext]_mcVars
OpenSpec == MCInit /\ [][OpenUpdateNext]_mcVars

\* Discharge obligation, checked under the full MCSpec.
DischargeContext == [][OmittedContextActions => EnvUpdate]_mcVars

(***************************************************************************
 * Update-visible state.                                                    *
 *************************************************************************)
PreVoteVisible == <<preVars, vote, role, candidateActive, leaderActive, messages>>

ConsumedAt(i, kind) == {m \in messages \ messages' : m.kind = kind /\ m.dest = i}
EmittedBy(i, kind) == {m \in messages' \ messages : m.kind = kind /\ m.source = i}

(***************************************************************************
 * U2 (primary interaction property).                                       *
 * RaftCore::handle_tick_election never starts an election, Pre-Vote or     *
 * not, on a cached Leader ("skip election, already a leader",              *
 * raft_core.rs:1966-1969). A timer-started Pre-Vote round only defers that *
 * timer's election decision until a quorum would grant, and Pre-Vote is    *
 * documented to keep a healthy leader from being disrupted                 *
 * (docs/protocol/pre_vote.md; config.rs enable_pre_vote doc). Hence the    *
 * deferred decision must not depose a node that is Leader when the         *
 * deciding response arrives. Rounds explicitly requested by the operator   *
 * (Trigger::elect(true)) are excluded via the origin ghost.                *
 * reference: base!HandlePreVoteResponse, base!HandleVoteResponse           *
 * code: engine_impl.rs:526-541 (elect() without a role check),             *
 *       engine_impl.rs:855-881 (establish_leader keeps pre_candidate)      *
 *************************************************************************)
TickPreVoteNeverDeposesLeader ==
    [][\A i \in Server :
          (/\ role[i] = "Leader"
           /\ preCandidateActive[i]
           /\ preCandidateByTick[i]
           /\ ConsumedAt(i, "PreVoteResp") /= {})
          => role'[i] = "Leader"]_mcVars

(***************************************************************************
 * U1. With Pre-Vote enabled and no operator-forced direct election, a node *
 * raises its own term only through a would-grant quorum of its frozen      *
 * Pre-Vote config, or as a single voter (raft_core.rs:2010-2012,           *
 * engine_impl.rs:308-315). Meaningful only for PreVoteSetting = "Enabled"  *
 * and AllowDirectOperatorElect = FALSE.                                    *
 *************************************************************************)
SelfTermIncreaseNeedsPreVoteQuorum ==
    [][\A i \in Server :
          (vote'[i].node = i /\ vote'[i].term > vote[i].term)
          => \/ VoterCount(i) = 1
             \/ \E m \in ConsumedAt(i, "PreVoteResp") : PreVoteWins(i, m)]_mcVars

(***************************************************************************
 * U3. Handling a Pre-Vote request persists nothing and changes nothing on  *
 * the responder (engine_impl.rs:406-447, docs/protocol/pre_vote.md).       *
 *************************************************************************)
PreVoteRequestIsReadOnly ==
    [][\A i \in Server :
          ConsumedAt(i, "PreVoteReq") /= {}
          => /\ vote'[i] = vote[i]
             /\ durableVote'[i] = durableVote[i]
             /\ role'[i] = role[i]
             /\ leaseValid'[i] = leaseValid[i]
             /\ votePersistPending'[i] = votePersistPending[i]]_mcVars

(***************************************************************************
 * U1/U3. Starting a Pre-Vote round changes neither the requester's vote    *
 * nor its role (engine_impl.rs:291-322 "no term bump, no persisted vote,   *
 * no server-state change").                                                *
 *************************************************************************)
PreElectLeavesVoteUnchanged ==
    [][\A i \in Server :
          EmittedBy(i, "PreVoteReq") /= {}
          => /\ vote'[i] = vote[i]
             /\ durableVote'[i] = durableVote[i]
             /\ role'[i] = role[i]]_mcVars

(***************************************************************************
 * U2/U4 structural interaction invariant: an in-flight round always probes *
 * exactly the term that its quorum would elect (do_elect uses term + 1 of  *
 * the then-current vote).                                                  *
 *************************************************************************)
PreVoteProbeIsNextTerm ==
    \A i \in Server :
        preCandidateActive[i] => preCandidateVote[i] = Vote(vote[i].term + 1, i, FALSE)

PreVoteTrackerWellFormed ==
    \A i \in Server :
        preCandidateActive[i] =>
            /\ i \in preGrants[i]
            /\ preGrants[i] \subseteq ConfigVoters(preCandidateConfig[i]) \cup {i}

UpdateInvariants ==
    /\ PreVoteProbeIsNextTerm
    /\ PreVoteTrackerWellFormed

(***************************************************************************
 * Reachability / non-vacuity canaries. Each is EXPECTED to be violated in  *
 * its canary run; the violation trace is the witness.                       *
 *************************************************************************)
CanaryNoLeaderWithTickPreRound ==
    ~\E i \in Server : role[i] = "Leader" /\ preCandidateActive[i] /\ preCandidateByTick[i]

CanaryNoJointPreVoteRound ==
    ~\E i \in Server : preCandidateActive[i] /\ Len(preCandidateConfig[i]) = 2

CanaryNoRejectedPreVoteResponse ==
    ~\E m \in messages : m.kind = "PreVoteResp" /\ ~m.granted

CanaryNoPreVoteElection ==
    [][~\E i \in Server : \E m \in ConsumedAt(i, "PreVoteResp") : PreVoteWins(i, m)]_mcVars

CanaryNoLeaseRejectedPreVote ==
    [][~\E i \in Server : ConsumedAt(i, "PreVoteReq") /= {} /\ vote[i].committed /\ leaseValid[i]]_mcVars

CanaryNoPreVoteCancelledByFollowing ==
    [][~\E i \in Server : preCandidateActive[i] /\ ~preCandidateActive'[i]
                              /\ ~crashed[i] /\ vote'[i].node /= i]_mcVars

CanaryNoGreaterLogFromPreVote ==
    [][~\E i \in Server : ConsumedAt(i, "PreVoteResp") /= {}
                              /\ ~seenGreaterLog[i] /\ seenGreaterLog'[i]]_mcVars

CanaryNoPreVoteAfterRestart ==
    [][~\E i \in Server : preCandidateActive[i] /\ crashed[i] /\ ~crashed'[i]]_mcVars

=============================================================================
