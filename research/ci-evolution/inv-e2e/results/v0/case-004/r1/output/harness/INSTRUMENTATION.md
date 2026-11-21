# Harness operation (rebased onto the update revision)

Run `./run.sh` (one command). It copies `../artifact` (commit `update`) to
`../build/work-source`, applies `instrumentation.patch`, and with outer timeouts:

1. runs the 8 V0 Engine unit scenarios plus `specula_trace_lease_touch` (U-S2), writing
   `../traces/<name>.ndjson`;
2. runs the integration tests `t14_transfer_leader::transfer_leader` (the update's own test)
   and `t14_specula_transfer_to_learner::specula_transfer_leader_to_learner` (U-S1) with
   `SPECULA_CORE_TRACE_FILE`, then `split_core_trace.py` writes `../traces/core-*.ndjson`
   (raw files kept in `../traces/raw-core/`).

Toolchain: `cargo +stable` (1.100.0 here; the tree's `rust-toolchain` pins an uninstalled
nightly; V0 used an installed 1.95.0 explicitly for the same reason).

## Changed points relative to V0 (`instrumentation.v0.patch`)

- V0 patch applied unchanged in substance; capture adds `lease_enabled` and
  `accepted_vote_io`; `VoteRequest` args add the request's last log id.
- New unit scenario `specula_trace_lease_touch`.
- New RaftCore hook module `openraft/src/specula_core_trace.rs` and hooks at the
  TransferLeader arm, `handle_vote_request`, and the `Notification::VoteResponse` handler
  (with an unwinding guard that records `VoteResponsePanic`).
- New read-only accessor `Leased::lease_enabled()`.
- New integration scenario file `tests/tests/client_api/t14_specula_transfer_to_learner.rs`.

## Reproduction / controls for MC-1 (no instrumentation)

`repro/run_repro.sh` (update tree), `repro/run_control_baseline.sh` (baseline commit,
pre-existing `trigger().elect()` on a learner), `repro/run_control_update_trigger.sh` (same
control on the update tree). Logs: `../spec/output/repro-MC-1*.log`, `control-MC-1-*.log`.
