# Harness operation (rebased for the updated revision, case-012)

Run from the suite root:

```bash
cd /work/current/.specula-output
bash harness/run.sh                 # instrument, build, run 17 scenarios, write traces/*.ndjson
bash harness/validate_traces.sh r3  # real TLC trace validation of every fresh trace
```

- `apply.sh` copies the updated `artifact/` tree (HEAD = `update`, aa05a38) to `work/instrumented` if absent and applies `harness/patches/instrumentation.patch` (or recognizes it as applied). It never resets an existing tree.
- `run.sh` builds once, then runs each scenario under a 300 s outer timeout with `SPECULA_TRACE=1 SPECULA_TRACE_FILE=...`; `preprocess_trace.py` keeps pure probes and outermost (`depth == 0`) Engine events only. Traces are removed before each run, so nonempty output is fresh.
- **Toolchain incompatibility (recorded)**: the source pins `nightly-2022-03-30` (`rust-toolchain`) and V0 ran `cargo +nightly`; no nightly is installed and `RUSTUP_HOME` is read-only, so the harness uses `cargo +stable` (rustc 1.100). The upstream lib suite passes under stable (101/101 upstream tests).

## What changed relative to the V0 harness

| Component | Change | Reason |
|---|---|---|
| `specula_trace.rs` | snapshot adds `leader_active`, `vote_granted`, `progress_configs`, ordered `progress_vector`, `progress_committed`; Engine events carry `depth`; generic `SpeculaValue`/`SpeculaQuorum` rendering; `ProgressUpgrade` event; `GreatestMajority` removed | the update made Engine leader progress (VecProgress order) behaviour-relevant; `greatest_majority_value` was deleted |
| `engine_impl.rs` probes | re-anchored (elect, follower commit, update_committed_membership); new probes for `update_effective_membership`, `update_progress`, `handle_vote_resp` (wrapper); `leader_append_entries` capture moved after the empty check | source drift + new affected actions |
| `progress/mod.rs` probes | `update` (3 exits) and `upgrade_quorum_set`; `specula_vector` accessor | VecProgress is on the commit path |
| `leader/leader.rs` | `SpeculaQuorum` bound on the `Leader` impl | needed for generic serialization only |
| scenarios | V0 `leader_membership_append` re-targeted to `test_leader_append_entries_fast_commit_upto_membership_entry` (V0 test replaced by the update); V0 `greatest_majority` superseded; 9 update scenarios added | see `spec/validation-summary.md` |

To add a snapshot field: extend `capture_engine` and `EngineSnapshotMatches(Next)` in `spec/Trace.tla`. After probe changes regenerate the patch with `git -C work/instrumented diff HEAD > harness/patches/instrumentation.patch`.
