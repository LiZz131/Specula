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

# Incremental update analysis (baseline ce863f4 → update aa05a38)

Inputs: `/work/old-source` and `/work/new-source` (changed-file snapshots), the
neutral two-commit history in `artifact/` (`baseline` ce863f4, `update` aa05a38),
and the V0 prior suite. No history, issue, network, or oracle material was used.
The V0 prior reports no unresolved trace or model error; its results were
`LIMITED_COVERAGE` (tight bounds, scale run timed out) and remain so.

## Changed behavior, projected onto the model vocabulary

| # | Change (new source) | Old behavior | Projection |
|---|---|---|---|
| C1 | `LeaderState::handle_update_matched` now calls `Engine::update_progress(target, matched)` + `run_engine_commands` (`core/replication.rs:96-141`); `calc_commit_log_id`/`get_match_log_ids` removed | commit = `greatest_majority_value` over all voters' *current* matched ids filtered to the current leader id, recomputed on every ack | **changed** commit relation: new value is the cached `VecProgress.committed` (below) |
| C2 | `Leader` now owns `progress: VecProgress<NID, Option<LogId>, Arc<EffectiveMembership>>` created by `RaftState::new_leader` in `elect` (`leader/leader.rs:22-53`, `raft_state.rs:114-117`) | Leader held only `vote_granted_by` | **new state**: per-node vector order, cached committed, quorum set |
| C3 | `VecProgress::update` re-sorts and re-scans only when `prev <= committed < value`; a value already above `committed` is raised in place (`progress/mod.rs:163-205`); unknown ids are now ignored | helper existed but was test-only (no production caller in baseline) | **newly reachable** on the commit path |
| C4 | `Engine::leader_append_entries`: `fast_commit` removed; before a membership entry `update_progress(self, prev)`, then `update_effective_membership`, then `update_progress(self, last)` (`engine_impl.rs:234-290`) | single-node fast commit only, with the *new* membership | **changed** leader self-progress / commit timing; entries before a membership entry are committed with the old quorum set |
| C5 | `Engine::update_effective_membership` (new) upgrades the leader progress quorum set via `upgrade_quorum_set` (replays old ids' values, ascending id order) (`engine_impl.rs:591-615`, `progress/mod.rs:222-232`) | effective membership replaced; commit read it directly | **changed**: quorum set and vector order are rebuilt |
| C6 | Vote quorum through `Leader::is_vote_granted` = progress quorum set (`leader.rs:49-53`, `engine_impl.rs:107-108,208`) | `is_granted_by(effective)` | same value while the Leader exists (quorum set tracks effective); modeled explicitly |
| C7 | `RaftState::update_committed` (new) used by follower commit: committed-membership promotion only when committed increases (`raft_state.rs:121-136`, `engine_impl.rs:363-386`) | promotion checked unconditionally | **changed** guard (equal outcomes in reachable MC states, distinguishable on fixtures) |
| C8 | `Command::LeaderCommit{since,upto}`, `ReplicateCommitted`; `raft_core.rs` marks both unreachable outside LeaderState | inline replication-stream update + apply loop | runtime/apply framing; applied range unchanged (`last_applied+1..=upto`) — excluded (apply/payload) |
| C9 | `Membership::greatest_majority_value`, `quorum::majority_of` and their tests removed | used by C1 | V0 `GreatestMajority` trace relation is superseded |
| C10 | README, test-only edits, `Engine: PartialEq`, `single_node_cluster` removal, `assert`→`debug_assert` in `initialize`, `run_engine_commands` visibility/error type | — | no modeled effect |

Disposition (Chapter 1 gate): **MODEL_CHANGE_REQUIRED**. C1–C5 change the
modeled commit relation, add leader-progress state whose internal order decides
the commit result, and change action atomicity inside `leader_append_entries`.

## Model repairs needed by the update (independent of the source delta)

- **R1 blank entry**: `LeaderState::run` writes a blank entry before the leader
  loop handles any replication event (`core/leader_state.rs:72-97`). V0 omitted
  it; harmless when commit read `last_log_id()` directly, but with C4 the
  leader's own progress is only set on append, so omitting it admits
  model-only orders (follower acks processed while the leader's own progress is
  `None`). Added `LeaderWriteBlank` + `blankPending`.
- **R2 replication state reset**: each `LeaderState` starts with fresh
  `ReplicationState.matched = None` (`core/replication.rs:26-47`). V0 kept
  stale matched values across elections. Reset at `StartElection` (with the
  commit witness).
- **R3 membership proposals**: `change_membership` writes `next_safe(goal)`
  (`core/admin.rs:146-199`, `membership.rs:288-312`), never a direct
  uniform→uniform jump. V0 admitted any allowed config. Now goal-based.
- **R4 Leader cleared**: `internal_handle_vote_req` sets `state.leader = None`
  (`engine_impl.rs:896-897`) for vote grants and accepted/rejected appends.
- **R5 symmetry**: VecProgress iterates ids in ascending order, so the V0
  permutation `SYMMETRY` is unsound for the updated model and was removed.

Independent issue recorded, not repaired (outside the update's interaction):
follower `follower_update_membership` keeps the "last two memberships"
(committed := previous effective) while the model only copies the effective
membership; it does not affect leader commit through progress.

## Update Scenarios

- **U1 cached commit under reordered acknowledgements** (`AffectedActions`:
  HandleUpdateMatched, LeaderAppendEntries). Old producer: replication acks.
  Changed path: VecProgress::update. Old consumer: commit/committed membership,
  `ReplicateCommitted`. Uncertainty: the scan reads `vector[i]` as the minimum of
  the prefix `vector[0..=i]`, which holds only while values above `committed`
  stay sorted; values above `committed` are raised in place without re-sorting.
- **U2 progress vs. real replication** (Interaction: SendAppendEntries,
  HandleUpdateMatched early return `matched <= committed`, crash). Progress
  values must never exceed the leader's actual replication facts.
- **U3 membership change rebuilds progress** (ProposeMembership →
  update_effective_membership → upgrade_quorum_set → later acks). Rebuild
  replays old ids in ascending id order through `update`; ties keep insertion
  order, so a lower-id follower that has caught up can precede the leader.
- **U4 progress lifecycle** (StartElection/new_leader, GrantVote, Crash,
  Deliver/Reject clearing the Leader): stale progress must not survive a
  re-election, and the vote quorum must follow the progress quorum set.

Analytic expectation (to be tested, not assumed): combining U1 and U3, a joint
quorum set in which the tied prefix {lower-id follower, leader} is not a quorum
leaves both above `committed`; the leader's next append raises its own value in
place, breaking the sorted-prefix assumption; a later ack whose `move_up` stops
behind the leader then makes the scan accept the whole prefix as a quorum at a
value one prefix member has not reached. This is checked by the model with
`CommitWitnessSound` and the new `ProgressCommittedSound`, and observed on the
real Engine by the harness trace `membership_change_then_acks` (U1+U3).

## Properties

- Preserved (re-justified): TypeOK, ElectionSafety, ActiveLeaderHasCommittedVote,
  CommitWithinLocalLog, CommittedLogAgreement, MembershipOrder,
  OneOutstandingMembership, CommitWitnessSound (witness now computed from the
  leader's real replication facts, independent of VecProgress).
- Revised/new (Update.tla): ProgressCommittedSound (replaces the implicit
  greatest_majority_value guarantee), ProgressSortedAboveCommitted (documented
  VecProgress representation invariant, `progress/mod.rs:56-58`),
  ProgressWithinReplication, ProgressTracksEffective.
