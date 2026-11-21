# Instrumentation points changed in V1

- `openraft/src/engine/mod.rs`: `mod specula_trace_test;` (test-only).
- `openraft/src/engine/tests/specula_trace_test.rs` (from `harness/src/`):
  - `state_json`: + `pre_candidate_active/vote/last_log/config`, `pre_grants`,
    `send_pre_vote_pending`; `seen_greater_log` = `Engine.seen_greater_log`.
  - event drivers `ev_pre_elect`, `ev_pre_vote_req`, `ev_pre_vote_resp`
    (applies RaftCore's `does_pre_candidate_vote_match` rule before calling the
    engine), `ev_append`, plus shared `ev_elect`, `ev_vote_req`, `ev_vote_resp`.
  - `observe()` writes `<trace>.observation.json`.

Rebuild/rerun: `harness/run.sh` (applies the patch if needed, builds with
`cargo test -p openraft --lib --no-run`, runs each
`engine::tests::specula_trace_test::specula_trace_<case>` with
`SPECULA_TRACE_PATH`).
