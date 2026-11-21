------------------------------ MODULE Update ------------------------------
(***************************************************************************
 * Update-focused checking lens for the Pre-Vote update (commit `update`).  *
 * All behavior is owned by base.tla / MC.tla; this module only selects    *
 * Actions, defines the omitted-context rely, and states update            *
 * properties. It does not replace full MCSpec checking.                   *
 *************************************************************************)
EXTENDS MC

frame == <<faultCounters, preRoundFromLeader>>

(***************************************************************************
 * AffectedActions: reference Actions whose behavior the update changed.   *
 *  - MCTickElect          reference: base!TickElect                       *
 *        code: core/raft_core.rs:1959-2036 (pre-vote branch, reset order) *
 *  - MCExternalPreElect   reference: base!ExternalPreElect / base!PreElect*
 *        code: core/raft_core.rs:1683-1691, engine/engine_impl.rs:298-322 *
 *  - MCExternalElect, MCStartTransferElection   reference: base!DoElect   *
 *        code: engine/engine_impl.rs:262-264 (clears pre_candidate)       *
 *  - MCDeliverPreVoteRequest  reference: base!HandlePreVoteRequest        *
 *        code: engine/engine_impl.rs:414-447, core/raft_core.rs:1551-1562 *
 *  - MCDeliverPreVoteResponse reference: base!HandlePreVoteResponse       *
 *        code: engine/engine_impl.rs:516-554, core/raft_core.rs:1803-1820 *
 *  - MCDeliverVoteRequest, MCDeliverVoteResponse, MCDeliverAppendEntries,  *
 *    MCRefreshServerState   reference: become_following callers           *
 *        code: engine/handler/vote_handler/mod.rs:244                     *
 *  - MCRestart            reference: base!Restart                         *
 *        code: engine/engine_impl.rs:117 (Engine::new)                    *
 *************************************************************************)
AffectedActions ==
    \/ \E i \in Server : MCTickElect(i) \/ MCExternalPreElect(i)
                           \/ MCExternalElect(i) \/ MCStartTransferElection(i)
    \/ /\ \/ \E m \in messages : MCDeliverPreVoteRequest(m) \/ MCDeliverPreVoteResponse(m)
                                    \/ MCDeliverVoteRequest(m) \/ MCDeliverVoteResponse(m)
                                    \/ MCDeliverAppendEntries(m)
          \/ \E i \in Server : MCRefreshServerState(i) \/ MCRestart(i)
       /\ UNCHANGED frame

(***************************************************************************
 * InteractionActions: unchanged Actions that establish or consume the    *
 * changed state.                                                          *
 *  - MCPersistVote: self-grant for the candidate whose win can inherit a  *
 *    live pre-candidate; completes SaveVote before a pre-vote win elects. *
 *    code: core/raft_core.rs:2274-2303                                    *
 *  - MCSendVoteRequest / MCFinishVoteBroadcast: real election after a     *
 *    pre-vote win. code: core/raft_core.rs:1385-1478                      *
 *  - MCSendAppendEntries: leader contact that cancels follower pre-vote   *
 *    rounds and installs leases that block pre-vote grants.              *
 *  - MCExpireLease: enables the tick and pre-vote grants.                 *
 *  - MCFlushLog, MCCrash, MCDropMessage: persistence/fault boundaries.    *
 *************************************************************************)
InteractionActions ==
    \/ /\ \/ \E i \in Server : MCPersistVote(i) \/ MCFinishVoteBroadcast(i)
                                 \/ MCFlushLog(i) \/ MCExpireLease(i)
          \/ \E i \in Server, j \in Server : MCSendVoteRequest(i, j) \/ MCSendAppendEntries(i, j)
       /\ UNCHANGED frame
    \/ \E i \in Server : MCCrash(i)
    \/ \E m \in messages : MCDropMessage(m)

(***************************************************************************
 * EnvUpdate: rely for the omitted membership context                     *
 * (AppendJointConfig, AppendUniformConfig, CommitMembership).             *
 * May change only node i's committed/effective config and indices, and   *
 * for an append the leader's last log/flush flag and membership counter. *
 * It allows any one-step leader reconfiguration that keeps at most one   *
 * outstanding membership entry (weaker than the reference's coherent      *
 * old -> joint -> new sequence). It never touches votes, roles,           *
 * candidates, pre-candidates, leases or messages.                         *
 *************************************************************************)
