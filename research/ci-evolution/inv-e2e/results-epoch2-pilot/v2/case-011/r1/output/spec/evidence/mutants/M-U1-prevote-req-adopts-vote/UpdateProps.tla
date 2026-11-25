---------------------------- MODULE UpdateProps ----------------------------
(***************************************************************************
 * Step and state predicates of the Pre-Vote update properties, over the   *
 * reference (base) variables only. Update.tla wraps them as [][P]_mcVars  *
 * for model checking; EvidenceTrace.tla wraps them as [][P]_traceVars to  *
 * evaluate the same definitions on validated implementation traces.       *
 *************************************************************************)
EXTENDS base

\* ---------------------------------------------------------------------------
\* Step observers (ghost-free; read only reference variables)
\* ---------------------------------------------------------------------------
ConsumedAt(i, m) == m \in messages /\ m \notin messages' /\ m.dest = i

PreVoteReqHandled(i) ==
    \E m \in messages :
        /\ m.kind = "PreVoteReq"
        /\ ConsumedAt(i, m)
        /\ \E r \in messages' \ messages : r.kind = "PreVoteResp" /\ r.source = i

PreVoteRespConsumed(i) ==
    \E m \in messages : m.kind = "PreVoteResp" /\ ConsumedAt(i, m)

ElectedNow(i) ==
    /\ vote'[i] /= vote[i]
    /\ vote'[i].node = i
    /\ ~vote'[i].committed
    /\ vote'[i].term = vote[i].term + 1

PreVoteElection(i) == PreVoteRespConsumed(i) /\ ElectedNow(i)

PanickedNow(i) == ~crashed[i] /\ crashed'[i]

\* ---------------------------------------------------------------------------
\* Update-specific properties (evidence: spec/invariant-evidence.json)
\* ---------------------------------------------------------------------------

\* REQ-EVIDENCE PreVoteResponderSideEffectFree
\* intent:   handling a Pre-Vote request changes none of the responder's vote, persisted vote, pending vote IO, lease, role, election/leader/pre-vote state, greater-log flag, or log.
\* status:   requirement
\* evidence: doc source/openraft/src/docs/protocol/pre_vote.md:42 "The crucial difference from a real vote: handling a Pre-Vote request **persists" -> nothing is persisted or changed (continues :43 "nothing and changes nothing** — no term bump, no saved vote, no lease update.")
\* evidence: contract source/openraft/src/raft/mod.rs:939 "it *would* grant it a vote at `rpc.vote` (a hypothetical next term). Handling this RPC never persists a" -> API contract: no persisted vote, no term change
\* evidence: comment source/openraft/src/engine/engine_impl.rs:409 "and last-log-id rules, but **without persisting any vote or changing the term**: the local" -> responder state untouched (:410 "state is left untouched and no command is emitted.")
\* evidence: test source/openraft/src/engine/tests/handle_pre_vote_req_test.rs (grant/reject cases assert vote and commands unchanged)
\* evidence: impl source/openraft/src/core/raft_core.rs:1555 "let resp = self.engine.handle_pre_vote_req(req);"
\* watch:    source/openraft/src/engine/engine_impl.rs:Engine::handle_pre_vote_req; source/openraft/src/core/raft_core.rs:RaftCore::handle_pre_vote_request
\* verified: update
PreVoteResponderSideEffectFreeStep ==
      \A i \in Server :
          PreVoteReqHandled(i) =>
              /\ vote'[i] = vote[i]
              /\ durableVote'[i] = durableVote[i]
              /\ votePersistPending'[i] = votePersistPending[i]
              /\ leaseValid'[i] = leaseValid[i]
              /\ role'[i] = role[i]
              /\ candidateActive'[i] = candidateActive[i]
              /\ leaderActive'[i] = leaderActive[i]
              /\ preCandidateActive'[i] = preCandidateActive[i]
              /\ preGrants'[i] = preGrants[i]
              /\ seenGreaterLog'[i] = seenGreaterLog[i]
              /\ lastLog'[i] = lastLog[i]

