# Bug Report — OpenRaft election (V1 incremental run, Pre-Vote update)

## Summary

- Source: artifact `update` 3ab6cddc34a5bf127747434bb41e20a1b9ef7769
- Update scenarios: 4 (U-S1..U-S4) + standard reference properties
- Bugs found (model checking): 1 (MC-1)
- Configs run: see "Campaign outcomes" below (`spec/output/v1-mc-*.log`)

## Bug 1: Stale Pre-Vote round survives leader establishment and makes the new Leader start a real election

- **Scenario**: U-S4 (Pre-Vote round × leader establishment)
- **Severity**: Medium (availability/liveness and engine-state consistency; no election-safety violation found)
- **Invariant violated**: `PreVoteNeverDemotesLeader` (action property, `spec/Update.tla`); precursor `NoStalePreCandidateAtLeader` (state invariant)
- **Config**: `spec/Update-hunt-stale-precandidate.cfg` (also `Update-full.cfg` for the precursor over the complete `MCNext`)
- **Counterexample**: 16 states, `spec/output/v1-mc-hunt-stale-precandidate-bfs.log` (decoded: `spec/output/MC-1-counterexample-decoded.txt`); consequence over the complete MCNext: `spec/output/v1-mc-update-full-U4.log` (decoded: `spec/output/MC-1-full-counterexample-decoded.txt`); precursor over the complete MCNext: `spec/output/v1-mc-update-full.log`
- **Implementation trace (real Engine, validated by TLC)**: `traces/candidate_pre_vote_then_leader.ndjson` (+ `.observation.json`), `spec/output/v1-trace-candidate_pre_vote_then_leader.log`

### Trace Summary

Pre-Vote permanently enabled (`Config::enable_pre_vote = Some(true)`), 3 voters {1,2,3},
no direct/administrative election, no crash, no message loss (only delay/reordering):

1. (s2) Node 1's election timer fires: `TickPreElect(1)` creates pre-candidate (1,1).
2. (s3-s5) The pre-vote request reaches node 2, which grants; quorum {1,2} →
   `elect()`: node 1 becomes Candidate with vote (1,1,uncommitted); the
   pre-candidate is cleared.
3. (s6) SaveVote completes; the local granted response is queued.
4. (s7) Node 1's election timer fires again while it is still **Candidate** (the
   tick skips only Leaders): `TickPreElect(1)` creates pre-candidate (2,1); the live
   term-1 candidacy is kept (`pre_elect` does not touch `candidate`).
5. (s8-s9) RaftCore dispatches the term-1 vote request and the term-2 pre-vote
   request to node 2.
6. (s10) Node 1 counts its own term-1 grant (grants {1}).
7. (s11-s12) Node 2 grants the term-1 vote, persists (1,1) and replies; the reply
   is delayed.
8. (s13) Node 2 handles the term-2 pre-vote: it has an uncommitted vote and no
   lease, so it grants (2,1) >= (1,1).
9. (s14) Node 2's delayed term-1 grant arrives: quorum → `establish_leader`:
   **Leader** with committed vote (1,1), lease valid, while pre-candidate (2,1)
   (started as Candidate) is still active.
10. (s15) The committed vote is persisted.
11. (s16) Node 2's granted pre-vote response arrives: the runtime correlation
   passes (pre-candidate leader id (2,1) matches), quorum {1,2} → `elect()` on the
   established Leader: vote (2,1,uncommitted), server state Candidate, new
   candidate, SaveVote/SendVote pending, while `leaderActive` (the term-1
   `Engine.leader`) stays set.

Over the complete `MCNext` (`Update-full-U4.cfg`, 13 states) TLC found the same
mechanism starting from a direct tick election (runtime flag off for that tick,
on for the next).

The same sequence was executed on the real `Engine` by
`specula_trace_candidate_pre_vote_then_leader` (events: `elect`, local grant,
`pre_elect`, delayed grant → `establish_leader`, pre-vote grant →
`elect`). The post-state of event 4 shows `role=Leader` with
`pre_candidate_active=true`; event 5 shows `role=Candidate`, vote (3,1,false),
`leader_active=true`. Afterwards `try_leader_handler()` (used by every
heartbeat tick and client write) panicked on its debug assertion
`leader.committed_vote >= state.vote` (observation file:
`leader_committed_vote` (2,1,true), `local_vote` (3,1,false), `panicked: true`).

