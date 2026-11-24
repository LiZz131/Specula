# v2 / case-011 census notes

- Cfgs probed (all run by the agent on module Update; spec/output/mc-*.log "Parsing file .../Update.tla"):
  Update.cfg (agent log name mc-Update-full.log), Update-full-U2, Update-residual, Update-focused-residual,
  Update-open-residual, MC_hunt_U2_prevote_leader, MC_hunt_U4_prevote_stale_round, MC_hunt_U4b_prevote_panic,
  MC_hunt_U4c_prevote_panic_operator, MC_hunt_U5_prevote_fallback.
- Skipped: Update-focused.cfg and Update-open.cfg (no agent log; the agent re-ran them as *-residual);
  Update-discharge.cfg (only DischargeContext); MC.cfg and MC-membership.cfg (prior invariants only, no update
  property); canary-*.cfg (different constants, e.g. MaxElectionCount=0 / MaxPreVoteCount=1); Trace.cfg; base.cfg.
- Several canaries are defined in UpdateProps.tla:152-166 (CanaryNoPreCandidate, CanaryNoLeaderWithTimerPreCandidate,
  CanaryNoStaleCorrelatedPreVoteResp, ...), but no cfg uses them. The agent's ad-hoc canary cfgs (canary-U2*,
  canary-diag, canary-U4c via DebugU4.tla) were run with constants that differ from the property cfgs, so
  they were not counted.
- Positive control SC_PC (a Pre-Vote round started) was reached in all 10 cfgs.
- Census = TLC simulation, depth 100, 120 s + 240 s retry, 1 worker. About 3,500-15,000 traces per cfg.
- U4b (stale non-member grant): the census did not hit it in any cfg. Coverage rests on the agent's BFS
  counterexample in MC_hunt_U4c (mc-hunt-U4c-panic-operator-bfs.log:300, operator rounds only). In
  MC_hunt_U4b (timer+operator), Update.cfg, Update-residual and Update-open-residual it was not seen by the
  agent (budget-limited BFS + simulation) nor by the census. It is structural in MC_hunt_U5 and
  Update-focused-residual (no membership change).
- Probes weaker than the wording (inferred): U5a (the cfg enables both timer branches and a timer round is
  active; which branch earlier ticks took is not kept), U6a (does not tell which cancellation path dropped
  the round), U6b (global crash counter, not tied to the round's node), U1b (any handler-produced Pre-Vote
  response).
- Not itemised: U.6 findings and the code-review note (folded into U2/U4); prior Scenarios 1-5 (inherited).
- No runner errors.
