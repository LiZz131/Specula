# Confirmation — MC-2: completed Pre-Vote round elects a node that left the voters (RaftCore panic)

- **Source**: MC (counterexample `spec/output/upd-hunt-nonvoter-cont.log` +
  `spec/output/cex/nonvoter.json`, property `CandidateGrantsWithinFrozenVoters`;
  first found under the initial in-flight form `VoteResponseFromFrozenVoter`,
  same trace prefix)
- **Novelty**: NEW — no in-tree report; external trackers not consulted (blinded run).
- **Status**: REPRODUCED (Level 1: public API + RPC post-hook delay)
- **Severity**: Medium (RaftCore panic -> node stops; needs a Pre-Vote round in
  flight while the node removes itself from the voters)
- **Update attribution**: introduced by the update. Every old `elect()` caller
  checked `is_voter` (raft_core.rs:1683-1684, 1971-1974); the new caller
  `handle_pre_vote_resp` (engine_impl.rs:535-539) does not.
- **Location**: `openraft/src/engine/engine_impl.rs:515-554` (elect on quorum
  without voter re-check), `openraft/src/engine/engine_impl.rs:262-289`
  (`do_elect` builds the candidate over the current effective voters),
  `openraft/src/core/raft_core.rs:2290-2302` (local self-grant after
  `save_vote`), `openraft/src/proposer/candidate.rs:106-107`
  (`grant_by` `expect("target not in quorum set")`).

## Investigation

**Code audit.** A Pre-Vote round's quorum is counted on the membership frozen
when the round started (new_pre_candidate, engine_impl.rs:149-165). Membership
can change while the round is in flight on a Leader (its own appends do not go
through `become_following`). When the round completes, `elect()` runs with no
check of the current membership. `do_elect` builds a `Candidate` whose quorum set
is the current effective voters, which no longer contain the node; if the node
is still a member as learner, `is_leading` holds (raft_state/mod.rs:453-455) and
the candidate survives `update_internal_server_state`. After `SaveVote`, the
runtime always sends the node's own granted `VoteResponse`
(raft_core.rs:2290-2302); the runtime gate passes (candidate present, same
vote) and `handle_vote_resp` calls `candidate.grant_by(&self.id)`
(engine_impl.rs:468), which panics because the node is not in the quorum set.

**Reachability.** Two producers keep a round alive into a self-removal: the
MC-1 stale timer round (model trace) and an explicit `trigger().elect(true)` on
the leader (`ExternalCommand::Elect { pre_vote: true }` accepts any voter,
including a Leader — raft_core.rs:1683-1689, "TODO: reject if it is already a
leader?"). The leader keeps running after removing itself until its step-down
policy acts, so responses arriving within the RPC timeout are processed.

**Developer knowledge.** raft_state/mod.rs:425-427: "Openraft does not require
Leader/Candidate to be a voter ... Although currently it is not supported."
`grant_by`'s `expect` documents the precondition. No test covers a round
completing after a membership change.

## Trigger scenario

MC trace (2-node universe): ExternalElect(1), PersistVote(1), TickPreElect(1)
[round at term 2, frozen {1,2}], SendVoteRequest(1,2), deliveries -> node 1
Leader (round kept, MC-1), AppendJointConfig(1, {2}), CommitMembership(1),
AppendUniformConfig(1) [effective {2}], PreVoteResponse delivered -> quorum on
the frozen {1,2} -> elect as learner-member Candidate over {2}, PersistVote(1)
-> self grant counted -> `CandidateGrantsWithinFrozenVoters` violated (state 17).

Runtime reproduction uses the second producer (explicit pre-vote trigger on
the leader) to reach the same code path deterministically.

## Reproduction

- Test: `spec/repro/t90_specular_pre_vote_repro.rs::specular_mc2_pre_vote_round_elects_removed_voter`
  (runner `spec/repro/test_bug2_mc2_nonvoter_elect_panic.sh`).
- Steps: 3-node cluster, leader 0; elections disabled on all nodes; leader
  heartbeats disabled until follower leases expire; post-hook delays the
  followers' answers to node 0's Pre-Vote by 300 ms (< 1000 ms RPC timeout);
  `n0.trigger().elect(true)`; `n0.change_membership({1,2}, retain=true)`.
- Result: 3/3 debug runs and the release run fail as expected
  (`...run2..run4.log`, `...release.log`; `...run1-superseded-metrics-oracle.log`
  used an oracle reading stale metrics and is superseded):

```
thread 'tokio-rt-worker' (12655) panicked at openraft/src/proposer/candidate.rs:107:59:
target not in quorum set: false
OUTCOME: node0 term=1 state=Leader running_state=Ok(()) voters=[1, 2]
CORE: node0 Err("panicked")
BUG REPRODUCED (MC-2): node 0's Pre-Vote round completed after it left the voters; elect() ran for a non-voter and RaftCore stopped: Err("panicked")
```

  Backtrace (`...backtrace.log`): `Candidate::grant_by` (candidate.rs:107) <-
  `Engine::handle_vote_resp` (engine_impl.rs:468) <-
  `RaftCore::handle_notification` (raft_core.rs:1798) — the self-grant of the
  non-voter candidate, as in the counterexample.
- Expected behaviour: the stale round is ignored (or the node does not elect
  as a non-voter) and RaftCore keeps running. Control with the candidate repair
  (`spec/repro/fixctl-control.patch`): test passes,
  `CORE: node0 Ok(("<T1-N0:Q>", Leader))` (`...fixctl.log`).

## Old-revision control

Not runnable: the old revision has no Pre-Vote (`Config::enable_pre_vote`,
`Trigger::elect(bool)`, `Engine::pre_elect` are absent), so the reproduction does
not compile there; the defect is attributed to the update by source comparison
(every old `elect()` caller checks `is_voter`; rounds and their leader-id
correlation do not exist in the old revision).

## Recommendation

In `handle_pre_vote_resp`, re-check before `elect()` that the node is still a
voter of the current effective membership (as the old callers do) and drop the
round otherwise; also clear `pre_candidate` on leadership (MC-1) and on any
membership change that removes the node.
