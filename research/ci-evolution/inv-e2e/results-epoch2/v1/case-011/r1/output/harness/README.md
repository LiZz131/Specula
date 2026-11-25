# Specula harness — incremental run (Pre-Vote revision)

Rebased from the V0 harness (`/work/previous/.specula-output/harness`).

* `apply-instrumentation.sh` — copies `artifact/` to `work-source/` if needed and
  applies `instrumentation.patch` (test-only module
  `openraft/src/engine/tests/specula_trace_test.rs`, mirrored in `src/`).
  `instrumentation-v0.patch` is the unchanged prior patch (applies to the
  baseline commit only; fails on `engine/mod.rs` context in the update).
* `run.sh` — one command: apply, build (`cargo test -p openraft --lib --no-run`,
  30 min timeout), run the 7 V0 + 8 update scenarios (5 min timeout each),
  write fresh `traces/*.ndjson`. Toolchain: `stable` (1.100.0); the pinned
  `nightly-2026-03-01` is not installed (V0 used `nightly-2025-12-31`, also
  absent here). Override with `SPECULA_RUST_TOOLCHAIN`.
* `validate-traces.sh [case...]` — TLC replay of every fresh trace with
  `Trace.cfg` (`TraceConsumed` temporal property), states under
  `/dev/shm/specula-e2e-case-011/`, logs `spec/output/trace-<case>.log`.
* `check-trace-fields.sh` — every emitted pre/post/args field is read by `Trace.tla`.
* `run-model-check.sh <name> <Module> <cfg> [tlc args]` — bounded TLC campaign
  (`-Dtlc2.TLC.stopAfter`, outer `timeout`, metadir removed afterwards, verdict
  line appended; a time-budget stop with a non-empty queue is LIMITED_COVERAGE).
* `run-canaries.sh` — reachability canaries for the update Scenarios.

Naming: the task fixes the output directory as `.specula-output`, so the
`SPECULA_*` environment names and `specula_trace_*` test names were kept.
* Provenance check (final): `instrumentation-v0.patch` still applies cleanly to the baseline commit 1adc857 and fails on 3ab6cdd only at `openraft/src/engine/mod.rs` (checked with `git apply --check`).
