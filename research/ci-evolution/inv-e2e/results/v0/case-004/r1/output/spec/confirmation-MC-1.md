# Confirmation — MC-1

- **Source**: MC (actual counterexamples `spec/output/MC-1_ElectOnlyByVoter_violation.out`,
  `spec/output/MC-1_NoCorePanic_violation.out`).
- **Status**: REPRODUCED
- **Novelty**: not assessed — issue/PR/advisory search is prohibited by this run's isolation
  contract (`/work/input-manifest.json`); no prior Specula finding exists (V0 froze none).
- **Attribution**: introduced by the update (new `RaftMsg::TransferLeader` path); the
  pre-existing elect() entry points remain guarded on both revisions.
- **Severity**: Medium (availability: target RaftCore panics, healthy leader deposed,
  leaderless until election timeout; no committed-data divergence observed).
- **Location**: `openraft/src/core/raft_core.rs:1190-1202` (missing voter guard);
  panic site `openraft/src/proposer/candidate.rs:92`.

## Investigation (code evidence, update revision)

1. `raft/mod.rs:645-703` `Raft::transfer_leader(from, to, flushed_log)`: no validation of `to`;
   for `to == self` it waits for `metrics.vote == from` (satisfied immediately on a caught-up
   learner) and sends `RaftMsg::TransferLeader`.
2. `core/raft_core.rs:1190-1202`: `if vote == from { disable_lease(); if self.id == to { elect() } }`.
3. `engine/engine_impl.rs:223-249` + `117-135`: candidate quorum = effective voters;
   `raft_state/mod.rs:369-371` keeps the candidate for a learner (`contains` includes learners).
4. `core/raft_core.rs:1669-1681`: SaveVote → `Notification::VoteResponse{target: self.id}`;
   `core/raft_core.rs:1260` → `handle_vote_resp(self.id)` → `candidate.rs:90-96`
   `progress.update(self.id).expect("target not in quorum set")`; `candidate.rs:62-75` builds the
   progress with `VecProgress::new(quorum_set, [], ..)` (no learners).
5. Guarded siblings: `raft_core.rs:1207-1213` (ExternalCommand::Elect, is_voter),
   `raft_core.rs:1452-1455` (tick, is_voter). Documentation: `docs/data/vote.md:50-51`.

## Reproduction

- Test: `harness/repro/test_bugMC-1_transfer_leader_to_learner.rs`, driver
  `harness/repro/run_repro.sh` (copies `artifact/`, adds only the test file, no
  instrumentation). Escalation level: integration test through the public API
  (`RaftRouter` in-process cluster: voters {0,1,2}, learner {3}).
- Result: PASS (bug triggered) 5/5 (`spec/output/repro-MC-1.log`,
  `spec/output/repro-MC-1-run1.log` … `run3.log`; plus the instrumented scenario
  `spec/output/scenario-core-learner.log`). Excerpt:

```
thread 'tokio-rt-worker' panicked at openraft/src/proposer/candidate.rs:92:59:
target not in quorum set: false
REPRO-MC-1 learner n3.is_initialized() after transfer_leader(to=learner) = Err(Panicked)
REPRO-MC-1 n0 state=Follower vote=<T3-N2:Q> current_leader=Some(2)
test result: ok. 1 passed; 0 failed
```

- Observed sequence matches the counterexample: learner holds `<T1-N0:Q>` → TransferLeader →
  candidate at term 2 → self grant → panic; voters granted term 2, old leader 0 stepped down, a
  later election (term 3) chose a leader.
- Controls: `harness/repro/run_control_baseline.sh` (baseline: `trigger().elect()` on the
  learner → `Ok(true)`, still Learner, leader unchanged; `spec/output/control-MC-1-baseline.log`)
  and `harness/repro/run_control_update_trigger.sh` (update: same, guarded;
  `spec/output/control-MC-1-update-trigger.log`).

## Recommendation

Add `if !self.engine.state.membership_state.effective().is_voter(&self.id) { return }` (or
equivalent) before `elect()` in the TransferLeader arm; optionally reject a non-voter `to` in
`Raft::transfer_leader` and make `Candidate::grant_by` tolerate non-quorum targets.
