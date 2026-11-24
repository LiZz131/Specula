# v1 / case-010 census notes

- Census cfgs (all run on module Update, UPDATED semantics, enabling the update invariants):
  Update-full, Update-focused, Update-open, Update-hunt-snap, Update-hunt-trunc(-gap), Update-hunt-trunc-noleak(-gap),
  Update-hunt-leak(-gap/-order/-prefix). Each: 120 s seed 1 + 240 s seed 2 (Update-focused needed only seed 1).
- Skipped cfgs: residual cfgs (Update-*-residual: drop U1-U4 by design), PRIOR control cfgs (old semantics),
  canary cfgs, Evidence-* oracles, MC-* inherited hunts / complete schedules (no learner-exit relevance), Trace*.
- Positive control SC_CTRL (counters.exits >= 1) reached in every cfg; no runner errors.
- Agent canaries (Update-canary-*.cfg) differ from their hunt cfgs only in TrackCoverage=TRUE, which only feeds the
  ghost variable `seen` (MC.tla:28-36); no guard reads `seen`. I treated them as behaviour-equivalent but still
  re-measured every item with state-only census probes on the property cfgs.
- Skipped items: baseline (pre-update) brief scenarios 1-4 and MC-EPOCH/SYNC/PIPE/RECOVERY (modeling-brief.md:13-160)
  because they belong to the prior V0 brief, not the update; bug-report MC-1 variants (bug-report.md:24) are
  consequences already witnessed by agent violations (U3a-c).
- Inferred, not measured: U1b probe stops at "ChooseSyncMode(DIFF) allowed" for the re-joining SNAP follower; the
  later "FollowerLogRequest/Flush -> RestartLoadDatabase" tail is not encoded (no history variable records it).
  U2a/U3a probes are pre-states of the exit step (exit enabled), not the post-exit state.
- Structural non-reach: SC_U1a/U1b/U2* not reachable in Update-hunt-leak*.cfg (LeakScenarioNext only allows serving
  exits, Update.tla:180); SC_U2* not in Update-hunt-snap.cfg (only DIFF/SNAP, Update.tla:154); SC_U3* not in
  Update-hunt-snap / trunc-noleak (exits only inside SyncWindow, Update.tla:156,173). Other non-reach is
  "not seen in budget" (e.g. SC_U2a/U2b/U3c in Update-full.cfg, 360 s).
- Result: all 9 MC-checkable items covered; C2 (thread-count code observation) unclear (not MC-checkable).
