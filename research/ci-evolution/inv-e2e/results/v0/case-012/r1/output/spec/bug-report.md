# Bug Report — OpenRaft (incremental run, baseline ce863f4 → update aa05a38)

## Summary

- Scenarios tested: prior S1–S4 (rerun on the updated model) and update scenarios U1–U4
- Bugs found: 1 (MC-1)
- Configs run: see the campaign table in `spec/validation-summary.md` and
  `## Not Reproduced` below
- Reproduction: real-runtime reproduction on the updated revision (5/5 runs) and
  identical-schedule control on the baseline revision (passes); see
  `spec/confirmation-MC-1.md`

## Bug 1: Leader commits a joint-membership entry without a quorum of the joint configuration (VecProgress cached commit)

- **Scenario**: U1 (cached VecProgress commit) × U3 (membership change rebuilds progress)
- **Severity**: Critical (state-machine safety: two nodes applied different entries at the same index in a 5-voter runtime reproduction)
- **Invariant violated**: `CommitWitnessSound` (reference), `ProgressCommittedSound`
  (Update.tla); precursor `ProgressSortedAboveCommitted` (documented VecProgress
  representation invariant)
- **Config**: `Update_hunt_u1_consequence.cfg` (full `MCNext`); same mechanism also in
  `MC_hunt_s2_membership.cfg` (inherited V0 hunt), `Update_full.cfg`,
  `Update_focused.cfg`, `Update_open.cfg`, `Update_hunt_u1_membership_progress.cfg`,
  `Update_hunt_u2_*.cfg`, `Update_hunt_u4_*.cfg`
- **Counterexample**: 11 states on the final artifacts,
  `spec/output/upd-hunt-u1-consequence-final.log` (leader n2, joint
  `[{n1,n2,n3},{n1,n3}]` — the same instance as the real-Engine trace
  `traces/membership_change_then_acks.ndjson`); the earlier run
  `spec/output/upd-hunt-u1-consequence-bfs.log` is the symmetric instance (leader
  n3, joint `[{n1,n2,n3},{n1,n2}]`) narrated below. Structural precursor:
  `spec/output/upd-hunt-u1-bfs-final.log`. TLC replay modules: `spec/output/ttrace/`.

### Trace Summary

1. n3 starts an election (term 1), n1 grants; n3 becomes leader and writes its
   blank entry (index 0). Its new `VecProgress` over `{n1,n2,n3}` becomes
   `[n3:(1,0), n1:None, n2:None]`.
2. n1 receives and acknowledges index 0; `update_progress(n1,(1,0))` commits
   index 0 (`{n3,n1}` is a majority).
3. n3 proposes the next safe membership toward `{n1,n2}` (removing itself):
   joint `[{n1,n2,n3},{n1,n2}]` at index 1. In `leader_append_entries`,
   `update_effective_membership` rebuilds the progress with
   `upgrade_quorum_set`, replaying old ids in ascending order: n1 (value (1,0)),
   n2 (None), n3 (value (1,0)); the tie keeps n1 ahead of the leader and, since
   `{n1,n3}` is not a joint quorum, the cached committed stays `None`.
   `update_progress(n3,(1,1))` then raises the leader's value **in place**
   (prev > committed), giving `[n1:(1,0), n3:(1,1), n2:None]` — no longer
   sorted above `committed`.
4. n3 replicates indexes 0..1 to n2; n2 acknowledges (1,1).
5. `update_progress(n2,(1,1))`: prev None ≤ committed < value, so `move_up`
   runs but stops behind n3 (equal value). The scan starts at n2's position and
   tests the prefix `{n1,n3,n2}` — a quorum — and sets committed to
   `vector[2] = (1,1)`. The leader commits index 1 and promotes the joint
   membership to committed. Nodes actually holding index 1: `{n2,n3}`; the
   `{n1,n2}` component has only n2 → **not a joint quorum**.

### Root Cause

`VecProgress::update` (`openraft/src/progress/mod.rs:163-205`) recomputes the
cached `committed` only when an updated value crosses it (`:184`) and otherwise
raises the value in place (`:182`) without restoring order. Its scan
(`:188-201`) assumes the documented representation invariant that values above
`committed` form a descending prefix (`:56-58`), reading `vector[i]` as the
minimum of `vector[0..=i]`. `upgrade_quorum_set` (`:222-232`) rebuilds the
vector by replaying old ids in ascending id order, so a caught-up lower-id
follower tied with the leader precedes the leader; when the tied prefix is not a
quorum of the new (joint) set, both stay above `committed`, and the leader's next
in-place raise (`engine_impl.rs:287`) breaks the invariant. The next crossing
update then commits a value one prefix member has not reached.

Before the update this helper had no production caller; the baseline commit rule
(`LeaderState::calc_commit_log_id` + `Membership::greatest_majority_value`)
recomputed the joint majority from all matched values on every acknowledgement.
The update routes leader commit through it: `core/replication.rs:137`,
`engine_impl.rs:270-287, 603, 618-648`, `leader/leader.rs:29`.

### Affected Code

- `openraft/src/progress/mod.rs:182-201`: in-place raise above `committed`; prefix scan assumes sortedness
- `openraft/src/progress/mod.rs:222-232`: `upgrade_quorum_set` replay order (ties keep id order)
- `openraft/src/engine/engine_impl.rs:270-287`: `leader_append_entries` → `update_effective_membership` then `update_progress(self, last)`
- `openraft/src/engine/engine_impl.rs:603`: progress upgraded on effective-membership change
- `openraft/src/engine/engine_impl.rs:618-648`: `update_progress` commits the cached value
- `openraft/src/core/replication.rs:133-138`: acknowledgements feed `update_progress`

### Recommendation

Keep the vector sorted whenever a value above `committed` grows (always run
`move_up`, or re-scan from position 0), or compute the committed value from
scratch over the quorum set (as the baseline `greatest_majority_value` did)
after an upgrade or out-of-order raise. Add a regression test with a leader
whose id is larger than a caught-up follower during a joint change.

### Consequence and attribution

The leader applies the joint membership entry, answers the first
`change_membership` step, and proceeds to the uniform step although the joint
entry is not durable on a joint quorum (3-voter runtime reproduction,
`harness/repro/t90_specula_joint_commit_repro.rs`, 6/6 runs).

With 5 voters (`harness/repro/t91_specula_joint_commit_divergence.rs`): leader
3 changes toward `{1,2,4}`; the joint entry `[{1,2,3,4,5},{1,2,4}]` at index 9
is committed and applied by node 3 although only `{2,3}` hold it (no majority of
either component). After isolating 3 and 2, nodes `{1,4,5}` (a majority of the
old configuration, none of which has index 9) elect a new leader that commits
and applies a different entry at index 9. Observed: node 3 applied
`(term 1, node 3, index 9)`, node 1 applied `(term 2|3|4, node 1|5, index 9)` —
**two nodes applied different log entries at the same index** (6/6 runs). The
3-server model shows the commit-quorum violation; the divergence needs ≥5
voters and was shown on the real runtime only.

**Update-introduced**: the identical schedules on the baseline revision commit
neither joint entry and show no divergence (2/2 tests pass).

---

## Not Reproduced

| Scenario | Config | States Explored | Result |
|---|---|---|---|
| see `spec/validation-summary.md` § Model checking for every campaign, its bounds, state counts, queue, and outcome | | | |

## Spec fixes during checking

- `OneOutstandingMembership` (V0) → `OneOutstandingMembershipDurable` (Case A):
  crash legitimately resets the volatile commit while the committed membership is
  reloaded from storage (`core/raft_core.rs:193-196`). See `spec/changelog.md`.
