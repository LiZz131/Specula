# Bug Report — OpenRaft (case-012 updated revision, synthetic commit `update` aa05a38)

## Summary

- Scenarios tested: U1 (progress order × membership upgrade), U2 (ordinary progress commit), U3 (follower promotion), U4 (vote counting), plus inherited V0 Scenarios 1-4.
- Bugs found: 1 (MC-1).
- Configs with violations: `Update_full.cfg` / `Update_full_cws.cfg` / `Update_full_pcs.cfg` / `Update_full_sorted.cfg` (complete MCNext), `Update_focused*.cfg`, `Update_open.cfg`.
- Coverage is bounded (3 servers; LIMITED_COVERAGE). See `spec/validation-summary.md` for every campaign.

## Bug 1: Leader commits an entry without a quorum of every joint-membership group (VecProgress order corruption)

- **Scenario**: U1 — membership change (joint config) followed by an out-of-order acknowledgement.
- **Severity**: Critical (commit rule violated; the directed 5-server check reaches two different entries committed at the same index).
- **Invariant violated**: `CommitWitnessSound` (also `ProgressCommittedSupported`, and the representation invariant `ProgressSortedAboveCommitted` one step earlier).
- **Config**: `spec/Update_full_cws.cfg` (full `MCNext`, 3 servers, MaxTerm 1, MaxIndex 1, 1 election, 1 client append, 1 membership change, 1 loss, 0 crashes).
- **Counterexample**: 11 states, `spec/output/MC-1_counterexample_Update_full_cws.out` (copy of the final-model run `spec/output/mc-upd-full-cws-final.log`; first found in `mc-upd-full-cws-r1.log`).
- **Implementation observation**: `engine::specula_update_test::specula_observe_joint_commit_requires_both_groups` fails on the updated revision (`spec/output/new-observe-u1.log`); the same sequence is a TLC-validated implementation trace (`traces/u1_joint_commit_order.ndjson`, `spec/output/trace-u1_joint_commit_order-r3.log`).

### Trace Summary

1. `StartElection(n2)`, `GrantVote(n2,n1)`: n2 leads term 1; `Engine::elect` creates `Leader.progress` over `{n1,n2,n3}` with vector order `<n1,n2,n3>`.
2. `ClientAppend(n2)` (blank, index 0): `update_progress(n2,(1,0))` moves n2 to the front: `<n2:(1,0), n1:None, n3:None>`.
3. n2 replicates index 0 to n1; `HandleUpdateMatched` → `update_progress(n1,(1,0))` → progress committed `(1,0)` (n1,n2) → leader commit index 0. Correct.
4. `ProposeMembership(n2, {{n1,n2,n3},{n1,n3}})` — the `next_safe` joint config that removes the leader. In `leader_append_entries`: `update_progress(n2, log(0))` is a no-op; `update_effective_membership` calls `upgrade_quorum_set`, which rebuilds the vector in id order and replays old values: `<n1:(1,0), n2:(1,0), n3:None>`, progress committed recomputes to `None` (no joint quorum). Then `update_progress(n2,(1,1))`: prev `(1,0)` > committed `None`, so the value is stored **in place without `move_up`**: `<n1:(1,0), n2:(1,1), n3:None>` — n1 (lagging) now sits before n2 (larger).
5. n2 replicates indices 0..1 to n3; n3 acks `(1,1)`.
6. `HandleUpdateMatched`: `(1,1) > committed (1,0)` → `update_progress(n3,(1,1))`: prev `None` ≤ committed `None` → `move_up` stops below n2 (`(1,1) >= (1,1)`), so n3 stays at position 2; the loop checks `is_quorum(vector[0..=2]) = is_quorum({n1,n2,n3})` = true and sets committed `(1,1)`. The term filter passes and `RaftState.committed` becomes index 1. Only n2 and n3 hold index 1; group `{n1,n3}` has 1 of 2 → **no joint quorum**. `CommitWitnessSound` fails (witness `{n2,n3}`, config `{{n1,n3},{n1,n2,n3}}`).

### Root Cause

`VecProgress::update` (openraft/src/progress/mod.rs:163-207) keeps only elements above `committed` sorted, and re-sorts (`move_up`) an element only when `prev <= committed < value` (progress/mod.rs:184-186). When `prev > committed`, the new value is written in place (progress/mod.rs:182), which can place a larger value behind a smaller one and break the documented invariant "Elements with values greater than the `committed` are sorted in descending order" (progress/mod.rs:58). The recompute loop then treats the prefix `vector[0..=i]` as "ids that have value GE `vector[i]`" (progress/mod.rs:194) and passes it to `is_quorum`, so a lagging node is counted.

