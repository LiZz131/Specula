# Specula harness (incremental run, Pre-Vote revision)

Rebased from the prior V0 harness (`/work/previous/.specula-output/harness`).

- `apply-instrumentation.sh` copies `src/specula_trace_test.rs` into
  `artifact/openraft/src/engine/tests/` and registers it after `mod startup_test;`
  in `openraft/src/engine/mod.rs` (symbol anchor; the prior `git apply` patch no
  longer applied with full context because the update added `mod pre_elect_test;`
  next to the anchor). `instrumentation.patch` is the resulting diff for review.
- `clean-instrumentation.sh` reverts it.
- `run.sh` applies, builds (`cargo test -p openraft --lib`, stable toolchain: the
  pinned `nightly-2026-03-01` is not installed and `/opt/rustup` is read-only), runs
  the 7 prior scenarios and 9 update scenarios, writes fresh `traces/*.ndjson`, and
  runs two code-observation tests whose JSON results go to
  `spec/output/harness-observations.log`.
- `validate-traces.sh [case...]` replays each trace with `spec/Trace.tla`
  (`TraceConsumed` + pre/post-state checks); summary in
  `spec/output/trace-validation-summary.txt`.
- `run-model-check.sh <name> <module> <cfg> <bfs|sim> <minutes> <workers> [heapGB] [depth]` runs one
  bounded TLC campaign (states under `/dev/shm/specula-e2e-case-011/`, removed afterwards; log
  `spec/output/mc-<name>.log`; `SPECULA_NODEADLOCK=1` for focused/open specs).
- `run-repro.sh` runs the two end-to-end RaftCore reproductions (`src/t90_*`, `src/t91_*`, installed into
  `tests/tests/elect/`); each asserts the correct behavior and fails (exit 101) while the defect is present.
  It also relies on `patches/memstore-delay-save-vote.patch` (test-support store only: optional
  `save_vote` delay).
- Helper scripts: `campaign_table.py` (campaign summary), `cex_diff.py` (counterexample diffs),
  `field_audit.py` (trace field consumption), `repro_timeline*.py` (reproduction timelines).

All instrumentation is `#[cfg(test)]`; no production code path is modified.
