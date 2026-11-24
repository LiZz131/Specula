# v0 / case-010 census notes (ZooKeeper Learner.shutdown(syncMode==SNAP) update)

Cfgs probed (extends Update unless noted; agent ran Update cfgs on module Update per scripts/run_F3.sh):
Update-full, -focused, -open, -smoke, -hunt-snap, -hunt-snap-steered, -hunt-snap-only-steered,
-hunt-snap-only-steered-consequence, -hunt-trunc, -hunt-trunc-steered, -hunt-trunc-steered2,
-hunt-trunclog-steered, -hunt-trunclog-consequence-steered, -hunt-diffwindow, -hunt-diffwindow-steered,
-hunt-diffwindow-steered2, -hunt-mc1-deterministic; MC.cfg, MC-full.cfg, MC-wide.cfg (extends MC; they enable
DurableHistoryConsistent). 9 probes each incl. positive control SC_PC (reached everywhere), 120 s + 240 s retry.
Skipped: *-oldcontrol*.cfg (UpdateFullShutdownOnSnap=FALSE: old-semantics differential controls),
Update-continue-mc1-consequence.cfg (INIT = the MC-1 witness end state, module UpdateContinueMC1),
Update-hunt-mc2-leadercompleteness.cfg (enables neither update property nor DurableHistoryConsistent),
Update-canary-*.cfg, MC-*-hunt.cfg (canary-only), Update-discharge.cfg, base.cfg, Trace*.cfg.

Canary matching: every Update-canary-* cfg that has a property twin differs from it in TrackCoverage
(TRUE vs FALSE). TrackCoverage only gates the `seen` bookkeeping (MC.tla:22), but per the brief's strict rule
the canary hits are not counted for the property cfgs; the census re-measured each item instead.
Update-canary-snapabort/-reload/-snapcommit/-truncabort/-diffabort have constants of no property cfg.

Items: 8 (U1, U1b, U1r, P-SERD, U2a, U2b, U3, U3c). 7 covered, 1 Q-a (U1).
- U1 (SNAP-window exit while the learner holds a leader image not on disk): not seen in any cfg (Q-a,
  not seen in budget; 840 s in the two SNAP-steered cfgs after a --seconds 600 rerun). No structural bound: the agent's old-control BFS reaches exactly this pre-exit
  state at depth 37 in a cfg differing only in UpdateFullShutdownOnSnap. Weaker states (SNAP window with an
  in-memory commit enabled, post-SNAP-exit LOOKING peer, rejoin after SNAP exit) are reached.
- U2b covered only by the agent's own BFS witness in Update-hunt-mc1-deterministic.cfg (property cfg);
  census simulation did not see SC_U2b/SC_U2 anywhere (random walk rarely hits the steered order).
- U3c is the MC-2 consequence (a DurableHistoryConsistent violation itself); no precondition probe.

Inferred, not measured: probes are post-/pre-step state signatures; the sync stage before an exit is lost
after LearnerShutdown (syncStage := EXITED), so U1/U2b/U3 are encoded as "window state + exit enabled"
(ENABLED MCLearnerShutdown(f)). ENABLED ignores the cfg's ACTION_CONSTRAINT steering, so an "enabled" exit may
be forbidden by the steering in steered cfgs. U2a encodes only the crash-based TRUNC decision (old leader's
never-committed record on disk), not the following memory-only exit. U1r uses the stale syncMode=SNAP
(only an exit before NEWLEADER leaves it, base.tla:309-310) as the trace of an earlier SNAP exit.
Property intents of DurableHistoryConsistent / LeaderCompleteness / revised SyncEntryJustified,
MonotoneUnlessRecovery name no specific situation beyond U1-U3; ReportedHistoryDurable's intent is U1/U2
(Update.tla:125). Not separate items.
SANY scratch copy /mydata/bingzhuo/evidence-work/census/v0/case-010/sany (only .tla copies, no states) could
not be deleted: rm was denied by the permission system.
