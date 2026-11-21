# Modeling Brief: OpenRaft exact-old V0

## 1. System Overview

- **System**: OpenRaft 0.6.4 exact-old tree, Rust; Category A (distributed/message-passing).
- **Boundary**: leader append and replication, acknowledged per-peer progress, effective/committed membership, joint quorum calculation, commit advancement, follower commit handling, and ordinary elections.
- **Architecture**: `Engine` performs synchronous protocol state transitions and queues `Command`s; `RaftCore`/`LeaderState` execute storage, network, replication-stream, and application work asynchronously (`openraft/src/engine/engine_impl.rs:29-56`, `openraft/src/core/raft_core.rs:565-590`).
- **Replication concurrency**: one task per target serializes AppendEntries RPCs, then sends `ReplicaEvent::UpdateMatched` to the leader actor; the leader actor owns externally meaningful matched progress and commit state (`openraft/src/replication/mod.rs:92-148`, `openraft/src/core/replication.rs:53-78`).
- **Membership**: the last membership is effective immediately; at most two recent memberships are retained as committed/effective, and a joint quorum requires a majority in every component (`openraft/src/membership/membership_state.rs:6-27`, `openraft/src/quorum/joint.rs:48-97`).
- **Failure assumptions**: crash-stop/restart and message loss are modeled only at actor/message boundaries. Storage internals, snapshots, timing, serialization, and payload meaning are excluded by scope.

## 2. Scenarios

### Scenario 1: Acknowledged progress drives leader commit

**Mechanism**: a successful replication response advances one target monotonically; the leader recomputes the greatest current-leader-term log acknowledged by a quorum of the effective membership.

**Evidence**:
- `ReplicationCore::update_matched` only raises its local matched value and emits `UpdateMatched` (`openraft/src/replication/mod.rs:468-497`).
- `LeaderState::handle_update_matched` asserts monotonicity, updates the leader-owned value, filters acknowledgements to the current leader id, and advances commit only after effective-membership quorum calculation (`openraft/src/core/replication.rs:97-169`, `openraft/src/core/replication.rs:183-220`).
- `Membership::greatest_majority_value` selects the minimum of the per-component majority values for joint consensus (`openraft/src/membership/membership.rs:271-307`).

**Affected code paths**: `send_append_entries`, `update_matched`, `handle_update_matched`, `get_match_log_ids`, `calc_commit_log_id`, `greatest_majority_value`.

**Suggested modeling approach**: per-leader/per-target `matchedIndex` and `matchedTerm`, explicit Append/Ack messages, and one actor-level `HandleUpdateMatched` action that updates progress and commit atomically. Record a ghost commit witness for a falsifiable quorum invariant.

**Priority**: High. This is the exact externally meaningful commit path and is directly exercised by progress and quorum traces.

### Scenario 2: Effective membership controls quorum before commitment

**Mechanism**: a membership entry becomes effective on append, while committed membership advances later; safe changes use a joint intermediate configuration and reject a second outstanding voter change.

**Evidence**:
- Leader append updates effective membership as soon as a membership entry is assigned a log id (`openraft/src/engine/engine_impl.rs:232-273`).
- `has_pending_config` blocks another voter change while effective membership is ahead of commit (`openraft/src/core/admin.rs:135-172`).
- `next_safe` moves uniform-to-uniform through a joint configuration (`openraft/src/membership/membership.rs:309-347`, `openraft/src/quorum/coherent_impl.rs:62-74`).
- Leader and election quorum checks use effective membership (`openraft/src/core/replication.rs:183-219`, `openraft/src/engine/engine_impl.rs:105-137`).

**Affected code paths**: `change_membership`, `leader_append_entries`, `next_safe`, `update_committed_membership`, `truncate_logs`.

**Suggested modeling approach**: per-node sets of quorum components plus committed/effective membership log positions. Split propose/effective from commit promotion, and preserve the one-outstanding-membership guard.

**Priority**: High. The effective/committed distinction changes which acknowledgements constitute commit.

### Scenario 3: Follower commit is capped by locally matched input

**Mechanism**: a follower accepts the leader's commit position only up to the maximum of the request's previous log and last entry; commit and committed membership only move forward.

**Evidence**:
- `handle_append_entries_req` first checks the vote and previous-log match, appends conflicts, then invokes follower commit (`openraft/src/engine/engine_impl.rs:276-342`).
- `follower_commit_entries` computes `min(leader_committed, max(prev_log_id,last_entry))`, raises local commit only, and promotes effective membership only when covered (`openraft/src/engine/engine_impl.rs:344-373`).