### Root Cause

The update adds `Engine.pre_candidate` and clears it only in `do_elect`
(`openraft/src/engine/engine_impl.rs:263-264`) and `become_following`
(`openraft/src/engine/handler/vote_handler/mod.rs:244`). It is not cleared
when the node becomes Leader (`establish_leader`,
`engine_impl.rs:855-881`; `become_leader`, `vote_handler/mod.rs:166-231`),
and `pre_elect` (`engine_impl.rs:298-322`) does not end a live real
candidacy. Because `handle_tick_election` (`core/raft_core.rs:1959-2035`)
runs Pre-Vote for any non-Leader voter, a Candidate whose timer fires holds
both a term-T candidacy and a term-(T+1) pre-vote round. If the candidacy wins,
the round survives; when its quorum arrives, `handle_pre_vote_resp`
(`engine_impl.rs:516-554`, forwarded by `raft_core.rs:1803-1820`) calls
`elect()` unconditionally. `update_internal_server_state` then sees
`is_leading` and keeps the old `Engine.leader`, so a term-T leader object
coexists with a term-(T+1) uncommitted local vote, contrary to the
`try_leader_handler` contract (`engine_impl.rs:977-982`) and to the Pre-Vote
contract that the round precedes a real election and does not disrupt a
healthy leader (`docs/protocol/pre_vote.md:3-5,14-20`, `raft/trigger.rs:47-56`).

Premises: Pre-Vote enabled (config or runtime handle) or a cautious manual
`trigger().elect(true)` on a Candidate; for the timer path, the delayed term-T
vote response must arrive after the election timer fired but within the vote
RPC timeout (`election_timeout_min`), i.e. vote persistence/dispatch latency
exceeding `election_timeout − election_timeout_min`. The manual trigger path
has no timing constraint beyond the response arriving after the trigger.

### Affected Code

- `openraft/src/engine/engine_impl.rs:855-881`: `establish_leader` keeps `pre_candidate`.
- `openraft/src/engine/handler/vote_handler/mod.rs:166-231`: `become_leader` keeps `pre_candidate`.
- `openraft/src/engine/engine_impl.rs:516-554`: `handle_pre_vote_resp` calls `elect()` without checking leadership.
- `openraft/src/engine/engine_impl.rs:298-322`: `pre_elect` starts a round beside a live candidacy.
- `openraft/src/core/raft_core.rs:1959-2035`: tick runs Pre-Vote on a Candidate.
- `openraft/src/engine/engine_impl.rs:968-982`: assertion violated afterwards.

### Recommendation

Discard the pre-vote round when the node stops being a pre-candidate for any
reason, in particular when leadership is established (`establish_leader` /
`become_leader`), and/or make `handle_pre_vote_resp` ignore a quorum when the
local vote is no longer the base of the probe (vote committed, or
`vote.term + 1 != pre_candidate.vote.term`) or the node is Leader.

---

## Campaign outcomes

Order executed (incremental workflow): standard `MC.cfg` round + membership
companion → full update check (`Update-full*.cfg`) → concrete focused
(`Update-focus*.cfg`) → open + discharge (`Update-open*.cfg`,
`Update-discharge*.cfg`) → Scenario hunts (`Update-hunt-*.cfg`) and
reachability canaries → simulation follow-ups (every BFS diameter ≤ 25).
Runs stopped by the 30-minute outer bound are budget-limited exploration
(LIMITED_COVERAGE), not proofs. `*.invalidated-pre-LogLE-repair.log` runs used
the model before the absent-log ordering repair and are not credited.

