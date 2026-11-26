------------------------------ MODULE Update ------------------------------
(***************************************************************************
 * Update-focused checking lens for the Pre-Vote update.                    *
 *                                                                           *
 * All behaviour is owned by base.tla / MC.tla.  This module only selects    *
 * MC wrappers, defines an explicit environment for omitted context, and     *
 * states the update-specific properties and reachability canaries.          *
 *                                                                           *
 * Source delta (artifact HEAD `update` vs `baseline`):                      *
 *  - engine/engine_impl.rs: pre_candidate field, new_pre_candidate,         *
 *    pre_elect, handle_pre_vote_req, handle_pre_vote_resp, do_elect clears  *
 *    pre_candidate.                                                         *
 *  - engine/handler/vote_handler/mod.rs: become_following clears            *
 *    pre_candidate.                                                         *
 *  - core/raft_core.rs: tick runs pre_elect when enable_pre_vote and >1     *
 *    voter; ExternalCommand::Elect{pre_vote}; RequestPreVote handling;      *
 *    PreVoteResponse notification gate; SendPreVote command.                *
 *  - network: pre_vote RPC with a granting default implementation.          *
 *************************************************************************)
EXTENDS MC

(***************************************************************************
 * Affected Actions: MC forms of every reference Action whose code changed. *
 *************************************************************************)
\* reference: base!TickElect/ExternalElect/StartTransferElection -> ElectEffects (do_elect)
\* code: openraft/src/engine/engine_impl.rs:262-289; openraft/src/core/raft_core.rs:1959-2036,1683-1691
\* reference: base!TickPreElect/ExternalPreElect -> PreElectCore
\* code: openraft/src/engine/engine_impl.rs:297-322
\* reference: base!HandlePreVoteRequest; code: openraft/src/engine/engine_impl.rs:413-447
\* reference: base!HandlePreVoteResponse; code: openraft/src/engine/engine_impl.rs:515-554, core/raft_core.rs:1803-1820
\* reference: base!NetworkDefaultPreVote; code: openraft/src/network/v2/network.rs:141-161
\* reference: base!HandleVoteRequest/HandleAppendEntries/RefreshServerState (become_following clears pre_candidate)
\* code: openraft/src/engine/handler/vote_handler/mod.rs:242-244
AffectedActions ==
    \/ \E i \in Server : MCTickElect(i) \/ MCExternalElect(i) \/ MCStartTransferElection(i)
    \/ \E i \in Server : MCTickPreElect(i) \/ MCExternalPreElect(i)
    \/ \E i \in Server : MCRefreshServerState(i)
    \/ \E m \in messages : MCDeliverPreVoteRequest(m) \/ MCDeliverPreVoteResponse(m)
                              \/ MCNetworkDefaultPreVote(m)
                              \/ MCDeliverVoteRequest(m) \/ MCDeliverAppendEntries(m)

(***************************************************************************
 * Interaction Actions: unchanged producers/consumers/faults of the update.  *
 *  - PersistVote / SendVoteRequest / FinishVoteBroadcast / DeliverVoteResp  *
 *    establish the real candidate and leader that a pre-vote round can      *
 *    outlive (establish_leader does not clear pre_candidate).               *
 *  - SendAppendEntries produces the leader contact that clears rounds.      *
 *  - ExpireLease enables pre-vote grants under the lease rule.              *
 *  - Crash/Restart drop rounds (Engine::new).  DropMessage loses replies.   *
 *  - AppendJointConfig/AppendUniformConfig/CommitMembership change the      *
 *    effective config captured by later rounds and real elections; they are *
 *    concrete here because the non-voter-election Scenario depends on them. *
 *************************************************************************)
InteractionActions ==
    \/ \E i \in Server : MCPersistVote(i) \/ MCFinishVoteBroadcast(i)
                           \/ MCExpireLease(i) \/ MCCrash(i) \/ MCRestart(i)
                           \/ MCCommitMembership(i) \/ MCAppendUniformConfig(i)
    \/ \E i \in Server, target \in SUBSET Server : MCAppendJointConfig(i, target)
    \/ \E i \in Server, j \in Server : MCSendVoteRequest(i, j) \/ MCSendAppendEntries(i, j)
    \/ \E m \in messages : MCDeliverVoteResponse(m) \/ MCDropMessage(m)

