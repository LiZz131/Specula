# Harness operation

Run `./run.sh` (rebased for the update commit). It applies `instrumentation.patch` to
`../artifact` (idempotent, `apply.sh`; `clean.sh` reverts), invokes the eight V0 unit-test
scenarios serially with a 15-minute outer timeout per process, and writes fresh NDJSON files to
`../traces/`. It then runs three RaftCore scenarios (`t14_transfer_leader`,
`t99_specula_transfer::specula_transfer_all_nodes`, `...::specula_transfer_to_learner`) with
`SPECULA_CORE_TRACE_DIR=../traces/core-<scenario>/` and `SPECULA_OBS_FILE=../spec/output/obs-<scenario>.jsonl`.
Toolchain: `cargo +stable` (1.100.0 here; V0 used 1.95.0 which is not installed in this
environment — recorded as an environment difference, the patch and scenarios are unchanged). Tests use the production exact-old Engine methods; only capture and scenario setup
are test-only. Missing `SPECULA_TRACE_FILE` makes the added tests no-op, so ordinary upstream test
runs are unaffected.

Capture is strong for the synchronous Engine boundary: vote, observed vote, role, complete local
log IDs, commit, committed/effective membership, learners, candidate grants, leader matches,
accepted log I/O, and emitted command kinds. It is intentionally not a RaftCore/storage capture;
durable callback state is covered by the formal model and remains a documented extension point.

The trace writer serializes each complete event under a mutex, appends exactly one newline, and
flushes. Scenarios do not start background processes.


## Update probes (changed points only)

- `openraft/src/core/specula_core_trace.rs` (new, runtime-gated) and three hooks in
  `openraft/src/core/raft_core.rs` (TransferLeader arm, `handle_vote_request`,
  `Notification::VoteResponse`). See `../spec/instrumentation-spec.md`, "Update: RaftCore-level
  probes", for trigger points, session contiguity, and id mapping.
- `tests/tests/client_api/t99_specula_transfer.rs` (new scenarios; observations only, no
  protocol assertions) registered in `tests/tests/client_api/main.rs`.
- Unit capture (`engine/specula_trace_tests.rs`): `accepted_kind`; VoteRequest args
  `last_term`/`last_node`.

## Reproduction / attribution scripts (MC-1, CR-2)

- `repro/run_clean_controls.sh`: creates clean git worktrees of `d7176ef` (update) and
  `d86101c` (baseline) under `../build/`, adds `repro/t99_specula_repro.rs` as
  `tests/tests/client_api/t97_specula_repro.rs`, and runs
  `specula_repro_transfer_to_learner_no_panic` (update only; expected to FAIL while MC-1 exists)
  and `specula_control_trigger_elect_on_learner` (both revisions). No Specula instrumentation.
  Logs: `../spec/output/clean-<rev>-<test>.log`. Remove the worktrees afterwards with
  `git -C ../artifact worktree remove --force <path>`.
- `repro/run_repro.sh`: same two tests on the instrumented `../artifact` (run `apply.sh` first).
- `repro/t99_specula_self_transfer.rs`, `repro/t97_specula_elect_on_leader_control.rs`: CR-2
  observation (debug-assert panic after a Leader elects itself), logs
  `../spec/output/obs-self-transfer-write.log`, `../spec/output/obs-elect-on-leader-<rev>.log`.

The artifact tree was left clean (instrumentation reverted with `clean.sh`); `run.sh` re-applies it.