| Log | Config | Mode | Outcome | Depth/level | States generated | Distinct (or traces) | Queue left |
|---|---|---|---|---|---|---|---|
| v1-mc-canary-CanaryNoCandidateWithPreCandidate.log | Canary-CanaryNoCandidateWithPreCandidate.cfg | BFS | VIOLATED CanaryNoCandidateWithPreCandidate | 5 | 330 | 146 | 123 |
| v1-mc-canary-CanaryNoGrantedPreVoteResp.log | Canary-CanaryNoGrantedPreVoteResp.cfg | BFS | VIOLATED CanaryNoGrantedPreVoteResp | 5 | 1092 | 422 | 346 |
| v1-mc-canary-CanaryNoLeaderWithPreCandidate.log | Canary-CanaryNoLeaderWithPreCandidate.cfg | BFS | VIOLATED CanaryNoLeaderWithPreCandidate | 9 | 621014 | 124652 | 85399 |
| v1-mc-canary-CanaryNoPreCandidate.log | Canary-CanaryNoPreCandidate.cfg | BFS | VIOLATED CanaryNoPreCandidate | 3 | 12 | 8 | 4 |
| v1-mc-canary-CanaryNoPreGrantCounted.log | Canary-CanaryNoPreGrantCounted.cfg | BFS | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | 12 | 8,362,546 | 1,497,400 | 929,673 |
| v1-mc-canary-CanaryNoPreVoteCleared.log | Canary-CanaryNoPreVoteCleared.cfg | BFS | VIOLATED CanaryNoPreVoteCleared | 6 | 7134 | 2122 | 1668 |
| v1-mc-canary-CanaryNoPreVoteElection.log | Canary-CanaryNoPreVoteElection.cfg | BFS | VIOLATED CanaryNoPreVoteElection | 6 | 6103 | 1761 | 1374 |
| v1-mc-canary-CanaryNoRejectedPreVoteResp.log | Canary-CanaryNoRejectedPreVoteResp.cfg | BFS | VIOLATED CanaryNoRejectedPreVoteResp | 7 | 18819 | 5033 | 3813 |
| v1-mc-canary-stale-CanaryNoCandidateWithPreCandidate.invalidated-pre-LogLE-repair.log | Canary-stale-CanaryNoCandidateWithPreCandidate.cfg | BFS | no violation; state space exhausted | 20 | 245827 | 36998 | 0 |
| v1-mc-canary-stale-CanaryNoLeaderWithPreCandidate.invalidated-pre-LogLE-repair.log | Canary-stale-CanaryNoLeaderWithPreCandidate.cfg | BFS | no violation; state space exhausted | 20 | 245827 | 36998 | 0 |
| v1-mc-canary-stale-CanaryNoPreVoteElection.invalidated-pre-LogLE-repair.log | Canary-stale-CanaryNoPreVoteElection.cfg | BFS | no violation; state space exhausted | 20 | 245827 | 36998 | 0 |
| v1-mc-hunt-next-term-bfs.log | Update-hunt-next-term.cfg | BFS | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | 16 | 89,765,937 | 14,681,835 | 8,047,891 |
| v1-mc-hunt-next-term-sim.log | Update-hunt-next-term.cfg | simulation | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | ? | 54547915 | 82706 traces | - |
| v1-mc-hunt-stale-precandidate-bfs.invalidated-pre-LogLE-repair.log | Update-hunt-stale-precandidate.cfg | BFS | no violation; state space exhausted | 20 | 245827 | 36998 | 0 |
| v1-mc-hunt-stale-precandidate-bfs.log | Update-hunt-stale-precandidate.cfg | BFS | VIOLATED PreVoteNeverDemotesLeader | 17 | 733252 | 130627 | 41108 |
| v1-mc-standard-MC-membership-sim.log | MC-membership.cfg | simulation | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | ? | 28289354 | 67593 traces | - |
| v1-mc-standard-MC-membership.log | MC-membership.cfg | BFS | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | 23 | 51,586,862 | 7,409,768 | 2,183,815 |
| v1-mc-standard-MC-sim.log | MC.cfg | simulation | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | ? | 63077927 | 120551 traces | - |
| v1-mc-standard-MC.invalidated-pre-LogLE-repair.log | MC.cfg | BFS | exit 143 | 14 | 11,539,991 | 2,024,311 | 1,233,132 |
| v1-mc-standard-MC.log | MC.cfg | BFS | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | 18 | 86,445,598 | 14,509,828 | 8,102,817 |
| v1-mc-update-discharge-membership.log | Update-discharge-membership.cfg | BFS | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | 22 | 35,828,085 | 5,306,658 | 1,692,091 |
| v1-mc-update-discharge.log | Update-discharge.cfg | BFS | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | 14 | 27,557,744 | 4,719,931 | 2,777,377 |
| v1-mc-update-focus-noU4-sim.log | Update-focus-noU4.cfg | simulation | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | ? | 37202308 | 259484 traces | - |
| v1-mc-update-focus-noU4.log | Update-focus-noU4.cfg | BFS | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | 16 | 89,911,165 | 14,764,031 | 8,151,223 |
| v1-mc-update-focus.log | Update-focus.cfg | BFS | VIOLATED NoStalePreCandidateAtLeader | 11 | 557775 | 117667 | 79609 |
| v1-mc-update-full-U4.log | Update-full-U4.cfg | BFS | VIOLATED PreVoteNeverDemotesLeader | 14 | 42616910 | 7142666 | 4133068 |
| v1-mc-update-full-noU4-sim.log | Update-full-noU4.cfg | simulation | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | ? | 36908544 | 70581 traces | - |
| v1-mc-update-full-noU4.log | Update-full-noU4.cfg | BFS | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | 16 | 87,438,132 | 14,537,701 | 8,118,243 |
| v1-mc-update-full.log | Update-full.cfg | BFS | VIOLATED NoStalePreCandidateAtLeader | 12 | 636096 | 128774 | 86525 |
| v1-mc-update-open-noU4-sim.log | Update-open-noU4.cfg | simulation | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | ? | 50365249 | 363307 traces | - |
| v1-mc-update-open-noU4.log | Update-open-noU4.cfg | BFS | no violation; BUDGET-LIMITED (LIMITED_COVERAGE) | 13 | 109,553,145 | 24,358,892 | 18,668,447 |
| v1-mc-update-open.log | Update-open.cfg | BFS | VIOLATED NoStalePreCandidateAtLeader | 10 | 53949946 | 12423337 | 9758679 |

