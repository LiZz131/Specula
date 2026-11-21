# Exact-old code-only analysis report

## Scope and method

This report analyzes only `/work/source/` under `/work/scope.md`. The tree is treated as an immutable neutral baseline. Per the experiment override, archaeology, history, issues, release notes, papers, upstream material, other revisions, and behavioral internet research were not performed. The analysis covered all 15 priority implementation files from the input manifest plus the full in-scope call-chain files `core/admin.rs`, `core/client.rs`, `core/append_entries.rs`, `core/replication_state.rs`, `quorum/quorum_set_impl.rs`, and `quorum/coherent*.rs`. The seven listed neutral-test areas were read as well.

Category: **A — distributed/message-passing**. The principal concurrency boundary is the channel between independent per-target `ReplicationCore` tasks and the single leader actor. `Engine` mutations are synchronous; queued commands introduce storage/network/application awaits after the protocol decision.

## Structural map

| Layer | Responsibility | Atomicity boundary |
|---|---|---|
| `Engine` | vote, log-id cache, role, commit, membership state; emits commands | one synchronous method call (`engine_impl.rs:29-56`) |
| `RaftCore` | main role loop, storage and network execution | one selected event is handled to completion before the role loop selects another (`raft_core.rs:249-266`, `leader_state.rs:97-137`) |
| `LeaderState` | leader-owned replication handles, matched values, commit advancement | a `ReplicaEvent` handler; storage/apply awaits do not allow another leader-loop event to mutate actor state |
| `ReplicationCore` | serialized AppendEntries RPCs for one target, conflict search, heartbeat | one independent Tokio task per target (`replication/mod.rs:92-148`) |
| Membership/quorum | uniform/joint voter groups and majority decisions | pure synchronous calculations |

## Exact leader replication and commit path

1. `LeaderState::write_entry` creates one entry reference and calls `Engine::leader_append_entries` (`core/admin.rs:249-274`).
2. The engine assigns current leader-id/index log ids, extends its log-id cache, updates effective membership immediately for a membership payload, attempts only the single-node fast commit, and queues append/replicate commands (`engine/engine_impl.rs:232-273`, `engine/engine_impl.rs:604-623`).
3. The runtime persists the input entries before the leader-specific replicate command notifies all target streams (`core/raft_core.rs:862-874`, `core/leader_state.rs:186-207`, `core/client.rs:153-165`).
4. Each per-target task serializes AppendEntries, loads a consecutive range, includes current `committed`, and handles Success/HigherVote/Conflict. On success, `update_matched` only raises progress and sends an actor event (`replication/mod.rs:264-445`, `replication/mod.rs:468-497`).
5. The leader actor receives `ReplicaEvent::UpdateMatched`, raises `ReplicationState.matched`, derives voter match log ids, excludes acknowledgements whose leader id differs from its current vote leader id, and calculates the joint-majority value (`core/replication.rs:97-152`, `core/replication.rs:183-220`).
6. If higher, commit and committed membership advance before streams receive the new commit and application work starts (`core/replication.rs:146-169`).

## Quorum and membership findings

- A uniform quorum counts matching identifiers and succeeds when `2*count > group_size` (`quorum/quorum_set_impl.rs:5-77`).
- A joint quorum requires every child group to succeed and exposes the union of child identifiers (`quorum/joint.rs:48-97`).
- `greatest_majority_value` computes each component's majority threshold, selects that component's majority order statistic, then takes the minimum across components (`membership/membership.rs:271-307`).
- The effective membership is the last observed membership log and drives leader replication commit and election quorums (`membership/effective_membership.rs:15-36`, `core/replication.rs:183-219`, `engine/engine_impl.rs:105-137`).
- Membership state retains committed and effective values because one uncommitted membership may need to be reverted after conflict truncation (`membership/membership_state.rs:6-27`, `engine/engine_impl.rs:407-471`).
- Safe voter evolution uses a shared component: if the goal is not already coherent with the current joint value, `find_coherent` constructs `[current-last, goal]`; the next step then becomes uniform (`quorum/coherent_impl.rs:62-74`, `membership/membership.rs:309-347`).

## Follower boundary

