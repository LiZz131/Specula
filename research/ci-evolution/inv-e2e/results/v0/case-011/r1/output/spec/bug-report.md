# Bug Report — OpenRaft Pre-Vote update (commit `update` 3ab6cdd)

## Summary

- Update Scenarios tested: U1–U5 (`modeling-brief.md` §8) plus the five prior V0 scenarios
- Bugs found: 2 — MC-1 (Medium) and MC-2 (Low), both REPRODUCED (`spec/confirmation-MC-1.md`, `spec/confirmation-MC-2.md`); independent root causes
- Configs run: see the campaign table below (`spec/output/campaign-summary.txt` is the raw record)
- All results are bounded (`LIMITED_COVERAGE`); "no violation" never means proof.

## Bug 1: Stale Pre-Vote round survives leader establishment and makes the new leader re-elect

- **Scenario**: U1 (stale Pre-Vote round × leader establishment); consequence variant U3
- **Severity**: Medium
- **Invariant violated**: `PreVoteNeverDemotesEstablishedLeader` (action property, `spec/Update.tla`); also `PreVoteElectOnlyByVoter` (U3 variant) and diagnostic `PreVoteRoundNotInheritedByLeader`
- **Config**: `MC_hunt_prevote_leader_tickonly.cfg` (timer-driven only) — also `MC_hunt_prevote_leader.cfg`, `Update-full.cfg` (complete MCNext), `Update-focused.cfg`, `Update-open.cfg`, `MC_hunt_prevote_inherited_round.cfg`, `Update-full-rest.cfg` (U3)
- **Counterexample**: 14 states, `spec/output/mc-hunt-prevote-leader-tickonly.log` (shortest with admin trigger: 12 states, `spec/output/mc-hunt-prevote-leader.log`; full model: depth 14, `spec/output/mc-upd-full.log`)

### Trace Summary (timer-only counterexample, 3 voters, Pre-Vote enabled, no crash, no drop, no membership change)

1. Node 1's election tick fires with Pre-Vote enabled: `PreElect` probes `(1, n1)`; PreVote requests to n2, n3.
2. n3 answers the probe: granted.
3. n1 reaches a Pre-Vote quorum `{n1, n3}` → `DoElect`: Candidate at term 1, SaveVote queued.
4. n1 persists its vote (self-grant response emitted).
5. n1's election tick fires again while it is still a Candidate (its uncommitted vote has a zero lease): `PreElect` probes `(2, n1)`; the candidate state for term 1 is kept.
6. n1 sends the term-1 vote request to n3; n1 counts its own grant.
7. n3 grants `(1, n1)` and persists it; its granted VoteResponse is delivered.
8. n1 reaches a quorum for term 1 → **Leader** with committed vote `(1, n1)`; `preCandidateActive[n1]` remains TRUE with probe `(2, n1)`.
9. n1 persists the committed vote.
10. n3 answers the `(2, n1)` probe: granted (its vote `(1, n1)` is uncommitted, so no lease blocks it).
11. n1 receives the grant: the runtime filter passes (pre-candidate present, same leader id), quorum `{n1, n3}` → `DoElect` on the established leader: vote `(2, n1)` uncommitted, role Candidate, Leader object retained. **Property violated.**

The engine-level part (steps 5–11 as engine calls) is the validated fresh trace
`traces/stale_pre_vote_after_establish.ndjson`.

### Root Cause

- `RaftCore::handle_tick_election` (`openraft/src/core/raft_core.rs:1959-2036`) and `ExternalCommand::Elect{pre_vote:true}` (`raft_core.rs:1683-1691`) call `Engine::pre_elect()` without checking for an in-flight candidacy; `pre_elect` (`openraft/src/engine/engine_impl.rs:298-322`) keeps `candidate`.
- `Engine::establish_leader` (`engine_impl.rs:855-881`) takes `candidate` only; `update_vote(committed)` → `update_internal_server_state` → `become_leader` (`engine/handler/vote_handler/mod.rs:154-162,172-230`) — only `become_following` (`:234-250`) clears `pre_candidate`.
- `Notification::PreVoteResponse` is delivered when `pre_candidate.is_some()` and the leader id matches (`raft_core.rs:1803-1820, 2067-2090`); there is no server-state check.
- `Engine::handle_pre_vote_resp` calls `self.elect()` on quorum (`engine_impl.rs:530-541`); `do_elect` (`:262-289`) bumps the term and installs an uncommitted vote while the Leader object survives, violating the leader-handler assertion `leader.vote >= state.vote` (`engine_impl.rs:977-982`).

### Affected Code

