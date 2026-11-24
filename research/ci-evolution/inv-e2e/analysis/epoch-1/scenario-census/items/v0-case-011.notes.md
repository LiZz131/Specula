# v0 / case-011 census notes (OpenRaft Pre-Vote update)

Cfgs probed (all on module Update, as the agent ran them per `spec/output/campaign-table.md`): Update-full,
Update-full-rest, Update-full-prevote, Update-full-U2U4, Update-focused, Update-focused-rest,
Update-focused-U2U4, Update-open, Update-open-rest, Update-open-U2U4, MC_hunt_prevote_leader,
MC_hunt_prevote_leader_tickonly, MC_hunt_prevote_membership, MC_hunt_prevote_membership_U2,
MC_hunt_prevote_crash. 11 probes each (SC_PC positive control + 10 items), 120 s seed 1, 240 s seed 2 retry.
Skipped: MC.cfg, MC-membership.cfg (no update property), base.cfg, Trace.cfg, Update-discharge*.cfg
(DischargeMembership only), Update-canary-*.cfg and MC_hunt_prevote_inherited_round.cfg (canary-only),
fixcheck*/ (agent's fix-control models, not the update model).

Canary matching: the four Update-canary-{prevote-win,lease-reject,cancel-following,preround-leader}.cfg have
the same SPECIFICATION/CONSTANTS/CONSTRAINT/VIEW as Update-full-prevote.cfg (property cfg), so their hits count.
MC_hunt_prevote_inherited_round.cfg matches MC_hunt_prevote_leader.cfg. Update-canary-win-after-membership.cfg
differs from MC_hunt_prevote_membership.cfg (MaxCrashCount 1 vs 0), so it was not counted; U3 is covered by the
census and by the agent's own property violations anyway.

Result: every item reached in at least one cfg that enables its related property (10 covered, 0 Q-a).
Structural "no" cells: MaxMembershipCount=0 (Update-focused*, MC_hunt_prevote_leader*) blocks U3;
MaxCrashCount=0 blocks U5c and MaxDropCount=0 blocks U5d in MC_hunt_prevote_leader*.

Caveats / inference:
- Several probes use ENABLED of an MC action (win step, crash, drop, direct elect). In TickOnlySpec / FocusedSpec
  ENABLED does not check whether that action belongs to the cfg's NEXT; for U5b this may over-report in
  MC_hunt_prevote_leader_tickonly.cfg (only the tick is a real step there). Other cfgs reach U5b anyway.
- U4's log-reject and vote-order-reject guards are claimed trace-covered by the agent; not probed separately.
- U2's "Any old Action that changes the local vote while the round is alive must cancel it ... or keep the term"
  is split across U1 (establish_leader keeps the term) and U5a/U5b (cancel); no separate item.
- PreCandidateProbesNextSelfTerm intent (Update.tla:185-188) repeats U2/U5; not a separate item.
- Many property cfgs stop early in the agent's BFS (violations at depth 14-17), but the census ignores
  INVARIANT/PROPERTY sections, so reachability is measured independently of those stops.