\* The only reference Action omitted from the concrete focused model.
OmittedContextActions == \E i \in Server : MCFlushLog(i)

FocusedNext == AffectedActions \/ InteractionActions
FocusedSpec == MCInit /\ [][FocusedNext]_mcVars

(***************************************************************************
 * EnvUpdate: rely for the omitted durable-log/config flush.  It may move    *
 * one node's durable log/config shadows to any value between the durable   *
 * and the projected state (here: exactly the projected state or unchanged) *
 * and clear the flush flag, without touching any update-visible variable   *
 * (vote, role, candidate, leader, pre-candidate, messages, effective       *
 * config).  It is weaker than FlushLog: no logFlushPending guard and the   *
 * durable log/config may move independently.                               *
 *************************************************************************)
EnvLogFlush(i) ==
    /\ ~crashed[i]
    /\ durableLastLog' \in {[durableLastLog EXCEPT ![i] = x] : x \in {durableLastLog[i], lastLog[i]}}
    /\ durableConfig' \in {[durableConfig EXCEPT ![i] = c] : c \in {durableConfig[i], effectiveConfig[i]}}
    /\ durableConfigIndex' =
          [durableConfigIndex EXCEPT ![i] = IF durableConfig'[i] = effectiveConfig[i]
                                              /\ durableConfig'[i] /= durableConfig[i]
                                           THEN effectiveConfigIndex[i] ELSE @]
    /\ logFlushPending' \in {[logFlushPending EXCEPT ![i] = b] : b \in {logFlushPending[i], FALSE}}
    /\ UNCHANGED <<runtimeVars, voteVars, candidateVars, leaderVars, lastLog,
                    committedConfig, committedConfigIndex, effectiveConfig,
                    effectiveConfigIndex, messages, preCandidateVars,
                    faultCounters, preOrigin>>

EnvUpdate == \E i \in Server : EnvLogFlush(i)

OpenNext == FocusedNext \/ EnvUpdate
OpenSpec == MCInit /\ [][OpenNext]_mcVars

\* Discharge: every omitted real context step satisfies the rely (frame included).
\* REQ-EVIDENCE DischargeContext
\* intent:   every omitted reference step (FlushLog) is admitted by EnvUpdate with its frame.
\* status:   model-internal
\* watch:    none
\* verified: update
DischargeContext == [][OmittedContextActions => EnvUpdate]_mcVars

(***************************************************************************
 * Helper: a step in which node i consumes a pre-vote response and, because *
 * the round reached a quorum, starts the real election (vote := term+1).   *
 * Only base!HandlePreVoteResponse (wins branch) consumes a PreVoteResp,    *
 * drops the pre-candidate, and bumps the vote in one step.                 *
 *************************************************************************)
PreVoteWinStep(i) ==
    /\ \E m \in messages : m.kind = "PreVoteResp" /\ m.dest = i /\ m \notin messages'
    /\ preCandidateActive[i]
    /\ ~preCandidateActive'[i]
    /\ vote'[i] = Vote(vote[i].term + 1, i, FALSE)

(***************************************************************************
 * Update properties                                                        *
 *************************************************************************)

