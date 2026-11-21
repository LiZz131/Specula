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

# Update: Pre-Vote revision (incremental run)

## U1. Changed / added trace fields

State fields (captured in every `pre`/`post`, compared by `StateMatches` in `Trace.tla`, both before
(`ValidatePre`) and after (`ValidatePost`) each event):

| JSON field | Source observation | TLA+ state |
|---|---|---|
| `pre_candidate_active` | `eng.pre_candidate_ref().is_some()` | `preCandidateActive` |
| `pre_candidate_vote` | `pre_candidate.vote_ref()` | `preCandidateVote` (checked when active) |
| `pre_candidate_config` | `pre_candidate.progress().quorum_set().get_joint_config()` (real frozen quorum set) | `preCandidateConfig` (checked when active) |
| `pre_grants` | `pre_candidate.granters()` | `preGrants` (checked when active) |
| `send_pre_vote_pending` | queued `CommandName::SendPreVote` | checked by `TracePreElect` against the emitted `PreVoteReq` set |
| `candidate_config` | **now** `candidate.progress().quorum_set().get_joint_config()` (was the effective config proxy) | `candidateConfig` |
| `seen_greater_log` | **now** `Engine::is_there_greater_log()` (was the constant `false`) | `seenGreaterLog` |

## U2. Action-to-code mapping (new/changed events)

| Spec action | Code location and trigger | Event | Fields |
|---|---|---|---|
| `TickPreElect` / `ExternalPreElect` (`PreElect`) | `openraft/src/engine/engine_impl.rs:297-322` `Engine::pre_elect`; timer form preceded by `reset_greater_log()` exactly as `raft_core.rs:2027-2031` | `PreElect` | `by_timer`, `send_pre_vote_req{vote,last_log}` (queued command) |
| `HandlePreVoteRequest` | `engine_impl.rs:414-447` `Engine::handle_pre_vote_req`, snapshot around the call | `HandlePreVoteRequest` | `source`, `vote`, `last_log`, `response_vote`, `response_last_log`, `response_granted`, `commands_emitted` |
| `HandlePreVoteResponse` | `engine_impl.rs:516-554` `Engine::handle_pre_vote_resp`, delivered only when the RaftCore correlation (`raft_core.rs:1815-1816`) would pass | `HandlePreVoteResponse` | `source`, `candidate_vote` (probe), `vote` (responder vote; not read by the engine), `last_log`, `granted` |
| `HandleAppendEntries` | `engine_impl.rs` `Engine::append_entries` with an empty segment at the local last log | `HandleAppendEntries` | `source`, `vote`, `prev_log`, `accepted` |
| `ElectEffects` via quorum | inside `handle_pre_vote_resp` → `elect()` | (post-state of `HandlePreVoteResponse`) | |
| runtime completions | `RaftCore::run_engine_commands` between events (harness `drain`) | silent `TraceRuntimeDrain`, gated by the next event's `pre` | `PersistVote`, `FlushLog`, vote-request sends, `ExpireLease` |
| inbound Pre-Vote messages | sent by untraced peers | silent `TraceInjectInbound` immediately before the consuming event | |

## U3. Special considerations

- `preCandidateByTimer` and the message `round`/`preRound` are model history only; they are not
  observable in the implementation and are not trace-checked.
- Engine-level traces cannot observe RaftCore's leader-id correlation (`does_pre_candidate_vote_match`);
  the harness applies the same rule before delivering a response. The correlation itself is
  covered by code review and by the model (`HandlePreVoteResponse` ~correlated branch).
- `ExpireLease` between events is real elapsed time (scenario `prevote_round_reuses_probe` uses a
  20 ms leader lease and sleeps 100 ms).
