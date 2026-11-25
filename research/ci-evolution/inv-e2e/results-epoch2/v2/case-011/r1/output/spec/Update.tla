------------------------------ MODULE Update ------------------------------
(***************************************************************************
 * Update-focused checking lens for the Pre-Vote revision.                 *
 *                                                                         *
 * All behavior is owned by base.tla / MC.tla. This module only selects    *
 * reference Actions, defines the omitted-context rely (EnvUpdate), the    *
 * discharge obligation, update-specific properties, and reachability      *
 * canaries. It never copies an Action body.                               *
 *************************************************************************)
EXTENDS MC

(***************************************************************************
 * Affected Actions: every reference Action whose behavior changed.        *
 *  - MCTickPreVote / MCExternalPreElect     -> base!PreElect              *
 *      code: engine/engine_impl.rs:291-322; core/raft_core.rs:1683-1696,  *
 *            2010-2036                                                    *
 *  - MCTickElect                            -> base!TickElect (mode split)*
 *      code: core/raft_core.rs:2010-2036                                  *
 *  - MCExternalElect / MCStartTransferElection -> base!DoElect (clears     *
 *      pre_candidate)  code: engine/engine_impl.rs:262-264                *
 *  - DeliverPreVoteRequest -> base!HandlePreVoteRequest                    *
 *      code: engine/engine_impl.rs:406-447; core/raft_core.rs:1551-1562   *
 *  - DeliverPreVoteResponse -> base!HandlePreVoteResponse{Ignored,Grant,  *
 *      Elect,Reject}  code: engine/engine_impl.rs:512-554;                *
 *      core/raft_core.rs:1803-1820,2067-2090                              *
 *  - DefaultPreVoteRpcGrant -> base!DefaultPreVoteRpcGrant                 *
 *      code: network/v2/network.rs:141-161                                *
 *  - DeliverVoteRequest / DeliverVoteResponse / DeliverAppendEntries /    *
 *    RefreshServerState / Restart: become_following() / reconstruction    *
 *    now also drop pre_candidate                                          *
 *      code: engine/handler/vote_handler/mod.rs:234-249                   *
 *************************************************************************)
AffectedNode(i) ==
    \/ MCTickPreVote(i)
    \/ MCExternalPreElect(i)
    \/ MCTickElect(i)
    \/ MCExternalElect(i)
    \/ MCStartTransferElection(i)

AffectedNodeReactive(i) ==
    Old!Restart(i) \/ Old!RefreshServerState(i)

AffectedMsg(m) ==
    \/ Old!DeliverPreVoteRequest(m)
    \/ Old!DeliverPreVoteResponse(m)
    \/ Old!DefaultPreVoteRpcGrant(m)
    \/ Old!DeliverVoteRequest(m)
    \/ Old!DeliverVoteResponse(m)
    \/ Old!DeliverAppendEntries(m)

AffectedActions ==
    \/ \E i \in Server : AffectedNode(i)
    \/ /\ \E i \in Server : AffectedNodeReactive(i)
       /\ UNCHANGED faultCounters
    \/ /\ \E m \in messages : AffectedMsg(m)
       /\ UNCHANGED faultCounters

(***************************************************************************
 * Interaction Actions: unchanged Actions that establish, consume, or       *
 * interrupt the Pre-Vote path.                                             *
 *  - PersistVote: drains the SaveVote that gates every event (ElectGuard)  *
 *    and emits the local VoteResp that lets a stale candidate win.         *
 *  - SendVoteRequest / FinishVoteBroadcast / SendAppendEntries: the       *
 *    producers of the competing real-vote and leader-contact messages.     *
 *  - ExpireLease: enables Pre-Vote grants (lease check).                   *
 *  - AppendJoint/AppendUniform/CommitMembership: change the effective      *
 *    membership that pre_elect freezes and that elect() re-reads.          *
 *  - Crash: drops all in-flight volatile state.                            *
 *  - DropMessage: loss of Pre-Vote requests/responses.                     *
 *************************************************************************)
InteractionActions ==
    \/ \E i \in Server : MCCrash(i) \/ MCAppendUniformConfig(i)
    \/ \E i \in Server, target \in SUBSET Server : MCAppendJointConfig(i, target)
    \/ \E m \in messages : MCDropMessage(m)
    \/ /\ \E i \in Server : \/ Old!PersistVote(i) \/ Old!FinishVoteBroadcast(i)
                            \/ Old!ExpireLease(i) \/ Old!CommitMembership(i)
       /\ UNCHANGED faultCounters
    \/ /\ \E i \in Server, j \in Server : MCReactiveSend(i, j)
       /\ UNCHANGED faultCounters

