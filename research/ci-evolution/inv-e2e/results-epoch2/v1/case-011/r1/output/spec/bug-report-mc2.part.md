## Bug 2: A stale Pre-Vote round demotes a newly established leader (MC-2)

- **Scenario**: U-S3 (pre-candidate survives leader establishment)
- **Severity**: Medium (availability / term inflation; no safety property of the reference model is violated)
- **Invariant violated**: `PreVoteQuorumNeverDemotesLeader` (action property, `Update.tla`)
- **Config**: `MC_hunt_prevote_leader_demote.cfg` (full `MCNext`, Pre-Vote tick, 3 voters, no faults)
- **Counterexample**: 14 states, `spec/output/mc-hunt-leader-demote-bfs.log` (JSON: `spec/output/mc-hunt-leader-demote-bfs.cex.json`)

### Trace Summary

1. s2: node 2's election tick (Pre-Vote on) runs `pre_elect`: pre-candidate (1,2), PreVoteReq to 1 and 3.
2. s3–s4: node 1 grants; quorum {1,2}; `elect()` → node 2 Candidate (1,2), SaveVote + SendVote.
3. s5: SaveVote completes (self grant queued).
4. s6: **node 2's election tick fires again while its real election is still open** (a Candidate is not skipped by the tick, `raft_core.rs:1966-1969,1996-2008`): `pre_elect` creates pre-candidate (2,2) and sends PreVoteReq (2,2).
5. s7–s11: vote request (1,2) reaches node 1, node 1 grants; node 2 counts self + node 1 → `establish_leader`: node 2 is **Leader (1,2,committed)**; `become_leader` leaves `pre_candidate` (2,2) in place.
6. s12–s13: node 1 (vote (1,2) uncommitted, no lease yet) answers the old PreVoteReq (2,2) with a grant.
7. s14: `RaftCore` forwards the response (pre-candidate exists and its leader id matches), `handle_pre_vote_resp` reaches quorum and calls `elect()`: the Leader becomes **Candidate (2,2)**, SaveVote/SendVote are issued, the term is bumped.

### Root Cause

`Engine::pre_candidate` is cleared only by `do_elect` (`engine_impl.rs:262-264`) and by
`become_following` (`vote_handler/mod.rs:242-244`). Leader establishment goes through
`establish_leader` → `update_vote(committed)` → `update_internal_server_state` →
`become_leader` (`engine_impl.rs:855-881`, `vote_handler/mod.rs:154-230`), which never
clears it. The tick runs `pre_elect` for any non-Leader voter, including a Candidate
whose real election is still pending (`raft_core.rs:1958-2035`). `handle_pre_vote_resp`
(`engine_impl.rs:516-554`) and the runtime filter `does_pre_candidate_vote_match`
(`raft_core.rs:2066-2090`) check only that a pre-candidate exists and the leader id
matches; neither checks that the node is still a non-leader. The quorum then calls
`elect()` on the Leader.

Real-engine evidence: trace `traces/candidate_prevote_then_establish.ndjson` (validated
by TLC; event 4 post `pre_candidate_active=true` with role Leader, event 5 post role
Candidate at term 2) and the code observation
`specula_observe_leader_demoted_by_stale_prevote` (`spec/output/observations.log`).
Requirement evidence: `docs/protocol/pre_vote.md:3-6` (Pre-Vote is run by a follower
before it increments its term), `pre_vote.md:13-24` and `config/config.rs:397-404`
(the point of Pre-Vote is to avoid needless term increases that disrupt a healthy
leader), `raft_core.rs:1966-1969` (a Leader never starts an election from the tick).

### Affected Code

- `openraft/src/engine/engine_impl.rs:855-881` — `establish_leader` keeps `pre_candidate`.
- `openraft/src/engine/handler/vote_handler/mod.rs:154-230` — `update_internal_server_state`/`become_leader` do not clear it.
- `openraft/src/engine/engine_impl.rs:516-554` — `handle_pre_vote_resp` elects without checking the node's current role.
- `openraft/src/core/raft_core.rs:1803-1820,2066-2090` — correlation by leader id only.
- `openraft/src/core/raft_core.rs:2010-2035` — tick runs `pre_elect` for a Candidate.

### Recommendation

Clear `pre_candidate` when a node becomes Leader (in `establish_leader` or
`become_leader`), and/or make `handle_pre_vote_resp` ignore responses while the
node is a Leader (or whenever its vote is committed).