\* REQ-EVIDENCE TickPreVoteRoundNotHeldByLeader
\* intent:   a Pre-Vote round started by the election timer is never still in flight while its node is the established Leader.
\* status:   requirement
\* evidence: doc source/openraft/src/docs/protocol/pre_vote.md:3 "Pre-Vote is an optional round that a follower runs **before** it increments its" -> a pre-vote round belongs to a non-leader that is about to start an election
\* evidence: doc source/openraft/src/docs/protocol/pre_vote.md:45 "pre-voting: it stays a Follower with its term unchanged until a quorum responds." -> the round's outcome is meaningful only for the state in which it was started
\* evidence: comment source/openraft/src/config/config.rs:400 "When enabled (`Some(true)`), a follower whose election timer fires first asks peers whether they" -> the timer-driven round is a follower's pre-election probe
\* evidence: impl source/openraft/src/core/raft_core.rs:1966 "if self.engine.state.server_state == ServerState::Leader {" -> the timer never starts an election on a Leader
\* evidence: impl source/openraft/src/engine/engine_impl.rs:858 "let candidate = self.candidate.take().unwrap();" -> establish_leader drops only the real candidate
\* watch:    source/openraft/src/engine/engine_impl.rs:Engine::establish_leader; source/openraft/src/engine/handler/vote_handler/mod.rs:VoteHandler::become_leader; source/openraft/src/engine/handler/vote_handler/mod.rs:VoteHandler::become_following; source/openraft/src/core/raft_core.rs:RaftCore::handle_tick_election
\* verified: update
\* note:     precursor state of LeaderNotPreemptedByTimerPreVote. Rounds started by an explicit external trigger are excluded (raft/trigger.rs leaves the leader case unspecified; core/raft_core.rs:1685 "TODO: reject if it is already a leader?").
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:855-881; openraft/src/core/raft_core.rs:1959-2036
\* reference: base!HandleVoteResponse (wins keeps pre-candidate), base!TickPreElect
TickPreVoteRoundNotHeldByLeader ==
    \A i \in Server : (preCandidateActive[i] /\ preOrigin[i] = "tick") => role[i] /= "Leader"

\* REQ-EVIDENCE LeaderNotPreemptedByTimerPreVote
\* intent:   an established Leader never abandons its leadership by starting a new election because a timer-started Pre-Vote round completed.
\* status:   requirement
\* evidence: doc source/openraft/src/docs/protocol/pre_vote.md:17 "healthy leader to step down (the leader observes the higher term while" -> avoiding needless leader step-down and term inflation is the purpose of Pre-Vote (lines 14-20)
\* evidence: comment source/openraft/src/config/config.rs:404 "inflating its term and disrupting a healthy leader once it reconnects." -> Pre-Vote must not disrupt a healthy leader
\* evidence: test source/tests/tests/elect/t12_pre_vote.rs:59 pre_vote_prevents_term_inflation "assert_eq!(leader_term_before, n0.metrics().borrow_watched().current_term);" -> with Pre-Vote enabled a healthy leader keeps its term
\* evidence: impl source/openraft/src/core/raft_core.rs:1966 "if self.engine.state.server_state == ServerState::Leader {" -> the timer path never elects on a Leader
\* evidence: impl source/openraft/src/engine/engine_impl.rs:538 "self.elect();" -> a completed round calls elect() with no role check
\* watch:    source/openraft/src/engine/engine_impl.rs:Engine::handle_pre_vote_resp; source/openraft/src/engine/engine_impl.rs:Engine::establish_leader; source/openraft/src/core/raft_core.rs:RaftCore::handle_notification (PreVoteResponse)
\* verified: update
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:515-554; openraft/src/core/raft_core.rs:1803-1820
\* reference: base!HandlePreVoteResponse
LeaderNotPreemptedByTimerPreVote ==
    [][\A i \in Server : (role[i] = "Leader" /\ preOrigin[i] = "tick") => ~PreVoteWinStep(i)]_mcVars

