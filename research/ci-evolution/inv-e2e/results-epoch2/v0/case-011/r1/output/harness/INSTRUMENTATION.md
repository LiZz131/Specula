# Instrumentation (incremental run, Pre-Vote update)

All instrumentation is test-only and lives in `harness/instrumentation.patch`
(applied to `work-source/`, a plain copy of `artifact/` at `3ab6cdd`):

- `openraft/src/engine/tests/specula_trace_test.rs` — V0 trace module rebased
  (the V0 `engine/mod.rs` hunk drifted because the update added test modules;
  reapplied with `git apply -3`). Changed points:
  - state capture adds `pre_candidate_*`, `pre_grants`, `send_pre_vote_pending`,
    real `seen_greater_log`, and the Candidate's real frozen quorum;
  - new event kinds `PreElect`, `HandlePreVoteRequest`, `HandlePreVoteResponse`
    (calls of the real `Engine::pre_elect`, `handle_pre_vote_req`,
    `handle_pre_vote_resp`);
  - 14 update scenarios (U1-U5) next to the 7 unchanged V0 scenarios.
- `openraft/src/engine/tests/specula_repro_test.rs` — reproduction tests for
  MC-1 and CR-1 (they assert the promised behavior and FAIL on this revision)
  and a passing direct-election control.
- `tests/tests/elect/t91_specula_stale_pre_vote_round.rs`,
  `tests/tests/elect/t92_specula_stale_pre_vote_round_timer.rs` — integration
  reproductions of MC-1 through the real RaftCore/network (`RaftRouter` hooks).
- `stores/memstore/src/lib.rs` — test store only: `BlockOperation::DelaySaveVote`
  (used by t92 to make the vote save slow).

Rebuild/rerun:

```bash
harness/run.sh                      # apply patch, build, run 21 trace scenarios -> traces/
harness/validate-traces.sh          # TLC replay of every trace (Trace.cfg, TraceConsumed)
harness/mutation-check.sh           # negative control: 34 single-field mutants must fail
harness/run-repro.sh                # reproduction tests (expected to FAIL on this revision)
```