- `openraft/src/core/raft_core.rs:1959-2036`: tick starts Pre-Vote while a candidate election is in flight
- `openraft/src/engine/engine_impl.rs:855-881`: `establish_leader` does not cancel the Pre-Vote round
- `openraft/src/core/raft_core.rs:1803-1820`: PreVoteResponse delivered regardless of server state
- `openraft/src/engine/engine_impl.rs:516-554`: `handle_pre_vote_resp` elects on quorum without checking leadership
- `openraft/src/engine/engine_impl.rs:977-982`: assertion that fires in debug builds

### Reproduction (summary; details in `spec/confirmation-MC-1.md`)

| Test | Update revision | Candidate-fix sanity control |
|---|---|---|
| engine: `harness/repro/specula_repro_stale_pre_vote_test.rs` | FAIL — `(Candidate, T3-N1 uncommitted)` after the late grant (`spec/output/repro-MC-1-engine-update.log`) | PASS (`spec/output/repro-MC-1-engine-mc1-fix-only.log`) |
| runtime: `harness/repro/t90_specula_stale_pre_vote.rs` | FAIL 3/3 — RaftCore panic `leader.vote(<T2-N1:Q>) >= state.vote(<T3-N1:->)`, write → `Fatal(Panicked)` (`spec/output/repro-MC-1-runtime-update.log`) | PASS 3/3 — stays Leader at term 2, write commits (`spec/output/repro-MC-1-runtime-mc1-fix-only.log`) |

### Recommendation

Cancel the Pre-Vote round when leadership is established (clear `pre_candidate`
in `establish_leader`, or in `become_leader`), and make the PreVoteResponse path
ignore responses unless the node is still a non-leader whose vote is the one
the round was started from. Optionally skip `pre_elect` while a real election is
in flight. Model-level control: with the round cancelled on establishment
(`spec/fixcheck/`), U1 is not violated in either U1 hunt (10.4M / 10.1M distinct
states, budget-limited), while U3 is still violated through MC-2.

---

## Bug 2: Pre-Vote-triggered election skips the voter check, so a leader that removed itself starts an election

- **Scenario**: U3 (voter gate)
- **Severity**: Low
- **Invariant violated**: `PreVoteElectOnlyByVoter`
- **Config**: `MC_hunt_prevote_membership.cfg` (also `Update-full-rest.cfg`, `Update-open-rest.cfg`, and `spec/fixcheck/` with the MC-1 fix applied)
- **Counterexample**: 11 states, `spec/output/mc-hunt-prevote-membership.log`

### Trace Summary

1. n1 (single voter of `{1}`) elects itself and becomes Leader at term 1.
2. n1 appends the joint config `<<{1},{3}>>`.
3. Operator `trigger().elect(true)` on the leader (`ExternalPreElect`): voter check passes; probe `(2, n1)` sent to n3.
4. n3 (no lease) grants; the answer is delayed.
5. n1 commits the joint config and appends the uniform config `<<{3}>>`: n1 is no longer a voter but keeps leading (`StepDownPolicy::Never`, or within the `After` window).
6. The grant arrives: runtime filter passes; quorum of the frozen `<<{1},{3}>>` → `DoElect` on a non-voter: vote `(2, n1)`. **Property violated.**

### Root Cause

`Engine::handle_pre_vote_resp` (`openraft/src/engine/engine_impl.rs:530-541`)
calls `elect()` without the `is_voter` check that the tick
(`raft_core.rs:1971-1974`) and the external command (`raft_core.rs:1683-1686`)
perform at election time; the Pre-Vote path checks it only when the round
starts, the round's quorum is frozen, and nothing cancels the round when the
leader removes itself. `ExternalCommand::Elect{pre_vote:true}` also accepts a
leader (`raft_core.rs:1683-1691`, "TODO: reject if it is already a leader?").

### Affected Code

- `openraft/src/engine/engine_impl.rs:530-541`: Pre-Vote quorum → `elect()` without voter re-check
- `openraft/src/core/raft_core.rs:1683-1691`: cautious election accepted on a leader
- `openraft/src/core/raft_core.rs:1803-1820`: response delivered regardless of membership/server state

### Reproduction (details in `spec/confirmation-MC-2.md`)

| Test | Update revision | MC-1 fix only | Combined fix |
|---|---|---|---|
| engine: `harness/repro/specula_repro_removed_leader_pre_vote_test.rs` | FAIL — non-voter's vote `(2,1,Q)` → `(3,1)` (`spec/output/repro-MC-2-engine-update.log`) | FAIL | PASS |
| runtime: `harness/repro/t91_specula_removed_leader_pre_vote.rs` | FAIL 3/3 — removed node 0: term 1 → 2, Learner (`spec/output/repro-MC-2-runtime-update.log`) | FAIL 3/3 | PASS 3/3 |

### Recommendation