EnvMembership(i) ==
    /\ ~crashed[i]
    /\ \/ /\ faultCounters.membership < MaxMembershipCount
          /\ leaderActive[i] /\ vote[i].committed /\ vote[i].node = i
          /\ committedConfigIndex[i] = effectiveConfigIndex[i]
          /\ effectiveConfigIndex[i] < MaxLogIndex
          /\ lastLog[i].index < MaxLogIndex
          /\ \E target \in (SUBSET Server) \ {{}} :
               \E nc \in {<<target>>, <<effectiveConfig[i][1], target>>} :
                  /\ nc /= effectiveConfig[i]
                  /\ effectiveConfig' = [effectiveConfig EXCEPT ![i] = nc]
          /\ committedConfig' = [committedConfig EXCEPT ![i] = effectiveConfig[i]]
          /\ committedConfigIndex' = [committedConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
          /\ effectiveConfigIndex' = [effectiveConfigIndex EXCEPT ![i] = @ + 1]
          /\ lastLog' = [lastLog EXCEPT ![i] = Log(vote[i].term, i, lastLog[i].index + 1)]
          /\ logFlushPending' = [logFlushPending EXCEPT ![i] = TRUE]
          /\ faultCounters' = [faultCounters EXCEPT !.membership = @ + 1]
       \/ /\ committedConfigIndex[i] < effectiveConfigIndex[i]
          /\ committedConfig' = [committedConfig EXCEPT ![i] = effectiveConfig[i]]
          /\ committedConfigIndex' = [committedConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
          /\ UNCHANGED <<effectiveConfig, effectiveConfigIndex, lastLog,
                          logFlushPending, faultCounters>>
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars,
                    durableLastLog, durableConfig, durableConfigIndex,
                    messages, preVoteVars, preRoundFromLeader>>

EnvUpdate == \E i \in Server : EnvMembership(i)

FocusedNext == AffectedActions \/ InteractionActions
OpenUpdateNext == AffectedActions \/ InteractionActions \/ EnvUpdate

FocusedSpec == MCInit /\ [][FocusedNext]_mcVars

\* Timer-driven only: no administrative trigger().elect(..) or leadership
\* transfer. Used to show that a finding needs no operator action.
TickOnlyNext ==
    \/ \E i \in Server : MCTickElect(i) \/ MCCrash(i) \/ MCAppendUniformConfig(i)
    \/ \E i \in Server, target \in SUBSET Server : MCAppendJointConfig(i, target)
    \/ \E m \in messages : MCDropMessage(m)
    \/ /\ MCReactive
       /\ UNCHANGED <<faultCounters, preRoundFromLeader>>
TickOnlySpec == MCInit /\ [][TickOnlyNext]_mcVars
OpenSpec == MCInit /\ [][OpenUpdateNext]_mcVars

(***************************************************************************
 * Discharge: every omitted real membership step (with its MC frame) is    *
 * accepted by EnvUpdate. Checked over full MCSpec reachable states.      *
 *************************************************************************)
OmittedContextStep ==
    \E i \in Server :
        \/ \E t \in SUBSET Server : MCAppendJointConfig(i, t)
        \/ MCAppendUniformConfig(i)
        \/ MCCommitMembership(i) /\ UNCHANGED frame

DischargeMembership == [][OmittedContextStep => EnvUpdate]_mcVars

(***************************************************************************
 * Update-visible step predicates.                                         *
 *************************************************************************)
\* A step in which node i consumed a Pre-Vote response and incremented its
\* vote term: only base!HandlePreVoteResponse's win branch (DoElect) does this.
PreVoteWinStep(i) ==
    /\ \E m \in messages \ messages' : m.kind = "PreVoteResp" /\ m.dest = i
    /\ vote'[i].term > vote[i].term

\* A step in which node i answered a Pre-Vote request.
PreVoteReqHandledBy(i) ==
    /\ \E m \in messages \ messages' : m.kind = "PreVoteReq" /\ m.dest = i
    /\ \E r \in messages' \ messages : r.kind = "PreVoteResp" /\ r.source = i

(***************************************************************************
 * Update properties.                                                      *
 *************************************************************************)

