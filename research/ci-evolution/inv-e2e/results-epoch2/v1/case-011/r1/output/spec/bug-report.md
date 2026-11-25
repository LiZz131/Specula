# Bug Report — OpenRaft election with Pre-Vote (case-011, artifact 3ab6cdd)

## Summary

- Disposition: MODEL_CHANGE_REQUIRED (Pre-Vote phase added); reference suite updated, `Update.tla` generated.
- Scenarios tested: V0 Scenarios 1–5 (standard rounds) and update Scenarios U-S1…U-S6.
- Bugs found (Case C, model checking): **2** — MC-1 (Pre-Vote livelock, High), MC-2 (stale Pre-Vote round demotes a new leader, Medium).
- No reference safety invariant (persistence ordering, role/vote consistency, frozen joint quorum, membership staging) was violated in any campaign.
- Both findings are update-introduced: they need Pre-Vote (`enable_pre_vote` or `trigger().elect(true)`), which does not exist in the baseline. Their mechanisms were observed on the real `Engine` (validated traces and `spec/output/observations.log`); the full multi-node schedules were not replayed on the real runtime (Part 4 reproduction not executed in this run).
- All model checking is bounded (`LIMITED_COVERAGE`): 3 nodes, small term/log/message bounds, 30-minute budgets; not a proof.

## Campaigns

