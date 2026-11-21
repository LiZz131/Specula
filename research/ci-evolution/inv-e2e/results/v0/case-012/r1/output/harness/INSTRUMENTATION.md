# Harness operation (incremental run, rebased from V0)

Run from the suite root:

```bash
cd /work/current/.specula-output
bash harness/run.sh
```

- `apply.sh` copies `artifact/` (updated source, commit aa05a38) to
  `work-source/` if absent, then applies `harness/patches/instrumentation.patch`
  (or recognizes it is already applied). The artifact tree itself is never
  modified. Override with `SPECULA_SOURCE` / `SPECULA_WORK_SOURCE`.
- `run.sh` builds once (`cargo +stable test --no-run`, 25-minute outer timeout),
  then runs every scenario with a 5-minute outer timeout and regenerates one
  NDJSON file (or `-seg<k>` segments) per scenario in `traces/`.
  V0 used `cargo +nightly`; only the stable toolchain is installed here
  (`/opt/rustup` is read-only), so `SPECULA_CARGO_TOOLCHAIN` defaults to
  `stable`. The tree builds and its tests pass unchanged with stable.
- `preprocess_trace.py` keeps outermost probes (`depth = 0`), optionally filters
  by event names, and splits multi-fixture tests at fixture boundaries.

Changed probe points relative to V0 (see `spec/instrumentation-spec.md`):

- new: `Engine::update_progress`, `Engine::update_effective_membership`,
  `Engine::handle_vote_resp`, `VecProgress::upgrade_quorum_set` (wrapper
  functions around the unchanged bodies), leader progress fields in every
  Engine snapshot, `depth` on every event;
- rebased: `VecProgress::update` (wrapper; no trait-bound changes),
  `follower_commit_entries` (new body), `leader_append_entries` (membership
  position now taken from the first membership entry);
- removed: `Membership::greatest_majority_value` probe (function deleted).

Tracing is disabled unless both `SPECULA_TRACE=1` and
`SPECULA_TRACE_FILE=/abs/path.ndjson` are set. To add a field, extend
`capture_engine` in `openraft/src/specula_trace.rs` and the matching check in
`spec/Trace.tla`; regenerate the patch with
`git -C work-source diff HEAD -- openraft/src > harness/patches/instrumentation.patch`.
Trace validation: `spec/run_trace_validation.sh <tag> [trace...]`.