FocusedNext == AffectedActions \/ InteractionActions
FocusedSpec == MCInit /\ [][FocusedNext]_mcVars

(***************************************************************************
 * Omitted context: base!FlushLog (log/config durability callback,         *
 * core/raft_core.rs:2262-2272 / storage callback). It changes only         *
 * durableLastLog, durableConfig(Index) and logFlushPending, which Restart  *
 * later reads. EnvUpdate is its rely: the environment may make node i's    *
 * projected log and effective config durable and clear its flush flag at  *
 * any time; it must preserve every other reference and MC variable,        *
 * including all vote, candidate, pre-candidate, leader, role, projected   *
 * log/config, and message state.                                           *
 *************************************************************************)
EnvDurability(i) ==
    /\ ~crashed[i]
    /\ durableLastLog' = [durableLastLog EXCEPT ![i] = lastLog[i]]
    /\ durableConfig' = [durableConfig EXCEPT ![i] = effectiveConfig[i]]
    /\ durableConfigIndex' = [durableConfigIndex EXCEPT ![i] = effectiveConfigIndex[i]]
    /\ logFlushPending' = [logFlushPending EXCEPT ![i] = FALSE]
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, lastLog,
                    committedConfig, committedConfigIndex, effectiveConfig,
                    effectiveConfigIndex, messages, preVars, faultCounters>>

EnvUpdate == \E i \in Server : EnvDurability(i)

OpenUpdateNext ==
    \/ AffectedActions
    \/ InteractionActions
    \/ EnvUpdate

OpenSpec == MCInit /\ [][OpenUpdateNext]_mcVars

\* Discharge: every real omitted step taken by full MCNext satisfies the
\* rely, including the frame on the MC counters.
OmittedContextStep(i) == Old!FlushLog(i) /\ UNCHANGED faultCounters

DischargeFlushLog ==
    [][\A i \in Server : OmittedContextStep(i) => EnvDurability(i)]_mcVars

(***************************************************************************
 * Observational step recognizers used by the update properties. They are  *
 * defined from state/message deltas, not by re-invoking the reference      *
 * Action bodies, so each property remains a falsifiable oracle for the     *
 * reference Actions (a property stated through the Action itself would be  *
 * true by construction).                                                    *
 *************************************************************************)
\* A Pre-Vote response addressed to i is consumed, i's round disappears, and
\* i's vote changes: the quorum branch of handle_pre_vote_resp ran elect().
\* reference: base!HandlePreVoteResponseElect
\* code: openraft/src/engine/engine_impl.rs:534-540
PreVoteElectStep(i) ==
    /\ preCandidateActive[i]
    /\ ~preCandidateActive'[i]
    /\ vote'[i] /= vote[i]
    /\ \E m \in messages \ messages' : m.kind = "PreVoteResp" /\ m.dest = i

\* A matching granted Pre-Vote response from m.source is consumed and either
\* added to the round's grants or ends the round (quorum).
\* reference: base!HandlePreVoteResponseGrant \/ base!HandlePreVoteResponseElect
\* code: openraft/src/engine/engine_impl.rs:531-541; proposer/candidate.rs:106-112
PreVoteGrantStepFrom(i, m) ==
    /\ m \in messages \ messages'
    /\ m.kind = "PreVoteResp"
    /\ m.dest = i
    /\ m.granted
    /\ PreVoteRespMatches(i, m)
    /\ \/ preGrants'[i] = preGrants[i] \cup {m.source}
       \/ ~preCandidateActive'[i]

\* A Pre-Vote request addressed to j is consumed and an answer from j to its
\* sender, carrying the request's vote as reqVote, appears.
\* reference: base!HandlePreVoteRequest (and base!DefaultPreVoteRpcGrant)
\* code: openraft/src/engine/engine_impl.rs:406-447
PreVoteRequestStep(m) ==
    /\ m \in messages \ messages'
    /\ m.kind = "PreVoteReq"
    /\ \E r \in messages' \ messages :
          /\ r.kind = "PreVoteResp"
          /\ r.source = m.dest
          /\ r.dest = m.source
          /\ r.reqVote = m.vote

\* New Pre-Vote requests from i appear: a round started (SendPreVote).
\* reference: base!PreElect (round-start branch)
\* code: openraft/src/engine/engine_impl.rs:298-322
PreVoteRoundStartStep(i) ==
    \E m \in messages' \ messages : m.kind = "PreVoteReq" /\ m.source = i

