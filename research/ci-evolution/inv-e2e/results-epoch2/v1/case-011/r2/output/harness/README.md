# Specular harness (rebased onto the Pre-Vote update revision)

- `apply-instrumentation.sh`: creates `harness/work-source` as a detached git worktree of `artifact/` at the `update` commit (the artifact tree itself stays clean) and applies `instrumentation.patch` (test-only).
- `run.sh`: one command to apply, build (`nightly-2026-03-01`, the toolchain requested by `rust-toolchain`; V0 had to use `nightly-2025-12-31`), run all 7 prior and 10 update scenarios under `timeout`, and write fresh `traces/*.ndjson`.
- `validate-traces.sh`: TLC trace validation of every retained trace (states under `/dev/shm/specular-e2e-case-011/`, removed after each run; logs `spec/output/trace-*.log`; summary `spec/output/trace-validation-summary.tsv`).
- `run-model-check.sh <Spec> <cfg> <label> [min] [workers]`: bounded TLC run (outer `timeout`, `-Dtlc2.TLC.stopAfter`), log `spec/output/mc-<label>.log`, state dir removed on exit.
- Reproduction of MC-1 is separate: `spec/repro/run-MC-1-repro.sh` (test-only router delay knob + integration test).
