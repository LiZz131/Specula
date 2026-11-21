# Instrumentation specification (rebased for the Pre-Vote update)

The V0 schema below is retained; the harness now runs on the updated tree (`update`, 3ab6cdd) and every event additionally carries the mandatory Pre-Vote fields of §4. Mandatory fields are enforced by `Trace.tla` `ASSUME EventFieldsPresent` and compared by `ValidatePre`/`ValidatePost`.

## 1. Trace event schema

The harness writes one NDJSON object per exact-old `Engine` invocation. The outer envelope is:

```json
{"tag":"trace","ts_unix_ns":"...","event":{"name":"...","nid":"1","pre":{},"post":{},"args":{}}}
```

`tag` is always `trace`; `ts_unix_ns` is a fresh wall-clock timestamp encoded as a string; `nid` and every node ID are strings matching the TLA+ `Server` domain. Each file currently contains one transition so its fixture pre-state is explicit rather than inferred from a previous scenario.

State field mapping:

| JSON field | Exact-old source observation | TLA+ state |
|---|---|---|
| `role` | `eng.state.server_state` | `role[nid]` |
| `vote.{term,node,committed}` | `eng.state.vote_ref()` | `vote[nid]` |
| `last_log` | `LogStateReader::last_log_id()` | `lastLog[nid]` |
| `committed_config`, `committed_config_index` | `membership_state.committed()` | `committedConfig`, `committedConfigIndex` |
| `effective_config`, `effective_config_index` | `membership_state.effective()` | `effectiveConfig`, `effectiveConfigIndex` |
| `candidate_active`, `candidate_vote`, `grants` | `candidate_ref()`, `vote_ref()`, `granters()` | `candidateActive`, `candidateVote`, `grants` |
| `candidate_config` | real frozen quorum set `candidate.progress().quorum_set().get_joint_config()` (V0 used effective membership as a proxy) | `candidateConfig` |
| `leader_active` | `leader_ref().is_some()` | `leaderActive` |
| `lease_valid` | `Leased::lease_info()` and `is_expired()` | `leaseValid` |
| `save_vote_pending` | queued `CommandName::SaveVote` | `votePersistPending` |
| `send_vote_pending` | queued `CommandName::SendVote` | `sendVotePending` |
| `append_pending` | queued `CommandName::AppendEntries` | `logFlushPending` |
| `seen_greater_log` | `Engine::is_there_greater_log()` (V0 emitted constant `false`) | `seenGreaterLog` |
| `crashed` | harness boundary metadata for a reconstructed engine before/after `startup()` | `crashed` |

Vote request arguments include `source`, request `vote`, `last_log`, `transfer`, and the returned `response_vote`/`response_granted`. Vote response arguments include `source`, `vote`, `last_log`, and `granted`. Membership append arguments include `target_config`.

## 2. Action-to-code mapping

| Spec action | Exact-old code location and trigger | Harness event / status |
|---|---|---|
| `StartElection` | `openraft/src/engine/engine_impl.rs:217-253`, snapshot around `elect()` or `elect_by_leadership_transfer()` | `StartElection`; collected for timer/external form |
| `PersistVote` | `openraft/src/core/raft_core.rs:2138-2166`, completion of awaited `SaveVote` | represented by pending command boundary; no standalone V0 trace |
| `SendVoteRequest`, `FinishVoteBroadcast` | `openraft/src/core/raft_core.rs:1360-1428,2203-2205`, runtime dispatch of queued `SendVote` | represented by `send_vote_pending`; no standalone V0 trace |
| `HandleVoteRequest` | `openraft/src/engine/engine_impl.rs:273-326`, snapshot immediately around `handle_vote_req()` | `HandleVoteRequest`; stale-log rejection and greater-vote grant collected |
| `HandleVoteResponse` | `openraft/src/engine/engine_impl.rs:330-389`, snapshot immediately around `handle_vote_resp()` | `HandleVoteResponse`; exact quorum establishment collected |
| `AppendJointConfig`, `AppendUniformConfig` | `openraft/src/engine/handler/leader_handler/mod.rs:56-109` and membership append in `raft_state/membership_state/mod.rs:183-203` | `AppendJointConfig` collected; uniform phase model-checked but not traced |
| `CommitMembership` | `openraft/src/raft_state/mod.rs:333-353` and `membership_state/mod.rs:121-147`, snapshot around `update_local_committed()` | `CommitMembership`; collected |
| `RefreshServerState` | `openraft/src/engine/handler/server_state_handler/mod.rs`, after committed membership changes | state effect represented; no standalone V0 trace |
| `FlushLog` | runtime storage completion for queued `AppendEntries` | represented by `append_pending`; no standalone V0 trace |
| `SendAppendEntries`, `HandleAppendEntries` | runtime replication dispatch and `engine_impl.rs` append handling | modeled and model-checked; no standalone V0 trace |
| `ExpireLease` | time-dependent `Leased::is_expired()` guard in `engine_impl.rs:285-300` | captured as `lease_valid`; no standalone V0 trace |
| `DropMessage` | environment/network loss, not an implementation call | model-checking only |
| `Crash` | process failure boundary, not an `Engine` method | pre-restart boundary metadata only |
| `Restart` | `openraft/src/engine/engine_impl.rs:136-181`, snapshot immediately around `startup()` on reconstructed durable state | `Restart`; follower reconstruction collected |

