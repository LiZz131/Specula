# Specular harness (rebased for the Pre-Vote update)

Provenance: rebased from the V0 harness of `/work/previous/.specular-output`
(original patch kept as `patches/v0-instrumentation.patch`). The V0 patch no
longer applied (context drift in `openraft/src/engine/mod.rs`); the test module
was renamed `specular_trace_test` and extended. Env vars use the `SPECULAR_`
prefix.

Commands (from `.specular-output/`):

| Step | Command |
|---|---|
| apply instrumentation to `work-source/` (copied from `artifact/` if missing) | `bash harness/apply-instrumentation.sh` |
| build + run all scenarios, write fresh `traces/*.ndjson` | `bash harness/run.sh` |
| TLC trace validation of every retained trace | `bash harness/validate-traces.sh` |
| field non-vacuity mutants | `bash harness/field-mutation-check.sh` |
| bounded TLC run (states in /dev/shm, removed after) | `bash harness/tlc-run.sh <Module> <cfg> <label> <workers> <minutes> [TLC args]` |
| model-checking campaign used in this run | `bash harness/run-model-check.sh` |
| real-interface reproductions (MC-1, MC-2) | `bash harness/repro/run-repro.sh [source-tree] [log-name]` |

Toolchain: `rust-toolchain` of the source (`nightly-2026-03-01`, installed).
Scenario inventory: `harness/cases.sh`. See `harness/INSTRUMENTATION.md`.