\* REQ-EVIDENCE PreVoteGrantsWithinFrozenVoters
\* intent:   every grant counted by an active Pre-Vote round comes from a voter of that round's frozen membership (Candidate::grant_by's precondition at the point of counting).
\* status:   requirement
\* evidence: contract source/openraft/src/proposer/candidate.rs:107 "let granted = *self.progress.update(target, true).expect("target not in quorum set");" -> grant_by's precondition: the granting node is in the round's quorum set (violation panics RaftCore)
\* evidence: comment source/openraft/src/core/raft_core.rs:1397 "// Safe unwrap(): target must be in membership" -> vote/pre-vote targets are members of the membership used for the round
\* evidence: doc source/openraft/src/docs/protocol/pre_vote.md:4 "term and starts a real election. It probes whether a quorum *would* grant it a" -> grants are counted towards a quorum of the round's membership
\* watch:    source/openraft/src/core/raft_core.rs:RaftCore::does_pre_candidate_vote_match; source/openraft/src/engine/engine_impl.rs:Engine::handle_pre_vote_resp; source/openraft/src/engine/engine_impl.rs:Engine::pre_elect; source/openraft/src/proposer/candidate.rs:Candidate::grant_by
\* verified: update
\* revised:  replaces the initial in-flight-message form (PreVoteResponseFromFrozenVoter), which also rejected a legal state (a stale non-member grant in flight that a guarded handler ignores) in the repaired-model control spec/evidence/mutants/CTRL-D-voter-recheck-repeat.
\* note:     the runtime correlates responses by leader_id only (raft_core.rs:2067-2090); a round re-issued at the same hypothetical vote over a different membership accepts responses from the older round.
\* UPDATE-MAP
\* code: openraft/src/core/raft_core.rs:1803-1820,2067-2090; openraft/src/engine/engine_impl.rs:533-541
\* reference: base!HandlePreVoteResponse, base!PreElectCore
PreVoteGrantsWithinFrozenVoters ==
    \A i \in Server :
        preCandidateActive[i] => preGrants[i] \subseteq ConfigVoters(preCandidateConfig[i])

\* REQ-EVIDENCE CandidateGrantsWithinFrozenVoters
\* intent:   every grant counted by an active real candidate (including its local self-grant) comes from a voter of the candidate's frozen membership (Candidate::grant_by's precondition at the point of counting).
\* status:   requirement
\* evidence: contract source/openraft/src/proposer/candidate.rs:107 "let granted = *self.progress.update(target, true).expect("target not in quorum set");" -> grant_by's precondition (violation panics RaftCore)
\* evidence: comment source/openraft/src/raft_state/mod.rs:425 "// Openraft does not require Leader/Candidate to be a voter, i.e., a learner node could" -> continues (426) "also be possible to be a leader. Although currently it is not supported."
\* evidence: impl source/openraft/src/core/raft_core.rs:1971 "if !self.engine.state.membership_state.effective().is_voter(&self.id) {" -> the old election callers never elect as a non-voter
\* evidence: impl source/openraft/src/core/raft_core.rs:2294 ".send(Notification::VoteResponse {" -> a saved uncommitted vote always produces a local self-grant (lines 2290-2302)
\* watch:    source/openraft/src/engine/engine_impl.rs:Engine::handle_pre_vote_resp; source/openraft/src/engine/engine_impl.rs:Engine::do_elect; source/openraft/src/engine/engine_impl.rs:Engine::handle_vote_resp; source/openraft/src/proposer/candidate.rs:Candidate::grant_by
\* verified: update
\* revised:  replaces the initial in-flight-message form (VoteResponseFromFrozenVoter) for the same reason as PreVoteGrantsWithinFrozenVoters.
\* note:     interaction property: observes the new pre-vote election path through the unchanged vote-response consumer. Holds in the exact-old model because every old elect() caller required is_voter.
\* UPDATE-MAP
\* code: openraft/src/engine/engine_impl.rs:262-289,449-470,535-539; openraft/src/core/raft_core.rs:2290-2302
\* reference: base!ElectEffects (non-voter branch), base!PersistVote, base!HandleVoteResponse
CandidateGrantsWithinFrozenVoters ==
    \A i \in Server :
        candidateActive[i] => grants[i] \subseteq ConfigVoters(candidateConfig[i])

