# v1/case-002 census notes

- Items: 2 update scenarios (S5, S6) split into U5a/U5b/U5c and U6a/U6b/U6c; Q5/Q6 merged into them;
  property intents for the two new update properties and four modified reference properties; one check statement (C_ActOld).
  ElectionSafety/CommittedHistoriesPrefix/HistoryPositionsMonotonicExceptRecovery are 'keep' with no situation named: skipped.
  V0 Scenarios 1-4 and Q1-Q4 (V0 brief) not inventoried (not tied to the update).
- cfgs examined: Update-full, Update-full-focusinit, Update-concrete, Update-open, Update-concrete-A2, Update-concrete2-A2,
  Update-concrete2-A2-crash (extends Update) for update items; MC.cfg, MC-hunt-sync/mutation/recovery/election (extends MC)
  for modified reference properties. Skipped: MC-canary-*, Update-reach-*, Update-discharge, Trace*, base.cfg.
- Canary cfgs (MC-canary-*) all differ from property cfgs (MaxEpoch/MaxCrash/MaxDepth/CONSTRAINT), so no canary was counted.
- Update-full.cfg (full MCNext from MCInit, the only update cfg not starting at a hand-built focused state) reached NOTHING
  in 360 s of simulation, including the positive control SC_CTRL (an active leader). The agent's own BFS of it (Z2a, depth 35)
  and simulation (Z2b) found no violation, and the agent wrote 'bug paths are deeper than the explored frontier'.
  All update items are classed covered via the focused cfgs (FocusInit/FocusInit2), whose reachability from MCInit the
  agent witnessed with Update-reach-focusinit-exact.cfg (canary cfg, MaxEpoch=1, not a property cfg).
- SC_CTRL also not seen in MC.cfg, MC-hunt-sync, MC-hunt-recovery: random simulation rarely completes a Zab election
  here, so 'not seen in budget' is weak evidence for P_SCJ and P_PP.
- U5b, P_CPoQ, P_LC, C_ActOld are reached by census only at the initial state of Update-concrete2-A2(-crash) (FocusInit2);
  in the other focused cfgs they are evidenced by the agent's own BFS counterexamples (Z3/Z4a/Z5), not by census.
- U6b/U6c probes are broader than the INITIAL-only history (cannot be expressed as a state predicate without a ghost).
- Census runner: no errors. Runs: 120 s seed 1 + 240 s seed 2 (where needed), depth 100.
