# Specula harness (incremental run, Pre-Vote update)

- `run.sh` — apply test-only instrumentation to `work/source-new` (extracted
  from `artifact` HEAD if missing), build, run 7 V0 regression + 14 update
  scenarios, write 21 fresh traces to `../traces/`.
- `validate-traces.sh` — real TLC trace validation of every fresh trace
  (`TraceConsumed` temporal completion + all Trace.cfg invariants).
- `field-consumption.sh` — 20 single-field mutants; each must be rejected.
- `run-tlc.sh` — bounded TLC wrapper (states under
  `/dev/shm/specula-e2e-case-011`, removed after the run; logs in
  `../spec/output/mc-<label>.log`; counterexamples in `mc-<label>.cex.json`).
- `run-canaries.sh`, `run-model-check.sh` — campaign drivers.
- `instrumentation.patch` — V0 patch (provenance; no longer applies, see
  INSTRUMENTATION.md). `src/` — V0 and rebased harness modules.

Toolchain: the repository pins `nightly-2026-03-01`, which is not installed
and cannot be installed here (`/opt/rustup` read-only); `stable` (rustc
1.100.0) builds and passes the library suite (486/486).

## Reproduction / code-observation assets (`repro/`)

- `repro/t13_specula_stale_prevote_repro.rs` + `repro/run-repro.sh [source-dir] [log]`:
  real RaftCore runtime (RaftRouter, memstore) for MC-1. Copies the test into
  `<source>/tests/tests/elect/` and runs
  `cargo test -p tests --test elect specula_repro -- --nocapture --test-threads=1`.
  `specula_repro_stale_prevote_demotes_new_leader` FAILS while the defect is
  present (debug: RaftCore panics at engine_impl.rs:977; release: the new
  leader becomes a term+1 Candidate); `specula_repro_control_without_prevote`
  is the same setup without the Pre-Vote trigger and must pass. Requires the
  updated API `trigger().elect(bool)` (not applicable to the old revision,
  which has no Pre-Vote).
- `repro/t14_specula_elect_on_leader_{old,new}.rs`: control for the
  pre-existing operator elect-on-leader panic (CR-PRE-1), one per API.
- `coverage-keylines.py <mc-log>`: expression-coverage counts of the key
  update branches; `summarize-mc.py`: campaign table
  (`spec/model-checking-summary.md`); `campaign-queue.sh`: remaining-campaign
  scheduler used in this run.
