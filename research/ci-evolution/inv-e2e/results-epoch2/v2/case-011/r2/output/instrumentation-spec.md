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

## 4. Incremental update (Pre-Vote), run incr-4e410cd184be

Harness: `harness/instrumentation.patch` (rebased; test-only module
`openraft/src/engine/tests/specular_trace_test.rs`, registered in
`openraft/src/engine/mod.rs`). Env var renamed `SPECULA_TRACE_PATH` ->
`SPECULAR_TRACE_PATH`; Trace.tla reads `SPECULAR_TRACE` (or `JSON`).
A file may now hold several events of one focus node; between events the
harness drains queued commands (stand-in for RaftCore executing them) and the
Trace spec matches the runtime completions with silent steps guarded by the
next event's captured pre-state; `ValidatePre` compares every event's pre-state.

### New/changed state fields (captured in `pre` and `post`)

| JSON field | Source observation | TLA+ state | Check |
|---|---|---|---|
| `pre_candidate_active` | `Engine::pre_candidate_ref().is_some()` | `preCandidateActive` | always |
| `pre_candidate_vote` | `pre_candidate.vote_ref()` | `preCandidateVote` | when active |
| `pre_candidate_config` | effective membership (frozen quorum set is private; no scenario changes membership after `pre_elect`) | `preCandidateConfig` | when active |
| `pre_grants` | `pre_candidate.granters()` | `preGrants` | when active |
| `send_pre_vote_pending`, `send_pre_vote_req{present,vote,last_log}` | queued `Command::SendPreVote { vote_req }` | PreVoteReq messages to every other frozen voter with that vote/last log | `PreVoteRequestsIssued`; `PreElect` requires pending ⇔ round created |
| `seen_greater_log` | `Engine::is_there_greater_log()` (was hard-coded `false` in V0) | `seenGreaterLog` | always |

### New events

| Event | Code / trigger point | Args | Spec wrapper |
|---|---|---|---|
| `PreElect` | around `Engine::pre_elect()` (engine_impl.rs:297-322); `caller = "tick"` performs the tick's engine calls `reset_greater_log(); pre_elect()` after asserting its guards (raft_core.rs:1959-2031); `caller = "external"` = ExternalCommand::Elect{pre_vote:true} | `caller` | `TickPreElect` / `ExternalPreElect` |
| `HandlePreVoteRequest` | around `Engine::handle_pre_vote_req()` (413-447) | `source, vote, last_log, response_vote, response_last_log, response_granted` | `HandlePreVoteRequest` + `PreVoteResponseMatches` |
| `HandlePreVoteResponse` | around `Engine::handle_pre_vote_resp()` (515-554), called only when the RaftCore gate would pass (raft_core.rs:1803-1820, 2067-2090) or when no round exists | `source, vote, last_log, granted, req_vote` | `HandlePreVoteResponse` |
| `StartElection` | as before; `caller` added | `transfer, caller` | `TickElect` / `ExternalElect` / `StartTransferElection` |
| `HandleVoteResponse` (self-grant) | the runtime's local grant after `save_vote` (raft_core.rs:2290-2302) replayed as the same Engine call | `source = self` | `HandleVoteResponse` |

### Silent runtime completions (Trace.tla)

`SilentPersistVote`, `SilentSendVote`, `SilentFlushLog`: enabled only on the
focus node, only before an unconsumed event (cursor >= 2), and only when that
event's captured pre-state shows the corresponding queued command gone.
