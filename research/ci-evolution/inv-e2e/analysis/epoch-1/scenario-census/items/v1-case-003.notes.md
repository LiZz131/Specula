# v1/case-003 census notes

- Items: U1-U7 from the V1 Update Scenarios (output/modeling-brief.md:26-87); U1/U2/U4/U5/U6 split into a/b by the
  distinct situations named. V1-MC-1..4 (findings table) map onto U2/U7, U1, U4/U5, U6 and are not separate items.
  Property intents (VEReachedImmutable etc.) are tied 1:1 to scenarios in the brief and are covered by the scenario items.
  U5 trace-only items (ve_echo_disabled row 3, ve_negative row 2) skipped: trace items, row 2 dismissed by the agent.
- cfgs examined (all extend Update): Update_full, _full_safety, _focused, _focused_safety, _open, _open_safety,
  _deep_bfs, _sim_deep, _hunt_enable, _hunt_recovery (VE properties), _hunt_unchanged, _hunt_unchanged_from_disabled,
  _sim_unchanged (UnchangedVENotRejected). Skipped: MC_reach_*, Update_reach_* (canary-only), Update_discharge*, MC.cfg,
  MC_hunt_* (V0 scenarios, no update property), Trace*.
- Every agent canary cfg (MC_reach_*, Update_reach_*) has MaxCrashes/AppRollbacks/Others/VEHeights different from every
  property cfg, so no canary was counted; all items were measured by census probes.
- ReachedRow(r) from MC.tla is reused as the precondition for row items. U5b uses row 6 with U != P (change to a non-future
  height); U5a uses row 9 with U != P.
- The small state spaces (agent BFS exhaustive at 40k-160k states) make simulation coverage near-complete here.
- Census runner: no errors.
