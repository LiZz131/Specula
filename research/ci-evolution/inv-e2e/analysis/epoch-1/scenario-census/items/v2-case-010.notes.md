# v2 / case-010 census notes

- Cfgs probed (all run by the agent on module Update, see spec/r2-batchA.txt, r2-batchB.txt, and
  spec/output/mc/update-focused-txn1.log): Update-focused, Update-focused-txn1, Update-full,
  Update-snapfix-new, Update-leak-new, Update-e2e-trunc-new, Update-e2e-snap-new, Update-open.
- Skipped: old-code controls (*-old.cfg, CodeVersion="old"); Update-full-txn2.cfg (no log, not run by
  the agent); Update-discharge.cfg (same behaviour sections as Update-full.cfg, checks only DischargeContext);
  MC*.cfg (MC-full/MC-wide have the same behaviour sections as Update-full/Update-full-txn2 but without
  the update properties; MC.cfg uses MCCoreNext with no exits); canary/hunt cfgs; Trace*.cfg; base*.cfg.
- Agent canaries (Update-canary-*.cfg) differ from the property cfgs in TrackCoverage (TRUE vs FALSE),
  SYMMETRY and mostly MaxTxn, so they were not counted for the property cfgs.
  UpdRejoinUnreachable also reads `seen`, which never changes when TrackCoverage=FALSE.
- Positive control SC_PC (a learner exit) was reached in all 8 cfgs.
- Census = TLC simulation, depth 100, 120 s seed 1 + 240 s seed 2, 1 worker. Throughput was low
  (Update-leak-new: ~1,000 traces in 360 s). The deep U2/U3 states (agent BFS depth 35-38) were never
  hit by random simulation. For U2, U3a and U3b the "covered" class rests on the agent's own BFS
  counterexamples in property cfgs (update-focused-txn1.log:54, update-full.log:78,
  update-focused-new.log:54, update-leak-new.log:53), which I read and checked against the item wording.
- U3c (leaked flush after the new session's processor appended later records): no agent witness and not
  hit by the census. Structural in the MaxTxn=1 cfgs; "not seen in budget" elsewhere. Simulation also
  missed the precursor U3a, so this is weak evidence: the state is not shown to be unreachable.
- Probes weaker than the wording (inferred, not measured): U1b (any DIFF session after any exit; the
  SNAP-abort-then-DIFF order is not kept in state), P3 (TRUNC mode packet seen; does not check that the cut
  removed anything).
- Not itemised: CR-U3 thread-leak observation (`syncAlive`), a real-code observation, not MC-checkable;
  the V0 Scenarios 1-4 (inherited, not update items).
