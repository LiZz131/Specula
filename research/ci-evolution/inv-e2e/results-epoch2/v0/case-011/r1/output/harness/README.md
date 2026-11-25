# Specula harness (incremental run, Pre-Vote update)

Rebased from the V0 harness (`/work/previous/.specula-output/harness`).

- `apply-instrumentation.sh` copies `artifact/` to `work-source/` when absent and applies `instrumentation.patch` (test-only).
- `run.sh` builds the updated crate (stable toolchain; the requested nightly-2026-03-01 is not installed and `/opt/rustup` is read-only) and generates 21 fresh NDJSON traces listed in `cases.txt` (7 V0 regression + 14 update scenarios).
- `validate-traces.sh` replays every trace with `spec/Trace.tla` (`Trace.cfg`, `TraceConsumed`); TLC states under `/dev/shm/specula-e2e-case-011/`, removed after each run.
- `mutation-check.sh` is the negative control for trace-field consumption.
- `run-tlc.sh` / `run-campaign.sh` run bounded TLC campaigns (outer `timeout`, logs in `spec/output/`, state dirs removed).
- `run-repro.sh` runs the reproduction tests (expected to FAIL on this revision) and the control.
- `tools/gen_cfgs.py` regenerates the Update/hunt/canary cfgs; `tools/make_mutants.py` builds trace mutants.

See `INSTRUMENTATION.md` for the changed instrumentation points.