NonMessageVars == <<runtimeVars, voteVars, candidateVars, leaderVars, logVars,
                    configVars, preVars>>

(***************************************************************************
 * Update properties. REQ-EVIDENCE blocks follow ledger-usage.md.          *
 *************************************************************************)

\* REQ-EVIDENCE PreVoteRoundNotOutlivedByOwnLeadership
\* intent:   a Pre-Vote round that a node started while it was not Leader never starts a real election after that node has become Leader; Pre-Vote probes on behalf of a follower that wants to start an election and must not demote the node's own established leadership.
\* status:   requirement
\* evidence: doc source/openraft/src/docs/protocol/pre_vote.md:3-6 "Pre-Vote is an optional round that a follower runs **before** it increments its term and starts a real election." -> the round belongs to a follower about to elect
\* evidence: doc source/openraft/src/docs/protocol/pre_vote.md:44-45 "the requester does not change its own state while pre-voting: it stays a Follower with its term unchanged until a quorum responds." -> the round presumes the requester is still the would-be candidate
\* evidence: comment source/openraft/src/config/config.rs:402-404 "This prevents a node that cannot currently win ... from inflating its term and disrupting a healthy leader once it reconnects." -> Pre-Vote must not inflate the term of / disrupt a healthy leader
\* evidence: test source/tests/tests/elect/t12_pre_vote.rs:23-66 (line 57) pre_vote_prevents_term_inflation "the leader kept leadership at the same term" -> a healthy leader keeps its leadership and term under Pre-Vote
\* evidence: impl source/openraft/src/core/raft_core.rs:1966-1969 "skip election, already a leader" -> the tick never elects on behalf of a Leader
\* evidence: impl source/openraft/src/engine/engine_impl.rs:534-540 "self.elect();" -> the quorum branch elects unconditionally
\* watch:    source/openraft/src/engine/engine_impl.rs:Engine::handle_pre_vote_resp; source/openraft/src/engine/engine_impl.rs:Engine::establish_leader; source/openraft/src/engine/handler/vote_handler/mod.rs:VoteHandler::become_leader; source/openraft/src/engine/handler/vote_handler/mod.rs:VoteHandler::become_following; source/openraft/src/core/raft_core.rs:RaftCore::handle_tick_election
\* verified: update
\* note:     rounds started while already Leader (ExternalCommand::Elect{pre_vote:true} on a leader, raft_core.rs:1683-1696, "TODO: reject if it is already a leader?") are excluded through the preRoundFromLeader history bit; this property concerns only rounds the node started as follower/candidate.
PreVoteRoundNotOutlivedByOwnLeadershipStep ==
    \A i \in Server :
          PreVoteElectStep(i) => (role[i] = "Leader" => preRoundFromLeader[i])
PreVoteRoundNotOutlivedByOwnLeadership == [][PreVoteRoundNotOutlivedByOwnLeadershipStep]_mcVars

\* REQ-EVIDENCE PreVoteElectionByVoter
\* intent:   a real election started by a Pre-Vote quorum is started only by a node that is a voter of its current effective membership.
\* status:   unknown
\* evidence: impl source/openraft/src/core/raft_core.rs:1971-1974 "skip election, not a voter" -> the tick never elects for a non-voter
\* evidence: impl source/openraft/src/core/raft_core.rs:1684-1694 "if self.engine.state.membership_state.effective().is_voter(&self.id)" -> external elect is gated on being a voter at trigger time
\* evidence: impl source/openraft/src/engine/engine_impl.rs:534-540 "self.elect();" -> no voter re-check when the Pre-Vote quorum arrives
\* evidence: doc source/openraft/src/engine/engine_impl.rs:656-658 "openraft allows a learner to act as Leader." -> a non-voter Leader is a documented possibility, so non-voter elections are not clearly forbidden
\* watch:    source/openraft/src/engine/engine_impl.rs:Engine::handle_pre_vote_resp; source/openraft/src/engine/engine_impl.rs:Engine::do_elect; source/openraft/src/core/raft_core.rs:RaftCore::handle_tick_election; source/openraft/src/core/raft_core.rs:RaftCore::handle_api_msg (ExternalCommand::Elect)
\* verified: update
\* note:     only implementation guards were found; a violation is recorded as unresolved, not as a defect, unless non-implementation evidence is found.
PreVoteElectionByVoterStep ==
    \A i \in Server :
          PreVoteElectStep(i) => InConfig(i, effectiveConfig[i])