\* REQ-EVIDENCE PreVoteElectionAtProbedVote
\* intent:   when a Pre-Vote quorum starts the real election, the election uses exactly the hypothetical vote that was probed.
\* status:   requirement
\* evidence: doc source/openraft/src/docs/protocol/pre_vote.md:31 "a Pre-Vote request to its peers asking: *"would you grant me a vote at" -> the probe is for term + 1 (line 32)
\* evidence: doc source/openraft/src/docs/protocol/pre_vote.md:47 "If a quorum would grant, the node runs the real election" -> the real election follows the probe
\* evidence: test source/openraft/src/engine/tests/handle_pre_vote_resp_test.rs:55 test_handle_pre_vote_resp_quorum_starts_real_election "assert_eq!(" -> vote (1,1) after a pre-vote at (1,1) (lines 55-59)
\* watch:    source/openraft/src/engine/engine_impl.rs:Engine::handle_pre_vote_resp; source/openraft/src/engine/engine_impl.rs:Engine::do_elect; source/openraft/src/engine/engine_impl.rs:Engine::pre_elect
\* verified: update
PreVoteElectionAtProbedVote ==
    [][\A i \in Server : PreVoteWinStep(i) => vote'[i] = preCandidateVote[i]]_mcVars

\* REQ-EVIDENCE PreVoteStepsDoNotPersist
\* intent:   handling a Pre-Vote request or a non-deciding Pre-Vote response changes no vote, persisted vote, pending persistence, or server role.
\* status:   requirement
\* evidence: doc source/openraft/src/docs/protocol/pre_vote.md:42 "The crucial difference from a real vote: handling a Pre-Vote request **persists" -> (43) "nothing and changes nothing** — no term bump, no saved vote, no lease update."
\* evidence: doc source/openraft/src/docs/protocol/pre_vote.md:44 "is a pure query. Likewise, the requester does not change its own state while" -> the requester is unchanged until a quorum responds
\* evidence: test source/openraft/src/engine/tests/handle_pre_vote_resp_test.rs:88 test_handle_pre_vote_resp_reject_keeps_waiting "assert_eq!(vote_before, *eng.state.vote_ref());" -> a rejected response changes no vote
\* watch:    source/openraft/src/engine/engine_impl.rs:Engine::handle_pre_vote_req; source/openraft/src/engine/engine_impl.rs:Engine::handle_pre_vote_resp
\* verified: update
\* note:     also validated against the implementation by Trace.tla post-state checks on HandlePreVoteRequest/HandlePreVoteResponse events.
PreVoteStepsDoNotPersist ==
    [][(\E m \in messages : m.kind \in {"PreVoteReq", "PreVoteResp"} /\ m \notin messages'
                           /\ ~\E i \in Server : PreVoteWinStep(i))
       => UNCHANGED <<vote, durableVote, votePersistPending, role>>]_mcVars

(***************************************************************************
 * Reachability canaries (expected to be VIOLATED; a violation is the       *
 * witness that the Scenario is reachable in the checked configuration).    *
 *************************************************************************)
CanaryNoPreVoteRound == ~\E i \in Server : preCandidateActive[i]
CanaryNoGrantedPreVoteResp == ~\E m \in messages : m.kind = "PreVoteResp" /\ m.granted
CanaryNoLeaseRejectedPreVote ==
    ~\E m \in messages : m.kind = "PreVoteResp" /\ ~m.granted /\ vote[m.source].committed
CanaryNoTickRoundWhileCandidate ==
    ~\E i \in Server : preOrigin[i] = "tick" /\ candidateActive[i]
CanaryNoRoundClearedByFollowing ==
    [][~\E i \in Server : preCandidateActive[i] /\ ~preCandidateActive'[i]
                          /\ vote'[i].node /= i]_mcVars
CanaryNoPreVoteElection == [][~\E i \in Server : PreVoteWinStep(i)]_mcVars
CanaryNoNonVoterCandidate ==
    ~\E i \in Server : candidateActive[i] /\ ~InConfig(i, candidateConfig[i])
CanaryNoRepeatedRoundOtherConfig ==
    ~\E m \in messages : /\ m.kind = "PreVoteResp"
                         /\ preCandidateActive[m.dest]
                         /\ m.reqVote = preCandidateVote[m.dest]
                         /\ m.source \notin ConfigVoters(preCandidateConfig[m.dest])

=============================================================================
