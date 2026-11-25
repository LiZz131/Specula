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
