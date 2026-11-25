# Instrumentation guide (changed points only)

- Trace module: `openraft/src/engine/tests/specular_trace_test.rs` (source of
  truth: `harness/src/specular_trace_test.rs`; regenerate the patch with
  `git add -N … && git diff > harness/instrumentation.patch` in `work-source/`).
- `state_json()` now records the pre-candidate (`pre_candidate_*`, `pre_grants`,
  `send_pre_vote_pending`), the real `seen_greater_log`, and the real frozen
  quorum sets of the candidate and pre-candidate (`Progress::quorum_set()`).
- Runtime boundaries are emulated with `run_save_vote`, `run_send_vote`,
  `run_send_pre_vote` (drain one queued command kind, keep the others).
- New engine wrappers: `pre_elect`, `handle_pre_vote_req`,
  `handle_pre_vote_resp` (records `candidate_vote`, the Notification's echoed
  request vote), `HandleAppendEntries` via `Engine::append_entries`.
- `vote_req_args` records `response_last_log` with the responder id as the
  `None` placeholder.
- Add a field: extend `state_json`, then `Trace.tla` `TraceInit`/`ValidatePost`
  and `instrumentation-spec.md`; add a mutant to `field-mutation-check.sh`.
- Add an event: add a `step(...)` call in a scenario and a `Trace*` wrapper +
  `TraceStep` CASE arm.
- Rebuild/rerun: `bash harness/run.sh && bash harness/validate-traces.sh`.
