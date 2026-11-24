# v1 / case-011 census notes

- Census cfgs (module Update, as the agent ran them: `tlc ... -config Update-full-U4.cfg Update`, see
  output/spec/output/v1-mc-update-full-U4.log header): Update-full, Update-full-noU4, Update-full-U4, Update-focus,
  Update-focus-noU4, Update-open, Update-open-noU4, Update-hunt-next-term, Update-hunt-stale-precandidate.
  120 s seed 1 + 240 s seed 2 (Update-open/-open-noU4 needed only seed 1). No runner errors; SC_CTRL reached everywhere.
- Skipped cfgs: Canary-*.cfg (canary-only), Update-discharge*.cfg (DischargeContext only), MC.cfg / MC-membership.cfg
  (base invariants only), base.cfg, Trace.cfg.
- Canary cfgs have the same CONSTANTS/SPECIFICATION/CONSTRAINT as Update-full*.cfg, so the agent's reached canaries
  count for those cfgs; census re-measured every item anyway.
- CanaryNoRejectedPreVoteResp / CanaryNoPreVoteCleared do not distinguish which guard rejected or which path cleared;
  census probes encode each guard / clearing path separately as the enabled pre-state (deliverable message plus the
  receiver condition). These are pre-states, i.e. the clearing/handling step is enabled, not observed.
- U2a (self-quorum shortcut) and U2b (remote grant counted without quorum) are reached ONLY in Update-open(-noU4).cfg,
  whose EnvUpdate lets any node evolve membership without leader guards (Update.tla:99-146, weaker than the reference).
  In the concrete cfgs: Update-focus* has no membership action (ConcreteFocusNext, Update.tla:151) and a 3-voter
  InitialConfig, so structurally unreachable; Update-hunt-* have MaxMembershipCount = 0; Update-full* not seen in 360 s.
  The agent itself recorded U2b as unreachable within budget and covered it by a trace (changelog.md:43-46,
  bug-report.md:160-164). Classified `covered` by the letter of the method; reader may treat as weak.
- Update-hunt-stale-precandidate.cfg: SC_U4a/b/c not seen in 480 s of depth-100 simulation, although the agent's BFS of
  the same cfg found the PreVoteNeverDemotesLeader violation at depth 17 (simulation miss, not structural).
  SC_U3a structural there (MaxElectionCount = 0), SC_U3f structural (MaxCrashCount = 0).
- Skipped items: the prior V0 brief scenarios 1-5 (modeling-brief.md:19-150) because they are not update scenarios;
  PreCandidateVoteIsNextTerm / PreVoteRequestPure intents name no situation beyond U-S1..U-S4.
- Result: 18 items, all covered; 6 dismissals.
