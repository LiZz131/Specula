# Confirmation — MC-1: Pre-Vote responses of an earlier round are accepted by a later round

- **Source**: MC (actual counterexample `spec/output/cex-update-full-PreVoteStaleResponseIgnored.log`, property `PreVoteStaleResponseIgnored`, config `Update_full.cfg`)
- **Novelty**: NEW (no prior Specular record — `specular findings lookup` returned none; blind run, external trackers not consulted)
- **Status**: REPRODUCED
- **Severity**: High
- **Location**: `openraft/src/core/raft_core.rs:2067-2090` (`does_pre_candidate_vote_match`), `openraft/src/engine/engine_impl.rs:298-322,516-554`, `openraft/src/proposer/candidate.rs:106-112`
- **Source revision**: `artifact/` `3ab6cddc34a5bf127747434bb41e20a1b9ef7769` (update); reproduced on the instrumented copy `work-source/` (same HEAD + test-only files)

## Description

Every Pre-Vote round that a node starts at the same local term uses the same
hypothetical vote `(term+1, self)`, and RaftCore forwards a Pre-Vote response
whenever its `candidate_vote` has the same leader id as the current
pre-candidate. Responses to an earlier round are therefore tallied by the
current round. When the responder is no longer a voter of the current round's
membership, `Candidate::grant_by` panics and the node's RaftCore stops.

## Trigger scenario (model counterexample, 6 states)

Timer round 1 → requests sent → timer restarts round 2 (same leader id) →
round-1 grant from node 3 is counted by round 2 → quorum → real election.

## Investigation (Phase 1)

- Reachability of a second same-term round: timer restart after
  `election_timeout` (`raft_core.rs:2014-2024`), operator `trigger().elect(true)`
  without rate limit (`raft_core.rs:1683-1690`), and a new round after
  `become_following` dropped one (leader contact). Pre-vote RPCs are bounded by
  `ttl = election_timeout_min` (`raft_core.rs:1403`), which narrows the
  timer-restart window but not the operator path or notification queueing.
- Developer intent: `raft_core.rs:2066` "If a Pre-Vote response is for a previous
  Pre-Vote round, it is stale and should be ignored."; the stale-filter warning
  text "pre-candidate vote changed" (`:2080`) shows the filter is meant to
  separate rounds. `candidate.rs:107` `expect("target not in quorum set")`
  states the tally precondition.
- Engine-level code observation (harness trace
  `traces/prevote_stale_member_panic.ndjson`, validated by `Trace.tla`;
  trace-lens witness `spec/evidence/trace-lens/prevote_stale_member_panic.log`):
  Leader round A over `{1,2,3}`, joint/uniform change to `{1,3}`, round B with
  the same pre-vote `(2,1)`, then a grant from node 2 → `grant_by` panics.

## Reproduction (Phase 2)

- **Test**: `harness/repro/t13_specular_pre_vote_repro.rs::repro_mc1_stale_pre_vote_grant_panics_core`
  (escalation level: integration test through the public `Raft` API and the
  project's `RaftRouter` RPC hooks; the test asserts the correct behavior and
  FAILS when the defect triggers).
- **Command**: `bash harness/repro/run-repro.sh` (debug) and
  `cargo test --release -p tests --test elect t13_specular_pre_vote_repro` (release).
- **Steps**: 3-node cluster, leader n0 (`election_timeout_min=3000`); n0's
  AppendEntries to n2 blocked so n2's lease expires; n0 `trigger().elect(true)`
  (round A, pre-vote `(T+1,0)`), n2 grants (response held by a post-hook);
  `n0.change_membership({0,1}, false)` completes; n0 `trigger().elect(true)`
  (round B, same pre-vote, quorum set `{0,1}`); the held round-A grant from n2 is
  released (within the RPC ttl).
- **Result**: REPRODUCED in debug and release builds. Output
  (`harness/repro/repro-current.log`, `harness/repro/repro-current-release.log`):

```
thread 'tokio-rt-worker' panicked at openraft/src/proposer/candidate.rs:107:59:
target not in quorum set: false
SPECULAR-REPRO MC-1: n0.with_raft_state() after stale grant => Err(Panicked)
```

  Excerpt of the node log: `harness/repro/repro_mc1_stale_pre_vote_grant_panics_core.excerpt.log`.
- **Old-revision control**: not applicable — the old revision has no Pre-Vote
  round, RPC, or `Trigger::elect(bool)`; the defect is introduced by the update.

## Consequence

The leader's RaftCore task panics; every API call returns `Fatal::Panicked`
until the node is restarted. Without a membership change the same defect lets a
grant issued for an earlier round complete the current round, so a node can
increment its term although the current round would be rejected.

## Recommendation

Tag each round (e.g. with the pre-candidate's progress id or starting time) in
the spawned RPC task/notification and require equality in RaftCore; make the
Pre-Vote tally ignore non-members instead of `expect`.
