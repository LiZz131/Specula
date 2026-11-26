# Instrumentation specification

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
| `candidate_config` | effective config at candidate construction in these non-mutating election fixtures | `candidateConfig` |
| `leader_active` | `leader_ref().is_some()` | `leaderActive` |
| `lease_valid` | `Leased::lease_info()` and `is_expired()` | `leaseValid` |
| `save_vote_pending` | queued `CommandName::SaveVote` | `votePersistPending` |
| `send_vote_pending` | queued `CommandName::SendVote` | `sendVotePending` |
| `append_pending` | queued `CommandName::AppendEntries` | `logFlushPending` |
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


---

## 4. Update (Pre-Vote revision) — rebased instrumentation

Harness: `harness/src/specular_trace_test.rs` (patch `harness/instrumentation.patch`, applied to a copy `work-source/` of `artifact/`). Env var renamed `SPECULA_TRACE_PATH` → `SPECULAR_TRACE_PATH`; `Trace.tla` reads `SPECULAR_TRACE` (fallback `JSON`).

### 4.1 New/changed state fields (all events, pre and post)

| JSON field | Source observation | TLA+ state | Trace check |
|---|---|---|---|
| `pre_candidate_active` | `eng.pre_candidate_ref().is_some()` | `preCandidateActive[nid]` | always compared |
| `pre_candidate_vote` | `pre_candidate.vote_ref()` (placeholder = current vote when inactive) | `preCandidateVote` | compared when active |
| `pre_candidate_config` | effective config at round creation (frozen quorum is private; no scenario mutates membership during a round) | `preCandidateConfig` | compared when active |
| `pre_grants` | `pre_candidate.granters()` | `preGrants` | compared when active |
| `send_pre_vote_pending` | queued `CommandName::SendPreVote` | new `PreVoteReq` messages from `nid` in this step | equality (both directions) |
| `send_pre_vote_req.{vote,last_log}` | the queued `Command::SendPreVote { vote_req }` | one `PreVoteReq` per effective voter ≠ nid | ⊆ `messages'` when pending |
| `leader_vote` | `leader_ref().committed_vote_ref()` (placeholder = vote) | `leaderVote[nid]` | compared when `leader_active` |
| `seen_greater_log` | `Engine::is_there_greater_log()` (prior hard-coded `false`) | `seenGreaterLog[nid]` | always compared |

### 4.2 New events

| Event | Code and trigger | Spec action | args |
|---|---|---|---|
| `PreElect` | `engine_impl.rs: pre_elect`; `trigger:"tick"` = `reset_greater_log()` + `pre_elect()` as in `raft_core.rs: handle_tick_election`; `trigger:"external"` = `ExternalCommand::Elect{pre_vote:true}` | `TickPreElect` / `ExternalPreElect` | `trigger` |
| `HandlePreVoteRequest` | `engine_impl.rs: handle_pre_vote_req` (runtime replies `when: None`) | `HandlePreVoteRequest` | `source, vote, last_log, response_vote, response_last_log, response_granted` |
| `HandlePreVoteResponse` | runtime gate `does_pre_candidate_vote_match` (evaluated by the harness on the same engine) then `handle_pre_vote_resp` | `HandlePreVoteResponse` | `source, candidate_vote, vote, last_log, granted, forwarded` |
| `RuntimeDrain` | harness emulation of `RaftCore::run_command` for the queued commands (SaveVote/AppendEntries complete, SendVote/SendPreVote dispatched); the self `VoteResponse` sent after `save_vote` is a separate `HandleVoteResponse` event, as in `raft_core.rs` | silent `PersistVote`, `SendVoteRequest`, `FinishVoteBroadcast`, `FlushLog`, then post-state comparison | `commands` |

### 4.3 Multi-event traces
Each later event's `pre` must equal the model state (`ValidatePre`), except `RuntimeDrain`, whose pre-state is tied to the previous post by the `TraceContinuity` assumption. Silent runtime steps are enabled only during a `RuntimeDrain` event and only for its node.

### 4.4 Not observed by traces (validated by source review and MC only)
Tick guards (`role /= Leader`, lease expiry, voter count, in-flight-round restart timer), real network dispatch of `SendPreVote`, the runtime gate as executed inside `RaftCore` (the harness evaluates the same predicate on the engine), `ExpireLease`, `DropMessage`, `Crash`.