Before the update this latent defect did not affect commits: the leader committed through `Membership::greatest_majority_value` (old core/replication.rs:141-220), which is order-insensitive. The update routes leader commit through `Engine::update_progress` → `Leader.progress.update` (engine_impl.rs:617-647; core/replication.rs:133-138; leader_append_entries engine_impl.rs:270-288), and `upgrade_quorum_set` (progress/mod.rs:222-232) resets `committed` to the default while preserving tied values in id order, which makes the in-place case reachable right after a membership change. Old-revision control (`spec/output/old-control-u1.log`): on the identical acknowledgement state, old `greatest_majority_value` yields index 1 (correct), while the old (unused) `VecProgress` sequence yields index 2. Attribution: a pre-existing latent defect that the update moved onto the production commit path.

### Consequence

The leader treats an entry as committed, applies it and advertises the commit, although one joint group has no majority holding it.

- 3 servers (removing the leader): the over-committed entry is the joint membership entry itself, which unblocks the next membership step (`has_pending_config`, core/admin.rs:136-140).
- 5 servers, adding voters (`{1,2,3}` → `[{1,2,3},{1,2,3,4,5}]`): the directed run `MC5_u1_divergence.cfg` (5-server instantiation of the same MC wrappers; `ACTION_CONSTRAINT DirectedU1` only restricts exploration) violates **`CommittedLogAgreement`** in 17 states (`spec/output/MC-1_consequence_counterexample_MC5_divergence.out`, final model; first found in `mc-mc5-u1-divergence-r1.log`): n2 (term 1) commits index 0 with n1; n1 is elected in term 2 by {n1,n3}, appends and commits a different index 1 with {n1,n3} (a legitimate majority of `{1,2,3}`); the stale leader n2 appends the joint config at index 1 and, after only learner n4 acknowledges it, commits it through the VecProgress defect (holders {n2,n4}; group `{1,2,3}` has 1 of 3). Two different entries are committed at index 1. With a correct commit computation n2 could not commit index 1 (n1 and n3 have moved to term 2).
- Engine-level confirmation of the voter-adding case: `spec/output/new-observe-add-voters.log` (`harness/src/specula_observe_test.rs`): committed index 2 while only {2,4} hold it.

### Affected Code

- `openraft/src/progress/mod.rs:180-203`: in-place update without reordering; recompute assumes a sorted prefix.
- `openraft/src/progress/mod.rs:222-232`: `upgrade_quorum_set` resets committed and replays ties in id order.
- `openraft/src/engine/engine_impl.rs:270-288`: membership append path (`update_progress` / `update_effective_membership` / `update_progress`).
- `openraft/src/engine/engine_impl.rs:617-647`: `update_progress` turns `VecProgress.committed` into `RaftState.committed`.
- `openraft/src/core/replication.rs:133-138`: acknowledgements feed `update_progress`.

### Recommendation

Keep the vector sorted on every increase (call `move_up` whenever the value grows, not only when it crosses `committed`), or recompute the quorum value from scratch in `update`/`upgrade_quorum_set` for small quorum sets. Add a regression test equivalent to `specula_observe_joint_commit_requires_both_groups`.

---

## Not Reproduced

| Scenario | Config | States Explored | Result |
|---|---|---|---|
| Standard convergence | MC.cfg | 4,234,432 (queue 0) | No violation (complete) |
| V0 S1 progress/loss | MC_hunt_s1_progress.cfg | 180,196 (queue 0) | No violation (complete) |
| V0 S2 membership | MC_hunt_s2_membership.cfg | 299,908 (queue 0) | No violation (complete; MaxIndex 0 cannot reach MC-1) |
| V0 S3 follower commit | MC_hunt_s3_follower_commit.cfg | 76,978 (queue 0) | No violation (complete) |
| V0 S4 elections | MC_hunt_s4_election.cfg | 183,487 (queue 0) | No violation (complete) |
| U2 uniform progress commit | Update_hunt_u2_uniform.cfg | 3.67M BFS + simulation | No violation (time-bounded) — consistent with MC-1 requiring a membership upgrade |
| U3 follower promotion | Update_hunt_u3_follower.cfg | 3.58M BFS + simulation | No violation (time-bounded) |
| U4 elections / vote counting | Update_hunt_u4_election.cfg | 366,862 (queue 0) | No violation (complete) |
| U1 deep (2 membership changes, crash, loss) | Update_hunt_u1_deep.cfg (MC-1 properties omitted) | simulation | No further distinct violation (time-bounded) |
| Remaining update properties | Update_full_control / faults_control / focused_control / open_control | 3.2M-5.5M each + simulation | No violation (time-bounded) |
| Discharge | Update_discharge.cfg | 3.58M + simulation | No violation (time-bounded) |

## Spec adjustments during checking

- `OneOutstandingMembership`: pre-existing Case A under crash/restart (identical on the V0 model); excluded from crash-enabled configs only.
- `DischargeContext`: frame for MC-private budget counters corrected (`CounterFrame`).
- Follower path (Round 2, Case B): V0 `DeliverAppendEntries` copied the sender's current effective membership; replaced by per-entry membership payloads and the exact append/truncate/membership flow (spurious `MembershipOrder` violation in `mc-upd-hunt-u1deep-sim1.log`). MC-1 reproduces unchanged on the repaired model.