PreVoteElectionByVoter == [][PreVoteElectionByVoterStep]_mcVars

\* REQ-EVIDENCE PreVoteElectionAtProbedVote
\* intent:   the real election that a Pre-Vote quorum triggers runs at exactly the hypothetical vote (term + 1, self) that the quorum was asked about.
\* status:   requirement
\* evidence: doc source/openraft/src/docs/protocol/pre_vote.md:31-34 "*\"would you grant me a vote at `term + 1`?\"* The request carries a hypothetical next-term vote" -> the probe is about one specific next-term vote
\* evidence: doc source/openraft/src/docs/protocol/pre_vote.md:47-49 "If a quorum would grant, the node runs the real election ... incrementing its term and persisting its vote as usual." -> the election follows from that probe
\* evidence: test source/openraft/src/engine/tests/handle_pre_vote_resp_test.rs:40-72 (line 58) test_handle_pre_vote_resp_quorum_starts_real_election "the real election bumped the vote" -> the real vote equals the probed Vote::new(1, 1)
\* watch:    source/openraft/src/engine/engine_impl.rs:Engine::pre_elect; source/openraft/src/engine/engine_impl.rs:Engine::handle_pre_vote_resp; source/openraft/src/engine/engine_impl.rs:Engine::do_elect; source/openraft/src/core/raft_core.rs:RaftCore::does_pre_candidate_vote_match
\* verified: update
PreVoteElectionAtProbedVoteStep ==
    \A i \in Server :
          PreVoteElectStep(i) => vote'[i] = preCandidateVote[i]
PreVoteElectionAtProbedVote == [][PreVoteElectionAtProbedVoteStep]_mcVars

\* REQ-EVIDENCE PreVoteRequestIsPure
\* intent:   handling a Pre-Vote request changes no responder state (vote, lease, role, persistence, candidate/leader/pre-candidate trackers, log, membership); it only answers.
\* status:   requirement
\* evidence: doc source/openraft/src/docs/protocol/pre_vote.md:42-44 "handling a Pre-Vote request **persists nothing and changes nothing** — no term bump, no saved vote, no lease update." -> no responder state changes
\* evidence: test source/openraft/src/engine/tests/handle_pre_vote_req_test.rs:91-109 (line 103) test_handle_pre_vote_req_granted_without_mutation "The defining invariant: granting a pre-vote changes nothing locally." -> vote/server state/commands unchanged
\* evidence: contract source/openraft/src/raft/mod.rs:939-940 "Handling this RPC never persists a vote or changes this node's term" -> public API contract
\* watch:    source/openraft/src/engine/engine_impl.rs:Engine::handle_pre_vote_req; source/openraft/src/core/raft_core.rs:RaftCore::handle_pre_vote_request
\* verified: update
\* note:     in the model this is enforced by HandlePreVoteRequest's frame; its implementation evidence comes from Trace validation (ValidatePost compares the full captured post-state).
PreVoteRequestIsPureStep ==
    \A m \in messages : PreVoteRequestStep(m) => UNCHANGED NonMessageVars
PreVoteRequestIsPure == [][PreVoteRequestIsPureStep]_mcVars

\* REQ-EVIDENCE PreVoteStartIsPure
\* intent:   starting a multi-voter Pre-Vote round changes neither the vote (term), its persistence state, the role, the lease, nor the real candidate/leader trackers.
\* status:   requirement
\* evidence: doc source/openraft/src/docs/protocol/pre_vote.md:44-45 "the requester does not change its own state while pre-voting: it stays a Follower with its term unchanged" -> no requester state change
\* evidence: test source/openraft/src/engine/tests/pre_elect_test.rs:34-67 (line 48) test_pre_elect_multi_node_no_mutation "A pre-vote must NOT bump the term, persist a vote, or change server state." -> vote, server state unchanged; only SendPreVote emitted
\* watch:    source/openraft/src/engine/engine_impl.rs:Engine::pre_elect; source/openraft/src/engine/engine_impl.rs:Engine::new_pre_candidate
\* verified: update
PreVoteStartIsPureStep ==
    \A i \in Server :
          PreVoteRoundStartStep(i) =>
              UNCHANGED <<vote, durableVote, votePersistPending, replyPending,
                          leaseValid, role, candidateVars, leaderVars>>
PreVoteStartIsPure == [][PreVoteStartIsPureStep]_mcVars

