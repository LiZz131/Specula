# Bug Report — Openraft (update revision d7176ef, leader transfer)

## Summary

- Update Scenarios tested: 5 (U-S1 … U-S5, `modeling-brief.md` §2b)
- Bugs found: 2 model-checking counterexamples, both reproduced on the real implementation:
  MC-1 (introduced by the update) and MC-2 (pre-existing; the update adds a new public trigger)
- Configs with an actual counterexample: `Update_full.cfg` (U1), `Update_full_NoCorePanic.cfg`
  (U2), `Update_focused.cfg`, `Update_open.cfg`, `MC_hunt_transfer_learner.cfg`
- All other campaigns: no violation within their bounds (budget-limited exploration,
  `LIMITED_COVERAGE`; see the table at the end).

## Bug 1: `transfer_leader` to a learner makes the learner run an election and panics its RaftCore

- **ID**: MC-1
- **Scenario**: U-S1 (transfer to a non-voter target)
- **Severity**: Medium — availability, not data safety: a public administrative API call with
  a learner as `to` (no precondition documented or checked) kills that node's RaftCore
  (`Fatal::Panicked`), and because the voters' leases were disabled by the same transfer and
  they grant the learner's higher vote, the healthy leader is deposed; the cluster is leaderless
  until an ordinary election timeout and leadership is not transferred. No committed-log
  divergence was found (U6 holds within bounds).
- **Invariants/properties violated**: `ElectOnlyByVoter` (action property, U1) and
  `NoCorePanic` (invariant, U2), both in `spec/Update.tla`.
- **Counterexamples**:
  - `spec/output/MC-1_ElectOnlyByVoter_violation.out` (10 states, `Update_full.cfg`, full `MCNext`)
  - `spec/output/MC-1_NoCorePanic_violation.out` (12 states, `Update_full_NoCorePanic.cfg`, full `MCNext`)
  - also found by `Update_focused.cfg`, `Update_open.cfg`, `MC_hunt_transfer_learner.cfg`
    (`spec/output/update-focused-c2-allprops.log`, `update-open-c3-allprops.log`,
    `hunt-transfer-learner-bfs.log`).
- **Real trace of the same path**: `traces/core-learner-n3-c0.ndjson`
  (`TransferLeader` → `VoteResponsePanic`), validated by TLC against the final suite
  (`spec/output/trace-core-learner-n3-c0.log`); raw hook output
  `traces/raw-core/core-learner.raw.ndjson`; scenario log `spec/output/scenario-core-learner.log`.

### Trace Summary (`MC-1_NoCorePanic_violation.out`)

1. States 2–8: node 1 is elected leader of voters {1,2} at term 1; node 3 is a learner.
2. State 9 `MCFollowerAppend(3,1)`: learner 3 replicates leader 1's blank entry and accepts the
   leader's committed vote (1,1,committed).
3. State 10 `MCTransfer(3,3)`: `TransferLeader{from = (1,1,committed), to = 3}` reaches node 3.
   The vote matches, so the handler calls `Engine::elect()`: node 3 becomes Candidate with vote
   (2,3) and a candidate quorum of voters {1,2} only (U1 violated here).
4. State 11 `MCPersistVote(3)`: SaveVote completes; RaftCore queues the self VoteResponse.
5. State 12 `MCVoteResponse(3,3)`: `handle_vote_resp(3)` → `Candidate::grant_by(3)` →
   `progress.update(3)` finds no entry → `expect("target not in quorum set")` panics
   (`panicked[3] = TRUE`, U2 violated).

### Root Cause

- `core/raft_core.rs:1190-1202` — the new `RaftMsg::TransferLeader` arm calls
  `self.engine.elect()` whenever `self.id == to` and the local vote equals `from`, with no
  `is_voter` check. Both pre-existing callers check it: `ExternalCommand::Elect`
  (`raft_core.rs:1207-1213`, "Node is switched to learner") and `handle_tick_election`
  (`raft_core.rs:1452-1455`). The documented contract is "a learner does not try to elect
  itself" (`docs/data/vote.md:50-51`).
- `engine/engine_impl.rs:117-135,223-249` — `elect()` builds the candidate from the effective
  membership; `raft_state/mod.rs:369-371` keeps it because a learner is *contained* in the
  membership (`is_leading`).
- `core/raft_core.rs:1669-1681` — SaveVote always delivers the self VoteResponse; it is ahead of
  every remote response in the FIFO notification channel.
- `proposer/candidate.rs:62-75,90-96` — the candidate progress is built from the voter quorum
  set with an empty learner list, and `grant_by` panics for an id outside it.
- `raft/mod.rs:645-703` — the public API forwards the message to the target without
  validating that `to` is a voter.

### Reproduction (real implementation)

