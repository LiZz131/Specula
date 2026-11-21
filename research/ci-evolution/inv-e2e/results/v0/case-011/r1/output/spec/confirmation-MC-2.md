# Confirmation — MC-2: Pre-Vote-triggered election skips the voter check (removed leader campaigns)

- **Source**: MC (actual model-checking counterexample)
- **Novelty**: NEW within this run's evidence (introduced by the `update` commit; blind run, no external tracker consulted)
- **Status**: REPRODUCED
- **Severity**: Low (requires an operator's `trigger().elect(true)` on the current leader, the leader's self-removal, and Pre-Vote grants that arrive after the removal; consequence is term inflation / disruption by a non-voter, no committed-entry safety violation observed)
- **Source revision**: `artifact/` commit `update` 3ab6cddc34a5bf127747434bb41e20a1b9ef7769
- **Relation to MC-1**: independent root cause. MC-1 is the round surviving leader *establishment*; MC-2 is the deferred election not re-checking voter status after a *membership change*. The MC-1 candidate fix alone does not remove MC-2 (engine and runtime tests still fail, see §4). MC-1's U3 variant (inherited round + self-removal) is also prevented by MC-2's voter re-check.

## 1. Investigation (code reachability)

| Step | Code | Reachable? |
|---|---|---|
| Operator requests a cautious election on the current leader: `ExternalCommand::Elect{pre_vote:true}` checks only `is_voter` ("TODO: reject if it is already a leader?") and calls `pre_elect()` | `core/raft_core.rs:1683-1691` | yes (public `trigger().elect(true)`) |
| `pre_elect()` creates the round with probe `(term+1, self)`; Pre-Vote requests are sent to the effective voters | `engine/engine_impl.rs:298-322`, `core/raft_core.rs:1385-1478` | yes |
| A voter whose leader lease has expired (e.g. idle leader with heartbeats disabled, or heartbeats delayed) grants the probe | `engine/engine_impl.rs:414-447` | yes |
| The leader removes itself: `change_membership` → joint → uniform; with `removed_leader_step_down = Never` (documented option) it keeps leading; with `After(ms)` until the countdown | `config/step_down_policy.rs:13-28`, `core/step_down_watcher.rs` | yes |
| No step clears `pre_candidate` (the leader never runs `become_following` while it keeps leading) | `engine/handler/vote_handler/mod.rs:154-162,234-250` | yes |
| RaftCore delivers the late grant (pre-candidate present, equal leader id) | `core/raft_core.rs:1803-1820` | yes |
| `handle_pre_vote_resp` → quorum of the *frozen* round config → `elect()` with no voter check | `engine/engine_impl.rs:530-541` | yes |
| `do_elect` bumps and persists the term (SaveVote) and queues `SendVote` to the new config's voters; `update_internal_server_state` then sends the non-member to following/learner | `engine/engine_impl.rs:262-289` | yes |

Every other route to `do_elect` checks `is_voter` at the moment of the election
(`raft_core.rs:1683-1686` external elect, `raft_core.rs:1971-1974` tick); the
Pre-Vote path checks it only when the round starts.

## 2. Model-checking evidence

| Run | Spec / cfg | Result |
|---|---|---|
| U3 hunt (one-voter seed, membership 2, Pre-Vote on) | `Update` / `MC_hunt_prevote_membership.cfg` | `PreVoteElectOnlyByVoter` violated, 11 states — `spec/output/mc-hunt-prevote-membership.log` |
| Full update check (complete MCNext) | `Update-full-rest.cfg`, `Update-full-prevote.cfg` | `PreVoteElectOnlyByVoter` violated (these traces use the MC-1 inherited-round path) |
| Model control with only the MC-1 fix | `spec/fixcheck/MC_hunt_prevote_membership.cfg` | see `spec/bug-report.md` campaign table |
| Model control with both fixes | `spec/fixcheck2/` | see `spec/bug-report.md` campaign table |

Counterexample (11 states): n1 is the single voter and elects itself (term 1,
Leader); n1 appends joint `<<{1},{3}>>`; operator `ExternalPreElect(n1)` on the
leader → probe `(2, n1)` to n3 (`preRoundFromLeader = TRUE`); n3 (no lease)
grants; n1 commits the joint config and appends uniform `<<{3}>>` (n1 no longer a
voter, keeps leading); the grant arrives → quorum of the frozen
`<<{1},{3}>>` → `DoElect` on a non-voter: vote `(2, n1)`, Candidate.

## 3. Reproduction

Commands (from `.specula-output/`, each source tree with its own target dir):

```bash
harness/repro/run-repro.sh MC-2
SPECULA_REPRO_SOURCE=$PWD/fixcheck-source  SPECULA_REPRO_LABEL=mc1-fix-only           harness/repro/run-repro.sh MC-2
SPECULA_REPRO_SOURCE=$PWD/fixcheck2-source SPECULA_REPRO_LABEL=candidate-fix-combined harness/repro/run-repro.sh MC-2
```

| Test | Level | Update revision | MC-1 fix only | Combined fix |
|---|---|---|---|---|
| `harness/repro/specula_repro_removed_leader_pre_vote_test.rs` (leader {1,2,3}; `pre_elect`; joint, commit, uniform {2,3}; late grant via RaftCore's filter) | Engine | FAILED: non-voter's vote `(2,1,Q)` → `(3,1,uncommitted)`, SaveVote/SendVote queued — `spec/output/repro-MC-2-engine-update.log` | FAILED — `repro-MC-2-engine-mc1-fix-only.log` | PASS — `repro-MC-2-engine-candidate-fix-combined.log` |
| `harness/repro/t91_specula_removed_leader_pre_vote.rs` (3 RaftCore nodes; `removed_leader_step_down = Never`; idle leader with heartbeats disabled until follower leases expire; `trigger().elect(true)` on the leader; pre-vote answers delayed 800 ms; `change_membership({1,2})`) | Runtime | FAILED 3/3: removed node 0 goes from term 1 to term 2 and becomes Learner (it started an election after removal) — `spec/output/repro-MC-2-runtime-update.log` | FAILED 3/3 — `repro-MC-2-runtime-mc1-fix-only.log` | PASS 3/3: node 0 stays at term 1 (still leading under `Never`) — `repro-MC-2-runtime-candidate-fix-combined.log` |

Old-version control: not applicable (no Pre-Vote / `trigger().elect(bool)` in the
exact-old revision). In the old code an operator `elect()` on a leader started
the election immediately, while the node was still a voter; the deferral that
lets the election happen after removal is introduced by the update.

## 4. Consequence

A node that has just removed itself from the voter set starts an election at a
higher term: it persists the inflated vote and sends `RequestVote` to the new
configuration's voters (observed: term 1 → 2 on the removed node). By the vote
rules, voters whose lease has expired would adopt the higher term and leave
their current leader — the term-inflation disruption Pre-Vote is meant to
prevent, here caused by a non-member (argued from `handle_vote_req`, not
observed in the test, which keeps the followers' elections disabled).

## 5. Recommendation

Before the Pre-Vote-triggered `elect()`, re-check (as the tick and external
command do) that the node is still a voter and not an established leader, and
cancel the round on membership changes that remove the node; optionally reject
`ExternalCommand::Elect{pre_vote:true}` on a leader.
