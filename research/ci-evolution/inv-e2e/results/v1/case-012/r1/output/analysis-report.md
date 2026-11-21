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

# Incremental update analysis (case-012: synthetic `baseline` ce863f4 → `update` aa05a38)

Inputs: `/work/old-source`, `/work/new-source` (verified byte-identical to the corresponding files of `artifact` HEAD~1/HEAD), prior suite `/work/previous/.specula-output` (V0, validated, LIMITED_COVERAGE, no unresolved errors). No history, network or external material was used.

## Chapter 1 decision: MODEL_CHANGE_REQUIRED

| Changed mechanism | Old behaviour | New behaviour | Model consequence |
|---|---|---|---|
| Leader commit computation | `LeaderState::handle_update_matched` → `calc_commit_log_id` → `Membership::greatest_majority_value` over `ReplicationState.matched` filtered to the current leader id (old core/replication.rs:141-220) — order-insensitive | `Engine::update_progress(target, matched)` → `Leader.progress: VecProgress<NID, Option<LogId>, Arc<EffectiveMembership>>` → filter "proposed by current vote" → `RaftState::update_committed` (core/replication.rs:133-138; engine_impl.rs:617-647; raft_state.rs:122-137). `greatest_majority_value` deleted. | New state: Engine leader state + VecProgress (vector **order**, values, internal committed). Commit is now a function of the vector order. |
| Leader append / fast commit | single-node `fast_commit` only (old engine_impl.rs:604-623) | `update_progress(self, log(m-1))` before a membership entry, `update_effective_membership` (progress `upgrade_quorum_set`), then `update_progress(self, last)` (engine_impl.rs:236-293) | `LeaderAppendEntries` rewritten as three sequential steps in one atomic Engine call. |
| Membership upgrade | effective replaced; no progress | `upgrade_quorum_set` rebuilds a VecProgress for the new quorum set and replays old ids in sorted order; ids that are new start at `None` (progress/mod.rs:222-232) | `UpgradeQuorumSet` operator; new voter progress resets. |
| Vote counting | `is_granted_by(effective)` | `is_vote_granted()` against the progress quorum set captured at `elect` (leader.rs:50-53; raft_state.rs:116-119) | `GrantVote`/`HandleVoteResp` count on `progress.cfg`; projected equal to effective at elect time. |
| Follower commit / membership promotion | promote committed membership whenever `committed >= effective` (old engine_impl.rs:370-372) | promote only when commit advances (`update_committed`) | `DeliverAppendEntries`, `FollowerCommitEntries`, leader paths: promotion on advance only. |
| `update_effective_membership` role update | n/a (no role change) | recompute server state unless calculated Leader before the change (engine_impl.rs:591-615) | `UpdateEffectiveMembership` with exact `calc_server_state` comparison. |
| Removed: `quorum/util.rs`, `greatest_majority_value`, `Engine.single_node_cluster` | | | V0 GreatestMajority trace superseded. |
| README, test-only edits, `admin.rs` signature, `Command` fields `since` | | | No modeled effect (excluded: commands/apply/metrics). |

Projected post-states differ for leader commit, membership promotion and leader state, so `NO_MODEL_CHANGE` is not possible.

## Abstraction revisited

V0 deliberately abstracted the `VecProgress` sorted-vector layout because it was not on the commit path (V0 modeling brief §3.2). The update makes `VecProgress::update` the production commit computation, and its result depends on the vector order: values are stored in place without `move_up` when `prev > committed` (progress/mod.rs:180-185), while the recompute loop treats `vector[0..=i]` as "ids with value >= vector[i]" (progress/mod.rs:194). The order is therefore modeled exactly (base.tla `VecUpdate`, `MoveUpPos`, `RecalcCommitted`, `UpgradeQuorumSet`), which also requires the node-id order (`ServerOrder`) and removes the V0 SYMMETRY reduction.

## Model repairs independent of the source delta (recorded separately)

1. `ReplicationState.matched` is per-`LeaderState` and starts at `None` (core/replication.rs:40-45); V0 kept stale matched values across leaderships → reset on `StartElection` (with the commit witness).
2. `ProposeMembership` admitted any allowed config; `change_membership` writes `next_safe(goal)` (membership.rs:288-309; coherent_impl.rs:62-74) → `SafeNext` guard.
3. `UpdateCommittedMembership` role update now uses the exact `calc_server_state` before/after comparison.
4. `Init`: servers outside the initial membership start as learners (only matters for the 5-server directed check).
5. Follower membership/truncation (found during checking, Round 2): V0 `DeliverAppendEntries` copied the sender's current effective membership and kept a stale tail after a conflict, and `RejectAppendConflict` did not revert an effective membership from the truncated range. The update's promote-on-advance rule exposed this as a spurious `MembershipOrder` violation. Repaired with a per-entry membership payload (`logConfig`) and the exact `handle_append_entries_req` / `truncate_logs` / `follower_update_membership` flow.
6. `OneOutstandingMembership` (unchanged text) is violated after `Crash` because restart resets the volatile commit while persisted membership is kept; the V0 model violates it identically (spec/output/mc-v0-control-oneoutstanding-crash.log). Classified pre-existing Case A; enabled only in crash-free configs.

## Update scenarios

- **U1 progress order × membership upgrade** (`ProposeMembership` → `UpgradeQuorumSet` → `HandleUpdateMatched`): old producer (follower ack) → changed upgrade/in-place update → old consumer (commit/apply, replication of committed). Expected: commit only with a quorum of every group (joint). Evidence: guide/src/dynamic-membership.md:3-4,157; guide/src/delete_log.md:18; progress/mod.rs:16,58,187,194.
- **U2 ordinary progress commit** (`ClientAppend`, `HandleUpdateMatched` in a uniform config): regression of the common path.
- **U3 follower promotion boundary** (`FollowerCommitEntries` with no commit advance).
- **U4 election vote counting on the progress quorum set** (`StartElection`, `HandleVoteResp`/`GrantVote`).

## Finding

**MC-1** (model checking, confirmed by code observation): the updated leader can commit an entry without a quorum of every joint group. See spec/bug-report.md.
