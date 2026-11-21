# Instrumentation specification — OpenRaft exact-old V0

## 1. Trace event schema

All lines use the required Category A envelope:

```json
{"tag":"trace","ts":"<epoch-nanoseconds>","event":{"name":"<action>","...":"..."}}
```

Engine events contain `nid`, `pre`, `post`, and `args`. A snapshot maps exact-old state to TLA+ fields:

| JSON field | Exact-old source | TLA+ state |
|---|---|---|
| `term`, `vote_node`, `vote_committed` | `Engine.state.vote` | `currentTerm`, `voteFor`, `voteCommitted` |
| `role` | `Engine.state.server_state` | `role` |
| `last_log`, `logs[]` | `RaftState::last_log_id/get_log_id` | `lastLog`, `logTerm` |
| `committed` | `RaftState.committed` | `committed` |
| `*_mem_index`, `*_mem_term`, `*_configs` | `MembershipState` and `Membership::get_joint_config` | committed/effective membership variables |

`Nil`/`None` indices are encoded as `-1`. Node ids are JSON strings so the trace configuration can use a finite string server domain. Helper events capture every argument and result used by their pure relation. Timestamps come from `SystemTime::now()` and every line is flushed under a process-local mutex.

## 2. Action-to-code mapping

### Elect

- **Spec action**: `StartElection`
- **Code**: `openraft/src/engine/engine_impl.rs:107-139` after instrumentation
- **Trigger**: capture immediately on entry; emit after the single-node return path or after the multi-node candidate path
- **Fields**: full Engine pre/post snapshots
- **Evidence boundary**: exact synchronous `Engine::elect` state transition

### LeaderAppend

- **Spec action**: `LeaderAppendEntries`
- **Code**: `openraft/src/engine/engine_impl.rs:245-294` after instrumentation
- **Trigger**: capture before the empty check; emit after log id assignment, effective-membership update, fast commit decision, and command queuing
- **Fields**: full pre/post; `args.count`; membership position within the appended batch or `-1`
- **Notes**: empty input intentionally emits nothing because the implementation performs no transition.

### FollowerCommit

- **Spec action**: `FollowerCommitEntries`
- **Code**: `openraft/src/engine/engine_impl.rs:365-407` after instrumentation
- **Trigger**: capture on function entry; emit after the min/max commit cap and membership promotion
- **Fields**: full pre/post; leader commit, previous-log, and last-entry term/index pairs

### UpdateCommittedMembership

- **Spec action**: `UpdateCommittedMembership`
- **Code**: `openraft/src/engine/engine_impl.rs:575-622` after instrumentation
- **Trigger**: capture before comparisons; emit after committed/effective replacement and possible role change
- **Fields**: full pre/post plus incoming membership log term/index/config groups

### ProgressUpdate

- **Spec action**: `ProgressUpdateValue`
- **Code**: `openraft/src/progress/mod.rs:165-225` after instrumentation
- **Trigger**: capture vector and committed scalar immediately before `VecProgress::update`; emit at the equal-value return or normal return
- **Fields**: uniform quorum ids, target/value, all per-id pre/post values, pre/post committed scalar
- **Notes**: vector ordering is captured only to enumerate values; Trace.tla validates the externally meaningful id→value mapping and committed result.

### QuorumCheck

- **Spec relation**: `Quorum`
- **Code**: `openraft/src/membership/effective_membership.rs:152-157` after instrumentation
- **Trigger**: collect the iterator, evaluate the real joint quorum, then emit
- **Fields**: membership component groups, granted ids, boolean result

### GreatestMajority

- **Spec relation**: `ExpectedGreatest`
- **Code**: `openraft/src/membership/membership.rs:279-309` after instrumentation
- **Trigger**: emit after the real per-component order-statistic calculation
- **Fields**: membership component groups, complete value map, optional result (`None` → `-1`)

### ReplicationLagCheck

- **Spec relation**: saturating index-distance comparison
- **Code**: `openraft/src/core/replication_state.rs:53-69` after instrumentation
- **Trigger**: emit after `is_matched_upto_date` evaluates
- **Fields**: matched index, leader last index, configured threshold, boolean result

### Semantic MC-only actions

`SendAppendEntries`, `DeliverAppendEntries`, `RejectAppendConflict`, `HandleUpdateMatched`, `GrantVote`, `LoseMessage`, `Crash`, and `Recover` are modeled from the production call chains documented in `base.tla`. They are not directly traced by the selected short unit scenarios because doing so would mix uninstrumented storage/network activity into a trace. Their constituent progress/quorum/commit relations are traced above; this limitation is recorded as L2 action coverage rather than hidden with silent actions.

## 3. Special considerations

