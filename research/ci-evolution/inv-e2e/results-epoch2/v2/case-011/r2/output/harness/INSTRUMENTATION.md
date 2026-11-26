# Specular instrumentation (incremental run incr-4e410cd184be)

Changed points are listed in `instrumentation-spec.md` §4; rebuild and rerun with `harness/run.sh`, validate with `harness/validate-traces.sh`.

Rebased from the V0 prior harness (`/work/previous/.specular-output/harness`).

- `apply-instrumentation.sh` — creates `work/source` from the artifact HEAD
  (git archive) if absent and applies `instrumentation.patch` (test-only module).
  Incompatibility with the prior patch: only context drift in
  `openraft/src/engine/mod.rs` (new pre-vote test modules); the prior test body
  was carried over unchanged apart from the specula->specular rename and the
  `caller` argument.
- `run.sh` — one command: apply, build (`cargo test -p openraft --lib
  specular_trace --no-run`, nightly-2026-03-01, `timeout 30m`), run the 17
  scenarios (7 prior + 10 update, `timeout 5m` each) and check each trace's
  event count. Log: `spec/output/harness-run.log`.
- `validate-traces.sh` — real TLC trace validation (Trace.cfg incl.
  `TraceConsumed`) per trace; logs `spec/output/trace-<case>.log`; TLC states
  under `/dev/shm/specular-e2e-case-011/` removed per run.
- `mutation-controls.sh` — 12 single-field mutations that Trace.tla must reject.
- `tlc-run.sh` — bounded TLC runner for model checking (stopAfter + outer timeout,
  states in /dev/shm, logs in `spec/output/`).
- Reproduction tests: `spec/repro/` (separate source copy `work/repro`).

Toolchain: `nightly-2026-03-01` (the repository's `rust-toolchain`) is installed
in this image; the V0 run had used `nightly-2025-12-31`.
