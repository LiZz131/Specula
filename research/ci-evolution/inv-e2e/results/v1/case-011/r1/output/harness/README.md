# Specula harness (V1: rebased onto the Pre-Vote update)

Reused from V0 (`/work/previous/.specula-output/harness`): the test-only
Engine-level trace module, NDJSON envelope, state serializer, the seven V0
scenarios and their drivers, and the one-file-per-scenario layout.

Changed for V1 (minimal, evidence-backed):

- `instrumentation.patch` rebased: the V0 hunk on `openraft/src/engine/mod.rs`
  no longer applied (new `pre_elect_test`/`handle_pre_vote_*_test` modules
  shifted the context); the module registration is re-anchored after
  `startup_test`. The test module source lives in `src/specula_trace_test.rs`.
- Serializer: added the pre-candidate fields and `send_pre_vote_pending`;
  `seen_greater_log` now reports the real engine flag.
- New update scenarios U-S1..U-S4 (12 tests), multi-event where the update
  interaction needs it.
- Toolchain: the requested `nightly-2026-03-01` and V0's `nightly-2025-12-31`
  are not installed; the installed `stable` (rustc 1.100.0) builds the crate
  without the nightly-only `bt`/`bench` features. Override with
  `SPECULA_RUST_TOOLCHAIN`.
- `rg` is not installed; scripts use `grep`.

Commands (all bounded by `timeout`):

```bash
harness/apply-instrumentation.sh      # copy artifact -> work-source (if needed) and apply the patch
harness/run.sh                        # build + 19 scenarios -> traces/*.ndjson (record counts checked)
harness/validate-traces.sh            # TLC Trace.cfg on every fresh trace -> spec/output/v1-trace-*.log
harness/mutation-controls.sh          # 11 single-field mutants, all must be rejected
harness/run-evidence.sh               # static property-decision evaluations (spec/evidence)
harness/run-model-check.sh <module> <cfg> <bfs|sim> <minutes> <workers> <tag>
```

TLC state directories live under `/dev/shm/specula-e2e-case-011/` and are
removed after every run.