- Instrumentation is compiled into `/work/work-source` only and is inert unless both `SPECULA_TRACE` and `SPECULA_TRACE_FILE` are set.
- The harness runs each state-changing Engine fixture separately, so `TraceInit` can bootstrap from that fixture's real pre-state without synthetic setup events.
- Pure helper traces may contain multiple independent queries; those wrappers leave base protocol state unchanged.
- The isolated follower-commit unit fixture intentionally supplies entry arguments without populating `RaftState.log_ids`. Trace validation therefore checks the exact helper relation and post-state fields, while `CommitWithinLocalLog` remains an MC/full-handler invariant rather than a Trace.cfg initial-state invariant.
- The extra `Display` bounds exist only on crate-private generic helper methods needed to serialize test values. Production runtime behavior and public source interfaces are unchanged.
- No event or trace is hand-written. `harness/run.sh` removes the named outputs and regenerates all of them by running the instrumented tests.

---

# V1 instrumentation (updated revision aa05a38)

Patch: `harness/patches/instrumentation.patch` (rebased; V0 patch kept as `harness/patches/v0-instrumentation.patch`). Probe placement is by symbol; line numbers below refer to the uninstrumented updated source.

## Envelope and nesting

Every event now carries `depth` = number of enclosing traced Engine actions (`specula_trace::Scope`, RAII). Engine actions call other traced Engine actions in V1 (`leader_append_entries` -> `update_progress` / `update_effective_membership`; `update_progress` -> `VecProgress::update` -> `EffectiveMembership::is_quorum`), so `harness/preprocess_trace.py` keeps only `depth == 0` events. No event field is synthesized.

## Engine snapshot (mandatory V1 fields)

| JSON field | Source | TLA+ state | Trace.tla check |
|---|---|---|---|
| `has_leader` | `RaftState.leader.is_some()` | `leaderState[i]` | `EngineSnapshotMatchesNext` |
| `progress` `[{id,index,term}]` | `leader.progress.quorum_set().ids()` + `Progress::get` | `matchedIndex[i][id]`, `matchedTerm[i][id]` (all other ids Nil/0) | all Server ids compared |
| `progress_configs` | `leader.progress.quorum_set().membership.get_joint_config()` | `progressConfig[i]` | when `has_leader` |
| `vote_granted` | `leader.vote_granted_by` | `voteGranted[i]` | when `has_leader` |

V0 snapshot fields are unchanged.

## Events

| Event | Spec action | Code (updated revision) | Trigger | Args |
|---|---|---|---|---|
| `Elect` | `StartElection` | `engine/engine_impl.rs:99-128` | scope on entry; emit at both returns | `{}` |
| `HandleVoteResp` (new) | `HandleVoteResp` | `engine_impl.rs:163-226` (wrapper around the original body) | scope on entry; emit after the body | `target`, `cmp` (`resp.vote.cmp(&state.vote)`: lt/eq/gt), `resp_term`, `resp_node`, `resp_committed`, `granted` |
| `LeaderAppend` | `LeaderAppendEntries` | `engine_impl.rs:226-292` | scope before the empty check; emit after the cursor command | `count`, `membership_position` (effective index change - old last, or -1) |
| `UpdateProgress` (new) | `UpdateProgress` | `engine_impl.rs:617-647` (wrapper; includes the no-leader return) | scope on entry; emit after the body | `node`, `index`, `term` |
| `UpdateEffectiveMembership` (new) | `UpdateEffectiveMembership` | `engine_impl.rs:591-615` | scope on entry; emit at end | `index`, `term`, `configs` |
| `FollowerCommit` | `FollowerCommitEntries` | `engine_impl.rs:364-389` | scope on entry; emit after `update_committed` | unchanged V0 args |
| `UpdateCommittedMembership` | `UpdateCommittedMembership` | `engine_impl.rs:555-588` | unchanged | unchanged |
| `ProgressUpdate` | `ProgressUpdateValue` | `progress/mod.rs:163-205` | emit at unknown-id return (new), equal-value return, normal return | unchanged; values via `SpeculaValue` (u64 or LogId index) |
| `QuorumCheck`, `ReplicationLagCheck` | pure relations | unchanged | unchanged | unchanged |
| `GreatestMajority` | — | removed (`greatest_majority_value` deleted) | — | — |

## Not directly traced (unchanged limitation)

`SendAppendEntries`, `DeliverAppendEntries`, `RejectAppendConflict`, `HandleUpdateMatched`, `GrantVote`, `LoseMessage`, `Crash`, `Recover` are message/actor-level MC actions. Their Engine cores (`update_progress`, `follower_commit_entries`, `handle_vote_resp`) are traced. Per-entry membership payloads (`logConfig`) are not captured; Trace.tla places the snapshot's committed and effective membership at their log positions and never checks `logConfig`.
