# Instrumentation (case-010 incremental)

- Base probes: `patches/instrumentation-v0.patch` (prior V0 patch, unchanged; applies cleanly to commit `update`).
- Update probes: `apply_update_probes.py <artifact> new|old` (exact-anchor edits; aborts on anchor drift). Adds `ReloadDatabase`, `LearnerShutdown`, `ReceiveSyncMode`, `SyncApplyCommitted`, the `stale` flag on `FlushTxnLog`, `dbInitialized` on `RestartLoadDatabase`, and the update-focused scenario `SpeculaTraceScenarioTest#testForcedSnapSyncCompletes`.
- `patches/instrumentation-case010-new.patch`: the resulting full diff against commit `update`, for review only.
- Rebuild/rerun: `harness/run.sh` (all scenarios) or `SPECULA_SCENARIOS="diff-sync-after-snap" SPECULA_TRACE_RUN_ID=<id> harness/run.sh`.
- Old-implementation control: `harness/run-old-control.sh` (worktree `work-old` at commit `baseline`, `old` probe variant, update's test file).
- Provenance gap: the prior V0 run produced schema-version-2 ("stateful") traces whose shadow-history probe is not contained in the preserved V0 patch (`harness/src/` was empty). The rebased harness therefore emits schema-1 common state plus the incremental fields above; the schema-2 conditional checks in `Trace.tla` are inactive for fresh traces. This is recorded as a validation limit, not replaced by a reimplemented shadow model.
