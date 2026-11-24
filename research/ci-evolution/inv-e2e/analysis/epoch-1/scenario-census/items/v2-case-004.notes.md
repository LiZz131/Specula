# v2 / case-004 census notes (Openraft RaftMsg::TransferLeader)

- Items: Update Scenarios U1-U4 of output/modeling-brief.md ("Update addendum"). U1 split into its four named
  consumers (elect, leader won, old leader steps down, commit by new leader) matching the agent's canaries;
  U2 split into learner campaigns (U2a), voter demoted to learner (U2b), learner becomes Leader (U2c);
  U4 split into crash before SaveVote (U4a) and crash after peers flushed grants (U4b). Property intents:
  ElectionByVoterOnly "removed nodes" half (the learner half = U2a) and NoRaftCorePanic. CR-1 = U2/MC-1,
  not duplicated.
- cfgs probed (10): Update_full, Update_focused, Update_open, Update_full_controls, Update_open_controls,
  Update_hunt_U1_voter_transfer, Update_hunt_U2_learner_transfer, Update_hunt_U2_learner_consequence,
  Update_hunt_U2_panic (on Update.tla, as in output/spec/run_tlc.sh usage), MC.cfg (kept controls, MC.tla).
  Skipped: Update_canary_*.cfg (canary-only), Update_discharge.cfg, base.cfg, Trace.cfg.
- Agent canaries counted: all Update_canary_*.cfg have exactly the CONSTANTS / SPECIFICATION MCSpec / VIEW of
  Update_full.cfg and Update_full_controls.cfg, so reached canaries count for those property cfgs.
  CanaryLearnerLeader was not witnessed (BFS budget-stopped at depth 29).
- Runner: 120 s + 240 s retry, depth 100, --jobs 3; no errors. Positive control (a Leader exists) reached.
- Q-a items, all structural:
  * U2b (voter demoted to learner): the MC has no action that turns a voter into a learner
    (MCAddLearner adds node 3 only; MCJoint/MCUniform, output/spec/MC.tla:162-190).
  * U2c (learner becomes Leader): FIFO self-grant repair + voter-only ReceiveVoteResponse make it impossible
    (MC.tla:144, base.tla:364); the agent itself switched to "expected NOT reachable" (Update.tla:148-149)
    after the code observation that the learner RaftCore panics first. The census still counts it as declared
    in U2's text.
  * P_EBVOr (removed node never elects): removal needs MCJoint then MCUniform, but MembershipLimit <= 1 in
    every cfg that enables ElectionByVoterOnly.
- U3 (stale/mismatching from) is trace-only by construction: MCTransferLeader always passes the target's own
  vote (MC.tla:93-97) and the mismatching branch is documented as a stutter validated by trace.
- Not seen in budget, but covered elsewhere: SC_U4a in FocusedSpec/OpenUpdateSpec cfgs, SC_U4b in
  Update_hunt_U1_voter_transfer.cfg. Update_hunt_U1_voter_transfer.cfg (InitialVoters {1,2,3},
  MembershipLimit 0) has no learners, so U2a/P_NRP are structurally absent there (it is not in their cfg lists).
- SC_U2b is encoded as "an initial voter that is now a learner"; SC_P_EBVOr as "an initial voter that is
  neither voter nor learner" (inferred from "removed nodes").
