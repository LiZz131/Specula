# ci-context (case-010) — run-local working memory

Source: artifact HEAD b16ba71 (update); old control worktree artifact-old at f8533cd (baseline).
Disposition: MODEL_CHANGE_REQUIRED (analysis-report.md "Incremental update analysis").

Model (spec/): base.tla (split SNAP/TRUNC, LearnerShutdownCore UPDATED/PRIOR, ReloadDatabase, leakedQueued per-processor FIFOs,
plain Append WAL, zxid-based SyncModeAllowed/NextFrom/TruncTarget, SNAP only if peer last <= leader applied last),
MC.tla (counters rounds/crashes/exits/snapshots; SteadyInit), Update.tla (+UpdateProps.tla U1..U4, ClearedOnlyAfterSnapExit,
MonotoneUnlessRecoveryUpd; scenario nexts SnapScenarioNext/TruncScenarioNext/LeakScenarioNext), Trace.tla v3 schema.

Validated: fresh traces v3/v3b/v3c passed on earlier candidates; v3d regenerated after atomic setPeerState probe (validate on final model).
Old-control traces (traces/old-control/*oldctl*) replay vs PRIOR: SNAP trace reproduces real recovered gap [11] and violates U1, OrderedHistoriesV1.
Code observations: old fails testDiffSyncAfterSnap (node 0 missing); new passes. Serving exit: new leaks SyncThreads (2 per follower, survive shutdown); old 1 and none after shutdown.

Findings so far (final model wave C pending):
- UPD-1 SNAP fix: UPDATED clean (earlier exhaustive 424k states); PRIOR violates U1/U2 => FIXED old bug (not a finding of new code).
- F-TRUNC (pre-existing, incomplete fix): TRUNC-mode exit after in-sync COMMIT keeps unpersisted image (U1, U2), in UPDATED and PRIOR.
- F-LEAK (update-introduced): serving exit bypasses LearnerZooKeeperServer.shutdown -> SyncRequestProcessor leaked; stale append after re-sync (U2 gap; U4 order). Need PRIOR per-property controls (wave C) for attribution; U4 also violated in PRIOR (drain-after-fastForward pre-existing).
- Independent (not pursued): TRUNC of a peer's ACKed-but-unapplied record reduces quorum durability (pre-existing).

Pending: wave C results; final trace regression (v3d) on final model; Update-full/focused/open/discharge; MC.cfg/MC-full; inherited hunts; simulation;
invariant-evidence.json (+ evidence/ modules via mkeval.py/runeval.sh); findings.json, bug-report.md, final-result.json, final-response.json.