## 3. Special considerations

- Instrumentation exists only under `#[cfg(test)]` and changes no production code path.
- Each scenario runs in its own test process and output file, so append-only `OpenOptions` does not require a cross-thread writer lock. The harness runner deletes only its named generated trace files before a fresh batch.
- Engine commands describe submitted work, not completed durability. The trace therefore records `SaveVote` and `AppendEntries` as pending flags. `Trace.tla` initializes durable shadows from each explicit pre-state and checks the projected transition at this atomic boundary.
- `candidate_config` is captured through the effective membership because the exact-old candidate quorum field is private. Every candidate trace freezes that same config and performs no intervening membership mutation. The TLA+ state keeps the frozen copy independently after initialization.
- The restart pre-state uses `crashed=true` as boundary metadata; exact-old `Engine` itself has no crashed field. The post-state is the direct result of `startup()`.
- `ServerState::Shutdown` is outside the bound and is conservatively serialized as `Follower`; no current harness scenario enters it.



## 4. Update instrumentation (Pre-Vote)

### 4.1 New mandatory state fields (pre and post of every event)

| JSON field | Updated-source observation | TLA+ state |
|---|---|---|
| `pre_candidate_active` | `eng.pre_candidate_ref().is_some()` (engine_impl.rs:340-342) | `preCandidateActive` |
| `pre_candidate_vote` | `pre_candidate.vote_ref()` (falls back to local vote when absent) | `preCandidateVote` (checked when active) |
| `pre_candidate_config` | `pre_candidate.progress().quorum_set().get_joint_config()` | `preCandidateConfig` (checked when active) |
| `pre_grants` | `pre_candidate.granters()` | `preGrants` (checked when active) |
| `send_pre_vote_pending` | queued `CommandName::SendPreVote` | compared at `PreElect` with the PreVoteReq messages dispatched in that step |

### 4.2 New / changed events

| Event | Code location and trigger | Args | Trace wrapper |
|---|---|---|---|
| `PreElect` | around `Engine::pre_elect()` (engine_impl.rs:298-322), as invoked by `ExternalCommand::Elect{pre_vote:true}` / the tick | `req_vote`, `req_last_log` from the queued `SendPreVote` | `TracePreElect` → `ExternalPreElect`; `PreVoteRequestsMatch` checks vote, last log and target set |
| `HandlePreVoteRequest` | around `Engine::handle_pre_vote_req()` (:414-447); harness asserts no command is queued | `source`, `vote`, `last_log`, `response_vote`, `response_last_log`, `response_granted` | `TraceHandlePreVoteRequest`; response vote = unchanged local vote; PreVoteResp message fields |
| `HandlePreVoteResponse` | around `Engine::handle_pre_vote_resp()` (:516-554), delivered only when RaftCore's filter would deliver it (raft_core.rs:1803-1820) | `source`, `candidate_vote`, `response_vote`, `last_log`, `granted` | `TraceHandlePreVoteResponse` |
| `HandleAppendEntries` | around `Engine::append_entries()` with an empty segment (:586-602) | `source`, `vote` | `TraceHandleAppendEntries` |
| `RunCommands` | the harness hands queued commands to the runtime boundary between engine events (RaftCore::run_engine_commands, raft_core.rs:1110-1160) | `commands` (names) | silent `PersistVote`/`FlushLog`/`SendVoteRequest`/`FinishVoteBroadcast` restricted to the named commands, then post-state equality |

`RunCommands` is a harness-emulated runtime boundary: the engine transitions are
real; the completion of storage/network commands is represented by the model's
own completion Actions and checked only through the next recorded engine state.

### 4.3 Action coverage by fresh traces

| Spec action | Fresh trace(s) |
|---|---|
| `PreElect` (multi-voter / single-voter self-quorum) | `pre_elect_multi`, `pre_elect_single`, and the multi-event traces |
| `HandlePreVoteRequest` grant / lease reject / log reject / vote-order reject | `pre_vote_req_grant`, `pre_vote_req_reject_lease`, `pre_vote_req_reject_log`, `pre_vote_req_reject_vote` |
| `HandlePreVoteResponse` win → `DoElect` / greater-log reject / joint no-quorum tally | `pre_vote_resp_quorum_elect`, `pre_vote_resp_reject_greater_log`, `pre_vote_resp_joint_no_quorum`, `stale_pre_vote_after_establish` |
| become_following clears pre-candidate (vote grant / heartbeat) | `vote_grant_cancels_pre_vote`, `heartbeat_cancels_pre_vote` |
| `HandleVoteResponse` win with a live pre-candidate (U1 interaction) | `stale_pre_vote_after_establish` |
| `TickElect` pre-vote branch (runtime tick guards) | not traced (runtime-level); covered by model checking and by the upstream `tests/tests/elect/t12_pre_vote.rs` integration tests (8/8 pass) |
