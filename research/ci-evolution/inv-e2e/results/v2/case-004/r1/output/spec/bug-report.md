# Bug Report — Openraft (incremental run, artifact commit d7176ef "update")

## Summary

- Update Scenarios tested: U1 (transfer to a voter), U2 (transfer to a non-voter), U3 (stale
  `from`, trace-validated), U4 (crash/restart around the transfer).
- Model-checking findings: **1** (MC-1, Scenario U2), with two violated properties
  (`ElectionByVoterOnly`, and its consequence `NoRaftCorePanic`).
- Configs with violations: `Update_full.cfg`, `Update_focused.cfg`, `Update_open.cfg`,
  `Update_hunt_U2_learner_transfer.cfg` (ElectionByVoterOnly); `Update_hunt_U2_panic.cfg`
  (NoRaftCorePanic).
- Code-level reproduction: yes, on a clean (uninstrumented) worktree of d7176ef; the analogous
  pre-existing guarded path does not misbehave on d86101c or d7176ef.
- Campaign coverage and the non-violating runs: see "Not Reproduced" and
  `spec/output/model-checking-summary.md`.

## Bug 1: TransferLeader makes a learner campaign; the learner's RaftCore panics

- **ID**: MC-1
- **Scenario**: U2 — transfer whose `to` node is not a voter (learner, or a voter demoted by a
  membership change before the message arrives)
- **Severity**: High (a documented public API call crashes the target node's Raft task with
  `Fatal::Panicked`, and the voters' grants depose the current leader until another election
  timeout; no committed-log divergence was found)
- **Invariant violated**: `ElectionByVoterOnly` (Update.tla); consequence `NoRaftCorePanic`
- **Config**: `Update_full.cfg` (full `MCSpec`), also focused/open/U2 hunts
- **Counterexample**: 12 states, `spec/output/mc-Update_full.log`
  (consequence: 16 states, `spec/output/mc-Update_hunt_U2_panic.log`)

### Trace Summary

Model: Server {1,2,3}, voters {1,2}, learner 3.

1. `MCElect(1)` → `MCPersistVote(1)` → `MCSendVote(1)`: node 1 campaigns at term 1.
2. `MCVoteRequest(2,1)`, `MCPersistVote(2)`, `MCVoteResponse(1,1)`, `MCVoteResponse(1,2)`:
   node 1 becomes Leader with committed vote (1,1) and appends its blank entry.
3. `MCSubmit(1)`, `MCFollowerAppend(3,1)`, `MCPersistVote(3)`: learner 3 accepts the leader's
   AppendEntries, so its vote becomes the leader's committed vote (1,1,committed).
4. State 12, `MCTransferLeader(3)`: `Raft::transfer_leader(from = (1,1,committed), to = 3)`
   reaches node 3; `vote == from` and `id == to`, so RaftCore calls `Engine::elect()`.
   Node 3 becomes Candidate for term 2 with `candidateConfigs[3] = {{1,2}}` (3 is not a voter):
   `ElectionByVoterOnly` is violated.
5. Consequence (`Update_hunt_U2_panic.cfg`, states 13-16): node 3 persists its vote and sends
   requests; its own grant (`MCVoteResponse(3,3)`) hits `Candidate::grant_by` for an id that is
   not in the voter-only candidate progress → `CandidateGrantPanic`: node 3's RaftCore panics.

The same sequence is observed on the real system (harness scenario
`specula_transfer_to_learner`): the learner becomes `Candidate` with vote `(2, 3)`
(validated trace `traces/core-transfer-to-learner/transfer-n4-003.ndjson`), all three voters —
including the old leader — grant it (traces `transfer-n1-004`, `n2-001`, `n3-002`), the leader
steps down, and node 3 then panics:
`panicked at openraft/src/proposer/candidate.rs:92:59: target not in quorum set: false`.
Its client calls return `Fatal::Panicked`; the cluster is leaderless until a voter's election
timeout elects a new leader (`spec/output/obs-transfer-to-learner.jsonl`).

### Root Cause

- `RaftMsg::TransferLeader` handling (`openraft/src/core/raft_core.rs:1190-1202`, new in the
  update) calls `self.engine.elect()` whenever `vote == from` and `self.id == to`, without the
  `is_voter` check that both pre-existing callers of `elect()` apply:
  `ExternalCommand::Elect` (`raft_core.rs:1206-1214`, "Node is switched to learner") and
  `handle_tick_election` (`raft_core.rs:1454-1457`). `Raft::transfer_leader`
  (`openraft/src/raft/mod.rs:635-703`) does not validate `to` either.
- `Engine::elect()` (`engine/engine_impl.rs:223-249`) has no guard; for a learner,
  `update_internal_server_state` keeps the candidate because `is_leading` only needs membership
  `contains()` (`raft_state/mod.rs:369-371`).
- `Candidate::new` builds a voter-only progress (`proposer/candidate.rs:58-72`), and the
  self-grant sent after `SaveVote` (`raft_core.rs:1670-1682`) reaches
  `Candidate::grant_by`, which `expect`s the target in the quorum set
  (`proposer/candidate.rs:90-96`) → panic.
- Requirement evidence: `docs/data/vote.md:50-51` ("a learner does not try to elect itself"),
  `docs/cluster_control/cluster-control.md:14`, `raft_state/mod.rs:341-342` (learner leadership
  "currently ... not supported"), `error.rs:122` (Fatal shuts Raft down).

