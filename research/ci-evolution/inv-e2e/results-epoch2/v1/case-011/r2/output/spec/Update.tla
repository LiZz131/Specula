------------------------------ MODULE Update ------------------------------
(***************************************************************************
 * Update-focused checking lens for the Pre-Vote revision.                  *
 *                                                                          *
 * All behavior is owned by base.tla / MC.tla. This module only selects     *
 * MC actions, defines the open environment for omitted context, and states *
 * update-specific properties. No action body is copied here.               *
 *                                                                          *
 * Changed source (update commit):                                          *
 *   openraft/src/engine/engine_impl.rs   pre_elect, new_pre_candidate,     *
 *       handle_pre_vote_req, handle_pre_vote_resp, do_elect (clears round) *
 *   openraft/src/engine/handler/vote_handler/mod.rs  become_following      *
 *       clears pre_candidate                                               *
 *   openraft/src/core/raft_core.rs  handle_tick_election (pre-vote         *
 *       branch), ExternalCommand::Elect{pre_vote}, PreVoteResponse filter, *
 *       handle_pre_vote_request, spawn_parallel_vote_requests(kind)        *
 *   openraft/src/config/*, raft/runtime_config_handle.rs  enable_pre_vote  *
 *************************************************************************)
EXTENDS MC

(***************************************************************************
 * Affected Actions: MC forms of every reference Action whose body or       *
 * guard changed.                                                           *
 *************************************************************************)
\* reference: base!TickElect (new pre-vote-mode guard), base!TickPreElect,
\*            base!ExternalPreElect, base!PreElect
\* code: openraft/src/core/raft_core.rs:1959-2036,1683-1695;
\*       openraft/src/engine/engine_impl.rs:291-322
PreElectActions ==
    \E i \in Server : MCTickElect(i) \/ MCTickPreElect(i) \/ MCExternalPreElect(i)

\* reference: base!DoElect (now drops the pre-candidate) via base!StartElection
\* code: openraft/src/engine/engine_impl.rs:262-289
ElectActions ==
    \E i \in Server : MCExternalElect(i) \/ MCStartTransferElection(i)

\* reference: base!HandlePreVoteRequest, base!HandlePreVoteResponse{Elect,
\*            Tally,Reject,Stale}
\* code: openraft/src/engine/engine_impl.rs:406-447,511-554;
\*       openraft/src/core/raft_core.rs:1551-1562,1803-1820,2066-2090
PreVoteMessageActions ==
    \E m \in messages : MCDeliverPreVoteRequest(m) \/ MCDeliverPreVoteResponse(m)

AffectedActions == PreElectActions \/ ElectActions \/ PreVoteMessageActions

(***************************************************************************
 * Interaction Actions: unchanged reference Actions that establish, consume, *
 * cancel, or cross a fault boundary of the Pre-Vote round.                 *
 *   - HandleVoteResponse (wins -> establish_leader keeps the round;        *
 *     adopt -> become_following drops it)                                  *
 *   - HandleVoteRequest / HandleAppendEntries (become_following drops it)  *
 *   - RefreshServerState (update_internal_server_state)                    *
 *   - PersistVote / SendVoteRequest / FinishVoteBroadcast (the real        *
 *     election that a Pre-Vote quorum starts, and the Candidate context    *
 *     from which a tick can start a round)                                 *
 *   - Crash / Restart, DropMessage, ExpireLease (lease guard of the query) *
 *   - SendAppendEntries (leader contact that ends a follower's round)      *
 *************************************************************************)
InteractionActions ==
    \/ \E i \in Server :
          MCPersistVote(i) \/ MCFinishVoteBroadcast(i) \/ MCExpireLease(i)
          \/ MCRestart(i) \/ MCRefreshServerState(i) \/ MCCrash(i)
    \/ \E i \in Server, j \in Server :
          MCSendVoteRequest(i, j) \/ MCSendAppendEntries(i, j)
    \/ \E m \in messages :
          MCDeliverVoteRequest(m) \/ MCDeliverVoteResponse(m)
          \/ MCDeliverAppendEntries(m) \/ MCDropMessage(m)

(***************************************************************************
 * Omitted context: ordinary membership evolution and log flush. None of    *
 * them reads or writes a Pre-Vote variable, vote, role, candidate/leader   *
 * state, or messages; they change membership/log bookkeeping that the      *
 * Pre-Vote round reads (PreElect's voter/quorum snapshot, the query's      *
 * last-log comparison, Restart's durable reconstruction).                  *
 *************************************************************************)
OmittedContextActions ==
    \/ \E i \in Server : MCAppendUniformConfig(i) \/ MCCommitMembership(i) \/ MCFlushLog(i)
    \/ \E i \in Server, target \in SUBSET Server : MCAppendJointConfig(i, target)

UpdateVisibleVars ==
    <<runtimeVars, voteVars, candidateVars, leaderVars, messages, preVoteVars, preVoteBase>>

\* Coherent one-step membership successors (membership.rs:280-339).
EnvSuccessorConfigs(i) ==
    {effectiveConfig[i]}
    \cup (IF Len(effectiveConfig[i]) = 1
          THEN {<<effectiveConfig[i][1], t>> : t \in (SUBSET Server) \ {{}, effectiveConfig[i][1]}}
          ELSE {<<effectiveConfig[i][2]>>})

(***************************************************************************
 * Rely for the omitted context. One non-crashed node's membership/log      *
 * bookkeeping advances: effective config moves to a coherent successor or  *
 * stays, committed config keeps or catches up to the old effective, last   *
 * log may grow by one entry of the node's current vote, and the durable    *
 * log/config may catch up to the projected values. Every update-visible    *
 * variable is preserved, and the structural membership/log invariants of   *
 * the reference are kept. The guards of the concrete actions (leader-only  *
 * append, one outstanding change, commit frontier) are deliberately        *
 * dropped, so the rely admits more context than the real actions.          *
 *************************************************************************)
EnvUpdate ==
    \E i \in Server :
       /\ ~crashed[i]
       /\ UNCHANGED UpdateVisibleVars
       /\ \E eff \in EnvSuccessorConfigs(i),
             cc \in {<<committedConfig[i], committedConfigIndex[i]>>,
                     <<effectiveConfig[i], effectiveConfigIndex[i]>>},
             grow \in BOOLEAN, flush \in BOOLEAN :
            LET newEffIndex == IF eff = effectiveConfig[i] THEN effectiveConfigIndex[i]
                               ELSE effectiveConfigIndex[i] + 1
                newLog == IF grow THEN Log(vote[i].term, vote[i].node, lastLog[i].index + 1)
                          ELSE lastLog[i]
            IN /\ newEffIndex <= MaxLogIndex
               /\ newLog.index <= MaxLogIndex
               \* Open-check repair: real appends come from a Leader whose
               \* committed vote bounds every log id it holds, so the log only
               \* grows (the first open run admitted a lower-leader append after
               \* a restart reverted the vote; spec/changelog.md Round 3).
               /\ (grow => LogLT(lastLog[i], newLog))
               /\ (eff /= effectiveConfig[i] => /\ grow
                                                /\ faultCounters.membership < MaxMembershipCount
                                                \* rely v3: only an active leader proposes
                                                \* membership (leader_handler); the open run
                                                \* with v2 changed a follower's voters
                                                \* without AppendEntries (changelog Round 4)
                                                /\ leaderActive[i]
                                                /\ vote[i].committed /\ vote[i].node = i)
               /\ effectiveConfig' = [effectiveConfig EXCEPT ![i] = eff]
               /\ effectiveConfigIndex' = [effectiveConfigIndex EXCEPT ![i] = newEffIndex]
               /\ committedConfig' = [committedConfig EXCEPT ![i] = cc[1]]
               /\ committedConfigIndex' = [committedConfigIndex EXCEPT ![i] = cc[2]]
               /\ cc[2] <= newEffIndex /\ newEffIndex <= cc[2] + 1
               /\ lastLog' = [lastLog EXCEPT ![i] = newLog]
               /\ logFlushPending' = [logFlushPending EXCEPT ![i] =
                                         IF grow THEN TRUE ELSE IF flush THEN FALSE ELSE @]
               /\ durableLastLog' = [durableLastLog EXCEPT ![i] =
                                         IF flush /\ ~grow THEN lastLog[i] ELSE @]
               /\ durableConfig' = [durableConfig EXCEPT ![i] =
                                         IF flush /\ ~grow THEN effectiveConfig[i] ELSE @]
               /\ durableConfigIndex' = [durableConfigIndex EXCEPT ![i] =
                                         IF flush /\ ~grow THEN effectiveConfigIndex[i] ELSE @]
               /\ faultCounters' = [faultCounters EXCEPT !.membership =
                                         IF eff /= effectiveConfig[i] THEN @ + 1 ELSE @]

FocusedNext == AffectedActions \/ InteractionActions
OpenUpdateNext == AffectedActions \/ InteractionActions \/ EnvUpdate

FocusedSpec == MCInit /\ [][FocusedNext]_mcVars
OpenSpec == MCInit /\ [][OpenUpdateNext]_mcVars

\* Discharge: every omitted real context step (with the MC frame) is an
\* EnvUpdate step. Checked as an action property over the full MCSpec.
DischargeContext == [][OmittedContextActions => EnvUpdate]_mcVars

(***************************************************************************
 * Update properties.                                                       *
 *************************************************************************)

\* A step in which a Pre-Vote quorum makes node i run elect().
\* reference: base!HandlePreVoteResponseElect
PreVoteElectStep(i) ==
    \E m \in messages : m.dest = i /\ m.kind = "PreVoteResp"
                        /\ HandlePreVoteResponseElect(i, m, TRUE)

(***************************************************************************
 * U1 (Scenario U-2). A real election started by a Pre-Vote quorum starts   *
 * from the local state that the Pre-Vote round probed: the node's vote is  *
 * still the vote from which pre_elect built `term + 1`.                    *
 * Requirement evidence (non-implementation):                               *
 *   docs/protocol/pre_vote.md:4-6,40-46 ("runs before it increments its    *
 *   term"; "the requester does not change its own state while pre-voting:  *
 *   it stays a Follower with its term unchanged until a quorum responds"); *
 *   config/config.rs:397-404 ("prevents a node that cannot currently win   *
 *   ... from inflating its term and disrupting a healthy leader");         *
 *   core/raft_msg/external_command.rs:32-37 (an incautious trigger does    *
 *   not disrupt a live leader); engine_impl.rs:96-99 (the round is only a  *
 *   hypothetical next-term vote).                                          *
 * A vote change between pre_elect and the quorum means the probe answered *
 * a question about a state that no longer exists; the only such path in    *
 * the reference is Candidate -> Leader establishment, after which the      *
 * quorum makes the fresh Leader abandon its term.                          *
 *************************************************************************)
PreVoteElectionPremiseCurrent ==
    [][\A i \in Server : PreVoteElectStep(i) => vote[i] = preVoteBase[i]]_mcVars

\* U1 consequence form: a Pre-Vote quorum never makes an established Leader
\* abandon its leadership unless that Leader itself started the round
\* (Trigger::elect(true) on a leader).
PreVoteNeverDisplacesLeader ==
    [][\A i \in Server :
         (PreVoteElectStep(i) /\ role[i] = "Leader")
            => preVoteBase[i] = vote[i]]_mcVars

\* U1 early state form: an established Leader holds no Pre-Vote round
\* inherited from before its election.
EstablishedLeaderHasNoInheritedPreVote ==
    \A i \in Server : (role[i] = "Leader" /\ preCandidateActive[i]) => preVoteBase[i] = vote[i]

(***************************************************************************
 * U2 (Scenario U-1). While a Pre-Vote round is active its hypothetical     *
 * vote is exactly the uncommitted self vote at `vote.term + 1`: Pre-Vote   *
 * never bumps or persists the local term.                                  *
 * Requirement: pre_vote.md:4-6,36-43; engine/command.rs:138-142            *
 * ("does not persist a vote or bump the term").                            *
 *************************************************************************)
PreCandidateTermUnbumped ==
    \A i \in Server :
        preCandidateActive[i] =>
            /\ preCandidateVote[i] = Vote(vote[i].term + 1, i, FALSE)
            /\ VoteLE(durableVote[i], vote[i])

(***************************************************************************
 * U3 (structural, Scenario U-1). Pre-Vote messages carry the requester's   *
 * uncommitted hypothetical vote as the correlation key; the response goes  *
 * back to that requester. Needed for the runtime filter                    *
 * does_pre_candidate_vote_match (raft_core.rs:2066-2090) to be meaningful. *
 *************************************************************************)
PreVoteMessagesWellFormed ==
    \A m \in messages :
        /\ m.kind = "PreVoteReq" => (m.vote.node = m.source /\ ~m.vote.committed /\ m.vote.term >= 1)
        /\ m.kind = "PreVoteResp" => (m.vote.node = m.dest /\ ~m.vote.committed /\ m.vote.term >= 1)

\* Known-counterexample filter (MC-1 is the Leader case): keep searching for
\* any other path on which the probed vote changes before the quorum.
PreVoteElectionPremiseCurrentNonLeader ==
    [][\A i \in Server : (PreVoteElectStep(i) /\ role[i] /= "Leader")
                         => vote[i] = preVoteBase[i]]_mcVars

(***************************************************************************
 * U4 (Scenario U-5). Every in-flight Pre-Vote grant that the current round *
 * would accept (leader-id filter) comes from a voter of that round: a      *
 * stale response for an earlier round with the same correlation key must   *
 * be ignored, not crash the node.                                          *
 * Requirement: raft_core.rs:2066 ("If a Pre-Vote response is for a         *
 * previous Pre-Vote round, it is stale and should be ignored."),           *
 * raft_core.rs:2038-2039 (stale messages "should be just ignored"),        *
 * proposer/candidate.rs:107 (grant_by precondition "target ... in quorum   *
 * set").                                                                   *
 *************************************************************************)
PreVoteGrantFromRoundMember ==
    \A m \in messages :
        (m.kind = "PreVoteResp" /\ m.granted /\ PreVoteMatches(m.dest, m))
            => m.source \in ConfigVoters(preCandidateConfig[m.dest])

\* Consequence form: no step processes such a grant (RaftCore panic).
NoPanicOnStalePreVoteGrant ==
    [][\A m \in messages : ~HandlePreVoteResponseNonMember(m.dest, m, TRUE)]_mcVars

(***************************************************************************
 * Reachability canaries (expected to be VIOLATED; each violation is a      *
 * witness that the Scenario's update interaction is reachable).            *
 *************************************************************************)
CanaryNoPreVoteElect == [][\A i \in Server : ~PreVoteElectStep(i)]_mcVars
CanaryNoPreVoteGrant ==
    ~\E m \in messages : m.kind = "PreVoteResp" /\ m.granted
CanaryNoPreVoteReject ==
    ~\E m \in messages : m.kind = "PreVoteResp" /\ ~m.granted
CanaryNoLeaderWithPreCandidate ==
    ~\E i \in Server : role[i] = "Leader" /\ preCandidateActive[i]
CanaryNoPreCandidateDroppedByFollow ==
    [][\A i \in Server : ~(preCandidateActive[i] /\ ~preCandidateActive'[i]
                             /\ role'[i] \in {"Follower", "Learner"})]_mcVars
CanaryNoPreVoteElectFromFollower ==
    [][\A i \in Server : ~(PreVoteElectStep(i) /\ role[i] = "Follower")]_mcVars

=============================================================================
