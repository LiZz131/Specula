# Bug Report — OpenRaft election model, Pre-Vote update (run incr-315482ff25a1)

## Summary

- Scenarios tested: U-1..U-4 (update) plus the V0 reference Scenarios 1-5
- Bugs found: 2 (MC-1 and MC-2, both REPRODUCED — `spec/confirmation-MC-1.md`, `spec/confirmation-MC-2.md`)
- Configs run: MC.cfg, MC-membership.cfg, Update_full.cfg, Update_full_continue.cfg, Update_focused.cfg,
  Update_open.cfg, Update_discharge.cfg, Update_discharge_3voter.cfg, Update_hunt_stale_round.cfg,
  Update_hunt_stale_membership.cfg, Update_hunt_stale_membership_leader.cfg, Update_canary_*.cfg (6) — outcomes in the table below and in `spec/model-checking-summary.md`

## Bug 1: Pre-Vote round started while Candidate survives leader establishment and makes the new leader re-elect

- **Scenario**: U-2 (old context Candidate -> PreElect -> HandleVoteResponse wins -> HandlePreVoteResponseElect)
- **Severity**: Medium
- **Invariant violated**: `PreVoteElectionPremiseCurrent` (consequence form `PreVoteNeverDisplacesLeader`; early form `EstablishedLeaderHasNoInheritedPreVote`)
- **Config**: `Update_full.cfg` (also `Update_focused.cfg`)
- **Counterexample**: 12 states, `spec/output/MC-1_update_full_PreVoteElectionPremiseCurrent.out` (first find); re-found on the final suite: 11 states, `spec/output/MC-1_final_update_full_PreVoteElectionPremiseCurrent.out` (same mechanism without the crash of node 2)

### Trace Summary

1. `MCTickElect(1)`: node 1 Candidate at term 1 (SaveVote/SendVote queued).
2. `MCCrash(2)`: node 2 down, so node 1 needs node 3.
3. `MCPersistVote(1)`: self grant becomes visible.
4. `MCTickPreElect(1)`: node 1's election timer fires while it is still Candidate; Pre-Vote round `(2,1)`, PreVoteReq to 2 and 3.
5. `MCSendVoteRequest(1,3)`; 6. self grant counted.
7. node 3 handles the VoteReq: vote `(1,1)` (uncommitted, no lease), reply pending its save.
8. node 3 handles the PreVoteReq: grants (no committed lease, logs equal, `(2,1) >= (1,1)`).
9. `MCPersistVote(3)`: real-vote grant sent.
10. node 1 handles the real grant: quorum, Leader at `(1,1,committed)` — `preCandidateActive[1]` stays TRUE.
11. node 1 handles the delayed Pre-Vote grant: quorum `{1,3}` -> `elect()` -> Candidate at `(2,1)`: the established leader abandons term 1.

### Root Cause

`establish_leader` (`openraft/src/engine/engine_impl.rs:855-881`) consumes only `self.candidate`; the
`update_vote(committed)` it performs reaches `become_leader` (`vote_handler/mod.rs:171-229`), which does not
reset `pre_candidate`. Only `do_elect` (`engine_impl.rs:263-264`) and `become_following`
(`vote_handler/mod.rs:241-244`) reset it. A round can be started while a real election is in flight because
the tick skips only Leaders (`raft_core.rs:1966-1969`) and `ExternalCommand::Elect{pre_vote:true}` has no role
check (`raft_core.rs:1683-1695`). `Notification::PreVoteResponse` is accepted whenever the round exists and the
leader id matches (`raft_core.rs:1803-1820,2067-2090`), and `handle_pre_vote_resp` calls `elect()` on a quorum
without checking role or the probed vote (`engine_impl.rs:516-540`).

### Affected Code

- `openraft/src/engine/engine_impl.rs:855`: `establish_leader` does not clear `pre_candidate`.
- `openraft/src/engine/engine_impl.rs:534`: quorum of Pre-Vote grants calls `elect()` unconditionally.
- `openraft/src/engine/handler/vote_handler/mod.rs:172`: `become_leader` keeps the round.
- `openraft/src/core/raft_core.rs:1966`: the tick starts a Pre-Vote round for a Candidate.
- `openraft/src/core/raft_core.rs:1815`: the response filter accepts the stale round.
- `openraft/src/engine/engine_impl.rs:977`: `debug_assert` that the stale Leader object trips afterwards.

### Recommendation

Reset `pre_candidate` when leadership is established (`establish_leader`/`become_leader`), or make
`handle_pre_vote_resp` start the real election only while the node is still a non-leader at the vote the
round was built from.

## Bug 2: Stale Pre-Vote grant from a node outside the current round's voter set panics RaftCore

