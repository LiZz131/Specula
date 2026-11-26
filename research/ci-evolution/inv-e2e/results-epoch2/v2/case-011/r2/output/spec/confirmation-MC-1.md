# Confirmation — MC-1: timer-started Pre-Vote round survives leader establishment

- **Source**: MC (actual counterexamples: `spec/output/upd-hunt-stale-round.log`
  [`TickPreVoteRoundNotHeldByLeader`], `spec/output/upd-hunt-stale-round-consequence.log`
  + `spec/output/cex/MC-1-stale-round.json` [`LeaderNotPreemptedByTimerPreVote`];
  also admitted by full `MCNext`: `spec/output/upd-full.log`, focused and open runs)
- **Novelty**: NEW — in-tree search (code comments, docs, tests incl.
  `tests/tests/elect/t12_pre_vote.rs`) found no report of this mechanism; external
  trackers were not consulted (blinded run: internet/issue research prohibited).
- **Status**: REPRODUCED (Level 1: public `Raft` API + router RPC hooks + test-store
  vote-save latency; no openraft logic changed)
- **Severity**: High
- **Update attribution**: introduced by the update (`pre_candidate` and the timer
  Pre-Vote path exist only in the new revision); the old revision cannot run the
  reproduction (no `enable_pre_vote`, no `trigger().elect(bool)`), recorded as an
  incompatible old control.
- **Location**: `openraft/src/engine/engine_impl.rs:855-881` (`establish_leader`
  takes only `candidate`), `openraft/src/engine/handler/vote_handler/mod.rs:154-231`
  (`update_internal_server_state`/`become_leader` keep `pre_candidate`),
  `openraft/src/engine/engine_impl.rs:533-541` (`handle_pre_vote_resp` -> `elect()`
  with no role/vote re-check), `openraft/src/core/raft_core.rs:1959-2036`
  (tick starts a round while Candidate).

## Investigation

**Code audit.** `handle_tick_election` returns early only for a Leader, a
non-voter, or disabled elections (raft_core.rs:1966-1979). A Candidate whose
vote lease (zero lease, last update at `do_elect`) is older than its election
timeout passes the expiry check (1996-2007) and, with `enable_pre_vote` and more
than one voter, runs `pre_elect()` (2012-2035) — the rate limit only looks at an
existing `pre_candidate` (2014-2022), which `do_elect` had cleared. The new
`pre_candidate` probes `(term+1, self)` while the real `candidate` at `term` is
still collecting votes. When the real quorum arrives, `establish_leader`
(855-881) takes `self.candidate`, and its `update_vote(committed)` reaches
`update_internal_server_state -> become_leader` (vote_handler/mod.rs:154-231);
only `do_elect` (263-264) and `become_following` (242-244) clear
`pre_candidate`. The runtime gate for `Notification::PreVoteResponse`
(raft_core.rs:1803-1820) checks only `pre_candidate.is_some()` and leader-id
equality (2067-2090), both true. `handle_pre_vote_resp` then counts the grant and
calls `self.elect()` (533-541) from the established Leader: `do_elect` bumps the
vote to `(term+1, self, uncommitted)` while the `Leader` object (committed vote
at `term`) is left in place.

**Reachability.** Requires `enable_pre_vote` (opt-in config, also runtime
toggle) and a candidate whose real election completes after its election timer
fired but before the vote RPC timeout (`election_timeout_min`,
raft_core.rs:1403): the vote RPCs are spawned only after `save_vote` returns
(raft_core.rs:2274-2303, 2339-2341), so storage latency, scheduling delay, and
the randomized election timeout (`[min, max)`) open the window. The Pre-Vote
responses have their own, later RPC deadline.

**Developer knowledge.** Docs state Pre-Vote is "an optional round that a
follower runs before it increments its term" (pre_vote.md:3) whose purpose is to
avoid "an unnecessary election even though the cluster was healthy"
(pre_vote.md:14-20) and to avoid "disrupting a healthy leader" (config.rs:400-404);
the tick refuses to elect on a Leader ("skip election, already a leader",
raft_core.rs:1966-1969). `try_leader_handler` asserts
`leader.vote >= state.vote` (engine_impl.rs:977-982). The in-tree tests
(`pre_elect_test.rs`, `handle_pre_vote_resp_test.rs`, `t12_pre_vote.rs`) never
start a round while Candidate. No TODO/issue references this interaction.

## Trigger scenario (matches the counterexample)

1. Node 1 is a Candidate at term 2 (first election via its timer's Pre-Vote
   round in the runtime test; via `ExternalElect` in the bounded MC trace because
   the hunt allows one pre-vote round).
2. Its vote RPCs are slow; its election timer fires -> Pre-Vote round (term 3).
3. Node 2 grants the term-2 vote -> node 1 establishes leadership (round kept).
4. Node 2's grant of the term-3 Pre-Vote arrives -> quorum -> `elect()` from the
   Leader: vote `(3,1,uncommitted)`, role Candidate, Leader object still present.

