# Harness instrumentation (rebased for the Pre-Vote revision)

Provenance: the V0 harness (`instrumentation.patch`, kept unchanged for
provenance) adds the test-only module `engine::tests::specula_trace_test`.
Its git patch no longer applies to the update (`openraft/src/engine/mod.rs`
gained `mod pre_elect_test;` inside the patch context;
`spec/output/harness-rebase-check.log`). It was rebased as copy-and-patch:

- `src/v0_specula_trace_test.rs`: the V0 module extracted verbatim from the patch.
- `src/specula_trace_test.rs`: the rebased module. Changes vs. V0:
  - `state_json` adds `pre_candidate_active`, `pre_candidate_vote`,
    `pre_grants`, `pre_candidate_config`, `send_pre_vote_pending`; captures the
    real `seen_greater_log` (V0 hard-coded `false`) and the real frozen
    candidate quorum set (V0 used the effective config as proxy).
  - Event helpers `ev_*` wrap exactly one `Engine` call each; `run_commands`
    executes queued commands between events as `RaftCore::run_command` does.
  - V0 scenarios are unchanged; 14 update scenarios were added (see
    `spec/validation-handoff.md`).
- `apply-instrumentation.sh`: copies the module into
  `openraft/src/engine/tests/` and inserts `mod specula_trace_test;` after
  `mod startup_test;` in `openraft/src/engine/mod.rs`. No production code
  changes.

Instrumentation points (after apply), all in
`openraft/src/engine/tests/specula_trace_test.rs`:

| Event | Wrapper | Engine call (new tree) |
|---|---|---|
| StartElection | `ev_elect` | `Engine::elect` (engine_impl.rs:249) |
| StartPreVote | `ev_pre_elect` | `Engine::pre_elect` (engine_impl.rs:298); tick form calls `reset_greater_log` first |
| HandleVoteRequest | `ev_vote_req` | `Engine::handle_vote_req` (engine_impl.rs:350) |
| HandleVoteResponse | `ev_vote_resp` | `Engine::handle_vote_resp` (engine_impl.rs:450) |
| HandlePreVoteRequest | `ev_pre_vote_req` | `Engine::handle_pre_vote_req` (engine_impl.rs:414) |
| HandlePreVoteResponse | `ev_pre_vote_resp` | `Engine::handle_pre_vote_resp` (engine_impl.rs:516) |
| HandleAppendEntries | `ev_heartbeat` | `Engine::append_entries` (engine_impl.rs:586) |
| AppendJointConfig / CommitMembership / Restart | inline (V0) | unchanged |

Adjusting: add a field in `state_json` and the matching conjunct in
`Trace!StateMatches`; add an event by copying an `ev_*` helper and a
`Trace*` wrapper plus its `CASE` arm in `Trace!TraceStep`; move a capture by
moving the `state_json` call around the engine call.

Rebuild/rerun: `bash harness/run.sh` (applies, builds with
`RUSTUP_TOOLCHAIN=stable`, writes `traces/*.ndjson`), then
`bash harness/validate-traces.sh` (TLC replay, logs `spec/output/trace-*.log`)
and `bash harness/field-consumption.sh` (single-field mutants must be rejected).