Re-check `is_voter` (and that the node is not an established leader) before the
Pre-Vote-triggered `elect()`, and cancel the round when a membership change
removes the node; optionally reject `trigger().elect(true)` on a leader. Model
control with both candidate fixes (`spec/fixcheck2/`): U1–U4 not violated in
`Update-full.cfg`, `Update-full-rest.cfg`, `MC_hunt_prevote_membership.cfg`
(15.7M / 18.9M / 9.4M distinct states, budget-limited).

---

## Campaigns

Raw logs: `spec/output/mc-<run>.log`. `fixcheck*` rows are sanity controls on copies of the model with candidate fixes (not the reference).

| Run | Spec / cfg | Purpose | Result | Explored | Depth / traces | Coverage status |
|---|---|---|---|---|---|---|
| `std-MC` | MC / MC.cfg | Standard convergence round (Pre-Vote toggled) | no violation | 23943591 distinct (107950681 generated) | 20 | budget-limited, 13,880,638 queued |
| `std-MC-membership` | MC / MC-membership.cfg | Standard round, one-voter seed | no violation | 299637 distinct (2701721 generated) | 29 | exhausted |
| `std-MC-sim` | MC / MC.cfg (simulation, depth 100) | Standard round simulation follow-up | no violation (time limit reached, exit 0) | 67,987,118 states checked | 144,684 traces (mean len 71) | simulation, budget-limited |
| `upd-full` | Update / Update-full.cfg | Full update check U1–U4 | Action property PreVoteNeverDemotesEstablishedLeader is violated | 597804 distinct (2836314 generated) | 14 | stopped at violation |
| `upd-full-rest` | Update / Update-full-rest.cfg | Full update check U2–U4 | Action property PreVoteElectOnlyByVoter is violated | 4519069 distinct (20782912 generated) | 17 | stopped at violation |
| `upd-full-prevote-rest` | Update / Update-full-prevote.cfg | Full update check U2–U4, Pre-Vote always on | Action property PreVoteElectOnlyByVoter is violated | 5074546 distinct (23312224 generated) | 17 | stopped at violation |
| `upd-full-U2U4` | Update / Update-full-U2U4.cfg | Full update check U2, U4 + invariant | no violation | 13657797 distinct (61720462 generated) | 19 | budget-limited, 7,801,092 queued |
| `upd-full-U2U4-sim` | Update / Update-full-U2U4.cfg (simulation) | Simulation follow-up | no violation (time limit reached, exit 0) | 71,209,078 states checked | 151,666 traces (mean len 71) | simulation, budget-limited |
| `upd-focused` | Update / Update-focused.cfg | Concrete focused U1–U4 | Action property PreVoteNeverDemotesEstablishedLeader is violated | 2587022 distinct (12943709 generated) | 15 | stopped at violation |
| `upd-focused-rest` | Update / Update-focused-rest.cfg | Concrete focused U2–U4 | no violation | 16357101 distinct (89327648 generated) | 18 | budget-limited, 8,452,747 queued |
| `upd-focused-U2U4` | Update / Update-focused-U2U4.cfg | Concrete focused U2, U4 | no violation | 12918826 distinct (69457997 generated) | 16 | budget-limited, 6,802,140 queued |
| `upd-open` | Update / Update-open.cfg | Open focused (EnvUpdate) U1–U4 | Action property PreVoteNeverDemotesEstablishedLeader is violated | 749257 distinct (3426563 generated) | 14 | stopped at violation |
| `upd-open-rest` | Update / Update-open-rest.cfg | Open focused U2–U4 | Action property PreVoteElectOnlyByVoter is violated | 1385309 distinct (5911429 generated) | 16 | stopped at violation |
| `upd-open-U2U4` | Update / Update-open-U2U4.cfg | Open focused U2, U4 | no violation | 25392291 distinct (94371529 generated) | 17 | budget-limited, 17,262,195 queued |
| `upd-discharge` | Update / Update-discharge.cfg | Discharge EnvUpdate (3 voters) | no violation | 8095012 distinct (36484203 generated) | 17 | budget-limited, 4,527,198 queued |
| `upd-discharge-sim` | Update / Update-discharge.cfg (simulation) | Discharge simulation follow-up | no violation (time limit reached, exit 0) | 55,677,335 states checked | 118,577 traces (mean len 71) | simulation, budget-limited |
| `upd-discharge-seed1` | Update / Update-discharge-seed1.cfg | Discharge EnvUpdate (one-voter seed) | no violation | 299637 distinct (2701721 generated) | 29 | exhausted |
| `hunt-prevote-leader` | Update / MC_hunt_prevote_leader.cfg | Hunt U1 | Action property PreVoteNeverDemotesEstablishedLeader is violated | 60921 distinct (285556 generated) | 14 | stopped at violation |
| `hunt-prevote-leader-tickonly` | Update / MC_hunt_prevote_leader_tickonly.cfg | Hunt U1, timer-only | Action property PreVoteNeverDemotesEstablishedLeader is violated | 93292 distinct (473990 generated) | 16 | stopped at violation |
| `hunt-prevote-inherited-round` | Update / MC_hunt_prevote_inherited_round.cfg | Hunt U1 precondition | Invariant PreVoteRoundNotInheritedByLeader is violated | 12046 distinct (50642 generated) | 12 | stopped at violation |
| `hunt-prevote-membership` | Update / MC_hunt_prevote_membership.cfg | Hunt U3/U2 with membership | Action property PreVoteElectOnlyByVoter is violated | 2919 distinct (10170 generated) | 14 | stopped at violation |
| `hunt-prevote-membership-U2` | Update / MC_hunt_prevote_membership_U2.cfg | Hunt U2/U4 with membership | no violation | 9665167 distinct (74774917 generated) | 28 | budget-limited, 1,950,934 queued |
| `hunt-prevote-crash` | Update / MC_hunt_prevote_crash.cfg | Hunt U2/U4/U5 with crash and loss | no violation | 21908449 distinct (127377112 generated) | 18 | budget-limited, 9,173,513 queued |
| `hunt-prevote-crash-sim` | Update / MC_hunt_prevote_crash.cfg (simulation) | Simulation follow-up | no violation (time limit reached, exit 0) | 78,250,844 states checked | 185,157 traces (mean len 71) | simulation, budget-limited |
| `canary-prevote-win` | Update / Update-canary-prevote-win.cfg | Canary (expected violation) | Action property CanaryNoPreVoteWin is violated | 719 distinct (1546 generated) | 6 | stopped at violation |
| `canary-lease-reject` | Update / Update-canary-lease-reject.cfg | Canary (expected violation) | Action property CanaryNoLeaseRejectedPreVote is violated | 150772 distinct (670550 generated) | 12 | stopped at violation |
| `canary-cancel-following` | Update / Update-canary-cancel-following.cfg | Canary (expected violation) | Action property CanaryNoPreCandidateCancelledByFollowing is violated | 1497 distinct (3815 generated) | 9 | stopped at violation |
| `canary-preround-leader` | Update / Update-canary-preround-leader.cfg | Canary (expected violation) | Invariant CanaryNoPreRoundOnLeader is violated | 67651 distinct (287704 generated) | 13 | stopped at violation |
| `canary-win-after-membership` | Update / Update-canary-win-after-membership.cfg | Canary (expected violation) | Action property CanaryNoPreVoteWinAfterMembershipChange is violated | 3642 distinct (11424 generated) | 13 | stopped at violation |
| `fixcheck-MC_hunt_prevote_leader` | fixcheck / MC_hunt_prevote_leader.cfg | Control: MC-1 fix in model | no violation | 10439775 distinct (64638957 generated) | 24 | budget-limited, 3,776,121 queued |
| `fixcheck-MC_hunt_prevote_leader_tickonly` | fixcheck / MC_hunt_prevote_leader_tickonly.cfg | Control: MC-1 fix in model | no violation | 10059601 distinct (66906946 generated) | 25 | budget-limited, 3,498,484 queued |
| `fixcheck-MC_hunt_prevote_membership` | fixcheck / MC_hunt_prevote_membership.cfg | Control: MC-1 fix only | Action property PreVoteElectOnlyByVoter is violated | 3024 distinct (10150 generated) | 12 | stopped at violation |
| `fixcheck-Update-full-rest` | fixcheck / Update-full-rest.cfg | Control: MC-1 fix only | Action property PreVoteElectOnlyByVoter is violated | 5332203 distinct (24423763 generated) | 18 | stopped at violation |
| `fixcheck2-MC_hunt_prevote_membership` | fixcheck2 / MC_hunt_prevote_membership.cfg | Control: MC-1 + MC-2 fixes | no violation | 9358078 distinct (73547137 generated) | 28 | budget-limited, 1,848,002 queued |
| `fixcheck2-Update-full` | fixcheck2 / Update-full.cfg | Control: MC-1 + MC-2 fixes, U1–U4 | no violation | 15666582 distinct (70769165 generated) | 19 | budget-limited, 8,968,223 queued |
| `fixcheck2-Update-full-rest` | fixcheck2 / Update-full-rest.cfg | Control: MC-1 + MC-2 fixes, U2–U4 | no violation | 18880325 distinct (85086051 generated) | 19 | budget-limited, 10,894,836 queued |

## Spec fixes during this run

- `NoLog` canonicalization (prior defect: log-less elections impossible in the 3-voter model).
- Lease installed on leader establishment (prior defect exposed by a fresh trace).
- Greater-log reset moved to the tick; tick lease/single-voter guards.
See `spec/changelog.md`.