`handle_append_entries_req` first applies the common vote guard, verifies `prev_log_id`, truncates conflicts, appends the nonmatching suffix, and finally updates follower commit. The commit candidate is exactly `min(leader_committed, max(prev_log_id,last_received_entry))`; it is applied only if greater than local commit. When the resulting commit covers the effective membership log, that membership becomes committed (`engine/engine_impl.rs:276-373`). This action is modeled without transport/storage framing.

## Election boundary

`elect` increments the vote, self-grants, and immediately commits leadership only for a self-quorum; otherwise it queues durable vote save and parallel requests (`engine/engine_impl.rs:105-137`). Vote responses are ignored if stale, force follower/learner state if higher, or add a grant and commit the vote after effective-membership quorum (`engine/engine_impl.rs:169-227`). Incoming uncommitted votes require a last-log comparison, while an already committed vote skips that freshness check (`engine/engine_impl.rs:797-864`).

## Failure assumptions

- Message loss may occur between semantic send and handler actions.
- Crash stops one node. Restart preserves vote/log/membership inputs but clears volatile commit in the runtime initialization path (`core/raft_core.rs:181-205`).
- The main actor is not concurrently mutated while an event handler awaits; per-target replication tasks only communicate through channels.
- Storage errors that terminate or shut down a task are not expanded into disk-layout states in V0.

## Exclusions and false-positive controls

- Snapshot transfer, log purge representation, precise timers, network framing, metrics, memory layout, and application data are excluded by the binding scope.
- `VecProgress` is traced as an exact-old helper but its internal sorted vector is not made protocol state because the scoped leader commit path uses externally meaningful `BTreeMap<NodeId,LogId>` plus `greatest_majority_value`.
- Assertions/TODOs were used only to locate assumptions. No suspicion is reported as a defect, and no future delta or expected evaluation outcome is encoded.
- No Case C finding is asserted by this analysis. The four model-checkable entries are neutral questions for bounded checking.

## Analysis coverage

- Priority implementation files read: 15/15.
- Additional in-scope call-chain files read: 7.
- Priority neutral-test areas read: 7/7.
- Historical commits/issues/PRs/release notes searched: 0, intentionally skipped by experiment override.
- External behavioral sources used: 0.

---

# Incremental update analysis (V0 exact-old -> V1 updated revision)

## Inputs and identity

- Old source: `/work/old-source/` (changed-file snapshot) = `artifact` commit `ce863f4` (`baseline`).
- New source: `/work/new-source/` = `artifact` commit `aa05a38` (`update`); writable copy used for the harness: `work-source/` (copied from `artifact`, same HEAD).
- Prior suite: `/work/previous/.specula-output/` (V0). Prior validation had no unresolved errors; its `MC_scale.cfg` run was budget-limited (LIMITED_COVERAGE), which is retained as a prior limit.
- Diff read in full (`git diff ce863f4 aa05a38`): 27 files, +702/-358. Category stays **A (distributed / message passing)**; the update does not change the actor/channel architecture.

## Chapter 1 reconnaissance: changed behavior projected onto the model vocabulary