**Affected code paths**: `handle_append_entries_request`, `handle_append_entries_req`, `follower_do_append_entries`, `follower_commit_entries`.

**Suggested modeling approach**: explicit AppendEntries delivery followed by the exact min/max cap and monotonic membership promotion.

**Priority**: High. It is the follower-side boundary preventing commit beyond durable/local input.

### Scenario 4: Ordinary election under effective membership

**Mechanism**: election increments the vote, self-grants, and becomes a committed-vote leader only after the effective membership grants a quorum; higher votes revert the node.

**Evidence**:
- `Engine::elect` increments the term, self-grants, and distinguishes single-node fast path from vote-request slow path (`openraft/src/engine/engine_impl.rs:105-137`).
- Vote responses ignore old votes, step down on higher votes, and commit leadership only after an effective-membership quorum (`openraft/src/engine/engine_impl.rs:169-227`).
- Vote requests enforce vote ordering and log freshness unless the incoming vote is already committed (`openraft/src/engine/engine_impl.rs:797-864`).

**Affected code paths**: `elect`, `handle_vote_req`, `internal_handle_vote_req`, `handle_vote_resp`.

**Suggested modeling approach**: term, voted-for/leader id, committed-vote bit, granted voter set, and candidate/leader roles; preserve log freshness in grant actions.

**Priority**: Medium. Elections are needed to make replication states reachable and to check election safety.

## 3. Modeling Recommendations

### 3.1 Model

| What | Why | How |
|---|---|---|
| Per-target acknowledgement | Scenario 1 | `matchedIndex`/`matchedTerm`; monotonic actor action |
| Current-term commit filter | Scenario 1 | only indices whose log leader term matches the leader vote can establish a new commit |
| Joint quorum | Scenarios 1-2 | configuration is a nonempty set of nonempty voter sets; quorum in every component |
| Committed/effective membership | Scenario 2 | separate config and log-position variables, with one outstanding change |
| Follower commit cap | Scenario 3 | exact `min(leaderCommit,max(prev,lastEntry))` relation |
| Election and vote commitment | Scenario 4 | candidate self-vote, freshness-guarded grants, quorum promotion |
| Loss/crash bounds | Makes actor/message boundaries explicit | loss and crash/recover actions, bounded only in MC wrapper |

### 3.2 Do Not Model

| What | Why |
|---|---|
| Metrics and allocation | Excluded and not protocol state |
| Network framing/serialization | Excluded; messages are semantic records |
| Snapshot transfer and purge layout | Outside this V0 boundary |
| Application payload/result meaning | Only log term/index and membership kind affect scoped behavior |
| Precise heartbeat/election time | Timers are nondeterministic triggers only |
| `VecProgress` internal vector ordering | Trace the real helper behavior, but model externally meaningful per-node values rather than the optimization layout |

## 4. Proposed Extensions

| Extension | Variables | Purpose | Scenario |
|---|---|---|---|
| Actor-owned progress | `matchedIndex`, `matchedTerm` | Represent acknowledged log ids | 1 |
| Commit witness | `witnessIndex`, `witnessNodes`, `witnessConfig` | Make commit quorum non-vacuously checkable | 1 |
| Dual membership | `effectiveConfig`, `committedConfig`, membership positions | Represent immediate effect vs later promotion | 2 |
| Semantic messages | `messages` | Separate replication send, follower handling, and acknowledgement | 1, 3 |
| Crash state | `crashed` | Bound actor unavailability and volatile leader-state loss | 1, 4 |

## 5. Proposed Invariants

| Invariant | Type | Description | Targets |
|---|---|---|---|
| TypeOK | Safety/structural | Every variable remains in its declared small domain | All |
| ElectionSafety | Safety | Two leaders in one term identify the same leader | Scenario 4 |
| ActiveLeaderHasCommittedVote | Safety | A leader role always has a quorum-committed vote | Scenario 4 |
| CommitWithinLocalLog | Safety | No node commits beyond its local last log | Scenario 3 |
| CommittedLogAgreement | Safety | nodes agree on the term at every commonly committed index | Scenarios 1, 3 |
| CommitWitnessSound | Safety | every newly established leader commit has a current-term acknowledgement quorum in the recorded effective configuration | Scenario 1 |
| MembershipOrder | Safety/structural | committed membership is never newer by position than effective membership | Scenario 2 |
| OneOutstandingMembership | Safety | an uncommitted effective membership has a strictly older committed predecessor | Scenario 2 |

