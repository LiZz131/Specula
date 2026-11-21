# Specula V0 harness

`apply-instrumentation.sh` applies the preserved test-only patch to a clean writable copy. `run.sh` builds the exact-old crate and generates seven fresh NDJSON files. `validate-traces.sh` consumes each trace with `Trace.tla`. `run-model-check.sh` runs the primary and membership non-vacuity configurations.

The immutable `/work/source` tree is never touched. The source requests `nightly-2026-03-01`, which is unavailable in this isolated image; the successful baseline and harness use the installed `nightly-2025-12-31` through `RUSTUP_TOOLCHAIN`. Override `SPECULA_RUST_TOOLCHAIN` if the requested toolchain later becomes available.

