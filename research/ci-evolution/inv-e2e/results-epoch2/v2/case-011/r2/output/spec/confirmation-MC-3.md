# Confirmation — MC-3: repeated Pre-Vote round counts a delayed grant from a removed node (RaftCore panic)

- **Source**: MC (counterexample `spec/output/upd-hunt-repeat-round-cont.log`
  + `spec/output/cex/repeat-round.json`; property `PreVoteGrantsWithinFrozenVoters`,
  initially found under the in-flight form `PreVoteResponseFromFrozenVoter`; that
  first log was overwritten by the rerun under the revised property — see
  `spec/changelog.md`)
- **Novelty**: NEW — no in-tree report; external trackers not consulted (blinded run).
- **Status**: REPRODUCED (Level 1: public API + RPC pre/post hooks)
- **Severity**: Medium (RaftCore panic; needs two Pre-Vote rounds at the same
  hypothetical vote with a membership change in between and a delayed grant)
- **Update attribution**: introduced by the update (Pre-Vote rounds and their
  leader-id-only correlation are new).
- **Location**: `openraft/src/core/raft_core.rs:2067-2090`
  (`does_pre_candidate_vote_match` compares leader ids only),
  `openraft/src/engine/engine_impl.rs:297-322` (`pre_elect` re-probes
  `(term+1, self)` while the vote is unchanged), `openraft/src/engine/engine_impl.rs:533-536`
  (`grant_by(&target)` for any granted response), `openraft/src/proposer/candidate.rs:106-107`.

## Investigation

**Code audit.** Real elections bump the term on every attempt, so a real
`VoteResponse` that matches the candidate vote always belongs to the current
round. A Pre-Vote does not change the vote; every round started at the same vote
probes the same `(term+1, self)`. The runtime forwards a `PreVoteResponse` when a
round exists with the same leader id (raft_core.rs:1803-1820, 2067-2090), and
`handle_pre_vote_resp` calls `grant_by(&target)` for any granted response
(engine_impl.rs:533-536). If the membership changed between the rounds and the
responder is not a voter of the new round's frozen membership, `grant_by`'s
`expect("target not in quorum set")` panics.

**Reachability.** Rounds at the same vote are produced by repeated
`trigger().elect(true)` calls (any time, including on a Leader whose vote does
not change) and by a timer that re-issues a round after its rate limit
(raft_core.rs:2014-2022). Vote RPCs live up to `election_timeout_min`
(raft_core.rs:1403), so a slow grant from the first round can reach the second.
For the follower timer variant the round is cleared by leader contact and the
re-issue needs lease + election timeout, which normally exceeds the RPC
lifetime; the explicit-trigger variant has no such constraint.

**Developer knowledge.** The candidate's `expect` and the comment
"Safe unwrap(): target must be in membership" (raft_core.rs:1397) state the
precondition; the Pre-Vote docs/tests do not discuss repeated rounds.

## Trigger scenario

MC trace (`upd-hunt-repeat-round-cont.log`, 16 states): ExternalElect(1),
PersistVote(1), ExternalPreElect(1) [round A at (2,1) over {1,2,3}, started while
Candidate], vote/pre-vote exchanges (node 3 grants round A, delayed) -> Leader;
AppendJointConfig(1, {1,2}), CommitMembership(1), AppendUniformConfig(1)
[effective {1,2}]; ExternalPreElect(1) [round B at the same (2,1) over {1,2}];
node 3's round-A grant delivered -> counted by round B -> property violated.

Runtime reproduction: leader 0 runs round A over {0,1,2}; node 2's pre-vote RPCs
fail (pre-hook), node 1's first answer is delayed 400 ms (post-hook);
`change_membership({0,2}, retain)` removes node 1; round B over {0,2}; node 1's
delayed grant arrives.

## Reproduction

- Test: `spec/repro/t90_specular_pre_vote_repro.rs::specular_mc3_repeated_pre_vote_round_accepts_removed_node_grant`
  (runner `spec/repro/test_bug3_mc3_repeated_round_removed_grant_panic.sh`,
  script check `spec/repro/test_bug3.script-check.log`).
- Result: 3/3 debug runs, the runner script and the release run fail as expected:

```
thread 'tokio-rt-worker' (12755) panicked at openraft/src/proposer/candidate.rs:107:59:
target not in quorum set: false
OUTCOME: node0 term=1 state=Leader running_state=Ok(()) voters=[0, 2] n1_answers=1
CORE: node0 Err("panicked")
BUG REPRODUCED (MC-3): a delayed Pre-Vote grant from removed node 1 (round A) was counted by round B (same leader id, membership without node 1) and RaftCore stopped: Err("panicked")
```

  Backtrace: `Candidate::grant_by` (candidate.rs:107) <-
  `Engine::handle_pre_vote_resp` (engine_impl.rs:535) <-
  `RaftCore::handle_notification` (raft_core.rs:1817).
- Expected behaviour: the stale grant is ignored. Control with the candidate
  repair (`spec/repro/fixctl-control.patch`): test passes (`...fixctl.log`).

## Old-revision control

Not runnable: the old revision has no Pre-Vote (`Config::enable_pre_vote`,
`Trigger::elect(bool)`, `Engine::pre_elect` are absent), so the reproduction does
not compile there; the defect is attributed to the update by source comparison
(every old `elect()` caller checks `is_voter`; rounds and their leader-id
correlation do not exist in the old revision).

## Recommendation

Correlate Pre-Vote responses with the round instance (e.g. a round id or the
round's start time) rather than the leader id alone, and ignore grants from
nodes outside the round's quorum set instead of panicking.
