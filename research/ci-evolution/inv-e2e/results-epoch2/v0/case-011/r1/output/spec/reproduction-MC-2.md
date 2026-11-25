# MC-2: a delayed Pre-Vote grant from a node removed between two same-term rounds panics RaftCore

Origin: the U5 membership hunt first produced a counterexample to the structural
invariant `PreVoteTrackerWellFormed` that depended on a response crossing a
crash/restart (a model artifact, repaired in `base!Restart`, Case B). Reading the
implementation behind that invariant showed that the mechanism is real without
any crash; after the repair, simulation of the complete `MCNext`
(`Update-full-noU2.cfg`) found a crash-free counterexample (31 states,
`spec/output/Update-full-noU2_sim_violation.out`): node 2's timer round as a
Candidate (config {1,2,3}) collects grants, node 2 wins (round kept, MC-1
state), changes the membership to {1,2}, an operator `Trigger::elect(true)` on
node 2 starts a same-term round with config {1,2}, and node 3's delayed grant to
the first round is counted (`PreVoteTrackerWellFormed` violated). In the
implementation that grant reaches `Candidate::grant_by`, which panics.

## Mechanism

- `Engine::pre_elect` always probes `(vote.term + 1, self)`; while the local vote
  term is unchanged, every round has the same leader id
  (`openraft/src/engine/engine_impl.rs:298-303`).
- RaftCore accepts a `Notification::PreVoteResponse` when a tracker exists and the
  response's `candidate_vote` has the tracker's leader id
  (`openraft/src/core/raft_core.rs:1803-1820, 2066-2090`); it cannot tell rounds apart.
- `Engine::handle_pre_vote_resp` calls `grant_by(&target)` on a grant
  (`engine_impl.rs:534-535`), and `Candidate::grant_by` does
  `self.progress.update(target, true).expect("target not in quorum set")`
  (`openraft/src/proposer/candidate.rs:105-107`); `VecProgress::update_with`
  returns `Err` for an id outside the frozen quorum set
  (`openraft/src/progress/vec_progress.rs:177-189`).
- Hence: round 1 sent to node j; j is removed by a membership change; round 2 at
  the same term with the new config; j's delayed grant to round 1 arrives while
  round 2 is live -> panic. Real votes are not exposed in the same way because
  every election uses a new term (new leader id).

## Reachability

- Rounds are started by the timer or by `Trigger::elect(true)`. The timer restarts
  a round only after `election_timeout` (>= `election_timeout_min` = the Pre-Vote
  RPC timeout), and a follower's config changes only through AppendEntries, which
  runs `become_following` and re-arms the lease, so a timer-only path is blocked
  by the RPC timeout. An operator calling `Trigger::elect(true)` again (follower
  or leader) after a membership change reaches it within the RPC timeout.
- On a follower, every heartbeat also runs `become_following` and drops the live
  round, so the delayed grant must arrive before the next heartbeat (the
  integration test disables heartbeats to make this deterministic).

## Evidence (updated revision `3ab6cdd`)

| Test | Result |
|---|---|
| `openraft/src/engine/tests/specula_repro_test.rs::specula_repro_stale_pre_vote_grant_leader_variant` (the MC counterexample shape: Candidate round kept by the new Leader, Leader removes node 3 via `leader_append_entries`, second round, delayed grant of node 3) | FAILS: `panicked at openraft/src/proposer/candidate.rs:107:59: target not in quorum set` (`spec/output/repro-engine-stale-grant.log`) |
| `openraft/src/engine/tests/specula_repro_test.rs::specula_repro_stale_pre_vote_grant_from_removed_member` (real `Engine::append_entries` delivers joint + uniform configs) | FAILS: `panicked at openraft/src/proposer/candidate.rs:107:59: target not in quorum set` (`spec/output/repro-engine-stale-grant.log`) |
| `tests/tests/elect/t93_specula_stale_pre_vote_grant_removed_member.rs` (4 nodes, `change_membership([0,1,2])`, node 3's grant delayed 1500 ms) | FAILS: `tokio-rt-worker panicked at openraft/src/proposer/candidate.rs:107:59: target not in quorum set`; RaftCore probe `Err(Panicked)` (`spec/output/repro-integration-stale-grant.log`) |
| Same integration test with heartbeats enabled (first attempt) | no panic: node 3 granted, but a heartbeat dropped round 2 before the grant arrived (`spec/output/repro-integration-stale-grant-heartbeat-attempt.txt`) |

Severity estimate: Medium (node crash through a public API plus timing; release
builds affected because it is an `expect`).