- Uninstrumented update tree: `harness/repro/run_repro.sh` with
  `harness/repro/test_bugMC-1_transfer_leader_to_learner.rs` — test passes (= bug reproduced)
  in 5/5 runs (`spec/output/repro-MC-1.log`, `repro-MC-1-run{1,2,3}.log`):
  `panicked at openraft/src/proposer/candidate.rs:92:59: target not in quorum set`,
  `n3.is_initialized() = Err(Panicked)`, old leader 0 deposed; a new leader is elected later at
  term 3 (not the transfer target).
- Controls: baseline commit (no `transfer_leader`; pre-existing `trigger().elect()` on the
  learner) → guarded, learner healthy, leader unchanged (`spec/output/control-MC-1-baseline.log`);
  same control on the update commit → guarded (`spec/output/control-MC-1-update-trigger.log`).
  The defect is introduced by the update's new path.
- Confirmation record: `spec/confirmation-MC-1.md`.

### Affected Code

- `openraft/src/core/raft_core.rs:1190-1202`: TransferLeader handler elects without a voter check.
- `openraft/src/raft/mod.rs:645-703`: `transfer_leader` accepts any `to`.
- `openraft/src/proposer/candidate.rs:90-96`: `grant_by` panics for a non-quorum target.
- `openraft/src/core/raft_core.rs:1669-1681`: unconditional self vote response after SaveVote.

### Recommendation

Guard the transfer the same way as the other elect() callers: in the TransferLeader arm, call
`elect()` only if `self.engine.state.membership_state.effective().is_voter(&self.id)` (and
consider rejecting non-voter `to` in `Raft::transfer_leader`). Defensively, make
`Candidate::grant_by` ignore (not panic on) targets outside its quorum set.

---

## Bug 2: a Leader that runs `elect()` trips the `leader_handler` vote-order assertion (transfer to the current leader)

