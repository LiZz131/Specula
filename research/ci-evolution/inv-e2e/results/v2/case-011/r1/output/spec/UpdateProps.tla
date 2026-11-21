---------------------------- MODULE UpdateProps ----------------------------
(***************************************************************************
 * Update properties and step recognizers for the Pre-Vote revision, stated *
 * over base variables only so that the same definitions are evaluated by   *
 * the model-checking lens (Update.tla), by trace replay (evidence/), and   *
 * by one-state evidence modules. Steps that change only MC fault counters  *
 * are stuttering steps for these properties.                               *
 *************************************************************************)
EXTENDS base

(***************************************************************************
 * Step recognizers (structural, evaluated on a step <<s, s'>>).            *
 *************************************************************************)
ConsumedPreVoteResp(i) ==
    \E m \in messages \ messages' : m.kind = "PreVoteResp" /\ m.dest = i

\* The quorum branch of HandlePreVoteResponse: the pre-candidate is consumed
\* by elect() in the same step that consumes a Pre-Vote response.
\* reference: base!HandlePreVoteResponse (quorum disjunct) -> base!ElectEffects
\* code: openraft/src/engine/engine_impl.rs:534-539
PreVoteQuorumElectStep(i) ==
    /\ preCandidateActive[i]
    /\ ~preCandidateActive'[i]
    /\ ~crashed'[i]
    /\ vote'[i] /= vote[i]
    /\ ConsumedPreVoteResp(i)

\* A correlated, granted Pre-Vote response whose processing changed the tally,
\* started the election, or panicked the core.
\* reference: base!HandlePreVoteResponse (grant, quorum and panic disjuncts)
\* code: openraft/src/core/raft_core.rs:1815-1816; openraft/src/engine/engine_impl.rs:534-541
CountedPreVoteGrant(i, m) ==
    /\ m \in messages
    /\ m \notin messages'
    /\ m.kind = "PreVoteResp" /\ m.dest = i /\ m.granted
    /\ preCandidateActive[i]
    /\ SameLeaderId(m.vote, preCandidateVote[i])
    /\ ~crashed[i]
    /\ \/ preGrants'[i] /= preGrants[i]
       \/ ~preCandidateActive'[i]
       \/ crashed'[i]

PreVoteRoundStep(i) ==
    \/ \* pre_elect without self quorum: a round is created, nothing else
       /\ preRound'[i] = preRound[i] + 1
    \/ \* Pre-Vote request handled by i
       \E m \in messages \ messages' : m.kind = "PreVoteReq" /\ m.dest = i
    \/ \* Pre-Vote response handled by i without reaching quorum or panicking
       /\ ConsumedPreVoteResp(i)
       /\ ~PreVoteQuorumElectStep(i)
       /\ ~crashed'[i]

(***************************************************************************
 * Update properties (evidence: spec/invariant-evidence.json).              *
 *************************************************************************)

\* REQ-EVIDENCE TimerPreVoteElectsOnlyNonLeader
\* intent:   a real election started by a Pre-Vote quorum of a timer-originated round never starts on a node whose server state is Leader; a healthy leader is not disrupted by an election timer path.
\* status:   requirement
\* evidence: comment openraft/src/core/raft_core.rs:1964-1968 "TODO: leader lease should be extended. Or it has to examine if it is leader before electing." + "skip election, already a leader" -> the timer must not start an election on a Leader
\* evidence: doc openraft/src/docs/protocol/pre_vote.md:3-6 "Pre-Vote is an optional round that a follower runs **before** it increments its term and starts a real election." -> the election that follows a Pre-Vote round is a follower's election
\* evidence: doc openraft/src/docs/protocol/pre_vote.md:21-26 "Pre-Vote addresses the complementary problem — it stops the term from ever climbing, so there is no higher term to disrupt the leader with on reconnect." -> a Pre-Vote round must not be the cause of a leader disruption
\* evidence: doc openraft/src/config/config.rs:397-404 "a follower whose election timer fires first asks peers whether they *would* grant it a vote at `term + 1` ... Only after a quorum would grant does it run the real election." -> the real election is the deferred continuation of the follower's timer election
\* evidence: contract openraft/src/engine/engine_impl.rs:977-982 "leader.vote({}) >= state.vote({})" (debug_assert in try_leader_handler) -> while a Leader object exists, the local vote must not exceed the leader's committed vote
\* evidence: impl openraft/src/engine/engine_impl.rs:534-539 "if quorum_granted { ... self.elect(); }"
\* evidence: impl openraft/src/engine/handler/vote_handler/mod.rs:154-161 "} else if self.state.is_leading(&self.config.id) { // candidate, nothing to do"
\* watch:    openraft/src/engine/engine_impl.rs:Engine::handle_pre_vote_resp; openraft/src/engine/engine_impl.rs:Engine::establish_leader; openraft/src/engine/handler/vote_handler/mod.rs:VoteHandler::become_leader; openraft/src/core/raft_core.rs:RaftCore::handle_tick_election
\* verified: update (pre-vote revision)
\* note:     admin rounds (ExternalCommand::Elect { pre_vote: true }) are excluded: they check only is_voter and carry a TODO about leaders (raft_core.rs:1685), so an operator-requested demotion is not forbidden by any cited evidence.
TimerPreVoteElectsOnlyNonLeaderStep ==
    \A i \in Server :
        (PreVoteQuorumElectStep(i) /\ preCandidateByTimer[i]) => role[i] /= "Leader"
TimerPreVoteElectsOnlyNonLeader == [][TimerPreVoteElectsOnlyNonLeaderStep]_vars

\* REQ-EVIDENCE StalePreVoteResponseIgnored
\* intent:   a Pre-Vote response produced for an earlier round never advances (or completes) the tally of the current round.
\* status:   requirement
\* evidence: comment openraft/src/core/raft_core.rs:2066 "If a Pre-Vote response is for a previous Pre-Vote round, it is stale and should be ignored." -> responses of an earlier round must not count
\* evidence: comment openraft/src/core/notification.rs:41-42 "The pre-candidate vote (the hypothetical next-term vote) this response answers." -> responses are bound to the round that asked
\* evidence: doc openraft/src/docs/protocol/pre_vote.md:43-46 "If a quorum would grant, the node runs the real election ... If not, nothing changed, and it retries on a later tick." -> each tick-started round decides from its own answers
\* evidence: impl openraft/src/core/raft_core.rs:2076 "if candidate_vote.leader_id() != my_vote.leader_id() {"
\* evidence: impl openraft/src/core/raft_core.rs:2018-2023 (a round is restarted once older than election_timeout, with the same probed vote)
\* watch:    openraft/src/core/raft_core.rs:RaftCore::does_pre_candidate_vote_match; openraft/src/engine/engine_impl.rs:Engine::pre_elect; openraft/src/engine/engine_impl.rs:Engine::handle_pre_vote_resp
\* verified: update (pre-vote revision)
\* note:     the model's message `round` is history only; the implementation has no round identity besides the probed leader id.
StalePreVoteResponseIgnoredStep ==
    \A i \in Server : \A m \in messages :
        CountedPreVoteGrant(i, m) => m.round = preRound[i]
StalePreVoteResponseIgnored == [][StalePreVoteResponseIgnoredStep]_vars

\* REQ-EVIDENCE PreVoteResponseNeverPanics
\* intent:   handling a Pre-Vote response never panics the Raft core.
\* status:   requirement
\* evidence: contract openraft/src/proposer/candidate.rs:107 "self.progress.update(target, true).expect(\"target not in quorum set\")" -> grant_by callers must only pass quorum-set members
\* evidence: comment openraft/src/core/raft_core.rs:2066 "If a Pre-Vote response is for a previous Pre-Vote round, it is stale and should be ignored." -> a response from another round must not reach grant_by
\* evidence: impl openraft/src/engine/engine_impl.rs:534-535 "if resp.vote_granted { let quorum_granted = self.pre_candidate.as_mut().unwrap().grant_by(&target);"
\* watch:    openraft/src/proposer/candidate.rs:Candidate::grant_by; openraft/src/engine/engine_impl.rs:Engine::handle_pre_vote_resp; openraft/src/core/raft_core.rs:RaftCore::does_pre_candidate_vote_match
\* verified: update (pre-vote revision)
PreVoteResponseNeverPanicsStep ==
    \A i \in Server : ~(~crashed[i] /\ crashed'[i] /\ ConsumedPreVoteResp(i))
PreVoteResponseNeverPanics == [][PreVoteResponseNeverPanicsStep]_vars

\* REQ-EVIDENCE PreVoteProbeMatchesElection
\* intent:   the real election that a Pre-Vote quorum starts asks for exactly the vote the round probed.
\* status:   requirement
\* evidence: doc openraft/src/docs/protocol/pre_vote.md:30-33 "*\"would you grant me a vote at `term + 1`?\"* The request carries a hypothetical next-term vote" -> the probed vote is (term + 1, self)
\* evidence: test openraft/src/engine/tests/handle_pre_vote_resp_test.rs:52-56 "assert_eq!(Vote::new(1, 1), *eng.state.vote_ref(), \"the real election bumped the vote\");" -> after the quorum the vote equals the pre-candidate vote Vote::new(1, 1)
\* evidence: impl openraft/src/engine/engine_impl.rs:266-268 "let new_term = self.state.vote.term().next();"
\* watch:    openraft/src/engine/engine_impl.rs:Engine::do_elect; openraft/src/engine/engine_impl.rs:Engine::pre_elect
\* verified: update (pre-vote revision)
PreVoteProbeMatchesElectionStep ==
    \A i \in Server : PreVoteQuorumElectStep(i) => vote'[i] = preCandidateVote[i]
PreVoteProbeMatchesElection == [][PreVoteProbeMatchesElectionStep]_vars

\* REQ-EVIDENCE PreCandidateProbeIsNextTerm
\* intent:   while a Pre-Vote round is active its probed vote is the node's own uncommitted vote at the current term plus one.
\* status:   requirement
\* evidence: doc openraft/src/config/config.rs:397-399 "asks peers whether they *would* grant it a vote at `term + 1`, without persisting any vote or bumping its term" -> probe is term + 1 while the term is unchanged
\* evidence: test openraft/src/engine/tests/pre_elect_test.rs:53-55 "assert_eq!(Vote::new(1, 1), *eng.pre_candidate_ref().unwrap().vote_ref());" -> probe at term + 1 for self
\* evidence: impl openraft/src/engine/engine_impl.rs:299-301
\* watch:    openraft/src/engine/engine_impl.rs:Engine::pre_elect; openraft/src/engine/handler/vote_handler/mod.rs:VoteHandler::update_vote
\* verified: update (pre-vote revision)
PreCandidateProbeIsNextTerm ==
    \A i \in Server :
        preCandidateActive[i] => preCandidateVote[i] = Vote(vote[i].term + 1, i, FALSE)

\* REQ-EVIDENCE PreVoteRoundPersistsNothing
\* intent:   starting a Pre-Vote round without self quorum, answering a Pre-Vote request, and handling a non-deciding Pre-Vote response change no vote, durable vote, pending vote save, server state, lease, candidate or leader state.
\* status:   requirement
\* evidence: doc openraft/src/docs/protocol/pre_vote.md:40-44 "handling a Pre-Vote request **persists nothing and changes nothing** — no term bump, no saved vote, no lease update. ... the requester does not change its own state while pre-voting" -> both sides unchanged
\* evidence: test openraft/src/engine/tests/pre_elect_test.rs:47-50 "A pre-vote must NOT bump the term, persist a vote, or change server state." -> requester unchanged
\* evidence: test openraft/src/engine/tests/handle_pre_vote_req_test.rs:104-106 -> responder vote, server state and commands unchanged
\* evidence: test openraft/src/engine/tests/handle_pre_vote_resp_test.rs:84-87 -> rejected response changes nothing
\* watch:    openraft/src/engine/engine_impl.rs:Engine::pre_elect; openraft/src/engine/engine_impl.rs:Engine::handle_pre_vote_req; openraft/src/engine/engine_impl.rs:Engine::handle_pre_vote_resp
\* verified: update (pre-vote revision)
PreVoteRoundPersistsNothingStep ==
    \A i \in Server :
          PreVoteRoundStep(i) =>
              /\ vote'[i] = vote[i]
              /\ durableVote'[i] = durableVote[i]
              /\ votePersistPending'[i] = votePersistPending[i]
              /\ role'[i] = role[i]
              /\ leaseValid'[i] = leaseValid[i]
              /\ candidateActive'[i] = candidateActive[i]
              /\ leaderActive'[i] = leaderActive[i]
PreVoteRoundPersistsNothing == [][PreVoteRoundPersistsNothingStep]_vars

(***************************************************************************
 * Reachability canaries (expected to be VIOLATED; a violation is the      *
 * witness that the Scenario path is reachable).                            *
 *************************************************************************)
CanaryNoPreCandidate == \A i \in Server : ~preCandidateActive[i]
CanaryNoRemotePreGrant == \A i \in Server : preGrants[i] \subseteq {i}
CanaryNoLeader == \A i \in Server : role[i] /= "Leader"
CanaryNoCandidate == \A i \in Server : ~candidateActive[i]
CanaryNoLeaderWithTimerPreCandidate ==
    \A i \in Server : ~(role[i] = "Leader" /\ preCandidateActive[i] /\ preCandidateByTimer[i])
CanaryNoPreVoteElect == [][\A i \in Server : ~PreVoteQuorumElectStep(i)]_vars
CanaryNoPreVoteReject ==
    \A m \in messages : m.kind = "PreVoteResp" => m.granted
CanaryNoStaleCorrelatedPreVoteResp ==
    \A m \in messages :
        ~(/\ m.kind = "PreVoteResp"
          /\ preCandidateActive[m.dest]
          /\ SameLeaderId(m.vote, preCandidateVote[m.dest])
          /\ m.round /= preRound[m.dest])

=============================================================================