### Affected Code

- `openraft/src/core/raft_core.rs:1190-1202`: TransferLeader arm calls `elect()` without the voter guard
- `openraft/src/raft/mod.rs:635-703`: `transfer_leader` accepts any `to`
- `openraft/src/engine/engine_impl.rs:223-249`: `elect()` has no voter check
- `openraft/src/proposer/candidate.rs:58-72,90-96`: voter-only progress; `grant_by` panics for a non-member
- `openraft/src/core/raft_core.rs:1670-1682`: self VoteResponse after SaveVote

### Reproduction

- Model: `spec/run_tlc.sh Update.tla Update_full.cfg Update_full 30` (see log header).
- Code (clean d7176ef worktree, no instrumentation): `harness/repro/run_clean_controls.sh`
  → `spec/output/clean-update-specula_repro_transfer_to_learner_no_panic.log` (FAILED:
  "learner node-3 RaftCore panicked"). Controls: `spec/output/clean-update-specula_control_trigger_elect_on_learner.log`
  and `spec/output/clean-baseline-specula_control_trigger_elect_on_learner.log` (the voter-guarded
  `trigger().elect()` on the same learner: no election, no panic, on both revisions).
- Attribution: introduced by the update (new API/handler); the old revision has no
  `transfer_leader`, and its only non-tick `elect()` caller is voter-guarded.

### Recommendation

In the `RaftMsg::TransferLeader` arm, call `elect()` only if
`self.engine.state.membership_state.effective().is_voter(&self.id)` (as `ExternalCommand::Elect`
does); optionally reject a non-voter `to` in `Raft::transfer_leader`, and make
`Candidate::grant_by` ignore ids outside the quorum set instead of panicking.

---

## Code-review observation (not a model-checking finding)

**CR-2 (pre-existing, newly reachable through the update)**: when the `to` node is the current
Leader, `elect()` leaves the Leader object alive while `state.vote` becomes the uncommitted
higher vote (`vote_handler/mod.rs:168-176`); a client write then trips
`debug_assert!(leader.committed_vote >= state.vote)` in `Engine::leader_handler`
(`engine/engine_impl.rs:765-770`) and the RaftCore panics in debug builds
(`spec/output/obs-self-transfer-write.log`). The same panic occurs on the baseline through
`trigger().elect()` on the Leader (`spec/output/obs-elect-on-leader-d86101c.log`,
`...-d7176ef.log`), so it is not introduced by the update. The model keeps the V0 guard
`voteCommitted[n]` on `LeaderAppend` and does not represent this debug-only path (limitation).

---

## Not Reproduced

All runs: 30-minute budget (`tlc2.TLC.stopAfter`), states under `/dev/shm/specula-e2e-case-004/`
(removed after each run). "Budget-stopped" = queue not exhausted: **LIMITED_COVERAGE**, not proof.

| Scenario | Config | Mode | States explored | Result |
|---|---|---|---|---|
| reference (V0 invariants) | `MC.cfg` (final model) | BFS | 15,499,553 distinct, depth 35 | no violation, budget-stopped |
| reference (V0 invariants) | `MC.cfg` (before SaveCommit repair; 2 voters, unaffected) | BFS | 16,003,293 distinct, depth 35 | no violation, budget-stopped |
| U1/U2/U4 kept core safety, full MCNext | `Update_full_controls.cfg` | BFS | 16,553,616 distinct, depth 36 | no violation, budget-stopped |
| same | `Update_full_controls.cfg` (final model) | simulation, depth ≤ 100 | 736,183 traces / 77.2M states | no violation |
| U1/U2 open focused (EnvUpdate) | `Update_open_controls.cfg` (final model) | BFS | 16,682,744 distinct, depth 30 | no violation, budget-stopped |
| U1+U4 transfer between voters (3 voters, 2 transfers, crash) | `Update_hunt_U1_voter_transfer.cfg` (final model) | BFS | 13,511,154 distinct, depth 27 | no violation (incl. ElectionByVoterOnly, NoRaftCorePanic), budget-stopped |
| same | same | simulation, depth ≤ 100 | 1,051,339 traces / 112.0M states | no violation |
| U2 consequences once a learner campaigns | `Update_hunt_U2_learner_consequence.cfg` | BFS | 9,927,225 distinct, depth 37 | no violation of core safety, budget-stopped |
| discharge of omitted actions | `Update_discharge.cfg` (`DischargeContext`) | BFS | 11,249,313 distinct, depth 28 | holds on explored states, budget-stopped |
| U2 learner leadership (canary) | `Update_canary_CanaryLearnerLeader.cfg` | BFS, 15 min | 7,196,944 distinct, depth 29 | not reachable within budget (code: self-grant panics first) |

Per-run details: `spec/output/model-checking-summary.md`; reachability witnesses:
`spec/output/reachability-evidence.md`.

## Spec fixes during this run (Case B / repairs)

See `spec/changelog.md`: Elect/StartElection split, full-LogId vote freshness, message-faithful
MC framing, `CandidateGrantPanic` (from code observation), self-grant-first ordering (canary
review), `SaveCommit` serialized-IO guard (3-voter hunt).