- **ID**: MC-2
- **Scenario**: U-S4 (transfer whose target is the current leader; candidate+leader coexistence)
- **Severity**: Low — reproduced consequence is a RaftCore panic of the *current leader* in builds
  with debug assertions (openraft's own test configuration); the cluster loses its leader until
  an election timeout. In release builds the assertion is compiled out; whether the leader then
  appends with its stale committed vote in a way that can collide with its re-election blank was
  **not verified** and is not claimed.
- **Invariant violated**: `LeaderVoteNotSuperseded` (U7, `spec/Update.tla`), the model form of
  `debug_assert!(leader.committed_vote >= state.vote)` in `Engine::leader_handler`
  (`engine/engine_impl.rs:765-770`), which RaftCore evaluates on every runtime-loop iteration
  (`core/raft_core.rs:967`).
- **Counterexamples**:
  - new trigger: `spec/output/MC-2_LeaderVoteNotSuperseded_transfer.out` (9 states:
    election of node 1, then `MCTransfer(1,1)`), cfg `Update_full_LeaderVoteNotSuperseded.cfg`;
  - pre-existing trigger with transfers disabled: `spec/output/MC-2_LeaderVoteNotSuperseded_preexisting.out`
    (second `MCElect(1)` on the leader), cfg `Update_preexisting_LeaderVoteNotSuperseded.cfg`.
- **Attribution**: pre-existing. The baseline panics identically through `trigger().elect()` on the
  leader; the update adds `transfer_leader(from = leader vote, to = leader)` as a second public
  trigger (the TransferLeader arm has no not-Leader guard; the tick path has one,
  `raft_core.rs:1446-1449`; `ExternalCommand::Elect` has none, with the comment
  "TODO: reject if it is already a leader?").

### Trace Summary (`MC-2_LeaderVoteNotSuperseded_transfer.out`)

1. States 2–8: node 1 elected leader at (1,1); its Leader object holds committed vote (1,1).
2. State 9 `MCTransfer(1,1)`: TransferLeader{from=(1,1,Q), to=1} reaches the leader; `elect()`
   sets the state vote to (2,1,non-committed) and keeps the Leader object (is_leading) → the next
   `leader_handler()` call asserts `(1,1,Q) >= (2,1,-)`, which is false.

### Reproduction

`harness/repro/run_probe_leader_self_elect.sh update|baseline`
(`probe_leader_self_elect.rs`, `probe_leader_transfer_self.rs`; no instrumentation):

- update, `transfer_leader(vote, 0, ..)` on all nodes with node 0 the leader → node 0
  `panicked at openraft/src/engine/engine_impl.rs:765:9: leader.vote(<T1-N0:Q>) >= state.vote(<T2-N0:->)`,
  `is_initialized() = Err(Panicked)`; another node is elected later
  (`spec/output/probe-leader-self-elect-update.log`);
- update and baseline, `trigger().elect()` on the leader → same panic
  (`spec/output/probe-leader-self-elect-update.log`, `spec/output/probe-leader-self-elect-baseline.log`).

### Affected Code

- `openraft/src/core/raft_core.rs:1190-1202`: TransferLeader elects on a Leader without a guard (new trigger).
- `openraft/src/core/raft_core.rs:1207-1213`: `ExternalCommand::Elect` elects on a Leader (pre-existing trigger).
- `openraft/src/engine/engine_impl.rs:765-770`: assertion contradicting candidate+leader coexistence
  (`proposer/leader.rs:21-27` design comment).
- `openraft/src/core/raft_core.rs:966-969`: unconditional per-iteration `leader_handler()` call.

### Recommendation

Either reject `elect()` on a node that is already Leader (TransferLeader and ExternalCommand::Elect),
or make the leader-handler invariant compare against the Leader's own vote rather than the local
acceptor vote while a re-election is in progress. Also review the release-mode behavior of
appends issued between `elect()` and re-establishment (the establishment blank is numbered from
the candidate's last-log snapshot).

---

## Not Reproduced / no violation within bounds

Filled from the campaign logs; every row is budget- or bound-limited exploration
(`LIMITED_COVERAGE`), never proof.

| Run (log `spec/output/<run>.log`) | cfg | Purpose | Outcome | Coverage | Time |
|---|---|---|---|---|---|
| `mc-standard-round3` | `MC.cfg` | standard convergence round (final reference) | no violation; budget-limited BFS | 290,764,287 gen / 40,710,696 distinct, depth 28, queue 9,739,774 | 1801s |
| `mc-standard-sim` | `MC.cfg` | standard model, simulation depth 100 | no violation; budget-limited simulation | 55157322 states / 546930 traces, mean length 71 | 1800s |
| `update-full-c1-final` | `Update_full.cfg` | C1 full MCNext, all update properties | VIOLATION: ElectOnlyByVoter | 1048 gen / 446 distinct, depth 12 | 2s |
| `update-full-c1-panic-final` | `Update_full_NoCorePanic.cfg` | C1 oracle isolation U2 | VIOLATION: NoCorePanic | 24218 gen / 6936 distinct, depth 14 | 3s |
| `update-full-c1-nonvoterleader-final` | `Update_full_ElectedLeaderWasVoter.cfg` | C1 oracle isolation U5 (after R8) | no violation; budget-limited BFS | 239,110,966 gen / 33,881,195 distinct, depth 27, queue 8,783,686 | 1801s |
| `update-full-u7` | `Update_full_LeaderVoteNotSuperseded.cfg` | C1 U7 with transfer inputs | VIOLATION: LeaderVoteNotSuperseded | 265 gen / 61 distinct, depth 11 | 4s |
| `update-preexisting-u7` | `Update_preexisting_LeaderVoteNotSuperseded.cfg` | U7, transfers disabled (pre-existing path) | VIOLATION: LeaderVoteNotSuperseded | 1202 gen / 294 distinct, depth 11 | 4s |
| `update-full-residual-c1b` | `Update_full_residual.cfg` | C1b full MCNext, remaining properties | no violation; budget-limited BFS | 129,911,888 gen / 19,139,667 distinct, depth 24, queue 6,239,390 | 1802s |
| `update-full-residual-sim` | `Update_full_residual.cfg` | C1b simulation depth 100 | no violation; budget-limited simulation | 38158301 states / 378377 traces, mean length 75 | 1801s |
| `update-focused-c2-allprops` | `Update_focused.cfg` | C2 concrete focused, all update properties | VIOLATION: ElectOnlyByVoter | 566 gen / 315 distinct, depth 11 | 2s |
| `update-focused-residual-c2` | `Update_focused_residual.cfg` | C2 concrete focused, remaining properties | no violation; budget-limited BFS | 108,143,135 gen / 20,362,156 distinct, depth 27, queue 4,717,733 | 1801s |
| `update-open-c3-allprops` | `Update_open.cfg` | C3a open focused (EnvUpdate), all update properties | VIOLATION: ElectOnlyByVoter | 4684 gen / 562 distinct, depth 11 | 3s |
| `update-open-residual-c3a` | `Update_open_residual.cfg` | C3a open focused, remaining properties | no violation; budget-limited BFS | 196,395,740 gen / 14,500,220 distinct, depth 21, queue 6,047,262 | 1801s |
| `update-discharge-c3b` | `Update_discharge.cfg` | C3b discharge of EnvUpdate | no violation; budget-limited BFS | 93,376,911 gen / 14,045,829 distinct, depth 22, queue 4,987,155 | 1801s |
| `hunt-transfer-learner-bfs` | `MC_hunt_transfer_learner.cfg` | hunt U-S1 learner target | VIOLATION: ElectOnlyByVoter | 647 gen / 270 distinct, depth 11 | 2s |
| `hunt-transfer-voter-bfs` | `MC_hunt_transfer_voter.cfg` | hunt U-S3 voter targets, BFS | no violation; budget-limited BFS | 131,014,874 gen / 21,769,338 distinct, depth 22, queue 11,102,725 | 1801s |
| `hunt-transfer-voter-sim` | `MC_hunt_transfer_voter.cfg` | hunt U-S3 voter targets, simulation | no violation; budget-limited simulation | 100357887 states / 990676 traces, mean length 64 | 1801s |
| `hunt-transfer-membership-bfs` | `MC_hunt_transfer_membership.cfg` | hunt U-S4 membership, BFS | no violation; budget-limited BFS | 151,375,212 gen / 23,274,024 distinct, depth 23, queue 9,335,647 | 1801s |
| `hunt-transfer-membership-sim` | `MC_hunt_transfer_membership.cfg` | hunt U-S4 membership, simulation | no violation; budget-limited simulation | 110582921 states / 1096322 traces, mean length 64 | 1801s |
| `canary-AbsentElect` | `Update_canary_AbsentElect.cfg` | reachability canary (violation expected) | no violation; budget-limited BFS | 14,266,472 gen / 2,560,995 distinct, depth 19, queue 1,418,980 | 361s |
| `canary-AbsentElect-witness` | `Update_canary_AbsentElect_witness.cfg` | reachability canary (violation expected) | VIOLATION: CanaryAbsentElect | 2216059 gen / 402205 distinct, depth 24 | 72s |
| `canary-CommitAfterTransfer` | `Update_canary_CommitAfterTransfer.cfg` | reachability canary (violation expected) | no violation; budget-limited BFS | 14,970,606 gen / 2,573,175 distinct, depth 19, queue 1,274,742 | 360s |
| `canary-CommitAfterTransfer-witness` | `Update_canary_CommitAfterTransfer_witness.cfg` | reachability canary (violation expected) | VIOLATION: CanaryCommitAfterTransfer | 62324 gen / 11835 distinct, depth 22 | 5s |
| `canary-LeaseDisabled` | `Update_canary_LeaseDisabled.cfg` | reachability canary (violation expected) | VIOLATION: CanaryLeaseDisabled | 366 gen / 100 distinct, depth 11 | 2s |
| `canary-NonVoterCandidate` | `Update_canary_NonVoterCandidate.cfg` | reachability canary (violation expected) | VIOLATION: CanaryNonVoterCandidate | 945 gen / 391 distinct, depth 11 | 2s |
| `canary-OldLeaderDeposed` | `Update_canary_OldLeaderDeposed.cfg` | reachability canary (violation expected) | VIOLATION: CanaryOldLeaderDeposed | 42798 gen / 11717 distinct, depth 13 | 5s |
| `canary-OmittedApply` | `Update_canary_OmittedApply.cfg` | reachability canary (violation expected) | VIOLATION: CanaryOmittedApply | 1638249 gen / 329119 distinct, depth 16 | 40s |
| `canary-OmittedStale` | `Update_canary_OmittedStale.cfg` | reachability canary (violation expected) | VIOLATION: CanaryOmittedStale | 303 gen / 87 distinct, depth 10 | 3s |
| `canary-TransferElectedLeader` | `Update_canary_TransferElectedLeader.cfg` | reachability canary (violation expected) | VIOLATION: CanaryTransferElectedLeader | 1525127 gen / 309667 distinct, depth 16 | 35s |
| `canary-TransferGrant` | `Update_canary_TransferGrant.cfg` | reachability canary (violation expected) | VIOLATION: CanaryTransferGrant | 36951 gen / 10263 distinct, depth 13 | 4s |

Startup/configuration errors (not counted as runs): `output/startup-errors/` (two hunts launched against module MC instead of Update; rerun). Superseded/interrupted standard rounds: `output/mc-standard-round2-interrupted-tool-limit.log`, `output/mc-standard-round2b-superseded-R8.log`.

## Spec fixes during checking

- Round 1 (`MC.cfg`, Case B): winning grant appended the establishment blank beyond
  `MaxIndex`; the MC wrapper bounds it.
- `Update_full_ElectedLeaderWasVoter.cfg` pre-repair (Case B, repair R8): the model let remote
  grants overtake the learner's own grant, making a learner *leader* reachable. RaftCore
  delivers the self response first on the same FIFO channel, so that path cannot occur; the
  pre-repair counterexample is kept as `spec/output/caseB-R8_ElectedLeaderWasVoter_pre-repair.out`.
  After R8, U5 holds within bounds and the learner always panics first (consistent with the
  real runs).
