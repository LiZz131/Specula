# v1 / case-012 census notes

- Census cfgs: Update_full, Update_focused, Update_open, Update_full_faults, Update_hunt_u1_deep, Update_hunt_u2_uniform,
  Update_hunt_u3_follower, Update_hunt_u4_election (module Update) and MC5_u1_divergence (module MC5; CensusProbes
  therefore EXTENDS base, the common module). 120 s seed 1 + 240 s seed 2 each. SC_CTRL reached everywhere.
- Skipped as behaviour-duplicates of a census cfg (identical CONSTANTS/INIT/NEXT/CONSTRAINT, fewer invariants):
  Update_full_cws/pcs/sorted/control (= Update_full), Update_focused_cws/control (= Update_focused),
  Update_open_control (= Update_open), Update_full_faults_control (= Update_full_faults). Also skipped: Update_reach_*
  and MC_reach_* (canary-only), Update_discharge, MC.cfg/MC_scale/MC_hunt_s* (base-only invariants), Trace*, base.cfg.
- Agent canaries (Update_reach_*.cfg) run MCNext with MaxLosses = 0; no property cfg has the same behaviour sections
  (Update_full has MaxLosses = 1; focused/open use other NEXT), so they were not credited; every item was re-measured.
- Runner issue: `--only` merge is broken (run_census.py:134 loads the whole result.json as the per-cfg state; crash at
  line 153 'string indices must be integers'). I added SC_U3c after the first full run and re-ran Update_full and
  Update_hunt_u3_follower with --only; the TLC runs finished (logs/ overwritten for those two cfgs) and I merged their
  entries into result.json by hand from the runner stdout (marked with a "note" field). SC_U3c was not run on the
  other 7 cfgs.
- U3b: the item is encoded with SC_U3c (no-advance append to a follower holding an uncommitted membership entry),
  reached. My stricter reading SC_U3b (follower commit already >= its uncommitted effective membership index, the
  exact state where old 'promote whenever committed >= effective' and new 'promote only on advance' differ) was not
  seen in any of the 9 cfgs (about 380 s each); no structural guard found, so "not seen in budget". This suggests
  the update's promotion change may be unobservable in these bounds; inferred, not proven.
- Structural non-reach: membership items (U1*, U3a) in Update_hunt_u2_uniform / Update_hunt_u4_election
  (MaxMembershipChanges = 0); U2 in Update_hunt_u4_election (MaxClientAppends = 0, MaxIndex = 0).
- Skipped items: prior V0 brief scenarios 1-4 (modeling-brief.md:14-73); property intents of ProgressWithinAcks /
  ProgressCommittedGreatest name no situation beyond U1/U2.
- Result: 9 items, all covered; 5 dismissals.
