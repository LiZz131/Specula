# Harness instrumentation (incremental rebase)

Prior V0 harness: engine-level, test-only module `openraft/src/engine/tests/specula_trace_test.rs`
(`/work/previous/.specula-output/harness/instrumentation.patch`, kept here as
`instrumentation.v0.patch`). It was **reused**, not regenerated:

- Source drift: the V0 hunk for `openraft/src/engine/mod.rs` no longer applies
  (the update added `handle_pre_vote_req_test`, `handle_pre_vote_resp_test`,
  `pre_elect_test` to the same `mod tests` block). `apply-instrumentation.sh`
  now copies `harness/src/specula_trace_test.rs` and registers it after
  `mod startup_test;`. The resulting diff is written to `instrumentation.patch`.
- Retained unchanged: NDJSON envelope, `emit`, fixture builders, the seven V0
  scenarios and their engine calls.
- Changed: state snapshot adds `pre_candidate_*`, `pre_grants`,
  `send_pre_vote_pending`; reads the real frozen candidate quorum set and the
  real `seen_greater_log` flag.
- Added (update-focused, derived from the diff): 12 scenarios listed in
  `cases.sh` (`update_cases`), including multi-event interaction traces using
  `RunCommands` to hand queued commands to the runtime boundary.

Rebuild/rerun:

```bash
harness/run.sh                      # apply, build (stable toolchain), run 19 scenarios, write traces/*.ndjson
harness/validate-traces.sh          # TLC replay of every retained trace (Trace.cfg, TraceConsumed)
harness/mutation-check.sh           # 25 single-field mutants must be rejected
harness/run-tlc.sh <Module> <cfg> <label> <seconds>   # bounded TLC campaign
harness/repro/run-repro.sh          # MC-1 reproduction tests (engine + runtime)
```

Toolchain: the tree requests `nightly-2026-03-01` (not installed); the
installed `stable` 1.100.0 builds and passes the library and integration suites
(`spec/output/baseline-new-*.log`). Override with `SPECULA_RUST_TOOLCHAIN`.
