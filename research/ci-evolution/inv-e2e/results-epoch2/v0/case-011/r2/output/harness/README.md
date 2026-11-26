# Specular harness (incremental run incr-b919e9f909ea)

Rebased from the prior Specula V0 harness onto the updated source.

- `apply-instrumentation.sh` — copies `artifact/` (without `.git`) to `work-source/` if needed and applies `instrumentation.patch` (test-only).
- `run.sh` — builds with `nightly-2026-03-01` (the source's `rust-toolchain`; now installed) and runs the 7 prior + 11 update scenarios, writing `traces/*.ndjson`.
- `validate-traces.sh` — TLC trace validation (`TraceConsumed` temporal property) for every trace; summary in `spec/output/trace-validation-summary.tsv`.
- `trace-negative-controls.sh` — mutation controls; summary in `spec/output/negative-controls/summary.tsv`.
- `tlc-run.sh` — bounded TLC wrapper (state dirs under `/dev/shm/specular-e2e-case-011/`, removed after each run).
- `run-model-check.sh` — the full model-checking campaign used in this run.
- `repro/` — reproduction test and script for finding MC-1.
