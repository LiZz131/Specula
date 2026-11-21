# Harness operation

Run from the suite root:

```bash
cd /work/prior/.specula-output
bash harness/run.sh
```

`apply.sh` applies `harness/patches/instrumentation.patch` to `/work/work-source` or recognizes that it is already applied. It never resets the tree. `run.sh` then runs nine exact-old unit scenarios under five-minute outer timeouts and recreates one NDJSON file per scenario. `preprocess_trace.py` removes nested helper probes from the three Engine-action scenarios, leaving each action trace at its observable before/after boundary; it never synthesizes or edits event fields.

Probe locations after apply are listed in `spec/instrumentation-spec.md`. Event serialization and field mapping live in `openraft/src/specula_trace.rs`; add a snapshot field in `capture_engine`, add a helper event in the matching `emit_*` function, and add the corresponding post-state check in `spec/Trace.tla`. To move a capture point, keep the `capture_engine` call before the exact transition and `emit_engine` after it.

Tracing is disabled unless both environment variables are present:

- `SPECULA_TRACE=1`
- `SPECULA_TRACE_FILE=/absolute/path/to/scenario.ndjson`

After any probe adjustment, regenerate the patch relative to the neutral baseline and rerun `bash harness/run.sh`; every named trace is removed first, so nonempty output is fresh evidence.

## V1 rebase (updated revision)

```bash
cd /work/current/.specula-output
bash harness/run.sh          # applies patches/instrumentation.patch to work-source/, cargo +stable, 18 scenarios
```

- `apply.sh` now defaults to `<suite>/work-source` (a copy of `artifact/` at commit `update`) and prints the HEAD it instruments.
- Toolchain: `cargo +stable` (override with `SPECULA_CARGO_TOOLCHAIN`); the pinned nightly in `rust-toolchain` is not installed here and the V0 `+nightly` invocation cannot run.
- `src/specula_trace.rs`: adds leader-data snapshot fields, `Scope` (RAII pre-capture + nesting depth), `SpeculaValue` formatting. `src/specula_trace_test.rs`: harness-owned scenarios `specula_trace_election_single` (V0), `specula_trace_leader_lifecycle`, `specula_trace_follower_commit_no_advance`, `specula_trace_update_effective_membership_to_learner` (V1).
- New probes: `Engine::update_progress`, `Engine::update_effective_membership`, `Engine::handle_vote_resp` (thin wrappers around the unchanged bodies), unknown-id return in `VecProgress::update`.
- Raw events are kept in `traces/raw/`; `preprocess_trace.py` keeps depth-0 events.
- Regenerate the patch after probe edits: `git -C work-source diff > harness/patches/instrumentation.patch` (with `git add -N` for new files).