| # | Old behavior (exact-old) | New behavior (updated) | Modeled? | Projection |
|---|---|---|---|---|
| U1 | Leader commit computed in `LeaderState::handle_update_matched` via `calc_commit_log_id` = `greatest_majority_value` over `get_match_log_ids` (voter ids of *current effective* membership, leader's own value = `last_log_id()`, only values with current leader id) (old `core/replication.rs:138-221`) | `handle_update_matched` calls `Engine::update_progress(target, matched)` (`core/replication.rs:133-138`); commit = `VecProgress` greatest quorum value over a **leader-owned progress** (`leader/leader.rs:29`), accepted only if its `leader_id` equals the vote (`engine/engine_impl.rs:618-647`), via `RaftState::update_committed` (`raft_state.rs:122-136`) | yes (`HandleUpdateMatched`) | commit value equivalent (proof sketch below) **but** the progress state now has its own lifetime and quorum set (U2/U3) and the skip `Some(matched) <= committed` now skips the progress update itself |
| U2 | Per-target `ReplicationState.matched` lives in `LeaderState`; leader's own value is its last log id | `Engine::elect` -> `RaftState::new_leader` creates a fresh `Leader{vote_granted_by, progress: VecProgress::new(effective)}` (`raft_state.rs:116-118`, `engine_impl.rs:101-109`); progress dropped whenever `state.leader = None` (`engine_impl.rs:200,897`); leader's own progress updated only by `leader_append_entries` | yes (`StartElection`, `GrantVote`, delivery/conflict, crash) | **changed state meaning**: matched rows become per-leadership, reset on election, owned by Engine |
| U3 | Vote quorum and commit quorum read `membership_state.effective` at use time | Vote quorum `Leader::is_vote_granted` and commit quorum read the **progress quorum set** captured at `new_leader` and replaced only by `update_effective_membership` -> `upgrade_quorum_set` (`leader/leader.rs:50-53`, `engine_impl.rs:592-615`, `progress/mod.rs:222-232`) | yes (`StartElection`, `GrantVote`, commit) | new state `progressConfig`; equal to effective on all modeled paths only if every effective change on a node with leader state upgrades it |
| U4 | `leader_append_entries`: membership entry sets effective immediately; `fast_commit` commits the whole batch iff the (new) effective config is a self-quorum; **no committed-membership promotion** (old `engine_impl.rs:232-273,604-623`) | for each membership entry: `update_progress(self, prev_log_id)` under the old quorum set, then `update_effective_membership` (upgrade quorum set, possibly server-state update), finally `update_progress(self, last)` under the new set (`engine_impl.rs:236-292`); commit may use followers' progress; `update_committed` promotes committed membership | yes (`LeaderAppendEntries`) | **changed post-state set**: commit point, committed membership, and progress rows differ (e.g. `test_leader_append_entries_fast_commit_upto_membership_entry`: old commits nothing, new commits up to the entry before the membership entry and promotes the old effective) |
| U5 | `follower_commit_entries` promoted committed membership whenever `committed >= effective.log_id`, even without a commit increase (old `engine_impl.rs:344-373`) | promotion only inside `update_committed`, i.e. only when commit increases (`engine_impl.rs:364-389`, `raft_state.rs:122-136`) | yes (`DeliverAppendEntries`, `FollowerCommitEntries`) | changed guard on committed-membership promotion |
| U6 | `VecProgress::update` panicked (`unreachable!`) on an unknown id | unknown id is ignored and the current committed value is returned (`progress/mod.rs:163-171`); `upgrade_quorum_set` copies every old id (`progress/mod.rs:222-232`) | yes (`ProgressUpdateValue`, upgrade) | new branch (no-op) |
| U7 | `update_effective_membership` did not exist; `try_update_membership` set effective only | new `update_effective_membership` also upgrades leader progress and may update server state unless the pre-state is Leader (`engine_impl.rs:592-615`); used by `initialize` and leader append | yes (leader append), trace-only otherwise | new action boundary |
| U8 | `Command::LeaderCommit{upto}` / `FollowerCommit{upto}`; leader commit applied entries inline | new `ReplicateCommitted`, `since` fields; `LeaderState` executes them (`core/leader_state.rs:190-206`) | no (commands/apply excluded) | excluded: apply/notification mechanics; the commit value they carry is modeled through `committed` and `SendAppendEntries.leaderCommit` |
| U9 | `greatest_majority_value`, `quorum::majority_of` | deleted | helper only | V0 `GreatestMajority` trace relation becomes obsolete; commit calculation is validated through `UpdateProgress` instead |
| U10 | README, `Engine.single_node_cluster` cache, `initialize` `assert_eq`->`debug_assert_eq`, `PartialEq` derives, test edits | same | no | excluded: no protocol state |

Commit-value equivalence for U1 (bounded argument, checked later by trace validation): every progress value lies in the leader's log, where `LogId` order equals index order and terms are non-decreasing; the greatest quorum value carries the current leader id iff some current-term index has quorum acknowledgement, and then both computations choose the same index. Skipping progress updates with `matched <= committed` leaves, for every threshold above the current commit, exactly the same set of nodes at or above the threshold, because a skipped value was at most the commit at the time it arrived and the commit only grows. Therefore the commit decision is unchanged even though the stored progress values differ.

## Decision gate

**Disposition: `MODEL_CHANGE_REQUIRED`.** U2, U3, U4, U5, U6 and U7 change modeled state meaning (per-leadership progress and its quorum set), the leader-append post-state set (commit, committed membership, progress), the follower promotion guard, and action boundaries. U8-U10 are excluded by scope.

## Reference surfaces to revisit

Variables (`matchedIndex`/`matchedTerm` meaning; new `leaderState`, `progressConfig`), `Init`, `StartElection`, `GrantVote`, `LeaderAppendEntries` (and `ClientAppend`/`ProposeMembership` callers), `HandleUpdateMatched`, `DeliverAppendEntries`, `RejectAppendConflict`, `Crash`, `FollowerCommitEntries`, `ProgressUpdateValue`, the commit helpers, new trace-only `UpdateProgress`, `UpdateEffectiveMembership`, `HandleVoteResp`; properties reading matched rows (`CommitWitnessSound`) and membership (`MembershipOrder`, `OneOutstandingMembership`).

## Prior scenarios to recheck

Scenario 1 (commit path moved into Engine), Scenario 2 (effective membership now also upgrades leader progress and drives commit inside leader append), Scenario 3 (follower promotion guard changed), Scenario 4 (vote quorum now read from the progress quorum set).

## Explicit exclusions (unchanged)

Metrics, allocation, memory layout, framing, serialization, timing, payload meaning, snapshot transfer, application of committed entries, and the new command plumbing (`ReplicateCommitted`, `LeaderCommit{since}`) beyond the commit value they carry.

## Chapter 3: update-focused analysis (after the first reference draft)

Interactions traced through the unchanged system:

- **Producers of the changed commit path**: `ReplicationCore` acknowledgements (unchanged) feed `handle_update_matched`, which now skips the Engine progress update when `matched <= committed` (`core/replication.rs:133-135`). Effect on commit: none (argument in the reconnaissance table); effect on stored progress: values may lag. Checked by `Update!ProgressMonotonic` and commit properties.
- **Leader append as a commit producer** (new): `leader_append_entries` can now commit using *followers'* progress when a membership entry upgrades the quorum set (U-S1). The MC canary `MC_reach_u1_append_commit.cfg` reaches it (leader removes itself to `{n2,n3}`, later proposes `{n1,n3}` and commits index 1 at append time from n3's earlier acknowledgement). Consequences are checked by `CommittedLogAgreement`, `Update!CommitWitnessSound_new` and `MembershipOrder`.
- **Election / crash / step-down** (U-S2): leader data and progress are recreated at `elect` and dropped by `internal_handle_vote_req`, `handle_vote_resp` (higher vote) and restart. The V0 witness clause that read live progress rows is no longer meaningful (divergence evidence E1/E1mc).
- **Consumers of committed membership**: `has_pending_config` uses the commit index, not the committed-membership record, so the promotion-on-advance change (U-S3) does not alter admission. The covered-but-unpromoted state is produced by the real code only from a hand-built fixture (code observation) and was not reached by the model within budget (`MC_reach_u3_follower_promotion.cfg`, 8.6M distinct states).
- **Vote quorum** reads the progress quorum set captured at `elect`. On all modeled paths it equals the effective membership (`Update!LeaderProgressConfigCurrent`); RaftCore paths that change vote/role without clearing Engine leader data are outside the modeled scope.
- **Old abstraction rechecked**: the follower membership/truncation abstraction (V0 `DeliverAppendEntries`) was not faithful once logs hold more than one entry. It was repaired (changelog Round 2) because the update's checks need deeper logs.

Prior findings lineage: the V0 suite had no findings (neutral prior); nothing to reuse.

## Chapter 5: completeness review

- Re-read the full diff after generation. Every changed behavioral branch has a reference location: elect/new_leader (`StartElection`), is_vote_granted (`GrantVote`, `HandleVoteResp`), leader_append_entries (`LeaderAppendEntries` + `UpdateProgressF` + `UpdateEffectiveMembershipF`), update_progress (`UpdateProgressF`, `UpdateProgress`), update_committed (`UpdateCommittedF` used by leader, follower and trace-only paths), follower_commit_entries (`DeliverAppendEntries`, `FollowerCommitEntries`), VecProgress unknown id / upgrade (`ProgressUpdateValue`, `UpgradeRow`), handle_update_matched skip (`HandleUpdateMatched`), try_update_membership -> update_effective_membership (only `initialize` uses it besides leader append; `initialize` is outside the model, as in V0).
- Model-to-source check: no old action bypasses the new commit path; every action that drops Engine leader data resets `leaderState` and progress rows; `progressConfig` is written only at election and by the leader-append upgrade.
- Excluded with rationale: command plumbing and apply (U8), deleted helpers (U9), non-protocol edits (U10).
