# Instrumentation changes for the Pre-Vote revision

Rebased from the V0 harness (`/work/previous/.specular-output/harness`).

- Rename: `specula_trace_test` -> `specular_trace_test`, `SPECULA_TRACE_PATH` -> `SPECULAR_TRACE_PATH`, `SPECULA_TRACE` -> `SPECULAR_TRACE`.
- Source drift: only the `engine/mod.rs` test-module hunk needed new context (three new engine test modules); applied by symbol/context.
- New captured fields (all events): `pre_candidate_active`, `pre_candidate_vote`, `pre_candidate_config`, `pre_grants`, `send_pre_vote_pending`; `seen_greater_log` now real; `candidate_config` from the frozen quorum set.
- New scenarios (`engine/tests/specular_trace_test.rs`): `pre_elect_follower`, `pre_elect_single_voter`, `pre_vote_req_grant`, `pre_vote_req_reject_lease`, `pre_vote_req_reject_log`, `pre_vote_req_grant_empty_logs`, `pre_vote_resp_quorum`, `pre_vote_resp_reject_greater_log`, `pre_candidate_cleared_by_vote` (2 events), `pre_vote_after_establish` (3 events).
- Instrumentation is `#[cfg(test)]` only; production code is untouched.

Rebuild/rerun:

```bash
harness/run.sh              # apply patch to harness/work-source (git worktree of artifact @ update), build, collect 17 traces
harness/validate-traces.sh  # real TLC replay of every traces/*.ndjson with Trace.cfg (TraceConsumed)
```
