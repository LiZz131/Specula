# Instrumentation guide (changed points only)

Location after `apply-instrumentation.sh`: `artifact/openraft/src/engine/tests/specula_trace_test.rs`.

## Changed / added capture points

| Event | Real entry point | Capture | Notes |
|---|---|---|---|
| `PreElect` | `Engine::pre_elect` (engine_impl.rs:297-322); `by_timer=true` first calls `Engine::reset_greater_log` as `handle_tick_election` does (raft_core.rs:2027-2031) | pre/post `state_json`, queued `Command::SendPreVote` contents | `send_pre_vote_pending`, `send_pre_vote_req` validated by `TracePreElect` |
| `HandlePreVoteRequest` | `Engine::handle_pre_vote_req` (engine_impl.rs:414-447) | pre/post state, response vote/last log/granted, number of commands emitted | the RaftCore wraps it in an immediate `Respond` (raft_core.rs:1551-1562) |
| `HandlePreVoteResponse` | `Engine::handle_pre_vote_resp` (engine_impl.rs:516-554) | pre/post state, probed `candidate_vote`, response granted/last log | the harness delivers only responses that pass RaftCore's leader-id correlation (raft_core.rs:1815-1816) |
| `HandleAppendEntries` | `Engine::append_entries` with an empty segment at the local last log (engine_impl.rs:586-600) | pre/post state | exercises the vote update / `become_following` path |
| all | `state_json` | new fields `pre_candidate_active`, `pre_candidate_vote`, `pre_candidate_config` (real frozen quorum set via `progress().quorum_set()`), `pre_grants`, `send_pre_vote_pending`; `candidate_config` is now the real frozen quorum set; `seen_greater_log` is now `Engine::is_there_greater_log()` (was a constant) | |

Multi-event traces drain the queued commands between events (`drain`), as RaftCore
does after every event; `Trace.tla` replays the corresponding runtime completions
(`PersistVote`, `FlushLog`, vote-request sends, lease expiry) only when the next
event's recorded `pre` state shows them, then checks the full pre-state.

## How to change

- New field: add it to `state_json` (and to `StateMatches` in `spec/Trace.tla`).
- New event: add an `ev_*` helper calling one engine entry point, a `#[test]` scenario,
  its name in `run.sh`, and a wrapper + CASE arm in `spec/Trace.tla`.
- Rebuild/rerun: `bash harness/run.sh && bash harness/validate-traces.sh`.