\* REQ-EVIDENCE PreVoteGrantFromTrackedVoter
\* intent:   a counted Pre-Vote grant comes from a node tracked by the pre-candidate's frozen quorum (otherwise Candidate::grant_by panics with "target not in quorum set").
\* status:   model-internal
\* evidence: impl source/openraft/src/proposer/candidate.rs:106-112 "expect(\"target not in quorum set\")" -> an untracked grant aborts RaftCore
\* watch:    source/openraft/src/proposer/candidate.rs:Candidate::grant_by; source/openraft/src/engine/engine_impl.rs:Engine::handle_pre_vote_resp; source/openraft/src/core/raft_core.rs:RaftCore::does_pre_candidate_vote_match
\* verified: update
\* note:     the model has no learners in a config, so a violation is a diagnostic needing learner-retention review before it is a finding.
PreVoteGrantFromTrackedVoterStep ==
    \A i \in Server : \A m \in messages :
          PreVoteGrantStepFrom(i, m) => m.source \in ConfigVoters(preCandidateConfig[i])
PreVoteGrantFromTrackedVoter == [][PreVoteGrantFromTrackedVoterStep]_mcVars

\* REQ-EVIDENCE LeaderObjectVoteNotBehind
\* intent:   while a node keeps its Leader object, its local vote never exceeds that Leader's committed vote (otherwise every leader-handler use hits the engine's assertion and RaftCore panics in debug builds, or acts as a stale leader in release builds).
\* status:   mixed
\* evidence: impl source/openraft/src/engine/engine_impl.rs:976-981 "leader.vote({}) >= state.vote({})" -> developer-stated invariant checked by debug_assert! on every try_leader_handler()
\* evidence: impl source/openraft/src/core/raft_core.rs:921 "trigger_routine_actions" -> the check runs on every runtime loop iteration while a Leader object exists
\* evidence: test spec/output/repro-MC-1-new.log -> real-runtime observation: RaftCore of node 1 panicked at engine_impl.rs:977 after a stale Pre-Vote quorum
\* watch:    source/openraft/src/engine/engine_impl.rs:Engine::try_leader_handler; source/openraft/src/engine/engine_impl.rs:Engine::handle_pre_vote_resp; source/openraft/src/engine/engine_impl.rs:Engine::do_elect; source/openraft/src/engine/handler/vote_handler/mod.rs:VoteHandler::update_internal_server_state
\* verified: update
\* clause assertion: impl-abstraction/contract - the rule is stated only as a debug assertion in code, not in documentation
\* note:     ExternalCommand::Elect{pre_vote:false} on a Leader (an operator elect on the leader, raft_core.rs:1683-1696 "TODO: reject if it is already a leader?") reaches the same state in both revisions; MC_hunt_prevote_leader_object.cfg sets MaxElectionCount = 0 so that only Pre-Vote-driven elections exist and every violation is attributable to the update.
LeaderObjectVoteNotBehind ==
    \A i \in Server : (leaderActive[i] /\ ~crashed[i]) => VoteLE(vote[i], leaderVote[i])

(***************************************************************************
 * Known-finding filter for continued hunting (validation-workflow: "filter *
 * the known counterexample"). As an ACTION_CONSTRAINT it prunes only the    *
 * transitions that end in a state where a retained Leader object is behind *
 * the local vote: MC-1 (stale Pre-Vote quorum on an established Leader)    *
 * and the pre-existing operator elect on a Leader. Everything else,        *
 * including non-member Pre-Vote elections (U3), stays explored.            *
 *************************************************************************)
KnownFindingsFilter == LeaderObjectVoteNotBehind'

(***************************************************************************
 * Reachability canaries (expected to be violated; each violation is a      *
 * witness that the Scenario is reachable in the model).                    *
 *************************************************************************)
CanaryNoPreVoteElect == [][\A i \in Server : ~PreVoteElectStep(i)]_mcVars
CanaryNoLeaderWithStaleRound ==
    ~\E i \in Server : role[i] = "Leader" /\ preCandidateActive[i] /\ ~preRoundFromLeader[i]
CanaryNoPreVoteGrantResponse ==
    ~\E m \in messages : m.kind = "PreVoteResp" /\ m.granted
CanaryNoPreVoteRejectResponse ==
    ~\E m \in messages : m.kind = "PreVoteResp" /\ ~m.granted
CanaryNoNonVoterWithPreRound ==
    ~\E i \in Server : preCandidateActive[i] /\ ~InConfig(i, effectiveConfig[i])

UpdateView == ModelView

=============================================================================