\* REQ-EVIDENCE PreVoteRequesterSideEffectFree
\* intent:   until a Pre-Vote quorum starts the real election, starting a Pre-Vote round or receiving a Pre-Vote response changes neither the requester's vote (term), persisted vote, pending vote IO, lease, nor role.
\* status:   requirement
\* evidence: doc source/openraft/src/docs/protocol/pre_vote.md:44 "is a pure query. Likewise, the requester does not change its own state while" -> requester state unchanged (:45 "pre-voting: it stays a Follower with its term unchanged until a quorum responds.")
\* evidence: comment source/openraft/src/engine/engine_impl.rs:514 "[`elect`](Self::elect). Receiving a Pre-Vote response never changes any persistent state." -> response handling persists nothing
\* evidence: test source/openraft/src/engine/tests/pre_elect_test.rs:48 test_pre_elect_multi_node_no_mutation "// A pre-vote must NOT bump the term, persist a vote, or change server state." -> pre_elect keeps vote and server state
\* evidence: test source/openraft/src/engine/tests/handle_pre_vote_resp_test.rs:83 test_handle_pre_vote_resp_reject_keeps_waiting "// Peer 2 rejects → no quorum, no real election, and no state mutation." -> rejection keeps vote
\* evidence: impl source/openraft/src/engine/engine_impl.rs:319 "self.output.push_command(Command::SendPreVote {"
\* watch:    source/openraft/src/engine/engine_impl.rs:Engine::pre_elect; source/openraft/src/engine/engine_impl.rs:Engine::handle_pre_vote_resp
\* verified: update
PreVoteRequesterSideEffectFreeStep ==
      \A i \in Server :
          ( /\ (preRound'[i] /= preRound[i] \/ PreVoteRespConsumed(i))
            /\ ~ElectedNow(i)
            /\ ~PanickedNow(i) ) =>
              /\ vote'[i] = vote[i]
              /\ durableVote'[i] = durableVote[i]
              /\ votePersistPending'[i] = votePersistPending[i]
              /\ leaseValid'[i] = leaseValid[i]
              /\ role'[i] = role[i]

\* REQ-EVIDENCE PreVoteElectionAtPreVotedTerm
\* intent:   an election started because a Pre-Vote quorum would grant runs at exactly the term the Pre-Vote asked about (the requester's term + 1 at the time of the round).
\* status:   requirement
\* evidence: doc source/openraft/src/docs/protocol/pre_vote.md:31 "a Pre-Vote request to its peers asking: *\"would you grant me a vote at" -> the round asks about term + 1 (:32 "`term + 1`?\"*")
\* evidence: doc source/openraft/src/docs/protocol/pre_vote.md:42 "If a quorum would grant, the node runs the real election" -> the real election is the one the quorum pre-approved
\* evidence: test source/openraft/src/engine/tests/handle_pre_vote_resp_test.rs:56 test_handle_pre_vote_resp_quorum_starts_real_election "Vote::new(1, 1)," -> the election vote equals the pre-vote (1,1)
\* evidence: impl source/openraft/src/engine/engine_impl.rs:538 "self.elect();"
\* watch:    source/openraft/src/engine/engine_impl.rs:Engine::handle_pre_vote_resp; source/openraft/src/engine/engine_impl.rs:Engine::do_elect
\* verified: update
PreVoteElectionAtPreVotedTermStep ==
      \A i \in Server : PreVoteElection(i) => vote'[i] = preCandidateVote[i]

\* REQ-EVIDENCE PreVoteStaleResponseIgnored
\* intent:   a Pre-Vote response that answers a previous Pre-Vote round of the same node is ignored: it neither changes the current round's tally, nor starts an election, nor stops the node.
\* status:   requirement
\* evidence: comment source/openraft/src/core/raft_core.rs:2066 "/// If a Pre-Vote response is for a previous Pre-Vote round, it is stale and should be ignored." -> previous-round responses must be ignored
\* evidence: comment source/openraft/src/core/raft_core.rs:2080 "\"A message will be ignored because pre-candidate vote changed: \\" -> the filter is meant to discard responses for a different round
\* evidence: comment source/openraft/src/engine/engine_impl.rs:527 "// The Pre-Vote round has finished or been canceled; ignore the delayed response." -> delayed responses of finished/canceled rounds are ignored
\* evidence: impl source/openraft/src/core/raft_core.rs:2078 "if candidate_vote.leader_id() != my_vote.leader_id() {"
\* evidence: impl source/openraft/src/engine/engine_impl.rs:311 "let quorum_granted = self.pre_candidate.as_mut().unwrap().grant_by(&id);"
\* watch:    source/openraft/src/core/raft_core.rs:RaftCore::does_pre_candidate_vote_match; source/openraft/src/core/raft_core.rs:RaftCore::handle_notification (PreVoteResponse); source/openraft/src/engine/engine_impl.rs:Engine::pre_elect; source/openraft/src/engine/engine_impl.rs:Engine::handle_pre_vote_resp
\* verified: update
\* note:     rounds are Candidate instances created by new_pre_candidate; the ghost message field `round` names them. A round reuses the leader id (term+1, self) of every earlier round at the same local term.
PreVoteStaleResponseIgnoredStep ==
      \A i \in Server : \A m \in messages :
          ( /\ m.kind = "PreVoteResp"
            /\ ConsumedAt(i, m)
            /\ m.round /= preRound[i] ) =>
              /\ preGrants'[i] = preGrants[i]
              /\ ~ElectedNow(i)
              /\ ~PanickedNow(i)

\* REQ-EVIDENCE TimerPreVoteElectionFromFollowerState
\* intent:   an election started by a Pre-Vote quorum of a round that the election timer began is run by a voter that is not an established Leader (the round is a follower's probe; a node that became Leader meanwhile does not abandon its leadership for it).
\* status:   mixed
\* clause not-leader: requirement — pre_vote.md:3-5 ("Pre-Vote is an optional round that a follower runs **before** it increments its term and starts a real election"), config.rs:398-404 ("a follower whose election timer fires first asks peers ... This prevents a node that cannot currently win ... from inflating its term and disrupting a healthy leader"), and pre_vote.md:44-45 (the requester "stays a Follower ... until a quorum responds") describe the timer round as a follower's probe that protects a healthy leader; raft_core.rs:1966-1969 skips the election timer for a Leader (impl)
\* clause voter: impl-abstraction — raft_core.rs:1971-1974 skips the timer for non-voters and raft_core.rs:1683-1693 ignores external elect for non-voters ("Node is switched to learner."); no non-implementation text found
\* evidence: doc source/openraft/src/docs/protocol/pre_vote.md:3 "Pre-Vote is an optional round that a follower runs **before** it increments its" -> the timer round belongs to a follower
\* evidence: contract source/openraft/src/config/config.rs:400 "/// When enabled (`Some(true)`), a follower whose election timer fires first asks peers whether" -> the timer pre-vote is a follower's
\* evidence: contract source/openraft/src/config/config.rs:403 "/// cannot currently win — e.g. one that was partitioned, restarted, or has a stale log — from" -> purpose: avoid disrupting a healthy leader (:404 "inflating its term and disrupting a healthy leader once it reconnects.")
\* evidence: doc source/openraft/src/docs/protocol/pre_vote.md:44 "is a pure query. Likewise, the requester does not change its own state while" -> the round's decision presumes the requester state it began with
\* evidence: impl source/openraft/src/core/raft_core.rs:1966 "if self.engine.state.server_state == ServerState::Leader {"
\* evidence: impl source/openraft/src/engine/engine_impl.rs:858 "let candidate = self.candidate.take().unwrap();"
\* watch:    source/openraft/src/core/raft_core.rs:RaftCore::handle_tick_election; source/openraft/src/engine/engine_impl.rs:Engine::establish_leader; source/openraft/src/engine/engine_impl.rs:Engine::handle_pre_vote_resp; source/openraft/src/engine/handler/vote_handler/mod.rs:VoteHandler::become_following
\* verified: update
TimerPreVoteElectionFromFollowerStateStep ==
      \A i \in Server :
          (PreVoteElection(i) /\ preByTimer[i]) =>
              /\ role[i] /= "Leader"
              /\ InConfig(i, effectiveConfig[i])

\* REQ-EVIDENCE PreVoteResponseNeverPanics
\* intent:   no deliverable granted Pre-Vote response that the runtime would forward to the node's current pre-candidate comes from a node outside that round's quorum set (Candidate::grant_by would panic).
\* status:   requirement
\* evidence: contract source/openraft/src/proposer/candidate.rs:107 "let granted = *self.progress.update(target, true).expect(\"target not in quorum set\");" -> grant_by's precondition: the target is in the quorum set
\* evidence: comment source/openraft/src/core/raft_core.rs:1397 "// Safe unwrap(): target must be in membership" -> requests target members of the round's membership
\* evidence: comment source/openraft/src/core/raft_core.rs:2066 "/// If a Pre-Vote response is for a previous Pre-Vote round, it is stale and should be ignored." -> responses of other rounds never reach grant_by
\* evidence: impl source/openraft/src/engine/engine_impl.rs:535 "let quorum_granted = self.pre_candidate.as_mut().unwrap().grant_by(&target);"
\* watch:    source/openraft/src/proposer/candidate.rs:Candidate::grant_by; source/openraft/src/engine/engine_impl.rs:Engine::handle_pre_vote_resp; source/openraft/src/core/raft_core.rs:RaftCore::does_pre_candidate_vote_match
\* verified: update
PreVoteResponseNeverPanics ==
    \A m \in messages :
        ( /\ m.kind = "PreVoteResp"
          /\ m.granted
          /\ ~crashed[m.dest]
          /\ preCandidateActive[m.dest]
          /\ SameLeaderId(m.vote, preCandidateVote[m.dest]) ) =>
            m.source \in ConfigVoters(preCandidateConfig[m.dest])

\* REQ-EVIDENCE PreCandidateTracksNextTerm
\* intent:   an active pre-candidate holds the uncommitted hypothetical vote (term + 1, self) for the node's current term.
\* status:   requirement
\* evidence: comment source/openraft/src/engine/engine_impl.rs:97 "/// A pre-candidate runs a Pre-Vote round — probing whether a quorum would grant a vote — before" -> probe for the next election (:99 "does not change `vote`: no term bump, no persisted vote.")
\* evidence: comment source/openraft/src/engine/engine_impl.rs:147 "/// quorum tracker lives in [`pre_candidate`](Self::pre_candidate) and `vote` is only a" -> hypothetical next-term vote (:148 "hypothetical next-term vote that is never persisted.")
\* evidence: test source/openraft/src/engine/tests/pre_elect_test.rs:54 test_pre_elect_multi_node_no_mutation "assert_eq!(Vote::new(1, 1), *eng.pre_candidate_ref().unwrap().vote_ref());" -> (term+1, self, uncommitted)
\* evidence: impl source/openraft/src/engine/engine_impl.rs:299 "let new_term = self.state.vote.term().next();"
\* watch:    source/openraft/src/engine/engine_impl.rs:Engine::pre_elect; source/openraft/src/engine/handler/vote_handler/mod.rs:VoteHandler::become_following; source/openraft/src/engine/engine_impl.rs:Engine::do_elect
\* verified: update
PreCandidateTracksNextTerm ==
    \A i \in Server :
        preCandidateActive[i] =>
            /\ preCandidateVote[i].node = i
            /\ ~preCandidateVote[i].committed
            /\ preCandidateVote[i].term = vote[i].term + 1

=============================================================================
