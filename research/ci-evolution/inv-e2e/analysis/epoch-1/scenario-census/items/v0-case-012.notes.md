# v0 / case-012 census notes (OpenRaft VecProgress leader-commit update)

Cfgs probed (module as the agent ran them, `spec/validation-summary.md` campaign table): Update.tla —
Update_full, Update_full_residual, Update_focused, Update_focused_residual, Update_open, Update_open_residual,
Update_hunt_u1_membership_progress, Update_hunt_u1_consequence, Update_hunt_u2_membership_client_loss(_residual),
Update_hunt_u4_reelection_crash(_residual); MC.tla — MC_hunt_s1_progress, MC_hunt_s2_membership (they enable
CommitWitnessSound, which the agent re-enabled for U1/U3). 12 probes each incl. SC_PC (reached everywhere).
*_residual cfgs have the same behaviour sections as their non-residual twins (only invariants differ) and give
the same reachability. Skipped: MC.cfg, MC_scale.cfg, MC_hunt_s3/s4 (no update or CommitWitnessSound check),
MC_reach_*, Update_reach_* (canary-only), Update_discharge.cfg, base.cfg, Trace*.cfg.

Canary matching: Update_reach_{ProgressCommit, UpgradedWithFollowerProgress, LeaderNotFirst, JointQuorumCommit}
have the same INIT/NEXT/CONSTANTS/CONSTRAINT/VIEW as Update_hunt_u1_membership_progress.cfg and
Update_hunt_u1_consequence.cfg, so their hits count. Update_reach_ReelectedLeaderProgress.cfg has no twin.

Result: 11 items, all covered (every probe reached in Update_full/_focused/_open and the u4 hunt).
Structural "no" cells: U4a-U4d in Update_hunt_u1*/u2* and MC_hunt_s1/s2 (MaxTerm=1, MaxElectionActions=1,
MaxCrashes=0: no re-election, no second candidate, no crash); U3/U3b/X13 in MC_hunt_s1_progress.cfg
(MaxMembershipChanges=0).

Caveats / inference:
- Items X13 and U3b come from the analysis-report's "Update Scenarios" / "Analytic expectation" text
  (analysis-report.md:133-146), not from the brief's U-list; U4d from analysis-report.md:136-137.
- U2's "LeaderState resets matched values" is folded into U4a (re-elected leader progress), not separate.
- Probes using ENABLED (U2a, U2b, U4b, U4c, U4d) do not check whether the action is part of the cfg's NEXT;
  e.g. RejectAppendConflict is not in FocusedNext (Update.tla:44). Update_full (MCNext) reaches all of them.
- Many of these property cfgs stop early in the agent's BFS (MC-1 violation at depth 8-12); the census
  ignores INVARIANT sections, so reachability here is independent of where the agent's runs stopped.
