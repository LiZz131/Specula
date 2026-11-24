# v2 / case-003 census notes (CometBFT ValidateUpdate enable-height rewrite)

- Items: update Scenarios 1 (updated), 4 and 5 (new) of output/modeling-brief.md, split by situation
  (S1a accepted Abci update, S1b rejection; S4a accepted change after stored heights, S4b rejection of a
  table-checked Abci update; S5a mock replay, S5b real replay, S5c rejected-again on restart), plus the
  intents of the six UpdateProps.tla properties (UnchangedVEUpdateNotRejected split into its two stated
  clauses before-reached / after-reached). Scenarios 2/3 are V0 (unchanged) and were not inventoried.
  Findings U-MC-1..3 map onto P_VHS/P_VEM/P_SLCC, P_PVNR and P_UVNRb and were not duplicated.
- cfgs probed (14): all Update_* cfgs that enable VE* properties (incl. *_core variants and Update_sim_deep*)
  on Update.tla, and MC.cfg / MC_hunt_scenario1_params.cfg (RejectedUpdateDoesNotInstall /
  ParameterUpdateReflected, for S1) on MC.tla, as in the agent's logs (output/spec/output/final/mc/*.log
  headers). Skipped: MC_reach_* canary cfgs, MC_hunt_scenario2/3 (V0 durability/recovery), Trace*, base.cfg,
  Update_discharge*.
- Agent canaries (MC_reach_*.cfg, all reached per output/spec/output/reachability-summary.log) run with
  MaxHeight 1-3, Rest {"r0","rBad"}, VEProposals {0..3}, InitialVEs {0,2}; no property cfg has the same
  CONSTANTS, so none counts; every item was measured by a census probe.
- Runner: 120 s seed 1, retry 240 s seed 2 (only 3 cfgs needed it), depth 100, --jobs 3. No errors.
  Every probe was reached in every listed cfg except SC_S5a in Update_hunt_scenario4_ve_lifecycle(_core).cfg and
  MC_hunt_scenario1_params.cfg, where MaxCrashes = 0 (cfg line 7) makes a mock replay impossible (structural;
  those cfgs are not in S5a's census_cfgs anyway).
- First run was aborted after 3 cfgs and restarted: SC_P_AVR originally required Abci presence, which the
  updated table always rejects at a reached height (rows 4/6/8), so it encoded the violation rather than the
  precondition. Final SC_P_AVR = accepted non-nil update at a block whose enable height is already reached.
- Caveat (not a census result): in the agent's own BFS, Update_full / Update_focused / Update_open /
  Update_hunt_scenario4/5 stopped at the first UnchangedVEUpdateNotRejected violation after a few thousand
  states (output/spec/output/final/mc-summary.log); the other VE properties were exhausted in the *_core
  variants (same CONSTANTS without UnchangedVEUpdateNotRejected), so each item is reached in a cfg whose
  checks actually ran to completion.
- SC_S5b does not require a crash (real replay can follow AbortRejectedApply and restart); SC_S5c uses the
  arm's coverage history ("rejectedAbort") plus replayMutatesState.
- Inferred encodings: CP_E (pre-update enable height = activeParam in phase rejected, persistedParam in phase
  updated) follows base.tla UpdateStateAccepted/Rejected framing.