Reachability / non-vacuity: canaries show pre-candidates (depth 2), granted
and rejected pre-vote responses, pre-vote-triggered elections, clearing by
another node's vote, a Candidate holding a pre-candidate, and a Leader
holding a pre-candidate are all reachable over the full model; hence the
antecedents of `PreCandidateVoteIsNextTerm`, `PreVoteElectsProbedVote`,
`PreVoteRequestPure`, `PreVoteNeverDemotesLeader` are exercised. Pre-vote grant
accumulation without quorum is not reachable from the 3-voter uniform seed
within budget (`CanaryNoPreGrantCounted`, structural: one remote grant is
already a quorum); it is covered by the joint-configuration trace
`pre_vote_resp_joint_accumulate`. The discharge antecedent (membership
evolution) is reached in the same constants (`MCAppendJointConfig` 147,484 and
`MCAppendUniformConfig` 13,848 distinct states in `v1-mc-standard-MC.log`
coverage).

## Not Reproduced

| Scenario | Config | States explored | Result |
|---|---|---|---|
| U-S1 pre-vote request purity | Update-full-noU4, Update-focus-noU4, Update-open-noU4, Update-hunt-next-term (+ sims) | up to 24.4M distinct (BFS) / 363k traces (sim) | No violation of `PreVoteRequestPure` (budget-limited) |
| U-S2 probe/election agreement | same | same | No violation of `PreCandidateVoteIsNextTerm`, `PreVoteElectsProbedVote` (budget-limited) |
| U-S3 cancellation | same + canary `CanaryNoPreVoteCleared` | same | Reachable; no violation (budget-limited) |
| Omitted membership context | Update-discharge, Update-discharge-membership | 4.7M / 5.3M distinct | No `DischargeContext` violation (budget-limited); open results are therefore usable within the bound |
| Reference safety (V0 properties) | MC.cfg, MC-membership.cfg (+ sims) | 14.5M / 7.4M distinct; 120k / 68k traces | No violation (budget-limited) |

## Spec fixes during checking

- `LogLE` absent-log equality (prior-model defect; before it no 3-voter remote
  grant was possible). All traces re-validated afterwards.
- Establishment lease and tick-only `seen_greater_log` reset (prior-model
  defects found while extending the trace spec). See `spec/changelog.md`.