- **Scenario**: U-5 (changed Action round 1 -> old Action membership change -> changed Action round 2 -> stale grant)
- **Severity**: High
- **Invariant violated**: `PreVoteGrantFromRoundMember` (consequence: `HandlePreVoteResponseNonMember`, RaftCore panic)
- **Config**: `Update_hunt_stale_membership.cfg`
- **Counterexample**: 15 states, `spec/output/MC-2_hunt_stale_membership_PreVoteGrantFromRoundMember.out`; also `spec/output/MC-2_final_hunt_leader_PreVoteGrantFromRoundMember.out` (leader-path hunt, rounds via `Trigger::elect(true)`); `spec/output/MC-2_full_sim_PreVoteGrantFromRoundMember.out` (standard full-update bounds, simulation, 31 states)

### Trace Summary

1. Node 1 Candidate at term 1; its tick starts Pre-Vote round 1 `(2,1)` with voters {1,2,3}.
2. Node 2 grants the real vote; node 1 becomes Leader at term 1 (round 1 survives, MC-1 mechanism).
3. The Leader removes node 3: joint `{1,2,3}/{1,2}` appended, committed, uniform `{1,2}` appended.
4. `Trigger::elect(true)` on the Leader starts round 2 from the same vote: key `(2,1)`, voters {1,2}.
5. Node 3 answers the round-1 request with a grant; the response matches round 2's key and is in flight.
6. Delivering it calls `grant_by(3)` on a round whose tracker has no node 3: `expect` panics.

### Root Cause

`does_pre_candidate_vote_match` compares only leader ids (`openraft/src/core/raft_core.rs:2067-2090`);
`pre_elect` builds the round vote from the unchanged local vote (`engine_impl.rs:298-302`), so rounds share
the key; `handle_pre_vote_resp` passes every matching grant to `grant_by` (`engine_impl.rs:534-535`), which
`expect`s membership in the frozen voter set (`proposer/candidate.rs:106-107`, tracker built from voters
only at `proposer/candidate.rs:66-82`). The runtime comment requires stale responses to be ignored
(`raft_core.rs:2066`).

### Affected Code

- `openraft/src/core/raft_core.rs:2067`: correlation by leader id only.
- `openraft/src/engine/engine_impl.rs:535`: unconditional `grant_by(&target)`.
- `openraft/src/proposer/candidate.rs:107`: `expect("target not in quorum set")`.
- `openraft/src/engine/engine_impl.rs:298`: round key derived from the unchanged local vote.

### Recommendation

Identify rounds uniquely in the notification (e.g. a round id or start time) or ignore grants from nodes
outside the pre-candidate's quorum set instead of `expect`ing them.

---

## Not Reproduced

| Scenario | Config | States Explored | Result |
|---|---|---|---|
| Reference Scenarios 1-5 (standard round) | `MC.cfg` | BFS 8,457,002 distinct, depth 17 (budget); simulation 14.9M states | No violation (budget-limited) |
| Reference membership companion | `MC-membership.cfg` | BFS 2,474,412 distinct, depth 19 (budget); simulation 25.2M states | No violation (budget-limited) |
| U-1..U-4 full update, MC-1 filtered | `Update_full_continue.cfg` | BFS 5,468,696 distinct, depth 15 (budget) | No violation in BFS; simulation hit MC-2 (31 states) |
| U-1..U-4 full update, MC-1 and MC-2 filtered | `Update_full_continue2.cfg` | simulation 33.7M states, 282,949 traces | No violation (budget-limited) |
| Concrete focused, MC-1 filtered | `Update_focused_continue.cfg` | BFS 3,761,251 distinct, depth 13 (budget); simulation 25.8M states | No violation (budget-limited) |
| Open focused (rely v3), MC-1 filtered | `Update_open_continue.cfg` | BFS 4,108,477 distinct, depth 11 (budget); simulation 27.9M states | No violation (budget-limited; provisional open result) |
| Discharge of omitted context (membership seed) | `Update_discharge.cfg` | BFS 2,196,042 distinct, depth 19 (budget) | `DischargeContext` holds within the bound |
| Discharge of omitted context (three-voter seed) | `Update_discharge_3voter.cfg` | BFS 1,188,370 distinct, depth 15 (budget) | `DischargeContext` holds within the bound |
| U-1 Pre-Vote never bumps/persists the term | all update cfgs (`PreCandidateTermUnbumped`) | as above | No violation |
| U-1 structural message shape | all update cfgs (`PreVoteMessagesWellFormed`) | as above | No violation |
| Inherited V0 properties (incl. unaffected control `CertifiedLeaderHasFrozenQuorum`) | all cfgs | as above | No violation |
| Liveness / eventual election | — | — | Not testable: no fairness is grounded in the source; not claimed |

Spec fixes made during checking (Case A/B, recorded in `spec/changelog.md`): `LogLE` absent-log equality
(V0 defect; the V0 three-voter run could not elect), `HandleVoteResponse` lease effects (V0 defect),
`HandlePreVoteResponseNonMember` (faithful `grant_by` panic), and `EnvUpdate` rely v2/v3 for the open check.
