# Confirmation — MC-2: a stale Pre-Vote grant from a node outside the current round's voter set panics RaftCore

- **Source**: MC (actual counterexample: `Update_hunt_stale_membership.cfg`, invariant `PreVoteGrantFromRoundMember`, 15 states, `spec/output/MC-2_hunt_stale_membership_PreVoteGrantFromRoundMember.out`); the mechanism was first identified in the Generation completeness reread and the model was repaired to represent the `expect` before the hunt
- **Revision**: artifact `update` 3ab6cdd. **Update attribution**: introduced by the update (Pre-Vote rounds and
  their leader-id-only correlation do not exist in `baseline`).
- **Status**: **REPRODUCED** (escalation Level 1 — delivery delay of already-produced replies in the test network)
- **Severity**: High (a node's RaftCore task panics — the node stops serving until restarted; reachable on a
  leader as well as a follower; panics in release builds too because it is an `expect`, not a `debug_assert`)
- **Novelty**: no prior Specular record (`specular findings lookup` returned `[]`); external trackers not
  searched (isolation contract), so upstream novelty is undetermined.

## Phase 1 — Investigation
### Code audit
1. Correlation is by leader id only: `does_pre_candidate_vote_match` compares
   `candidate_vote.leader_id()` with the current pre-candidate's (`raft_core.rs:2067-2090`); a round's vote is
   `(state.vote.term + 1, self)` (`engine_impl.rs:298-302`), so **every round started from the same local
   vote has the same key**. The doc comment states the intent: "If a Pre-Vote response is for a previous
   Pre-Vote round, it is stale and should be ignored." (`raft_core.rs:2066`).
2. Each round freezes the effective voter set: `new_pre_candidate` (`engine_impl.rs:149-165`) →
   `Candidate::new` builds the progress tracker from the quorum set only (`proposer/candidate.rs:66-82`).
3. `handle_pre_vote_resp` → `grant_by(&target)` (`engine_impl.rs:534-535`) →
   `self.progress.update(target, true).expect("target not in quorum set")` (`proposer/candidate.rs:106-107`);
   `VecProgress::update_with` returns `Err` for an unknown id (`progress/vec_progress.rs:177-189`).
4. Old path is safe: real-vote rounds always use a new term (`do_elect`), and a response counts only if its
   full vote equals the candidate vote (`engine_impl.rs:463-470`).
### Trigger scenario
A node runs Pre-Vote round 1 while a peer P is a voter; P grants (no leader lease) and the reply is delayed;
the voter set then changes so that P is no longer a voter (membership change; on a follower it arrives by
AppendEntries, which drops round 1 via `become_following` without changing the local vote); the node runs
round 2 from the same local vote (same key) with the new voter set; P's delayed round-1 grant arrives within
the RPC timeout, passes the filter, and reaches `grant_by` with a non-member.
Rounds can be restarted from the same vote by `Trigger::elect(true)` (no timing constraint) or by the tick
after `election_timeout` (`raft_core.rs:2014-2024`); the tick path additionally needs the delayed reply to
fit within `election_timeout_min` (`raft_core.rs:1403`).
### Developer evidence (in-tree)
- `raft_core.rs:2066` and `:2038-2039`: stale responses "should be ignored" / "should be just ignored".
- No test covers two rounds with the same key and different voter sets.

### Model counterexample (15 states)
1-3. node 1 Candidate at term 1, self vote persisted; 4. `MCTickPreElect(1)` while Candidate: round 1 `(2,1)`
with voters {1,2,3}; 5-9. node 2 grants the real vote, node 1 becomes Leader at term 1 (round 1 survives —
the MC-1 mechanism); 10-13. the Leader removes node 3: `AppendJointConfig({1,2})`, `CommitMembership`,
`AppendUniformConfig`; 14. `MCExternalPreElect(1)` (`Trigger::elect(true)` on the leader): round 2, same key
`(2,1)`, voters {1,2}; 15. node 3 answers the round-1 request with a grant (its vote `(0,3)` carries no lease,
logs equal) — a matching grant from a non-voter of round 2 is in flight; delivering it is
`HandlePreVoteResponseNonMember` (RaftCore panic).
The integration reproduction exercises the same `grant_by` site without depending on MC-1 (follower and
leader rounds both started by `Trigger::elect(true)`).

## Phase 2 — Reproduction
- Test: `spec/repro/test_bugMC-2_stale_pre_vote_grant_nonmember.rs` (installed by
  `spec/repro/specular-repro-all.patch`; run `spec/repro/run-all-repro.sh`). Level 1: the router knob delays
  delivery of node 2's round-1 Pre-Vote reply by 1500 ms (< 2000 ms RPC timeout); the other peer's Pre-Vote
  replies are delayed past the RPC timeout so no round completes by itself. Membership change via
  `Raft::change_membership({0,1}, false)`; rounds via `Trigger::elect(true)`. No production code changed.
- Command: `RUSTUP_TOOLCHAIN=nightly-2026-03-01 timeout 15m cargo test -p tests --test elect t14_specular_repro -- --test-threads=1 --nocapture` (and `--release`).

### Output — debug (`spec/repro/MC-2-repro-debug.log`; reruns `-run2`, `-run3`: 3/3)
```
thread 'tokio-rt-worker' panicked at openraft/src/proposer/candidate.rs:107:59:
target not in quorum set: false
SPECULAR-REPRO-CR2: prober=1 change_membership=true core_alive=false state=Follower term=1 voters=[0, 1]
SPECULAR-REPRO-CR2: prober=0 change_membership=true core_alive=false state=Leader term=1 voters=[0, 1]
```
### Output — release (`spec/repro/MC-2-repro-release.log`)
```
thread 'tokio-rt-worker' panicked at openraft/src/proposer/candidate.rs:107:59:
target not in quorum set: false
SPECULAR-REPRO-CR2: prober=1 change_membership=true core_alive=false state=Follower term=1 voters=[0, 1]
```
### Control (same revision, same follower schedule, no membership change)
```
SPECULAR-REPRO-CR2: prober=1 change_membership=false core_alive=true state=Leader term=2 voters=[0, 1, 2]
```
The delayed grant comes from a voter of round 2, is counted, and the follower proceeds to a normal real
election (Leader at term 2). Old-revision control: not applicable (no Pre-Vote in `baseline`).

## Verdict
**REPRODUCED.** Public-API trigger with ordinary message delay; the consequence is a RaftCore panic (node
stops) on followers and leaders, in debug and release builds.

**Recommendation**: correlate Pre-Vote responses per round (e.g. include the round's start time or a round
id in the notification), and/or make `handle_pre_vote_resp` ignore responses from nodes outside the
pre-candidate's quorum set instead of calling `grant_by` unconditionally.