MC trace (`upd-hunt-stale-round-consequence.log`): ExternalElect(1), PersistVote(1),
TickPreElect(1), SendVoteRequest(1,3), [deliver self grant], [deliver VoteReq at 3],
PersistVote(3), [deliver VoteResp 3->1: Leader], PersistVote(1),
[deliver PreVoteResp: election at term 2 from Leader] -> action property violated.

## Reproduction

- Test: `spec/repro/t90_specular_pre_vote_repro.rs::specular_mc1_timer_pre_vote_round_preempts_new_leader`
  (patch `spec/repro/repro.patch`; runner `spec/repro/test_bug1_mc1_stale_timer_pre_vote.sh`).
- Escalation level 1 (timing assistance only): node 1's `save_vote` delayed
  450 ms via a new test-only memstore `BlockOperation::SaveVote` (emulates a slow
  disk); router pre-hook delays node 1's real term-2 vote request to node 2 by
  100 ms; router post-hook delays node 2's answer to the term-3 Pre-Vote by
  250 ms; all below the 400 ms vote RPC timeout. Nodes 0/2 have elections
  disabled; node 0 is isolated so node 1's timer fires.
- Level 0 (pure black-box, `specular_mc1_level0_black_box_attempt`): Pre-Vote
  enabled, no hooks, no storage latency, 8 rounds of isolating the current
  leader — not triggered (`spec/repro/specular_mc1_level0_black_box_attempt.log`).
  Expected: the in-memory store persists votes in microseconds, so the window
  (`save_vote` latency > `election_timeout - election_timeout_min`, plus tick
  alignment at 1.5 x heartbeat) is essentially closed; escalated to Level 1.
- Command: `cd .specular-output/work/repro && timeout 5m cargo test -p tests --test elect
  "t90_specular_pre_vote_repro::specular_mc1_timer_pre_vote_round_preempts_new_leader" -- --exact --nocapture`
- Result: 4/4 debug runs FAIL as expected (`spec/repro/...run1..run4.log`):

```
thread 'tokio-rt-worker' (12559) panicked at openraft/src/engine/engine_impl.rs:977:9:
leader.vote(<T2-N1:Q>) >= state.vote(<T3-N1:->)
EVENTS: ["1->2 vote-rpc term=2 #0 delay=0", "1->2 vote-rpc term=2 #1 delay=100", "1->2 vote-rpc term=3 (timer pre-vote)", "2->1 pre-vote resp term=3 granted=true delayed", ...]
CORE: node1 Err("panicked")
BUG REPRODUCED (MC-1): node 1 won the term-2 election (real vote delivered: true), but a Pre-Vote round its election timer started while it was still a Candidate completed afterwards and started a new election from the established leader; RaftCore view: Err("panicked"); metrics term=2 state=Candidate
```

  Backtrace (`...backtrace.log`): `try_leader_handler` (engine_impl.rs:977) <-
  `send_heartbeat` (raft_core.rs:671) <- `handle_notification`: the stale Leader
  object (vote T2) still drives heartbeats after the state vote moved to T3.
- Release build (`cargo test --release`, debug assertions off,
  `...release.log`):

```
OUTCOME: node1 term=16 state=Candidate leader=None stale_pre_votes_sent=2
CORE: node1 Ok(("<T17-N1:->", Candidate))
BUG REPRODUCED (MC-1): ... RaftCore view: Ok(("<T17-N1:->", Candidate)); metrics term=16 state=Candidate
```

  The established leader abandoned leadership; the cluster stayed leaderless and
  the term kept inflating (each later election re-opened the same window because
  the emulated 450 ms vote-save latency exceeds the 400 ms election timeout).
- Expected (correct) behaviour: node 1 remains Leader at term 2 (no other node may
  elect). Control: with a minimal candidate repair (`spec/repro/fixctl-control.patch`:
  `establish_leader` drops `pre_candidate`) the same test passes —
  `OUTCOME: node1 term=2 state=Leader leader=Some(1) stale_pre_votes_sent=1`,
  `CORE: node1 Ok(("<T2-N1:Q>", Leader))` (`...fixctl.log`), i.e. the precondition is
  still reached but the stale round no longer acts.
- Engine-level evidence: the fresh validated trace
  `traces/stale_pre_vote_after_leader.ndjson` shows the same transition on the
  real Engine (post-state of event 4: Leader with an active round; event 5:
  Candidate at term 3 with the Leader object still present).

## Consequence

A healthy, newly established leader abandons leadership and inflates the term
without any external request or higher term — the disruption Pre-Vote exists to
prevent. Internally the engine keeps a `Leader` whose committed vote is behind
`state.vote`, violating the `try_leader_handler` assertion (RaftCore panic in
debug builds; in release builds the stale Leader keeps replicating at the old
term while the node campaigns at the new one).

## Recommendation

Drop `pre_candidate` whenever the node stops being a follower-in-waiting: in
`establish_leader`/`become_leader` (or in `update_internal_server_state` for any
vote change), and in `handle_pre_vote_resp` re-check that the node is not Leader
and that `state.vote` still has the term the round probed before calling
`elect()`; alternatively do not start a timer Pre-Vote while a real candidate is
in flight.