| Run | Scenario | Config | Mode | Outcome | Violation | Distinct states / sim states | Depth | Queue left | Log |
|---|---|---|---|---|---|---|---|---|---|
| MC-membership | V0 standard (single voter seed) | `MC-membership.cfg` | BFS | LIMITED_COVERAGE(queue=5452163) (tlc rc=0) | - | 13485457 | 23 | 5452163 | `spec/output/mc-MC-membership.log` |
| MC | V0 standard | `MC.cfg` | BFS | LIMITED_COVERAGE(queue=8388541) (tlc rc=0) | - | 15748310 | 17 | 8388541 | `spec/output/mc-MC.log` |
| Update_discharge | discharge (EnvUpdate) | `Update_discharge.cfg` | BFS | LIMITED_COVERAGE(queue=4190952) (tlc rc=0) | - | 7727867 | 15 | 4190952 | `spec/output/mc-Update_discharge.log` |
| Update_focused-sim | concrete focused | `Update_focused.cfg` | simulation | VIOLATION (tlc rc=13) | PreVoteQuorumNeverDemotesLeader | 396619 | - | - | `spec/output/mc-Update_focused-sim.log` |
| Update_focused | concrete focused | `Update_focused.cfg` | BFS | LIMITED_COVERAGE(queue=9207761) (tlc rc=0) | - | 15894086 | 15 | 9207761 | `spec/output/mc-Update_focused.log` |
| Update_focused_cont | concrete focused (MC-1, MC-2 disabled) | `Update_focused_cont.cfg` | BFS | LIMITED_COVERAGE(queue=6833262) (tlc rc=0) | - | 11635196 | 13 | 6833262 | `spec/output/mc-Update_focused_cont.log` |
| Update_full | full update (all) | `Update_full.cfg` | BFS | VIOLATION (tlc rc=13) | PreVoteQuorumNeverDemotesLeader | 10437408 | 15 | 6126155 | `spec/output/mc-Update_full.log` |
| Update_full_cont1 | full update (MC-2 disabled) | `Update_full_cont1.cfg` | BFS | LIMITED_COVERAGE(queue=10708645) (tlc rc=0) | - | 18617678 | 15 | 10708645 | `spec/output/mc-Update_full_cont1.log` |
| Update_full_cont2-sim | full update (MC-1, MC-2 disabled) | `Update_full_cont2.cfg` | simulation | SIMULATION_BUDGET_EXHAUSTED_NO_VIOLATION (rc=0) | - | 64640767 | - | - | `spec/output/mc-Update_full_cont2-sim.log` |
| Update_full_cont2 | full update (MC-1, MC-2 disabled) | `Update_full_cont2.cfg` | BFS | LIMITED_COVERAGE(queue=11532575) (tlc rc=0) | - | 20065101 | 16 | 11532575 | `spec/output/mc-Update_full_cont2.log` |
| Update_open-evalerror | open focused (aborted: TLC evaluation error) | `Update_open.cfg` | BFS | TLC EVALUATION ERROR in EnvUpdate (effectiveConfig'[i] read before assignment), not a property violation; fixed in Update.tla and rerun as mc-Update_open.log | - | 494459 | 12 | 286449 | `spec/output/mc-Update_open-evalerror.log` |
| Update_open | open focused (EnvUpdate) | `Update_open.cfg` | BFS | VIOLATION (tlc rc=13) | PreVoteQuorumNeverDemotesLeader | 4743269 | 16 | 2530001 | `spec/output/mc-Update_open.log` |
| Update_open_cont | open focused (MC-1, MC-2 disabled) | `Update_open_cont.cfg` | BFS | LIMITED_COVERAGE(queue=7629658) (tlc rc=0) | - | 14612340 | 17 | 7629658 | `spec/output/mc-Update_open_cont.log` |
| hunt-leader-demote-bfs | U-S3 | `MC_hunt_prevote_leader_demote.cfg` | BFS | VIOLATION (tlc rc=13) | PreVoteQuorumNeverDemotesLeader | 98258 | 17 | 39677 | `spec/output/mc-hunt-leader-demote-bfs.log` |
| hunt-leader-demote-cont-sim | U-S3 (MC-2 disabled) | `MC_hunt_prevote_leader_demote_cont.cfg` | simulation | SIMULATION_BUDGET_EXHAUSTED_NO_VIOLATION (rc=0) | - | 47549009 | - | - | `spec/output/mc-hunt-leader-demote-cont-sim.log` |
| hunt-leader-demote-cont | U-S3 (MC-2 disabled) | `MC_hunt_prevote_leader_demote_cont.cfg` | BFS | LIMITED_COVERAGE(queue=5938669) (tlc rc=0) | - | 15182176 | 25 | 5938669 | `spec/output/mc-hunt-leader-demote-cont.log` |
| hunt-livelock-bfs | U-S2 | `MC_hunt_prevote_livelock.cfg` | BFS | LIMITED_COVERAGE(queue=5559486) (tlc rc=0) | - | 13578324 | 21 | 5559486 | `spec/output/mc-hunt-livelock-bfs.log` |
| hunt-livelock-cont-sim | U-S2 (MC-1 disabled) | `MC_hunt_prevote_livelock_cont.cfg` | simulation | SIMULATION_BUDGET_EXHAUSTED_NO_VIOLATION (rc=0) | - | 36665228 | - | - | `spec/output/mc-hunt-livelock-cont-sim.log` |
| hunt-livelock-directed-bfs | U-S2 (monitor, superseded) | `MC_hunt_prevote_livelock_directed_bfs.cfg` | BFS | LIMITED_COVERAGE(queue=838) (tlc rc=143) — stopped by operator; superseded by MC_hunt_prevote_livelock_phased.cfg (tighter monitor). Budget-limited, no violation. | - | 1219018 | 18 | 491838 | `spec/output/mc-hunt-livelock-directed-bfs.log` |
| hunt-livelock-directed-sim | U-S2 (reduced domains, superseded) | `MC_hunt_prevote_livelock_directed.cfg` | simulation | INCOMPLETE(rc=143) (tlc rc=143) — stopped by operator; superseded by MC_hunt_prevote_livelock_phased.cfg (tighter monitor). Budget-limited, no violation. | - | 6044708 | - | - | `spec/output/mc-hunt-livelock-directed-sim.log` |
| hunt-livelock-phased-bfs | U-S2 (phased monitor) | `MC_hunt_prevote_livelock_phased.cfg` | BFS | VIOLATION (tlc rc=12) | NoPermanentPreVoteLivelock | 4086089 | 26 | 1505969 | `spec/output/mc-hunt-livelock-phased-bfs.log` |

Reachability canaries (each expected VIOLATED = reachable): CanaryNoFollowerLog (reached, 14 states), CanaryNoGrantedPreVoteResp (reached, 4 states), CanaryNoLeader (reached, 11 states), CanaryNoLeaderWithPreCandidate (reached, 11 states), CanaryNoPreCandidate (reached, 2 states), CanaryNoPreCandidateCleared (reached, 14 states), CanaryNoPreVoteTally (not reached, - states), CanaryNoRejectedPreVoteResp (reached, 7 states). `CanaryNoPreVoteTally` was retired (unreachable by construction with three uniform voters).

## Bug 1: Pre-Vote can leave a live majority permanently leaderless (MC-1)

- **Scenario**: U-S2 (higher votes are invisible to Pre-Vote)
- **Severity**: High (liveness/availability: with `enable_pre_vote` on, a connected live voter majority never elects a leader without operator action or recovery of the down node; no reference safety invariant is violated)
- **Invariant violated**: `NoPermanentPreVoteLivelock` (liveness witness encoded as a safety predicate, `Update.tla`), with closure obligation `LivelockClosed`
- **Config**: `MC_hunt_prevote_livelock_phased.cfg` (`MCSpec`/full `MCNext`, Pre-Vote tick, one crash, no restart, no operator trigger, pruning-only search monitor `LivelockDirectorPhased`)
- **Counterexample**: 25 states, `spec/output/mc-hunt-livelock-phased-bfs.log` (JSON: `spec/output/mc-hunt-livelock-phased-bfs.cex.json`); permanence check `spec/witness/livelock/closure_on.log`; old-behaviour control `spec/witness/livelock/control_off.log`

### Trace Summary

Three voters {1,2,3}, Pre-Vote enabled.

1. s2–s10: node 1 runs Pre-Vote (1,1), gets a quorum, elects at term 1; node 3 grants
   the real vote (node 3's vote becomes (1,1)); node 1 becomes **Leader (1,1,committed)**
   and appends its blank entry (1,1,1). Node 2 has not voted (vote (0,2)).
2. s11: node 3's election tick (Pre-Vote) sends PreVoteReq (2,3) with an empty last log.
3. s12–s14: node 1's committed vote is persisted and it sends AppendEntries (blank entry) to
   node 2 only; **node 2 answers node 3's Pre-Vote with a grant** (no lease, logs equal so far).
4. s15: node 3 reaches a Pre-Vote quorum {2,3} and runs `elect()`: **Candidate (2,3)**.
5. s16: **node 1 crashes** (stays down).
6. s17–s23: node 3 persists (2,3) and sends its vote requests; node 2 now receives node 1's
   AppendEntries: vote (1,1,committed), lease, **last log (1,1,1)** (longer than node 3's).
7. s24–s25: node 2 rejects node 3's vote request (lease / last log); node 3 does not adopt
   node 2's lower vote.

Final state: live {2,3} is a majority. Node 2: vote (1,1,committed), log (1,1,1).
Node 3: vote (2,3), empty log. Node 2's next Pre-Vote (2,2) is rejected by node 3
because (2,2) < (2,3) (`engine_impl.rs:441-446`); node 3's next Pre-Vote (3,3) is
rejected by node 2 because node 3's log is behind (`engine_impl.rs:433-440`). Neither
side updates its vote on these exchanges (`engine_impl.rs:414-447`, `542-553`). From
this state TLC explored every behaviour with Pre-Vote ticks (no crash/restart/operator
action): no live leader, live votes never change, the livelock predicate holds in all
1,456 reachable states. The same state with the pre-update tick (direct `elect()`)
elects node 2 at term 3 after it adopts (2,3) from the rejected real vote response.

### Root Cause

With Pre-Vote, a node only bumps its term after a Pre-Vote quorum. Pre-Vote never
transfers vote information: `handle_pre_vote_req` never updates the responder's vote,
and `handle_pre_vote_resp` explicitly ignores the responder's (higher) vote
("A Pre-Vote response never updates the local vote", `engine_impl.rs:553`), unlike
`handle_vote_resp`, which adopts a higher non-committed vote (`engine_impl.rs:485-509`).
In addition the responder rejects any Pre-Vote below its own vote
(`granted = req.vote >= local vote`, `engine_impl.rs:441-446`), although the documented
rule is lease, then last log, "otherwise it would grant" (`docs/protocol/pre_vote.md:33-39`).
So the voter with the most up-to-date log but the lower term can never be granted, and
the voters with higher terms but shorter logs are always refused by it. Since no leader
exists, no other message can change either vote: the cluster stays leaderless until
the crashed node returns or an operator calls `trigger().elect(false)`.

Real-engine evidence: trace `prevote_reject_higher_vote` (requester keeps its vote after
a rejection carrying (2,3) and re-probes the same term), trace `prevote_request_branches`
(responder rejects by vote order and by log without mutation), and the code
observations in `spec/output/observations.log`: `specula_observe_prevote_livelock`
(20 Pre-Vote rounds between the two live engines in the witness state: 0 real
elections, votes unchanged) and `specula_observe_old_path_recovers` (same engines,
old real-vote path: leader at term 3 after 2 attempts).
Requirement evidence: `tests/tests/elect/t12_pre_vote.rs:188-197` ("Pre-Vote makes
elections *cautious*, not *impossible*: this is the core liveness requirement");
`docs/protocol/pre_vote.md:47-49` ("If not, nothing changed, and it retries on a later
tick"); `docs/protocol/pre_vote.md:33-39` (responder rule without a vote comparison).

### Affected Code

- `openraft/src/engine/engine_impl.rs:516-554` — `handle_pre_vote_resp` ignores a rejecting responder's higher vote.
- `openraft/src/engine/engine_impl.rs:441-446` — `handle_pre_vote_req` rejects a Pre-Vote below the local vote (not in the documented rule).
- `openraft/src/core/raft_core.rs:2010-2035` — with Pre-Vote enabled the tick never calls `elect()` directly, so the old catch-up path through `handle_vote_resp` is never used.

### Recommendation

Let Pre-Vote propagate vote information, e.g. adopt the responder's higher vote
(non-committed, as `handle_vote_resp` does) when a Pre-Vote is rejected because of
it, or follow the documented responder rule (grant when the lease has expired and the
candidate's log is not behind, regardless of the local vote, which the real election
then resolves). Add an integration test where the most up-to-date live voter has the
lowest term.

---

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

---

## Not Reproduced

| Scenario | Config | States Explored | Result |
|---|---|---|---|
| V0 standard (single voter seed) | `MC-membership.cfg` (BFS) | 13485457 | No violation (LIMITED_COVERAGE(queue=5452163) (tlc rc=0)) |
| V0 standard | `MC.cfg` (BFS) | 15748310 | No violation (LIMITED_COVERAGE(queue=8388541) (tlc rc=0)) |
| discharge (EnvUpdate) | `Update_discharge.cfg` (BFS) | 7727867 | No violation (LIMITED_COVERAGE(queue=4190952) (tlc rc=0)) |
| concrete focused | `Update_focused.cfg` (BFS) | 15894086 | No violation (LIMITED_COVERAGE(queue=9207761) (tlc rc=0)) |
| concrete focused (MC-1, MC-2 disabled) | `Update_focused_cont.cfg` (BFS) | 11635196 | No violation (LIMITED_COVERAGE(queue=6833262) (tlc rc=0)) |
| full update (MC-2 disabled) | `Update_full_cont1.cfg` (BFS) | 18617678 | No violation (LIMITED_COVERAGE(queue=10708645) (tlc rc=0)) |
| full update (MC-1, MC-2 disabled) | `Update_full_cont2.cfg` (simulation) | 64640767 | No violation (SIMULATION_BUDGET_EXHAUSTED_NO_VIOLATION (rc=0)) |
| full update (MC-1, MC-2 disabled) | `Update_full_cont2.cfg` (BFS) | 20065101 | No violation (LIMITED_COVERAGE(queue=11532575) (tlc rc=0)) |
| open focused (MC-1, MC-2 disabled) | `Update_open_cont.cfg` (BFS) | 14612340 | No violation (LIMITED_COVERAGE(queue=7629658) (tlc rc=0)) |
| U-S3 (MC-2 disabled) | `MC_hunt_prevote_leader_demote_cont.cfg` (simulation) | 47549009 | No violation (SIMULATION_BUDGET_EXHAUSTED_NO_VIOLATION (rc=0)) |
| U-S3 (MC-2 disabled) | `MC_hunt_prevote_leader_demote_cont.cfg` (BFS) | 15182176 | No violation (LIMITED_COVERAGE(queue=5938669) (tlc rc=0)) |
| U-S2 | `MC_hunt_prevote_livelock.cfg` (BFS) | 13578324 | No violation (LIMITED_COVERAGE(queue=5559486) (tlc rc=0)) |
| U-S2 (MC-1 disabled) | `MC_hunt_prevote_livelock_cont.cfg` (simulation) | 36665228 | No violation (SIMULATION_BUDGET_EXHAUSTED_NO_VIOLATION (rc=0)) |
| U-S2 (monitor, superseded) | `MC_hunt_prevote_livelock_directed_bfs.cfg` (BFS) | 1219018 | Stopped early by operator (superseded); no violation before stop |
| U-S2 (reduced domains, superseded) | `MC_hunt_prevote_livelock_directed.cfg` (simulation) | 6044708 | Stopped early by operator (superseded); no violation before stop |

---

## Spec fixes made during validation / checking

- R-1 follower log adoption on AppendEntries; R-2 log append not durable before a queued SaveVote; R-3 tick only after the lease expired (generation, update-relevant repairs of V0 abstractions).
- R-4 leader lease installed at establishment (found by trace `candidate_prevote_then_establish`).
- R-5 `Option<LogId>::None == None` in `LogLE` (found by reachability canaries; V0's 3-voter `MC.cfg` never reached a leader — its election coverage was vacuous).
- `EnvUpdate` rewritten (TLC evaluation error, no semantic change).
See `spec/changelog.md`.

## Coverage limits

- Bounds: 3 nodes; MaxTerm 2–3 (5 in the witness closure); MaxLogIndex 2–4; ≤6 in-flight messages; ≤3 election ticks, ≤1 operator trigger, ≤2 membership appends, ≤1 crash/restart/drop per run.
- BFS never exhausted the full-model state spaces within 30 minutes; simulation follow-ups are random and non-exhaustive.
- The U-S2 witness was found under a pruning-only search monitor (`LivelockDirectorPhased`); the unconstrained BFS reached depth 21 and did not reach the ~25-step schedule. Absence results under monitors are not claimed.
- Not modeled (inherited or excluded): leader stepping down on `HigherVote` from replication, membership payload propagation to followers, snapshots, timing (election/lease durations, Pre-Vote rate limit), the default `RaftNetworkV2::pre_vote` synthesised grant, transport framing.
- Engine-level harness: runtime wrappers (`handle_tick_election`, `ExternalCommand::Elect`, `does_pre_candidate_vote_match`) are model-checked but not traced.