## 6. Findings Pending Verification

### 6.1 Model-Checkable

| ID | Open exact-old question | Expected invariant | Scenario |
|---|---|---|---|
| MC-PRIOR-1 | Across reordered send/ack/loss steps, can leader commit advance without a current-term quorum of its effective membership? | CommitWitnessSound, CommittedLogAgreement | 1 |
| MC-PRIOR-2 | During a safe uniform→joint→uniform evolution, can effective and committed membership positions permit a second outstanding change or a non-joint quorum witness? | MembershipOrder, OneOutstandingMembership, CommitWitnessSound | 2 |
| MC-PRIOR-3 | Can follower commit exceed its locally accepted request boundary under delivery and loss interleavings? | CommitWithinLocalLog, CommittedLogAgreement | 3 |
| MC-PRIOR-4 | Can ordinary effective-membership elections create two committed-vote leaders for one term? | ElectionSafety, ActiveLeaderHasCommittedVote | 4 |

### 6.2 Test-Verifiable

| ID | Description | Test approach |
|---|---|---|
| TV-1 | Vector progress preserves monotonic committed value while updates arrive out of order | Existing `progress::t::vec_progress_update` with trace capture |
| TV-2 | Replication lag threshold uses saturating distance | Existing `core::replication_state_test::test_is_line_rate` with trace capture |
| TV-3 | Joint quorum and greatest-majority calculations match concrete inputs | Existing quorum/effective-membership/membership tests with trace capture |

### 6.3 Code-Review-Only

No incident-targeted or future-facing code-review candidates are included in this neutral prior.

## 7. Reference Pointers

- Full report: `analysis-report.md`
- Commit path: `openraft/src/core/replication.rs:97-220`
- Replication task: `openraft/src/replication/mod.rs:264-497`
- Engine append/follower path: `openraft/src/engine/engine_impl.rs:232-405`
- Membership/quorum: `openraft/src/membership/membership.rs:271-347`
- Neutral tests: paths listed in `/work/input-manifest.json`; no historical or external references were used.

---

## Incremental update (baseline ce863f4 → update aa05a38): MODEL_CHANGE_REQUIRED

Full evidence: `analysis-report.md` § Incremental update analysis.

### Update Scenario U1: cached VecProgress commit on the leader commit path
- **Mechanism**: `LeaderState::handle_update_matched` → `Engine::update_progress`
  → `VecProgress::update` (`core/replication.rs:96-141`, `engine_impl.rs:617-648`,
  `progress/mod.rs:163-205`). `committed` is re-derived only when an updated value
  crosses it; values above it are raised in place.
- **Model**: explicit `progVec` (ordered), `progCommitted`, `progQS`; `PUpdate`
  follows `move_up` and the prefix scan exactly. Properties:
  `ProgressCommittedSound`, `ProgressSortedAboveCommitted`, `CommitWitnessSound`.
- **Priority**: High (decides commit).

### Update Scenario U2: progress bounded by real replication
- **Mechanism**: early return when `matched <= committed`; leader self-progress
  only on append; LeaderState resets matched values.
- **Model**: `HandleUpdateMatched`, `LeaderAppendEntries`, `LeaderWriteBlank`,
  `Crash`. Property `ProgressWithinReplication`.

### Update Scenario U3: membership change rebuilds the progress
- **Mechanism**: `leader_append_entries` → `update_effective_membership` →
  `upgrade_quorum_set` (`engine_impl.rs:270-287,591-615`, `progress/mod.rs:222-232`).
- **Model**: `ProposeMembership` (next_safe) + `EngineUpdateEffective` + `PUpgrade`.
  Properties `ProgressTracksEffective`, `CommitWitnessSound`,
  `OneOutstandingMembership`. Hunt: `Update_hunt_u1_membership_progress.cfg`.

### Update Scenario U4: leader progress lifecycle
- **Mechanism**: `elect`/`new_leader`, `internal_handle_vote_req` clearing the
  Leader, crash/restart (no Leader).
- **Model**: `StartElection`, `GrantVote`, `DeliverAppendEntries`,
  `RejectAppendConflict`, `Crash`. Hunt: `Update_hunt_u4_reelection_crash.cfg`.

### Updated recommendations / exclusions
- Model the VecProgress internal order (previously "do not model"): the update
  made it decide the commit result.
- Still excluded: apply/state-machine and client response (`LeaderCommit`
  command execution), metrics, snapshot, network framing, payload meaning.
- Code-review-only candidates: none beyond the model-checked scenarios above.