\* Scenario U1 (stale round x leader establishment).
\* The tick never starts an election on a Leader (raft_core.rs:1966-1969), and
\* the documented Pre-Vote contract is that a node runs the real election only
\* when a quorum would grant it while it is still trying to become leader
\* (docs/protocol/pre_vote.md:28-48). A Pre-Vote round that was started while
\* the node was NOT an established leader must therefore never make an
\* established leader abandon its leadership by incrementing its term.
\* (Rounds explicitly requested on a leader via trigger().elect(true) are
\* administrative and excluded by preRoundFromLeader.)
PreVoteNeverDemotesEstablishedLeader ==
    [][\A i \in Server :
          (PreVoteWinStep(i) /\ EstablishedLeader(i)) => preRoundFromLeader[i]]_mcVars

\* Scenario U2 (probe/election agreement): the election started by a Pre-Vote
\* win is for exactly the vote the quorum was asked about
\* (engine_impl.rs:298-322 probe vote; 262-289 elect uses vote.term + 1).
PreVoteElectsAtProbedTerm ==
    [][\A i \in Server :
          PreVoteWinStep(i) =>
              vote'[i] = Vote(preCandidateVote[i].term, i, FALSE)]_mcVars

\* Scenario U3 (voter gate): every other path to do_elect() checks
\* is_voter (raft_core.rs:1683-1686, 1971-1974); a Pre-Vote-triggered election
\* must likewise only start on a current voter.
PreVoteElectOnlyByVoter ==
    [][\A i \in Server : PreVoteWinStep(i) => InConfig(i, effectiveConfig[i])]_mcVars

\* Scenario U4 (side-effect freedom, structural): answering a Pre-Vote request
\* changes no vote, durable vote, lease, role, persistence or candidate state
\* (engine_impl.rs:405-447, docs/protocol/pre_vote.md:42-45).
PreVoteHandlingIsSideEffectFree ==
    [][\A i \in Server :
          PreVoteReqHandledBy(i) =>
              /\ vote'[i] = vote[i]
              /\ durableVote'[i] = durableVote[i]
              /\ leaseValid'[i] = leaseValid[i]
              /\ role'[i] = role[i]
              /\ votePersistPending'[i] = votePersistPending[i]
              /\ candidateActive'[i] = candidateActive[i]
              /\ preCandidateActive'[i] = preCandidateActive[i]]_mcVars

\* Scenario U2/U5 (interaction invariant): while a pre-candidate is alive, it
\* still probes this node's next term. Every old Action that changes the
\* local vote must either cancel the round (become_following / do_elect) or
\* keep the term (establish_leader commits the same term).
PreCandidateProbesNextSelfTerm ==
    \A i \in Server :
        preCandidateActive[i] => preCandidateVote[i] = Vote(vote[i].term + 1, i, FALSE)

\* Diagnostic precondition of U1 (used only in the dedicated hunt cfg).
PreVoteRoundNotInheritedByLeader ==
    \A i \in Server :
        (preCandidateActive[i] /\ EstablishedLeader(i)) => preRoundFromLeader[i]

(***************************************************************************
 * Reachability canaries. Each is EXPECTED to be violated; the violation  *
 * trace is the witness that the corresponding update interaction is       *
 * reachable in the checked model.                                         *
 *************************************************************************)
CanaryNoPreVoteWin == [][\A i \in Server : ~PreVoteWinStep(i)]_mcVars

CanaryNoLeaseRejectedPreVote ==
    [][\A i \in Server :
          ~(/\ PreVoteReqHandledBy(i)
            /\ vote[i].committed /\ leaseValid[i]
            /\ \E r \in messages' \ messages : r.kind = "PreVoteResp" /\ r.source = i /\ ~r.granted)]_mcVars

CanaryNoPreCandidateCancelledByFollowing ==
    [][\A i \in Server :
          ~(preCandidateActive[i] /\ ~preCandidateActive'[i]
            /\ vote'[i].node /= i /\ ~crashed'[i])]_mcVars

CanaryNoPreRoundOnLeader ==
    \A i \in Server : ~(preCandidateActive[i] /\ EstablishedLeader(i))

CanaryNoPreVoteWinAfterMembershipChange ==
    [][\A i \in Server : ~(PreVoteWinStep(i) /\ effectiveConfigIndex[i] > 0)]_mcVars

=============================================================================
