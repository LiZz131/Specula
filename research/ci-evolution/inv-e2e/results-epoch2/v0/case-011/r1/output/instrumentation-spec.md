# Instrumentation specification

## 1. Trace event schema

The harness writes one NDJSON object per `Engine` invocation of the updated revision (`artifact/` at `3ab6cdd`). A file may contain several events of one Engine (multi-event update scenarios); only the first event's `pre` seeds the replay and every event's `post` is checked. The outer envelope is:

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
| `candidate_config` | frozen quorum set of the live Candidate (`progress().quorum_set().get_joint_config()`); effective config when no candidate | `candidateConfig` |
| `pre_candidate_active`, `pre_candidate_vote`, `pre_grants` (update) | `pre_candidate_ref()`, its `vote_ref()`, `granters()` | `preCandidateActive`, `preCandidateVote`, `preGrants` |
| `pre_candidate_config` (update) | frozen quorum set of the Pre-Vote tracker | `preCandidateConfig` |
| `send_pre_vote_pending` (update) | queued `CommandName::SendPreVote` | emitted `PreVoteReq` messages of the node |
| `seen_greater_log` | `Engine::seen_greater_log` (V0 hard-coded `false`) | `seenGreaterLog` |
| `leader_active` | `leader_ref().is_some()` | `leaderActive` |
| `lease_valid` | `Leased::lease_info()` and `is_expired()` | `leaseValid` |
| `save_vote_pending` | queued `CommandName::SaveVote` | `votePersistPending` |
| `send_vote_pending` | queued `CommandName::SendVote` | `sendVotePending` |
| `append_pending` | queued `CommandName::AppendEntries` | `logFlushPending` |
| `crashed` | harness boundary metadata for a reconstructed engine before/after `startup()` | `crashed` |

Vote request arguments include `source`, request `vote`, `last_log`, `transfer`, and the returned `response_vote`/`response_granted`. `PreElect` arguments (update): `request_present`, `request_vote`, `request_last_log` (from the queued `Command::SendPreVote`) and `request_targets` (effective voters minus self, as `spawn_parallel_vote_requests` computes them at dispatch). `HandlePreVoteRequest` arguments (update): `source`, `vote`, `last_log`, `response_vote`, `response_last_log`, `response_granted`. `HandlePreVoteResponse` arguments (update): `source`, `candidate_vote` (the request vote RaftCore attaches to `Notification::PreVoteResponse`), `last_log`, `granted`. The responder's own `VoteResponse.vote` is not consumed by `handle_pre_vote_resp` and is therefore not traced on the requester side. Vote response arguments include `source`, `vote`, `last_log`, and `granted`. Membership append arguments include `target_config`.

## 2. Action-to-code mapping

| Spec action | Exact-old code location and trigger | Harness event / status |
|---|---|---|
| `StartElection` | `openraft/src/engine/engine_impl.rs:217-253`, snapshot around `elect()` or `elect_by_leadership_transfer()` | `StartElection`; collected for timer/external form |
| `PreElect` (update) | `openraft/src/engine/engine_impl.rs:291-322`, snapshot around `pre_elect()`; shared by the timer (`raft_core.rs:2029-2031`) and `ExternalCommand::Elect { pre_vote: true }` (`raft_core.rs:1683-1695`) | `PreElect`; multi-voter, single-voter, Candidate, joint-config cases collected |
| `HandlePreVoteRequest` (update) | `engine_impl.rs:406-447` via `raft_core.rs:1551-1562`, snapshot around `handle_pre_vote_req()` | `HandlePreVoteRequest`; lease, log, vote rejections and grant collected |
| `HandlePreVoteResponse` (update) | `engine_impl.rs:511-554` after RaftCore's filter `raft_core.rs:1803-1820,2066-2090`, snapshot around `handle_pre_vote_resp()` | `HandlePreVoteResponse`; reject with greater log, grant without quorum, quorum -> `elect()` (follower and Leader), no-tracker cases collected |
| `TickElect`, `TickPreElect` (update) | `raft_core.rs:1959-2036` timer guards | runtime-level guards are not traced (time abstraction); their engine effect is `StartElection`/`PreElect` |
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


## 4. Update scenarios and observed effects (incremental run)

| Trace file | Events | Affected / interaction Actions | Effect compared by Trace.tla |
|---|---|---|---|
| `pre_elect` | PreElect | PreElect | tracker vote/config/grants, vote/role unchanged, request vote/log/targets |
| `pre_elect_single_voter` | PreElect | PreElect -> DoElect | Candidate role, new vote, tracker absent, no request |
| `pre_vote_req_lease_reject` / `_log_reject` / `_vote_reject` / `_grant` | HandlePreVoteRequest | HandlePreVoteRequest | response granted bit and last log, responder vote returned, responder state unchanged |
| `pre_vote_round` | PreElect, HandlePreVoteResponse x2 | PreElect, HandlePreVoteResponse | greater-log hint, partial grants, quorum -> election (vote, role, candidate, tracker cleared) |
| `pre_vote_stale_resp` | HandlePreVoteResponse | HandlePreVoteResponse (no tracker) | no state change |
| `vote_req_cancels_pre_vote` | PreElect, HandleVoteRequest | HandleVoteRequest (become_following) | tracker cleared, vote/role/reply |
| `elect_cancels_pre_vote` | PreElect, StartElection | DoElect | tracker cleared |
| `candidate_pre_round_survives_leadership` | PreElect, HandleVoteResponse | PreElect on Candidate, establishment | tracker kept on the new Leader, leader lease installed |
| `leader_pre_vote_win` | HandlePreVoteResponse | HandlePreVoteResponse at a Leader | Leader -> Candidate at term+1, leader object retained |
| `restart_drops_pre_round` | Restart | Restart | tracker lost across crash/restart |
| `pre_vote_joint_config` | PreElect, HandlePreVoteResponse x2 | PreElect, HandlePreVoteResponse | frozen joint config, no quorum with one component, quorum with both |

Not traced (environment/time limitations, as in V0): runtime timer guards, network
dispatch/drop, IO completion (`PersistVote`, `FlushLog`), AppendEntries receipt,
membership-driven `RefreshServerState`.
