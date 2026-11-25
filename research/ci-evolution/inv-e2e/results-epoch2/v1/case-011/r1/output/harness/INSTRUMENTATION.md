# Instrumentation changes (incremental)

Only `openraft/src/engine/tests/specula_trace_test.rs` (test-only, `#[cfg(test)]`)
and one line in `openraft/src/engine/mod.rs` are added. No production code changes.

Changed/added probes (see `instrumentation-spec.md` §4):
* `state_json`: `pre_candidate_*`, `pre_grants`, real frozen `candidate_config`
  and `pre_candidate_config` (`Candidate::progress().quorum_set()`),
  `send_pre_vote_pending`, `append_behind_vote` (FIFO order of queued
  SaveVote/AppendEntries), `seen_greater_log` from `Engine::is_there_greater_log`.
* `step()`: multi-event capture; records `send_pre_vote` / `send_vote` command
  payloads; drains the output afterwards (runtime executes commands).
* events `PreElect`, `HandlePreVoteRequest`, `HandlePreVoteResponse`,
  `HandleAppendEntries` (around `Engine::pre_elect`, `handle_pre_vote_req`,
  `handle_pre_vote_resp`, `append_entries`).

Rebuild/rerun: `harness/run.sh`; validate: `harness/validate-traces.sh`.
