# Instrumentation specification (update revision)

Rebased from the V0 specification. The harness is test-only
(`openraft/src/engine/tests/specular_trace_test.rs`, applied by
`harness/instrumentation.patch`) and drives the real `Engine` of the updated
source. Each scenario is one test process writing one NDJSON file.

## 1. Trace event schema

```json
{"tag":"trace","ts_unix_ns":"...","event":{"name":"...","nid":"1","pre":{},"post":{},"args":{}}}
```

All events of one file come from the same `Engine` (`nid` constant). `pre` of
the first event initializes `Trace.tla`; every event's `post` is compared by
`ValidatePost`.

State fields (all mandatory, all compared by `Trace.tla:ValidatePost` unless noted):

| JSON field | Source observation | TLA+ state |
|---|---|---|
| `role` | `eng.state.server_state` (`Shutdown` → `Follower`, unused) | `role[nid]` |
| `vote.{term,node,committed}` | `eng.state.vote_ref()` | `vote[nid]` |
| `last_log` | `last_log_id()`; `None` → `present=false` with node = `nid` | `lastLog[nid]` |
| `committed_config(_index)`, `effective_config(_index)` | `membership_state.{committed,effective}()` | config vars |
| `lease_valid` | `Leased::lease_info()` and `!is_expired(now, 0)` and non-zero lease | `leaseValid` |
| `candidate_active`, `candidate_vote`, `grants` | `candidate_ref()`, `vote_ref()`, `granters()` | candidate vars (compared when active) |
| `candidate_config` | **real frozen quorum set** `candidate.progress().quorum_set()` (V0: effective config) | `candidateConfig` (when active) |
| `leader_active` | `leader_ref().is_some()` | `leaderActive` |
| `save_vote_pending`, `send_vote_pending`, `append_pending` | queued `SaveVote`, `SendVote`, `AppendEntries` | `votePersistPending`, `sendVotePending`, `logFlushPending` |
| `seen_greater_log` | **real** `Engine.seen_greater_log` (V0: constant false) | `seenGreaterLog` |
| `crashed` | harness boundary metadata (restart pre-state; caught `grant_by` panic) | `crashed` |
| `pre_candidate_active` | `pre_candidate_ref().is_some()` | `preCandidateActive` |
| `pre_candidate_vote` | `pre_candidate.vote_ref()` | `preCandidateVote` (when active) |
| `pre_candidate_config` | `pre_candidate.progress().quorum_set()` | `preCandidateConfig` (when active) |
| `pre_candidate_last_log` | `pre_candidate.last_log_id()` | `preCandidateLastLog` (when active) |
| `pre_grants` | `pre_candidate.granters()` | `preGrants` (when active) |
| `send_pre_vote_pending` | queued `CommandName::SendPreVote` | `sendPreVotePending` |

Ghost model variables `preRound`, `preByTimer` and message field `round` have no
implementation counterpart and are not traced.

## 2. Action-to-code mapping

| Spec action | Code location / trigger | Event (args) |
|---|---|---|
| `DoElect` (`StartElection` wrapper) | `engine_impl.rs:249-290` `elect()` | `StartElection` (`transfer`) |
| `PreElect` | `engine_impl.rs:298-322` `pre_elect()` | `PreElect` |
| `SendPreVoteRequests` | `raft_core.rs:2342-2344,1385-1478`: harness drains the queued `SendPreVote` | `SendPreVoteRequests` (`vote`, `last_log`, `targets`) — request content and targets are compared |
| `HandlePreVoteRequest` | `engine_impl.rs:414-446` `handle_pre_vote_req()` | `HandlePreVoteRequest` (`source`, `vote`, `last_log`, `response_vote`, `response_last_log`, `response_granted`) |
| `HandlePreVoteResponse` | `engine_impl.rs:516-554` `handle_pre_vote_resp()` as forwarded by `raft_core.rs:1803-1820` | `HandlePreVoteResponse` (`source`, `candidate_vote`, `response_vote`, `last_log`, `granted`); a caught `grant_by` panic is recorded with post `crashed=true` |
| `PersistVote` | `raft_core.rs:2274-2300`: harness completes the queued `SaveVote` | `PersistVote` |
| `SendVoteRequest`, `FinishVoteBroadcast` | `raft_core.rs:2339-2341`: one event per spawned target, then completion | `SendVoteRequest` (`target`), `FinishVoteBroadcast` |
| `HandleVoteRequest` | `engine_impl.rs:350-401` | `HandleVoteRequest` (as V0 + `response_last_log`) |
| `HandleVoteResponse` | `engine_impl.rs:449-513` (+ `establish_leader` `:855-880`) | `HandleVoteResponse` |
| `HandleAppendEntries` | `engine_impl.rs:586-600` `append_entries()` with an empty segment at the local last log | `HandleAppendEntries` (`source`, `vote`, `last_log`) |
| `ExpireLease` | time boundary: `Leased::disable_lease()` | `ExpireLease` |
| `FlushLog` | runtime executes queued log append and its flush callback | `FlushLog` |
| `AppendJointConfig`, `AppendUniformConfig` | `LeaderHandler::leader_append_entries` with a membership entry | `AppendJointConfig` (`target_config`), `AppendUniformConfig` |
| `CommitMembership` | `RaftState::update_local_committed` | `CommitMembership` |
| `Restart` | `engine_impl.rs:166-210` `startup()` on reconstructed state | `Restart` |
| `TickElect` / `ExternalPreElect` / `ExternalElect` | RaftCore callers (`raft_core.rs:1959-2036,1683-1693`) | not traced (runtime timing); their engine effect is `PreElect`/`StartElection` |
| `Crash`, `DropMessage`, `RefreshServerState` | environment / not exercised | MC only |

## 3. Special considerations

- Runtime command boundaries (`PersistVote`, `SendVoteRequest`,
  `FinishVoteBroadcast`, `SendPreVoteRequests`, `FlushLog`) are executed by the
  harness exactly where `RaftCore::run_command` executes them (after the engine
  event, before the next event); other queued commands are kept.
- `HandlePreVoteResponse` at the engine boundary has no round identity; the
  RaftCore leader-id filter (`does_pre_candidate_vote_match`) is not reachable
  from an engine test and is exercised by the integration reproduction in
  `harness/repro/`.
- Field non-vacuity: `harness/field-mutation-check.sh` mutates one field per
  mutant; all 20 mutants are rejected by TLC
  (`spec/output/trace-mutations/summary.txt`).
